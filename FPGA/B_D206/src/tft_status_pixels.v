`timescale 1ns / 1ps

// Generated from this template by generate_font.py.
// 18x18 Chinese glyphs at x=16; rows at y=48/108/168/228.
// Values are optional, right aligned, 0..255, using 9-pixel-wide digits.
module tft_status_pixels (
    input wire [7:0] x,
    input wire [8:0] y,
    input wire [7:0] piano_tone,
    input wire [7:0] pad_tone,
    input wire [7:0] piano_volume,
    input wire [7:0] pad_volume,
    input wire [3:0] value_valid,
    output wire [15:0] pixel
);
    reg active_row;
    reg [1:0] line_number;
    reg [8:0] glyph_y;
    reg [7:0] glyph_x;
    reg [3:0] column;
    reg [5:0] glyph;
    reg [7:0] selected_value;
    reg is_value;
    wire [17:0] glyph_bits;

    function [5:0] label_glyph;
        input [1:0] line_id;
        input [3:0] character;
        begin
            case ({line_id, character})
                6'd0: label_glyph = 6'd1; // 电
                6'd1: label_glyph = 6'd2; // 子
                6'd2: label_glyph = 6'd3; // 琴
                6'd3: label_glyph = 6'd4; // 当
                6'd4: label_glyph = 6'd5; // 前
                6'd5: label_glyph = 6'd6; // 音
                6'd6: label_glyph = 6'd7; // 色
                6'd7: label_glyph = 6'd8; // 档
                6'd8: label_glyph = 6'd9; // 位
                6'd9: label_glyph = 6'd10; // ：
                6'd16: label_glyph = 6'd11; // 打
                6'd17: label_glyph = 6'd12; // 击
                6'd18: label_glyph = 6'd13; // 板
                6'd19: label_glyph = 6'd4; // 当
                6'd20: label_glyph = 6'd5; // 前
                6'd21: label_glyph = 6'd6; // 音
                6'd22: label_glyph = 6'd7; // 色
                6'd23: label_glyph = 6'd8; // 档
                6'd24: label_glyph = 6'd9; // 位
                6'd25: label_glyph = 6'd10; // ：
                6'd32: label_glyph = 6'd1; // 电
                6'd33: label_glyph = 6'd2; // 子
                6'd34: label_glyph = 6'd3; // 琴
                6'd35: label_glyph = 6'd4; // 当
                6'd36: label_glyph = 6'd5; // 前
                6'd37: label_glyph = 6'd6; // 音
                6'd38: label_glyph = 6'd14; // 量
                6'd39: label_glyph = 6'd15; // 级
                6'd40: label_glyph = 6'd16; // 别
                6'd41: label_glyph = 6'd10; // ：
                6'd48: label_glyph = 6'd11; // 打
                6'd49: label_glyph = 6'd12; // 击
                6'd50: label_glyph = 6'd13; // 板
                6'd51: label_glyph = 6'd4; // 当
                6'd52: label_glyph = 6'd5; // 前
                6'd53: label_glyph = 6'd6; // 音
                6'd54: label_glyph = 6'd14; // 量
                6'd55: label_glyph = 6'd15; // 级
                6'd56: label_glyph = 6'd16; // 别
                6'd57: label_glyph = 6'd10; // ：
                default: label_glyph = 6'd0;
            endcase
        end
    endfunction

    function [5:0] digit_glyph;
        input [7:0] digit;
        begin
            case (digit)
                8'd0: digit_glyph = 6'd17;
                8'd1: digit_glyph = 6'd18;
                8'd2: digit_glyph = 6'd19;
                8'd3: digit_glyph = 6'd20;
                8'd4: digit_glyph = 6'd21;
                8'd5: digit_glyph = 6'd22;
                8'd6: digit_glyph = 6'd23;
                8'd7: digit_glyph = 6'd24;
                8'd8: digit_glyph = 6'd25;
                8'd9: digit_glyph = 6'd26;
                default: digit_glyph = 6'd0;
            endcase
        end
    endfunction

    always @* begin
        active_row = 1'b1;
        line_number = 2'd0;
        glyph_y = 5'd0;
        if (y >= 9'd48 && y < 9'd66) begin
            line_number = 2'd0; glyph_y = y - 9'd48;
        end else if (y >= 9'd108 && y < 9'd126) begin
            line_number = 2'd1; glyph_y = y - 9'd108;
        end else if (y >= 9'd168 && y < 9'd186) begin
            line_number = 2'd2; glyph_y = y - 9'd168;
        end else if (y >= 9'd228 && y < 9'd246) begin
            line_number = 2'd3; glyph_y = y - 9'd228;
        end else active_row = 1'b0;

        case (line_number)
            0: selected_value = piano_tone;
            1: selected_value = pad_tone;
            2: selected_value = piano_volume;
            default: selected_value = pad_volume;
        endcase

        column = 4'd0;
        glyph_x = 5'd0;
        glyph = 6'd0;
        is_value = 1'b0;
        if (active_row && x >= 8'd16 && x < 8'd196) begin
            if      (x < 8'd34)  begin column = 0; glyph_x = x - 8'd16; end
            else if (x < 8'd52)  begin column = 1; glyph_x = x - 8'd34; end
            else if (x < 8'd70)  begin column = 2; glyph_x = x - 8'd52; end
            else if (x < 8'd88)  begin column = 3; glyph_x = x - 8'd70; end
            else if (x < 8'd106) begin column = 4; glyph_x = x - 8'd88; end
            else if (x < 8'd124) begin column = 5; glyph_x = x - 8'd106; end
            else if (x < 8'd142) begin column = 6; glyph_x = x - 8'd124; end
            else if (x < 8'd160) begin column = 7; glyph_x = x - 8'd142; end
            else if (x < 8'd178) begin column = 8; glyph_x = x - 8'd160; end
            else                begin column = 9; glyph_x = x - 8'd178; end
            glyph = label_glyph(line_number, column);
        end else if (active_row && value_valid[line_number] && x >= 8'd196 && x < 8'd223) begin
            is_value = 1'b1;
            if (x < 8'd205) begin
                glyph_x = x - 8'd196;
                if (selected_value >= 8'd100) glyph = digit_glyph(selected_value / 8'd100);
            end else if (x < 8'd214) begin
                glyph_x = x - 8'd205;
                if (selected_value >= 8'd10) glyph = digit_glyph((selected_value / 8'd10) % 8'd10);
            end else begin
                glyph_x = x - 8'd214;
                glyph = digit_glyph(selected_value % 8'd10);
            end
        end
    end

    tft_font_rom u_font (.glyph(glyph), .row(glyph_y[4:0]), .bits(glyph_bits));
    assign pixel = (active_row && glyph_bits[5'd17 - glyph_x[4:0]]) ?
                   (is_value ? 16'h07FF : 16'hFFFF) : 16'h0000;
endmodule
