// Display, USB touch and remote drum synthesis; final audio mixing stays on A.
`timescale 1ns/1ps
module studio_board_b(
 input wire clk,key_n,
 inout wire usb1_dp,usb1_dm,usb2_dp,usb2_dm,
 output wire tmds_clk_p,tmds_clk_n,output wire [2:0] tmds_data_p,tmds_data_n,
 input wire hdmi_hpd,hdmi_aux,output wire debug_uart_tx,rgb_led,
 output wire phy_clk,phy_rst_n,tx_clk,tx_ctl,output wire [3:0] txd,
 input wire rx_clk,rx_ctl,input wire [3:0] rxd,output wire phy_mdc,inout wire phy_mdio,
 output wire [14:0] ddr_addr,output wire [2:0] ddr_bank,
 output wire ddr_cs,ddr_ras,ddr_cas,ddr_we,ddr_ck,ddr_ck_n,ddr_cke,ddr_odt,ddr_reset_n,
 output wire [3:0] ddr_dm,inout wire [31:0] ddr_dq,inout wire [3:0] ddr_dqs,ddr_dqs_n
);
 reg [15:0] por=0;reg [1:0] key_sync=0;reg rst_n=0;
 always @(posedge clk)begin
  key_sync<={key_sync[0],key_n};rst_n<=(&por)&&(&key_sync);
  if(!key_sync[1])por<=0;else if(!(&por))por<=por+1'b1;
 end
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

 wire [7:0] remote_byte,remote_index;wire remote_valid,remote_done,remote_alive,network_link;
 wire [2047:0] drum_peer;wire [1257:0] remote_display_state;wire sample_tick,sample_reset;wire signed [15:0] dac_sample;
 wire [273:0] safe_touch;
 wire [1:0] extra_mode,extra_game_state;
 wire [15:0] extra_elapsed,extra_expected,extra_score;
 wire [7:0] extra_hits,extra_misses,extra_wrong,extra_perfects,extra_combo,extra_max_combo;
 wire extra_game_menu,extra_game_complete;wire [2:0] extra_judgement;
 wire [1:0] extra_test_mode;
 wire [15:0] extra_beat_phase;wire [7:0] extra_beat_index,extra_practice_bpm;wire [2:0] extra_count_in;
 wire [5:0] extra_index;wire [7:0] extra_pending;wire [2:0] extra_song;wire extra_cal_recent;
 studio_extra_control extra_control(.clk(clk),.rst_n(rst_n),.alive(remote_alive),
  .base_page(remote_display_state[2:0]),.octave_group(remote_display_state[4:3]),
  .piano_keys(remote_display_state[68:37]),.touch(touch_state),.touch_to_a(safe_touch),
  .mode(extra_mode),.game_state(extra_game_state),.elapsed_ms(extra_elapsed),
  .expected_ms(extra_expected),.score(extra_score),.hits(extra_hits),.misses(extra_misses),
  .wrong(extra_wrong),.perfects(extra_perfects),.song(extra_song),.cal_recent(extra_cal_recent),
  .game_menu(extra_game_menu),.game_complete(extra_game_complete),.judgement(extra_judgement),
  .test_mode(extra_test_mode),
  .beat_phase_ms(extra_beat_phase),.beat_index(extra_beat_index),.count_in(extra_count_in),.practice_bpm(extra_practice_bpm),.beat_pulse(),
  .combo(extra_combo),.max_combo(extra_max_combo),.index(extra_index),.pending(extra_pending));
 wire [127:0] lab_fft;wire lab_fft_valid,lab_fft_overflow;
 studio_lab_fft lab_analysis(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),
  .sample_reset(sample_reset||!remote_alive),.pcm(dac_sample),
  .levels(lab_fft),.frame_valid(lab_fft_valid),.overflow(lab_fft_overflow));
 wire touch_urgent;
 studio_touch_urgent touch_change(.clk(clk),.rst_n(rst_n),.touch(safe_touch),.urgent(touch_urgent));
 wire [255:0] returned_drum;wire [31:0] drum_block_start,drum_active,drum_faults;wire [7:0] remote_drum_epoch;wire drum_block_valid,drum_fault;
 wire [31:0] drum_note_active;wire [7:0] drum_component_count;
 studio_remote_drum drum_sound(.clk(clk),.rst_n(rst_n),.peer_alive(remote_alive),.peer_payload(drum_peer),
  .test_mode(extra_test_mode),.component_count(drum_component_count),.note_active_mask(drum_note_active),
  .pcm_block(returned_drum),.block_start(drum_block_start),.block_valid(drum_block_valid),.epoch(remote_drum_epoch),
  .active_mask(drum_active),.fault(drum_fault),.faults(drum_faults));
 reg [2047:0] touch_payload;always @*begin
  touch_payload=0;touch_payload[273:0]=safe_touch;touch_payload[319:288]=drum_block_start;
  touch_payload[575:320]=returned_drum;touch_payload[591:576]=drum_block_valid?16'hb2d1:16'd0;
  touch_payload[599:592]=remote_drum_epoch;touch_payload[639:608]=drum_active;touch_payload[640]=drum_fault;
 end
 studio_display_link #(.ROLE(1)) net(.clk(clk),.rst_n(rst_n),.payload(touch_payload),.urgent(touch_urgent),
  .rx_byte(remote_byte),.rx_index(remote_index),.rx_valid(remote_valid),.rx_done(remote_done),.link_up(network_link),
  .phy_clk(phy_clk),.phy_rst_n(phy_rst_n),.tx_clk(tx_clk),.tx_ctl(tx_ctl),.txd(txd),
  .rx_clk(rx_clk),.rx_ctl(rx_ctl),.rxd(rxd),.phy_mdc(phy_mdc),.phy_mdio(phy_mdio));
 // The phase portrait selects a display-only phase automatically.
 wire [1:0] lissa_delay=2'd2;
 reg [3:0] wave_clear=15;
 always @(posedge clk)if(!rst_n||sample_reset)wave_clear<=15;else wave_clear<={wave_clear[2:0],1'b0};
 (* syn_preserve=1 *)reg [1:0] wave_pixel_reset=3;
 always @(posedge pixel_clk)wave_pixel_reset<={wave_pixel_reset[0],|wave_clear};
 studio_remote_display remote_display(.clk(clk),.rst_n(rst_n),.rx_byte(remote_byte),.rx_index(remote_index),
  .rx_valid(remote_valid),.rx_done(remote_done),.display_state(remote_display_state),
  .sample_tick(sample_tick),.pcm(dac_sample),.sample_reset(sample_reset),.alive(remote_alive),.peer_payload(drum_peer));
 ws2812_status status_led(.clk(clk),.rst_n(rst_n),.red(network_link?8'd0:8'd12),
  .green(remote_alive?8'd12:8'd0),.blue(network_link&&!remote_alive?8'd12:8'd0),.led_out(rgb_led));
 wire [1257:0] state_pending;wire state_updated;
 ui_cdc_snapshot #(.WIDTH(1258)) state_cdc(.src_clk(clk),.src_reset(!rst_n || !video_locked),
  .dst_clk(pixel_clk),.dst_reset(pixel_reset),.src_data(remote_display_state),.dst_data(state_pending),.dst_updated(state_updated));
 reg [1257:0] visible=0;
 // One atomic snapshot of all local game, FFT and status fields per frame.
 wire [7:0] drum_voice_count,drum_recent_peak;
 reg [7:0] activity_epoch=0;
 reg [1:0] activity_mode=0;
 always @(posedge clk)if(!rst_n)begin activity_epoch<=0;activity_mode<=0;end
  else begin activity_epoch<=remote_drum_epoch;activity_mode<=extra_test_mode;end
 wire drum_activity_valid=remote_alive&&drum_block_valid&&activity_epoch==remote_drum_epoch&&activity_mode==extra_test_mode;
 studio_drum_activity drum_activity(.clk(clk),.rst_n(rst_n),
  .enable(drum_activity_valid),
  .active_count(drum_component_count),
  .current_count(drum_voice_count),.peak_count(drum_recent_peak));
 // Rounded kOSC/s at DESIGN Fs=50 MHz/1024; no measured-Fs claim.
 // A local constant table avoids a multiplier/divider in pixel geometry.
 function [12:0] design_rate_k;input [7:0] count;begin case(count)
   8'd0:design_rate_k=13'd0;
   8'd1:design_rate_k=13'd49;
   8'd2:design_rate_k=13'd98;
   8'd3:design_rate_k=13'd146;
   8'd4:design_rate_k=13'd195;
   8'd5:design_rate_k=13'd244;
   8'd6:design_rate_k=13'd293;
   8'd7:design_rate_k=13'd342;
   8'd8:design_rate_k=13'd391;
   8'd9:design_rate_k=13'd439;
   8'd10:design_rate_k=13'd488;
   8'd11:design_rate_k=13'd537;
   8'd12:design_rate_k=13'd586;
   8'd13:design_rate_k=13'd635;
   8'd14:design_rate_k=13'd684;
   8'd15:design_rate_k=13'd732;
   8'd16:design_rate_k=13'd781;
   8'd17:design_rate_k=13'd830;
   8'd18:design_rate_k=13'd879;
   8'd19:design_rate_k=13'd928;
   8'd20:design_rate_k=13'd977;
   8'd21:design_rate_k=13'd1025;
   8'd22:design_rate_k=13'd1074;
   8'd23:design_rate_k=13'd1123;
   8'd24:design_rate_k=13'd1172;
   8'd25:design_rate_k=13'd1221;
   8'd26:design_rate_k=13'd1270;
   8'd27:design_rate_k=13'd1318;
   8'd28:design_rate_k=13'd1367;
   8'd29:design_rate_k=13'd1416;
   8'd30:design_rate_k=13'd1465;
   8'd31:design_rate_k=13'd1514;
   8'd32:design_rate_k=13'd1563;
   8'd33:design_rate_k=13'd1611;
   8'd34:design_rate_k=13'd1660;
   8'd35:design_rate_k=13'd1709;
   8'd36:design_rate_k=13'd1758;
   8'd37:design_rate_k=13'd1807;
   8'd38:design_rate_k=13'd1855;
   8'd39:design_rate_k=13'd1904;
   8'd40:design_rate_k=13'd1953;
   8'd41:design_rate_k=13'd2002;
   8'd42:design_rate_k=13'd2051;
   8'd43:design_rate_k=13'd2100;
   8'd44:design_rate_k=13'd2148;
   8'd45:design_rate_k=13'd2197;
   8'd46:design_rate_k=13'd2246;
   8'd47:design_rate_k=13'd2295;
   8'd48:design_rate_k=13'd2344;
   8'd49:design_rate_k=13'd2393;
   8'd50:design_rate_k=13'd2441;
   8'd51:design_rate_k=13'd2490;
   8'd52:design_rate_k=13'd2539;
   8'd53:design_rate_k=13'd2588;
   8'd54:design_rate_k=13'd2637;
   8'd55:design_rate_k=13'd2686;
   8'd56:design_rate_k=13'd2734;
   8'd57:design_rate_k=13'd2783;
   8'd58:design_rate_k=13'd2832;
   8'd59:design_rate_k=13'd2881;
   8'd60:design_rate_k=13'd2930;
   8'd61:design_rate_k=13'd2979;
   8'd62:design_rate_k=13'd3027;
   8'd63:design_rate_k=13'd3076;
   8'd64:design_rate_k=13'd3125;
   8'd65:design_rate_k=13'd3174;
   8'd66:design_rate_k=13'd3223;
   8'd67:design_rate_k=13'd3271;
   8'd68:design_rate_k=13'd3320;
   8'd69:design_rate_k=13'd3369;
   8'd70:design_rate_k=13'd3418;
   8'd71:design_rate_k=13'd3467;
   8'd72:design_rate_k=13'd3516;
   8'd73:design_rate_k=13'd3564;
   8'd74:design_rate_k=13'd3613;
   8'd75:design_rate_k=13'd3662;
   8'd76:design_rate_k=13'd3711;
   8'd77:design_rate_k=13'd3760;
   8'd78:design_rate_k=13'd3809;
   8'd79:design_rate_k=13'd3857;
   8'd80:design_rate_k=13'd3906;
   8'd81:design_rate_k=13'd3955;
   8'd82:design_rate_k=13'd4004;
   8'd83:design_rate_k=13'd4053;
   8'd84:design_rate_k=13'd4102;
   8'd85:design_rate_k=13'd4150;
   8'd86:design_rate_k=13'd4199;
   8'd87:design_rate_k=13'd4248;
   8'd88:design_rate_k=13'd4297;
   8'd89:design_rate_k=13'd4346;
   8'd90:design_rate_k=13'd4395;
   8'd91:design_rate_k=13'd4443;
   8'd92:design_rate_k=13'd4492;
   8'd93:design_rate_k=13'd4541;
   8'd94:design_rate_k=13'd4590;
   8'd95:design_rate_k=13'd4639;
   8'd96:design_rate_k=13'd4688;
   8'd97:design_rate_k=13'd4736;
   8'd98:design_rate_k=13'd4785;
   8'd99:design_rate_k=13'd4834;
   8'd100:design_rate_k=13'd4883;
   8'd101:design_rate_k=13'd4932;
   8'd102:design_rate_k=13'd4980;
   8'd103:design_rate_k=13'd5029;
   8'd104:design_rate_k=13'd5078;
   8'd105:design_rate_k=13'd5127;
   8'd106:design_rate_k=13'd5176;
   8'd107:design_rate_k=13'd5225;
   8'd108:design_rate_k=13'd5273;
   8'd109:design_rate_k=13'd5322;
   8'd110:design_rate_k=13'd5371;
   8'd111:design_rate_k=13'd5420;
   8'd112:design_rate_k=13'd5469;
   8'd113:design_rate_k=13'd5518;
   8'd114:design_rate_k=13'd5566;
   8'd115:design_rate_k=13'd5615;
   8'd116:design_rate_k=13'd5664;
   8'd117:design_rate_k=13'd5713;
   8'd118:design_rate_k=13'd5762;
   8'd119:design_rate_k=13'd5811;
   8'd120:design_rate_k=13'd5859;
   8'd121:design_rate_k=13'd5908;
   8'd122:design_rate_k=13'd5957;
   8'd123:design_rate_k=13'd6006;
   8'd124:design_rate_k=13'd6055;
   8'd125:design_rate_k=13'd6104;
   8'd126:design_rate_k=13'd6152;
   8'd127:design_rate_k=13'd6201;
   8'd128:design_rate_k=13'd6250;
   default:design_rate_k=0;
  endcase end endfunction
 reg [12:0] design_kosc=0;
 reg [7:0] ui_component_count=0,ui_drum_peak=0;reg [1:0] ui_test_mode=0;
 // The displayed count and its derived design rate belong to the same sample
 // before entering the existing atomic host-to-pixel snapshot.
 always @(posedge clk)begin
  if(!rst_n)begin design_kosc<=0;ui_component_count<=0;ui_drum_peak<=0;ui_test_mode<=0;end
  else begin
   ui_test_mode<=extra_test_mode;
   if(drum_activity_valid)begin
    design_kosc<=design_rate_k(drum_voice_count);ui_component_count<=drum_voice_count;ui_drum_peak<=drum_recent_peak;
   end else begin design_kosc<=0;ui_component_count<=0;ui_drum_peak<=0;end
  end
 end
 wire [327:0] extra_src={design_kosc,ui_test_mode,ui_component_count,extra_beat_phase,extra_beat_index,extra_count_in,extra_practice_bpm,ui_drum_peak,extra_game_menu,extra_game_complete,extra_judgement,ui_component_count,extra_cal_recent,extra_mode,extra_game_state,remote_display_state[4:3],remote_alive,
  (lab_fft_overflow||drum_fault||(|drum_peer[1967:1936])),remote_display_state[36:30],extra_elapsed,extra_expected,extra_score,
  extra_hits,extra_misses,extra_wrong,extra_perfects,extra_combo,extra_index,extra_song,extra_pending,lab_fft};
 wire [327:0] extra_pending_pix;wire extra_updated;
 ui_cdc_snapshot #(.WIDTH(328)) extra_cdc(.src_clk(clk),.src_reset(!rst_n || !video_locked),
  .dst_clk(pixel_clk),.dst_reset(pixel_reset),.src_data(extra_src),
  .dst_data(extra_pending_pix),.dst_updated(extra_updated));
 reg [327:0] extra_visible=0;
 wire [12:0] v_design_kosc;wire [1:0] v_test_mode;wire [7:0] v_components;
 wire [1:0] v_mode,v_game_state,v_octave;
 wire [15:0] v_beat_phase;wire [7:0] v_beat_index,v_practice_bpm;wire [2:0] v_count_in;wire [7:0] v_drum_peak;
 wire v_game_menu,v_game_complete;wire [2:0] v_judgement;wire [7:0] v_drum_voices;
 wire v_cal_recent,v_alive,v_fft_overflow;wire [6:0] v_voice_count;
 wire [15:0] v_elapsed,v_expected,v_score;wire [7:0] v_hits,v_misses,v_wrong,v_perfects,v_combo;
 wire [5:0] v_index;wire [7:0] v_pending;wire [2:0] v_song;wire [127:0] v_fft;
 assign {v_design_kosc,v_test_mode,v_components,v_beat_phase,v_beat_index,v_count_in,v_practice_bpm,v_drum_peak,v_game_menu,v_game_complete,v_judgement,v_drum_voices,v_cal_recent,v_mode,v_game_state,v_octave,v_alive,v_fft_overflow,v_voice_count,
  v_elapsed,v_expected,v_score,v_hits,v_misses,v_wrong,v_perfects,v_combo,v_index,v_song,v_pending,v_fft}=extra_visible;
 wire [10:0] x;wire [9:0] y;wire de,hs,vs,frame_end,frame_prepare;
 video_timing timing(.pixel_clk(pixel_clk),.reset(pixel_reset),.x(x),.y(y),.de(de),.hsync(hs),.vsync(vs),.frame_end(frame_end),.frame_prepare(frame_prepare));
 always @(posedge pixel_clk) if(pixel_reset)begin visible<=0;extra_visible<=0;end
  else if(frame_prepare)begin visible<=state_pending;extra_visible<=extra_pending_pix;end
 wire [15:0] scope_pair;
 wire [8:0] scope_x;
 studio_scope_coordinate scope_coordinate(.x(x),.column(scope_x));
 ui_scope_capture scope(.audio_clk(clk),.audio_reset(!rst_n || !video_locked || (|wave_clear)),.sample_tick(sample_tick),.pcm(dac_sample),
  .pixel_clk(pixel_clk),.pixel_reset(pixel_reset||wave_pixel_reset[1]),.frame_end(frame_end),.read_x(scope_x),.sample_pair(scope_pair));
 wire lissa_pixel;
 wire [6:0] lissa_x=x>=132&&x<324?((x-132)*2)/3:0;
 wire [6:0] lissa_y=y>=148&&y<340?((y-148)*2)/3:0;
 ui_lissajous_capture lissa(.audio_clk(clk),.audio_reset(!rst_n||!video_locked||(|wave_clear)),.sample_tick(sample_tick),.pcm(dac_sample),
  .delay_select(lissa_delay),.pixel_clk(pixel_clk),.pixel_reset(pixel_reset||wave_pixel_reset[1]),.frame_end(frame_end),.run(visible[933]),
  .read_x(lissa_x),.read_y(lissa_y),.pixel(lissa_pixel));
 wire [23:0] rgb;wire video_de,video_hs,video_vs;
 wire ui_mem_request,ui_mem_write,ui_mem_ready,ui_mem_done,ui_mem_error;
 wire [28:0] ui_mem_address;wire [255:0] ui_mem_write_data,ui_mem_read_data;
 studio_renderer renderer(.studio_state(visible[1257:1002]),
  .extra_mode(v_mode),.extra_game_state(v_game_state),.extra_octave(v_octave),
  .extra_game_menu(v_game_menu),.extra_game_complete(v_game_complete),.extra_judgement(v_judgement),.extra_drum_voices(v_drum_voices),
  .extra_beat_phase(v_beat_phase),.extra_beat_index(v_beat_index),.extra_count_in(v_count_in),.extra_practice_bpm(v_practice_bpm),.extra_drum_peak(v_drum_peak),
  .extra_test_mode(v_test_mode),.extra_component_count(v_components),.extra_design_kosc(v_design_kosc),
  .extra_alive(v_alive),.extra_fft_overflow(v_fft_overflow),.extra_cal_recent(v_cal_recent),.extra_voice_count(v_voice_count),
  .extra_elapsed(v_elapsed),.extra_expected(v_expected),.extra_score(v_score),
  .extra_hits(v_hits),.extra_misses(v_misses),.extra_wrong(v_wrong),.extra_perfects(v_perfects),.extra_combo(v_combo),.extra_index(v_index),
  .extra_song(v_song),.extra_pending(v_pending),.extra_fft(v_fft),.pixel_clk(pixel_clk),.reset(pixel_reset),
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

 video_diagnostics diagnostics(.clk(clk),.pixel_clk(pixel_clk),.serial_clk(serial_clk),
  .video_locked(video_locked),.usb_locked(usb_locked),.hpd(hdmi_hpd),.aux_level(hdmi_aux),
  .video_running(!pixel_reset),.frame_end(frame_end),.uart_tx(debug_uart_tx));
 wire memory_clk,pll_lock,pll_stop,mem_clk,calibrated;
 wire cmd_ready,wr_data_rdy,rd_data_valid,cmd_en,wr_data_en,wr_data_end;
 wire [2:0] cmd;wire [28:0] addr;wire [255:0] wr_data,rd_data;
 record_ddr_bridge ui_bridge(.clk(clk),.rst_n(rst_n),.request(ui_mem_request),.write_request(ui_mem_write),
  .address(ui_mem_address),.write_data(ui_mem_write_data),.ready(ui_mem_ready),.done(ui_mem_done),.error(ui_mem_error),.read_data(ui_mem_read_data),
  .mem_clk(mem_clk),.calibrated(calibrated),.cmd_ready(cmd_ready),.wr_data_rdy(wr_data_rdy),
  .rd_data_valid(rd_data_valid),.rd_data(rd_data),.cmd(cmd),.cmd_en(cmd_en),.addr(addr),.wr_data(wr_data),
  .wr_data_en(wr_data_en),.wr_data_end(wr_data_end));
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
