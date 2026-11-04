// Real 32-band DAC spectrum, rendered as a quiet cyan/blue/violet matrix.
// 50 MHz, GRB/MSB, 256 pixels, 50 fps. Silence fades to completely black.
// Height is Q4: partial top pixels and eased envelopes remove row stepping.
module ws2812_matrix_32x8 #(
    parameter integer BRIGHTNESS_SHIFT=1,
    parameter integer BEAT_ACCENT=0,
    parameter integer PEAK_DOTS=1,
    parameter integer COLUMN_MAJOR=0,
    parameter integer SERPENTINE=1,
    parameter integer FLIP_X=0,
    parameter integer FLIP_Y=1,
    parameter integer TEST_PATTERN=0,
    parameter integer FRAME_CYCLES=1000000
)(
    input wire clk, input wire rst_n,
    input wire [127:0] levels, input wire [127:0] peaks,
    input wire [3:0] beat,
    output reg din
);
    // Coordinate origin: bottom left. x=0 is the lowest frequency band.
    reg [7:0] height_q4[0:31], crest_q4[0:31];
    reg [255:0] frame_heights, frame_crests;
    reg [127:0] captured_levels,captured_peaks;
    reg [4:0] update_index;
    reg [7:0] previous_height,previous_crest,next_height,next_crest;
    reg [3:0] target_height,target_crest;
    reg [3:0] frame_beat;
    reg [19:0] frame_counter;
    reg [14:0] reset_counter;
    reg [7:0] pixel_index;
    reg [4:0] bit_index;
    reg [5:0] bit_cycle;
    reg [23:0] shift_word;
    reg last_pixel;
    reg [2:0] state;
    localparam WAIT_FRAME=0, RESET_LOW=1, LOAD_PIXEL=2, SEND=3,
               READ_HEIGHT=4, CALC_HEIGHT=5, WRITE_HEIGHT=6;
    integer i;

    function [7:0] eased_height;
        input [7:0] previous;
        input [3:0] incoming;
        reg [7:0] target, difference;
        begin
            target=incoming>=8 ? 8'd128 : {incoming,4'b0};
            if(target>previous) begin
                difference=target-previous;
                eased_height=previous+((difference+8'd1)>>1);
            end else begin
                difference=previous-target;
                eased_height=previous-((difference+8'd7)>>3);
            end
        end
    endfunction

    // Bounded shift/add brightness scaling; no DSP multiplier is needed.
    function [7:0] shade;
        input [7:0] channel;
        input [4:0] amount;
        reg [12:0] sum;
        begin
            sum=(amount[0]?{5'b0,channel}:13'd0)
               +(amount[1]?{4'b0,channel,1'b0}:13'd0)
               +(amount[2]?{3'b0,channel,2'b0}:13'd0)
               +(amount[3]?{2'b0,channel,3'b0}:13'd0)
               +(amount[4]?{1'b0,channel,4'b0}:13'd0);
            shade=sum[11:4];
        end
    endfunction

    reg [4:0] x;
    reg [2:0] y;
    reg [4:0] x0,x1,x2,x3;
    reg [2:0] y0,y1,y2,y3;
    reg [7:0] h0,p0,floor_q4,cell_top,distance;
    reg [4:0] coverage,peak_coverage;
    reg [4:0] coverage1,peak_coverage1;
    reg [7:0] base_red,base_green,base_blue,red1,green1,blue1;
    reg [7:0] red2,green2,blue2,red3,green3,blue3;
    reg [7:0] pr2,pg2,pb2,pr3,pg3,pb3;
    reg [7:0] red,green,blue;
    reg [1:0] accent2;
    reg [23:0] pixel_grb;
    // Prepare the NEXT pixel while the current 24-bit word is transmitted.
    // Five registered render stages keep each 50 MHz path short, without
    // stretching the WS2812 word gap or exempting any internal timing paths.
    always @* begin
        if(COLUMN_MAJOR) begin
            x=pixel_index[7:3]; y=pixel_index[2:0];
            if(SERPENTINE && x[0]) y=7-y;
        end else begin
            x=pixel_index[4:0]; y=pixel_index[7:5];
            if(SERPENTINE && y[0]) x=31-x;
        end
        if(FLIP_X) x=31-x;
        if(FLIP_Y) y=7-y;
    end
    always @* begin
        floor_q4={1'b0,y0,4'b0};cell_top=floor_q4+8'd16;
        coverage=0;peak_coverage=0;distance=0;
        if(h0>=cell_top) coverage=16;
        else if(h0>floor_q4) coverage=h0-floor_q4;
        // Low frequency: pale blue; middle: blue; high: violet.
        if(!x0[4]) begin
            base_red=8'd0;
            base_green=8'd60-({2'd0,x0[3:0],2'b0});
            base_blue=8'd48;
        end else begin
            base_red={2'd0,x0[3:0],2'b0};
            base_green=8'd0;
            base_blue=8'd48;
        end
        if(PEAK_DOTS && p0!=0) begin
            distance=p0>cell_top ? p0-cell_top : cell_top-p0;
            if(distance<16) peak_coverage=5'd16-distance[4:0];
        end
    end
    always @* begin
        red=pr3>red3?pr3:red3;
        green=pg3>green3?pg3:green3;
        blue=pb3>blue3?pb3:blue3;
        if(TEST_PATTERN) begin
            red=0;green=0;blue=0;
            if(x3==0 && y3==0) red=12;
            if(x3==31 && y3==0) green=12;
            if(x3==0 && y3==7) blue=12;
            if(x3==31 && y3==7) begin red=8;green=8;blue=8;end
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            x0<=0;x1<=0;x2<=0;x3<=0;y0<=0;y1<=0;y2<=0;y3<=0;
            h0<=0;p0<=0;coverage1<=0;peak_coverage1<=0;
            red1<=0;green1<=0;blue1<=0;red2<=0;green2<=0;blue2<=0;
            red3<=0;green3<=0;blue3<=0;pr2<=0;pg2<=0;pb2<=0;
            pr3<=0;pg3<=0;pb3<=0;accent2<=0;pixel_grb<=0;
        end else begin
            x0<=x;y0<=y;h0<=frame_heights[x*8+:8];p0<=frame_crests[x*8+:8];
            x1<=x0;y1<=y0;coverage1<=coverage;peak_coverage1<=peak_coverage;
            red1<=base_red;green1<=base_green;blue1<=base_blue;
            x2<=x1;y2<=y1;
            red2<=shade(red1,coverage1);green2<=shade(green1,coverage1);blue2<=shade(blue1,coverage1);
            pr2<=shade(8'd4,peak_coverage1);pg2<=shade(8'd10,peak_coverage1);pb2<=shade(8'd16,peak_coverage1);
            accent2<=BEAT_ACCENT && coverage1!=0 ? frame_beat[3:2] : 2'd0;
            x3<=x2;y3<=y2;
            // A vertical light gradient gives each column a luminous cap.
            red3<=shade(red2,5'd8+{2'd0,y2});green3<=shade(green2,5'd8+{2'd0,y2});
            blue3<=shade(blue2,5'd8+{2'd0,y2})+{6'd0,accent2};
            pr3<=pr2;pg3<=pg2;pb3<=pb2;
            pixel_grb<={green>>BRIGHTNESS_SHIFT,red>>BRIGHTNESS_SHIFT,blue>>BRIGHTNESS_SHIFT};
        end
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            state<=RESET_LOW;reset_counter<=0;frame_counter<=0;
            frame_heights<=0;frame_crests<=0;frame_beat<=0;
            captured_levels<=0;captured_peaks<=0;update_index<=0;
            previous_height<=0;previous_crest<=0;next_height<=0;next_crest<=0;
            target_height<=0;target_crest<=0;
            pixel_index<=0;bit_index<=23;bit_cycle<=0;shift_word<=0;din<=0;last_pixel<=0;
            for(i=0;i<32;i=i+1) begin height_q4[i]<=0;crest_q4[i]<=0;end
        end else begin
            if(frame_counter<FRAME_CYCLES-1) frame_counter<=frame_counter+1'b1;
            case(state)
                WAIT_FRAME: begin
                    din<=0;
                    if(frame_counter==FRAME_CYCLES-1) begin
                        frame_counter<=0;reset_counter<=0;pixel_index<=0;
                        // Capture every band together, then reuse two easing
                        // units for all 32 bands. 96 cycles = 1.92 us/frame.
                        // The frame remains frozen throughout the wire transfer.
                        captured_levels<=levels;captured_peaks<=peaks;
                        frame_beat<=beat;update_index<=0;state<=READ_HEIGHT;
                    end
                end
                READ_HEIGHT: begin
                    previous_height<=height_q4[update_index];previous_crest<=crest_q4[update_index];
                    target_height<=captured_levels[update_index*4+:4];
                    target_crest<=captured_peaks[update_index*4+:4];
                    state<=CALC_HEIGHT;
                end
                CALC_HEIGHT: begin
                    next_height<=eased_height(previous_height,target_height);
                    next_crest<=eased_height(previous_crest,target_crest);state<=WRITE_HEIGHT;
                end
                WRITE_HEIGHT: begin
                    height_q4[update_index]<=next_height;crest_q4[update_index]<=next_crest;
                    frame_heights[update_index*8+:8]<=next_height;
                    frame_crests[update_index*8+:8]<=next_crest;
                    if(update_index==31) state<=RESET_LOW;
                    else begin update_index<=update_index+1'b1;state<=READ_HEIGHT;end
                end
                RESET_LOW: begin
                    din<=0;
                    if(reset_counter==19999) begin reset_counter<=0;state<=LOAD_PIXEL;end
                    else reset_counter<=reset_counter+1'b1;
                end
                LOAD_PIXEL: begin
                    shift_word<=pixel_grb;bit_index<=23;bit_cycle<=0;state<=SEND;
                    last_pixel<=pixel_index==255;
                    if(pixel_index!=255) pixel_index<=pixel_index+1'b1;
                end
                SEND: begin
                    // 1.26us cell: 340ns for zero, 660ns for one.
                    din<=bit_cycle<(shift_word[23]?33:17);
                    if(bit_cycle==62) begin
                        bit_cycle<=0;
                        if(bit_index==0) begin
                            if(last_pixel) state<=WAIT_FRAME;
                            else state<=LOAD_PIXEL;
                        end else begin shift_word<={shift_word[22:0],1'b0};bit_index<=bit_index-1'b1;end
                    end else bit_cycle<=bit_cycle+1'b1;
                end
                default: begin state<=RESET_LOW;reset_counter<=0;din<=0;end
            endcase
        end
    end
endmodule


