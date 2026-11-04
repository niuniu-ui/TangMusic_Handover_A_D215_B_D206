`timescale 1ns/1ps
// Reusable front end. Connect hit/strength/drum_id to your EXISTING audio engine.
// The caller supplies a clean active-low reset in the clk domain.
module air_drum_imu_core #(
    parameter integer CLK_HZ=50000000, parameter integer IMU_BAUD=115200,
    parameter integer AUTO_CONFIG=1, parameter integer CONFIG_STARTUP_MS=1500,
    parameter integer CONFIG_GAP_MS=20, parameter integer CONFIG_ACK_MS=150,
    parameter integer LINK_TIMEOUT_MS=250,
    parameter integer GYRO_AXIS=1, parameter integer DOWN_SIGN=1,
    parameter integer TRIGGER_RAW=4915, parameter integer QUIET_RAW=1638,
    parameter integer REARM_RAW=2458, parameter integer COOLDOWN_MS=80,
    parameter integer QUIET_MS=80, parameter integer USE_ANGLE_GATE=0,
    parameter integer ANGLE_AXIS=1, parameter integer ANGLE_SIGN=1,
    parameter integer HIT_ANGLE_RAW=0
)(
    input wire clk, input wire rst_n,
    input wire imu_rx, output wire imu_tx,
    output wire signed [15:0] ax,ay,az,gx,gy,gz,roll,pitch,yaw,
    output wire motion_valid, output wire angle_valid,
    output wire link_ok, output wire angles_fresh,
    output wire config_done, output wire config_failed,
    output wire [7:0] config_failed_reg,
    output wire hit, output wire [7:0] strength, output wire [7:0] drum_id,
    output wire [15:0] hit_count, frame_count,
    output wire [15:0] checksum_errors, format_errors, timeouts,
    output reg [15:0] uart_errors
);
    wire [7:0] rx_byte,tx_byte,ack_id,ack_len;
    wire [15:0] ack_data;
    wire rx_valid,rx_error,tx_valid,tx_ready,tx_done,ack_valid;
    reg motion_seen,angle_seen;
    reg [31:0] motion_age,angle_age;
    localparam integer LINK_TICKS=(CLK_HZ/1000)*LINK_TIMEOUT_MS;
    assign link_ok=motion_seen && motion_age<LINK_TICKS;
    assign angles_fresh=angle_seen && angle_age<LINK_TICKS;
    assign drum_id=8'd0;
    air_uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(IMU_BAUD)) receiver(
        .clk(clk),.rst_n(rst_n),.rx(imu_rx),.rx_data(rx_byte),
        .rx_valid(rx_valid),.framing_error(rx_error));
    air_uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(IMU_BAUD)) transmitter(
        .clk(clk),.rst_n(rst_n),.tx_data(tx_byte),.tx_valid(tx_valid),
        .tx_ready(tx_ready),.tx(imu_tx),.tx_done(tx_done));
    air_atk_imu901_parser #(.CLK_HZ(CLK_HZ)) parser(
        .clk(clk),.rst_n(rst_n),.rx_data(rx_byte),.rx_valid(rx_valid),.rx_error(rx_error),
        .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),
        .roll(roll),.pitch(pitch),.yaw(yaw),
        .motion_valid(motion_valid),.angle_valid(angle_valid),
        .ack_valid(ack_valid),.ack_id(ack_id),.ack_len(ack_len),.ack_data(ack_data),
        .frame_count(frame_count),.checksum_errors(checksum_errors),
        .format_errors(format_errors),.timeouts(timeouts));
    air_atk_imu901_config #(.CLK_HZ(CLK_HZ),.ENABLE(AUTO_CONFIG),
        .STARTUP_MS(CONFIG_STARTUP_MS),.GAP_MS(CONFIG_GAP_MS),.ACK_TIMEOUT_MS(CONFIG_ACK_MS)) config_writer(
        .clk(clk),.rst_n(rst_n),.tx_data(tx_byte),.tx_valid(tx_valid),.tx_ready(tx_ready),
        .ack_valid(ack_valid),.ack_id(ack_id),.ack_len(ack_len),.ack_data(ack_data),
        .done(config_done),.failed(config_failed),.failed_reg(config_failed_reg));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            motion_seen<=0; angle_seen<=0; motion_age<=LINK_TICKS; angle_age<=LINK_TICKS;
            uart_errors<=0;
        end else begin
            if (rx_error) uart_errors<=uart_errors+1'b1;
            if (motion_valid) begin motion_seen<=1; motion_age<=0; end
            else if (motion_age<LINK_TICKS) motion_age<=motion_age+1'b1;
            if (angle_valid) begin angle_seen<=1; angle_age<=0; end
            else if (angle_age<LINK_TICKS) angle_age<=angle_age+1'b1;
        end
    end
    air_drum_hit #(.CLK_HZ(CLK_HZ),.GYRO_AXIS(GYRO_AXIS),.DOWN_SIGN(DOWN_SIGN),
        .TRIGGER_RAW(TRIGGER_RAW),.QUIET_RAW(QUIET_RAW),.REARM_RAW(REARM_RAW),
        .COOLDOWN_MS(COOLDOWN_MS),.QUIET_MS(QUIET_MS),.USE_ANGLE_GATE(USE_ANGLE_GATE),
        .ANGLE_AXIS(ANGLE_AXIS),.ANGLE_SIGN(ANGLE_SIGN),.HIT_ANGLE_RAW(HIT_ANGLE_RAW)) hit_detector(
        // Accept the first verified motion frame before the age register updates.
        .clk(clk),.rst_n(rst_n),.enable(config_done && (link_ok || motion_valid)),
        .motion_valid(motion_valid),.angles_fresh(angles_fresh),
        .gx(gx),.gy(gy),.gz(gz),.roll(roll),.pitch(pitch),.yaw(yaw),
        .hit(hit),.strength(strength),.hit_count(hit_count));
endmodule
