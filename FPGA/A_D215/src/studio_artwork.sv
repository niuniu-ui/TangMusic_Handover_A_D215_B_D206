module studio_artwork(
 input wire clk,reset,input wire [4:0] scene,input wire [10:0] x,input wire [9:0] y,
 input wire de,hs,vs,output reg [23:0] rgb,output wire [10:0] px,output wire [9:0] py,
 output wire out_de,out_hs,out_vs
);
 `include "src/studio_colors.vh"
 wire [15:0] row_id,tile_id,pixels;wire [31:0] palettes;
 reg [10:0] xx[0:3];reg [9:0] yy[0:3];reg [3:0] dd,hh,vv;integer i;
 studio_rows rows(.clk(clk),.addr({scene,y[9:3],x[9:8]}),.data(row_id));
 studio_tiles tiles(.clk(clk),.addr({row_id[10:0],xx[0][7:3]}),.data(tile_id));
 studio_pixels pix(.clk(clk),.addr({tile_id[13:0],yy[1][2:0]}),.data(pixels));
 studio_palettes pal(.clk(clk),.addr(tile_id[13:0]),.data(palettes));
 wire [1:0] index=pixels>>(xx[2][2:0]*2);
 wire [6:0] colour=palettes>>(index*7);
 always @(posedge clk)begin
  xx[0]<=x;yy[0]<=y;for(i=1;i<4;i=i+1)begin xx[i]<=xx[i-1];yy[i]<=yy[i-1];end
  rgb<=studio_color(colour);dd<={dd[2:0],de};hh<={hh[2:0],hs};vv<={vv[2:0],vs};
  if(reset)begin dd<=0;hh<=0;vv<=0;end
 end
 assign px=xx[3];assign py=yy[3];assign out_de=dd[3];assign out_hs=hh[3];assign out_vs=vv[3];
endmodule
