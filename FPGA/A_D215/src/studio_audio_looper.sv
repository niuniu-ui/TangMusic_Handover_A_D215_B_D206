// Four mono PCM tracks. DDR byte region 48..80 MiB, two 4 MiB banks/track.
// A write acknowledgement MUST mean read-back verification, as record_ddr_bridge provides.
// Only tiny tagged 32-byte caches live on chip. Input excludes this module's mix.
module studio_audio_looper #(
 parameter integer MAX_SAMPLES=1200000, MIN_SAMPLES=48832, CHECK_TIMING=1
)(
 input wire clk,rst_n,sample_tick,input wire signed [15:0] live_pcm,
 output reg signed [15:0] mix_pcm,output wire busy,
 input wire blocked,panic,
 input wire request,input wire [15:0] command,payload_length,input wire [559:0] payload,
 output reg done,output reg [15:0] result,output reg [6:0] reply_length,output reg [511:0] reply,
 output reg mem_request,mem_write,output reg [28:0] mem_address,output reg [255:0] mem_write_data,
 input wire mem_ready,mem_done,mem_error,input wire [255:0] mem_read_data
);
 reg running,preparing,recording,armed,finalizing,stop_end;
 reg [1:0] record_track;
 reg [3:0] valid,undo_valid,bank,mute,solo;
 reg [7:0] volume[0:3] /* synthesis syn_ramstyle="registers" */;
 reg [7:0] gain[0:3] /* synthesis syn_ramstyle="registers" */;
 reg [31:0] length_samples,position,revision,captured,verified,count_remaining;
 reg [15:0] bpm;reg [2:0] bars,count_in;reg [7:0] fault;
 // One 128 x 16 dual-port block RAM: four tracks x two blocks x 16 samples.
 // A single registered multiplier/accumulator services all four tracks.
 reg [15:0] cache[0:127] /* synthesis syn_ramstyle="block_ram" */;
 reg [31:0] tag[0:7] /* synthesis syn_ramstyle="registers" */;
 reg [7:0] cache_valid,cache_bank;
 reg [6:0] cache_read_address;reg signed [15:0] cache_sample;
 reg fill_active,fill_bank;reg [2:0] fill_slot;reg [3:0] fill_index;
 reg [255:0] fill_data;reg [31:0] fill_block,fill_epoch;
 reg [1:0] mix_phase,mix_track;reg [4:0] mix_offset;reg [3:0] mix_enabled;
 reg [7:0] mix_gain[0:3] /* synthesis syn_ramstyle="registers" */;
 reg signed [24:0] mix_product;reg signed [20:0] mix_sum;
 wire signed [20:0] mix_term=mix_product>>>7;
 wire signed [20:0] mix_next_sum=mix_sum+mix_term;
 // Do not overwrite a cache slot while a sample still reads its old block.
 wire cache_write_en=fill_active&&(mix_phase==0)&&!sample_tick;
 reg [255:0] capture_block,pending_data;reg pending_write;
 reg [31:0] pending_block;reg pending_bank;
 reg memory_active,memory_write,memory_bank;reg [2:0] memory_slot;
 reg [31:0] memory_block,memory_epoch,epoch;
 reg [2:0] scan_slot;
 // Two-stage prefetch candidate separates block selection from cache tag compare.
 reg scan_candidate_valid,scan_candidate_need,scan_candidate_bank;
 reg [1:0] scan_candidate_track,scan_candidate_record_track;
 reg [2:0] scan_candidate_slot;
 reg [31:0] scan_candidate_block,scan_candidate_current;
 reg scan_candidate_preparing,scan_candidate_recording;
 integer i,t,s;reg [31:0] wanted,block_count;reg desired_bank,need_read,all_ready;
 reg [7:0] target_gain;
 wire [31:0] current_block=position>>4;
 wire capture_overflow=running&&count_remaining==0&&recording&&position[3:0]==15&&pending_write;
 // length ~= 48828.125 * 60 * 4 * bars / BPM, rounded to 64 samples.
 // One bounded multiply validates the host calculation without a divider.
 wire [28:0] requested_time=payload[20:0]*payload[39:32];
 wire [28:0] nominal_time=payload[55:48]==4?29'd46875000:payload[55:48]==2?29'd23437500:29'd11718750;
 wire [12:0] rounding_tolerance={payload[39:32],5'b0};
 wire timing_valid=requested_time+rounding_tolerance>=nominal_time&&requested_time<=nominal_time+rounding_tolerance;
 assign busy=running||preparing||armed||recording||finalizing;
 function [31:0] u32(input integer n);begin u32=payload[n*8+:32];end endfunction
 function [28:0] address_of(input [1:0] track,input b,input [31:0] block_index);
  begin address_of=29'h0c00000+({27'b0,track}<<21)+(b?29'h0100000:0)+(block_index<<3);end
 endfunction
 function present(input integer track,input [31:0] block_index,input b);
  integer slot;begin slot=track*2+block_index[0];present=cache_valid[slot]&&cache_bank[slot]==b&&tag[slot]==block_index;end
 endfunction
 task fail(input [7:0] code);begin
  fault<=code;running<=0;preparing<=0;armed<=0;recording<=0;stop_end<=0;mix_pcm<=0;
  if(finalizing)begin bank[record_track]<=~bank[record_track];undo_valid[record_track]<=0;end
  finalizing<=0;pending_write<=0;cache_valid<=0;epoch<=epoch+1'b1;fill_active<=0;mix_phase<=0;
 end endtask
 task snapshot;integer k;begin
  reply=0;reply[7:0]=1;reply[15:8]={2'b0,preparing,finalizing,stop_end,armed,recording,running};
  reply[23:16]=fault;reply[31:24]=(armed||recording||finalizing)?{6'b0,record_track}:8'hff;
  reply[63:32]=length_samples;reply[95:64]=position;reply[127:96]=count_remaining;
  reply[135:128]={4'b0,valid};reply[143:136]={4'b0,mute};reply[151:144]={4'b0,solo};reply[159:152]={4'b0,undo_valid};
  for(k=0;k<4;k=k+1)reply[160+k*8+:8]=volume[k];
  reply[223:192]=revision;reply[255:224]=verified;reply[271:256]=bpm;
  reply[279:272]={5'b0,bars};reply[287:280]={5'b0,count_in};reply[319:288]=MAX_SAMPLES;
  reply_length=40;
 end endtask
 always @(posedge clk)begin
  cache_sample<=cache[cache_read_address];
  if(rst_n&&cache_write_en)cache[{fill_slot,fill_index}]<=fill_data[15:0];
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   running<=0;preparing<=0;recording<=0;armed<=0;finalizing<=0;stop_end<=0;record_track<=0;
   valid<=0;undo_valid<=0;bank<=0;mute<=0;solo<=0;length_samples<=195328;position<=0;revision<=0;
   captured<=0;verified<=0;count_remaining<=0;bpm<=120;bars<=2;count_in<=0;fault<=0;
   cache_valid<=0;cache_bank<=0;capture_block<=0;pending_data<=0;pending_write<=0;pending_block<=0;pending_bank<=0;
   cache_read_address<=0;fill_active<=0;fill_bank<=0;fill_slot<=0;fill_index<=0;fill_data<=0;fill_block<=0;fill_epoch<=0;
   mix_phase<=0;mix_track<=0;mix_offset<=0;mix_enabled<=0;mix_product<=0;mix_sum<=0;
   memory_active<=0;memory_write<=0;memory_bank<=0;memory_slot<=0;memory_block<=0;memory_epoch<=0;epoch<=0;scan_slot<=0;scan_candidate_valid<=0;scan_candidate_need<=0;scan_candidate_bank<=0;scan_candidate_track<=0;scan_candidate_record_track<=0;scan_candidate_slot<=0;scan_candidate_block<=0;scan_candidate_current<=0;scan_candidate_preparing<=0;scan_candidate_recording<=0;
   mem_request<=0;mem_write<=0;mem_address<=0;mem_write_data<=0;mix_pcm<=0;done<=0;result<=0;reply_length<=0;reply<=0;
   for(i=0;i<4;i=i+1)begin volume[i]<=100;gain[i]<=0;mix_gain[i]<=0;end
   for(i=0;i<8;i=i+1)tag[i]<=0;
  end else begin
   mem_request<=0;
   if(!request)done<=0;
   if(cache_write_en)begin
    fill_data<=fill_data>>16;fill_index<=fill_index+1'b1;
    if(fill_index==15)begin
     fill_active<=0;
     if(fill_epoch==epoch)begin tag[fill_slot]<=fill_block;cache_bank[fill_slot]<=fill_bank;cache_valid[fill_slot]<=1;end
    end
   end
   case(mix_phase)
    1:mix_phase<=2; // synchronous RAM read has now reached its output register
    2:begin
     mix_product<=mix_enabled[mix_track]?cache_sample*$signed({1'b0,mix_gain[mix_track]}):25'sd0;
     mix_phase<=3;
    end
    3:begin
     mix_sum<=mix_next_sum;
     if(mix_track==3)begin
      if(mix_next_sum>32767)mix_pcm<=32767;else if(mix_next_sum< -32768)mix_pcm<=-32768;else mix_pcm<=mix_next_sum[15:0];
      mix_phase<=0;
     end else begin mix_track<=mix_track+1'b1;cache_read_address<={mix_track+2'd1,mix_offset};mix_phase<=1;end
    end
    default:begin end
   endcase
   // One transaction at a time. Capture writes take priority over prefetch.
   if(memory_active&&mem_done)begin
    memory_active<=0;
    if(mem_error)fail(2);
    else if(memory_epoch==epoch)begin
     if(memory_write)begin
      verified<=verified+16;
      if(finalizing&&verified+16==length_samples)begin
       valid[record_track]<=1;finalizing<=0;revision<=revision+1'b1;
      end
     end else begin
      fill_data<=mem_read_data;fill_slot<=memory_slot;fill_block<=memory_block;fill_bank<=memory_bank;fill_epoch<=memory_epoch;
      fill_index<=0;fill_active<=1;cache_valid[memory_slot]<=0;
     end
    end
   end
   if(!busy)scan_candidate_valid<=0;
   if(!memory_active&&!mem_request&&mem_ready&&!fill_active)begin
    if(pending_write)begin
     scan_candidate_valid<=0;
     mem_request<=1;mem_write<=1;mem_address<=address_of(record_track,pending_bank,pending_block);mem_write_data<=pending_data;
     memory_active<=1;memory_write<=1;memory_epoch<=epoch;pending_write<=0;
    end else if(busy)begin
     if(scan_candidate_valid)begin
      scan_candidate_valid<=0;
      if(scan_candidate_preparing==preparing && scan_candidate_recording==recording &&
         scan_candidate_record_track==record_track && scan_candidate_current==current_block)begin
       if(scan_candidate_need&&!present(scan_candidate_track,scan_candidate_block,scan_candidate_bank))begin
        mem_request<=1;mem_write<=0;mem_address<=address_of(scan_candidate_track,scan_candidate_bank,scan_candidate_block);
        memory_active<=1;memory_write<=0;memory_slot<=scan_candidate_slot;memory_block<=scan_candidate_block;memory_bank<=scan_candidate_bank;memory_epoch<=epoch;
       end
       scan_slot<=scan_slot+1'b1;
      end
     end else if(!sample_tick&&!request&&!mem_done&&!panic&&!mem_error)begin
      t=scan_slot>>1;wanted=preparing?0:current_block;desired_bank=bank[t];need_read=valid[t]||(finalizing&&t==record_track);
      if(recording&&t==record_track)begin wanted=0;desired_bank=~bank[t];need_read=verified>=32;end
      if(scan_slot[0])begin wanted=wanted+1;if(wanted>=length_samples>>4)wanted=0;end
      s=t*2+wanted[0];
      scan_candidate_track<=t[1:0];scan_candidate_block<=wanted;scan_candidate_bank<=desired_bank;
      scan_candidate_need<=need_read;scan_candidate_slot<=s[2:0];
      scan_candidate_preparing<=preparing;scan_candidate_recording<=recording;scan_candidate_record_track<=record_track;scan_candidate_current<=current_block;
      scan_candidate_valid<=1;
     end
    end else scan_candidate_valid<=0;
   end
   if(preparing)begin
    all_ready=1;
    for(i=0;i<4;i=i+1)if(valid[i]&&!(armed&&record_track==i)&&(!present(i,0,bank[i])||!present(i,1,bank[i])))all_ready=0;
    if(all_ready&&mem_ready&&!memory_active&&!pending_write&&!fill_active)begin
     preparing<=0;running<=1;position<=0;
     if(armed&&count_remaining==0)begin recording<=1;armed<=0;captured<=0;verified<=0;capture_block<=0;end
    end
   end
   if(sample_tick)begin
    all_ready=1;
    for(i=0;i<4;i=i+1)begin
     target_gain=running&&count_remaining==0&&!mute[i]&&(!(solo!=0)||solo[i])&&!(recording&&record_track==i)?volume[i]:0;
     if(gain[i]<target_gain)gain[i]<=gain[i]+1'b1;else if(gain[i]>target_gain)gain[i]<=gain[i]-1'b1;
     mix_gain[i]<=gain[i];
     mix_enabled[i]<=running&&count_remaining==0&&(valid[i]||(finalizing&&record_track==i))&&!(recording&&record_track==i);
     if(running&&count_remaining==0&&(valid[i]||(finalizing&&record_track==i))&&!(recording&&record_track==i)&&!present(i,current_block,bank[i]))all_ready=0;
    end
    if(mix_phase!=0)fail(4);
    else if(!all_ready)fail(1);
    else if(capture_overflow)fail(3);
    else begin mix_phase<=1;mix_track<=0;mix_sum<=0;mix_offset<={current_block[0],position[3:0]};cache_read_address<={2'b0,current_block[0],position[3:0]};end
    // Fault cancellation must win even on the last sample of a recording.
    if(running&&mix_phase==0&&all_ready&&!capture_overflow)begin
     if(count_remaining!=0)begin
      count_remaining<=count_remaining-1'b1;
      if(count_remaining==1&&armed)begin recording<=1;armed<=0;captured<=0;verified<=0;capture_block<=0;end
     end else begin
      if(recording)begin
       capture_block[position[3:0]*16+:16]<=live_pcm;captured<=captured+1'b1;
       if(position[3:0]==15)begin
        pending_data<={live_pcm,capture_block[239:0]};pending_block<=current_block;pending_bank<=~bank[record_track];pending_write<=1;
       end
      end
      if(position+1==length_samples)begin
       position<=0;
       if(recording)begin
        recording<=0;finalizing<=1;undo_valid[record_track]<=valid[record_track];bank[record_track]<=~bank[record_track];
       end
       if(armed)begin recording<=1;armed<=0;captured<=0;verified<=0;capture_block<=0;end
       if(stop_end)begin running<=0;stop_end<=0;armed<=0;end
      end else position<=position+1'b1;
     end
    end
   end
   // Command execution is last; explicit stop wins over capture on this edge.
   if(request&&!done)begin
    result=0;reply_length=0;reply=0;done<=1;
    case(command)
     16'h0400:if(payload_length!=0)result=2;else snapshot();
     16'h0401:begin
      if(payload_length!=12)result=2;
      else if(u32(8)!=revision)result=18;
      else if(busy||memory_active||pending_write||fill_active||valid!=0)result=10;
      else if(u32(0)<MIN_SAMPLES||u32(0)>MAX_SAMPLES||payload[5:0]!=0||payload[47:32]<40||payload[47:32]>240||!(payload[55:48]==1||payload[55:48]==2||payload[55:48]==4)||!(payload[63:56]==0||payload[63:56]==4)||(CHECK_TIMING&&!timing_valid))result=2;
      else begin length_samples<=u32(0);bpm<=payload[47:32];bars<=payload[50:48];count_in<=payload[58:56];undo_valid<=0;revision<=revision+1'b1;end
     end
     16'h0402:begin
      if(payload_length!=1||payload[7:0]>3)result=2;
      else if(blocked||fault!=0||recording||armed||finalizing||preparing||pending_write||!mem_ready)result=10;
      else begin
       record_track<=payload[1:0];armed<=1;stop_end<=0;captured<=0;verified<=0;
       // Overwriting the inactive bank consumes the previous undo immediately.
       undo_valid[payload[1:0]]<=0;
       if(!running)begin preparing<=1;position<=0;cache_valid<=0;count_remaining<=count_in==0?0:(length_samples>>(bars==4?2:bars==2?1:0));end
      end
     end
     16'h0403:begin
      if(payload_length!=0)result=2;
      else if(blocked||busy||valid==0||fault!=0||!mem_ready)result=10;
      else begin preparing<=1;position<=0;cache_valid<=0;count_remaining<=0;stop_end<=0;end
     end
     16'h0404:begin
      if(payload_length!=1||payload[7:0]>1)result=2;
      else if(payload[7:0]==0&&running&&count_remaining==0)begin stop_end<=1;armed<=0;if(armed)recording<=0;end
      else begin
       running<=0;preparing<=0;recording<=0;armed<=0;stop_end<=0;pending_write<=0;mix_pcm<=0;mix_phase<=0;fill_active<=0;
       if(!mem_error&&mem_ready&&!memory_active)fault<=0;
       if(finalizing)begin bank[record_track]<=~bank[record_track];undo_valid[record_track]<=0;end
       finalizing<=0;epoch<=epoch+1'b1;cache_valid<=0;
      end
     end
     16'h0405:begin
      if(payload_length!=8||payload[39:32]>3||payload[47:40]>1||payload[55:48]>1||payload[63:56]>128)result=2;
      else if(u32(0)!=revision)result=18;
      else begin mute[payload[33:32]]<=payload[40];solo[payload[33:32]]<=payload[48];volume[payload[33:32]]<=payload[63:56];revision<=revision+1'b1;end
     end
     16'h0406:begin
      if(payload_length!=1||(payload[7:0]>3&&payload[7:0]!=255))result=2;
      else if(busy||memory_active||pending_write||fill_active)result=10;
      else begin
       if(payload[7:0]==255)begin valid<=0;undo_valid<=0;end
       else begin valid[payload[1:0]]<=0;undo_valid[payload[1:0]]<=0;end
       cache_valid<=0;revision<=revision+1'b1;
      end
     end
     16'h0407:begin
      if(payload_length!=1||payload[7:0]>3)result=2;
      else if(busy||memory_active||pending_write||fill_active||!undo_valid[payload[1:0]])result=10;
      else begin bank[payload[1:0]]<=~bank[payload[1:0]];cache_valid<=0;revision<=revision+1'b1;end
     end
     default:result=7;
    endcase
   end
   if(panic)fail(0);
   if(mem_error)fail(2);
  end
 end
endmodule
