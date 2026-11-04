`timescale 1ns / 1ps

// 240 x 320 ST7789 Chinese status display. Values are latched once per frame.
// No framebuffer is required. All LCD signals are FPGA outputs.
module st7789_status #(
    parameter integer CLK_HZ = 50000000,
    parameter integer SPI_HALF_PERIOD = 25,
    parameter [7:0] MADCTL = 8'h00,
    parameter integer INVERT_DISPLAY = 1
) (
    input  wire clk,
    input  wire reset_n,
    input  wire [7:0] piano_tone,
    input  wire [7:0] pad_tone,
    input  wire [7:0] piano_volume,
    input  wire [7:0] pad_volume,
    input  wire [3:0] value_valid,
    output reg  lcd_cs,
    output reg  lcd_dc,
    output reg  lcd_rst,
    output wire lcd_mosi,
    output wire lcd_sck
);
    localparam [3:0] POWER_WAIT = 0, RESET_LOW = 1, RESET_WAIT = 2,
                     SCRIPT = 3, BYTE_WAIT = 4, SCRIPT_DELAY = 5,
                     PIXEL_HIGH = 6, PIXEL_LOW = 7, PIXEL_NEXT = 8,
                     FRAME_WAIT = 9;
    localparam integer MS_CYCLES = CLK_HZ / 1000;

    reg [3:0] state, return_state;
    reg [31:0] ms_divider;
    wire ms_tick = (ms_divider == MS_CYCLES - 1);
    reg [15:0] wait_ms;
    reg [5:0] script_index;
    reg [7:0] x;
    reg [8:0] y;
    reg [7:0] frame_piano_tone, frame_pad_tone;
    reg [7:0] frame_piano_volume, frame_pad_volume;
    reg [3:0] frame_value_valid;
    reg tx_start;
    reg [7:0] tx_data;
    wire tx_done;

    // Entry: {delay_in_ms, data_not_command, value[15:0]}.
    // Delays are deliberately conservative for first hardware bring-up.
    function [17:0] script_entry;
        input [5:0] index;
        begin
            case (index)
                0:  script_entry = {1'b0, 1'b0, 16'h0001}; // SWRESET
                1:  script_entry = {1'b1, 1'b0, 16'd200};
                2:  script_entry = {1'b0, 1'b0, 16'h0011}; // SLPOUT
                3:  script_entry = {1'b1, 1'b0, 16'd200};
                4:  script_entry = {1'b0, 1'b0, 16'h003A}; // COLMOD
                5:  script_entry = {1'b0, 1'b1, 16'h0055}; // RGB565
                6:  script_entry = {1'b1, 1'b0, 16'd10};
                7:  script_entry = {1'b0, 1'b0, 16'h0036}; // MADCTL
                8:  script_entry = {1'b0, 1'b1, 8'h00, MADCTL};
                9:  script_entry = {1'b0, 1'b0, 8'h00,
                                   (INVERT_DISPLAY ? 8'h21 : 8'h20)};
                10: script_entry = {1'b1, 1'b0, 16'd10};
                11: script_entry = {1'b0, 1'b0, 16'h0013}; // NORON
                12: script_entry = {1'b1, 1'b0, 16'd10};
                13: script_entry = {1'b0, 1'b0, 16'h0029}; // DISPON
                14: script_entry = {1'b1, 1'b0, 16'd200};
                // Repeated for each frame. End coordinates are inclusive.
                15: script_entry = {1'b0, 1'b0, 16'h002A}; // CASET
                16: script_entry = {1'b0, 1'b1, 16'h0000};
                17: script_entry = {1'b0, 1'b1, 16'h0000};
                18: script_entry = {1'b0, 1'b1, 16'h0000};
                19: script_entry = {1'b0, 1'b1, 16'h00EF}; // x = 0..239
                20: script_entry = {1'b0, 1'b0, 16'h002B}; // RASET
                21: script_entry = {1'b0, 1'b1, 16'h0000};
                22: script_entry = {1'b0, 1'b1, 16'h0000};
                23: script_entry = {1'b0, 1'b1, 16'h0001};
                24: script_entry = {1'b0, 1'b1, 16'h003F}; // y = 0..319
                25: script_entry = {1'b0, 1'b0, 16'h002C}; // RAMWR
                default: script_entry = 18'd0;
            endcase
        end
    endfunction

    wire [17:0] entry = script_entry(script_index);
    wire [15:0] pixel;
    tft_status_pixels u_pixels (
        .x(x), .y(y),
        .piano_tone(frame_piano_tone), .pad_tone(frame_pad_tone),
        .piano_volume(frame_piano_volume), .pad_volume(frame_pad_volume),
        .value_valid(frame_value_valid), .pixel(pixel)
    );

    spi_tx_byte #(.HALF_PERIOD(SPI_HALF_PERIOD)) u_spi (
        .clk(clk), .reset_n(reset_n), .start(tx_start), .data(tx_data),
        .busy(), .done(tx_done), .sck(lcd_sck), .mosi(lcd_mosi)
    );

    always @(posedge clk) begin
        if (!reset_n || ms_tick)
            ms_divider <= 0;
        else
            ms_divider <= ms_divider + 1;
    end

    always @(posedge clk) begin
        if (!reset_n) begin
            state        <= POWER_WAIT;
            return_state <= SCRIPT;
            wait_ms      <= 200;
            script_index <= 0;
            x            <= 0;
            y            <= 0;
            frame_piano_tone   <= 0;
            frame_pad_tone     <= 0;
            frame_piano_volume <= 0;
            frame_pad_volume   <= 0;
            frame_value_valid  <= 0;
            tx_start     <= 0;
            tx_data      <= 0;
            lcd_cs       <= 1;
            lcd_dc       <= 0;
            lcd_rst      <= 1;
        end else begin
            tx_start <= 0;
            case (state)
                POWER_WAIT: if (ms_tick) begin
                    if (wait_ms == 0) begin
                        lcd_rst <= 0;
                        wait_ms <= 20;
                        state   <= RESET_LOW;
                    end else wait_ms <= wait_ms - 16'd1;
                end
                RESET_LOW: if (ms_tick) begin
                    if (wait_ms == 0) begin
                        lcd_rst <= 1;
                        wait_ms <= 200;
                        state   <= RESET_WAIT;
                    end else wait_ms <= wait_ms - 16'd1;
                end
                RESET_WAIT: if (ms_tick) begin
                    if (wait_ms == 0) state <= SCRIPT;
                    else wait_ms <= wait_ms - 16'd1;
                end
                SCRIPT: begin
                    // Capture all fields together before the frame window command.
                    // Mid-frame input changes cannot split a number across bytes.
                    if (script_index == 15) begin
                        frame_piano_tone   <= piano_tone;
                        frame_pad_tone     <= pad_tone;
                        frame_piano_volume <= piano_volume;
                        frame_pad_volume   <= pad_volume;
                        frame_value_valid  <= value_valid;
                    end
                    if (script_index == 26) begin
                        state <= PIXEL_HIGH;
                    end else if (entry[17]) begin
                        lcd_cs       <= 1;
                        wait_ms      <= entry[15:0];
                        script_index <= script_index + 1;
                        state        <= SCRIPT_DELAY;
                    end else begin
                        lcd_cs       <= 0;
                        lcd_dc       <= entry[16];
                        tx_data      <= entry[7:0];
                        tx_start     <= 1;
                        script_index <= script_index + 1;
                        return_state <= SCRIPT;
                        state        <= BYTE_WAIT;
                    end
                end
                BYTE_WAIT: if (tx_done) state <= return_state;
                SCRIPT_DELAY: if (ms_tick) begin
                    if (wait_ms == 0) state <= SCRIPT;
                    else wait_ms <= wait_ms - 16'd1;
                end
                PIXEL_HIGH: begin
                    lcd_cs       <= 0;
                    lcd_dc       <= 1;
                    tx_data      <= pixel[15:8];
                    tx_start     <= 1;
                    return_state <= PIXEL_LOW;
                    state        <= BYTE_WAIT;
                end
                PIXEL_LOW: begin
                    tx_data      <= pixel[7:0];
                    tx_start     <= 1;
                    return_state <= PIXEL_NEXT;
                    state        <= BYTE_WAIT;
                end
                PIXEL_NEXT: begin
                    if (x == 239) begin
                        x <= 0;
                        if (y == 319) begin
                            y       <= 0;
                            lcd_cs  <= 1;
                            wait_ms <= 16'd200;
                            state   <= FRAME_WAIT;
                        end else begin
                            y     <= y + 1;
                            state <= PIXEL_HIGH;
                        end
                    end else begin
                        x     <= x + 1;
                        state <= PIXEL_HIGH;
                    end
                end
                FRAME_WAIT: if (ms_tick) begin
                    if (wait_ms == 0) begin
                        script_index <= 15;
                        state        <= SCRIPT;
                    end else wait_ms <= wait_ms - 16'd1;
                end
                default: begin
                    state   <= POWER_WAIT;
                    wait_ms <= 200;
                    lcd_cs  <= 1;
                end
            endcase
        end
    end
endmodule
