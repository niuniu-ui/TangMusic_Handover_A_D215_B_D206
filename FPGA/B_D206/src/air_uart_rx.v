`timescale 1ns/1ps
// 8N1 receiver. rx_data/rx_valid are in clk domain; bad stop bits are rejected.
module air_uart_rx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200
)(
    input wire clk, input wire rst_n, input wire rx,
    output reg [7:0] rx_data,
    output reg rx_valid, output reg framing_error
);
    localparam integer BIT_TICKS = (CLK_HZ + BAUD/2) / BAUD;
    localparam integer HALF_TICKS = BIT_TICKS / 2;
    localparam IDLE=0, START=1, DATA=2, STOP=3, RECOVER=4;
    reg [2:0] state, bit_index;
    reg [31:0] ticks;
    reg [7:0] shift;
    (* syn_preserve=1 *) reg rx_meta, rx_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rx_meta<=1'b1; rx_sync<=1'b1; end
        else begin rx_meta<=rx; rx_sync<=rx_meta; end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; ticks<=0; bit_index<=0; shift<=0;
            rx_data<=0; rx_valid<=0; framing_error<=0;
        end else begin
            rx_valid<=0; framing_error<=0;
            case (state)
                IDLE: begin
                    ticks<=0;
                    if (!rx_sync) state<=START;
                end
                START: if (ticks==HALF_TICKS-1) begin
                    ticks<=0;
                    if (!rx_sync) begin state<=DATA; bit_index<=0; end
                    else state<=IDLE;
                end else ticks<=ticks+1'b1;
                DATA: if (ticks==BIT_TICKS-1) begin
                    ticks<=0; shift[bit_index]<=rx_sync;
                    if (bit_index==7) state<=STOP;
                    else bit_index<=bit_index+1'b1;
                end else ticks<=ticks+1'b1;
                STOP: if (ticks==BIT_TICKS-1) begin
                    ticks<=0;
                    if (rx_sync) begin
                        rx_data<=shift; rx_valid<=1; state<=IDLE;
                    end else begin framing_error<=1; state<=RECOVER; end
                end else ticks<=ticks+1'b1;
                RECOVER: if (rx_sync) state<=IDLE;
                default: state<=IDLE;
            endcase
        end
    end
endmodule
