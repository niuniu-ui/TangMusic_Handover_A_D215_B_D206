// Resolve whole/half-cycle DDR byte pairing using the Ethernet SFD.
// PHY/FPCB clock delay can make the captured rising sample the upper nibble.
// Mode is frozen for each frame; eth_rx still checks the full peer frame/FCS.
module rgmii_byte_align(input wire clk,rst_n,input wire [3:0] low,high,
 input wire ctl_rise,ctl_fall,output reg [7:0] data,output reg valid,error,output reg mode);
reg [3:0] previous_high;reg previous_fall,locked;reg [3:0] pre0,pre1;
wire [7:0] byte0={high,low};
wire [7:0] byte1={low,previous_high};
wire valid0=ctl_rise,valid1=previous_fall;
wire error0=ctl_rise^ctl_fall,error1=ctl_rise^previous_fall;
wire hit0=valid0&&!error0&&byte0==8'hd5&&pre0>=3;
wire hit1=valid1&&!error1&&byte1==8'hd5&&pre1>=3;
wire selected=locked?mode:hit0?1'b0:hit1?1'b1:mode;
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin previous_high<=0;previous_fall<=0;locked<=0;pre0<=0;pre1<=0;data<=0;valid<=0;error<=0;mode<=0;end
 else begin
  previous_high<=high;previous_fall<=ctl_fall;
  data<=selected?byte1:byte0;valid<=selected?valid1:valid0;error<=selected?error1:error0;
  if(!locked)begin
   if(valid0&&byte0==8'h55)begin if(pre0<7)pre0<=pre0+1'b1;end else pre0<=0;
   if(valid1&&byte1==8'h55)begin if(pre1<7)pre1<=pre1+1'b1;end else pre1<=0;
   if(hit0||hit1)begin locked<=1;mode<=selected;pre0<=0;pre1<=0;end
  end else if(!(mode?valid1:valid0))begin locked<=0;pre0<=0;pre1<=0;end
 end
end
endmodule
