`timescale 1ns/1ps
// Physical 32-key input. Scan -> contact timing -> internal note events;
// no UART serialization, PC processing or large snapshot FIFO is involved.
module keyboard_scan_input #(
    parameter [6:0] BASE_NOTE = 7'd41
)(
    input wire clk, rst_n, clear,
    input wire [7:0] drive_in, sense_in,
    output wire [7:0] drive_low,
    output wire raw_press_pulse,
    output wire [31:0] keys_down,
    output wire [7:0] idle_low, drive_fail,
    output reg event_valid,
    output reg [3:0] event_kind,
    output reg [6:0] event_key, event_value
);
    wire frame_valid;
    wire [63:0] contacts;
    wire [31:0] velocity_seq;
    wire [511:0] velocity_ticks;
    wire [63:0] velocity_order;
    wire velocity_frame_done,velocity_overflow;
    wire [7:0] scanner_drive_fail;
    assign drive_fail=scanner_drive_fail|{8{velocity_overflow}};
    matrix_scan #(.RELEASE_CYCLES(750), .SETTLE_CYCLES(500), .DEBOUNCE_FRAMES(10)) scanner(
        .clk(clk), .rst(!rst_n), .sense_in(sense_in), .drive_in(drive_in),
        .drive_low(drive_low), .keys(keys_down), .contacts(contacts),
        .frame_valid(frame_valid), .raw_press_pulse(raw_press_pulse),
        .idle_low(idle_low), .drive_fail(scanner_drive_fail));
    key_velocity #(.TIMEOUT_TICKS(10000), .CLOSE_FRAMES(4), .OPEN_FRAMES(8)) velocity(
        .clk(clk), .rst(!rst_n || clear), .frame_valid(frame_valid), .contacts(contacts),
        .velocity_seq(velocity_seq), .velocity_ticks(velocity_ticks), .velocity_order(velocity_order),
        .frame_done(velocity_frame_done),.overflow(velocity_overflow));

    // Capture the scan frame, then publish only after all 32 keys are processed.
    // The velocity engine finishes in <100 clocks, versus 10000 between scans.
    reg [31:0] frame_keys;
    reg [63:0] frame_contacts;
    reg [31:0] snapshot_keys, snapshot_seq;
    reg [63:0] snapshot_contacts;
    reg [511:0] snapshot_ticks;
    reg [31:0] seen_seq, pending, sounding;
    reg [511:0] pending_ticks;
    reg [4:0] cursor;
    wire [15:0] measured_ticks = snapshot_ticks[cursor*16 +:16];
    wire [15:0] strike_ticks = pending_ticks[cursor*16 +:16];
    // Measured key1 response: 24ms -> 32, 9.4ms -> 72, 3.7ms -> 112.
    // 200us ticks; balanced combinational thresholds, no extra sample delay.
    `include "src/key_velocity_curve.vh"

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            frame_keys <= 0;frame_contacts<=0; snapshot_keys <= 0; snapshot_seq <= 0;
            snapshot_contacts <= 0; snapshot_ticks <= 0;
            seen_seq <= 0; pending <= 0; sounding <= 0; pending_ticks <= 0;
            cursor <= 0; event_valid <= 0; event_kind <= 0; event_key <= 0; event_value <= 0;
        end else begin
            if(frame_valid)begin frame_keys<=keys_down;frame_contacts<=contacts;end
            if (velocity_frame_done) begin
                snapshot_keys <= frame_keys; snapshot_seq <= velocity_seq;
                snapshot_contacts <= frame_contacts; snapshot_ticks <= velocity_ticks;
            end
            cursor <= cursor + 1'b1;
            event_valid <= 0;
            if (snapshot_seq[cursor] != seen_seq[cursor]) begin
                seen_seq[cursor] <= snapshot_seq[cursor];
                pending[cursor] <= measured_ticks <= 10000;
                pending_ticks[cursor*16 +:16] <= measured_ticks;
            end else if (pending[cursor] && snapshot_keys[cursor]) begin
                // Wait for the original ~2ms key debounce AND both contacts.
                // A new complete strike can retrigger a still-decaying voice.
                event_valid <= 1; event_kind <= 4'h9;
                event_key <= BASE_NOTE + {2'b0,cursor};
                event_value <= key_velocity_value(strike_ticks);
                sounding[cursor] <= 1; pending[cursor] <= 0;
            end else if (sounding[cursor] && !snapshot_keys[cursor]) begin
                event_valid <= 1; event_kind <= 4'h8;
                event_key <= BASE_NOTE + {2'b0,cursor}; event_value <= 0;
                sounding[cursor] <= 0;
            end
            // Discard a candidate that was released before key debounce.
            if (!snapshot_keys[cursor] && snapshot_contacts[cursor*2 +:2] == 0)
                pending[cursor] <= 0;
        end
    end
endmodule
