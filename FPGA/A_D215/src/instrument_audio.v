// Tang Mega NEO 138K PG484A: clk=V22 (50 MHz), key_n=AB13,
// Production top selects direct scanned-key events. A18/pad audio is removed.
// Legacy MIDI input is retained only as a selectable core regression path.
// Debug signals stay INTERNAL: do not add event buses to physical top ports.
module instrument_audio #(parameter ENABLE_LOOP=0,ENABLE_PEDAL=0,
    parameter integer USE_SCANNED_KEYS = 0,
    parameter integer ENABLE_FLUTE = 0,
    parameter integer ENABLE_AIR_DRUM = 0,
    parameter integer MATRIX_BRIGHTNESS_SHIFT = 2, // 1: half; 2: quarter; 3: eighth.
    parameter integer MATRIX_BEAT_ACCENT = 0,
    parameter integer MATRIX_PEAK_DOTS = 0,
    parameter integer MATRIX_COLUMN_MAJOR = 1,
    parameter integer MATRIX_FLIP_X = 1,
    parameter integer MATRIX_FLIP_Y = 0,
    parameter integer MATRIX_TEST_PATTERN = 0,
    parameter integer AUDIO_STARTUP_CYCLES = 10000000,
    parameter integer MIDI_BAUD = 31250,
    parameter [3:0] MIDI_CHANNEL_ZERO = 4'd0 // MIDI channel 1; captured 90/80 messages.
)(
    input wire clk, input wire key_n, input wire uart_rx,
    input wire pedal_down,house_piano,
    input wire scan_valid, input wire [3:0] scan_kind,
    input wire [6:0] scan_key,scan_value, input wire [31:0] scan_keys,
    input wire scan_error,
    input wire signed [15:0] flute_pcm,
    input wire signed [15:0] air_drum_pcm,
    input wire playback_active,playback_muted,input wire [15:0] playback_pcm,
    output wire rgb_led,
    output wire matrix_din, // WS2812B 32x8 matrix DIN, A18
    output wire i2s_bck, output wire i2s_lrck, output wire i2s_din,
    output wire PA_EN,
    input wire ui_note_valid, input wire [3:0] ui_note_kind,
    input wire signed [15:0] loop_pcm,output wire signed [15:0] ui_live_pcm,
    input wire [6:0] ui_note_key, ui_note_value, input wire [6:0] master_volume,
    input wire panic, output wire ui_note_ready,
    input wire [1:0] octave_group,
    input wire [2:0] fx_enabled,input wire [62:0] fx_values,
    input wire [6:0] piano_volume,
    output wire [31:0] physical_piano_down,output reg [31:0] physical_piano_strike,
    output wire ui_rst_n, output wire ui_sample_tick,
    output wire signed [15:0] ui_dac_sample,
    output wire [127:0] ui_spectrum,
    output wire [31:0] ui_active,
    output wire signed [15:0] debug_piano_pcm
);
    localparam integer CLK_HZ = 50000000;
    // Gowin register power-up initialization holds reset for 65536 clocks.
    reg [15:0] por_count = 0;
    (* syn_preserve = 1 *) reg [1:0] key_sync = 0;
    (* syn_preserve = 1 *) reg rst_n = 0;
    always @(posedge clk) rst_n <= key_sync[0] && key_sync[1] && (por_count >= 16'hfffe);
    reg [1:0] previous_group=2;
    // A local registered clear stops the parameter-to-all-voices fanout path.
    (* syn_preserve=1 *) reg pitch_reset=0;
    always @(posedge clk)if(!rst_n)begin previous_group<=2;pitch_reset<=0;end
      else begin previous_group<=octave_group;pitch_reset<=previous_group!=octave_group;end
    always @(posedge clk) begin
        key_sync <= {key_sync[0], key_n};
        if (!key_sync[1]) por_count <= 0;
        else if (!(&por_count)) por_count <= por_count+1'b1;
    end

    (* syn_keep = 1 *) wire event_valid;
    (* syn_keep = 1 *) wire [3:0] event_kind, channel_zero;
    (* syn_keep = 1 *) wire [6:0] key_or_cc, value;
    (* syn_keep = 1 *) wire [31:0] event_count, byte_count, framing_errors, timeout_errors;
    (* syn_keep = 1 *) wire [127:0] notes_down;
    (* syn_keep = 1 *) wire [6:0] last_note, last_velocity, pressure_note, last_pressure;
    (* syn_keep = 1 *) wire [6:0] last_cc, last_cc_value;
    (* syn_keep = 1 *) wire [3:0] last_note_channel, pressure_channel, last_cc_channel;
    (* syn_keep = 1 *) wire last_note_on;

    generate if (USE_SCANNED_KEYS) begin: scanned_input
        assign event_valid=scan_valid; assign event_kind=scan_kind;
        assign channel_zero=MIDI_CHANNEL_ZERO; assign key_or_cc=scan_key; assign value=scan_value;
        reg [31:0] count;
        always @(posedge clk) if(!rst_n) count<=0; else if(scan_valid) count<=count+1'b1;
        assign event_count=count;
        assign byte_count=0; assign framing_errors=0; assign timeout_errors=0;
    end else begin: no_serial_note_input
     assign event_valid=0;assign event_kind=0;assign channel_zero=0;assign key_or_cc=0;assign value=0;
     assign event_count=0;assign byte_count=0;assign framing_errors=0;assign timeout_errors=0;
    end endgenerate
    midi_state #(.PAD_CHANNEL_ZERO(MIDI_CHANNEL_ZERO)) u_state (
        .clk(clk), .rst_n(rst_n), .event_valid(event_valid), .event_kind(event_kind),
        .channel_zero(channel_zero), .key_or_cc(key_or_cc), .value(value),
        .notes_down(notes_down), .last_note(last_note), .last_velocity(last_velocity),
        .last_note_channel(last_note_channel), .last_note_on(last_note_on),
        .pressure_note(pressure_note), .last_pressure(last_pressure),
        .pressure_channel(pressure_channel), .last_cc(last_cc),
        .last_cc_value(last_cc_value), .last_cc_channel(last_cc_channel)
    );
    assign physical_piano_down=USE_SCANNED_KEYS ? scan_keys : notes_down[72:41];
    always @(posedge clk)begin
      physical_piano_strike<=0;
      if(rst_n&&!panic&&!pitch_reset&&event_valid&&channel_zero==MIDI_CHANNEL_ZERO&&
         event_kind==9&&value!=0&&key_or_cc>=41&&key_or_cc<=72)
        physical_piano_strike[key_or_cc-41]<=1;
    end

    // PCM5102A external DAC; keep the onboard active-low amplifier disabled.
    localparam integer WARMUP_W = AUDIO_STARTUP_CYCLES < 1 ? 1 : $clog2(AUDIO_STARTUP_CYCLES+1);
    reg [WARMUP_W-1:0] audio_warmup;
    wire audio_ready = rst_n && (audio_warmup == AUDIO_STARTUP_CYCLES);
    assign PA_EN = 1'b1; // Disable the unused onboard amplifier.
    always @(posedge clk) begin
        if (!rst_n) audio_warmup <= 0;
        else if (!audio_ready) audio_warmup <= audio_warmup+1'b1;
    end
    wire sample_tick;
    wire signed [15:0] audio_pcm,piano_pcm;
    wire [31:0] audio_active;
    assign debug_piano_pcm=piano_pcm;
    wire merged_valid;
    wire [3:0] merged_kind,merged_channel;
    wire [6:0] merged_key,merged_value;
    ui_note_merge u_touch_merge(
        .clk(clk),.rst_n(rst_n),.panic(panic),.clear_owners(pitch_reset),
        .physical_valid(event_valid),.physical_kind(event_kind),.physical_channel(channel_zero),
        .physical_key(key_or_cc),.physical_value(value),
        .touch_valid(ui_note_valid),.touch_kind(ui_note_kind),.touch_key(ui_note_key),
        .touch_value(ui_note_value),.touch_ready(ui_note_ready),
        .event_valid(merged_valid),.event_kind(merged_kind),.channel_zero(merged_channel),
        .key_or_cc(merged_key),.value(merged_value)
    );
    wire synth_valid;wire [3:0] synth_kind,synth_channel;wire [6:0] synth_key,synth_value;
    studio_sustain_events #(.CHANNEL(MIDI_CHANNEL_ZERO)) pedal_events(
        .clk(clk),.rst_n(rst_n),.clear(panic||pitch_reset),.pedal_down(ENABLE_PEDAL?pedal_down:1'b0),
        .in_valid(merged_valid),.in_kind(merged_kind),.in_channel(merged_channel),.in_key(merged_key),.in_value(merged_value),
        .out_valid(synth_valid),.out_kind(synth_kind),.out_channel(synth_channel),.out_key(synth_key),.out_value(synth_value));
    midi_keyboard_synth_v2 #(.MIDI_CHANNEL_ZERO(MIDI_CHANNEL_ZERO)) u_synth (
        .clk(clk), .rst_n(rst_n), .sample_tick(sample_tick),
        .event_valid(synth_valid), .event_kind(synth_kind), .channel_zero(synth_channel),
        .key_or_cc(synth_key), .value(synth_value), .pcm(piano_pcm), .active(audio_active),
        .octave_group(octave_group),.house_piano(house_piano),.pitch_reset(pitch_reset)
    );
    wire signed [15:0] piano_volume_pcm,piano_effect_pcm;
    piano_effects u_effects(.clk(clk),.rst_n(rst_n),.clear(panic||pitch_reset),
        .sample_tick(sample_tick),.pcm_in(piano_pcm),.enabled(fx_enabled),.parameters(fx_values),
        .pcm_out(piano_effect_pcm),.ready(),.frame_done());
    ui_master_volume u_piano_volume(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),
        .level(piano_volume),.pcm_in(piano_effect_pcm),.pcm_out(piano_volume_pcm));
    // Preserve piano gain/rounding; add the CA76 voice at its original level.
    assign audio_pcm=$signed(piano_volume_pcm) >>> 1;
    // Three signed sources need 18 bits before the final saturation.
    wire signed [17:0] mixed_pcm=$signed({{2{audio_pcm[15]}},audio_pcm})+
        (ENABLE_FLUTE ? $signed({{2{flute_pcm[15]}},flute_pcm}) : 18'sd0)+
        (ENABLE_AIR_DRUM ? $signed({{2{air_drum_pcm[15]}},air_drum_pcm}) : 18'sd0);
    // Saturation prevents wraparound when both instruments reach full scale.
    // With the flute silent, the existing piano pipeline is bit-identical.
    reg signed [15:0] combined_pcm;
    always @(posedge clk) begin
        if(!rst_n) combined_pcm<=0;
        else if(mixed_pcm>18'sd32767) combined_pcm<=16'sh7fff;
        else if(mixed_pcm< -18'sd32768) combined_pcm<=16'sh8000;
        else combined_pcm<=mixed_pcm[15:0];
    end
    // The analyzer sees exactly the sample latched by the DAC, including mute.
    wire signed [15:0] dac_sample;
    assign ui_live_pcm=combined_pcm;
    wire signed [16:0] loop_sum=$signed(combined_pcm)+(ENABLE_LOOP?$signed(loop_pcm):17'sd0);
    wire signed [15:0] final_live_pcm=loop_sum>32767?16'sh7fff:loop_sum< -32768?16'sh8000:loop_sum[15:0];
    wire signed [15:0] master_pcm;
    wire signed [15:0] replay_level_pcm;
    ui_master_volume replay_level(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),
        .level(master_volume),.pcm_in(playback_pcm),.pcm_out(replay_level_pcm));
    ui_master_volume u_master(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),
        .level(master_volume),.pcm_in(final_live_pcm),.pcm_out(master_pcm));
    assign ui_rst_n=rst_n;
    assign ui_sample_tick=sample_tick;
    assign ui_dac_sample=dac_sample;
    assign ui_active=audio_active;
    // Preserve the previous 1024-cycle sample cadence and latch instant.
    wire signed [15:0] output_pcm=audio_ready ?
        (playback_active ? (playback_muted ? 16'd0 : replay_level_pcm) : master_pcm) : 16'sd0;
    audio_sample_clock u_sample_clock(.clk(clk),.rst_n(rst_n),.pcm_in(output_pcm),
        .sample_tick(sample_tick),.sample_pcm(dac_sample));
    // Both I2S channels carry the exact same held 16-bit mix; 32-bit slots.
    pcm5102_i2s_tx #(.SAMPLE_BITS(16),.STEREO(0)) u_pcm5102(
        .clk(clk),.rst_n(rst_n),.pcm_mono(dac_sample),.pcm_right(16'sd0),
        .bck(i2s_bck),.lrck(i2s_lrck),.din(i2s_din));


    // Read-only audio branch: no backpressure, no change to the sound path.
    wire [127:0] spectrum_levels, spectrum_peaks;
    wire [3:0] spectrum_beat;
    assign ui_spectrum=spectrum_levels;
    spectrum_analyzer_32 u_spectrum (
        .clk(clk), .rst_n(rst_n), .sample_tick(sample_tick), .pcm(dac_sample),
        .levels(spectrum_levels), .peaks(spectrum_peaks), .beat(spectrum_beat)
    );
    ws2812_matrix_32x8 #(
        .BRIGHTNESS_SHIFT(MATRIX_BRIGHTNESS_SHIFT),
        .BEAT_ACCENT(MATRIX_BEAT_ACCENT), .PEAK_DOTS(MATRIX_PEAK_DOTS),
        .COLUMN_MAJOR(MATRIX_COLUMN_MAJOR), .FLIP_X(MATRIX_FLIP_X),
        .FLIP_Y(MATRIX_FLIP_Y), .TEST_PATTERN(MATRIX_TEST_PATTERN)
    ) u_matrix (
        .clk(clk), .rst_n(rst_n), .levels(spectrum_levels),
        .peaks(spectrum_peaks), .beat(spectrum_beat), .din(matrix_din)
    );

    reg [25:0] heartbeat;
    reg [23:0] activity_timer;
    reg [7:0] red, green, blue;
    always @(posedge clk) begin
        if (!rst_n) begin
            heartbeat <= 0; activity_timer <= 0;
        end
        else begin
            if (heartbeat == CLK_HZ-1) heartbeat <= 0;
            else heartbeat <= heartbeat+1'b1;
            // Activity reflects decoded messages on the selected MIDI channel.
            if (event_valid && channel_zero == MIDI_CHANNEL_ZERO)
                activity_timer <= CLK_HZ/5; // Hold feedback for 200 ms.
            else if (activity_timer != 0) activity_timer <= activity_timer-1'b1;
        end
    end
    always @* begin
        red = 0; green = 0; blue = 0;
        if ((USE_SCANNED_KEYS && scan_error) || framing_errors != 0 || timeout_errors != 0) red = 8'd24;
        else if (activity_timer != 0) green = 24;
        else blue = heartbeat < CLK_HZ/2 ? 8'd8 : 8'd1;
    end
    ws2812_status #(.CLK_HZ(CLK_HZ)) u_led (
        .clk(clk), .rst_n(rst_n), .red(red), .green(green), .blue(blue), .led_out(rgb_led)
    );
endmodule


