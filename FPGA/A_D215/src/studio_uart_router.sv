// Packet ownership is held across byte gaps: TMCP and recording replies cannot interleave.
module studio_uart_router #(parameter integer CLK_HZ=50000000,BAUD=921600)(
 input wire clk,rst_n,uart_rx,disconnect,output wire uart_tx,
 output wire [7:0] rx_data,output wire rx_error,
 output wire control_rx_valid,record_rx_valid,
 input wire [7:0] control_tx_data,record_tx_data,
 input wire control_tx_valid,record_tx_valid,
 output wire control_tx_ready,record_tx_ready
);
 wire rx_valid,uart_ready;wire [7:0] tx_data;wire tx_valid;
 uart_rx_8n1 #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) rx(.clk(clk),.rst_n(rst_n),.rx(uart_rx),.data(rx_data),.valid(rx_valid),.frame_error(rx_error));
 air_uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) tx(.clk(clk),.rst_n(rst_n),.tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(uart_ready),.tx(uart_tx),.tx_done());
 reg rx_owned,rx_record;reg [8:0] rx_index;reg [9:0] rx_length;reg [7:0] rx_low;
 reg [31:0] rx_timeout;
 wire bad_header=rx_owned&&((!rx_record&&rx_index==1&&rx_data!=8'h4d)||
  (rx_record&&((rx_index==1&&rx_data!=8'h52)||(rx_index==2&&rx_data!=8'h51)||(rx_index==3&&rx_data!=8'h31))));
 wire first_control=(!rx_owned||bad_header)&&rx_data==8'h54;
 wire first_record=(!rx_owned||bad_header)&&rx_data==8'h50;
 assign control_rx_valid=rx_valid&&((rx_owned&&!bad_header&&!rx_record)||first_control);
 assign record_rx_valid=rx_valid&&((rx_owned&&!bad_header&&rx_record)||first_record);
 reg tx_owned,tx_record,last_owner;
 reg [8:0] tx_index;reg [9:0] tx_length;reg [7:0] tx_low;
 reg [31:0] tx_stall;
 wire choose_record=tx_owned?tx_record:(record_tx_valid&&(!control_tx_valid||!last_owner));
 assign tx_data=choose_record?record_tx_data:control_tx_data;
 assign tx_valid=choose_record?record_tx_valid:control_tx_valid;
 assign control_tx_ready=uart_ready&&!choose_record;
 assign record_tx_ready=uart_ready&&choose_record;
 always @(posedge clk)begin
  if(!rst_n)begin
   rx_owned<=0;rx_record<=0;rx_index<=0;rx_length<=0;rx_low<=0;rx_timeout<=0;
   tx_owned<=0;tx_record<=0;last_owner<=1;tx_index<=0;tx_length<=0;tx_low<=0;tx_stall<=0;
  end else begin
   if(rx_owned)begin
    if(rx_timeout<CLK_HZ/5)rx_timeout<=rx_timeout+1'b1;
    else rx_owned<=0;
   end
   if(rx_valid)begin
    rx_timeout<=0;
    if(!rx_owned||bad_header)begin
     rx_owned<=0;
     if(first_control||first_record)begin rx_owned<=1;rx_record<=first_record;rx_index<=1;rx_length<=first_record?20:16;end
    end else begin
     if(!rx_record&&rx_index==12)rx_low<=rx_data;
     if(!rx_record&&rx_index==13)begin
      if({rx_data,rx_low}>256)rx_owned<=0;
      else rx_length<=16+{rx_data,rx_low};
     end
     if(rx_index==rx_length-1)rx_owned<=0;
     rx_index<=rx_index+1'b1;
    end
   end
   if(rx_error||disconnect)rx_owned<=0;
   if(tx_valid&&uart_ready)begin
    tx_stall<=0;
    if(!tx_owned)begin tx_owned<=1;tx_record<=choose_record;tx_index<=1;tx_length<=choose_record?24:16;end
    else begin
     if(tx_index==(tx_record?16:12))tx_low<=tx_data;
     if(tx_index==(tx_record?17:13))tx_length<=(tx_record?24:16)+{tx_data,tx_low};
     if(tx_index==tx_length-1)begin tx_owned<=0;last_owner<=tx_record;end
     tx_index<=tx_index+1'b1;
    end
   end else if(tx_owned)begin
    if(tx_stall>=CLK_HZ/500)begin tx_owned<=0;tx_stall<=0;end
    else tx_stall<=tx_stall+1'b1;
   end else tx_stall<=0;
   // TMCP intentionally aborts a reply on disconnect or malformed UART input.
   // The recording sender drains its current frame instead; never truncate it.
   if((disconnect||rx_error)&&tx_owned&&!tx_record)begin tx_owned<=0;tx_stall<=0;end
  end
 end
endmodule
