`timescale 1ns/1ps
// Standalone endpoint for later integration; no physical pin constraints are assigned.
module tmcp_uart_endpoint #(parameter integer CLK_HZ=50000000,BAUD=115200,BYTE_INTERFACE=0,SCORE_SUPPORT=0,LOOP_SUPPORT=0)(
 input wire clk,rst_n,bt_uart_rx,disconnect_pulse,register_locked,
 output wire loop_request,output wire [15:0] loop_command,loop_payload_length,output wire [559:0] loop_payload,
 input wire loop_done,input wire [15:0] loop_result,input wire [6:0] loop_reply_length,input wire [511:0] loop_reply,
 input wire [31:0] score_keys_down,input wire score_blocked,score_stop,
 output wire score_loaded,score_active,score_waiting,score_completed,
 output wire [255:0] keymap_values,
 output wire [31:0] score_targets,score_elapsed,score_duration,
 output wire [15:0] score_current,score_total,

 output wire bt_uart_tx,
 input wire local_valid,input wire [15:0] local_id,local_value,output wire local_ready,local_ack,
 output wire [15:0] local_status,
 output wire hello_seen,app_online,output wire [31:0] session_id,param_revision,state_revision,
 output wire [255:0] parameter_values,output wire [6:0] master_volume,piano_volume,
 output wire muted,output wire [1:0] octave_group,output wire [2:0] fx_enabled,output wire [62:0] fx_values,
 output reg [175:0] trace_uart,trace_fifo,output wire [175:0] trace_parser,output wire [31:0] trace_checksums,
 output reg [31:0] debug_rx_count,debug_edges,debug_frame_errors,debug_hello_count,
 output wire [31:0] debug_crc_errors,output wire [15:0] debug_last_command,
 output reg [7:0] debug_last_byte,output wire debug_rx_level,
 output wire rx_overflow,output wire uart_frame_error,
 input wire [7:0] byte_rx_data,input wire byte_rx_valid,byte_rx_error,
 output wire [7:0] byte_tx_data,output wire byte_tx_valid,input wire byte_tx_ready
);
 wire [7:0] input_byte,output_byte;wire input_valid,core_ready,output_valid,uart_ready;
 wire [7:0] fifo_byte;wire fifo_valid,overflow_pulse;
 wire pop=fifo_valid&&core_ready;
 (* syn_preserve=1 *)reg [1:0] debug_rx_sync;
 reg debug_rx_old,debug_hello_old;
 assign debug_rx_level=debug_rx_sync[1];
 always @(posedge clk)begin
  if(!rst_n)begin debug_rx_sync<=3;debug_rx_old<=1;debug_hello_old<=0;
   trace_uart<=0;trace_fifo<=0;debug_rx_count<=0;debug_edges<=0;debug_frame_errors<=0;debug_last_byte<=0;debug_hello_count<=0;end
  else begin
   debug_rx_sync<={debug_rx_sync[0],bt_uart_rx};debug_rx_old<=debug_rx_sync[1];debug_hello_old<=hello_seen;
   if(debug_rx_sync[1]!=debug_rx_old)debug_edges<=debug_edges+1'b1;
   if(input_valid)begin trace_uart<={trace_uart[167:0],input_byte};debug_rx_count<=debug_rx_count+1'b1;debug_last_byte<=input_byte;end
   if(pop)trace_fifo<={trace_fifo[167:0],fifo_byte};
   if(uart_frame_error)debug_frame_errors<=debug_frame_errors+1'b1;
   if(hello_seen&&!debug_hello_old)debug_hello_count<=debug_hello_count+1'b1;
  end
 end
 localparam integer MS_CYCLES=(CLK_HZ+999)/1000;
 reg [$clog2(MS_CYCLES+1)-1:0] ms_counter;
 wire ms_tick=ms_counter==MS_CYCLES-1;
 always @(posedge clk)if(!rst_n)ms_counter<=0;else ms_counter<=ms_tick?0:ms_counter+1'b1;
 assign byte_tx_data=output_byte;assign byte_tx_valid=output_valid;
 generate if(BYTE_INTERFACE)begin:bytes
  assign input_byte=byte_rx_data;assign input_valid=byte_rx_valid;assign uart_frame_error=byte_rx_error;
  assign uart_ready=byte_tx_ready;assign bt_uart_tx=1'b1;
 end else begin:serial
  uart_rx_8n1 #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) receive_uart(.clk(clk),.rst_n(rst_n),.rx(bt_uart_rx),.data(input_byte),.valid(input_valid),.frame_error(uart_frame_error));
  air_uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) transmit_uart(.clk(clk),.rst_n(rst_n),.tx_data(output_byte),.tx_valid(output_valid),.tx_ready(uart_ready),.tx(bt_uart_tx),.tx_done());
 end endgenerate
 tmcp_sync_fifo rx_fifo(.clk(clk),.rst_n(rst_n),.clear(disconnect_pulse||uart_frame_error),
  .write_valid(input_valid),.write_data(input_byte),.read_ready(core_ready),.read_valid(fifo_valid),.read_data(fifo_byte),
  .overflow_pulse(overflow_pulse),.overflow_sticky(rx_overflow),.count());
 tmcp_minlink_core #(.STEP_DIV(4),.SCORE_SUPPORT(SCORE_SUPPORT),.LOOP_SUPPORT(LOOP_SUPPORT)) core(
  .loop_request(loop_request),.loop_command(loop_command),.loop_payload_length(loop_payload_length),.loop_payload(loop_payload),
  .loop_done(loop_done),.loop_result(loop_result),.loop_reply_length(loop_reply_length),.loop_reply(loop_reply),
  .keymap_values(keymap_values),.score_keys_down(score_keys_down),.score_blocked(score_blocked),.score_stop(score_stop),
  .score_loaded(score_loaded),.score_active(score_active),.score_waiting(score_waiting),.score_completed(score_completed),
  .score_targets(score_targets),.score_elapsed(score_elapsed),.score_duration(score_duration),.score_current(score_current),.score_total(score_total),.clk(clk),.rst_n(rst_n),.ms_tick(ms_tick),.force_disconnect(disconnect_pulse||uart_frame_error||overflow_pulse),
  .rx_valid(fifo_valid),.rx_data(fifo_byte),.rx_ready(core_ready),.tx_valid(output_valid),.tx_data(output_byte),.tx_ready(uart_ready),
  .local_valid(local_valid),.local_id(local_id),.local_value(local_value),.local_ready(local_ready),.local_ack(local_ack),.local_status(local_status),.register_locked(register_locked),
  .hello_seen(hello_seen),.app_online(app_online),.session_id(session_id),.param_revision(param_revision),.state_revision(state_revision),.parameter_values(parameter_values),
  .master_volume(master_volume),.piano_volume(piano_volume),.muted(muted),.octave_group(octave_group),.fx_enabled(fx_enabled),.fx_values(fx_values),.trace_parser(trace_parser),.trace_checksums(trace_checksums),.crc_errors(debug_crc_errors),.param_write_count(),.last_command(debug_last_command));
endmodule
