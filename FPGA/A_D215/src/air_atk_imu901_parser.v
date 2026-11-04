`timescale 1ns/1ps
// ATK-IMU901 / MS901M: 55 55 ID LEN DATA SUM; register replies: 55 AF ...
// Payload words are signed, LOW BYTE FIRST. Publish only complete, valid frames.
module air_atk_imu901_parser #(
    parameter integer CLK_HZ=50000000,
    parameter integer TIMEOUT_MS=10,
    parameter integer MAX_PAYLOAD=32
)(
    input wire clk, input wire rst_n,
    input wire [7:0] rx_data, input wire rx_valid, input wire rx_error,
    output reg signed [15:0] ax, ay, az, gx, gy, gz,
    output reg signed [15:0] roll, pitch, yaw,
    output reg motion_valid, output reg angle_valid,
    output reg ack_valid, output reg [7:0] ack_id, ack_len,
    output reg [15:0] ack_data,
    output reg [15:0] frame_count, checksum_errors, format_errors, timeouts
);
    localparam H1=0,H2=1,ID=2,LEN=3,PAYLOAD=4,CHECK=5;
    localparam integer TIMEOUT_TICKS=(CLK_HZ/1000)*TIMEOUT_MS;
    reg [2:0] state;
    reg is_ack;
    reg [7:0] frame_id, length, index, sum;
    reg [7:0] payload [0:MAX_PAYLOAD-1];
    reg [31:0] idle_ticks;
    wire length_ok = (rx_data!=0 && rx_data<=MAX_PAYLOAD) &&
        (is_ack || ((frame_id!=1 || rx_data==6) &&
                    (frame_id!=2 || rx_data==8) &&
                    (frame_id!=3 || rx_data==12) &&
                    (frame_id!=4 || rx_data==8) &&
                    (frame_id!=5 || rx_data==10) &&
                    (frame_id!=6 || rx_data==8)));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=H1; is_ack<=0; frame_id<=0; length<=0; index<=0;
            sum<=0; idle_ticks<=0;
            ax<=0; ay<=0; az<=0; gx<=0; gy<=0; gz<=0;
            roll<=0; pitch<=0; yaw<=0;
            motion_valid<=0; angle_valid<=0; ack_valid<=0;
            ack_id<=0; ack_len<=0; ack_data<=0;
            frame_count<=0; checksum_errors<=0; format_errors<=0; timeouts<=0;
        end else begin
            motion_valid<=0; angle_valid<=0; ack_valid<=0;
            if (rx_error) begin state<=H1; idle_ticks<=0; end
            else if (rx_valid) begin
                idle_ticks<=0;
                case (state)
                    H1: if (rx_data==8'h55) begin sum<=8'h55; state<=H2; end
                    H2: begin
                        if (rx_data==8'h55 || rx_data==8'haf) begin
                            is_ack<=(rx_data==8'haf); sum<=sum+rx_data; state<=ID;
                        end else state<=H1;
                    end
                    ID: begin
                        // Sliding sync for garbage ending in an extra 55 byte.
                        if (!is_ack && rx_data==8'h55) begin sum<=8'haa; state<=ID; end
                        else begin frame_id<=rx_data; sum<=sum+rx_data; state<=LEN; end
                    end
                    LEN: if (length_ok) begin
                        length<=rx_data; index<=0; sum<=sum+rx_data; state<=PAYLOAD;
                    end else begin
                        format_errors<=format_errors+1'b1;
                        state<=(rx_data==8'h55) ? H2 : H1; sum<=8'h55;
                    end
                    PAYLOAD: begin
                        payload[index]<=rx_data; sum<=sum+rx_data;
                        if (index==length-1) state<=CHECK;
                        else index<=index+1'b1;
                    end
                    CHECK: begin
                        state<=H1;
                        if (rx_data==sum) begin
                            frame_count<=frame_count+1'b1;
                            if (is_ack) begin
                                ack_valid<=1; ack_id<=frame_id; ack_len<=length;
                                ack_data<={(length>1 ? payload[1] : 8'b0),payload[0]};
                            end else if (frame_id==1) begin
                                roll<={payload[1],payload[0]};
                                pitch<={payload[3],payload[2]};
                                yaw<={payload[5],payload[4]}; angle_valid<=1;
                            end else if (frame_id==3) begin
                                ax<={payload[1],payload[0]}; ay<={payload[3],payload[2]};
                                az<={payload[5],payload[4]}; gx<={payload[7],payload[6]};
                                gy<={payload[9],payload[8]}; gz<={payload[11],payload[10]};
                                motion_valid<=1;
                            end
                        end else begin
                            checksum_errors<=checksum_errors+1'b1;
                            state<=(rx_data==8'h55) ? H2 : H1; sum<=8'h55;
                        end
                    end
                    default: state<=H1;
                endcase
            end else if (state!=H1) begin
                if (idle_ticks==TIMEOUT_TICKS-1) begin
                    state<=H1; idle_ticks<=0; timeouts<=timeouts+1'b1;
                end else idle_ticks<=idle_ticks+1'b1;
            end else idle_ticks<=0;
        end
    end
endmodule
