`timescale 1ns/1ps
// Full-speed transactions. One 64-byte endpoint packet at a time.
// kind: 0 IN, 1 SETUP+DATA0(8 bytes), 2 OUT+DATA1(ZLP), 3 SOF.
// result: 0 success, 1 NAK, 2 STALL, 3 malformed/timeout. Correct duplicate
// DATA packets are ACKed; the caller owns per-endpoint toggle state.
module usb_fs_transaction (
    input wire clk, reset, start,
    input wire [1:0] kind,
    input wire [6:0] address,
    input wire [3:0] endpoint,
    input wire [10:0] frame_number,
    input wire [63:0] setup_data,
    input wire dp_i, dm_i,
    output wire dp_o, dm_o, oe, line_j, line_se0,
    output reg busy, done,
    output reg [1:0] result,
    output reg data_toggle,
    output reg [6:0] data_length,
    input wire [5:0] read_index,
    output wire [7:0] read_data
);
    function [15:0] crc16_byte;
        input [15:0] initial_crc; input [7:0] value;
        reg [15:0] c; integer n;
        begin
            c = initial_crc;
            for (n=0;n<8;n=n+1) c = (c >> 1) ^ ((c[0] ^ value[n]) ? 16'ha001 : 16'h0);
            crc16_byte = c;
        end
    endfunction
    function [4:0] crc5;
        input [10:0] value;
        reg [4:0] c; integer n;
        begin
            c = 5'h1f;
            for(n=0;n<11;n=n+1) c = (c >> 1) ^ ((c[0] ^ value[n]) ? 5'h14 : 5'h0);
            crc5 = ~c;
        end
    endfunction
    reg [7:0] tx_mem [0:10];
    reg [7:0] rx_mem [0:63];
    assign read_data = rx_mem[read_index];
    wire [6:0] tx_index;
    reg [6:0] tx_length;
    reg tx_start;
    wire tx_done, rx_active, rx_valid, rx_done, rx_error;
    wire [7:0] rx_data;
    usb_fs_phy phy(.clk(clk), .reset(reset), .dp_i(dp_i), .dm_i(dm_i),
        .dp_o(dp_o), .dm_o(dm_o), .oe(oe), .tx_start(tx_start),
        .tx_length(tx_length), .tx_index(tx_index), .tx_data(tx_mem[tx_index]),
        .tx_done(tx_done), .rx_active(rx_active), .rx_valid(rx_valid),
        .rx_done(rx_done), .rx_error(rx_error), .rx_data(rx_data),
        .line_j(line_j), .line_se0(line_se0));
    localparam IDLE=0, TOKEN=1, GAP_DATA=2, SEND_DATA=3, RECEIVE=4, GAP_ACK=5, ACK=6, FINISH=7;
    reg [3:0] state;
    reg [1:0] job;
    reg [7:0] pid;
    reg [6:0] count;
    reg overflow;
    reg [15:0] receive_crc, setup_crc;
    reg [63:0] setup_latched;
    reg [3:0] gap;
    reg [11:0] timer;
    wire [10:0] token = kind == 3 ? frame_number : {endpoint,address};
    reg [15:0] next_setup_crc;
    integer i, k;
    always @* begin
        next_setup_crc = 16'hffff;
        for(i=0;i<8;i=i+1) next_setup_crc = crc16_byte(next_setup_crc, setup_data[8*i +: 8]);
    end
    always @(posedge clk) begin
        tx_start <= 0; done <= 0;
        if (reset) begin
            state <= IDLE; busy <= 0; result <= 3; data_length <= 0;
            data_toggle <= 0; count <= 0; overflow <= 0; receive_crc <= 16'hffff;
            pid <= 0; timer <= 0; gap <= 0; job <= 0;
            tx_length <= 0; setup_crc <= 0; setup_latched <= 0;
        end else begin
            // Capture a single packet. Trailing CRC bytes are deliberately
            // included in the CRC accumulator (good residue = B001).
            if (rx_valid && state == RECEIVE) begin
                if (count == 0) pid <= rx_data;
                else begin
                    receive_crc <= crc16_byte(receive_crc, rx_data);
                    if (count <= 64) rx_mem[count-1'b1] <= rx_data;
                end
                if (count < 67) count <= count + 1'b1;
                else overflow <= 1;
            end
            case (state)
                IDLE: if (start) begin
                    busy <= 1; job <= kind; result <= 3; data_length <= 0;
                    setup_latched <= setup_data; setup_crc <= ~next_setup_crc;
                    tx_mem[0] <= kind == 0 ? 8'h69 : kind == 1 ? 8'h2d : kind == 2 ? 8'he1 : 8'ha5;
                    tx_mem[1] <= token[7:0]; tx_mem[2] <= {crc5(token),token[10:8]};
                    tx_length <= 3; tx_start <= 1; state <= TOKEN;
                end
                TOKEN: if (tx_done) begin
                    if (job == 3) begin result <= 0; state <= FINISH; end
                    else if (job == 0) begin
                        count <= 0; overflow <= 0; receive_crc <= 16'hffff; timer <= 0; state <= RECEIVE;
                    end else begin gap <= 9; state <= GAP_DATA; end
                end
                GAP_DATA: if (gap != 0) gap <= gap - 1'b1;
                    else begin
                        tx_mem[0] <= job == 1 ? 8'hc3 : 8'h4b;
                        for (k=0;k<8;k=k+1) tx_mem[k+1] <= setup_latched[8*k +: 8];
                        if (job == 1) begin
                            tx_mem[9] <= setup_crc[7:0]; tx_mem[10] <= setup_crc[15:8]; tx_length <= 11;
                        end else begin tx_mem[1] <= 0; tx_mem[2] <= 0; tx_length <= 3; end
                        tx_start <= 1; state <= SEND_DATA;
                    end
                SEND_DATA: if (tx_done) begin
                    count <= 0; overflow <= 0; receive_crc <= 16'hffff; timer <= 0; state <= RECEIVE;
                end
                RECEIVE: begin
                    timer <= timer + 1'b1;
                    if (rx_done) begin
                        if (rx_error || overflow || pid[7:4] != ~pid[3:0]) state <= FINISH;
                        else if (count == 1 && pid == 8'h5a) begin result <= 1; state <= FINISH; end
                        else if (count == 1 && pid == 8'h1e) begin result <= 2; state <= FINISH; end
                        else if (job != 0 && count == 1 && pid == 8'hd2) begin result <= 0; state <= FINISH; end
                        else if (job == 0 && (pid == 8'hc3 || pid == 8'h4b) && count >= 3 && receive_crc == 16'hb001) begin
                            data_length <= count - 7'd3; data_toggle <= pid[3];
                            result <= 0; gap <= 9; state <= GAP_ACK;
                        end else state <= FINISH;
                    end else if ((!rx_active && timer >= 90) || timer == 4095) state <= FINISH;
                end
                GAP_ACK: if (gap != 0) gap <= gap - 1'b1;
                    else begin tx_mem[0] <= 8'hd2; tx_length <= 1; tx_start <= 1; state <= ACK; end
                ACK: if (tx_done) state <= FINISH;
                FINISH: begin busy <= 0; done <= 1; state <= IDLE; end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
