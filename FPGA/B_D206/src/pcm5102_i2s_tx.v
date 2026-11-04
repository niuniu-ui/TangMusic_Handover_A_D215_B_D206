// PCM5102A: Philips I2S, 32-bit slots, signed 16-bit PCM in bits 31:16.
// clk = 50 MHz; BCK = clk/16 = 3.125 MHz; LRCK = BCK/64 = 48828.125 Hz.
// LRCK low = left, high = right. MSB follows each LRCK edge by ONE bit.
// SCK on the external module is tied to GND (BCK-referenced internal PLL).
//
// Read-only mirror of the original DAC's held sample. Both serializers share
// clk/rst_n. PT8211 latches a new sample on clock 32 + 1024*n; this module
// snapshots that held word on clock 48 + 1024*n, then sends the same word to
// both channels. No backpressure or change to the existing sample_tick.
module pcm5102_i2s_tx(
    input wire clk, rst_n,
    input wire signed [15:0] pcm_mono,
    output reg bck, lrck, din
);
    reg [2:0] divider;
    reg [5:0] bit_index;
    reg [15:0] frame_sample;

    always @(posedge clk) begin
        if (!rst_n) begin
            divider <= 0;
            // One startup padding bit aligns the left boundary with PT8211.
            bit_index <= 6'd62;
            frame_sample <= 0;
            bck <= 0;
            lrck <= 1;
            din <= 0;
        end else begin
            divider <= divider + 1'b1;
            if (divider == 3'd7) begin
                bck <= ~bck;
                if (bck) begin // Falling edge; receiver samples on rising edge.
                    bit_index <= bit_index + 1'b1;
                    case (bit_index)
                        6'd63: begin lrck <= 0; din <= 0; end
                        6'd31: begin lrck <= 1; din <= 0; end
                        6'd0: begin
                            frame_sample <= pcm_mono;
                            din <= pcm_mono[15];
                        end
                        default: begin
                            if (bit_index < 6'd16 ||
                                (bit_index >= 6'd32 && bit_index < 6'd48))
                                din <= frame_sample[4'd15-bit_index[3:0]];
                            else din <= 0; // Low 16 bits of each slot are zero.
                        end
                    endcase
                end
            end
        end
    end
endmodule
