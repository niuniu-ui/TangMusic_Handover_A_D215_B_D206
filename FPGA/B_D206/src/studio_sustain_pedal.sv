`timescale 1ns/1ps
module studio_sustain_pedal #(
 parameter integer CLK_HZ=50000000,STABLE_MS=10,CALIBRATION_MS=100,
 parameter integer AUTO_POLARITY=0,ACTIVE_LOW=1
)(
 input wire clk,rst_n,sig,
 output wire down,output reg calibrated
);
 localparam integer FILTER_TICKS=(CLK_HZ/1000)*STABLE_MS;
 localparam integer CAL_TICKS=(CLK_HZ/1000)*CALIBRATION_MS;
 localparam integer FW=FILTER_TICKS>1?$clog2(FILTER_TICKS):1;
 localparam integer CW=CAL_TICKS>1?$clog2(CAL_TICKS+1):1;
 (* syn_preserve=1 *) reg [1:0] sync;
 reg stable,idle_level;reg [FW-1:0] filter_count;reg [CW-1:0] calibration_count;
 assign down=calibrated&&(stable!=idle_level);
 // Automatic polarity is sampled ONCE while the pedal is released at startup
 // or user reset. It never follows the pedal again during a performance.
 always @(posedge clk)begin
  if(!rst_n)begin
   sync<=3;stable<=1;idle_level<=ACTIVE_LOW!=0;
   filter_count<=0;calibration_count<=0;calibrated<=0;
  end else begin
   sync<={sync[0],sig};
   if(sync[1]==stable)filter_count<=0;
   else if(filter_count==FILTER_TICKS-1)begin stable<=sync[1];filter_count<=0;end
   else filter_count<=filter_count+1'b1;
   if(!calibrated)begin
    if(!AUTO_POLARITY)begin calibrated<=1;idle_level<=ACTIVE_LOW!=0;end
    else if(calibration_count<CAL_TICKS)calibration_count<=calibration_count+1'b1;
    else if(filter_count==0&&sync[1]==stable)begin idle_level<=stable;calibrated<=1;end
   end
  end
 end
endmodule
