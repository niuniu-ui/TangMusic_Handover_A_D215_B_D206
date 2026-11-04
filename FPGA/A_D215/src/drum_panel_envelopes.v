// Four independent envelopes. Two simultaneous stick hits arrive on consecutive
// clocks from the existing event merger. LED refresh must never lose either hit.
module drum_panel_envelopes #(
    parameter integer PANEL_ZONE_0=3, PANEL_ZONE_1=2,
    parameter integer PANEL_ZONE_2=1, PANEL_ZONE_3=0
)(
    input wire clk,rst_n,frame_tick,event_valid,
    input wire [1:0] event_zone,
    input wire [7:0] event_velocity,
    output wire [31:0] frame_levels,
    output wire [31:0] frame_phases
);
    reg [7:0] level[0:3],next_level[0:3];
    reg [7:0] phase[0:3],next_phase[0:3];
    reg hold_frame[0:3],next_hold_frame[0:3];
    // AD05: hold each of 24 phases for two 50 Hz frames (~0.96 seconds).
    // Keep serial timing/refresh unchanged and restart immediately on every hit.
    // Bounded 6/8/10/12 of 255; 255 is the idle phase.
    wire [7:0] peak=8'd6+{5'b0,event_velocity[7:6],1'b0};
    integer i,j;
    function [1:0] zone_for_panel;
        input integer panel;
        begin
            case(panel)
                0:zone_for_panel=PANEL_ZONE_0;1:zone_for_panel=PANEL_ZONE_1;
                2:zone_for_panel=PANEL_ZONE_2;default:zone_for_panel=PANEL_ZONE_3;
            endcase
        end
    endfunction
    always @* begin
        for(i=0;i<4;i=i+1) begin
            next_level[i]=level[i];next_phase[i]=phase[i];
            next_hold_frame[i]=hold_frame[i];
            if(frame_tick && phase[i]!=255) begin
                next_hold_frame[i]=!hold_frame[i];
                if(hold_frame[i]) begin
                    if(phase[i]>=23) begin next_level[i]=0;next_phase[i]=255;end
                    else begin
                        next_phase[i]=phase[i]+1'b1;
                        if(phase[i]>=7 && phase[i][0] && level[i]>1) next_level[i]=level[i]-1'b1;
                    end
                end
            end
            // A new hit has priority over fading, including at a frame boundary.
            if(event_valid && event_zone==zone_for_panel(i)) begin
                next_level[i]=(level[i]>peak) ? level[i] : peak;
                next_phase[i]=0;
                next_hold_frame[i]=0;
            end
        end
    end
    assign frame_levels={next_level[3],next_level[2],next_level[1],next_level[0]};
    assign frame_phases={next_phase[3],next_phase[2],next_phase[1],next_phase[0]};
    always @(posedge clk) begin
        for(j=0;j<4;j=j+1) begin
            if(!rst_n) begin level[j]<=0;phase[j]<=255;hold_frame[j]<=0;end
            else begin level[j]<=next_level[j];phase[j]<=next_phase[j];hold_frame[j]<=next_hold_frame[j];end
        end
    end
endmodule
