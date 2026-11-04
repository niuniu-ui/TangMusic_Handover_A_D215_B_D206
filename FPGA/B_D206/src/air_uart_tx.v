`timescale 1ns/1ps
// A byte is accepted on a rising edge with tx_valid && tx_ready.
module air_uart_tx #(
    parameter integer CLK_HZ=50000000, parameter integer BAUD=115200
)(
    input wire clk, input wire rst_n,
    input wire [7:0] tx_data, input wire tx_valid,
    output wire tx_ready, output reg tx, output reg tx_done
);
    localparam integer BIT_TICKS=(CLK_HZ+BAUD/2)/BAUD;
    reg busy;
    reg [9:0] shift;
    reg [3:0] bit_index;
    reg [31:0] ticks;
    assign tx_ready=!busy;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy<=0; tx<=1; tx_done<=0; shift<=10'h3ff;
            bit_index<=0; ticks<=0;
        end else begin
            tx_done<=0;
            if (!busy) begin
                tx<=1;
                if (tx_valid) begin
                    shift<={1'b1,tx_data,1'b0}; tx<=0;
                    busy<=1; bit_index<=0; ticks<=0;
                end
            end else if (ticks==BIT_TICKS-1) begin
                ticks<=0;
                if (bit_index==9) begin busy<=0; tx<=1; tx_done<=1; end
                else begin
                    shift<={1'b1,shift[9:1]}; tx<=shift[1];
                    bit_index<=bit_index+1'b1;
                end
            end else ticks<=ticks+1'b1;
        end
    end
endmodule
