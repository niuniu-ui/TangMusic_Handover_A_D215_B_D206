// One fixed-pitch voice. Note number selects it; velocity controls amplitude.
// The waveform is a synthesized harmonic tone, not a sampled acoustic piano.
module midi_piano_voice #(
    parameter [6:0] NOTE = 7'd41,
    parameter [31:0] PHASE_STEP = 32'd0,
    parameter [3:0] MIDI_CHANNEL_ZERO = 4'd9
)(
    input wire clk, input wire rst_n, input wire sample_tick,
    input wire event_valid,
    input wire [3:0] event_kind, channel_zero,
    input wire [6:0] key_or_cc, value,
    output wire signed [15:0] pcm,
    output wire active
);
    reg [31:0] phase;
    reg [15:0] envelope;
    reg [6:0] velocity;
    reg held, sustain, attacking;
    reg [3:0] decay_divider;
    wire [15:0] decay_step = (envelope >> 12) + 16'd1;
    wire signed [15:0] wave;
    piano_wave_rom u_wave(.address(phase[31:24]), .sample(wave));

    // Explicitly signed products avoid unsigned MIDI values corrupting the
    // negative half-wave. Q7 velocity * Q16 envelope; 23 fractional bits.
    reg signed [23:0] velocity_product;
    reg signed [40:0] envelope_product;
    // Product is bounded to signed 39 bits; extract the Q23 integer explicitly.
    assign pcm = envelope_product[38:23];
    assign active = (envelope != 0);
    always @(posedge clk) begin
        if (!rst_n) begin
            velocity_product <= 0; envelope_product <= 0;
        end else begin
            velocity_product <= wave * $signed({1'b0, velocity});
            envelope_product <= velocity_product * $signed({1'b0, envelope});
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            phase <= 0; envelope <= 0; velocity <= 0;
            held <= 0; sustain <= 0; attacking <= 0; decay_divider <= 0;
        end else begin
            if (sample_tick) begin
                phase <= phase + PHASE_STEP;
                decay_divider <= decay_divider+1'b1;
                if (held || sustain) begin
                    if (attacking) begin
                        if (envelope >= 16'd65023) begin
                            envelope <= 16'hFFFF; attacking <= 0;
                        end else envelope <= envelope + 16'd512;
                    end else if (decay_divider == 0) begin
                        if (envelope > decay_step) envelope <= envelope-decay_step;
                        else envelope <= 0;
                    end
                end else begin
                    // A full-scale release lasts <= 4096 samples (~84 ms).
                    attacking <= 0;
                    if (envelope > 16'd16) envelope <= envelope-16'd16;
                    else envelope <= 0;
                end
            end
            // Events have priority over simultaneous sample ticks.
            if (event_valid && channel_zero == MIDI_CHANNEL_ZERO) begin
                if (event_kind == 4'h9 && key_or_cc == NOTE && value != 0) begin
                    held <= 1; attacking <= 1; velocity <= value;
                    if (envelope == 0) phase <= 0;
                end else if ((event_kind == 4'h8 || (event_kind == 4'h9 && value == 0)) && key_or_cc == NOTE) begin
                    held <= 0;
                end else if (event_kind == 4'hB) begin
                    case (key_or_cc)
                        7'd64: sustain <= (value >= 64);
                        7'd123: held <= 0; // All Notes Off respects sustain.
                        7'd120: begin // All Sound Off, including sustained notes.
                            held <= 0; sustain <= 0; attacking <= 0;
                            envelope <= 0; velocity <= 0;
                        end
                        7'd121: sustain <= 0;
                        default: begin end
                    endcase
                end
            end
        end
    end
endmodule
