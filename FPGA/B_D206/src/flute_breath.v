`timescale 1ns/1ps
// Parameters are ADC codes, not calibrated physical pressure units.
module flute_breath #(parameter integer CLK_HZ=50000000,
    CAL_SAMPLES=1024, WARMUP_SAMPLES=32, ON_LEVEL=40, OFF_LEVEL=24,
    FULL_LEVEL=600, SUPPLY_MIN=2500, SUPPLY_MAX=3700,
    DROP_BAD_SAMPLES=0, MEDIAN_FILTER=0, MIN_PRESSURE=1, FILTER_SHIFT=3)(
    input wire clk,rst_n,sample_valid,input wire [11:0] pressure,supply,
    output reg calibrated,gate,fault,
    output reg [11:0] baseline,filtered,delta,
    output reg [7:0] gain
);
    reg [31:0] samples,warmup,watchdog;
    reg [31:0] total;
    reg [15:0] filter_q4;
    reg gain_pending;
    reg [11:0] gain_delta;
    reg [11:0] history1,history2;
    reg [1:0] history_count;
    function [11:0] median3;
        input [11:0] a,b,c;
        begin
            if(a<=b) median3=(b<=c) ? b : ((a<=c) ? c : a);
            else median3=(a<=c) ? a : ((b<=c) ? c : b);
        end
    endfunction
    wire healthy=(supply>=SUPPLY_MIN && supply<=SUPPLY_MAX && pressure>=MIN_PRESSURE && pressure<4095);
    wire [11:0] clean_pressure=(MEDIAN_FILTER && history_count==2) ? median3(pressure,history1,history2) : pressure;
    wire signed [17:0] filter_error=$signed({2'b0,clean_pressure,4'b0})-$signed({2'b0,filter_q4});
    wire signed [17:0] filter_step=filter_error>>>FILTER_SHIFT;
    wire [15:0] next_filter=filter_q4+filter_step[15:0];
    wire [11:0] next_filtered=next_filter[15:4];
    wire [11:0] next_delta=(next_filtered>baseline) ? next_filtered-baseline : 12'd0;
    wire [31:0] scaled_gain=(gain_delta*255)/FULL_LEVEL;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            samples<=0;warmup<=0;watchdog<=0;total<=0;filter_q4<=0;gain_pending<=0;gain_delta<=0;
            history1<=0;history2<=0;history_count<=0;
            calibrated<=0;gate<=0;fault<=1;baseline<=0;filtered<=0;delta<=0;gain<=0;
        end else begin
            gain_pending<=0;
            // Register pressure delta before scaling; avoid filter + divider
            // in one 20ns path. One extra system cycle, not one ADC sample.
            if(gain_pending && calibrated && !fault) begin
                if(gain_delta>=FULL_LEVEL) gain<=255;
                else gain<=scaled_gain[7:0];
            end
            // In tolerant mode, invalid ADC words cannot refresh the watchdog.
            if(sample_valid && (healthy || !DROP_BAD_SAMPLES)) watchdog<=0;
            else if(watchdog<CLK_HZ/4) watchdog<=watchdog+1'b1;
            if(watchdog>=CLK_HZ/4) begin
                gate<=0;gain<=0;fault<=1;
                if(DROP_BAD_SAMPLES) begin
                    delta<=0;history_count<=0;
                    if(!calibrated) begin samples<=0;total<=0;warmup<=0;end
                end
            end
            if(sample_valid) begin
                if(!healthy) begin
                    if(!DROP_BAD_SAMPLES) begin
                        fault<=1;gate<=0;gain<=0;delta<=0;
                        if(!calibrated) begin samples<=0;total<=0;warmup<=0;end
                    end
                end else begin
                    fault<=0;history2<=history1;history1<=pressure;
                    if(history_count<2) history_count<=history_count+1'b1;
                    if(!calibrated) begin
                    filter_q4<={clean_pressure,4'b0};filtered<=clean_pressure;
                    if(warmup<WARMUP_SAMPLES) warmup<=warmup+1'b1;
                    else if(samples==CAL_SAMPLES-1) begin
                        baseline<=(total+clean_pressure)/CAL_SAMPLES;calibrated<=1;
                    end else begin total<=total+clean_pressure;samples<=samples+1'b1;end
                end else begin
                    filter_q4<=next_filter;filtered<=next_filtered;delta<=next_delta;
                    if(next_delta>=ON_LEVEL) gate<=1;
                    else if(next_delta<=OFF_LEVEL) gate<=0;
                    gain_delta<=next_delta;gain_pending<=1;
                end
                end
            end
        end
    end
endmodule
