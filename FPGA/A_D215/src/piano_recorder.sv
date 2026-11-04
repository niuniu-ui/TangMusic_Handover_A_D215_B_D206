// Hardware diagnostic: one bounded take, explicit erase before replacement.
// Audio never stalls for memory. Any overrun, underrun or memory fault is sticky.
module piano_recorder #(parameter integer MAX_SAMPLES=244144)(
 input wire clk,rst_n,sample_tick,input wire [15:0] sample_pcm,
 input wire start_record,stop_record,erase_record,start_play,stop_play,
 input wire download_request,input wire [31:0] download_offset,
 output reg download_done,output reg [255:0] download_data,output reg [5:0] download_bytes,
 output reg [3:0] state,output reg [7:0] fault,
 output reg [31:0] sample_count,output wire [31:0] pcm_crc,
 output reg [31:0] committed_samples,
 output reg [15:0] peak,output reg [31:0] take_id,
 output wire playback_active,output wire [15:0] playback_pcm,
 output reg mem_request,mem_write,output reg [28:0] mem_address,
 output reg [255:0] mem_write_data,
 input wire mem_ready,mem_done,mem_error,input wire [255:0] mem_read_data
);
 localparam BOOT=0,BOOT_WAIT=1,IDLE=2,RECORD=3,FLUSH=4,READY=5,
            PLAY_LOAD=6,PLAY=7,ERROR=8,DOWNLOAD=9;
 localparam [255:0] PATTERN0={4{64'h0123456789abcdef}};
 localparam [255:0] PATTERN1={4{64'hfedcba9876543210}};
 reg [1:0] boot_step;
 reg [255:0] pack_data,next_data;
 reg [3:0] fill,play_index;
 reg [28:0] write_address,play_next_address;
 reg [31:0] crc,played,download_saved_offset;
 reg next_valid,read_pending;
 reg cancel_play;
 reg commit_pending;
 reg [31:0] commit_target;
 wire [15:0] magnitude=sample_pcm[15] ? (~sample_pcm+16'd1) : sample_pcm;
 assign pcm_crc=(state==READY || state==PLAY_LOAD || state==PLAY || state==DOWNLOAD) ? ~crc : 0;
 assign playback_active=state==PLAY || state==PLAY_LOAD;
 assign playback_pcm=state==PLAY ? pack_data[play_index*16 +:16] : 16'd0;
 function [31:0] crc_byte;
  input [31:0] c;input [7:0] d;integer i;reg [31:0] v;
  begin v=c^{24'd0,d};for(i=0;i<8;i=i+1)v=v[0] ? (v>>1)^32'hedb88320 : v>>1;crc_byte=v;end
 endfunction
 always @(posedge clk) begin
  if(!rst_n) begin
   state<=BOOT;boot_step<=0;fault<=0;sample_count<=0;peak<=0;take_id<=0;
   committed_samples<=0;commit_pending<=0;commit_target<=0;
   crc<=32'hffffffff;pack_data<=0;next_data<=0;fill<=0;write_address<=0;
   mem_request<=0;mem_write<=0;mem_address<=0;mem_write_data<=0;
   played<=0;play_index<=0;play_next_address<=0;next_valid<=0;read_pending<=0;cancel_play<=0;
   download_done<=0;download_data<=0;download_bytes<=0;download_saved_offset<=0;
  end else begin
   mem_request<=0;download_done<=0;
   if(mem_done && commit_pending)begin
    if(!mem_error)committed_samples<=commit_target;
    commit_pending<=0;
   end
   case(state)
    BOOT: if(mem_ready && !mem_request) begin
     mem_request<=1;mem_write<=!boot_step[1];mem_address<=boot_step[0]?29'd8:29'd0;
     mem_write_data<=boot_step[0]?PATTERN1:PATTERN0;state<=BOOT_WAIT;
    end
    BOOT_WAIT: if(mem_done) begin
     if(mem_error || (boot_step[1] && mem_read_data!=(boot_step[0]?PATTERN1:PATTERN0)))begin
      state<=ERROR;fault<=1;
     end else if(boot_step==3)state<=IDLE;
     else begin boot_step<=boot_step+1'b1;state<=BOOT;end
    end
    IDLE: if(start_record && mem_ready) begin
     state<=RECORD;sample_count<=0;crc<=32'hffffffff;peak<=0;take_id<=take_id+1'b1;
     committed_samples<=0;commit_pending<=0;
     fill<=0;pack_data<=0;write_address<=0;fault<=0;
    end
    RECORD: begin
     // STOP excludes a sample arriving on the same edge.
     if(stop_record)state<=FLUSH;
     else if(sample_tick) begin
      pack_data[fill*16 +:16]<=sample_pcm;sample_count<=sample_count+1'b1;
      crc<=crc_byte(crc_byte(crc,sample_pcm[7:0]),sample_pcm[15:8]);
      if(magnitude>peak)peak<=magnitude;
      if(fill==15) begin
       if(mem_ready && !mem_request) begin
        mem_request<=1;mem_write<=1;mem_address<=write_address;
        mem_write_data<={sample_pcm,pack_data[239:0]};write_address<=write_address+29'd8;
        commit_pending<=1;commit_target<=sample_count+1'b1;
        fill<=0;pack_data<=0;
       end else begin state<=ERROR;fault<=2;end
      end else fill<=fill+1'b1;
      if(sample_count==MAX_SAMPLES-1 && !(fill==15 && (!mem_ready || mem_request)))state<=FLUSH;
     end
    end
    FLUSH: if(mem_ready && !mem_request) begin
     if(fill!=0) begin
      mem_request<=1;mem_write<=1;mem_address<=write_address;mem_write_data<=pack_data;fill<=0;
      commit_pending<=1;commit_target<=sample_count;
     end else state<=READY; // Bridge acknowledges only after a matching readback.
    end
    READY: begin
     if(erase_record)begin state<=IDLE;sample_count<=0;committed_samples<=0;crc<=32'hffffffff;peak<=0;end
     else if(start_play && sample_count!=0 && mem_ready) begin
      mem_request<=1;mem_write<=0;mem_address<=0;state<=PLAY_LOAD;
      played<=0;play_index<=0;play_next_address<=8;next_valid<=0;read_pending<=0;
      cancel_play<=0;
     end else if(download_request && mem_ready) begin
      if(download_offset[4:0]==0 && download_offset<(sample_count<<1)) begin
       mem_request<=1;mem_write<=0;mem_address<=download_offset[30:2];state<=DOWNLOAD;
       download_saved_offset<=download_offset;
      end else begin download_bytes<=0;download_data<=0;download_done<=1;end
     end
    end
    PLAY_LOAD: begin
     if(stop_play)cancel_play<=1;
     if(mem_done)begin pack_data<=mem_read_data;state<=(stop_play||cancel_play)?READY:PLAY;end
    end
    PLAY: begin
     if(mem_done && read_pending)begin next_data<=mem_read_data;next_valid<=1;read_pending<=0;end
     // Read the following burst early; there is ~160 us before it is needed.
     if(!next_valid && !read_pending && mem_ready && !mem_request &&
        (play_next_address<<1)<sample_count) begin
      mem_request<=1;mem_write<=0;mem_address<=play_next_address;read_pending<=1;
     end
     if(sample_tick) begin
      played<=played+1'b1;
      if(played==sample_count-1)state<=READY;
      else if(play_index==15) begin
       if(next_valid)begin
        pack_data<=next_data;next_valid<=0;play_index<=0;play_next_address<=play_next_address+8;
       end else begin state<=ERROR;fault<=3;end
      end else play_index<=play_index+1'b1;
     end
     if(stop_play)state<=READY;
    end
    DOWNLOAD: if(mem_done) begin
     download_data<=mem_read_data;
     download_bytes<=((sample_count<<1)-download_saved_offset>=32)?6'd32:((sample_count<<1)-download_saved_offset);
     download_done<=1;state<=READY;
    end
    ERROR: begin end // Requires board reset: do not re-use a failed memory transaction.
    default: begin state<=ERROR;fault<=5;end
   endcase
   if(mem_error && state!=BOOT)begin state<=ERROR;fault<=4;download_done<=0;end
  end
 end
endmodule
