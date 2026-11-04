`timescale 1ns/1ps
// Configure RAM registers, then READ EACH BACK. No calibration, baud change,
// or flash SAVE is issued. done means all four readbacks matched, not just TX done.
module air_atk_imu901_config #(
    parameter integer CLK_HZ=50000000, parameter integer ENABLE=1,
    parameter integer STARTUP_MS=1500, parameter integer GAP_MS=20,
    parameter integer ACK_TIMEOUT_MS=150, parameter integer MAX_ATTEMPTS=3
)(
    input wire clk, input wire rst_n,
    output reg [7:0] tx_data, output wire tx_valid, input wire tx_ready,
    input wire ack_valid, input wire [7:0] ack_id, ack_len,
    input wire [15:0] ack_data,
    output reg done, output reg failed, output reg [7:0] failed_reg
);
    localparam WAIT_START=0,SEND_WRITE=1,GAP=2,SEND_READ=3,WAIT_ACK=4,FINISH=5;
    reg [2:0] state, byte_index;
    reg [1:0] setting;
    reg [7:0] attempts;
    reg [31:0] ticks;
    reg [7:0] reg_id, reg_value;
    wire reading=(state==SEND_READ);
    wire [7:0] command_id=reading ? (reg_id|8'h80) : reg_id;
    wire [7:0] command_value=reading ? 8'h00 : reg_value;
    wire [7:0] checksum=8'h55+8'haf+command_id+8'h01+command_value;
    assign tx_valid=(state==SEND_WRITE || state==SEND_READ);
    always @* begin
        case (setting)
            0: begin reg_id=8'h03; reg_value=8'h03; end // gyro +/-2000 dps
            1: begin reg_id=8'h04; reg_value=8'h02; end // accel +/-8 g
            2: begin reg_id=8'h08; reg_value=8'h05; end // angles + motion only
            default: begin reg_id=8'h0a; reg_value=8'h01; end // 200 Hz
        endcase
        case (byte_index)
            0: tx_data=8'h55;
            1: tx_data=8'haf;
            2: tx_data=command_id;
            3: tx_data=8'h01;
            4: tx_data=command_value;
            default: tx_data=checksum;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=WAIT_START; ticks<=0; setting<=0; byte_index<=0;
            attempts<=1; done<=0; failed<=0; failed_reg<=0;
        end else case (state)
            WAIT_START: if (!ENABLE) begin done<=1; state<=FINISH; end
            else if (ticks>=(CLK_HZ/1000)*STARTUP_MS-1) begin
                ticks<=0; state<=SEND_WRITE;
            end else ticks<=ticks+1'b1;
            SEND_WRITE, SEND_READ: if (tx_ready) begin
                if (byte_index==5) begin
                    byte_index<=0; ticks<=0;
                    state<=reading ? WAIT_ACK : GAP;
                end else byte_index<=byte_index+1'b1;
            end
            GAP: if (ticks>=(CLK_HZ/1000)*GAP_MS-1 && tx_ready) begin
                ticks<=0; state<=SEND_READ;
            end else ticks<=ticks+1'b1;
            WAIT_ACK: if (ack_valid && ack_id==reg_id && ack_len==1 && ack_data[7:0]==reg_value) begin
                ticks<=0; attempts<=1;
                if (setting==3) begin done<=1; state<=FINISH; end
                else begin setting<=setting+1'b1; state<=SEND_WRITE; end
            end else if (ticks>=(CLK_HZ/1000)*ACK_TIMEOUT_MS-1) begin
                ticks<=0;
                if (attempts>=MAX_ATTEMPTS) begin
                    failed<=1; failed_reg<=reg_id; state<=FINISH;
                end else begin attempts<=attempts+1'b1; state<=SEND_WRITE; end
            end else ticks<=ticks+1'b1;
            FINISH: begin end
            default: state<=WAIT_START;
        endcase
    end
endmodule
