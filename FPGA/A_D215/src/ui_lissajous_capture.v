`timescale 1ns/1ps
// X = final DAC PCM, Y = the same PCM delayed by 8/16/32/64 samples.
// Two 128x128 one-bit banks, with the same vblank ownership protocol as scope.
// The displayed bank is never written. All interpolation is display-only.
module ui_lissajous_capture(
 input wire audio_clk,audio_reset,sample_tick,input wire signed [15:0] pcm,
 input wire [1:0] delay_select,
 input wire pixel_clk,pixel_reset,frame_end,run,
 input wire [6:0] read_x,read_y,output reg pixel
);
 reg bitmap[0:32767] /* synthesis syn_ramstyle="block_ram" */;
 reg [7:0] history[0:63];reg [5:0] history_write=0;
 reg [6:0] history_valid=0;
 wire signed [15:0] amplified=pcm>>>5;
 wire [7:0] amp=amplified>127?8'h7f:amplified< -128?8'h80:amplified[7:0];
 wire [5:0] distance=delay_select==0?6'd8:delay_select==1?6'd16:delay_select==2?6'd32:6'd0;
 wire [5:0] delay_address=history_write-distance;
 wire [7:0] past=history[delay_address];
 wire [6:0] sx={~amp[7],amp[6:1]};
 wire [6:0] sy=7'd127-{~past[7],past[6:1]};
 reg write_bank=0,read_bank=1,published_bank=0,valid_bank=0;
 reg request=0,acknowledge=0;
 (* syn_preserve=1 *) reg [1:0] ack_sync=0,req_sync=0;
 localparam CLEAR=0,CAPTURE=1,PREPARE=2,DRAW=3,STEP=4,WAIT=5;
 reg [2:0] state=0;
 reg [13:0] clear_address=0;reg [8:0] count=0;
 reg first=1,last=0;
 reg [6:0] cx=0,cy=0,ex=0,ey=0;
 reg signed [9:0] dx=0,dy=0,error=0;
 reg step_x=0,step_y=0;
 wire signed [10:0] twice_error=$signed(error)*2;
 reg move_x=0,move_y=0;
 wire [14:0] wr_addr={write_bank,state==CLEAR?clear_address:{cy,cx}};
 wire wr_en=!audio_reset&&(state==CLEAR||state==DRAW);
 always @(posedge audio_clk)if(wr_en)bitmap[wr_addr]<=state==DRAW;
 always @(posedge audio_clk)begin
  ack_sync<={ack_sync[0],acknowledge};
  if(audio_reset)begin
   state<=CLEAR;clear_address<=0;count<=0;first<=1;last<=0;
   write_bank<=0;published_bank<=0;request<=0;ack_sync<=0;
   history_write<=0;history_valid<=0;cx<=0;cy<=0;ex<=0;ey<=0;dx<=0;dy<=0;error<=0;step_x<=0;step_y<=0;move_x<=0;move_y<=0;
  end else begin
   if(sample_tick)begin
    history[history_write]<=amp;history_write<=history_write+1'b1;
    if(history_valid<64)history_valid<=history_valid+1'b1;
   end
   case(state)
    CLEAR:if(clear_address==16383)begin state<=CAPTURE;clear_address<=0;count<=0;first<=1;end
          else clear_address<=clear_address+1'b1;
    CAPTURE:if(sample_tick&&history_valid==64)begin
     ex<=sx;ey<=sy;last<=count==511;count<=count+1'b1;state<=PREPARE;
     if(first)begin cx<=sx;cy<=sy;dx<=0;dy<=0;error<=0;first<=0;end
     else begin
      dx<=sx>=cx?{3'b0,sx}-{3'b0,cx}:{3'b0,cx}-{3'b0,sx};
      dy<=sy>=cy?$signed({3'b0,cy})-$signed({3'b0,sy}):$signed({3'b0,sy})-$signed({3'b0,cy});
      step_x<=sx>=cx;step_y<=sy>=cy;
     end
    end
    PREPARE:begin error<=dx+dy;state<=DRAW;end
    DRAW:if(cx==ex&&cy==ey)begin
     if(last)begin published_bank<=write_bank;request<=!request;state<=WAIT;end
     else state<=CAPTURE;
    end else begin move_x<=twice_error>=dy;move_y<=twice_error<=dx;state<=STEP;end
    STEP:begin
     error<=error+(move_x?dy:10'sd0)+(move_y?dx:10'sd0);
     if(move_x)cx<=step_x?cx+1'b1:cx-1'b1;
     if(move_y)cy<=step_y?cy+1'b1:cy-1'b1;
     state<=DRAW;
    end
    WAIT:if(ack_sync[1]==request)begin write_bank<=!write_bank;state<=CLEAR;clear_address<=0;end
   endcase
  end
 end
 // Dedicated synchronous read infers a dual-clock block RAM.
 reg memory_pixel;
 always @(posedge pixel_clk)memory_pixel<=bitmap[{read_bank,read_y,read_x}];
 // Expose the one-cycle RAM read without adding another pixel of latency.
 always @*pixel=valid_bank?memory_pixel:1'b0;
 always @(posedge pixel_clk)begin
  req_sync<={req_sync[0],request};
  if(pixel_reset)begin req_sync<=0;read_bank<=1;valid_bank<=0;acknowledge<=0;end
  else if(frame_end&&run&&req_sync[1]!=acknowledge)begin
   read_bank<=published_bank;acknowledge<=req_sync[1];valid_bank<=1;
  end
 end
endmodule
