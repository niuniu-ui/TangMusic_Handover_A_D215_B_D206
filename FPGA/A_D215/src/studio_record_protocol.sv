// PRB1 bounded phone recorder transport; deliberately distinct from TMCP.
// Requests: PRQ1, command:u8, 0:u8, seq:u16, arg:u32, take:u32, CRC32:u32.
// Replies: PRS1, command:u8, status:u8, seq:u16, arg:u32, take:u32,
//          body_length:u16, 0:u16, body[0..192], CRC32 over header+body.
// A single outstanding request. Exact duplicates replay the cached response.
module studio_record_protocol #(parameter integer CLK_HZ=50000000, BAUD=921600,
 parameter integer MAX_SAMPLES=5859375)(
 input wire clk,rst_n,disconnect,
 input wire [7:0] rx_data,input wire rx_valid,rx_error,
 output wire [7:0] tx_data,output wire tx_valid,input wire tx_ready,
 input wire selected,lease,saved_on_phone,input wire [3:0] other_state,
 input wire [31:0] committed_samples,other_samples,other_take,confirmed_bytes,
 output reg select_valid,select_slot,lease_open,lease_close,save_ack,progress_ack,
 output wire [31:0] ack_value,output wire transport_busy,protocol_busy,
 input wire [3:0] state,input wire [7:0] fault,input wire mem_ready,
 input wire [31:0] sample_count,pcm_crc,keys_down,take_id,input wire [15:0] peak,
 output reg start_record,stop_record,erase_record,start_play,stop_play,
 output reg download_request,output reg [31:0] download_offset,
 input wire download_done,input wire [255:0] download_data,input wire [5:0] download_bytes
);
 localparam IDLE=0,CHECK=1,EXEC=2,SETTLE=3,STATUS=4,READ_REQ=5,READ_WAIT=6,COPY=7,CRC=8,SEND=9,NEXT_BURST=10,VALIDATE=11,HEADER=12,BODY=13,TRAILER=14,CRC_WAIT=15;
 reg burst_active;reg [4:0] burst_left;reg [7:0] burst_gap_ms;
 reg [31:0] packet_wait,rx_framing_errors,rx_crc_errors,busy_rx_bytes;
 reg [3:0] mode;reg [159:0] request;reg [127:0] previous_request;
 reg cache_valid;reg [7:0] index,body_length,tx_length;
 reg [159:0] frame_header;reg [511:0] status_snapshot;reg status_body;
 // One write port and synchronous read port infer a real packet RAM. Header
 // and status are serialized into it; a cached reply includes its exact CRC.
 (* syn_ramstyle="block_ram" *) reg [7:0] bytes_out[0:255];
 reg [7:0] packet_q;
 reg [31:0] crc,watchdog;reg [15:0] gap;
 reg [255:0] block_data;reg [5:0] block_bytes,block_index;
 reg [7:0] copied,target_bytes;reg [31:0] origin;
 wire [7:0] command=request[39:32];wire [31:0] argument=request[95:64];
 wire [31:0] expected_take=request[127:96];wire [31:0] total_bytes=sample_count<<1;
 wire sending=mode==SEND && gap==0;
 wire [31:0] final_crc=~crc;
 assign tx_data=packet_q;assign tx_valid=sending;
 assign ack_value=argument;
 assign protocol_busy=mode!=IDLE;
 assign transport_busy=mode!=IDLE && (command==7||command==8);
 reg [31:0] last_take;reg last_selected,abort_transfer,session_ready;reg [2:0] settle_cycles;
 // Split unsigned range checks into registered byte comparisons. The old
 // selected-slot mux -> 32-bit compare -> command/action enable path exceeded
 // 20 ns. Recheck the snapshot before acting so concurrent UI changes cannot
 // authorize a command using stale count/CRC/progress information.
 reg [31:0] checked_take,checked_count,checked_confirmed,checked_crc,remaining_bytes;
 reg [3:0] total_gt,total_eq,confirmed_gt,confirmed_eq;
 reg crc_matches;integer compare_byte;
 function ge_chunks;input [3:0] gt,eq;begin
  ge_chunks=gt[3]||(eq[3]&&gt[2])||(eq[3]&&eq[2]&&gt[1])||
            (eq[3]&&eq[2]&&eq[1]&&gt[0])||(&eq);
 end endfunction
 wire argument_ge_total=ge_chunks(total_gt,total_eq);
 wire argument_le_total=!argument_ge_total||(&total_eq);
 wire argument_ge_confirmed=ge_chunks(confirmed_gt,confirmed_eq);
 wire validation_changed=checked_take!=take_id||checked_count!=sample_count||
                         checked_confirmed!=confirmed_bytes||checked_crc!=pcm_crc;
 wire packet_we=rst_n&&(mode==HEADER||mode==BODY||mode==COPY||mode==TRAILER);
 wire [7:0] packet_write_address=mode==HEADER?index:mode==BODY?8'd20+index:
  mode==COPY?8'd20+copied+block_index:8'd20+body_length+index;
 wire [7:0] packet_write_data=mode==HEADER?frame_header[index*8+:8]:
  mode==BODY?status_snapshot[index*8+:8]:mode==COPY?block_data[block_index*8+:8]:final_crc[index*8+:8];
 always @(posedge clk)begin
  if(packet_we)bytes_out[packet_write_address]<=packet_write_data;
  packet_q<=bytes_out[index];
 end
 function [31:0] crc_byte;
  input [31:0] c;input [7:0] d;integer i;reg [31:0] v;
  begin v=c^{24'd0,d};for(i=0;i<8;i=i+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;end
 endfunction
 task put32;input integer p;input [31:0] v;begin
  if(p<20)frame_header[p*8+:32]<=v;
  else status_snapshot[(p-20)*8+:32]<=v;
 end endtask
 task finish_body;input [7:0] n;begin
  body_length<=n;frame_header[128+:8]<=n;frame_header[136+:8]<=0;index<=0;crc<=32'hffffffff;status_body<=0;mode<=HEADER;
 end endtask
 always @(posedge clk) begin
  if(!rst_n)begin
   last_take<=0;last_selected<=0;abort_transfer<=0;session_ready<=0;settle_cycles<=0;select_valid<=0;select_slot<=0;lease_open<=0;lease_close<=0;save_ack<=0;progress_ack<=0;mode<=IDLE;request<=0;previous_request<=0;cache_valid<=0;index<=0;body_length<=0;tx_length<=0;
   crc<=32'hffffffff;watchdog<=0;gap<=0;block_data<=0;block_bytes<=0;block_index<=0;copied<=0;target_bytes<=0;origin<=0;
   burst_active<=0;burst_left<=0;burst_gap_ms<=8;packet_wait<=0;rx_framing_errors<=0;rx_crc_errors<=0;busy_rx_bytes<=0;
   start_record<=0;stop_record<=0;erase_record<=0;start_play<=0;stop_play<=0;download_request<=0;download_offset<=0;
   frame_header<=0;status_snapshot<=0;status_body<=0;
   checked_take<=0;checked_count<=0;checked_confirmed<=0;checked_crc<=0;remaining_bytes<=0;
   total_gt<=0;total_eq<=0;confirmed_gt<=0;confirmed_eq<=0;crc_matches<=0;
  end else begin
   select_valid<=0;lease_open<=0;lease_close<=0;save_ack<=0;progress_ack<=0;
   last_take<=take_id;last_selected<=selected;
   if(last_take!=take_id||last_selected!=selected||disconnect)cache_valid<=0;
   if(disconnect)begin abort_transfer<=1;session_ready<=0;end
   start_record<=0;stop_record<=0;erase_record<=0;start_play<=0;stop_play<=0;download_request<=0;
   if(rx_error)rx_framing_errors<=rx_framing_errors+1'b1;
   if(rx_valid && mode!=IDLE)busy_rx_bytes<=busy_rx_bytes+1'b1;
   if(gap!=0)gap<=gap-1'b1;
   case(mode)
    IDLE:begin
     // Sliding window resynchronizes after corruption, missing bytes or noise.
     if(rx_valid)begin request<={rx_data,request[159:8]};watchdog<=0;mode<=CHECK;index<=0;crc<=32'hffffffff;end
     else if(watchdog<CLK_HZ/5)watchdog<=watchdog+1'b1;
     else request<=0;
     if(rx_error)request<=0;
    end
    CHECK:begin
     if(request[31:0]!=32'h31515250 || request[47:40]!=0)mode<=IDLE;
     else if(index<16)begin crc<=crc_byte(crc,request[index*8 +:8]);index<=index+1'b1;end
     else if(final_crc!=request[159:128])begin rx_crc_errors<=rx_crc_errors+1'b1;mode<=IDLE;end
     else if(session_ready && command!=8 && (command!=7 || (lease&&state==5)) && cache_valid && previous_request==request[127:0])begin index<=0;gap<=2;mode<=SEND;end
     else begin
      previous_request<=request[127:0];cache_valid<=0;burst_active<=0;abort_transfer<=0;
      put32(0,32'h31535250);frame_header[32+:8]<=command;frame_header[40+:8]<=0;
      frame_header[48+:8]<=request[55:48];frame_header[56+:8]<=request[63:56];put32(8,argument);put32(12,take_id);
      frame_header[144+:8]<=0;frame_header[152+:8]<=0;mode<=VALIDATE;
     end
    end
    VALIDATE:begin
     checked_take<=take_id;checked_count<=sample_count;checked_confirmed<=confirmed_bytes;checked_crc<=pcm_crc;
     remaining_bytes<=total_bytes-argument;crc_matches<=argument==pcm_crc;
     for(compare_byte=0;compare_byte<4;compare_byte=compare_byte+1)begin
      total_gt[compare_byte]<=argument[compare_byte*8+:8]>total_bytes[compare_byte*8+:8];
      total_eq[compare_byte]<=argument[compare_byte*8+:8]==total_bytes[compare_byte*8+:8];
      confirmed_gt[compare_byte]<=argument[compare_byte*8+:8]>confirmed_bytes[compare_byte*8+:8];
      confirmed_eq[compare_byte]<=argument[compare_byte*8+:8]==confirmed_bytes[compare_byte*8+:8];
     end
     mode<=EXEC;
    end
    EXEC:begin
     if(validation_changed)mode<=VALIDATE;
     else if(command==1)begin session_ready<=1;mode<=STATUS;end
     else if(!session_ready&&command!=9)begin frame_header[40+:8]<=6;finish_body(0);end
     else if(expected_take!=take_id)begin frame_header[40+:8]<=2;finish_body(0);end
     else case(command)
      2:if(state==2 && mem_ready && !lease)begin start_record<=1;mode<=SETTLE;settle_cycles<=0;end else begin frame_header[40+:8]<=1;finish_body(0);end
      3:if(state==3)begin stop_record<=1;mode<=SETTLE;settle_cycles<=0;end else if(state==4||state==5)mode<=STATUS;else begin frame_header[40+:8]<=1;finish_body(0);end
      4:if(state==5 && !lease && mem_ready)begin erase_record<=1;mode<=SETTLE;settle_cycles<=0;end else begin frame_header[40+:8]<=1;finish_body(0);end
      5:if(state==5 && sample_count!=0 && mem_ready && !lease)begin start_play<=1;mode<=SETTLE;settle_cycles<=0;end else begin frame_header[40+:8]<=1;finish_body(0);end
      6:if(state==7 || state==6)begin stop_play<=1;mode<=SETTLE;settle_cycles<=0;end else if(state==5)mode<=STATUS;else begin frame_header[40+:8]<=1;finish_body(0);end
      7,8:if(state!=5)begin frame_header[40+:8]<=1;finish_body(0);end
        else if(argument[4:0]!=0 || argument_ge_total)begin frame_header[40+:8]<=3;finish_body(0);end
        else begin burst_active<=command==8;burst_left<=16;origin<=argument;download_offset<=argument;copied<=0;target_bytes<=remaining_bytes>=192?192:remaining_bytes[7:0];watchdog<=0;mode<=READ_REQ;end
      9:if(argument>=2 && argument<=30)begin burst_gap_ms<=argument[7:0];session_ready<=1;mode<=STATUS;end else begin frame_header[40+:8]<=3;finish_body(0);end
      10:if((state==2||state==5)&&!lease&&mem_ready&&argument<2)begin
       select_valid<=1;select_slot<=argument[0];mode<=SETTLE;settle_cycles<=0;
      end else begin frame_header[40+:8]<=1;finish_body(0);end
      11:if(state==5&&mem_ready)begin lease_open<=1;mode<=SETTLE;settle_cycles<=0;end
       else begin frame_header[40+:8]<=1;finish_body(0);end
      12:begin lease_close<=1;mode<=SETTLE;settle_cycles<=0;end
      13:if(lease&&crc_matches)begin save_ack<=1;mode<=SETTLE;settle_cycles<=0;end
       else begin frame_header[40+:8]<=2;finish_body(0);end
      14:if(lease&&argument_le_total&&argument_ge_confirmed)begin progress_ack<=1;mode<=SETTLE;settle_cycles<=0;end
       else begin frame_header[40+:8]<=3;finish_body(0);end
      default:begin frame_header[40+:8]<=4;finish_body(0);end
     endcase
    end
    SETTLE:if(settle_cycles==4)mode<=STATUS;else settle_cycles<=settle_cycles+1'b1;
    STATUS:begin
     put32(12,take_id);status_snapshot[0+:8]<={4'd0,state};status_snapshot[8+:8]<=fault;status_snapshot[16+:8]<={7'd0,mem_ready};status_snapshot[24+:8]<=3;
     put32(24,sample_count);put32(28,pcm_crc);put32(32,keys_down);
     status_snapshot[128+:8]<=peak[7:0];status_snapshot[136+:8]<=peak[15:8];status_snapshot[144+:8]<=192;status_snapshot[152+:8]<=0;
     put32(40,390625);status_snapshot[192+:8]<=8;status_snapshot[200+:8]<=0;status_snapshot[208+:8]<=16;status_snapshot[216+:8]<=burst_gap_ms;put32(48,MAX_SAMPLES);
     put32(52,rx_framing_errors);put32(56,rx_crc_errors);put32(60,busy_rx_bytes);
     status_snapshot[352+:8]<={7'd0,selected};status_snapshot[360+:8]<=2;status_snapshot[368+:8]<={6'd0,saved_on_phone,lease};status_snapshot[376+:8]<={4'd0,other_state};
     put32(68,committed_samples);put32(72,other_samples);put32(76,other_take);put32(80,confirmed_bytes);
     finish_body(64);status_body<=1;
    end
    READ_REQ:begin
     watchdog<=watchdog+1'b1;
     if(state==8 || abort_transfer || watchdog>=CLK_HZ)begin burst_active<=0;frame_header[40+:8]<=5;finish_body(0);end
     else if(state==5 && mem_ready && !lease)lease_open<=1;
     else if(state==5 && mem_ready && lease)begin download_request<=1;watchdog<=0;mode<=READ_WAIT;end
    end
    READ_WAIT:begin
     watchdog<=watchdog+1'b1;
     if(state==8 || watchdog>=CLK_HZ)begin burst_active<=0;frame_header[40+:8]<=5;finish_body(0);end
     else if(download_done)begin
      if(download_bytes==0 || download_bytes>32 || copied+download_bytes>target_bytes)begin burst_active<=0;frame_header[40+:8]<=5;finish_body(0);end
      else begin block_data<=download_data;block_bytes<=download_bytes;block_index<=0;mode<=COPY;end
     end
    end
    COPY:begin
     if(block_index==block_bytes-1)begin
      copied<=copied+block_bytes;
      if(copied+block_bytes==target_bytes)finish_body(target_bytes);
      else begin download_offset<=download_offset+32;watchdog<=0;mode<=READ_REQ;end
     end else block_index<=block_index+1'b1;
    end
    HEADER:if(index==19)begin index<=0;mode<=status_body?BODY:CRC;end else index<=index+1'b1;
    BODY:if(index==63)begin index<=0;mode<=CRC;end else index<=index+1'b1;
    CRC:mode<=CRC_WAIT; // synchronous packet RAM read
    CRC_WAIT:begin
     crc<=crc_byte(crc,packet_q);
     if(index==19+body_length)begin index<=0;mode<=TRAILER;end
     else begin index<=index+1'b1;mode<=CRC;end
    end
    TRAILER:if(index==3)begin
     tx_length<=24+body_length;index<=0;cache_valid<=1;gap<=2;mode<=SEND;
    end else index<=index+1'b1;
    SEND:if(sending && tx_ready)begin
     // One extra idle bit between UART bytes; no unbounded module stream.
     gap<=((CLK_HZ+BAUD/2)/BAUD)*11+2;
     if(index==tx_length-1)begin
      if(burst_active)begin mode<=NEXT_BURST;packet_wait<=burst_gap_ms*(CLK_HZ/1000);end
      else begin mode<=IDLE;request<=0;watchdog<=0;end
     end else index<=index+1'b1;
    end
    NEXT_BURST:if(packet_wait!=0)packet_wait<=packet_wait-1'b1;
     else if(lease && !abort_transfer && burst_left>1 && origin+target_bytes<total_bytes)begin
      burst_left<=burst_left-1'b1;origin<=origin+target_bytes;download_offset<=origin+target_bytes;
      put32(8,origin+target_bytes);copied<=0;target_bytes<=total_bytes-origin-target_bytes>=192?192:total_bytes-origin-target_bytes;
      watchdog<=0;mode<=READ_REQ;
     end else begin
      // Explicit empty end marker, same request sequence, exclusive end offset.
      burst_active<=0;put32(8,origin+target_bytes);finish_body(0);
     end
    default:mode<=IDLE;
   endcase
   if(disconnect)begin
    abort_transfer<=1;session_ready<=0;cache_valid<=0;
    // Cancel a not-yet-executed request on the same edge as disconnect.
    // An already-transmitting reply still drains through SEND unchanged.
    if(mode==IDLE||mode==CHECK||mode==VALIDATE||mode==EXEC)begin
     mode<=IDLE;request<=0;
     select_valid<=0;lease_open<=0;lease_close<=0;save_ack<=0;progress_ack<=0;
     start_record<=0;stop_record<=0;erase_record<=0;start_play<=0;stop_play<=0;download_request<=0;
    end
   end
  end
 end
endmodule
