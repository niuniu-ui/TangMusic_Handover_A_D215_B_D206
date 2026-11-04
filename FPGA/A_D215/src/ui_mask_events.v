`timescale 1ns/1ps
module ui_mask_events #(parameter N=32)(
 input wire clk,rst_n,flush,input wire [N-1:0] desired,
 output wire valid,input wire ready,output wire [3:0] kind,
 output wire [6:0] note,value
);
 reg [N-1:0] sent;reg queued,on;reg [5:0] index;
 reg found,next_on;reg [5:0] next_index;integer i;
 always @* begin
  found=0;next_on=0;next_index=0;
  for(i=0;i<N;i=i+1)if(!found&&sent[i]&&!desired[i])begin found=1;next_index=i;end
  for(i=0;i<N;i=i+1)if(!found&&!sent[i]&&desired[i])begin found=1;next_index=i;next_on=1;end
 end
 assign valid=queued&&rst_n&&!flush&&(on==desired[index]);
 assign kind=on?4'h9:4'h8;assign value=on?7'd100:7'd0;
 assign note=7'd41+index;
 always @(posedge clk)begin
  if(!rst_n||flush)begin sent<=0;queued<=0;on<=0;index<=0;end
  else if(queued&&on!=desired[index])queued<=0;
  else if(valid&&ready)begin sent[index]<=on;queued<=0;end
  else if(!queued&&found)begin queued<=1;on<=next_on;index<=next_index;end
 end
endmodule
