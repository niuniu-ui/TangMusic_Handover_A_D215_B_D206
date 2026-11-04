`timescale 1ns/1ps
// Preferred detailed timing in the supplied EDID, bytes 54..71.
// H: active 1024, front porch 160, sync 20, back porch 140 = 1344.
// V: active 600, front porch 12, sync 3, back porch 20 = 635.
// Pixel clock MUST be 51.25 MHz (see video_pll.v).
module video_timing (
    input wire pixel_clk,
    input wire reset,
    output reg [10:0] x,
    output reg [9:0] y,
    output wire de,
    output wire hsync,
    output wire vsync,
    output reg frame_end,
    output reg frame_prepare
);
    localparam H_ACTIVE = 1024, H_FRONT = 160, H_SYNC = 20, H_BACK = 140;
    localparam V_ACTIVE = 600, V_FRONT = 12, V_SYNC = 3, V_BACK = 20;
    localparam H_TOTAL = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam V_TOTAL = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    always @(posedge pixel_clk) begin
        if (reset) begin
            x <= 0;
            y <= 0;
        end else if (x == H_TOTAL - 1) begin
            x <= 0;
            if (y == V_TOTAL - 1) y <= 0;
            else y <= y + 1'b1;
        end else begin
            x <= x + 1'b1;
        end
        // Predict the last pixel one cycle early. The registered pulse is
        // still asserted exactly at x=1343,y=634, but its high-fanout users
        // no longer see the coordinate comparator in their enable path.
        if (reset) frame_end <= 0;
        else frame_end <= (x == H_TOTAL - 2) && (y == V_TOTAL - 1);
        // Commit visible UI state BEFORE the vertical blank, giving the DDR
        // artwork cache 35 lines to prefill the next scene without a blank frame.
        // Keep frame_end unchanged for waveform/history bank handovers.
        if (reset) frame_prepare <= 0;
        else frame_prepare <= (x == H_TOTAL - 2) && (y == V_ACTIVE - 1);
    end

    // x/y include blanking coordinates: consume them only when de is high.
    assign de = !reset && (x < H_ACTIVE) && (y < V_ACTIVE);
    assign hsync = !reset && (x >= H_ACTIVE + H_FRONT) &&
                            (x < H_ACTIVE + H_FRONT + H_SYNC);
    assign vsync = !reset && (y >= V_ACTIVE + V_FRONT) &&
                            (y < V_ACTIVE + V_FRONT + V_SYNC);
endmodule
