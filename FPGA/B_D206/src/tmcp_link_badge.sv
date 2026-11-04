`timescale 1ns/1ps
// Overlay coordinates MUST already be aligned with rgb_in / de.
// page-independent 1024x600 badge; no frame buffer or new font ROM required.
module tmcp_link_badge(
 input wire clk50,reset50,pixel_clk,pixel_reset,frame_end,
 input wire hello_seen,app_online,
 input wire [10:0] x,input wire [9:0] y,input wire de,input wire [23:0] rgb_in,
 output reg [23:0] rgb_out,output reg [1:0] visible_state
);
 wire [1:0] mailbox;wire updated;
 ui_cdc_snapshot #(.WIDTH(2)) cdc(.src_clk(clk50),.src_reset(reset50),.dst_clk(pixel_clk),.dst_reset(pixel_reset),
 .src_data({hello_seen,app_online}),.dst_data(mailbox),.dst_updated(updated));
 always @(posedge pixel_clk)if(pixel_reset)visible_state<=0;else if(frame_end)visible_state<=mailbox==3?2:mailbox[1]?1:0;
 function [34:0] font(input [7:0] c);begin case(c)
  "A":font=35'b01110_10001_10001_11111_10001_10001_10001;
  "P":font=35'b11110_10001_10001_11110_10000_10000_10000;
  "O":font=35'b01110_10001_10001_10001_10001_10001_01110;
  "N":font=35'b10001_11001_11001_10101_10011_10011_10001;
  "F":font=35'b11111_10000_10000_11110_10000_10000_10000;
  "W":font=35'b10001_10001_10001_10101_10101_11011_10001;
  "I":font=35'b01110_00100_00100_00100_00100_00100_01110;
  "T":font=35'b11111_00100_00100_00100_00100_00100_00100;
  ".":font=35'b00000_00000_00000_00000_00000_01100_01100;
  default:font=0;endcase end endfunction
 // Fixed glyph slots avoid a 32-bit divide/modulo pixel path.
 function glyph_pixel(input [10:0] xx,input [9:0] yy,input [10:0] left,input [7:0] c);
  reg [34:0] bitmap;reg [10:0] dx;reg [2:0] column,row;reg [5:0] at_bit;
  begin
   bitmap=font(c);dx=xx-left;column=dx[3:1];row=yy[3:1];
   at_bit=6'd34-({3'b0,row}*6'd5)-{3'b0,column};
   glyph_pixel=xx>=left&&xx<left+11'd10&&yy>=32&&yy<46&&bitmap[at_bit];
  end
 endfunction
 reg letter_on;reg [23:0] ink;
 always @*begin
  ink=visible_state==2?24'h8edccc:visible_state==1?24'hf4c270:24'h8b9eaa;
  letter_on=glyph_pixel(x,y,11'd638,"A")||glyph_pixel(x,y,11'd650,"P")||glyph_pixel(x,y,11'd662,"P")||
   glyph_pixel(x,y,11'd686,visible_state==1?"W":"O")||
   glyph_pixel(x,y,11'd698,visible_state==2?"N":visible_state==1?"A":"F")||
   glyph_pixel(x,y,11'd710,visible_state==2?" ":visible_state==1?"I":"F")||glyph_pixel(x,y,11'd722,visible_state==1?"T":" ");
  rgb_out=rgb_in;
  if(de&&x>=610&&x<766&&y>=24&&y<56)begin
   rgb_out=24'h16303d;
   if((x>=620&&x<628&&y>=36&&y<44)||letter_on)rgb_out=ink;
  end
 end
endmodule
