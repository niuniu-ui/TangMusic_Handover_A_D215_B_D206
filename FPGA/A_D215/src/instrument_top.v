`timescale 1ns/1ps
module instrument_top #(parameter integer DRUM_MONITOR_UART=1,
                        parameter integer BT_BAUD=921600)(
 input wire clk,key_n,
 input wire ENC1_A,ENC1_B,ENC2_A,ENC2_B,ENC3_A,ENC3_B,
 input wire S1_N,S2_N,S3_N,S4_N,S5_N,
 input wire sustain_sig,
 input wire bt_uart_rx,bt_link_n,output wire bt_uart_tx,
 inout wire [7:0] fpc_drive,
 input wire [7:0] fpc_sense,
 input wire [7:0] flute_keys_n,
 input wire flute_spi_miso,
 input wire air_drum_key_n,imu_rx,imu2_rx,
 output wire imu_tx,imu2_tx,
 output wire flute_spi_cs_n,flute_spi_clk,flute_spi_mosi,flute_uart_tx,
 output wire rgb_led,matrix_din,drum_led_din,piano_guide_din,HP_BCK,HP_WS,HP_DIN,PA_EN,
 inout wire usb1_dp,usb1_dm,usb2_dp,usb2_dm,
 output wire tmds_clk_p,tmds_clk_n,output wire [2:0] tmds_data_p,tmds_data_n,
 input wire hdmi_hpd,hdmi_aux,output wire debug_uart_tx,
 output wire [14:0] ddr_addr,output wire [2:0] ddr_bank,
 output wire ddr_cs,ddr_ras,ddr_cas,ddr_we,ddr_ck,ddr_ck_n,ddr_cke,ddr_odt,ddr_reset_n,
 output wire [3:0] ddr_dm,inout wire [31:0] ddr_dq,inout wire [3:0] ddr_dqs,ddr_dqs_n
);
 wire muted,lissa_run;wire [1:0] lissa_delay;wire [2:0] fx_enabled;wire [62:0] fx_values;
 wire rst_n,sample_tick;wire signed [15:0] dac_sample;
 wire sustain_down,sustain_calibrated;
 studio_sustain_pedal #(.AUTO_POLARITY(0),.ACTIVE_LOW(1)) pedal(.clk(clk),.rst_n(rst_n),.sig(sustain_sig),
  .down(sustain_down),.calibrated(sustain_calibrated));
 wire panel_reset_n,panel_valid,panel_ready;wire [3:0] panel_code;
 studio_control_panel panel(.clk(clk),.rst_n(rst_n),
  .enc_a({ENC3_A,ENC2_A,ENC1_A}),.enc_b({ENC3_B,ENC2_B,ENC1_B}),
  .switches_n({S5_N,S4_N,S3_N,S2_N,S1_N}),.reset_n(panel_reset_n),
  .event_valid(panel_valid),.event_code(panel_code),.event_ready(panel_ready));
 wire [127:0] spectrum;wire [31:0] active;
 wire note_valid,note_ready,panic;wire [3:0] note_kind;
 wire [6:0] note_key,note_value,volume;
 wire [2:0] page;wire [1:0] octave_group;wire [3:0] touch_count;
 wire [6:0] piano_volume;
 wire [31:0] desired_notes;
 wire [31:0] physical_keys,physical_key_strike;
 wire [2:0] guide_action;wire [1:0] guide_arg,piece,guide_status,feedback;
 wire menu_open,tempo_mode,blocked;wire [7:0] bpm;wire [5:0] step_index,total_steps;
 wire signed [15:0] position;wire [6:0] correct,missed,errors,progress_percent;
 wire [31:0] target_keys,builtin_target_keys;wire [319:0] bars;wire [63:0] cues;
 wire loop_request,loop_done,loop_busy;wire [15:0] loop_command,loop_payload_length,loop_result;
 wire [559:0] loop_payload;wire [511:0] loop_reply;wire [6:0] loop_reply_length;
 wire signed [15:0] loop_pcm,live_pcm;
 wire loop_mem_request,loop_mem_write,loop_mem_ready,loop_mem_done,loop_mem_error;
 wire [28:0] loop_mem_address;wire [255:0] loop_mem_write_data,loop_mem_read_data;
 wire score_loaded,score_active,score_waiting,score_completed,score_blocked;
 wire [255:0] keymap_values;wire mapped_valid;wire [3:0] mapped_kind;wire [6:0] mapped_key,mapped_value;wire [31:0] mapped_down;
 wire [31:0] score_targets,score_elapsed,score_duration;wire [15:0] score_current,score_total;
 reg score_was_active,score_view;reg [63:0] score_cues;integer score_key,score_cue_count;
 wire score_started=score_active&&!score_was_active;
 always @(posedge clk)if(!rst_n)begin score_was_active<=0;score_view<=0;end else begin
  score_was_active<=score_active;if(score_started)score_view<=1;else if(guide_action==3)score_view<=0;
 end
 assign target_keys=score_view?score_targets:builtin_target_keys;
 always @*begin
  score_cues=0;score_cue_count=0;
  for(score_key=0;score_key<32;score_key=score_key+1)if(score_targets[score_key]&&score_cue_count<4)begin
   score_cues[score_cue_count*16+:16]=16'h8020|score_key;score_cue_count=score_cue_count+1;
  end
 end
 reg [1:0] old_group=2;
 always @(posedge clk)if(!rst_n)old_group<=2;else old_group<=octave_group;
 wire pitch_reset=old_group!=octave_group;
 wire [7:0] key_drive_low,key_idle_low,key_drive_fail;
 wire [31:0] scanned_keys;
 wire scan_valid;wire [3:0] scan_kind;wire [6:0] scan_key,scan_value;
 genvar key_row;
 generate for(key_row=0;key_row<8;key_row=key_row+1)begin:keyboard_io
  assign fpc_drive[key_row]=key_drive_low[key_row]?1'b0:1'bz;
 end endgenerate
 keyboard_scan_input keyboard(.clk(clk),.rst_n(rst_n),.clear(panic||pitch_reset),
  .drive_in(fpc_drive),.sense_in(fpc_sense),.drive_low(key_drive_low),.keys_down(scanned_keys),
  .idle_low(key_idle_low),.drive_fail(key_drive_fail),
  .event_valid(scan_valid),.event_kind(scan_kind),.event_key(scan_key),.event_value(scan_value));
 studio_keymap physical_mapping(.clk(clk),.rst_n(rst_n),.clear(panic||pitch_reset),.mapping(keymap_values),
  .in_valid(scan_valid),.in_kind(scan_kind),.in_key(scan_key),.in_value(scan_value),
  .out_valid(mapped_valid),.out_kind(mapped_kind),.out_key(mapped_key),.out_value(mapped_value),.mapped_down(mapped_down));
 wire [31:0] playing_keys=(physical_keys|desired_notes)&(octave_group==0?32'hffffff80:32'hffffffff);
 wire piano_guide_enabled=score_view?score_active:
  (page==2 && guide_status==1 && !blocked && !menu_open);
 ws2812_keyboard_guide keyboard_lights(.clk(clk),.rst_n(rst_n),
  .guide_enabled(piano_guide_enabled),.target_keys(target_keys),.keys_down(playing_keys),
  .keymap_values(keymap_values),.din(piano_guide_din));
 wire [255:0] bt_parameters;wire bt_hello,bt_online;wire [31:0] bt_revision;
 wire bt_local_valid,bt_local_ready,bt_local_ack;wire [15:0] bt_local_id,bt_local_value,bt_local_status;
 (* syn_preserve=1 *) reg [1:0] bt_link_sync=2'b11;
 reg bt_link_stable=1,bt_link_previous=1;reg [15:0] bt_link_count=0;
 always @(posedge clk)begin
  if(!rst_n)begin bt_link_sync<=3;bt_link_stable<=1;bt_link_previous<=1;bt_link_count<=0;end
  else begin
   bt_link_sync<={bt_link_sync[0],bt_link_n};bt_link_previous<=bt_link_stable;
   if(bt_link_sync[1]==bt_link_stable)bt_link_count<=0;
   else if(bt_link_count==49999)begin bt_link_stable<=bt_link_sync[1];bt_link_count<=0;end
   else bt_link_count<=bt_link_count+1'b1;
  end
 end
 wire [7:0] shared_rx,control_tx,record_tx;
 wire shared_rx_error,control_rx_valid,record_rx_valid,control_tx_valid,record_tx_valid,control_tx_ready,record_tx_ready;
 // LINK is active low. Reset a protocol session on a debounced disconnect edge.
 tmcp_uart_endpoint #(.CLK_HZ(50000000),.BAUD(BT_BAUD),.BYTE_INTERFACE(1),.SCORE_SUPPORT(1),.LOOP_SUPPORT(1)) bluetooth(
  .keymap_values(keymap_values),
  .loop_request(loop_request),.loop_command(loop_command),.loop_payload_length(loop_payload_length),.loop_payload(loop_payload),
  .loop_done(loop_done),.loop_result(loop_result),.loop_reply_length(loop_reply_length),.loop_reply(loop_reply),
  .score_keys_down(playing_keys),.score_blocked(score_blocked),
  .score_stop(panic||(score_view&&(guide_action==1||guide_action==3))),
  .score_loaded(score_loaded),.score_active(score_active),.score_waiting(score_waiting),.score_completed(score_completed),
  .score_targets(score_targets),.score_elapsed(score_elapsed),.score_duration(score_duration),.score_current(score_current),.score_total(score_total),
  .clk(clk),.rst_n(rst_n),.bt_uart_rx(bt_uart_rx),.bt_uart_tx(),
  .byte_rx_data(shared_rx),.byte_rx_valid(control_rx_valid),.byte_rx_error(shared_rx_error),
  .byte_tx_data(control_tx),.byte_tx_valid(control_tx_valid),.byte_tx_ready(control_tx_ready),
  .disconnect_pulse(bt_link_stable&&!bt_link_previous),.register_locked((|scanned_keys)||(|playing_keys)||guide_status==1||score_active||loop_busy),
  .local_valid(bt_local_valid),.local_id(bt_local_id),.local_value(bt_local_value),.local_ready(bt_local_ready),.local_ack(bt_local_ack),.local_status(bt_local_status),
  .hello_seen(bt_hello),.app_online(bt_online),.param_revision(bt_revision),.parameter_values(bt_parameters),
  .master_volume(volume),.piano_volume(piano_volume),.muted(muted),.octave_group(octave_group),.fx_enabled(fx_enabled),.fx_values(fx_values));

 wire disconnect=bt_link_stable&&!bt_link_previous;
 studio_uart_router #(.BAUD(BT_BAUD)) link_router(
  .clk(clk),.rst_n(rst_n),.uart_rx(bt_uart_rx),.uart_tx(bt_uart_tx),.disconnect(disconnect),
  .rx_data(shared_rx),.rx_error(shared_rx_error),.control_rx_valid(control_rx_valid),.record_rx_valid(record_rx_valid),
  .control_tx_data(control_tx),.control_tx_valid(control_tx_valid),.control_tx_ready(control_tx_ready),
  .record_tx_data(record_tx),.record_tx_valid(record_tx_valid),.record_tx_ready(record_tx_ready));
 wire playback_active;wire [15:0] playback_pcm;
 wire ui_rec_start,ui_rec_stop,ui_rec_erase,ui_play_start,ui_play_stop,ui_slot_valid,ui_slot;
 wire start_record,stop_record,erase_record,start_play,stop_play,download_request,download_done;
 wire proto_slot_valid,proto_slot,lease_open,lease_close,save_ack,progress_ack,transport_busy,record_protocol_busy;
 wire selected,lease,saved_on_phone,ready_for_command,recorder_busy,recorder_erase_accepted;
 wire [31:0] download_offset,sample_count,committed_samples,pcm_crc,take_id,other_samples,other_take,confirmed_bytes,ack_value;
 wire [255:0] download_data;wire [5:0] download_bytes;
 wire [3:0] rec_state,other_state;wire [7:0] rec_fault;wire [15:0] rec_peak;
 assign score_blocked=guide_status==1||rec_state==3||rec_state==4||lease||loop_busy;
 wire mem_request,mem_write,mem_ready,mem_done,mem_error;wire [28:0] mem_address;
 wire [255:0] mem_write_data,mem_read_data;
 studio_record_protocol record_protocol(
  .clk(clk),.rst_n(rst_n),.disconnect(disconnect),.rx_data(shared_rx),.rx_valid(record_rx_valid),.rx_error(shared_rx_error),
  .tx_data(record_tx),.tx_valid(record_tx_valid),.tx_ready(record_tx_ready),
  .selected(selected),.lease(lease),.saved_on_phone(saved_on_phone),.other_state(other_state),
  .committed_samples(committed_samples),.other_samples(other_samples),.other_take(other_take),.confirmed_bytes(confirmed_bytes),
  .select_valid(proto_slot_valid),.select_slot(proto_slot),.lease_open(lease_open),.lease_close(lease_close),
  .save_ack(save_ack),.progress_ack(progress_ack),.ack_value(ack_value),.transport_busy(transport_busy),.protocol_busy(record_protocol_busy),
  .state(rec_state),.fault(rec_fault),.mem_ready(ready_for_command),.sample_count(sample_count),.pcm_crc(pcm_crc),
  .keys_down(playing_keys),.take_id(take_id),.peak(rec_peak),.start_record(start_record),.stop_record(stop_record),
  .erase_record(erase_record),.start_play(start_play),.stop_play(stop_play),.download_request(download_request),
  .download_offset(download_offset),.download_done(download_done),.download_data(download_data),.download_bytes(download_bytes));
 studio_recorder recorder(
  .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.sample_pcm(dac_sample),.disconnect(disconnect),.transport_busy(transport_busy),
  .select_valid(proto_slot_valid||(ui_slot_valid&&!record_protocol_busy)),.select_slot(proto_slot_valid?proto_slot:ui_slot),
  .start_record(start_record||(ui_rec_start&&!record_protocol_busy)),.stop_record(stop_record||ui_rec_stop),.erase_record(erase_record||(ui_rec_erase&&!record_protocol_busy)),
  .start_play(start_play||(ui_play_start&&!record_protocol_busy)),.stop_play(stop_play||ui_play_stop),
  .lease_open(lease_open),.lease_close(lease_close),.save_ack(save_ack),.progress_ack(progress_ack),.ack_value(ack_value),
  .download_request(download_request),.download_offset(download_offset),.download_done(download_done),.download_data(download_data),.download_bytes(download_bytes),
  .selected(selected),.lease(lease),.saved_on_phone(saved_on_phone),.confirmed_bytes(confirmed_bytes),
  .state(rec_state),.other_state(other_state),.fault(rec_fault),.sample_count(sample_count),.committed_samples(committed_samples),
  .pcm_crc(pcm_crc),.take_id(take_id),.other_samples(other_samples),.other_take(other_take),.peak(rec_peak),
  .ready_for_command(ready_for_command),.busy(recorder_busy),.erase_accepted(recorder_erase_accepted),.playback_active(playback_active),.playback_pcm(playback_pcm),
  .mem_request(mem_request),.mem_write(mem_write),.mem_address(mem_address),.mem_write_data(mem_write_data),
  .mem_ready(mem_ready),.mem_done(mem_done),.mem_error(mem_error),.mem_read_data(mem_read_data));
 wire flute_suona;
 wire [6:0] drum_volume,flute_volume;wire drum_bank_set,drum_bank_value,drum_bank;
 wire drum_recalibrate;reg [15:0] drum_reset_count=0;
 always @(posedge clk) begin
  if(!rst_n)drum_reset_count<=0;
  else if(drum_recalibrate)drum_reset_count<=16'd50000;
  else if(drum_reset_count!=0)drum_reset_count<=drum_reset_count-1'b1;
 end
 wire drum_rst_n=rst_n && drum_reset_count==0;
 wire [1:0] rec_confirm;wire about_open;
 wire flute_calibrated,flute_fault;wire [7:0] flute_gain;wire [6:0] flute_note;
 wire signed [15:0] flute_raw,drum_raw,flute_pcm,air_drum_pcm;
 ui_master_volume flute_level(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.level(flute_volume),.pcm_in(flute_raw),.pcm_out(flute_pcm));
 ui_master_volume drum_level(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.level(drum_volume),.pcm_in(drum_raw),.pcm_out(air_drum_pcm));
 instrument_flute flute(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.timbre_suona(flute_suona),
  .keys_n(flute_keys_n),.spi_miso(flute_spi_miso),.spi_cs_n(flute_spi_cs_n),
  .spi_clk(flute_spi_clk),.spi_mosi(flute_spi_mosi),.uart_tx(flute_uart_tx),
  .status_led(),.pcm(flute_raw),.pressed(),.gain(flute_gain),.note(flute_note),
  .calibrated(flute_calibrated),.breath_gate(),.fault(flute_fault),.fingering_valid());
 wire drum_event_valid;wire [1:0] drum_event_zone;wire [7:0] drum_event_velocity;
 wire [511:0] drum_snapshot;
 instrument_air_drum air_drum(.bank_set(drum_bank_set),.bank_value(drum_bank_value),.clk(clk),.rst_n(drum_rst_n),.sample_tick(sample_tick),
  .key_s1_n(air_drum_key_n),.imu_rx(imu_rx),.imu_tx(imu_tx),.imu2_rx(imu2_rx),.imu2_tx(imu2_tx),
  .pcm(drum_raw),.active_mask(),.mode_out(),.bank_out(drum_bank),.imu_link(),.imu_configured(),
  .audio_fault(),.monitor_led_n(),
  .led_event_valid(drum_event_valid),.led_event_zone(drum_event_zone),.led_event_velocity(drum_event_velocity),
  .monitor_snapshot(drum_snapshot));
 // AD05: independent four-panel output on D17; keyboard spectrum stays on A18.
 wire drum_frame_tick;wire [31:0] drum_levels,drum_phases;
 drum_panel_envelopes drum_lights(.clk(clk),.rst_n(drum_rst_n),.frame_tick(drum_frame_tick),
  .event_valid(drum_event_valid),.event_zone(drum_event_zone),.event_velocity(drum_event_velocity),
  .frame_levels(drum_levels),.frame_phases(drum_phases));
 ws2812_drum_panels drum_leds(.clk(clk),.rst_n(rst_n),.panel_levels(drum_levels),.panel_phases(drum_phases),
  .frame_tick(drum_frame_tick),.din(drum_led_din));
 reg [511:0] drum_telemetry_snapshot;
 always @* begin
  drum_telemetry_snapshot=drum_snapshot;
  drum_telemetry_snapshot[52*8+:32]=drum_levels;
  drum_telemetry_snapshot[58*8+:32]=drum_phases;
 end
 wire [7:0] drum_debug_data;wire drum_debug_valid,drum_debug_ready,drum_debug_tx;
 performance_telemetry drum_monitor(.clk(clk),.rst_n(rst_n),.snapshot_in(drum_telemetry_snapshot),
  .tx_data(drum_debug_data),.tx_valid(drum_debug_valid),.tx_ready(drum_debug_ready));
 air_uart_tx drum_monitor_uart(.clk(clk),.rst_n(rst_n),.tx_data(drum_debug_data),
  .tx_valid(drum_debug_valid),.tx_ready(drum_debug_ready),.tx(drum_debug_tx),.tx_done());
 studio_audio_looper looper(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.live_pcm(live_pcm),.mix_pcm(loop_pcm),.busy(loop_busy),
  .blocked(playback_active||score_active||guide_status==1||lease),.panic(panic||playback_active),
  .request(loop_request),.command(loop_command),.payload_length(loop_payload_length),.payload(loop_payload),
  .done(loop_done),.result(loop_result),.reply_length(loop_reply_length),.reply(loop_reply),
  .mem_request(loop_mem_request),.mem_write(loop_mem_write),.mem_address(loop_mem_address),.mem_write_data(loop_mem_write_data),
  .mem_ready(loop_mem_ready),.mem_done(loop_mem_done),.mem_error(loop_mem_error),.mem_read_data(loop_mem_read_data));
 instrument_audio #(.ENABLE_PEDAL(1),.ENABLE_LOOP(1),.USE_SCANNED_KEYS(1),.ENABLE_FLUTE(1),.ENABLE_AIR_DRUM(1)) audio(
  .pedal_down(sustain_down),
  .loop_pcm(loop_pcm),.ui_live_pcm(live_pcm),
  .playback_active(playback_active),.playback_pcm(playback_pcm),.playback_muted(muted),
  .flute_pcm(flute_pcm),
  .air_drum_pcm(air_drum_pcm),
  .scan_valid(mapped_valid),.scan_kind(mapped_kind),.scan_key(mapped_key),.scan_value(mapped_value),
  .scan_keys(mapped_down),.scan_error(|key_idle_low || |key_drive_fail),.fx_enabled(fx_enabled),.fx_values(fx_values),.clk(clk),.key_n(key_n&&panel_reset_n),.uart_rx(1'b1),
  .rgb_led(rgb_led),.matrix_din(matrix_din),.HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN),.PA_EN(PA_EN),
  .ui_note_valid(note_valid),.ui_note_kind(note_kind),.ui_note_key(note_key),.ui_note_value(note_value),
  .master_volume(muted?7'd0:volume),.panic(panic),.ui_note_ready(note_ready),.ui_rst_n(rst_n),
  .ui_sample_tick(sample_tick),.ui_dac_sample(dac_sample),.ui_spectrum(spectrum),
  .ui_active(active),
  .octave_group(octave_group),.piano_volume(piano_volume),
  .physical_piano_down(physical_keys),.physical_piano_strike(physical_key_strike));
 // PCM5102 was physically removed; onboard HP audio remains connected.
 wire pixel_clk,serial_clk,serializer_reset_clk,video_locked,usb_clk,usb_locked;
 video_pll u_pll(.clkin(clk),.pixel_clk(pixel_clk),.serial_clk(serial_clk),.reset_clk(serializer_reset_clk),.locked(video_locked));
 usb_pll u_usb_pll(.clkin(clk),.usb_clk(usb_clk),.locked(usb_locked));
 wire video_run=video_locked && rst_n, usb_run=video_locked && usb_locked && rst_n;
 reg [15:0] pixel_reset_pipe=0,usb_reset_pipe=0;
 always @(posedge pixel_clk or negedge video_run)
  if(!video_run) pixel_reset_pipe<=0;else pixel_reset_pipe<={pixel_reset_pipe[14:0],1'b1};
 always @(posedge usb_clk or negedge usb_run)
  if(!usb_run) usb_reset_pipe<=0;else usb_reset_pipe<={usb_reset_pipe[14:0],1'b1};
 wire pixel_reset=!pixel_reset_pipe[15],usb_reset=!usb_reset_pipe[15];
 reg [2:0] usb_ready50=0;
 always @(posedge clk) if(!rst_n) usb_ready50<=0;else usb_ready50<={usb_ready50[1:0],!usb_reset};
 wire [1:0] status0,status1;
 wire dp0,dm0,oe0,dp1,dm1,oe1;
 wire [9:0] down0,down1;wire [99:0] xs0,ys0,xs1,ys1;wire [59:0] ids0,ids1;
 assign usb1_dp=oe0 && !usb_reset ? dp0 : 1'bz;
 assign usb1_dm=oe0 && !usb_reset ? dm0 : 1'bz;
 assign usb2_dp=oe1 && !usb_reset ? dp1 : 1'bz;
 assign usb2_dm=oe1 && !usb_reset ? dm1 : 1'bz;
 usb_touch_host host0(.clk(usb_clk),.reset(usb_reset),.dp_i(usb1_dp),.dm_i(usb1_dm),
  .dp_o(dp0),.dm_o(dm0),.oe(oe0),.status(status0),.pressed(),.touch_x(),.touch_y(),
  .contacts(),.updated(),.error_count(),.contact_down(down0),.contact_x(xs0),.contact_y(ys0),.contact_id(ids0));
 usb_touch_host host1(.clk(usb_clk),.reset(usb_reset),.dp_i(usb2_dp),.dm_i(usb2_dm),
  .dp_o(dp1),.dm_o(dm1),.oe(oe1),.status(status1),.pressed(),.touch_x(),.touch_y(),
  .contacts(),.updated(),.error_count(),.contact_down(down1),.contact_x(xs1),.contact_y(ys1),.contact_id(ids1));
 wire choose1=status0!=2 && status1==2;
 wire [273:0] usb_bundle={status1,status0,choose1?ids1:ids0,choose1?ys1:ys0,
                         choose1?xs1:xs0,(status0==2||status1==2)?(choose1?down1:down0):10'b0};
 wire [273:0] touch_mailbox;
 wire touch_updated;
 ui_cdc_snapshot #(.WIDTH(274)) touch_cdc(.src_clk(usb_clk),.src_reset(usb_reset),
  .dst_clk(clk),.dst_reset(!rst_n || !usb_ready50[2]),.src_data(usb_bundle),
  .dst_data(touch_mailbox),.dst_updated(touch_updated));
 wire [273:0] touch_state=usb_ready50[2]?touch_mailbox:274'b0;
 studio_controller controls(
  .panel_valid(panel_valid),.panel_code(panel_code),.panel_ready(panel_ready),.drum_bank(drum_bank),
  .remote_practice(score_started),
  .rec_state(rec_state),.rec_ready(ready_for_command&&!record_protocol_busy),.rec_lease(lease),.rec_selected(selected),.rec_take(take_id),
  .rec_erase_accepted(recorder_erase_accepted&&ui_rec_erase&&!record_protocol_busy),
  .rec_start(ui_rec_start),.rec_stop(ui_rec_stop),.rec_erase(ui_rec_erase),.play_start(ui_play_start),.play_stop(ui_play_stop),
  .slot_valid(ui_slot_valid),.slot_value(ui_slot),.rec_confirm(rec_confirm),.about_open(about_open),
  .drum_volume(drum_volume),.flute_volume(flute_volume),.bank_set(drum_bank_set),.bank_value(drum_bank_value),.drum_recalibrate(drum_recalibrate),.clk(clk),.rst_n(rst_n),.touch_update(touch_updated || !usb_ready50[2]),
  .contact_down(touch_state[9:0]),.contact_x(touch_state[109:10]),.contact_y(touch_state[209:110]),
  .contact_id(touch_state[269:210]),.guide_piece(piece),
  .parameter_sync_enable(1'b1),.parameter_values(bt_parameters),.parameter_valid(bt_local_valid),.parameter_id(bt_local_id),.parameter_value(bt_local_value),.parameter_ready(bt_local_ready),.parameter_ack(bt_local_ack),
  .page(page),.flute_suona(flute_suona),.octave_group(),.master_volume(),.piano_volume(),
  .panic(panic),
  .desired_keys(desired_notes),.touch_count(touch_count),
  .guide_action(guide_action),.guide_arg(guide_arg),.menu_open(menu_open),
  .muted(),.lissa_run(lissa_run),.lissa_delay(lissa_delay),.fx_enabled(),.fx_values());
 ui_mask_events key_events(.clk(clk),.rst_n(rst_n),.flush(panic||pitch_reset),.desired(desired_notes),
  .valid(note_valid),.ready(note_ready),.kind(note_kind),.note(note_key),.value(note_value));
 instrument_guide guide(.clk(clk),.rst_n(rst_n),.page(page==5?3'd4:page),.octave_group(octave_group),
  .action(score_view&&guide_action!=3?3'd0:guide_action),.argument(guide_arg),.menu_open(menu_open),.keys_down(playing_keys),
  .key_strike(physical_key_strike&(octave_group==0?32'hffffff80:32'hffffffff)),
  .piece(piece),.status(guide_status),.tempo_mode(tempo_mode),.bpm(bpm),.step_index(step_index),.total_steps(total_steps),
  .position(position),.correct(correct),.missed(missed),.errors(errors),.feedback(feedback),.blocked(blocked),
  .target_keys(builtin_target_keys),.bars(bars),.cues(cues),.progress_percent(progress_percent));
 `include "src/ui_math.vh"
 reg [6:0] voice_count,volume_percent,piano_percent;
 reg [3:0] count8[0:3];reg [4:0] count16[0:1];reg [5:0] count32;
 function [3:0] pop8;
  input [7:0] bits;
  reg [1:0] a,b,c,d;
  begin
   a={1'b0,bits[0]}+bits[1];b={1'b0,bits[2]}+bits[3];
   c={1'b0,bits[4]}+bits[5];d={1'b0,bits[6]}+bits[7];
   pop8=({2'b0,a}+{2'b0,b})+({2'b0,c}+{2'b0,d});
  end
 endfunction
 integer j;
 always @(posedge clk) begin
  for(j=0;j<4;j=j+1)count8[j]<=pop8(active[j*8 +:8]);
  for(j=0;j<2;j=j+1)count16[j]<={1'b0,count8[2*j]}+count8[2*j+1];
  count32<={1'b0,count16[0]}+count16[1];
  voice_count<={1'b0,count32};
  volume_percent<=ui_volume_percent(volume);piano_percent<=ui_volume_percent(piano_volume);
 end
 // Bit 19 uses one reserved display bit for the frame-atomic flute timbre.
 // All existing mailbox offsets remain stable.
 wire [63:0] display_cues=score_view?score_cues:cues;
 wire [1:0] display_guide_status=score_view?(score_active?2'd1:score_completed?2'd3:2'd0):guide_status;
 wire display_tempo=score_view?!score_waiting:tempo_mode;
 wire [1001:0] state_bundle={fx_values,fx_enabled,lissa_delay,lissa_run,muted,display_cues,bars,16'b0,target_keys,progress_percent,errors,missed,correct,position,total_steps,step_index,bpm,menu_open,blocked,display_tempo,feedback,display_guide_status,piece,touch_state[209:110],touch_state[109:10],touch_state[9:0],spectrum,touch_state[273:270],16'b0,playing_keys,voice_count,touch_count,6'b0,flute_suona,piano_percent,volume_percent,octave_group,page};
 reg [255:0] studio_bundle;
 reg [6:0] drum_percent,flute_percent;
 reg [31:0] previous_committed;reg previous_slot;reg [25:0] time_fraction;reg [7:0] record_seconds;
 always @(posedge clk)begin
  drum_percent<=ui_volume_percent(drum_volume);flute_percent<=ui_volume_percent(flute_volume);
  // Incremental exact rational time avoids a wide combinational divider.
  if(!rst_n||previous_slot!=selected||committed_samples<previous_committed)begin
   previous_committed<=0;time_fraction<=0;record_seconds<=0;
  end else if(committed_samples!=previous_committed)begin
   time_fraction<=time_fraction+((committed_samples-previous_committed)<<3);previous_committed<=committed_samples;
  end else if(time_fraction>=390625)begin time_fraction<=time_fraction-390625;record_seconds<=record_seconds+1'b1;end
  previous_slot<=selected;
 end
 always @* begin
  studio_bundle=0;studio_bundle[3:0]=rec_state;studio_bundle[11:4]=rec_fault;
  studio_bundle[12]=selected;studio_bundle[13]=lease;studio_bundle[14]=saved_on_phone;studio_bundle[15]=ready_for_command;
  studio_bundle[47:16]=committed_samples;studio_bundle[79:48]=sample_count;studio_bundle[111:80]=take_id;studio_bundle[143:112]=confirmed_bytes;
  studio_bundle[144]=!bt_link_stable;studio_bundle[145]=bt_online;
  studio_bundle[152:146]=drum_percent;studio_bundle[159:153]=flute_percent;studio_bundle[160]=drum_bank;
  studio_bundle[162:161]=rec_confirm;studio_bundle[163]=about_open;studio_bundle[164]=flute_calibrated;
  studio_bundle[165]=flute_fault;studio_bundle[173:166]=flute_gain;studio_bundle[180:174]=flute_note;studio_bundle[188:181]=record_seconds;
  studio_bundle[189]=score_view;studio_bundle[190]=score_active;studio_bundle[191]=score_waiting;studio_bundle[192]=score_completed;
  studio_bundle[208:193]=score_current;studio_bundle[224:209]=score_total;
 end
 wire [1257:0] state_pending;wire state_updated;
 ui_cdc_snapshot #(.WIDTH(1258)) state_cdc(.src_clk(clk),.src_reset(!rst_n || !video_locked),
  .dst_clk(pixel_clk),.dst_reset(pixel_reset),.src_data({studio_bundle,state_bundle}),.dst_data(state_pending),.dst_updated(state_updated));
 reg [1257:0] visible=0;
 wire [10:0] x;wire [9:0] y;wire de,hs,vs,frame_end,frame_prepare;
 video_timing timing(.pixel_clk(pixel_clk),.reset(pixel_reset),.x(x),.y(y),.de(de),.hsync(hs),.vsync(vs),.frame_end(frame_end),.frame_prepare(frame_prepare));
 always @(posedge pixel_clk) if(pixel_reset) visible<=0;else if(frame_prepare) visible<=state_pending;
 wire [15:0] scope_pair;
 wire [8:0] scope_x;
 studio_scope_coordinate scope_coordinate(.x(x),.column(scope_x));
 ui_scope_capture scope(.audio_clk(clk),.audio_reset(!rst_n || !video_locked),.sample_tick(sample_tick),.pcm(dac_sample),
  .pixel_clk(pixel_clk),.pixel_reset(pixel_reset),.frame_end(frame_end),.read_x(scope_x),.sample_pair(scope_pair));
 wire lissa_pixel;
 wire [6:0] lissa_x=x>=132&&x<324?((x-132)*2)/3:0;
 wire [6:0] lissa_y=y>=148&&y<340?((y-148)*2)/3:0;
 ui_lissajous_capture lissa(.audio_clk(clk),.audio_reset(!rst_n||!video_locked),.sample_tick(sample_tick),.pcm(dac_sample),
  .delay_select(lissa_delay),.pixel_clk(pixel_clk),.pixel_reset(pixel_reset),.frame_end(frame_end),.run(visible[933]),
  .read_x(lissa_x),.read_y(lissa_y),.pixel(lissa_pixel));
 wire [23:0] rgb;wire video_de,video_hs,video_vs;
 wire ui_mem_request,ui_mem_write,ui_mem_ready,ui_mem_done,ui_mem_error;
 wire [28:0] ui_mem_address;wire [255:0] ui_mem_write_data,ui_mem_read_data;
 studio_renderer renderer(.studio_state(visible[1257:1002]),.pixel_clk(pixel_clk),.reset(pixel_reset),
  .host_clk(clk),.host_rst_n(rst_n),.ui_mem_request(ui_mem_request),.ui_mem_write(ui_mem_write),.ui_mem_address(ui_mem_address),.ui_mem_write_data(ui_mem_write_data),
  .ui_mem_ready(ui_mem_ready),.ui_mem_done(ui_mem_done),.ui_mem_error(ui_mem_error),.ui_mem_read_data(ui_mem_read_data),
  .muted(visible[932]),.lissa_run(visible[933]),.lissa_delay(visible[935:934]),
  .fx_enabled(visible[938:936]),.fx_values(visible[1001:939]),.lissa_pixel(lissa_pixel),
  .page(visible[2:0]),.flute_suona(visible[19]),
  .octave_group(visible[4:3]),
  .master_percent(visible[11:5]),
  .piano_percent(visible[18:12]),
  .touch_count(visible[29:26]),
  .voice_count(visible[36:30]),
  .keys_down(visible[68:37]),
  .usb_status(visible[88:85]),
  .spectrum(visible[216:89]),
  .contact_down(visible[226:217]),
  .contact_x(visible[326:227]),
  .contact_y(visible[426:327]),
  .piece(visible[428:427]),
  .status(visible[430:429]),
  .feedback(visible[432:431]),
  .tempo_mode(visible[433:433]),
  .blocked(visible[434:434]),
  .menu_open(visible[435:435]),
  .bpm(visible[443:436]),
  .step_index(visible[449:444]),
  .total_steps(visible[455:450]),
  .position(visible[471:456]),
  .correct(visible[478:472]),
  .missed(visible[485:479]),
  .errors(visible[492:486]),
  .progress_percent(visible[499:493]),
  .target_keys(visible[531:500]),
  .bars(visible[867:548]),
  .cues(visible[931:868]),
  .x(x),.y(y),.de(de),.hs(hs),.vs(vs),.scope_pair(scope_pair),
  .rgb(rgb),.out_de(video_de),.out_hs(video_hs),.out_vs(video_vs));
 // Registered output after the eight-cycle tile/text renderer.
 reg [23:0] linked_rgb_q;reg linked_de_q,linked_hs_q,linked_vs_q;
 always @(posedge pixel_clk)begin
  linked_rgb_q<=rgb;linked_de_q<=video_de;linked_hs_q<=video_hs;linked_vs_q<=video_vs;
  if(pixel_reset)begin linked_rgb_q<=0;linked_de_q<=0;linked_hs_q<=0;linked_vs_q<=0;end
 end
 hdmi_tx u_tx(.pixel_clk(pixel_clk),.serial_clk(serial_clk),.reset_clk(serializer_reset_clk),.reset(pixel_reset),.rgb(linked_rgb_q),
  .de(linked_de_q),.hsync(linked_hs_q),.vsync(linked_vs_q),.tmds_clk_p(tmds_clk_p),.tmds_clk_n(tmds_clk_n),
  .tmds_data_p(tmds_data_p),.tmds_data_n(tmds_data_n));
 wire video_debug_tx;
 // U15 defaults to AD04-compatible direction telemetry. Set parameter 0 for legacy HDMI diagnostics.
 assign debug_uart_tx=DRUM_MONITOR_UART ? drum_debug_tx : video_debug_tx;
 video_diagnostics diagnostics(.clk(clk),.pixel_clk(pixel_clk),.serial_clk(serial_clk),
  .video_locked(video_locked),.usb_locked(usb_locked),.hpd(hdmi_hpd),.aux_level(hdmi_aux),
  .video_running(!pixel_reset),.frame_end(frame_end),.uart_tx(video_debug_tx));
 wire memory_clk,pll_lock,pll_stop,mem_clk,calibrated;
 wire cmd_ready,wr_data_rdy,rd_data_valid,cmd_en,wr_data_en,wr_data_end;
 wire [2:0] cmd;wire [28:0] addr;wire [255:0] wr_data,rd_data;
 wire [2:0] rec_cmd,ui_cmd;wire rec_cmd_en,ui_cmd_en,rec_wr_en,ui_wr_en,rec_wr_end,ui_wr_end;
 wire rec_cmd_ready,ui_cmd_ready,rec_wr_ready,ui_wr_ready,rec_rd_valid,ui_rd_valid;
 wire [28:0] rec_addr,ui_addr;wire [255:0] rec_wr_data,ui_wr_data;
 wire [2:0] loop_cmd,pair_cmd;wire loop_cmd_en,loop_wr_en,loop_wr_end,loop_cmd_ready,loop_wr_ready,loop_rd_valid;
 wire pair_cmd_en,pair_wr_en,pair_wr_end,pair_cmd_ready,pair_wr_ready,pair_rd_valid;
 wire [28:0] loop_addr,pair_addr;wire [255:0] loop_wr_data,pair_wr_data;
 record_ddr_bridge loop_bridge(.clk(clk),.rst_n(rst_n),.request(loop_mem_request),.write_request(loop_mem_write),
  .address(loop_mem_address),.write_data(loop_mem_write_data),.ready(loop_mem_ready),.done(loop_mem_done),.error(loop_mem_error),.read_data(loop_mem_read_data),
  .mem_clk(mem_clk),.calibrated(calibrated),.cmd_ready(loop_cmd_ready),.wr_data_rdy(loop_wr_ready),
  .rd_data_valid(loop_rd_valid),.rd_data(rd_data),.cmd(loop_cmd),.cmd_en(loop_cmd_en),.addr(loop_addr),.wr_data(loop_wr_data),
  .wr_data_en(loop_wr_en),.wr_data_end(loop_wr_end));
 record_ddr_bridge bridge(.clk(clk),.rst_n(rst_n),.request(mem_request),.write_request(mem_write),
  .address(mem_address),.write_data(mem_write_data),.ready(mem_ready),.done(mem_done),.error(mem_error),.read_data(mem_read_data),
  .mem_clk(mem_clk),.calibrated(calibrated),.cmd_ready(rec_cmd_ready),.wr_data_rdy(rec_wr_ready),
  .rd_data_valid(rec_rd_valid),.rd_data(rd_data),.cmd(rec_cmd),.cmd_en(rec_cmd_en),.addr(rec_addr),.wr_data(rec_wr_data),
  .wr_data_en(rec_wr_en),.wr_data_end(rec_wr_end));
 record_ddr_bridge ui_bridge(.clk(clk),.rst_n(rst_n),.request(ui_mem_request),.write_request(ui_mem_write),
  .address(ui_mem_address),.write_data(ui_mem_write_data),.ready(ui_mem_ready),.done(ui_mem_done),.error(ui_mem_error),.read_data(ui_mem_read_data),
  .mem_clk(mem_clk),.calibrated(calibrated),.cmd_ready(ui_cmd_ready),.wr_data_rdy(ui_wr_ready),
  .rd_data_valid(ui_rd_valid),.rd_data(rd_data),.cmd(ui_cmd),.cmd_en(ui_cmd_en),.addr(ui_addr),.wr_data(ui_wr_data),
  .wr_data_en(ui_wr_en),.wr_data_end(ui_wr_end));
 (* syn_preserve=1 *) reg [1:0] arb_reset_pipe;
 always @(posedge mem_clk or negedge rst_n)if(!rst_n)arb_reset_pipe<=0;else arb_reset_pipe<={arb_reset_pipe[0],1'b1};
 studio_ddr_arbiter audio_memory_arbiter(.clk(mem_clk),.rst_n(arb_reset_pipe[1]&&calibrated),
  .a_cmd(rec_cmd),.b_cmd(loop_cmd),.a_cmd_en(rec_cmd_en),.b_cmd_en(loop_cmd_en),.a_addr(rec_addr),.b_addr(loop_addr),.a_data(rec_wr_data),.b_data(loop_wr_data),
  .a_wr_en(rec_wr_en),.b_wr_en(loop_wr_en),.a_wr_end(rec_wr_end),.b_wr_end(loop_wr_end),
  .a_cmd_ready(rec_cmd_ready),.b_cmd_ready(loop_cmd_ready),.a_wr_ready(rec_wr_ready),.b_wr_ready(loop_wr_ready),.a_rd_valid(rec_rd_valid),.b_rd_valid(loop_rd_valid),
  .cmd_ready(pair_cmd_ready),.wr_ready(pair_wr_ready),.rd_valid(pair_rd_valid),.cmd(pair_cmd),.cmd_en(pair_cmd_en),.addr(pair_addr),.wr_data(pair_wr_data),.wr_en(pair_wr_en),.wr_end(pair_wr_end));
 studio_ddr_arbiter memory_arbiter(.clk(mem_clk),.rst_n(arb_reset_pipe[1]&&calibrated),
  .a_cmd(pair_cmd),.b_cmd(ui_cmd),.a_cmd_en(pair_cmd_en),.b_cmd_en(ui_cmd_en),.a_addr(pair_addr),.b_addr(ui_addr),.a_data(pair_wr_data),.b_data(ui_wr_data),
  .a_wr_en(pair_wr_en),.b_wr_en(ui_wr_en),.a_wr_end(pair_wr_end),.b_wr_end(ui_wr_end),
  .a_cmd_ready(pair_cmd_ready),.b_cmd_ready(ui_cmd_ready),.a_wr_ready(pair_wr_ready),.b_wr_ready(ui_wr_ready),.a_rd_valid(pair_rd_valid),.b_rd_valid(ui_rd_valid),
  .cmd_ready(cmd_ready),.wr_ready(wr_data_rdy),.rd_valid(rd_data_valid),.cmd(cmd),.cmd_en(cmd_en),.addr(addr),.wr_data(wr_data),.wr_en(wr_data_en),.wr_end(wr_data_end));
 Gowin_PLL Gowin_PLL_inst(.clkin(clk),.init_clk(clk),.reset(!rst_n),
  .enclk0(1'b1),.enclk1(1'b1),.enclk2(pll_stop),.clkout0(),.clkout1(),.clkout2(memory_clk),.lock(pll_lock));
 DDR3_Memory_Interface_Top u_ddr3(
  .memory_clk(memory_clk),.pll_stop(pll_stop),.clk(clk),.rst_n(rst_n),.pll_lock(pll_lock),
  .cmd_ready(cmd_ready),.cmd(cmd),.cmd_en(cmd_en),.addr(addr),.wr_data_rdy(wr_data_rdy),
  .wr_data(wr_data),.wr_data_en(wr_data_en),.wr_data_end(wr_data_end),.wr_data_mask(32'd0),
  .rd_data(rd_data),.rd_data_valid(rd_data_valid),.rd_data_end(),
  .sr_req(1'b0),.ref_req(1'b0),.sr_ack(),.ref_ack(),.init_calib_complete(calibrated),
  .clk_out(mem_clk),.burst(1'b0),.ddr_rst(),
  .O_ddr_addr(ddr_addr),.O_ddr_ba(ddr_bank),.O_ddr_cs_n(ddr_cs),.O_ddr_ras_n(ddr_ras),
  .O_ddr_cas_n(ddr_cas),.O_ddr_we_n(ddr_we),.O_ddr_clk(ddr_ck),.O_ddr_clk_n(ddr_ck_n),
  .O_ddr_cke(ddr_cke),.O_ddr_odt(ddr_odt),.O_ddr_reset_n(ddr_reset_n),.O_ddr_dqm(ddr_dm),
  .IO_ddr_dq(ddr_dq),.IO_ddr_dqs(ddr_dqs),.IO_ddr_dqs_n(ddr_dqs_n));
endmodule
