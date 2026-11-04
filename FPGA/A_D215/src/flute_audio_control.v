`timescale 1ns/1ps
// Quiet start, D5/F#5/A5 chime, then breath playing in every rear-hole state.
module flute_audio_control #(parameter integer SAMPLE_HZ=41016)(
    input wire clk,rst_n,sample_ce,input wire [7:0] breath_gain,
    input wire [6:0] finger_note,input wire calibrated,breath_gate,fault,
    output wire amp_enable,output reg voice_gate,test_mode,
    output reg [7:0] voice_gain,output reg [6:0] voice_note
);
    localparam integer START=SAMPLE_HZ/2, TONE=SAMPLE_HZ*18/100,
        GAP=SAMPLE_HZ*8/100, END_BOOT=START+3*(TONE+GAP);
    reg [31:0] boot_samples;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) boot_samples<=0;
        else if(sample_ce && boot_samples<END_BOOT) boot_samples<=boot_samples+1'b1;
    end
    assign amp_enable=rst_n && boot_samples>=SAMPLE_HZ/4;
    always @* begin
        voice_gate=0;voice_gain=0;voice_note=finger_note;test_mode=0;
        if(boot_samples<END_BOOT) begin
            test_mode=1;voice_gain=96;
            if(boot_samples>=START && boot_samples<START+TONE) begin voice_gate=1;voice_note=74;end
            else if(boot_samples>=START+TONE+GAP && boot_samples<START+2*TONE+GAP) begin voice_gate=1;voice_note=78;end
            else if(boot_samples>=START+2*(TONE+GAP) && boot_samples<START+3*TONE+2*GAP) begin voice_gate=1;voice_note=81;end
        end else begin
            voice_gate=calibrated && breath_gate && !fault;
            voice_gain=breath_gain;
        end
    end
endmodule
