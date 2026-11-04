// Same 50 MHz serial timing as AD01 / accepted EDA5-EDA7.
// Snapshot all four panel levels once per frame: no mid-frame colour tearing.
module ws2812_drum_panels #(
    parameter integer FRAME_CYCLES=1000000
)(
    input wire clk,rst_n,
    input wire [31:0] panel_levels,panel_phases,
    output wire frame_tick,
    output reg din
);
    localparam WAIT_FRAME=0,RESET_LOW=1,LOAD_PIXEL=2,SEND=3;
    reg [1:0] state;
    reg [19:0] frame_counter;
    reg [14:0] reset_counter;
    reg [7:0] pixel_index;
    reg [4:0] bit_index;
    reg [5:0] bit_cycle;
    reg [23:0] shift_word;
    reg [31:0] snapshot,snapshot_phases;
    wire [23:0] pixel_grb;
    drum_ripple_pixel renderer(.pixel_index(pixel_index),.levels(snapshot),.phases(snapshot_phases),.grb(pixel_grb));
    assign frame_tick=rst_n && state==WAIT_FRAME && frame_counter==FRAME_CYCLES-1;
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=RESET_LOW;reset_counter<=0;frame_counter<=0;snapshot<=0;snapshot_phases<=32'hffffffff;
            pixel_index<=0;bit_index<=23;bit_cycle<=0;shift_word<=0;din<=0;
        end else begin
            if(frame_counter<FRAME_CYCLES-1) frame_counter<=frame_counter+1'b1;
            case(state)
                WAIT_FRAME:begin
                    din<=0;
                    if(frame_tick) begin
                        frame_counter<=0;reset_counter<=0;pixel_index<=0;
                        snapshot<=panel_levels;snapshot_phases<=panel_phases;state<=RESET_LOW;
                    end
                end
                RESET_LOW:begin
                    din<=0;
                    if(reset_counter==19999) begin reset_counter<=0;state<=LOAD_PIXEL;end
                    else reset_counter<=reset_counter+1'b1;
                end
                LOAD_PIXEL:begin
                    shift_word<=pixel_grb;bit_index<=23;bit_cycle<=0;state<=SEND;
                end
                SEND:begin
                    din<=bit_cycle<(shift_word[23]?45:17);
                    if(bit_cycle==62) begin
                        bit_cycle<=0;
                        if(bit_index==0) begin
                            if(pixel_index==255) state<=WAIT_FRAME;
                            else begin pixel_index<=pixel_index+1'b1;state<=LOAD_PIXEL;end
                        end else begin shift_word<={shift_word[22:0],1'b0};bit_index<=bit_index-1'b1;end
                    end else bit_cycle<=bit_cycle+1'b1;
                end
                default:begin state<=RESET_LOW;reset_counter<=0;snapshot<=0;din<=0;end
            endcase
        end
    end
endmodule
