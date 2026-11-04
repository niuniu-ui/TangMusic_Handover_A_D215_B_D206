// Application example: all-channel last-event registers plus the gate bitmap
// of the JP-1 pad channel (displayed channel 10 = zero-based index 9).
// Note/pressure/CC snapshots each carry their own channel and number.
module midi_state #(
    parameter [3:0] PAD_CHANNEL_ZERO = 4'd9
)(
    input wire clk, input wire rst_n, input wire event_valid,
    input wire [3:0] event_kind, channel_zero,
    input wire [6:0] key_or_cc, value,
    output reg [127:0] notes_down,
    output reg [6:0] last_note, last_velocity,
    output reg [3:0] last_note_channel,
    output reg last_note_on,
    output reg [6:0] pressure_note, last_pressure,
    output reg [3:0] pressure_channel,
    output reg [6:0] last_cc, last_cc_value,
    output reg [3:0] last_cc_channel
) /* synthesis syn_preserve = 1 */;
    always @(posedge clk) begin
        if (!rst_n) begin
            notes_down <= 0;
            last_note <= 0; last_velocity <= 0; last_note_channel <= 0;
            last_note_on <= 0;
            pressure_note <= 0; last_pressure <= 0; pressure_channel <= 0;
            last_cc <= 0; last_cc_value <= 0; last_cc_channel <= 0;
        end else if (event_valid) begin
            case (event_kind)
                4'h8, 4'h9: begin
                    last_note <= key_or_cc; last_velocity <= value;
                    last_note_channel <= channel_zero;
                    last_note_on <= event_kind == 4'h9;
                    if (channel_zero == PAD_CHANNEL_ZERO)
                        notes_down[key_or_cc] <= event_kind == 4'h9;
                end
                4'hA: begin
                    pressure_note <= key_or_cc; last_pressure <= value;
                    pressure_channel <= channel_zero;
                end
                4'hB: begin
                    last_cc <= key_or_cc; last_cc_value <= value;
                    last_cc_channel <= channel_zero;
                    // MIDI all sound off / all notes off for tracked channel.
                    if (channel_zero == PAD_CHANNEL_ZERO &&
                        (key_or_cc == 7'd120 || key_or_cc == 7'd123)) notes_down <= 0;
                end
                default: begin end
            endcase
        end
    end
endmodule
