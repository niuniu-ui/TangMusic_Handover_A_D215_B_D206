`timescale 1ns/1ps
// CA77 (2026-10-16): bits 0..5 = front KEY1..6, bits 6/7 = rear holes 1/2.
// A set bit means pressed. Rear 11/(10 or 01)/00 = low/middle/high.
// Front fingering and rear register selection are independent: an invalid
// front transition holds the last base pitch, never the entire old octave.
module flute_fingering(
    input wire clk, rst_n,
    input wire [7:0] pressed,
    output reg [6:0] note,
    output reg fingering_valid
);
    reg [7:0] decoded; // {valid front pattern, low-register MIDI pitch}
    reg [6:0] held_base;
    wire [6:0] register_offset=pressed[7:6]==2'b11 ? 7'd0 :
                               pressed[7:6]==2'b00 ? 7'd24 : 7'd12;
    always @* begin
        case (pressed[5:0])
            6'h3f: decoded = {1'b1, 7'd43};
            6'h1f: decoded = {1'b1, 7'd45};
            6'h0f: decoded = {1'b1, 7'd47};
            6'h07: decoded = {1'b1, 7'd48};
            6'h03: decoded = {1'b1, 7'd50};
            6'h01: decoded = {1'b1, 7'd52};
            6'h06: decoded = {1'b1, 7'd53};
            6'h00: decoded = {1'b1, 7'd54};
            default: decoded = 8'b0;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin held_base<=7'd43;note<=7'd55;fingering_valid<=0;end
        else begin
            fingering_valid<=decoded[7];
            if(decoded[7])held_base<=decoded[6:0];
            note<=(decoded[7]?decoded[6:0]:held_base)+register_offset;
        end
    end
endmodule
