// PT8211: 16-bit signed, MSB first, RIGHT-JUSTIFIED (not Philips I2S).
// WS=0: right, WS=1: left, according to PT8211 v1.7 page 4.
// All logic uses clk; BCK is an output signal, not an internal clock.
// 50 MHz / (2 * 16 * 32) = 48828.125 stereo sample pairs / second.
module pt8211_tx #(
    parameter integer HALF_BIT_CYCLES = 16
)(
    input wire clk, input wire rst_n,
    input wire signed [15:0] pcm_mono,
    output reg sample_tick,
    output wire signed [15:0] sample_pcm, // Exact held DAC word for read-only analysis.
    output reg bck, output reg ws, output reg din
);
    localparam integer DIV_W = $clog2(HALF_BIT_CYCLES+1);
    reg [DIV_W-1:0] divider;
    reg [4:0] bit_index;
    reg [15:0] shift_reg, left_sample;
    assign sample_pcm = left_sample;
    always @(posedge clk) begin
        if (!rst_n) begin
            divider <= 0; bit_index <= 31;
            bck <= 0; ws <= 0; din <= 0; sample_tick <= 0;
            shift_reg <= 0; left_sample <= 0;
        end else begin
            sample_tick <= 0;
            if (divider == HALF_BIT_CYCLES-1) begin
                divider <= 0;
                bck <= ~bck;
                if (bck) begin // Falling edge: 320 ns before DAC samples DIN.
                    if (bit_index == 31) begin
                        bit_index <= 0; ws <= 0;
                        shift_reg <= pcm_mono; din <= pcm_mono[15];
                        left_sample <= pcm_mono; sample_tick <= 1;
                    end else if (bit_index == 15) begin
                        bit_index <= 16; ws <= 1;
                        shift_reg <= left_sample; din <= left_sample[15];
                    end else begin
                        bit_index <= bit_index+1'b1;
                        shift_reg <= {shift_reg[14:0], 1'b0};
                        din <= shift_reg[14];
                    end
                end
            end else divider <= divider+1'b1;
        end
    end
endmodule
