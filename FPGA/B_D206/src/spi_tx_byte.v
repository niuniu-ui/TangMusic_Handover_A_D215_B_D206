`timescale 1ns / 1ps

// SPI mode 0, MSB first. SCK = clk / (2 * HALF_PERIOD).
// start is sampled only while idle; done pulses after the final falling edge.
module spi_tx_byte #(
    parameter integer HALF_PERIOD = 25
) (
    input  wire       clk,
    input  wire       reset_n,
    input  wire       start,
    input  wire [7:0] data,
    output reg        busy,
    output reg        done,
    output reg        sck,
    output reg        mosi
);
    reg [31:0] divider;
    reg [7:0] shift_reg;
    reg [2:0] bit_index;

    always @(posedge clk) begin
        if (!reset_n) begin
            divider   <= 0;
            shift_reg <= 0;
            bit_index <= 0;
            busy      <= 0;
            done      <= 0;
            sck       <= 0;
            mosi      <= 0;
        end else begin
            done <= 0;
            if (!busy) begin
                sck <= 0;
                if (start) begin
                    shift_reg <= data;
                    mosi      <= data[7];
                    bit_index <= 7;
                    divider   <= HALF_PERIOD - 1;
                    busy      <= 1;
                end
            end else if (divider != 0) begin
                divider <= divider - 1;
            end else begin
                divider <= HALF_PERIOD - 1;
                if (!sck) begin
                    sck <= 1;
                end else begin
                    sck <= 0;
                    if (bit_index == 0) begin
                        busy <= 0;
                        done <= 1;
                    end else begin
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        mosi      <= shift_reg[6];
                        bit_index <= bit_index - 1;
                    end
                end
            end
        end
    end
endmodule
