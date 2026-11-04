// PCM5102A: Philips I2S, 32-bit slots; selectable 16/24-bit signed PCM.
// clk = 50 MHz; BCK = clk/16 = 3.125 MHz; LRCK = BCK/64 = 48828.125 Hz.
// LRCK low = left, high = right. MSB follows each LRCK edge by ONE bit.
// SCK on the external module is tied to GND (BCK-referenced internal PLL).
//
// Both serializers share clk/rst_n. PT8211 takes the prior completed modal
// frame at clock 32+1024*n; this module snapshots that still-stable stereo
// frame at clock 48+1024*n. The next modal result is ready much later in the
// frame. STEREO=0 retains the legacy mono interface; STEREO=1 latches both
// channels together. No backpressure or change to sample_tick.
module pcm5102_i2s_tx #(parameter integer SAMPLE_BITS=16,STEREO=0)(
    input wire clk, rst_n,
    input wire signed [SAMPLE_BITS-1:0] pcm_mono,pcm_right,
    output reg bck, lrck, din
);
    reg [2:0] divider;
    reg [5:0] bit_index;
    reg [SAMPLE_BITS-1:0] frame_sample,frame_right;

    always @(posedge clk) begin
        if (!rst_n) begin
            divider <= 0;
            // One startup padding bit aligns the left boundary with PT8211.
            bit_index <= 6'd62;
            frame_sample <= 0;
            frame_right <= 0;
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
                            frame_right <= STEREO?pcm_right:pcm_mono;
                            din <= pcm_mono[SAMPLE_BITS-1];
                        end
                        default: begin
                            if(bit_index<SAMPLE_BITS)din<=frame_sample[SAMPLE_BITS-1-bit_index];
                            else if(bit_index>=32&&bit_index<32+SAMPLE_BITS)
                                din<=frame_right[SAMPLE_BITS-1-bit_index[4:0]];
                            else din <= 0; // Low unused bits of each slot are zero.
                        end
                    endcase
                end
            end
        end
    end
endmodule
