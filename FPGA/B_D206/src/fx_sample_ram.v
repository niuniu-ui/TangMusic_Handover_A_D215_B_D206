`timescale 1ns/1ps
// Synchronous simple dual-port sample history. Reset is implemented by the
// caller's sequential write sweep, so Gowin can infer block RAM.
module fx_sample_ram #(parameter AW=11, DW=16)(
 input wire clk,we,input wire [AW-1:0] write_addr,read_addr,
 input wire signed [DW-1:0] write_data,output reg signed [DW-1:0] read_data
);
 (* syn_ramstyle="block_ram" *) reg signed [DW-1:0] memory[0:(1<<AW)-1];
 always @(posedge clk)begin
  if(we)memory[write_addr]<=write_data;
  read_data<=memory[read_addr];
 end
endmodule
