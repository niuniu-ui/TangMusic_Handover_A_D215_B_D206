// Clause 22, full 32-bit preamble, 1 MHz MDC from 50 MHz.
module mdio_master #(parameter integer HALF=25)(
 input wire clk,rst_n,start,read_op,input wire [4:0] phy_addr,reg_addr,input wire [15:0] write_data,
 output reg busy,done,error,output reg [15:0] read_data,output reg mdc,inout wire mdio);
reg [63:0] frame;reg [6:0] bit_index;reg [7:0] divider;reg reading;
wire drive=busy&&(!reading||bit_index>=18);
assign mdio=drive?frame[bit_index]:1'bz;
always @(posedge clk)begin
 if(!rst_n)begin frame<=0;bit_index<=0;divider<=0;reading<=0;busy<=0;done<=0;error<=0;read_data<=0;mdc<=0;end
 else begin
  done<=0;
  if(!busy)begin
   mdc<=0;divider<=0;
   if(start)begin
    frame<={32'hffffffff,2'b01,(read_op?2'b10:2'b01),phy_addr,reg_addr,2'b10,write_data};
    reading<=read_op;bit_index<=63;busy<=1;error<=0;read_data<=0;
   end
  end else if(divider==HALF-1)begin
   divider<=0;mdc<=~mdc;
   if(!mdc)begin
    if(reading&&bit_index==16&&mdio!==1'b0)error<=1;
    if(reading&&bit_index<16)read_data[bit_index]<=mdio;
   end else begin
    if(bit_index==0)begin busy<=0;done<=1;end
    else bit_index<=bit_index-1'b1;
   end
  end else divider<=divider+1'b1;
 end
end
endmodule
