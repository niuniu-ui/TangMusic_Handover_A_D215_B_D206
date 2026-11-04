`timescale 1ns/1ps
// The output becomes valid only after enabled synchronous RAM reads settle.
// Count includes the prefetched head. The memory output holds while stalled.
module tmcp_sync_fifo(
 input wire clk,rst_n,clear,write_valid,input wire [7:0] write_data,
 input wire read_ready,output reg read_valid,output wire [7:0] read_data,
 output reg overflow_pulse,overflow_sticky,output reg [9:0] count
);
 reg [8:0] wr,rd;reg [1:0] read_wait;
 reg [7:0] memory[0:511] /* synthesis syn_ramstyle = "block_ram" */;
 reg [7:0] memory_out;
 wire push=write_valid&&count<512;
 wire pop=read_valid&&read_ready;
 wire start_read=!read_valid&&read_wait==0&&count!=0;
 wire memory_enable=start_read||read_wait!=0;
 wire active=rst_n&&!clear&&!overflow_pulse;
 assign read_data=memory_out;
 // Shared clock, one write port and one explicitly enabled clocked read port.
 // No read/write collision: empty writes are read on a later cycle, and the
 // prefetched head stays counted until pop, so full memory cannot overwrite it.
 always @(posedge clk)begin
  if(active&&push)memory[wr]<=write_data;
  if(active&&memory_enable)memory_out<=memory[rd];
 end
 always @(posedge clk)begin
  overflow_pulse<=0;
  if(!rst_n)begin
   wr<=0;rd<=0;count<=0;read_valid<=0;read_wait<=0;
   overflow_pulse<=0;overflow_sticky<=0;
  end else if(clear||overflow_pulse)begin
   wr<=0;rd<=0;count<=0;read_valid<=0;read_wait<=0;
  end else begin
   if(push)wr<=wr+1'b1;
   if(pop)begin rd<=rd+1'b1;read_valid<=0;end
   case({push,pop})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:begin end endcase
   if(start_read)read_wait<=3;
   else if(read_wait!=0)begin
    read_wait<=read_wait-1'b1;
    if(read_wait==1)read_valid<=1;
   end
   if(write_valid&&count==512)begin overflow_pulse<=1;overflow_sticky<=1;end
  end
 end
endmodule
