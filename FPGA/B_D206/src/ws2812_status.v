// One board RGB LED. Snapshot GRB at start of each frame, MSB first.
// 50 MHz: bit=1.26 us, zero high=0.40 us, one high=0.80 us.
// A 10 ms low interval also satisfies the WS2812 latch/reset interval.
module ws2812_status #(
    parameter integer CLK_HZ = 50000000
)(
    input wire clk, input wire rst_n,
    input wire [7:0] red, green, blue,
    output reg led_out
);
    localparam integer BIT_CYCLES = (CLK_HZ+400000)/800000;
    localparam integer T0H = CLK_HZ/2500000;
    localparam integer T1H = CLK_HZ/1250000;
    localparam integer GAP_CYCLES = CLK_HZ/100;
    localparam integer GAP_W = $clog2(GAP_CYCLES+1);
    localparam integer BIT_W = $clog2(BIT_CYCLES+1);
    reg sending;
    reg [GAP_W-1:0] gap_timer;
    reg [BIT_W-1:0] bit_timer;
    reg [4:0] bit_index;
    reg [23:0] frame;
    always @(posedge clk) begin
        if (!rst_n) begin
            sending <= 0; gap_timer <= 0; bit_timer <= 0;
            bit_index <= 0; frame <= 0; led_out <= 0;
        end else if (!sending) begin
            led_out <= 0;
            if (gap_timer == GAP_CYCLES-1) begin
                frame <= {green, red, blue}; bit_index <= 23;
                bit_timer <= 0; sending <= 1; gap_timer <= 0;
            end else gap_timer <= gap_timer+1'b1;
        end else begin
            led_out <= (bit_timer < (frame[bit_index] ? T1H : T0H));
            if (bit_timer == BIT_CYCLES-1) begin
                bit_timer <= 0;
                if (bit_index == 0) begin sending <= 0; gap_timer <= 0; end
                else bit_index <= bit_index-1'b1;
            end else bit_timer <= bit_timer+1'b1;
        end
    end
endmodule
