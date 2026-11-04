`timescale 1ns/1ps
// Candidate: preserve 32 independent voices, share the output gain multipliers.
module air_drum_synth #(parameter integer VOICES=32)(
 input wire clk,rst_n,sample_ce,event_valid,input wire [1:0] event_zone,input wire [7:0] event_velocity,
 input wire bank,input wire signed [7:0] bend,input wire [7:0] expression,input wire spectral_test,
 output reg signed [15:0] pcm,output reg pcm_valid,output wire [VOICES-1:0] active_mask,
 output reg overflow,output reg [15:0] event_count,
 output reg signed [21:0] mix_sum,
 output wire note_launch,output wire [4:0] note_slot,output wire [18:0] note_data
);
 reg [18:0] queue[0:63];reg [5:0] rd,wr;reg [6:0] count;
 reg [5:0] next_voice,selected;reg launch;reg [1:0] zone;reg [7:0] velocity,expr;reg timbre;
 // Read-only taps for the additional partial bank. Preserve the original
 // event allocation, arithmetic and saturated pcm output exactly.
 assign note_launch=launch;assign note_slot=selected[4:0];
 assign note_data={timbre,expr,zone,velocity};
 wire pop=sample_ce&&count!=0&&!spectral_test;wire push=event_valid&&(count<64||pop);
 wire signed [12:0] waves[0:VOICES-1];wire [15:0] envs[0:VOICES-1];wire [7:0] gains[0:VOICES-1];
 genvar v;generate for(v=0;v<VOICES;v=v+1)begin:voices
  air_drum_voice #(.INDEX(v),.SHARED_GAIN(1)) voice(.clk(clk),.rst_n(rst_n),.sample_ce(sample_ce),
   .note_on(launch&&selected==v),.zone(zone),.velocity(velocity),.bank(timbre),.bend(bend),.expression(expr),
   .spectral_test(spectral_test),.pcm(),.active(active_mask[v]),.shared_wave(waves[v]),.shared_env(envs[v]),.shared_gain(gains[v]));
 end endgenerate
 reg processing=0;reg [5:0] index=0;reg [2:0] valid=0,last=0;reg signed [21:0] prod1;reg [15:0] env1;
 reg signed [38:0] prod2;reg signed [15:0] voice_value;reg signed [21:0] accumulator;
 wire signed [21:0] addend={{6{voice_value[15]}},voice_value};wire signed [21:0] total=accumulator+addend;
 function signed [15:0] saturate(input signed [21:0] x);begin if(x>32767)saturate=32767;else if(x< -32768)saturate=-32768;else saturate=x[15:0];end endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin rd<=0;wr<=0;count<=0;next_voice<=0;selected<=0;launch<=0;zone<=0;velocity<=0;expr<=0;timbre<=0;overflow<=0;event_count<=0;
   processing<=0;index<=0;valid<=0;last<=0;prod1<=0;env1<=0;prod2<=0;voice_value<=0;accumulator<=0;pcm<=0;pcm_valid<=0;mix_sum<=0;
  end else begin
   launch<=0;pcm_valid<=0;
   if(event_valid&&!push)overflow<=1;
   if(push)begin queue[wr]<={bank,expression,event_zone,event_velocity};wr<=wr+1'b1;end
   if(pop)begin {timbre,expr,zone,velocity}<=queue[rd];rd<=rd+1'b1;selected<=next_voice;next_voice<=next_voice==VOICES-1?0:next_voice+1'b1;launch<=1;event_count<=event_count+1'b1;end
   case({push,pop})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:begin end endcase
   valid<={valid[1:0],processing};last<={last[1:0],processing&&(index==VOICES-1)};
   if(sample_ce)begin processing<=1;index<=0;accumulator<=0;end
   else if(processing)begin
    prod1<=waves[index]*$signed({1'b0,gains[index]});env1<=envs[index];
    if(index==VOICES-1)processing<=0;else index<=index+1'b1;
   end
   if(valid[0])prod2<=prod1*$signed({1'b0,env1});
   if(valid[1])voice_value<=prod2>>>24;
   if(valid[2])begin accumulator<=total;if(last[2])begin pcm<=saturate(total);mix_sum<=total;pcm_valid<=1;end end
  end
 end
endmodule
