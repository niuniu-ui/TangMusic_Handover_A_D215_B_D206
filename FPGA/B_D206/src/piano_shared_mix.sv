// One wavetable and two multipliers serve all 32 independent piano voices.
// Each sweep finishes in <40 clocks of the 1024-clock audio sample period.
// The completed sum is held and latched at the next original sample boundary.
module piano_shared_mix(
 input wire clk,rst_n,sample_tick,input wire [255:0] addresses,
 input wire [511:0] envelopes,input wire [223:0] velocities,input wire [31:0] banks,
 output reg signed [15:0] pcm
);
 reg running=0;reg [4:0] voice=0;reg [2:0] valid=0,last=0;reg [9:0] wait_cycles=0;
 wire signed [15:0] wave;
 piano_wave_rom table_rom(.address(addresses[voice*8+:8]),.house(banks[voice]),.sample(wave));
 reg signed [23:0] velocity_product=0;reg [15:0] env=0;
 reg signed [40:0] envelope_product=0;reg signed [15:0] voice_pcm=0;
 reg signed [20:0] sum=0,completed=0;
 wire signed [20:0] total=sum+{{5{voice_pcm[15]}},voice_pcm};
 wire signed [20:0] attenuated=completed>>>3;
 always @(posedge clk)begin
  if(!rst_n)begin running<=0;voice<=0;valid<=0;last<=0;wait_cycles<=0;velocity_product<=0;env<=0;envelope_product<=0;voice_pcm<=0;sum<=0;completed<=0;pcm<=0;end
  else begin
   valid<={valid[1:0],running};last<={last[1:0],running&&voice==31};
   if(sample_tick)begin
    wait_cycles<=900;
    pcm<=attenuated>32767?16'sh7fff:attenuated< -32768?16'sh8000:attenuated[15:0];
   end else if(wait_cycles!=0)begin
    wait_cycles<=wait_cycles-1'b1;if(wait_cycles==1)begin running<=1;voice<=0;sum<=0;end
   end else if(running)begin
    velocity_product<=wave*$signed({1'b0,velocities[voice*7+:7]});env<=envelopes[voice*16+:16];
    if(voice==31)running<=0;else voice<=voice+1'b1;
   end
   if(valid[0])envelope_product<=velocity_product*$signed({1'b0,env});
   if(valid[1])voice_pcm<=envelope_product[38:23];
   if(valid[2])begin sum<=total;if(last[2])completed<=total;end
  end
 end
endmodule
