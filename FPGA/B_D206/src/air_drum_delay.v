`timescale 1ns/1ps
// Synchronous block-RAM delay, 4096 samples (~83.9 ms), feedback=1/4.
// Valid history avoids costly RAM reset and stale sound after reset.
module air_drum_delay #(parameter integer DEPTH=4096)(
    input wire clk,rst_n,in_valid, input wire signed [15:0] dry,
    input wire [7:0] wet, input wire bypass,
    output reg signed [15:0] pcm, output reg out_valid
);
    reg signed [15:0] memory[0:DEPTH-1];reg [11:0] pointer;
    reg [12:0] filled;reg signed [15:0] ram_read,dry_pipe;
    reg history_valid;
    wire signed [15:0] delayed=history_valid ? ram_read : 16'sd0;
    reg [7:0] wet_pipe;reg bypass_pipe,pending;
    wire signed [24:0] product=delayed*$signed({1'b0,wet_pipe});
    // Truncate signed fractions toward zero. Arithmetic shift alone rounds
    // negative tails downward, leaving -1 circulating forever in the RAM.
    // Correct the shifted integer only when discarded negative bits are
    // nonzero. Avoid a wide bias-before-shift expression: Gowin 1.9.12.03
    // triggers SP00019 on that equivalent carry/shift optimization.
    wire signed [15:0] wet_floor=product[24:9];
    wire wet_fraction=product[24]&&(|product[8:0]);
    wire signed [15:0] wet_scaled=wet_floor+$signed({15'd0,wet_fraction});
    wire signed [17:0] blend=$signed(dry_pipe)+$signed(wet_scaled);
    wire signed [15:0] feedback_floor=$signed(delayed)>>>2;
    wire feedback_fraction=delayed[15]&&(|delayed[1:0]);
    wire signed [15:0] feedback_scaled=feedback_floor+$signed({15'd0,feedback_fraction});
    wire signed [17:0] feedback=$signed(dry_pipe)+$signed(feedback_scaled);
    function signed [15:0] clip;
        input signed [17:0] x;
        begin clip=x>32767 ? 16'sd32767 : (x< -32768 ? -16'sd32768 : x[15:0]);end
    endfunction
    // Explicit WRITE_FIRST single-port template. GW5AST cannot implement the
    // READ_FIRST SP mode inferred by newer Gowin from independent read/write
    // blocks. Reads and writes alternate; in_valid spacing must be >=2 clocks.
    always @(posedge clk) begin
        if(pending) begin memory[pointer]<=clip(feedback);ram_read<=clip(feedback);end
        else if(in_valid) ram_read<=memory[pointer];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin pointer<=0;filled<=0;history_valid<=0;dry_pipe<=0;wet_pipe<=0;bypass_pipe<=0;pending<=0;pcm<=0;out_valid<=0;end
        else begin
            pending<=in_valid;out_valid<=pending;
            if(in_valid) begin history_valid<=(filled==DEPTH);dry_pipe<=dry;wet_pipe<=wet;bypass_pipe<=bypass;end
            if(pending) begin
                pcm<=bypass_pipe ? dry_pipe : clip(blend);
                pointer<=(pointer==DEPTH-1) ? 12'd0 : pointer+12'd1;
                if(filled<DEPTH) filled<=filled+1'b1;
            end
        end
    end
endmodule
