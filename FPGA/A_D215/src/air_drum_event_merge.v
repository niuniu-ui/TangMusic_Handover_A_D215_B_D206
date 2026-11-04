`timescale 1ns/1ps
// Register FIFO: accept up to three simultaneous events, drain one per clock.
// Inputs: audition/demo, first IMU, second IMU. Capture complete note metadata.
module air_drum_event_merge #(parameter integer WIDTH=19)(
    input wire clk,rst_n,enable,
    input wire valid0,valid1,valid2,
    input wire [WIDTH-1:0] data0,data1,data2,
    output reg out_valid,output reg [WIDTH-1:0] out_data,
    output reg overflow
);
    reg [WIDTH-1:0] queue[0:7];
    reg [2:0] rd,wr;reg [3:0] count;
    wire pop=(count!=0);
    integer room,n;
    reg take0,take1,take2;
    always @* begin
        room=8-count+(pop ? 1 : 0);n=0;
        take0=valid0 && n<room;if(take0) n=n+1;
        take1=valid1 && n<room;if(take1) n=n+1;
        take2=valid2 && n<room;if(take2) n=n+1;
    end
    function [2:0] slot;
        input [2:0] base;input integer offset;
        begin slot=base+offset;end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin rd<=0;wr<=0;count<=0;out_valid<=0;out_data<=0;overflow<=0;end
        else if(!enable) begin rd<=0;wr<=0;count<=0;out_valid<=0;out_data<=0;end
        else begin
            out_valid<=pop;
            if(pop) begin out_data<=queue[rd];rd<=rd+1'b1;end
            if(take0) queue[wr]<=data0;
            if(take1) queue[slot(wr,take0 ? 1 : 0)]<=data1;
            if(take2) queue[slot(wr,(take0 ? 1 : 0)+(take1 ? 1 : 0))]<=data2;
            wr<=slot(wr,n);count<=count+n-(pop ? 1 : 0);
            if((valid0 && !take0)||(valid1 && !take1)||(valid2 && !take2)) overflow<=1;
        end
    end
endmodule
