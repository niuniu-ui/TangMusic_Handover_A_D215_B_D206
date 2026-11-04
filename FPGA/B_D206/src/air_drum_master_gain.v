`timescale 1ns/1ps
// AD04: x8 after effects, +6.02 dB relative to AD03's x4 (below clipping).
// Keep the calibrated 32-tone spectrum mode at its original level.
module air_drum_master_gain(
    input wire signed [15:0] pcm_in,
    input wire bypass,
    output wire signed [15:0] pcm_out
);
    wire signed [18:0] boosted={pcm_in,3'b000};
    assign pcm_out=bypass ? pcm_in :
        (boosted>19'sd32767 ? 16'sd32767 :
        (boosted< -19'sd32768 ? 16'sh8000 : boosted[15:0]));
endmodule
