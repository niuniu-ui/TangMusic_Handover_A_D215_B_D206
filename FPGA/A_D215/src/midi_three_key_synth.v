// Legacy 3-key reference used by tb_audio only; NOT used by the current FPGA top.
// Generated pitch constants. UART channel 10 is the existing PC bridge output.
// Fs = 50000000 / 1024 = 48828.125 Hz; do not substitute 48000 here.
module midi_three_key_synth #(
    parameter [3:0] MIDI_CHANNEL_ZERO = 4'd9
)(
    input wire clk, input wire rst_n, input wire sample_tick,
    input wire event_valid,
    input wire [3:0] event_kind, channel_zero,
    input wire [6:0] key_or_cc, value,
    output reg signed [15:0] pcm, output wire [2:0] active
);
    wire signed [15:0] voice0;
    // Key 1: F2, 87.307057858 Hz.
    midi_piano_voice #(.NOTE(7'd41), .PHASE_STEP(32'd7679610),
                       .MIDI_CHANNEL_ZERO(MIDI_CHANNEL_ZERO)) u_voice0 (
        .clk(clk), .rst_n(rst_n), .sample_tick(sample_tick),
        .event_valid(event_valid), .event_kind(event_kind), .channel_zero(channel_zero),
        .key_or_cc(key_or_cc), .value(value), .pcm(voice0), .active(active[0])
    );
    wire signed [15:0] voice1;
    // Key 2: G2, 97.998858995 Hz.
    midi_piano_voice #(.NOTE(7'd43), .PHASE_STEP(32'd8620071),
                       .MIDI_CHANNEL_ZERO(MIDI_CHANNEL_ZERO)) u_voice1 (
        .clk(clk), .rst_n(rst_n), .sample_tick(sample_tick),
        .event_valid(event_valid), .event_kind(event_kind), .channel_zero(channel_zero),
        .key_or_cc(key_or_cc), .value(value), .pcm(voice1), .active(active[1])
    );
    wire signed [15:0] voice2;
    // Key 3: A2, 110.000000000 Hz.
    midi_piano_voice #(.NOTE(7'd45), .PHASE_STEP(32'd9675702),
                       .MIDI_CHANNEL_ZERO(MIDI_CHANNEL_ZERO)) u_voice2 (
        .clk(clk), .rst_n(rst_n), .sample_tick(sample_tick),
        .event_valid(event_valid), .event_kind(event_kind), .channel_zero(channel_zero),
        .key_or_cc(key_or_cc), .value(value), .pcm(voice2), .active(active[2])
    );
    wire signed [17:0] mixed = {{2{voice0[15]}},voice0}
                               + {{2{voice1[15]}},voice1}
                               + {{2{voice2[15]}},voice2};
    // Fixed 1/4 gain leaves headroom even with all three voices at 127.
    always @(posedge clk) begin
        if (!rst_n) pcm <= 0;
        else if (sample_tick) pcm <= mixed[17:2];
    end
endmodule
