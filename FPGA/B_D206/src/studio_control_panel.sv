`timescale 1ns/1ps
// REV O: three quadrature encoders, five active-low buttons, 50 MHz clock.
// Input filters run independently of user reset so S4 can hold reset asserted.
module studio_control_panel #(
 parameter integer ENCODER_FILTER=12500, BUTTON_FILTER=250000
)(
 input wire clk,rst_n,input wire [2:0] enc_a,enc_b,
 input wire [4:0] switches_n,
 output wire reset_n,output reg event_valid,output reg [3:0] event_code,
 input wire event_ready
);
 (* syn_preserve=1 *) reg [10:0] meta=11'h7ff,sync=11'h7ff;
 reg [1:0] stable_enc[0:2];reg [4:0] stable_sw=5'b11111;
 reg [17:0] enc_count[0:2],sw_count[0:4];
 reg [1:0] previous[0:2];reg signed [3:0] quarter[0:2];
 reg signed [7:0] pending[0:2];reg [4:0] old_sw;
 reg [3:0] button_pending;
 integer i,choice;reg signed [2:0] delta;reg signed [8:0] next_pending;
 initial begin
  for(integer k=0;k<3;k=k+1)begin stable_enc[k]=3;enc_count[k]=0;end
  for(integer k=0;k<5;k=k+1)sw_count[k]=0;
 end
 assign reset_n=stable_sw[3];
 always @(posedge clk)begin
  meta<={switches_n,enc_b,enc_a};sync<=meta;
  for(integer k=0;k<3;k=k+1)begin
   if({sync[k],sync[k+3]}==stable_enc[k])enc_count[k]<=0;
   else if(enc_count[k]==ENCODER_FILTER-1)begin stable_enc[k]<={sync[k],sync[k+3]};enc_count[k]<=0;end
   else enc_count[k]<=enc_count[k]+1'b1;
  end
  for(integer k=0;k<5;k=k+1)begin
   if(sync[k+6]==stable_sw[k])sw_count[k]<=0;
   else if(sw_count[k]==BUTTON_FILTER-1)begin stable_sw[k]<=sync[k+6];sw_count[k]<=0;end
   else sw_count[k]<=sw_count[k]+1'b1;
  end
 end
 // A leading B: 11 -> 01 -> 00 -> 10 -> 11 increases volume.
 function signed [2:0] direction(input [3:0] transition);
  case(transition)
   4'b1101,4'b0100,4'b0010,4'b1011:direction=1;
   4'b1110,4'b1000,4'b0001,4'b0111:direction=-1;
   default:direction=0;
  endcase
 endfunction
 always @*begin
  event_valid=0;event_code=0;choice=-1;
  for(integer k=2;k>=0;k=k-1)if(pending[k]!=0)begin
   choice=k;event_valid=1;event_code=k*2+(pending[k]<0);
  end
  for(integer k=3;k>=0;k=k-1)if(button_pending[k])begin
   choice=3+k;event_valid=1;event_code=6+k;
  end
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   old_sw<=stable_sw;button_pending<=0;
   for(i=0;i<3;i=i+1)begin previous[i]<=stable_enc[i];quarter[i]<=0;pending[i]<=0;end
  end else begin
   old_sw<=stable_sw;
   // Set wins over consume if a new press arrives in the same clock.
   button_pending<=(button_pending & ~((event_valid&&event_ready&&choice>=3)?(4'b1<<(choice-3)):4'b0)) |
     {old_sw[4]&!stable_sw[4],old_sw[2]&!stable_sw[2],old_sw[1]&!stable_sw[1],old_sw[0]&!stable_sw[0]};
   for(i=0;i<3;i=i+1)begin
    next_pending=pending[i];
    if(event_valid&&event_ready&&choice==i)next_pending=next_pending+(pending[i]<0?1:-1);
    if(previous[i]!=stable_enc[i])begin
     previous[i]<=stable_enc[i];delta=direction({previous[i],stable_enc[i]});
     if(delta==0)quarter[i]<=0; // illegal two-bit jump never becomes a turn
     else if(quarter[i]+delta==4)begin quarter[i]<=0;next_pending=next_pending+1;end
     else if(quarter[i]+delta==-4)begin quarter[i]<=0;next_pending=next_pending-1;end
     else quarter[i]<=quarter[i]+delta;
    end
    if(next_pending>127)pending[i]<=127;
    else if(next_pending< -127)pending[i]<=-127;
    else pending[i]<=next_pending[7:0];
   end
  end
 end
endmodule
