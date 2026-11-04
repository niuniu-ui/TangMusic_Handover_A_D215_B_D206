// Two independent host bridges share the vendor command/data port. One read may
// be outstanding; write command and write data may handshake in either order.
// Record bridge has first preference; alternating ties prevent display starvation.
module studio_ddr_arbiter(
 input wire clk,rst_n,
 input wire [2:0] a_cmd,b_cmd,input wire a_cmd_en,b_cmd_en,
 input wire [28:0] a_addr,b_addr,input wire [255:0] a_data,b_data,
 input wire a_wr_en,b_wr_en,a_wr_end,b_wr_end,
 output wire a_cmd_ready,b_cmd_ready,a_wr_ready,b_wr_ready,
 output wire a_rd_valid,b_rd_valid,
 input wire cmd_ready,wr_ready,rd_valid,
 output wire [2:0] cmd,output wire cmd_en,output wire [28:0] addr,
 output wire [255:0] wr_data,output wire wr_en,wr_end
);
 reg active,owner,last_owner,command_done,data_done,is_read;
 wire command_fire=cmd_en&&cmd_ready;
 wire data_fire=wr_en&&wr_ready;
 assign cmd=owner?b_cmd:a_cmd;assign addr=owner?b_addr:a_addr;assign wr_data=owner?b_data:a_data;
 assign cmd_en=active&&!command_done&&(owner?b_cmd_en:a_cmd_en);
 assign wr_en=active&&!is_read&&!data_done&&(owner?b_wr_en:a_wr_en);
 assign wr_end=owner?b_wr_end:a_wr_end;
 assign a_cmd_ready=active&&!owner&&!command_done&&cmd_ready;
 assign b_cmd_ready=active&&owner&&!command_done&&cmd_ready;
 assign a_wr_ready=active&&!owner&&!is_read&&!data_done&&wr_ready;
 assign b_wr_ready=active&&owner&&!is_read&&!data_done&&wr_ready;
 // The clocked DDR controller responds after command acceptance, and each
 // bridge enters its receive state on that acceptance edge. Do not feed the
 // current command handshake combinationally back into 256 response enables.
 assign a_rd_valid=active&&!owner&&is_read&&command_done&&rd_valid;
 assign b_rd_valid=active&&owner&&is_read&&command_done&&rd_valid;
 always @(posedge clk)begin
  if(!rst_n)begin active<=0;owner<=0;last_owner<=1;command_done<=0;data_done<=0;is_read<=0;end
  else if(!active)begin
   if(a_cmd_en||b_cmd_en||a_wr_en||b_wr_en)begin
    active<=1;command_done<=0;data_done<=0;
    if((a_cmd_en||a_wr_en)&&(b_cmd_en||b_wr_en))begin owner<=!last_owner;is_read<=last_owner?a_cmd[0]:b_cmd[0];end
    else begin owner<=b_cmd_en||b_wr_en;is_read<=(b_cmd_en||b_wr_en)?b_cmd[0]:a_cmd[0];end
   end
  end else begin
   if(command_fire)command_done<=1;
   if(data_fire)data_done<=1;
   if(is_read)begin if(command_done&&rd_valid)begin active<=0;last_owner<=owner;end end
   else if((command_done||command_fire)&&(data_done||data_fire))begin active<=0;last_owner<=owner;end
  end
 end
endmodule
