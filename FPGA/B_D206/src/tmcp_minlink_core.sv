`timescale 1ns/1ps
module tmcp_minlink_core #(parameter integer STEP_DIV=1,SCORE_SUPPORT=0,LOOP_SUPPORT=0)(
 input wire clk,rst_n,ms_tick,force_disconnect,
 output wire loop_request,output wire [15:0] loop_command,loop_payload_length,output wire [559:0] loop_payload,
 input wire loop_done,input wire [15:0] loop_result,input wire [6:0] loop_reply_length,input wire [511:0] loop_reply,
 input wire [31:0] score_keys_down,input wire score_blocked,score_stop,
 output wire score_loaded,score_active,score_waiting,score_completed,
 output wire [255:0] keymap_values,
 output wire [31:0] score_targets,score_elapsed,score_duration,
 output wire [15:0] score_current,score_total,

 input wire rx_valid,input wire [7:0] rx_data,output wire rx_ready,
 output wire tx_valid,output wire [7:0] tx_data,input wire tx_ready,
 input wire local_valid,input wire [15:0] local_id,local_value,output wire local_ready,
 output wire local_ack,output wire [15:0] local_status,input wire register_locked,
 output wire hello_seen,app_online,output wire [31:0] session_id,param_revision,state_revision,
 output wire [255:0] parameter_values,
 output wire [6:0] master_volume,piano_volume,output wire muted,
 output wire [1:0] octave_group,output wire [2:0] fx_enabled,output wire [62:0] fx_values,
 output wire [175:0] trace_parser,output wire [31:0] trace_checksums,
 output wire [31:0] crc_errors,param_write_count,output wire [15:0] last_command
);
 localparam integer CW=STEP_DIV>1?$clog2(STEP_DIV):1;
 reg [CW-1:0] phase;
 wire step_en=STEP_DIV==1||phase==STEP_DIV-1;
 reg ms_pending,disconnect_pending;
 wire tick=ms_tick||ms_pending,disconnect=force_disconnect||disconnect_pending;
 always @(posedge clk)begin
  if(!rst_n)begin phase<=0;ms_pending<=0;disconnect_pending<=0;end
  else begin
   phase<=step_en?0:phase+1'b1;
   if(step_en)begin ms_pending<=0;disconnect_pending<=0;end
   else begin
    if(ms_tick)ms_pending<=1;
    if(force_disconnect)disconnect_pending<=1;
   end
  end
 end
 wire engine_rx_ready,engine_tx_valid,engine_local_ready,engine_local_ack;
 assign rx_ready=engine_rx_ready&&step_en&&!disconnect;
 assign tx_valid=engine_tx_valid&&step_en&&!disconnect;
 assign local_ready=engine_local_ready&&step_en&&!disconnect;
 assign local_ack=engine_local_ack&&step_en&&!disconnect;
 tmcp_minlink_engine #(.SCORE_SUPPORT(SCORE_SUPPORT),.LOOP_SUPPORT(LOOP_SUPPORT)) engine(
  .loop_request(loop_request),.loop_command(loop_command),.loop_payload_length(loop_payload_length),.loop_payload(loop_payload),
  .loop_done(loop_done),.loop_result(loop_result),.loop_reply_length(loop_reply_length),.loop_reply(loop_reply),
  .keymap_values(keymap_values),.score_keys_down(score_keys_down),.score_blocked(score_blocked),.score_stop(score_stop),
  .score_loaded(score_loaded),.score_active(score_active),.score_waiting(score_waiting),.score_completed(score_completed),
  .score_targets(score_targets),.score_elapsed(score_elapsed),.score_duration(score_duration),.score_current(score_current),.score_total(score_total),
  .clk(clk),.rst_n(rst_n),.step_en(step_en),.ms_tick(tick),.force_disconnect(disconnect),
  .rx_valid(rx_valid),.rx_data(rx_data),.rx_ready(engine_rx_ready),
  .tx_valid(engine_tx_valid),.tx_data(tx_data),.tx_ready(tx_ready),
  .local_valid(local_valid),.local_id(local_id),.local_value(local_value),.local_ready(engine_local_ready),.local_ack(engine_local_ack),.local_status(local_status),.register_locked(register_locked),
  .hello_seen(hello_seen),.app_online(app_online),.session_id(session_id),.param_revision(param_revision),.state_revision(state_revision),
  .parameter_values(parameter_values),.master_volume(master_volume),.piano_volume(piano_volume),.muted(muted),.octave_group(octave_group),.fx_enabled(fx_enabled),.fx_values(fx_values),
  .trace_parser(trace_parser),.trace_checksums(trace_checksums),.crc_errors(crc_errors),.param_write_count(param_write_count),.last_command(last_command));
endmodule

`timescale 1ns/1ps
// Isolated preview implementation. Byte-stream interface; no production pin assignment.
module tmcp_minlink_engine #(parameter integer SCORE_SUPPORT=0,LOOP_SUPPORT=0)(
 input wire clk,rst_n,step_en,ms_tick,force_disconnect,
 output wire loop_request,output wire [15:0] loop_command,loop_payload_length,output wire [559:0] loop_payload,
 input wire loop_done,input wire [15:0] loop_result,input wire [6:0] loop_reply_length,input wire [511:0] loop_reply,
 input wire [31:0] score_keys_down,input wire score_blocked,score_stop,
 output wire score_loaded,score_active,score_waiting,score_completed,
 output wire [255:0] keymap_values,
 output wire [31:0] score_targets,score_elapsed,score_duration,
 output wire [15:0] score_current,score_total,

 input wire rx_valid,input wire [7:0] rx_data,output wire rx_ready,
 output wire tx_valid,output wire [7:0] tx_data,input wire tx_ready,
 input wire local_valid,input wire [15:0] local_id,local_value,output wire local_ready,
 output reg local_ack,output reg [15:0] local_status,input wire register_locked,
 output reg hello_seen,app_online,output reg [31:0] session_id,param_revision,state_revision,
 output wire [255:0] parameter_values,
 output wire [6:0] master_volume,piano_volume,output wire muted,
 output wire [1:0] octave_group,output wire [2:0] fx_enabled,output wire [62:0] fx_values,
 output reg [175:0] trace_parser,output reg [31:0] trace_checksums,
 output reg [31:0] crc_errors,param_write_count,output reg [15:0] last_command
);
 localparam RX=0,SCAN=1,CHECK=2,DISPATCH=3,TXCRC=4,CACHE=5,SEND=6,DROP=7,VALIDATE=8,COMMIT=9,REPLAY_CHECK=10,REPLAY_LOAD=11,REQ_WAIT=12,RESP_WAIT=13,REQ_WAIT2=14,RESP_WAIT2=15,FRAME_WAIT1=16,FRAME_WAIT2=17,FRAME_DATA=18,SCORE_WAIT=19,KEYMAP_VALIDATE=20,KEYMAP_COMMIT=21;
 reg [4:0] state;
 localparam F_CRC=0,F_RELOAD=1,F_CACHE=2;
 reg [1:0] frame_target;reg [8:0] frame_read_index,head;
 reg [7:0] incoming_crc_low;wire [7:0] frame_byte;
 // Incoming wire payload limit remains 256 bytes (272-byte frame).
 // Maximum implemented reply is PARAMS: 16-byte frame overhead + 71 bytes.
 localparam integer REPLY_BYTES=87;
 reg [7:0] rb[0:84] /* synthesis syn_ramstyle = "registers" */;
 reg [7:0] tb[0:REPLY_BYTES-1];
 wire [7:0] cached_request,cached_response;
 reg [8:0] cache_index;
 reg [15:0] p[0:15],pending[0:15];
 reg [7:0] keymap[0:31],keymap_draft[0:31];reg [31:0] keymap_revision,keymap_seen;reg [5:0] keymap_cursor;
 genvar km;generate for(km=0;km<32;km=km+1)begin:keymap_export assign keymap_values[km*8+:8]=keymap[km];end endgenerate
 reg [8:0] used,frame_n,tx_n,tx_index,crc_index,drop_left,cache_req_n,cache_tx_n;
 reg [15:0] crc_work,idle_ms,link_ms,cache_sequence;
 reg [16:0] expected_sequence;
 reg cache_valid,cache_this;
 reg [7:0] hello_min,hello_max;
 integer i,j,index,number,plen,reply_len;
 reg [15:0] command,req_seq,status;
 reg [31:0] incoming_session,nonce,detail,reply_session,next_revision;
 reg changed,identical,replay,ordinary,defer_reply;
 reg [4:0] batch_count,batch_cursor;reg [15:0] batch_seen;
 reg [15:0] value,calculated;
 // Cache memory has a synchronous read contract. Two explicit wait states
 // precede consuming a newly addressed byte, even when STEP_DIV is one.
 wire abort_frame=force_disconnect||(ms_tick&&hello_seen&&link_ms>=9999);
 wire frame_write=rst_n&&step_en&&!abort_frame&&state==RX&&rx_valid&&rx_ready;
 wire [8:0] replay_address=(state==REQ_WAIT||state==REQ_WAIT2||state==REPLAY_CHECK)?cache_index:frame_read_index;
 wire [8:0] frame_address=head+replay_address;
 wire [8:0] frame_write_address=head+used;
 tmcp_cache_memory #(.ADDRESS_BITS(9)) frame_buffer(
  .clk(clk),.read_enable(step_en),.read_address(frame_address),.read_data(frame_byte),
  .write_enable(frame_write),.write_address(frame_write_address),.write_data(rx_data));
 tmcp_cache_memory #(.ADDRESS_BITS(9)) request_cache(
  .clk(clk),.read_enable(step_en),.read_address(cache_index),.read_data(cached_request),
  .write_enable(rst_n&&step_en&&state==FRAME_DATA&&frame_target==F_CACHE&&cache_this&&cache_index<frame_n),
  .write_address(cache_index),.write_data(frame_byte));
 tmcp_cache_memory #(.ADDRESS_BITS(7)) response_cache(
  .clk(clk),.read_enable(step_en),.read_address(cache_index[6:0]),.read_data(cached_response),
  .write_enable(rst_n&&step_en&&state==FRAME_DATA&&frame_target==F_CACHE&&cache_this&&cache_index<tx_n),
  .write_address(cache_index[6:0]),.write_data(tb[cache_index]));
 reg score_request,score_abort;
 wire score_done;wire [15:0] score_result;wire [31:0] score_detail;wire [5:0] score_reply_length;wire [159:0] score_reply;
 wire [559:0] score_payload;
 assign loop_request=LOOP_SUPPORT&&score_request&&command[15:8]==4;
 assign loop_command=command;assign loop_payload_length={rb[13],rb[12]};assign loop_payload=score_payload;
 genvar sb;generate for(sb=0;sb<70;sb=sb+1)begin:score_bytes assign score_payload[sb*8+:8]=rb[sb+14];end
 if(SCORE_SUPPORT)begin:score_feature
  studio_score_store scores(.clk(clk),.rst_n(rst_n),.abort_upload(force_disconnect||score_abort),.busy_external(score_blocked),.stop_guide(score_stop),
   .octave_group(p[3][1:0]),.keys_down(score_keys_down),.request(score_request&&command[15:8]!=4),.command(command),.payload_length({rb[13],rb[12]}),.payload(score_payload),
   .done(score_done),.result(score_result),.detail(score_detail),.reply_length(score_reply_length),.reply(score_reply),
   .loaded(score_loaded),.active(score_active),.waiting(score_waiting),.completed(score_completed),.target_keys(score_targets),
   .elapsed_us(score_elapsed),.current_note(score_current),.total_notes(score_total),.score_duration(score_duration));
 end else begin:no_score_feature
  assign score_done=0;assign score_result=7;assign score_detail=0;assign score_reply_length=0;assign score_reply=0;
  assign score_loaded=0;assign score_active=0;assign score_waiting=0;assign score_completed=0;
  assign score_targets=0;assign score_elapsed=0;assign score_duration=0;assign score_current=0;assign score_total=0;
 end endgenerate
 function [15:0] crc_byte(input [15:0] crc,input [7:0] b);
  reg [15:0] c;integer k;begin c=crc^{b,8'b0};for(k=0;k<8;k=k+1)c=c[15]?(c<<1)^16'h1021:(c<<1);crc_byte=c;end
 endfunction
 function [15:0] r16(input [6:0] a);begin r16={rb[a+7'd1],rb[a]};end endfunction
 function [31:0] r32(input [6:0] a);begin r32={rb[a+7'd3],rb[a+7'd2],rb[a+7'd1],rb[a]};end endfunction
 task w16(input [6:0] a,input [15:0] v);begin tb[a]=v[7:0];tb[a+7'd1]=v[15:8];end endtask
 task w32(input [6:0] a,input [31:0] v);begin tb[a]=v[7:0];tb[a+7'd1]=v[15:8];tb[a+7'd2]=v[23:16];tb[a+7'd3]=v[31:24];end endtask
 function integer param_index(input [15:0] id);
  begin case(id)
   1:param_index=0;2:param_index=1;3:param_index=2;4:param_index=3;
   16:param_index=4;17:param_index=5;18:param_index=6;19:param_index=7;
   32:param_index=8;33:param_index=9;34:param_index=10;35:param_index=11;
   48:param_index=12;49:param_index=13;50:param_index=14;51:param_index=15;
   default:param_index=-1;endcase end
 endfunction
 function [15:0] param_id(input integer n);
  begin if(n<4)param_id=n+1;else if(n<8)param_id=n+12;else if(n<12)param_id=n+24;else param_id=n+36;end
 endfunction
 function [15:0] param_max(input integer n);
  begin if(n==2||n==4||n==8||n==12)param_max=1;else if(n==3)param_max=3;else param_max=127;end
 endfunction
 function [31:0] bump(input [31:0] v);begin bump=v==32'hfffffffe ? 0 : v+1'b1;end endfunction
 task caps;
  begin
   // payload = status(2) + Caps(46). Only PARAMS is implemented.
   reply_len=48;tb[16]=0;tb[17]=2;tb[18]=0;tb[19]=0;
   w32(20,(SCORE_SUPPORT?83:1)|(LOOP_SUPPORT?128:0));w16(24,256);w16(26,SCORE_SUPPORT?50:192);
   if(SCORE_SUPPORT)begin w16(28,1024);w32(30,120000000);end
   tb[35]=1;tb[36]=1;tb[37]=16;w32(38,390625);w32(42,8);
   tb[50]=53;tb[51]=84;tb[52]=41;tb[53]=2;w16(54,12);w32(56,32'h19025d6f);
  end
 endtask
 task keymap_reply(input use_pending,input [31:0] revision);integer k;begin
 reply_len=38;w32(16,revision);for(k=0;k<32;k=k+1)tb[20+k]=use_pending?keymap_draft[k]:keymap[k];
 end endtask
 task params(input use_pending,input [31:0] revision);
  integer t;begin
   reply_len=71;w32(16,revision);tb[20]=16;
   for(t=0;t<16;t=t+1)begin w16(21+t*4,param_id(t));w16(23+t*4,use_pending?pending[t]:p[t]);end
  end
 endtask
 // Local writes win only at frame boundaries. A held local request must not
 // block the remaining bytes of a partially received protocol frame.
 task finish_reply;begin
       if(status!=0)begin reply_len=6;w32(16,detail);end
       tb[0]=8'h54;tb[1]=8'h4d;tb[2]=1;tb[3]=1;w16(4,command);w16(6,req_seq);w32(8,reply_session);w16(12,reply_len);w16(14,status);
       tx_n<=16+reply_len;crc_index<=2;crc_work<=16'hffff;cache_this<=ordinary;state<=TXCRC;
 end endtask
 assign rx_ready=state==RX&&!force_disconnect&&!(local_valid&&used==0);
 assign local_ready=state==RX&&used==0&&!force_disconnect;
 // Header mirror contains all implemented request fields (maximum SET is
 // 85 bytes). Full 272-byte requests, CRC and exact replay use frame RAM.
 wire header_reload=rst_n&&step_en&&!abort_frame&&state==FRAME_DATA&&frame_target==F_RELOAD;
 wire header_write=(frame_write&&used<85)||header_reload;
 wire [6:0] header_address=header_reload?frame_read_index[6:0]:used[6:0];
 wire [7:0] header_data=header_reload?frame_byte:rx_data;
 always @(posedge clk)if(header_write)rb[header_address]<=header_data;
 assign tx_valid=state==SEND;
 assign tx_data=tb[tx_index];
 assign master_volume=p[0][6:0];assign piano_volume=p[1][6:0];assign muted=p[2][0];assign octave_group=p[3][1:0];
 assign fx_enabled={p[12][0],p[8][0],p[4][0]};
 assign fx_values={p[15][6:0],p[14][6:0],p[13][6:0],p[11][6:0],p[10][6:0],p[9][6:0],p[7][6:0],p[6][6:0],p[5][6:0]};
 genvar g;generate for(g=0;g<16;g=g+1)begin:values assign parameter_values[g*16+:16]=p[g];end endgenerate

 always @(posedge clk)begin
  if(!rst_n)begin
   keymap_revision<=0;keymap_seen<=0;keymap_cursor<=0;for(i=0;i<32;i=i+1)begin keymap[i]<=53+i;keymap_draft[i]<=53+i;end
   score_request<=0;score_abort<=0;trace_parser<=0;trace_checksums<=0;local_ack<=0;head<=0;frame_target<=0;frame_read_index<=0;incoming_crc_low<=0;
   state<=RX;used<=0;frame_n<=0;tx_n<=0;tx_index<=0;crc_index<=0;drop_left<=0;crc_work<=16'hffff;
   cache_index<=0;cache_valid<=0;cache_this<=0;cache_req_n<=0;cache_tx_n<=0;cache_sequence<=0;expected_sequence<=2;
   hello_seen<=0;app_online<=0;session_id<=0;idle_ms<=0;link_ms<=0;hello_min<=0;hello_max<=0;
   param_revision<=0;state_revision<=0;crc_errors<=0;param_write_count<=0;last_command<=0;local_status<=0;
   p[0]<=127;p[1]<=127;p[2]<=0;p[3]<=2;p[4]<=0;p[5]<=70;p[6]<=42;p[7]<=32;
   p[8]<=0;p[9]<=40;p[10]<=49;p[11]<=38;p[12]<=0;p[13]<=18;p[14]<=51;p[15]<=38;
  end else if(step_en)begin
   local_ack<=0;score_abort<=0;
   if(force_disconnect||(ms_tick&&hello_seen&&link_ms>=9999))begin
   score_request<=0;score_abort<=1;
   // Link reset does not reset instrument parameters or affect the audio clock.
   state<=RX;used<=0;head<=0;cache_valid<=0;hello_seen<=0;app_online<=0;session_id<=0;expected_sequence<=2;
   idle_ms<=0;link_ms<=0;
  end else begin
   if(ms_tick&&hello_seen)link_ms<=link_ms+1'b1;
   if(ms_tick&&state==RX&&used!=0)idle_ms<=idle_ms+1'b1;
   case(state)
    RX:begin
     if(local_valid&&local_ready)begin
      index=param_index(local_id);local_ack<=1;local_status<=0;
      if(index<0)local_status<=7;
      else if(local_value>param_max(index))local_status<=4;
      else if(index==3&&(register_locked||score_blocked)&&p[3]!=local_value)local_status<=6;
      else if(p[index]!=local_value)begin
       p[index]<=local_value;param_revision<=bump(param_revision);state_revision<=state_revision+1'b1;param_write_count<=param_write_count+1'b1;
      end
     end else if(rx_valid&&rx_ready)begin used<=used+1'b1;idle_ms<=0;state<=SCAN;end
     else if(ms_tick&&used!=0&&idle_ms>=999)begin drop_left<=1;state<=DROP;idle_ms<=0;end
    end
    SCAN:begin
     if(used==0)state<=RX;
     else if(rb[0]!=8'h54)begin drop_left<=1;state<=DROP;end
     else if(used<2)state<=RX;
     else if(rb[1]!=8'h4d)begin drop_left<=1;state<=DROP;end
     else if(used<14)state<=RX;
     else if(r16(12)>256)begin drop_left<=1;state<=DROP;end
     else if(used<16+r16(12))state<=RX;
     else begin frame_n<=16+r16(12);crc_index<=2;crc_work<=16'hffff;state<=CHECK;end
    end
    CHECK:begin
     frame_target<=F_CRC;frame_read_index<=2;state<=FRAME_WAIT1;
     trace_parser[175:160]<=16'h544d;
    end
    DISPATCH:begin
     command=r16(4);req_seq=r16(6);incoming_session=r32(8);plen=r16(12);
     status=0;detail=0;reply_len=2;reply_session=incoming_session;ordinary=0;replay=0;defer_reply=0;
     last_command<=command;
     for(i=0;i<REPLY_BYTES;i=i+1)tb[i]=0;
     if(rb[3]!=0||req_seq==0)begin drop_left<=frame_n;state<=DROP;end
     else begin
      if(command==1)begin
       if(rb[2]!=1)begin status=1;detail=1;reply_session=0;end
       else if(plen!=6)begin status=3;detail=6;end
       else if(req_seq!=1||incoming_session!=0)begin status=9;detail=1;end
       else if(rb[14]>1||rb[15]<1)begin status=1;detail=1;reply_session=0;end
       else if(r32(16)==0)status=4;
       else begin
        nonce=r32(16);reply_session=nonce;
        if(hello_seen&&nonce==session_id&&(hello_min!=rb[14]||hello_max!=rb[15]))begin status=9;detail=expected_sequence;end
        else begin
         if(!hello_seen||nonce!=session_id)begin
          score_abort<=1;session_id<=nonce;hello_seen<=1;app_online<=0;expected_sequence<=2;cache_valid<=0;
          hello_min<=rb[14];hello_max<=rb[15];
         end
         link_ms<=0;caps();
        end
       end
      end else if(!hello_seen||incoming_session!=session_id)status=8;
      else begin
       // Compare exact bytes sequentially; do not use a CRC-only duplicate key.
       if(cache_valid&&req_seq==cache_sequence&&frame_n==cache_req_n)begin
        replay=1;cache_index<=0;state<=REQ_WAIT;
       end else if({1'b0,req_seq}!=expected_sequence||expected_sequence>65535)begin status=9;detail=expected_sequence;end
       else begin
        ordinary=1;link_ms<=0;
        if(rb[2]!=1)begin status=1;detail=1;end
        else case(command)
         2:if(plen!=0)begin status=3;end else caps();
         3:if(plen!=0)status=3;else begin reply_len=34;w32(16,state_revision);tb[22]=8'hff;end
         4:if(plen!=4)begin status=3;detail=4;end else begin reply_len=6;w32(16,r32(14));app_online<=1;end
         16'h0101:if(plen!=0)status=3;else params(0,param_revision);
         16'h0102:begin
          if(plen<5)begin status=3;detail=0;end
          else if(rb[18]<1||rb[18]>16||plen!=5+rb[18]*4)begin status=3;detail=0;end
          else if(r32(14)!=param_revision)begin status=18;detail=param_revision;end
          else begin
           for(i=0;i<16;i=i+1)pending[i]<=p[i];
           batch_count<=rb[18];batch_cursor<=0;batch_seen<=0;defer_reply=1;state<=VALIDATE;
          end
         end
         16'h0400,16'h0401,16'h0402,16'h0403,16'h0404,16'h0405,16'h0406,16'h0407:
          if(!LOOP_SUPPORT)status=7;else begin score_request<=1;defer_reply=1;state<=SCORE_WAIT;end
         16'h0201,16'h0202,16'h0203,16'h0204,16'h0205,16'h0220,16'h0221,16'h0222:
          if(!SCORE_SUPPORT)status=7;else begin score_request<=1;defer_reply=1;state<=SCORE_WAIT;end
         16'h0110:if(!SCORE_SUPPORT)status=7;else if(plen!=0)status=3;else keymap_reply(0,keymap_revision);
         16'h0111:if(!SCORE_SUPPORT)status=7;else if(plen!=36)status=3;else if(r32(14)!=keymap_revision)begin status=18;detail=keymap_revision;end
          else if(register_locked||score_blocked)status=6;else begin keymap_seen<=0;keymap_cursor<=0;state<=KEYMAP_VALIDATE;defer_reply=1;end
         5,16'h0210,16'h0211,
         16'h0301,16'h0302,16'h0303,16'h0304,16'h0305,16'h0310,16'h0311,16'h0312:status=7;
         default:status=2;
        endcase
       end
      end
      if(!replay&&!defer_reply)finish_reply();
     end
    end
    KEYMAP_VALIDATE:begin
     if(rb[18+keymap_cursor]<53||rb[18+keymap_cursor]>84)begin status=4;detail=keymap_cursor;finish_reply();end
     else if(keymap_seen[rb[18+keymap_cursor]-53])begin status=4;detail=keymap_cursor;finish_reply();end
     else begin keymap_draft[keymap_cursor]<=rb[18+keymap_cursor];keymap_seen[rb[18+keymap_cursor]-53]<=1;
      if(keymap_cursor==31)state<=KEYMAP_COMMIT;else keymap_cursor<=keymap_cursor+1'b1;
     end
    end
    KEYMAP_COMMIT:begin
     if(register_locked||score_blocked)begin status=6;detail=0;finish_reply();end
     else begin
      changed=0;for(i=0;i<32;i=i+1)if(keymap[i]!=keymap_draft[i])changed=1;
      next_revision=changed?bump(keymap_revision):keymap_revision;
      for(i=0;i<32;i=i+1)keymap[i]<=keymap_draft[i];keymap_revision<=next_revision;
      if(changed)state_revision<=state_revision+1'b1;
      status=0;keymap_reply(1,next_revision);finish_reply();
     end
    end
    SCORE_WAIT:if(command[15:8]==4?loop_done:score_done)begin
     score_request<=0;
     if(command[15:8]==4)begin
      status=loop_result;detail=0;reply_len=2+loop_reply_length;
      for(i=0;i<64;i=i+1)tb[16+i]=loop_reply[i*8+:8];
     end else begin
      status=score_result;detail=score_detail;reply_len=2+score_reply_length;
      for(i=0;i<20;i=i+1)tb[16+i]=score_reply[i*8+:8];
     end
     finish_reply();
    end
    VALIDATE:begin
     index=param_index(r16(19+batch_cursor*4));value=r16(21+batch_cursor*4);
     status=0;detail=0;
     if(index<0)begin status=7;detail=r16(19+batch_cursor*4);end
     else if(value>param_max(index)||batch_seen[index])begin status=4;detail=r16(19+batch_cursor*4);end
     else if(index==3&&(register_locked||score_blocked)&&p[3]!=value)status=6;
     if(status!=0)finish_reply();
     else begin
      pending[index]<=value;batch_seen[index]<=1;
      if(batch_cursor+1==batch_count)state<=COMMIT;else batch_cursor<=batch_cursor+1'b1;
     end
    end
    COMMIT:begin
     changed=0;for(i=0;i<16;i=i+1)if(p[i]!=pending[i])changed=1;
     next_revision=changed?bump(param_revision):param_revision;
     for(i=0;i<16;i=i+1)p[i]<=pending[i];
     if(changed)begin param_revision<=next_revision;state_revision<=state_revision+1'b1;param_write_count<=param_write_count+1'b1;end
     status=0;params(1,next_revision);finish_reply();
    end
    TXCRC:begin
     calculated=crc_byte(crc_work,tb[crc_index]);crc_work<=calculated;
     if(crc_index==tx_n-3)begin tb[tx_n-2]<=calculated[7:0];tb[tx_n-1]<=calculated[15:8];cache_index<=0;state<=CACHE;end
     else crc_index<=crc_index+1'b1;
    end
    CACHE:begin
     if(!cache_this)begin tx_index<=0;state<=SEND;end
     else begin frame_target<=F_CACHE;frame_read_index<=0;cache_index<=0;state<=FRAME_WAIT1;end
    end
    REQ_WAIT:state<=REQ_WAIT2;
    REQ_WAIT2:state<=REPLAY_CHECK;
    RESP_WAIT:state<=RESP_WAIT2;
    RESP_WAIT2:state<=REPLAY_LOAD;
    REPLAY_CHECK:begin
     if(frame_byte!=cached_request)begin
      // A changed request with a reused sequence receives the same SEQ error.
      command=r16(4);req_seq=r16(6);reply_session=r32(8);
      status=9;detail=expected_sequence;ordinary=0;finish_reply();
     end else if(cache_index+1==frame_n)begin
      cache_index<=0;link_ms<=0;state<=RESP_WAIT;
     end else begin cache_index<=cache_index+1'b1;state<=REQ_WAIT;end
    end
    REPLAY_LOAD:begin
     tb[cache_index]<=cached_response;
     if(cache_index+1==cache_tx_n)begin tx_n<=cache_tx_n;tx_index<=0;state<=SEND;end
     else begin cache_index<=cache_index+1'b1;state<=RESP_WAIT;end
    end
    SEND:if(tx_ready)begin
     if(tx_index==tx_n-1)begin drop_left<=frame_n;state<=DROP;end else tx_index<=tx_index+1'b1;
    end
    DROP:begin
     // Advancing the circular head replaces physical whole-buffer shifting.
     head<=head+drop_left;used<=used-drop_left;drop_left<=0;idle_ms<=0;
     if(drop_left>=used)begin used<=0;state<=SCAN;end
     else begin frame_target<=F_RELOAD;frame_read_index<=0;state<=FRAME_WAIT1;end
    end
    FRAME_WAIT1:state<=FRAME_WAIT2;
    FRAME_WAIT2:state<=FRAME_DATA;
    FRAME_DATA:begin
     case(frame_target)
      F_CRC:begin
       if(frame_read_index<22)trace_parser[175-frame_read_index*8-:8]<=frame_byte;
       if(frame_read_index<frame_n-2)begin
        crc_work<=crc_byte(crc_work,frame_byte);frame_read_index<=frame_read_index+1'b1;state<=FRAME_WAIT1;
       end else if(frame_read_index==frame_n-2)begin
        incoming_crc_low<=frame_byte;frame_read_index<=frame_read_index+1'b1;state<=FRAME_WAIT1;
       end else begin
        trace_checksums<={crc_work,frame_byte,incoming_crc_low};
        if(crc_work=={frame_byte,incoming_crc_low})state<=DISPATCH;
        else begin crc_errors<=crc_errors+1'b1;drop_left<=1;state<=DROP;end
       end
      end
      F_RELOAD:begin
       if(frame_read_index+1>=85||frame_read_index+1>=used)state<=SCAN;
       else begin frame_read_index<=frame_read_index+1'b1;state<=FRAME_WAIT1;end
      end
      F_CACHE:begin
       // Both cache banks commit one byte only when the frame RAM read is valid.
       if(cache_index+1>=frame_n&&cache_index+1>=tx_n)begin
        cache_valid<=1;cache_req_n<=frame_n;cache_tx_n<=tx_n;
        cache_sequence<=r16(6);expected_sequence<=expected_sequence+1'b1;
        tx_index<=0;state<=SEND;
       end else begin
        cache_index<=cache_index+1'b1;frame_read_index<=frame_read_index+1'b1;state<=FRAME_WAIT1;
       end
      end
      default:begin state<=RX;used<=0;head<=0;end
     endcase
    end
    default:begin state<=RX;used<=0;end
   endcase
  end
  end
 end
endmodule

// Single write port, clocked read port; no asynchronous RAM output is used.
module tmcp_cache_memory #(parameter integer ADDRESS_BITS=9)(
 input wire clk,write_enable,read_enable,
 input wire [ADDRESS_BITS-1:0] write_address,read_address,
 input wire [7:0] write_data,output reg [7:0] read_data
);
 reg [7:0] storage[0:(1<<ADDRESS_BITS)-1] /* synthesis syn_ramstyle = "block_ram" */;
 always @(posedge clk)begin
  if(write_enable)storage[write_address]<=write_data;
  if(read_enable)read_data<=storage[read_address];
 end
endmodule
