// Bounded LZ4 decoder. History shares the display cache RAM until ready rises.
// Only the compressed stream is in configuration ROM; writes are verified by the DDR bridge.
module studio_asset_loader #(
 parameter integer RAW_BYTES=453920, PACKED_BYTES=156431, STREAM_AW=18,
 parameter [31:0] EXPECTED_CRC=32'h420521d5,
 parameter [28:0] BASE_WORD=29'h0800000
)(
 input wire clk,rst_n,
 output wire [STREAM_AW-1:0] rom_address,input wire [7:0] rom_data,
 output wire [11:0] history_address,output wire [31:0] history_write_data,
 output wire [3:0] history_write_mask,input wire [31:0] history_read_data,
 output reg request,output reg [28:0] address,output reg [255:0] write_data,
 input wire mem_ready,mem_done,mem_error,
 output reg ready,output reg [7:0] fault,output reg [31:0] bytes_written
);
 localparam WAIT_MEM=0,FETCH=1,FETCH_WAIT=2,DISPATCH=3,EMIT=4,NEXT=5,
  HISTORY_REQ=6,HISTORY_WAIT=7,WRITE_REQ=8,WRITE_WAIT=9,FINISHED=10,FAILED=11,
  CHECK_LITERAL=12,CHECK_MATCH=13;
 localparam TOKEN=0,LITERAL_LENGTH=1,LITERAL=2,OFFSET_LO=3,OFFSET_HI=4,MATCH_LENGTH=5;
 // The extra length bit makes malformed extension bytes detectable before overflow.
 // Keep at least 14 bits for the 16 KiB circular history address.
 localparam OUTPUT_AW=($clog2(RAW_BYTES+1)<14)?14:$clog2(RAW_BYTES+1);
 reg [3:0] state;reg [2:0] purpose;
 reg [STREAM_AW:0] cursor;
 reg [OUTPUT_AW-1:0] produced,remaining_output;
 reg [OUTPUT_AW:0] literal_left,match_left;
 reg [31:0] crc;
 reg [7:0] source_byte,output_byte,offset_lo;reg [3:0] match_nibble;reg [15:0] distance;
 reg copying;reg [255:0] block_data;
 wire [13:0] history_ref=produced[13:0]-distance[13:0];
 assign rom_address=cursor[STREAM_AW-1:0];
 assign history_address=state==EMIT?produced[13:2]:history_ref[13:2];
 assign history_write_mask=state==EMIT?4'b0001<<produced[1:0]:4'b0000;
 assign history_write_data={4{output_byte}};
 function [31:0] crc_byte;input [31:0] c;input [7:0] b;reg [31:0] v;integer k;begin
  v=c^b;for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;
 end endfunction
 task fetch;input [2:0] why;begin purpose<=why;state<=FETCH;end endtask
 task fail;input [7:0] code;begin fault<=code;state<=FAILED;ready<=0;end endtask
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=WAIT_MEM;purpose<=TOKEN;cursor<=0;produced<=0;remaining_output<=RAW_BYTES;literal_left<=0;match_left<=0;
   crc<=32'hffffffff;source_byte<=0;output_byte<=0;offset_lo<=0;match_nibble<=0;distance<=0;
   copying<=0;block_data<=0;request<=0;address<=BASE_WORD;write_data<=0;ready<=0;fault<=0;bytes_written<=0;
  end else begin
   request<=0;
   case(state)
    WAIT_MEM:if(mem_ready)fetch(TOKEN);
    FETCH:if(cursor>=PACKED_BYTES)fail(1);else state<=FETCH_WAIT;
    FETCH_WAIT:begin source_byte<=rom_data;cursor<=cursor+1'b1;state<=DISPATCH;end
    DISPATCH:case(purpose)
     TOKEN:begin
      literal_left<=source_byte[7:4];match_nibble<=source_byte[3:0];copying<=0;
      if(source_byte[7:4]==15)fetch(LITERAL_LENGTH);
      else if(source_byte[7:4]!=0)fetch(LITERAL);else fetch(OFFSET_LO);
     end
     LITERAL_LENGTH:begin
      literal_left<=literal_left+source_byte;
      state<=CHECK_LITERAL;
     end
     LITERAL:begin output_byte<=source_byte;copying<=0;state<=EMIT;end
     OFFSET_LO:begin offset_lo<=source_byte;fetch(OFFSET_HI);end
     OFFSET_HI:begin
      distance<={source_byte,offset_lo};match_left<=match_nibble+5'd4;
      if({source_byte,offset_lo}==0||{source_byte,offset_lo}>16384||{source_byte,offset_lo}>produced)fail(2);
      else if(match_nibble==15)fetch(MATCH_LENGTH);else state<=HISTORY_REQ;
     end
     MATCH_LENGTH:begin
      match_left<=match_left+source_byte;
      state<=CHECK_MATCH;
     end
     default:fail(1);
    endcase
    // Split extension addition from bounds checking; no add/subtract/compare chain.
    CHECK_LITERAL:if(literal_left>remaining_output)fail(3);
     else if(source_byte==255)fetch(LITERAL_LENGTH);else fetch(LITERAL);
    CHECK_MATCH:if(match_left>remaining_output)fail(3);
     else if(source_byte==255)fetch(MATCH_LENGTH);else state<=HISTORY_REQ;
    HISTORY_REQ:state<=HISTORY_WAIT;
    HISTORY_WAIT:begin output_byte<=history_read_data>>(history_ref[1:0]*8);copying<=1;state<=EMIT;end
    EMIT:begin
     if(remaining_output==0)fail(3);
     else begin
      block_data[produced[4:0]*8+:8]<=output_byte;
      crc<=crc_byte(crc,output_byte);produced<=produced+1'b1;remaining_output<=remaining_output-1'b1;
      if(copying)match_left<=match_left-1'b1;else literal_left<=literal_left-1'b1;
      if(produced[4:0]==31||remaining_output==1)begin address<=BASE_WORD+((produced>>5)<<3);state<=WRITE_REQ;end
      else state<=NEXT;
     end
    end
    WRITE_REQ:if(mem_ready)begin request<=1;write_data<=block_data;state<=WRITE_WAIT;end
    WRITE_WAIT:if(mem_done)begin
     if(mem_error)fail(5);else begin bytes_written<=produced;block_data<=0;state<=NEXT;end
    end
    NEXT:begin
     if(produced==RAW_BYTES)begin
      if((copying&&match_left!=0)||(!copying&&literal_left!=0))fail(3);
      else if(cursor!=PACKED_BYTES)fail(6);
      else if(~crc!=EXPECTED_CRC)fail(4);
      else begin ready<=1;state<=FINISHED;end
     end else if(copying)begin if(match_left==0)fetch(TOKEN);else state<=HISTORY_REQ;end
     else begin if(literal_left==0)fetch(OFFSET_LO);else fetch(LITERAL);end
    end
    FINISHED:begin end
    FAILED:begin end
    default:fail(1);
   endcase
   if(mem_error&&state!=FINISHED)fail(5);
  end
 end
endmodule
