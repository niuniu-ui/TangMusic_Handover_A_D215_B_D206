`timescale 1ns/1ps
// MCP3204 mode 0, 24 clocks. Start at clock 6, null at clock 12,
// B11..B0 at clocks 13..24. CS remains low through the final falling edge.
module flute_adc #(parameter integer CLK_HZ=50000000,
    parameter integer SPI_HZ=500000, PAIR_HZ=1000)(
    input wire clk,rst_n,miso,
    output reg cs_n,sck,mosi,
    output reg [11:0] pressure,supply,
    output reg pair_valid
);
    localparam integer HALF=CLK_HZ/(2*SPI_HZ), PERIOD=CLK_HZ/PAIR_HZ;
    reg [31:0] period_count,divider;
    reg [4:0] bit_index;
    reg [23:0] tx_shift,rx_shift;
    reg [2:0] state;
    reg channel;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cs_n<=1;sck<=0;mosi<=0;pressure<=0;supply<=0;pair_valid<=0;
            period_count<=0;divider<=0;bit_index<=0;tx_shift<=0;rx_shift<=0;state<=0;channel<=0;
        end else begin
            pair_valid<=0;
            if(period_count==PERIOD-1) period_count<=0;
            else period_count<=period_count+1'b1;
            case(state)
                0: if(period_count==PERIOD-1) begin channel<=0;state<=1;end
                1: begin
                    cs_n<=0;sck<=0;mosi<=0;divider<=0;bit_index<=0;rx_shift<=0;
                    tx_shift<=channel ? 24'h064000 : 24'h060000;state<=2;
                end
                2: if(divider==HALF-1) begin
                    divider<=0;
                    if(!sck) begin sck<=1;rx_shift<={rx_shift[22:0],miso};end
                    else begin
                        sck<=0;
                        if(bit_index==23) state<=3;
                        else begin
                            bit_index<=bit_index+1'b1;
                            tx_shift<={tx_shift[22:0],1'b0};mosi<=tx_shift[22];
                        end
                    end
                end else divider<=divider+1'b1;
                3: begin cs_n<=1;mosi<=0;divider<=0;state<=4;
                    if(channel) supply<=rx_shift[11:0];else pressure<=rx_shift[11:0];
                end
                4: if(divider==HALF-1) begin
                    divider<=0;
                    if(!channel) begin channel<=1;state<=1;end
                    else begin pair_valid<=1;state<=0;end
                end else divider<=divider+1'b1;
                default: state<=0;
            endcase
        end
    end
endmodule
