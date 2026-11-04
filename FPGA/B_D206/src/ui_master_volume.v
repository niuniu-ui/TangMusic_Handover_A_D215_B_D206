`timescale 1ns/1ps
// Unity at 127, zero at 0. Same signed Q15 scaling/ramp as the existing pad
// volume, with a separate master target; the JP-1 knob remains unchanged.
module ui_master_volume(
 input wire clk,rst_n,sample_tick,input wire [6:0] level,
 input wire signed [15:0] pcm_in, output wire signed [15:0] pcm_out
);
 reg [15:0] target;
 reg [15:0] gain;
 wire signed [16:0] delta=$signed({1'b0,target})-$signed({1'b0,gain});
 // Decode the UI value ahead of the sample strobe, rather than placing
 // the level adder and the ramp arithmetic in the same register path.
 always @(posedge clk) begin
  if(!rst_n) begin gain<=32768;target<=32768;end
  else begin
   target<={1'b0,level,8'b0}+{8'b0,level,1'b0}+
           (level>=96 ? 16'd2 : level>=32 ? 16'd1 : 16'd0);
   if(sample_tick) begin
    if(delta>17'sd256) gain<=gain+16'd256;
    else if(delta< -17'sd256) gain<=gain-16'd256;
    else gain<=target;
   end
  end
 end
 wire signed [16:0] signed_gain=$signed({1'b0,gain});
 wire signed [32:0] product=$signed(pcm_in)*signed_gain;
 assign pcm_out=product[30:15];
endmodule
