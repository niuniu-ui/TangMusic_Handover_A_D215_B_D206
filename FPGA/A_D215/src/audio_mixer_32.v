// Balanced, pipelined signed adder tree: 32 independent physical-key voices.
// Gain = 1/8. Saturation protects dense chords from signed wraparound.
// All five tree stages update each clk; samples are 1024 clk cycles apart.
module audio_mixer_32(
    input wire clk, input wire rst_n, input wire sample_tick,
    input wire [511:0] voices,
    output reg signed [15:0] pcm
);
    wire signed [20:0] leaf [0:31];
    reg signed [20:0] sum1 [0:15];
    reg signed [20:0] sum2 [0:7];
    reg signed [20:0] sum3 [0:3];
    reg signed [20:0] sum4 [0:1];
    reg signed [20:0] sum5;
    genvar g;
    generate for (g=0; g<32; g=g+1) begin: input_sign
        assign leaf[g] = {{5{voices[g*16+15]}}, voices[g*16 +: 16]};
    end endgenerate
    integer i;
    wire signed [20:0] attenuated = sum5 >>> 3;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i=0;i<16;i=i+1) sum1[i] <= 0;
            for (i=0;i<8;i=i+1) sum2[i] <= 0;
            for (i=0;i<4;i=i+1) sum3[i] <= 0;
            for (i=0;i<2;i=i+1) sum4[i] <= 0;
            sum5 <= 0; pcm <= 0;
        end else begin
            for (i=0;i<16;i=i+1) sum1[i] <= leaf[2*i]+leaf[2*i+1];
            for (i=0;i<8;i=i+1) sum2[i] <= sum1[2*i]+sum1[2*i+1];
            for (i=0;i<4;i=i+1) sum3[i] <= sum2[2*i]+sum2[2*i+1];
            for (i=0;i<2;i=i+1) sum4[i] <= sum3[2*i]+sum3[2*i+1];
            sum5 <= sum4[0]+sum4[1];
            if (sample_tick) begin
                if (attenuated > 21'sd32767) pcm <= 16'sd32767;
                else if (attenuated < -21'sd32768) pcm <= -16'sd32768;
                else pcm <= attenuated[15:0];
            end
        end
    end
endmodule
