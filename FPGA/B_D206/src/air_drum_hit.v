`timescale 1ns/1ps
// Initial gesture detector, NOT a calibrated spatial drum-plane model.
// Default: +Gy downstroke crosses 300 dps; rearm after 80 ms quiet or an upstroke.
// One clk pulse per hit. All inputs/outputs use the same clk domain.
module air_drum_hit #(
    parameter integer CLK_HZ=50000000,
    parameter integer GYRO_AXIS=1, // 0=X, 1=Y, 2=Z
    parameter integer DOWN_SIGN=1,
    parameter integer TRIGGER_RAW=4915, // 300/2000*32768
    parameter integer QUIET_RAW=1638,   // 100 dps
    parameter integer REARM_RAW=2458,   // 150 dps, opposite direction
    parameter integer COOLDOWN_MS=80, parameter integer QUIET_MS=80,
    parameter integer USE_ANGLE_GATE=0,
    parameter integer ANGLE_AXIS=1,
    parameter integer ANGLE_SIGN=1,
    parameter integer HIT_ANGLE_RAW=0
)(
    input wire clk, input wire rst_n, input wire enable,
    input wire motion_valid, input wire angles_fresh,
    input wire signed [15:0] gx,gy,gz,roll,pitch,yaw,
    output reg hit, output reg [7:0] strength,
    output reg [15:0] hit_count
);
    wire signed [15:0] raw_g=(GYRO_AXIS==0) ? gx : (GYRO_AXIS==1 ? gy : gz);
    wire signed [16:0] extended_g={raw_g[15],raw_g};
    wire signed [16:0] down_g=(DOWN_SIGN<0) ? -extended_g : extended_g;
    wire signed [15:0] raw_angle=(ANGLE_AXIS==0) ? roll : (ANGLE_AXIS==1 ? pitch : yaw);
    wire signed [16:0] extended_angle={raw_angle[15],raw_angle};
    wire signed [16:0] angle=(ANGLE_SIGN<0) ? -extended_angle : extended_angle;
    wire quiet_now=(down_g<=QUIET_RAW && down_g>=-QUIET_RAW);
    wire angle_ok=(!USE_ANGLE_GATE) || (angles_fresh && angle<=HIT_ANGLE_RAW);
    reg armed, quiet_sample;
    reg [31:0] cooldown, quiet_ticks;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hit<=0; strength<=0; hit_count<=0;
            armed<=0; quiet_sample<=0; cooldown<=0; quiet_ticks<=0;
        end else begin
            hit<=0;
            if (!enable) begin
                armed<=0; quiet_sample<=0; cooldown<=0; quiet_ticks<=0;
            end else begin
                if (cooldown!=0) cooldown<=cooldown-1'b1;
                if (quiet_sample) begin
                    if (quiet_ticks<(CLK_HZ/1000)*QUIET_MS) quiet_ticks<=quiet_ticks+1'b1;
                    else armed<=1;
                end else quiet_ticks<=0;
                if (motion_valid) begin
                    quiet_sample<=quiet_now;
                    if (!quiet_now) quiet_ticks<=0;
                    if (down_g<=-REARM_RAW) armed<=1;
                    if (armed && cooldown==0 && down_g>=TRIGGER_RAW && angle_ok) begin
                        hit<=1; armed<=0; quiet_ticks<=0; quiet_sample<=0;
                        cooldown<=(CLK_HZ/1000)*COOLDOWN_MS;
                        // Saturating rough velocity proxy; /128 maps full-scale to 255.
                        strength<=(down_g>=32640) ? 8'd255 : down_g[14:7];
                        hit_count<=hit_count+1'b1;
                    end
                end
            end
        end
    end
endmodule
