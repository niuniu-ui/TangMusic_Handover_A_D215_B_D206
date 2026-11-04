// RTL8211F address 1. Enable TX delay; disable RX delay (board-tested).
// Register locations match upstream Linux Realtek PHY driver.
module phy_config #(parameter integer START_WAIT=1000000,POLL_WAIT=12500000)(
 input wire clk,rst_n,output wire mdc,inout wire mdio,
 output reg mdio_ok,config_done,link_up,output reg [1:0] speed);
reg start,read_op,pending;reg [4:0] reg_addr,seq;reg [15:0] write_data;
reg [31:0] wait_count;reg [15:0] id2,tx_control,rx_control;reg tx_delay_ok,delay_ok;
wire busy,done,error;wire [15:0] rd;
mdio_master bus(.clk(clk),.rst_n(rst_n),.start(start),.read_op(read_op),.phy_addr(5'd1),.reg_addr(reg_addr),.write_data(write_data),.busy(busy),.done(done),.error(error),.read_data(rd),.mdc(mdc),.mdio(mdio));
always @(posedge clk)begin
 if(!rst_n)begin
  start<=0;read_op<=0;pending<=0;reg_addr<=0;seq<=0;write_data<=0;wait_count<=START_WAIT;
  id2<=0;tx_control<=0;rx_control<=0;tx_delay_ok<=0;delay_ok<=0;mdio_ok<=0;config_done<=0;link_up<=0;speed<=0;
 end else begin
  start<=0;
  if(wait_count!=0)wait_count<=wait_count-1'b1;
  else if(!pending&&!busy&&!done)begin
   pending<=1;start<=1;read_op<=0;reg_addr<=31;write_data<=0;
   case(seq)
    0:begin reg_addr<=31;write_data<=0;end
    1:begin read_op<=1;reg_addr<=2;end
    2:begin read_op<=1;reg_addr<=3;end
    3:begin reg_addr<=31;write_data<=16'h0d08;end
    4:begin read_op<=1;reg_addr<=17;end
    5:begin reg_addr<=17;write_data<=tx_control|16'h0100;end
    6:begin read_op<=1;reg_addr<=21;end
    7:begin reg_addr<=21;write_data<=rx_control&~16'h0008;end
    8:begin read_op<=1;reg_addr<=17;end
    9:begin read_op<=1;reg_addr<=21;end
    10:begin reg_addr<=31;write_data<=0;end
    11,12:begin read_op<=1;reg_addr<=1;end
    13:begin read_op<=1;reg_addr<=26;end
    default:begin reg_addr<=31;write_data<=0;end
   endcase
  end
  if(done)begin
   pending<=0;
   if(error)begin seq<=0;wait_count<=POLL_WAIT;mdio_ok<=0;config_done<=0;link_up<=0;end
   else begin
    seq<=seq+1'b1;
    case(seq)
     1:id2<=rd;
     2:begin
      mdio_ok<=id2==16'h001c&&(rd&16'hfff0)==16'hc910;
      if(id2!=16'h001c||(rd&16'hfff0)!=16'hc910)begin seq<=0;wait_count<=POLL_WAIT;config_done<=0;end
     end
     4:tx_control<=rd;
     6:rx_control<=rd;
     8:tx_delay_ok<=rd[8];
     9:delay_ok<=tx_delay_ok&&!rd[3];
     12:link_up<=rd[2];
     13:begin speed<=rd[5:4];config_done<=mdio_ok&&delay_ok;seq<=10;wait_count<=POLL_WAIT;end
     default:begin end
    endcase
   end
  end
 end
end
endmodule
