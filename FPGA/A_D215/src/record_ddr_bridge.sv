// One outstanding 32-byte transaction. Bundled payload remains stable until ack.
// At 32-bit DQ and BL8: byte address / 4 = controller address; block stride = 8.
// Writes are read back and compared before acknowledgement (not just queued).
module record_ddr_bridge #(parameter integer TIMEOUT=1000000)(
 input wire clk,rst_n,request,write_request,
 input wire [28:0] address,input wire [255:0] write_data,
 output wire ready,output reg done,output reg error,output reg [255:0] read_data,
 input wire mem_clk,calibrated,
 input wire cmd_ready,wr_data_rdy,rd_data_valid,
 input wire [255:0] rd_data,
 output wire [2:0] cmd,output wire cmd_en,
 output wire [28:0] addr,output wire [255:0] wr_data,
 output wire wr_data_en,wr_data_end
);
 reg req_toggle; reg [28:0] held_addr; reg [255:0] held_data; reg held_write;
 reg ack_toggle,ack_error; reg [255:0] response;
 (* syn_preserve=1 *) reg [1:0] ack_sync,req_sync,cal_sync,mem_reset;
 reg busy,seen_ack; reg [31:0] host_timer;
 assign ready=!busy && cal_sync[1] && !error;
 always @(posedge clk) begin
  if(!rst_n) begin
   req_toggle<=0;held_addr<=0;held_data<=0;held_write<=0;
   ack_sync<=0;cal_sync<=0;busy<=0;seen_ack<=0;done<=0;error<=0;read_data<=0;host_timer<=0;
  end else begin
   ack_sync<={ack_sync[0],ack_toggle}; cal_sync<={cal_sync[0],calibrated};done<=0;
   if(request && ready) begin
    held_addr<=address;held_data<=write_data;held_write<=write_request;
    req_toggle<=~req_toggle;busy<=1;host_timer<=0;
   end
   if(busy) begin
    host_timer<=host_timer+1'b1;
    if(ack_sync[1]!=seen_ack) begin
     read_data<=response;error<=ack_error;seen_ack<=ack_sync[1];done<=1;busy<=0;
    end else if(host_timer==TIMEOUT-1 || !cal_sync[1]) begin
     // Sticky fault; only global reset can reuse a timed-out mailbox safely.
     error<=1;done<=1;busy<=0;
    end
   end
  end
 end
 always @(posedge mem_clk or negedge rst_n)
  if(!rst_n)mem_reset<=0;else mem_reset<={mem_reset[0],1'b1};
 reg [2:0] state;
 reg command_sent,data_sent,verify_write;
 reg [7:0] compare_bad;integer lane;
 reg [28:0] mem_addr;reg [255:0] mem_data;
 reg [31:0] mem_timer;
 assign cmd=state==1 ? 3'b000 : 3'b001;
 assign cmd_en=calibrated && ((state==1 && !command_sent) || state==2);
 assign addr=mem_addr;assign wr_data=mem_data;
 assign wr_data_en=calibrated && state==1 && !data_sent;
 assign wr_data_end=wr_data_en;
 always @(posedge mem_clk) begin
  if(!mem_reset[1]) begin
   req_sync<=0;ack_toggle<=0;ack_error<=0;response<=0;state<=0;
   command_sent<=0;data_sent<=0;mem_addr<=0;mem_data<=0;verify_write<=0;mem_timer<=0;compare_bad<=0;
  end else begin
   req_sync<={req_sync[0],req_toggle};
   if(state==0) begin
    mem_timer<=0;
    if(calibrated && req_sync[1]!=ack_toggle) begin
     mem_addr<=held_addr;mem_data<=held_data;verify_write<=held_write;
     command_sent<=0;data_sent<=0;ack_error<=0;state<=held_write?1:2;
    end
   end else begin
    mem_timer<=mem_timer+1'b1;
    case(state)
     1: begin
      if(cmd_en && cmd_ready)command_sent<=1;
      if(wr_data_en && wr_data_rdy)data_sent<=1;
      if((command_sent||cmd_ready)&&(data_sent||wr_data_rdy))state<=2;
     end
     2: if(cmd_ready)state<=3;
     3: if(rd_data_valid) begin
      response<=rd_data;
      // Bound carry-chain length: eight registered 32-bit comparisons.
      for(lane=0;lane<8;lane=lane+1)
       compare_bad[lane]<=rd_data[lane*32 +:32]!=mem_data[lane*32 +:32];
      state<=6;
     end
     6: begin ack_error<=verify_write&&(|compare_bad);state<=4;end
     4: begin ack_toggle<=req_sync[1];state<=0;end
     default: state<=0;
    endcase
    if(state!=4 && (mem_timer==TIMEOUT-1 || !calibrated)) begin ack_error<=1;state<=4;end
   end
  end
 end
endmodule
