// Two disjoint 16 MiB slots. The verified core uses 32-bit-word addresses.
// Recording survives link loss; only the transfer lease is released.
module studio_recorder #(parameter integer MAX_SAMPLES=5859375,
 parameter integer CLK_HZ=50000000)(
 input wire clk,rst_n,sample_tick,input wire [15:0] sample_pcm,
 input wire disconnect,transport_busy,
 input wire select_valid,select_slot,
 input wire start_record,stop_record,erase_record,start_play,stop_play,
 input wire lease_open,lease_close,save_ack,progress_ack,
 input wire [31:0] ack_value,
 input wire download_request,input wire [31:0] download_offset,
 output wire download_done,output wire [255:0] download_data,output wire [5:0] download_bytes,
 output reg selected,output reg lease,output wire saved_on_phone,
 output wire [31:0] confirmed_bytes,
 output wire [3:0] state,other_state,output wire [7:0] fault,
 output wire [31:0] sample_count,committed_samples,pcm_crc,take_id,other_samples,other_take,
 output wire [15:0] peak,output wire ready_for_command,output wire busy,erase_accepted,
 output wire playback_active,output wire [15:0] playback_pcm,
 output wire mem_request,mem_write,output wire [28:0] mem_address,
 output wire [255:0] mem_write_data,input wire mem_ready,mem_done,mem_error,
 input wire [255:0] mem_read_data
);
 wire [3:0] states[0:1];wire [7:0] faults[0:1];
 wire [31:0] counts[0:1],committed[0:1],crcs[0:1],ids[0:1];
 wire [15:0] peaks[0:1],pcm[0:1];
 wire [1:0] req,wr,done,playing,core_ready;
 wire [28:0] addresses[0:1];wire [255:0] writes[0:1],downloads[0:1];
 wire [5:0] sizes[0:1];
 reg owner,inflight,grant;
 reg [1:0] saved;
 reg [31:0] confirmed[0:1];
 reg [$clog2(CLK_HZ+1)-1:0] second_counter;
 reg [5:0] lease_seconds;
 wire initialized=states[0]>=2 && states[1]>=2;
 assign state=states[selected];assign other_state=states[!selected];
 assign fault=faults[selected];assign sample_count=counts[selected];
 assign committed_samples=committed[selected];assign pcm_crc=crcs[selected];
 // Slot is part of the identity. Old PRB clients remain 32-bit compatible.
 assign take_id={ids[selected][30:0],selected};
 assign other_take={ids[!selected][30:0],!selected};assign other_samples=counts[!selected];
 assign peak=peaks[selected];assign saved_on_phone=saved[selected];
 assign confirmed_bytes=confirmed[selected];
 assign busy=state!=2 && state!=5;
 assign ready_for_command=initialized && mem_ready && !inflight && !(|req) && !mem_error && grant==selected;
 assign erase_accepted=erase_record&&ready_for_command&&!select_valid&&!lease_open&&!lease&&!transport_busy&&state==5;
 assign playback_active=|playing;assign playback_pcm=playing[0]?pcm[0]:pcm[1];
 assign download_done=done[selected];assign download_data=downloads[selected];assign download_bytes=sizes[selected];
 assign mem_request=|req;
 assign mem_write=req[1]?wr[1]:wr[0];
 assign mem_address=(req[1]?addresses[1]:addresses[0])+(req[1]?29'h0400000:29'd0);
 assign mem_write_data=req[1]?writes[1]:writes[0];
 wire ack_in_range,ack_not_backwards;
 studio_u32_ge ack_upper(.a(sample_count<<1),.b(ack_value),.ge(ack_in_range));
 studio_u32_ge ack_lower(.a(ack_value),.b(confirmed[selected]),.ge(ack_not_backwards));
 assign core_ready[0]=mem_ready&&!inflight&&!(|req)&&!grant;
 assign core_ready[1]=mem_ready&&!inflight&&!(|req)&&grant;
 always @(posedge clk)begin
  if(!rst_n)begin
   selected<=0;lease<=0;saved<=0;confirmed[0]<=0;confirmed[1]<=0;
   owner<=0;inflight<=0;grant<=0;second_counter<=0;lease_seconds<=0;
  end else begin
   if(|req)begin owner<=req[1];inflight<=1;end
   if(mem_done)inflight<=0;
   if(!inflight&&!(|req))begin
    if(initialized)grant<=selected;
    else if(states[0]>=2)grant<=1;
    else if(states[1]>=2)grant<=0;
    else grant<=!grant;
   end
   if(select_valid&&!lease&&!transport_busy&&!busy&&ready_for_command)selected<=select_slot;
   if(start_record&&!lease&&!transport_busy&&state==2&&ready_for_command)begin saved[selected]<=0;confirmed[selected]<=0;end
   if(erase_record&&!lease&&!transport_busy&&state==5&&ready_for_command)begin saved[selected]<=0;confirmed[selected]<=0;end
   if(lease_open&&state==5&&ready_for_command)begin lease<=1;lease_seconds<=0;second_counter<=0;if(!lease)confirmed[selected]<=0;end
   if(lease)begin
    if(download_request||progress_ack||transport_busy)begin lease_seconds<=0;second_counter<=0;end
    else if(second_counter==CLK_HZ-1)begin
     second_counter<=0;if(lease_seconds==29)lease<=0;else lease_seconds<=lease_seconds+1'b1;
    end else second_counter<=second_counter+1'b1;
   end
   if(progress_ack&&lease&&ack_in_range&&ack_not_backwards)confirmed[selected]<=ack_value;
   if(save_ack&&lease&&ack_value==pcm_crc)begin saved[selected]<=1;confirmed[selected]<=sample_count*2;end
   if(disconnect||lease_close||mem_error)lease<=0;
  end
 end
 genvar k;
 generate for(k=0;k<2;k=k+1)begin:slot
  wire chosen=selected==k;
  // Require the arbiter to point at this core before accepting a command.
  wire command_ok=chosen&&ready_for_command&&grant==k&&!select_valid&&!lease_open;
  piano_recorder #(.MAX_SAMPLES(MAX_SAMPLES)) core(
   .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.sample_pcm(sample_pcm),
   .start_record(start_record&&command_ok&&!lease&&!transport_busy),
   .stop_record(stop_record&&chosen),
   .erase_record(erase_record&&command_ok&&!lease&&!transport_busy),
   .start_play(start_play&&command_ok&&!lease&&!transport_busy),.stop_play(stop_play&&chosen),
   .download_request(download_request&&chosen&&lease),.download_offset(download_offset),
   .download_done(done[k]),.download_data(downloads[k]),.download_bytes(sizes[k]),
   .state(states[k]),.fault(faults[k]),.sample_count(counts[k]),.committed_samples(committed[k]),
   .pcm_crc(crcs[k]),.peak(peaks[k]),.take_id(ids[k]),.playback_active(playing[k]),.playback_pcm(pcm[k]),
   .mem_request(req[k]),.mem_write(wr[k]),.mem_address(addresses[k]),.mem_write_data(writes[k]),
   .mem_ready(core_ready[k]),.mem_done(mem_done&&owner==k),.mem_error(mem_error),.mem_read_data(mem_read_data));
 end endgenerate
endmodule
