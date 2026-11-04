// Keep exactly the original PT8211-derived 1024-clock timing and sample latch.
module audio_sample_clock(input wire clk,rst_n,input wire signed [15:0] pcm_in,
 output reg sample_tick,output reg signed [15:0] sample_pcm);
 reg [9:0] count;
 always @(posedge clk)begin
  if(!rst_n)begin count<=0;sample_tick<=0;sample_pcm<=0;end
  else begin
   count<=count+1'b1;sample_tick<=0;
   if(count==10'd31)begin sample_tick<=1;sample_pcm<=pcm_in;end
  end
 end
endmodule
