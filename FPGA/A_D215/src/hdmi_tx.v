`timescale 1ns/1ps
// Video-only DVI-compatible TMDS on the HDMI connector; no audio/HDCP/packets.
// OSER10 + ELVDS_OBUF + LVCMOS33D follows Sipeed's ordinary Dock reference.
module hdmi_tx (
    input wire pixel_clk,
    input wire reset_clk, // phase-aligned pixel-frequency PLL output, dedicated tree
    input wire serial_clk, // exactly 5x pixel_clk, DDR => 10 bits/pixel
    input wire reset,
    input wire [23:0] rgb,
    input wire de,
    input wire hsync,
    input wire vsync,
    output wire tmds_clk_p,
    output wire tmds_clk_n,
    output wire [2:0] tmds_data_p,
    output wire [2:0] tmds_data_n
);
    genvar lane;
    generate for (lane = 0; lane < 3; lane = lane + 1) begin : channels
        wire [9:0] symbol;
        wire serial_data;
        // Use a separate slow reset clock tree for fabric reset flops. Its falling edge is
        // aligned with a falling FCLK edge (5:1 clocks, both PLL phases zero).
        // Avoid routing 256.25 MHz through fabric reset flops; the final flop
        // is placed next to its OSER10 in instrument.cst. Recovery/removal
        // remain timed. Assertion remains asynchronous on PLL lock loss.
        reg [2:0] serial_reset_pipe = 3'b111 /* synthesis syn_preserve=1 */;
        always @(negedge reset_clk or posedge reset) begin
            if (reset) serial_reset_pipe <= 3'b111;
            else serial_reset_pipe <= {serial_reset_pipe[1:0], 1'b0};
        end
        tmds_encoder u_encoder (
            .pixel_clk(pixel_clk), .reset(reset), .de(de),
            .data(rgb[lane*8 +: 8]),
            .control(lane == 0 ? {vsync, hsync} : 2'b00),
            .symbol(symbol)
        );
        OSER10 u_serializer (
            .Q(serial_data), .D0(symbol[0]), .D1(symbol[1]),
            .D2(symbol[2]), .D3(symbol[3]), .D4(symbol[4]),
            .D5(symbol[5]), .D6(symbol[6]), .D7(symbol[7]),
            .D8(symbol[8]), .D9(symbol[9]),
            .PCLK(pixel_clk), .FCLK(serial_clk), .RESET(serial_reset_pipe[2])
        );
        ELVDS_OBUF u_output (
            .I(serial_data), .O(tmds_data_p[lane]), .OB(tmds_data_n[lane])
        );
    end endgenerate
    ELVDS_OBUF u_clock_output (
        .I(pixel_clk), .O(tmds_clk_p), .OB(tmds_clk_n)
    );
endmodule
