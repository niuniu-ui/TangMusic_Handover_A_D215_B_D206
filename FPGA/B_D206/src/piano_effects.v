`timescale 1ns/1ps
// Piano-only mono processor, 48828.125 samples/s. Chorus -> echo -> reverb.
// All RAMs and arithmetic run at 50 MHz; one sample takes fewer than 100 clocks.
// All effects off is a combinational bit-exact bypass of the original piano.
module piano_effects(
 input wire clk,rst_n,clear,sample_tick,
 input wire signed [15:0] pcm_in,input wire [2:0] enabled,
 input wire [62:0] parameters,
 output wire signed [15:0] pcm_out,output reg ready,frame_done
);
 `include "src/fx_audio_params.vh"
 reg [6:0] state;
 reg clearing,bypass;reg [15:0] clear_addr;
 reg [15:0] delay_ptr,delay_age;reg [10:0] chorus_ptr,chorus_age,rev_ptr,rev_age;
 reg [8:0] mix_reverb,mix_delay,mix_chorus;
 reg [15:0] feedback_gain,depth_gain;
 reg [15:0] delay_current,delay_previous;reg [8:0] delay_fade;
 reg [31:0] lfo_phase;
 reg [10:0] comb_length[0:3];reg [8:0] ap_length[0:1];
 reg [17:0] decay_factor;
 reg signed [15:0] dry,chorus_result,delay_result,processed;
 reg signed [15:0] sine_base,sine_value,ca0,ca1,cb0,cb1,interp_a,interp_b,chorus_wet;
 reg signed [15:0] delay_a,delay_b,delay_wet,reverb_wet;
 reg signed [37:0] product;
 reg signed [32:0] modulation_product;
 reg [28:0] gain_product;
 reg [18:0] tap_a,tap_b;
 reg [1:0] comb_index;reg ap_index;
 reg signed [19:0] comb_delayed,ap_input,ap_delayed,ap_output;
 reg signed [21:0] comb_sum;
 reg [15:0] comb_gain;
 reg cw,dw,rw,aw;
 reg [10:0] cwa,cra;reg [15:0] dwa,dra;reg [12:0] rwa,rra;reg [9:0] awa,ara;
 reg signed [15:0] cwd,dwd;reg signed [19:0] rwd,awd;
 wire signed [15:0] crd,drd;wire signed [19:0] rrd,ard;
 wire initialize=clearing&&rst_n&&!clear;
 fx_sample_ram #(.AW(11),.DW(16)) chorus_ram(.clk(clk),.we(initialize||cw),
  .write_addr(initialize?clear_addr[10:0]:cwa),.write_data(initialize?16'sd0:cwd),.read_addr(cra),.read_data(crd));
 fx_sample_ram #(.AW(16),.DW(16)) delay_ram(.clk(clk),.we(initialize||dw),
  .write_addr(initialize?clear_addr:dwa),.write_data(initialize?16'sd0:dwd),.read_addr(dra),.read_data(drd));
 fx_sample_ram #(.AW(13),.DW(20)) comb_ram(.clk(clk),.we(initialize||rw),
  .write_addr(initialize?clear_addr[12:0]:rwa),.write_data(initialize?20'sd0:rwd),.read_addr(rra),.read_data(rrd));
 fx_sample_ram #(.AW(10),.DW(20)) allpass_ram(.clk(clk),.we(initialize||aw),
  .write_addr(initialize?clear_addr[9:0]:awa),.write_data(initialize?20'sd0:awd),.read_addr(ara),.read_data(ard));
 assign pcm_out=(!ready||bypass)?pcm_in:processed;
 function signed [15:0] sat16;input signed [37:0] a;begin
  sat16=a>32767?16'sh7fff:a< -32768?16'sh8000:a[15:0];end endfunction
 function signed [19:0] sat20;input signed [37:0] a;begin
  sat20=a>524287?20'sh7ffff:a< -524288?20'sh80000:a[19:0];end endfunction
 function [8:0] ramp_mix;input [8:0] a,b;begin ramp_mix=a<b?a+1'b1:a>b?a-1'b1:a;end endfunction
 function [15:0] ramp64;input [15:0] a,b;begin
  if(a<b)ramp64=b-a>64?a+16'd64:b;
  else ramp64=a-b>64?a-16'd64:b;
 end endfunction
 function signed [22:0] feedback_trunc;input signed [37:0] p;begin
  feedback_trunc=(p>>>15)+(p[37]&&(|p[14:0])?23'sd1:23'sd0);
 end endfunction
 function signed [19:0] half;input signed [19:0] a;begin
  half=(a>>>1)+(a[19]&&a[0]?20'sd1:20'sd0);
 end endfunction
 wire signed [15:0] lfo_base=fx_lfo_sine(lfo_phase[31:24]);
 wire signed [15:0] lfo_next=fx_lfo_sine(lfo_phase[31:24]+8'd1);
 wire [15:0] requested_delay=fx_delay_samples(parameters[27:21]);
 wire [8:0] target_reverb=enabled[0]?fx_mix_q8(parameters[20:14]):9'd0;
 wire [8:0] target_delay=enabled[1]?fx_mix_q8(parameters[41:35]):9'd0;
 wire [8:0] target_chorus=enabled[2]?fx_mix_q8(parameters[62:56]):9'd0;
 wire chorus_running=enabled[2]||mix_chorus!=0;
 wire delay_running=enabled[1]||mix_delay!=0;
 wire reverb_running=enabled[0]||mix_reverb!=0;
 wire [10:0] chorus_addr_a=chorus_ptr-tap_a[18:8];
 wire [10:0] chorus_addr_b=chorus_ptr-tap_b[18:8];
 wire [10:0] comb_addr=rev_ptr-comb_length[comb_index];
 wire [8:0] ap_addr=rev_ptr[8:0]-ap_length[ap_index];
 integer i;
 always @(posedge clk)begin
  cw<=0;dw<=0;rw<=0;aw<=0;frame_done<=0;
  if(!rst_n||clear)begin
   state<=0;clearing<=1;clear_addr<=0;ready<=0;bypass<=1;
   chorus_ptr<=0;delay_ptr<=0;rev_ptr<=0;chorus_age<=0;delay_age<=0;rev_age<=0;
   mix_reverb<=0;mix_delay<=0;mix_chorus<=0;feedback_gain<=0;depth_gain<=0;
   delay_current<=17090;delay_previous<=17090;delay_fade<=256;lfo_phase<=0;
   dry<=0;processed<=0;chorus_result<=0;delay_result<=0;
   cra<=0;dra<=0;rra<=0;ara<=0;cwa<=0;dwa<=0;rwa<=0;awa<=0;
   cwd<=0;dwd<=0;rwd<=0;awd<=0;product<=0;modulation_product<=0;gain_product<=0;
   tap_a<=19'd250112;tap_b<=19'd250112;comb_index<=0;ap_index<=0;decay_factor<=0;
   for(i=0;i<4;i=i+1)comb_length[i]<=fx_room_length({i[1:0],7'd70});
   for(i=0;i<2;i=i+1)ap_length[i]<=fx_allpass_length({i[0],7'd70});
  end else if(clearing)begin
   if(clear_addr==65535)begin clearing<=0;ready<=1;end else clear_addr<=clear_addr+1'b1;
  end else case(state)
   0:if(sample_tick)state<=1;
   // The piano's phase/envelope products settle after its sample strobe.
   1:state<=2;
   2:state<=3;
   3:begin dry<=pcm_in;state<=4;end
   4:begin
    // Register the next zero-mix state alongside the ramps. This is exactly
    // ramp_mix(a,b)==0, without putting ramp logic in the DAC data path.
    bypass<=target_reverb==0&&target_delay==0&&target_chorus==0&&
            mix_reverb<=1&&mix_delay<=1&&mix_chorus<=1;
    mix_reverb<=ramp_mix(mix_reverb,target_reverb);mix_delay<=ramp_mix(mix_delay,target_delay);mix_chorus<=ramp_mix(mix_chorus,target_chorus);
    feedback_gain<=ramp64(feedback_gain,fx_feedback_q15(parameters[34:28]));
    depth_gain<=ramp64(depth_gain,fx_depth_q8(parameters[55:49]));
    decay_factor<=fx_decay_factor(parameters[13:7]);
    for(i=0;i<4;i=i+1)begin
     if(comb_length[i]<fx_room_length({i[1:0],parameters[6:0]}))comb_length[i]<=comb_length[i]+1'b1;
     else if(comb_length[i]>fx_room_length({i[1:0],parameters[6:0]}))comb_length[i]<=comb_length[i]-1'b1;
    end
    for(i=0;i<2;i=i+1)ap_length[i]<=fx_allpass_length({i[0],parameters[6:0]});
    if(delay_fade==256&&delay_current!=requested_delay)begin delay_previous<=delay_current;delay_current<=requested_delay;delay_fade<=0;end
    else if(delay_fade<256)delay_fade<=delay_fade+1'b1;
    sine_base<=fx_lfo_sine(lfo_phase[31:24]);
    product<=($signed({lfo_next[15],lfo_next})-$signed({lfo_base[15],lfo_base}))*$signed({1'b0,lfo_phase[23:16]});
    lfo_phase<=lfo_phase+fx_lfo_step(parameters[48:42]);state<=5;
   end
   5:begin sine_value<=sine_base+(product>>>8);state<=6;end
   6:begin modulation_product<=sine_value*$signed({1'b0,depth_gain});state<=7;end
   7:begin tap_a<=33'sd250112+(modulation_product>>>15);tap_b<=33'sd250112-(modulation_product>>>15);state<=8;end
   8:begin cwa<=chorus_ptr;cwd<=chorus_running?dry:16'sd0;cw<=1;cra<=chorus_addr_a;state<=9;end
   9:state<=10;
   10:begin ca0<=chorus_age>=tap_a[18:8]?crd:16'sd0;cra<=chorus_addr_a-1'b1;state<=11;end
   11:state<=12;
   12:begin ca1<=chorus_age>{1'b0,tap_a[18:8]}?crd:16'sd0;cra<=chorus_addr_b;state<=13;end
   13:state<=14;
   14:begin cb0<=chorus_age>=tap_b[18:8]?crd:16'sd0;cra<=chorus_addr_b-1'b1;state<=15;end
   15:state<=16;
   16:begin cb1<=chorus_age>{1'b0,tap_b[18:8]}?crd:16'sd0;product<=($signed({ca1[15],ca1})-$signed({ca0[15],ca0}))*$signed({1'b0,tap_a[7:0]});state<=17;end
   17:begin interp_a<=ca0+(product>>>8);product<=($signed({cb1[15],cb1})-$signed({cb0[15],cb0}))*$signed({1'b0,tap_b[7:0]});state<=18;end
   18:begin interp_b<=cb0+(product>>>8);state<=19;end
   19:begin chorus_wet<=($signed({interp_a[15],interp_a})+$signed({interp_b[15],interp_b}))>>>1;state<=20;end
   20:begin product<=($signed({chorus_wet[15],chorus_wet})-$signed({dry[15],dry}))*$signed({1'b0,mix_chorus});state<=21;end
   21:begin chorus_result<=sat16(dry+(product>>>8));state<=22;end
   22:begin dra<=delay_ptr-delay_current;state<=23;end
   23:state<=24;
   24:begin delay_a<=delay_age>=delay_current?drd:16'sd0;dra<=delay_ptr-delay_previous;state<=25;end
   25:state<=26;
   26:begin delay_b<=delay_age>=delay_previous?drd:16'sd0;state<=27;end
   27:begin product<=($signed({delay_a[15],delay_a})-$signed({delay_b[15],delay_b}))*$signed({1'b0,delay_fade});state<=28;end
   28:begin delay_wet<=delay_b+(product>>>8);state<=29;end
   29:begin product<=delay_wet*$signed({1'b0,feedback_gain});state<=30;end
   30:begin
    dwa<=delay_ptr;dwd<=delay_running?sat16(chorus_result+feedback_trunc(product)):16'sd0;dw<=1;
    product<=($signed({delay_wet[15],delay_wet})-$signed({chorus_result[15],chorus_result}))*$signed({1'b0,mix_delay});state<=31;
   end
   31:begin delay_result<=sat16(chorus_result+(product>>>8));comb_index<=0;comb_sum<=0;state<=32;end
   32:begin rra<={comb_index,comb_addr};state<=33;end
   33:state<=34;
   34:begin comb_delayed<=rev_age>=comb_length[comb_index]?rrd:20'sd0;gain_product<=comb_length[comb_index]*decay_factor;state<=35;end
   35:begin comb_gain<=fx_rt60_gain(gain_product[28:20]+{8'b0,gain_product[19]});state<=36;end
   36:begin product<=comb_delayed*$signed({1'b0,comb_gain});state<=37;end
   37:begin
    rwa<={comb_index,rev_ptr};rwd<=reverb_running?sat20(($signed(delay_result)>>>2)+feedback_trunc(product)):20'sd0;rw<=1;
    comb_sum<=comb_sum+comb_delayed;
    if(comb_index==3)state<=38;else begin comb_index<=comb_index+1'b1;state<=32;end
   end
   38:begin ap_input<=sat20(comb_sum);ap_index<=0;state<=39;end
   39:begin ara<={ap_index,ap_addr};state<=40;end
   40:state<=41;
   41:begin ap_delayed<=rev_age>=ap_length[ap_index]?ard:20'sd0;state<=42;end
   42:begin ap_output<=sat20($signed({ap_delayed[19],ap_delayed})-half(ap_input));state<=43;end
   43:begin
    awa<={ap_index,rev_ptr[8:0]};awd<=reverb_running?sat20($signed({ap_input[19],ap_input})+half(ap_output)):20'sd0;aw<=1;
    if(ap_index)state<=44;else begin ap_input<=ap_output;ap_index<=1;state<=39;end
   end
   44:begin reverb_wet<=sat16(ap_output);state<=45;end
   45:begin product<=($signed({reverb_wet[15],reverb_wet})-$signed({delay_result[15],delay_result}))*$signed({1'b0,mix_reverb});state<=46;end
   46:begin
    processed<=sat16(delay_result+(product>>>8));frame_done<=1;state<=0;
    delay_ptr<=delay_ptr+1'b1;chorus_ptr<=chorus_ptr+1'b1;rev_ptr<=rev_ptr+1'b1;
    if(!delay_running)delay_age<=0;else if(delay_age!=65535)delay_age<=delay_age+1'b1;
    if(!chorus_running)chorus_age<=0;else if(chorus_age!=2047)chorus_age<=chorus_age+1'b1;
    if(!reverb_running)rev_age<=0;else if(rev_age!=2047)rev_age<=rev_age+1'b1;
   end
   default:state<=0;
  endcase
 end
endmodule
