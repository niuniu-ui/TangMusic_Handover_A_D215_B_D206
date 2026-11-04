// Register the change detector in 16-bit groups to keep the USB-ready and
// local-touch filter signals out of one long 274-bit compare/reduction path.
// The 40 ns delay affects only the optional early-send hint; the payload itself
// remains a coherent snapshot and periodic frames continue unchanged.
module studio_touch_urgent(
 input wire clk,rst_n,input wire [273:0] touch,
 output reg urgent
);
 reg [287:0] previous;
 (* syn_keep=1, syn_preserve=1 *) reg [17:0] changed;
 wire [287:0] current={14'd0,touch};
 integer i;
 always @(posedge clk)begin
  if(!rst_n)begin previous<=0;changed<=0;urgent<=0;end
  else begin
   previous<=current;
   for(i=0;i<18;i=i+1)changed[i]<=|(current[i*16+:16]^previous[i*16+:16]);
   urgent<=|changed;
  end
 end
endmodule
