`timescale 1ns/1ps
// 12 Mbit/s full-speed USB packet PHY, 60 MHz clock, direct 3.3 V I/O.
// tx_data contains PID/payload/CRC, excluding SYNC and EOP. RX strips SYNC
// but delivers PID and CRC. The transaction layer checks PID and CRC.
module usb_fs_phy (
    input wire clk, reset,
    input wire dp_i, dm_i,
    output reg dp_o, dm_o, oe,
    input wire tx_start,
    input wire [6:0] tx_length,
    output reg [6:0] tx_index,
    input wire [7:0] tx_data,
    output reg tx_done,
    output reg rx_active, rx_valid, rx_done, rx_error,
    output reg [7:0] rx_data,
    output wire line_j, line_se0
);
    reg [2:0] dp_sync = 0, dm_sync = 0;
    always @(posedge clk) begin
        dp_sync <= {dp_sync[1:0], dp_i};
        dm_sync <= {dm_sync[1:0], dm_i};
    end
    wire dp = dp_sync[2], dm = dm_sync[2];
    assign line_j = dp && !dm;
    assign line_se0 = !dp && !dm;

    localparam T_IDLE=0, T_SYNC=1, T_DATA=2, T_SE0=3, T_J=4, T_END=5;
    reg [2:0] ts;
    reg [2:0] tick, bit_num, ones;
    reg [7:0] shift;
    reg last_bit;
    // Hold each driven symbol for five clocks. SYNC's final one participates
    // in stuffing; a stuffed zero after the final data bit must precede EOP.
    always @(posedge clk) begin
        tx_done <= 0;
        if (reset) begin
            ts <= T_IDLE; oe <= 0; dp_o <= 1; dm_o <= 0;
            tx_index <= 0; tick <= 0; ones <= 0; last_bit <= 0;
            bit_num <= 0; shift <= 0;
        end else begin
            if (tick != 0) tick <= tick - 1'b1;
            case (ts)
                T_IDLE: if (tx_start) begin
                    oe <= 1; dp_o <= 0; dm_o <= 1; // first SYNC zero
                    shift <= 8'h40; bit_num <= 1; tick <= 4;
                    ones <= 0; last_bit <= 0; tx_index <= 0; ts <= T_SYNC;
                end
                T_SYNC: if (tick == 0) begin
                    tick <= 4;
                    if (!shift[0]) begin dp_o <= !dp_o; dm_o <= !dm_o; end
                    shift <= {1'b0, shift[7:1]};
                    bit_num <= bit_num + 1'b1;
                    if (bit_num == 7) begin
                        ts <= T_DATA; bit_num <= 0; ones <= 1;
                    end
                end
                T_DATA: if (tick == 0) begin
                    tick <= 4;
                    if (ones == 6) begin
                        dp_o <= !dp_o; dm_o <= !dm_o; ones <= 0;
                    end else if (last_bit) begin
                        dp_o <= 0; dm_o <= 0; ts <= T_SE0;
                    end else begin
                        if (!tx_data[bit_num]) begin dp_o <= !dp_o; dm_o <= !dm_o; end
                        ones <= tx_data[bit_num] ? ones + 3'd1 : 3'd0;
                        bit_num <= bit_num + 1'b1;
                        if (bit_num == 7) begin
                            if (tx_index + 1'b1 == tx_length) last_bit <= 1;
                            else tx_index <= tx_index + 1'b1;
                        end
                    end
                end
                T_SE0: if (tick == 0) begin tick <= 4; ts <= T_J; end
                T_J: if (tick == 0) begin
                    dp_o <= 1; dm_o <= 0; tick <= 4; ts <= T_END;
                end
                T_END: if (tick == 0) begin oe <= 0; tx_done <= 1; ts <= T_IDLE; end
                default: ts <= T_IDLE;
            endcase
        end
    end

    reg previous_dp, previous_dm, nrzi;
    reg [2:0] phase, rx_bit, rx_ones;
    reg [7:0] rx_shift;
    reg sync_seen, bad;
    reg [1:0] se0_bits;
    reg [11:0] watchdog;
    wire transition = (dp != previous_dp || dm != previous_dm) && (dp != dm);
    wire decoded_bit = (dp == nrzi);
    wire [7:0] assembled = {decoded_bit, rx_shift[7:1]};
    // Re-center sampling on J/K edges. Registered line inputs isolate external
    // metastability; phase 2 samples the middle of the 5-clock bit cell.
    always @(posedge clk) begin
        previous_dp <= dp; previous_dm <= dm;
        rx_valid <= 0; rx_done <= 0;
        if (reset || oe || tx_start) begin
            rx_active <= 0; rx_error <= 0; phase <= 0; rx_bit <= 0;
            rx_ones <= 0; nrzi <= 1; sync_seen <= 0; bad <= 0;
            rx_shift <= 0; se0_bits <= 0; watchdog <= 0; rx_data <= 0;
        end else if (!rx_active) begin
            if (!dp && dm) begin
                rx_active <= 1; phase <= 0; rx_bit <= 0; rx_ones <= 0;
                nrzi <= 1; sync_seen <= 0; bad <= 0; se0_bits <= 0;
                watchdog <= 0;
            end
        end else begin
            watchdog <= watchdog + 1'b1;
            if (transition) phase <= 0;
            else if (phase == 4) phase <= 0;
            else phase <= phase + 1'b1;
            if (!transition && phase == 1) begin
                if (!dp && !dm) begin
                    if (se0_bits != 3) se0_bits <= se0_bits + 1'b1;
                end else if (se0_bits != 0) begin
                    rx_active <= 0; rx_done <= 1;
                    rx_error <= bad || !sync_seen || rx_bit != 0 || se0_bits != 2 || !line_j || rx_ones == 6;
                end else if (dp && dm) begin
                    bad <= 1;
                end else begin
                    nrzi <= dp;
                    if (rx_ones == 6) begin
                        if (decoded_bit) bad <= 1;
                        rx_ones <= 0;
                    end else begin
                        rx_shift <= assembled;
                        rx_bit <= rx_bit + 1'b1;
                        rx_ones <= decoded_bit ? rx_ones + 3'd1 : 3'd0;
                        if (rx_bit == 7) begin
                            if (!sync_seen) begin
                                sync_seen <= 1;
                                if (assembled != 8'h80) bad <= 1;
                            end else begin rx_data <= assembled; rx_valid <= 1; end
                        end
                    end
                end
            end
            if (&watchdog) begin
                rx_active <= 0; rx_done <= 1; rx_error <= 1;
            end
        end
    end
endmodule
