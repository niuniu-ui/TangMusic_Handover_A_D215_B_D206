`timescale 1ns/1ps
// Read-only bring-up telemetry on the board's debugger UART (115200, 8N1).
// Runs directly from the 50 MHz reference, even if either PLL fails to lock.
module video_diagnostics #(
    parameter integer REF_HZ = 50000000,
    parameter integer BAUD = 115200,
    parameter integer REPORT_CYCLES = 50000000
) (
    input wire clk, pixel_clk, serial_clk,
    input wire video_locked, usb_locked, hpd, aux_level, video_running,
    input wire frame_end,
    output wire uart_tx
);
    localparam integer BIT_CYCLES = (REF_HZ + BAUD/2) / BAUD;
    localparam integer MESSAGE_BYTES = 42;
    reg [11:0] pixel_div = 0;
    reg frame_toggle = 0;
    always @(posedge pixel_clk) begin
        pixel_div <= pixel_div + 1'b1;
        if (video_running && frame_end) frame_toggle <= ~frame_toggle;
    end
    // The 256.25 MHz serializer clock belongs to the dedicated I/O clock
    // network. A fabric debug counter forced it onto an extra clock route and
    // produced negative minimum-pulse widths. TX below reports PLL lock;
    // pixel/frame activity is still independently observed.

    // Every bit is an independent status or a slow event toggle, not a bus.
    // First-stage D pins alone are excluded from inter-clock timing.
    reg [7:0] meta = 0, synced = 0, previous = 0;
    always @(posedge clk) begin
        meta <= {frame_toggle, video_locked, pixel_div[11],
                 video_running, aux_level, hpd, usb_locked, video_locked};
        synced <= meta;
        previous <= synced;
    end
    reg [7:0] frames = 0;
    reg pixel_seen = 0, serial_seen = 0;
    reg [31:0] report_timer = 0;
    reg [MESSAGE_BYTES*8-1:0] message = 0;
    reg [5:0] bytes_left = 0;
    reg [3:0] bits_left = 0;
    reg [31:0] bit_timer = 0;
    reg [9:0] shift = 10'h3ff;
    assign uart_tx = shift[0];

    function [7:0] digit;
        input value;
        begin digit = value ? "1" : "0"; end
    endfunction
    function [7:0] hex_digit;
        input [3:0] value;
        begin hex_digit = value < 10 ? 8'h30 + value : 8'h41 + value - 10; end
    endfunction

    always @(posedge clk) begin
        if (synced[7] != previous[7] && frames != 255) frames <= frames + 1'b1;
        if (synced[5] != previous[5]) pixel_seen <= 1;
        if (synced[6]) serial_seen <= 1;
        if (report_timer == REPORT_CYCLES-1) begin
            report_timer <= 0;
            if (bytes_left == 0 && bits_left == 0) begin
                message <= {"HDMI1 P=", digit(synced[0]), " U=", digit(synced[1]),
                    " H=", digit(synced[2]), " A=", digit(synced[3]),
                    " R=", digit(synced[4]), " PX=", digit(pixel_seen),
                    " TX=", digit(serial_seen), " F=", hex_digit(frames[7:4]),
                    hex_digit(frames[3:0]), 8'h0d, 8'h0a};
            end
            frames <= 0;
            pixel_seen <= 0;
            serial_seen <= 0;
        end else report_timer <= report_timer + 1'b1;

        if (bits_left != 0) begin
            if (bit_timer == 0) begin
                shift <= {1'b1, shift[9:1]};
                bits_left <= bits_left - 1'b1;
                bit_timer <= BIT_CYCLES-1;
            end else bit_timer <= bit_timer - 1'b1;
        end else if (bytes_left != 0) begin
            shift <= {1'b1, message[MESSAGE_BYTES*8-1 -: 8], 1'b0};
            message <= message << 8;
            bytes_left <= bytes_left - 1'b1;
            bits_left <= 10;
            bit_timer <= BIT_CYCLES-1;
        end
        // Set after the UART state update so the new report starts next cycle.
        if (report_timer == REPORT_CYCLES-1 && bytes_left == 0 && bits_left == 0)
            bytes_left <= MESSAGE_BYTES;
    end
endmodule
