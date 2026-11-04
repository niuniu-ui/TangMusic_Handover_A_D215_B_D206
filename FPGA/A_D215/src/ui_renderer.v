`timescale 1ns/1ps
module ui_renderer(
 input wire pixel_clk,reset,
 input wire [2:0] page,input wire plot,octave_high,
 input wire [6:0] volume_percent,input wire [3:0] touch_count,
 input wire [6:0] voice_count,input wire [31:0] piano_active,
 input wire [3:0] usb_status,input wire [127:0] spectrum,
 input wire [9:0] contact_down,input wire [99:0] contact_x,contact_y,
 input wire [10:0] x,input wire [9:0] y,input wire de,hs,vs,
 input wire [15:0] scope_pair,
 output reg [23:0] rgb,output reg out_de,out_hs,out_vs
);
 `include "src/ui_layout.vh"
 wire [2:0] scene=page==0 ? {1'b0,octave_high,plot} : page+3'd3;
 wire [23:0] art_background;
 wire raw_de,raw_hs,raw_vs;
 reg [23:0] background;
 reg art_de,art_hs,art_vs;
 reg [23:0] composed_rgb;
 wire [10:0] ax;wire [9:0] ay;
 reg [10:0] px;reg [9:0] py;
 ui_artwork artwork(.clk(pixel_clk),.reset(reset),.scene(scene),.x(x),.y(y),
  .de(de),.hs(hs),.vs(vs),.rgb(art_background),.px(ax),.py(ay),
  .out_de(raw_de),.out_hs(raw_hs),.out_vs(raw_vs));
 reg [15:0] wave1,wave2,wave3,wave4;
 reg [10:0] slider_x;
 wire [11:0] slider_scaled=volume_percent*5'd27;
 wire [11:0] slider_offset=slider_scaled/12'd10;
 reg [3:0] volume_units,volume_tens,touch_units,touch_tens,voice_units,voice_tens;
 always @(posedge pixel_clk) begin
  wave1<=scope_pair;wave2<=wave1;wave3<=wave2;wave4<=wave3;
  slider_x<=11'd711+slider_offset[10:0];
  volume_units<=volume_percent%7'd10;volume_tens<=(volume_percent/7'd10)%7'd10;
  touch_units<=touch_count%4'd10;touch_tens<=touch_count/4'd10;
  voice_units<=voice_count%7'd10;voice_tens<=voice_count/7'd10;
 end
 function digit;
  input [3:0] n;input [3:0] col,row;
  reg [34:0] bits;
  reg [5:0] bit_index;
  begin
   case(n)
    0:bits=35'b01110_10001_10011_10101_11001_10001_01110;
    1:bits=35'b00100_01100_00100_00100_00100_00100_01110;
    2:bits=35'b01110_10001_00001_00010_00100_01000_11111;
    3:bits=35'b11110_00001_00001_01110_00001_00001_11110;
    4:bits=35'b00010_00110_01010_10010_11111_00010_00010;
    5:bits=35'b11111_10000_10000_11110_00001_00001_11110;
    6:bits=35'b01110_10000_10000_11110_10001_10001_01110;
    7:bits=35'b11111_00001_00010_00100_01000_01000_01000;
    8:bits=35'b01110_10001_10001_01110_10001_10001_01110;
    9:bits=35'b01110_10001_10001_01111_00001_00001_01110;
    default:bits=0;
   endcase
   bit_index=(6'd6-row)*6'd5+6'd4-col;
   digit=(col<5 && row<7) ? bits[bit_index] : 1'b0;
  end
 endfunction
 integer i;
 reg signed [11:0] w0,w1,low_y,high_y,dx,dy;
 reg [4:0] bar;
 reg [3:0] bar_level;
 reg [1:0] pos;
 reg [5:0] vol_x;
 reg [4:0] vol_cell_x,vol_y;
 reg [3:0] small_x,small_y,small_col;
 reg signed [4:0] circle_dx,circle_dy;
 reg [10:0] circle_radius;
 reg [4:0] key;
 reg [3:0] volume_col,volume_row;
 reg [1:0] volume_pos;
 reg [10:0] pre_radius;
 reg circle_bounds;
 wire [5:0] art_vol_x=ax-11'd916;
 wire [4:0] art_vol_y=ay-10'd153;
 wire [4:0] art_cell_x=art_vol_x>=36 ? art_vol_x-6'd36 : art_vol_x>=18 ? art_vol_x-6'd18 : art_vol_x;
 wire signed [11:0] art_dx=$signed({1'b0,ax})-$signed({1'b0,slider_x});
 wire signed [11:0] art_dy=$signed({1'b0,ay})-12'sd197;
 wire signed [4:0] art_circle_dx=art_dx[4:0],art_circle_dy=art_dy[4:0];
 // Predecode coordinates before the dynamic color mux. Keep background,
 // waveform and valid/sync on the same additional pipeline stage.
 always @(posedge pixel_clk) begin
  px<=ax;py<=ay;background<=art_background;
  art_de<=raw_de;art_hs<=raw_hs;art_vs<=raw_vs;
  key<=ui_key_at(ax[9:0],ay);
  volume_col<=art_cell_x/5'd3;volume_row<=art_vol_y/5'd3;
  volume_pos<=art_vol_x>=36 ? 2 : art_vol_x>=18 ? 1 : 0;
  pre_radius<=art_circle_dx*art_circle_dx+art_circle_dy*art_circle_dy;
  circle_bounds<=art_dx>=-9 && art_dx<=9 && art_dy>=-9 && art_dy<=9;
  if(reset)begin art_de<=0;art_hs<=0;art_vs<=0;end
 end
 reg [3:0] ndigit;
 reg mark;
 always @* begin
  composed_rgb=background;
  w0=317-($signed(wave4[15:8])>>>2);w1=317-($signed(wave4[7:0])>>>2);
  low_y=w0<w1?w0:w1;high_y=w0>w1?w0:w1;
  bar=0;bar_level=0;dx=0;dy=0;pos=0;ndigit=0;mark=0;
  vol_x=px-11'd916;vol_y=py-10'd153;
  vol_cell_x=vol_x>=36 ? vol_x-6'd36 : vol_x>=18 ? vol_x-6'd18 : vol_x;
  small_x=0;small_y=0;small_col=0;circle_dx=0;circle_dy=0;circle_radius=0;
  if(art_de) begin
   // Connection status is derived from the enumerating USB hosts.
   if(px>=877 && px<883 && py>=47 && py<53) begin
    if(usb_status[1:0]==2 || usb_status[3:2]==2) composed_rgb=24'hd0ed8a;
    else if(usb_status[1:0]==3 || usb_status[3:2]==3) composed_rgb=24'hf09b7c;
    else if(usb_status!=0) composed_rgb=24'hb49b60;
    else composed_rgb=24'h71817a;
   end
   if(page==0) begin
    if(px>=711 && px<=981 && py>=195 && py<=199)
     composed_rgb=px<=slider_x ? 24'hd0ed8a : 24'h3b4640;
    if(circle_bounds && pre_radius<=81)
     composed_rgb=pre_radius<=36 ? 24'hd0ed8a : 24'h45533f;
    if(px>=916 && px<970 && py>=153 && py<174) begin
     pos=volume_pos;
     ndigit=pos==0 ? 4'd1 : pos==1 ? volume_tens : volume_units;
     if((pos==2 || (pos==1 && volume_percent>=10) || volume_percent>=100) &&
          digit(ndigit,volume_col,volume_row)) composed_rgb=24'hd0ed8a;
    end
    if(px>=781 && px<795 && ((py>=273 && py<287)||(py>=298 && py<312))) begin
     small_x=px-11'd781;small_y=py-(py<290?10'd273:10'd298);
     small_col=small_x>=7 ? small_x-4'd7 : small_x;
     ndigit=py<290 ? (small_x<7 ? touch_tens : touch_units) : (small_x<7 ? voice_tens : voice_units);
     if(digit(ndigit,small_col,{1'b0,small_y[3:1]})) composed_rgb=24'hd0ed8a;
    end
    if(px>=134 && px<646 && py>=281 && py<355) begin
     if(!plot && py>=low_y && py<=high_y) composed_rgb=24'hd0ed8a;
     if(plot) begin
      bar=(px-11'd134)>>4;bar_level=spectrum[bar*4 +:4];
      if((px-134)%16<12 && py>=354-bar_level*4 && py<354) composed_rgb=24'hd0ed8a;
     end
    end
    if(key<13 && piano_active[7+key+(octave_high?12:0)]) begin
     if(py>=528 || ((key==1 || key==3 || key==6 || key==8 || key==10) && py>=490)) composed_rgb=24'hd0ed8a;
    end
    if(volume_percent==0 && px>=893 && px<981 && py>=484 && py<530 &&
         (px<895 || px>=979 || py<486 || py>=528)) composed_rgb=24'hf09b7c;
   end
   if(page==4) begin
    if(px>=637 && px<651 && py>=476 && py<490) begin
     small_x=px-11'd637;small_y=py-10'd476;
     small_col=small_x>=7 ? small_x-4'd7 : small_x;
     ndigit=small_x<7 ? touch_tens : touch_units;
     if(digit(ndigit,small_col,{1'b0,small_y[3:1]})) composed_rgb=24'hd0ed8a;
    end
    if(px>=582 && px<978 && py>=220 && py<460) begin
     for(i=0;i<10;i=i+1) if(contact_down[i]) begin
      dx=$signed({1'b0,px})-$signed({1'b0,contact_x[i*10 +:10]});
      dy=$signed({1'b0,py})-$signed({1'b0,contact_y[i*10 +:10]});
      if((dx>=-1 && dx<=1 && dy>=-10 && dy<=10) ||
         (dy>=-1 && dy<=1 && dx>=-10 && dx<=10)) composed_rgb=24'hd0ed8a;
     end
    end
   end
  end else composed_rgb=0;
 end
 // Separate the overlay path from TMDS disparity/encoding logic.
 // Artwork has four clocks; coordinate decode and RGB make six in total.
 always @(posedge pixel_clk) begin
  rgb<=composed_rgb;out_de<=art_de;out_hs<=art_hs;out_vs<=art_vs;
  if(reset)begin rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;end
 end
endmodule
