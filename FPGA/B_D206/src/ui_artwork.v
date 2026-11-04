`timescale 1ns/1ps
// Generated tile artwork. Three synchronous BSRAM lookups and one palette
// register; coordinate and sync signals have the same five-cycle latency.
module ui_artwork(
 input wire clk, reset, input wire [4:0] scene,
 input wire [10:0] x, input wire [9:0] y,
 input wire de, hs, vs,
 output reg [23:0] rgb, output wire [10:0] px, output wire [9:0] py,
 output wire out_de, out_hs, out_vs
);
 wire [15:0] row_id, tile_id;
 wire [15:0] pixels;
 reg [10:0] xx[0:4]; reg [9:0] yy[0:4];
 reg [12:0] tile_index;
 ui_rows_rom rows(.clk(clk),.addr({scene,y[9:3],x[9:8]}),.data(row_id));
 ui_tiles_rom tiles(.clk(clk),.addr({row_id[10:0],xx[0][7:3]}),.data(tile_id));
 ui_pixels_rom tile_data(.clk(clk),.addr({tile_index,yy[2][2:0],xx[2][2]}),.data(pixels));
 reg [4:0] dd=0,hh=0,vv=0;
 integer i;
 function [23:0] color;
  input [3:0] index;
  begin case(index)
            4'd0: color=24'h10181f;
            4'd1: color=24'h142029;
            4'd2: color=24'h1a252e;
            4'd3: color=24'h24343f;
            4'd4: color=24'h304451;
            4'd5: color=24'h16405a;
            4'd6: color=24'h9eb0bd;
            4'd7: color=24'heef4f8;
            4'd8: color=24'h42bff5;
            4'd9: color=24'h8d9aa2;
            4'd10: color=24'he3eaf0;
            4'd11: color=24'h005183;
            4'd12: color=24'h8edccc;
            4'd13: color=24'hf09b7c;
            4'd14: color=24'h062337;
            4'd15: color=24'h00a0e9;
   default:color=24'h10181f;
  endcase end
 endfunction
 always @(posedge clk) begin
  tile_index<=tile_id[12:0];
  rgb<=color(pixels>>(xx[3][1:0]*4));
  xx[0]<=x;yy[0]<=y;
  for(i=1;i<5;i=i+1) begin xx[i]<=xx[i-1];yy[i]<=yy[i-1];end
  dd<={dd[3:0],de};hh<={hh[3:0],hs};vv<={vv[3:0],vs};
  if(reset) begin dd<=0;hh<=0;vv<=0;end
 end
 assign px=xx[4];assign py=yy[4];
 assign out_de=dd[4];assign out_hs=hh[4];assign out_vs=vv[4];
endmodule
