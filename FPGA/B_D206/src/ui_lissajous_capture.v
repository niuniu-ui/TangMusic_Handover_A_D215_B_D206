`timescale 1ns/1ps
// Display-only phase portrait of the final mixed PCM. Both axes use the same
// low-pass signal and frame-constant gain; Y is a measured quarter-period late.
// Two 128x128 one-bit banks, with the same vblank ownership protocol as scope.
// A short, triggered 256-sample exposure replaces the previous whole trace.
// No display filtering, gain or trigger is applied to the audible PCM stream.
module ui_lissajous_capture(
 input wire audio_clk,audio_reset,sample_tick,input wire signed [15:0] pcm,
 input wire [1:0] delay_select,
 input wire pixel_clk,pixel_reset,frame_end,run,
 input wire [6:0] read_x,read_y,output reg pixel
);
 reg bitmap[0:32767] /* synthesis syn_ramstyle="block_ram" */;
 // Keep full precision before applying the same gain to both axes. Storing
 // already-amplified samples would distort Y whenever a new frame changes gain.
 reg signed [15:0] history[0:63];reg [5:0] history_write=0;
 reg [6:0] history_valid=0;
 // Display-only one-pole low-pass: retain four fractional bits and update
 // exactly once per received audio sample. Both axes use this same signal.
 reg signed [20:0] smooth_q4=0;
 wire signed [20:0] target_q4={pcm[15],pcm,4'b0};
 wire signed [21:0] smooth_delta=$signed({target_q4[20],target_q4})-$signed({smooth_q4[20],smooth_q4});
 wire signed [21:0] smooth_next=$signed({smooth_q4[20],smooth_q4})+(smooth_delta >>> 3);
 wire signed [15:0] smooth_pcm=smooth_next >>> 4;
 wire [15:0] magnitude=smooth_pcm[15]?(~smooth_pcm)+16'd1:smooth_pcm;
 reg [15:0] peak_work=0,measured_peak=0;reg [7:0] peak_count=0;
 wire [15:0] gain_peak=peak_work>measured_peak?peak_work:measured_peak;
 reg [3:0] capture_shift=5;
 reg quiet_capture=1;
 function [3:0] gain_for_peak;
  input [15:0] peak;
  begin
   // Coarse, stable powers of two keep normal peaks inside the plot margin.
   if(peak>28160)gain_for_peak=9;
   else if(peak>14080)gain_for_peak=8;
   else if(peak>7040)gain_for_peak=7;
   else if(peak>3520)gain_for_peak=6;
   else if(peak>1760)gain_for_peak=5;
   else if(peak>880)gain_for_peak=4;
   else if(peak>440)gain_for_peak=3;
   else gain_for_peak=2;
  end
 endfunction
 reg negative_seen=0;
 reg [9:0] period_count=0;
 reg [6:0] estimated_delay=32,capture_delay=32;
 wire rising_cross=negative_seen&&!smooth_pcm[15];
 wire [9:0] quarter_period=(period_count+10'd1)>>2;
 // delay_select is retained for source compatibility; phase is now automatic.
 wire [5:0] delay_address=history_write-capture_delay[5:0];
 wire signed [15:0] past=history[delay_address];
 wire signed [15:0] scaled_x=smooth_pcm>>>capture_shift;
 wire signed [15:0] scaled_y=past>>>capture_shift;
 function [7:0] plot_amplitude;
  input signed [15:0] value;
  begin plot_amplitude=value>110?8'd110:value< -110?-8'sd110:value[7:0];end
 endfunction
 wire [7:0] amp_x=plot_amplitude(scaled_x),amp_y=plot_amplitude(scaled_y);
 wire [6:0] sx=quiet_capture?7'd64:{~amp_x[7],amp_x[6:1]};
 wire [6:0] sy=quiet_capture?7'd63:7'd127-{~amp_y[7],amp_y[6:1]};
 reg write_bank=0,read_bank=1,published_bank=0,valid_bank=0;
 reg request=0,acknowledge=0;
 (* syn_preserve=1 *) reg [1:0] ack_sync=0,req_sync=0;
 localparam CLEAR=0,CAPTURE=1,PREPARE=2,DRAW=3,STEP=4,WAIT=5,TRIGGER=6;
 reg [2:0] state=0;
 reg [13:0] clear_address=0;reg [8:0] count=0;
 reg [8:0] trigger_wait=0;
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
   history_write<=0;history_valid<=0;smooth_q4<=0;cx<=0;cy<=0;ex<=0;ey<=0;dx<=0;dy<=0;error<=0;step_x<=0;step_y<=0;move_x<=0;move_y<=0;
   peak_work<=0;measured_peak<=0;peak_count<=0;capture_shift<=5;quiet_capture<=1;
   negative_seen<=0;period_count<=0;estimated_delay<=32;capture_delay<=32;trigger_wait<=0;
  end else begin
   if(sample_tick)begin
    smooth_q4<=smooth_next[20:0];
    history[history_write]<=smooth_pcm;history_write<=history_write+1'b1;
    if(history_valid<64)history_valid<=history_valid+1'b1;
    peak_count<=peak_count+1'b1;
    if(peak_count==255)begin
     measured_peak<=magnitude>peak_work?magnitude:peak_work;peak_work<=0;
    end else if(magnitude>peak_work)peak_work<=magnitude;
    if(period_count!=1023)period_count<=period_count+1'b1;
    if(smooth_pcm< -16'sd64)negative_seen<=1;
    if(rising_cross)begin
     negative_seen<=0;period_count<=0;
     if(period_count>=16&&period_count<1023)
      estimated_delay<=quarter_period<8?7'd8:quarter_period>64?7'd64:quarter_period[6:0];
    end
   end
   case(state)
    CLEAR:if(clear_address==16383)begin state<=TRIGGER;clear_address<=0;count<=0;first<=1;trigger_wait<=0;end
          else clear_address<=clear_address+1'b1;
    TRIGGER:if(sample_tick&&history_valid==64)begin
     // Stable onset for tones, bounded wait for silence/DC/complex mixtures.
     if(rising_cross||trigger_wait==511||gain_peak<64)begin
      capture_shift<=gain_for_peak(gain_peak);quiet_capture<=gain_peak<64;
      capture_delay<=estimated_delay;state<=CAPTURE;
     end else trigger_wait<=trigger_wait+1'b1;
    end
    CAPTURE:if(sample_tick&&history_valid==64)begin
     ex<=sx;ey<=sy;last<=count==255;count<=count+1'b1;state<=PREPARE;
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
