// A held TX mailbox and a two-bank RX RAM cross clock domains. RX publishes
// only complete, peer-addressed frames with valid length/header/FCS. The host
// acknowledges after draining all bytes; a published bank is never overwritten.
module studio_net_frames #(parameter integer ROLE=0, PERIOD=5000)(
 input wire host_clk,host_rst_n,tx_clk,tx_rst_n,rx_clk,rx_rst_n,enable,
 input wire [2047:0] payload,input wire urgent,
 output reg [7:0] tx_data,output reg tx_valid,
 input wire [7:0] rx_data,input wire rx_valid,rx_error,
 output reg [7:0] host_byte,host_index,output reg host_valid,host_done,
 output reg [31:0] good_frames,bad_frames,dropped_frames
);
 `include "src/studio_net_protocol.vh"
 // Keep the held-word semantics, but allow constant payload padding to fold
 // away: B sends only 274 meaningful touch bits, A sends 1824 display bits.
 reg [2047:0] tx_mailbox=0;
 reg tx_request=0,tx_ack=0;
 (* syn_preserve=1 *) reg [1:0] tx_ack_sync=0,tx_req_sync=0;
 reg [15:0] period_count=0;reg urgent_pending=0;
 reg [9:0] minimum_gap=0;reg loading=0;reg [7:0] load_index=0;
 reg [7:0] tx_memory[0:255] /* synthesis syn_ramstyle="block_ram" */;
 always @(posedge host_clk)if(loading)tx_memory[load_index]<=tx_mailbox[load_index*8+:8];
 always @(posedge host_clk)begin
  tx_ack_sync<={tx_ack_sync[0],tx_ack};
  if(!host_rst_n)begin tx_request<=0;tx_mailbox<=0;tx_ack_sync<=0;period_count<=0;urgent_pending<=0;minimum_gap<=0;loading<=0;load_index<=0;end
  else begin
   if(period_count!=0)period_count<=period_count-1'b1;
   if(minimum_gap!=0)minimum_gap<=minimum_gap-1'b1;
   if(urgent)urgent_pending<=1;
   if(loading)begin
    if(load_index==255)begin loading<=0;tx_request<=!tx_request;end
    else load_index<=load_index+1'b1;
   end else if(tx_ack_sync[1]==tx_request&&minimum_gap==0&&(period_count==0||urgent_pending))begin
    tx_mailbox<=payload;loading<=1;load_index<=0;period_count<=PERIOD-1;urgent_pending<=0;minimum_gap<=999;
   end
  end
 end
 reg sending=0;reg [8:0] tx_index=0;reg [31:0] tx_crc=32'hffffffff,tx_sequence=0;reg [4:0] gap=0;
 // Sequence increments occur only after a complete 298-byte frame. Registered
 // byte carries have hundreds of clocks to settle before the next increment;
 // keep the 32-bit bookkeeping adder off the 125 MHz critical path.
 reg carry8=0,carry16=0,carry24=0;
 always @(posedge tx_clk)begin
  if(!tx_rst_n)begin carry8<=0;carry16<=0;carry24<=0;end
  else begin carry8<=&tx_sequence[7:0];carry16<=&tx_sequence[15:0];carry24<=&tx_sequence[23:0];end
 end
 wire [8:0] offset=tx_index-9'd8;
 wire [8:0] prefetch_address=tx_index-9'd37;
 reg [7:0] memory_tx_byte,header_tx_byte;
 // A synchronous RAM read and predecoded header break the payload mux ->
 // CRC path. Clock 37 prefetches payload byte 0 for transmission at clock 38.
 always @(posedge tx_clk)begin
  memory_tx_byte<=tx_memory[prefetch_address[7:0]];
  header_tx_byte<=ui_header(ROLE[0],tx_sequence,tx_index-9'd7);
 end
 reg [7:0] current_byte;
 always @*begin
  if(tx_index<7)current_byte=8'h55;
  else if(tx_index==7)current_byte=8'hd5;
  else if(offset<30)current_byte=header_tx_byte;
  else if(offset<UI_BODY_BYTES)current_byte=memory_tx_byte;
  else current_byte=0; // FCS is selected after the byte pipeline register.
 end
 reg [7:0] pipe_byte=0;reg pipe_valid=0,pipe_body=0,pipe_fcs=0,pipe_last=0;
 reg [1:0] pipe_fcs_index=0;
 wire [8:0] fcs_offset=offset-9'd286;
 always @(posedge tx_clk)begin
  tx_req_sync<={tx_req_sync[0],tx_request};
  // Register the byte and its classification before CRC accumulation. Index
  // decoding and header/payload selection no longer share the CRC data path.
  pipe_byte<=current_byte;pipe_valid<=sending;
  pipe_body<=tx_index>=8&&offset<UI_BODY_BYTES;
  pipe_fcs<=tx_index>=8&&offset>=UI_BODY_BYTES;
  pipe_fcs_index<=fcs_offset[1:0];pipe_last<=tx_index==UI_FRAME_BYTES+7;
  tx_valid<=pipe_valid;
  if(pipe_valid)begin
   if(pipe_fcs)case(pipe_fcs_index)
    0:tx_data<=~tx_crc[7:0];1:tx_data<=~tx_crc[15:8];
    2:tx_data<=~tx_crc[23:16];3:tx_data<=~tx_crc[31:24];
   endcase
   else tx_data<=pipe_byte;
   if(pipe_body)tx_crc<=ui_crc(tx_crc,pipe_byte);
  end
  if(!tx_rst_n)begin
   tx_req_sync<=0;tx_ack<=0;tx_data<=0;tx_valid<=0;sending<=0;tx_index<=0;tx_crc<=32'hffffffff;tx_sequence<=0;gap<=0;
   pipe_valid<=0;pipe_byte<=0;pipe_body<=0;pipe_fcs<=0;pipe_last<=0;pipe_fcs_index<=0;
  end
  // Cancel pending packets while the physical link is down. The host can
  // keep replacing its latest snapshot instead of replaying an old held key
  // after a long cable disconnection.
  else if(!enable)begin sending<=0;pipe_valid<=0;tx_valid<=0;gap<=12;tx_ack<=tx_req_sync[1];end
  else if(sending)begin
   if(tx_index==UI_FRAME_BYTES+7)begin sending<=0;gap<=12;end
   else tx_index<=tx_index+1'b1;
  end else if(gap!=0)gap<=gap-1'b1;
  else if(tx_req_sync[1]!=tx_ack)begin sending<=1;tx_index<=0;tx_crc<=32'hffffffff;end
  if(tx_rst_n&&enable&&pipe_valid&&pipe_last)begin
   tx_ack<=tx_req_sync[1];
   tx_sequence[7:0]<=tx_sequence[7:0]+1'b1;
   tx_sequence[15:8]<=tx_sequence[15:8]+carry8;
   tx_sequence[23:16]<=tx_sequence[23:16]+carry16;
   tx_sequence[31:24]<=tx_sequence[31:24]+carry24;
  end
 end

 reg [7:0] rx_memory[0:511] /* synthesis syn_ramstyle="block_ram" */;
 reg rx_request=0,rx_ack=0,published_bank=0,write_bank=0;
 (* syn_preserve=1 *) reg [1:0] rx_ack_sync=0,rx_req_sync=0;
 reg [3:0] preamble=0;reg receiving=0,header_bad=0,wire_bad=0,can_publish=0;
 reg [8:0] rx_index=0;reg [31:0] rx_crc=32'hffffffff,rx_sequence=0;
 wire [8:0] payload_offset=rx_index-9'd30;
 always @(posedge rx_clk)if(rx_valid&&receiving&&rx_index>=30&&rx_index<UI_BODY_BYTES)
  rx_memory[{write_bank,payload_offset[7:0]}]<=rx_data;
 always @(posedge rx_clk)begin
  rx_ack_sync<={rx_ack_sync[0],rx_ack};
  if(!rx_rst_n)begin
   rx_ack_sync<=0;rx_request<=0;published_bank<=0;write_bank<=0;preamble<=0;receiving<=0;
   header_bad<=0;wire_bad<=0;can_publish<=0;rx_index<=0;rx_crc<=32'hffffffff;rx_sequence<=0;
   good_frames<=0;bad_frames<=0;dropped_frames<=0;
  end else if(rx_valid)begin
   if(!receiving)begin
    if(rx_data==8'h55&&!rx_error)begin if(preamble<7)preamble<=preamble+1'b1;end
    else if(rx_data==8'hd5&&preamble>=3&&!rx_error)begin
     receiving<=1;preamble<=0;rx_index<=0;rx_crc<=32'hffffffff;rx_sequence<=0;header_bad<=0;wire_bad<=0;
     can_publish<=rx_request==rx_ack_sync[1];
    end else preamble<=0;
   end else begin
    if(rx_index<511)rx_index<=rx_index+1'b1;
    rx_crc<=ui_crc(rx_crc,rx_data);if(rx_error)wire_bad<=1;
    if(rx_index<22&&rx_data!=ui_header(!ROLE[0],32'd0,rx_index))header_bad<=1;
    if(rx_index>=22&&rx_index<26)rx_sequence<={rx_sequence[23:0],rx_data};
    case(rx_index)
     26:if(rx_data!=~rx_sequence[31:24])header_bad<=1;
     27:if(rx_data!=~rx_sequence[23:16])header_bad<=1;
     28:if(rx_data!=~rx_sequence[15:8])header_bad<=1;
     29:if(rx_data!=~rx_sequence[7:0])header_bad<=1;
    endcase
   end
  end else begin
   preamble<=0;
   if(receiving)begin
    if(rx_index==UI_FRAME_BYTES&&rx_crc==32'hdebb20e3&&!header_bad&&!wire_bad)begin
     if(can_publish)begin published_bank<=write_bank;write_bank<=!write_bank;rx_request<=!rx_request;good_frames<=good_frames+1'b1;end
     else dropped_frames<=dropped_frames+1'b1;
    end else bad_frames<=bad_frames+1'b1;
   end
   receiving<=0;
  end
 end
 // Two host clocks per byte allow a synchronous true dual-clock RAM read.
 reg [8:0] read_address=0;reg [7:0] memory_byte;reg [1:0] read_state=0;
 always @(posedge host_clk)memory_byte<=rx_memory[read_address];
 always @(posedge host_clk)begin
  rx_req_sync<={rx_req_sync[0],rx_request};host_valid<=0;host_done<=0;
  if(!host_rst_n)begin rx_req_sync<=0;rx_ack<=0;read_address<=0;read_state<=0;host_byte<=0;host_index<=0;end
  else case(read_state)
   0:if(rx_req_sync[1]!=rx_ack)begin read_address<={published_bank,8'd0};host_index<=0;read_state<=1;end
   1:read_state<=2;
   2:begin
    host_byte<=memory_byte;host_valid<=1;
    if(read_address[7:0]==255)read_state<=3;
    else begin read_address<=read_address+1'b1;read_state<=1;end
   end
   3:begin host_done<=1;rx_ack<=rx_req_sync[1];read_state<=0;end
  endcase
  // Index accompanies the emitted byte; derive from RAM address rather than
  // advancing an output counter on the same edge as host_valid.
  if(read_state==2)host_index<=read_address[7:0];
 end
endmodule
