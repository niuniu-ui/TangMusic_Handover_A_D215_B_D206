`timescale 1ns/1ps
// Inject CC64 only in a free event slot. Existing key events keep their cycle
// and order; each of the existing piano voices already implements CC64.
module studio_sustain_events #(parameter [3:0] CHANNEL=0)(
 input wire clk,rst_n,clear,pedal_down,
 input wire in_valid,input wire [3:0] in_kind,in_channel,
 input wire [6:0] in_key,in_value,
 output wire out_valid,output wire [3:0] out_kind,out_channel,
 output wire [6:0] out_key,out_value
);
 reg sent;
 wire send=rst_n&&!clear&&!in_valid&&(sent!=pedal_down);
 assign out_valid=in_valid||send;
 assign out_kind=send?4'hb:in_kind;
 assign out_channel=send?CHANNEL:in_channel;
 assign out_key=send?7'd64:in_key;
 assign out_value=send?(pedal_down?7'd127:7'd0):in_value;
 always @(posedge clk)begin
  if(!rst_n||clear)sent<=0;
  else if(in_valid&&in_channel==CHANNEL&&in_kind==11&&(in_key==120||in_key==121))sent<=0;
  else if(send)sent<=pedal_down;
 end
endmodule
