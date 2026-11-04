`timescale 1ns/1ps
// Independent dimensions: yaw selects drum; stroke velocity controls gain;
// roll bends active pitches; pitch controls duration and effect amount.
module air_drum_expression #(
    // +/-45 degree outer boundaries, +/-8 degree hysteresis on every boundary.
    // IMU units are 32768 / 180 degrees. All constants evaluated at elaboration.
    parameter integer OUTER_BOUNDARY_RAW=8192,
    parameter integer HYSTERESIS_RAW=1456
)(
    input wire clk,rst_n,hit,angles_fresh,angle_valid,
    input wire signed [15:0] roll,pitch,yaw,
    input wire [7:0] strength,
    output reg event_valid, output reg [1:0] event_zone,
    output reg [7:0] event_velocity,
    output reg signed [7:0] bend, output reg [7:0] expression,
    output reg [1:0] current_zone,
    output wire signed [15:0] relative_yaw,
    output wire calibrated
);
    reg centered;reg signed [15:0] yaw_center;
    wire signed [15:0] yaw_delta=yaw-yaw_center; // modular +/-180 deg difference
    assign relative_yaw=yaw_delta;
    assign calibrated=centered;
    wire signed [15:0] roll_scaled=roll >>> 7;
    wire signed [16:0] pitch_scaled=17'sd128+($signed({pitch[15],pitch}) >>> 7);
    reg [1:0] next_zone;
    always @* begin
        next_zone=current_zone;
        // Direct jumps avoid traversing intermediate instruments for several
        // sensor frames when the player moves from one extreme to the other.
        case(current_zone)
            0:begin
                if(yaw_delta>OUTER_BOUNDARY_RAW+HYSTERESIS_RAW) next_zone=3;
                else if(yaw_delta>HYSTERESIS_RAW) next_zone=2;
                else if(yaw_delta> -OUTER_BOUNDARY_RAW+HYSTERESIS_RAW) next_zone=1;
            end
            1:begin
                if(yaw_delta>OUTER_BOUNDARY_RAW+HYSTERESIS_RAW) next_zone=3;
                else if(yaw_delta>HYSTERESIS_RAW) next_zone=2;
                else if(yaw_delta< -OUTER_BOUNDARY_RAW-HYSTERESIS_RAW) next_zone=0;
            end
            2:begin
                if(yaw_delta< -OUTER_BOUNDARY_RAW-HYSTERESIS_RAW) next_zone=0;
                else if(yaw_delta< -HYSTERESIS_RAW) next_zone=1;
                else if(yaw_delta>OUTER_BOUNDARY_RAW+HYSTERESIS_RAW) next_zone=3;
            end
            3:begin
                if(yaw_delta< -OUTER_BOUNDARY_RAW-HYSTERESIS_RAW) next_zone=0;
                else if(yaw_delta< -HYSTERESIS_RAW) next_zone=1;
                else if(yaw_delta<OUTER_BOUNDARY_RAW-HYSTERESIS_RAW) next_zone=2;
            end
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin centered<=0;yaw_center<=0;event_valid<=0;event_zone<=0;event_velocity<=0;bend<=0;expression<=128;current_zone<=1;end
        else begin
            event_valid<=0;
            if(angle_valid) begin
                if(!centered) begin centered<=1;yaw_center<=yaw;current_zone<=1;end
                else current_zone<=next_zone;
                bend<=roll_scaled>64 ? 8'sd64 : (roll_scaled< -64 ? -8'sd64 : roll_scaled[7:0]);
                expression<=pitch_scaled>255 ? 255 : (pitch_scaled<0 ? 0 : pitch_scaled[7:0]);
            end
            if(!angles_fresh) begin bend<=0;expression<=128;end
            if(hit && centered && angles_fresh) begin
                event_valid<=1;event_velocity<=strength;
                event_zone<=angle_valid ? next_zone : current_zone;
            end
        end
    end
endmodule
