// 32 logarithmic, constant-peak-gain biquads, 50 Hz..12.5 kHz.
// Fs MUST be 50 MHz / 1024 = 48828.125 Hz. One shared signed multiplier.
// Coefficients Q28, filter state Q12. Mean-square energy, not MIDI animation.
module spectrum_analyzer_32 (
    input wire clk, input wire rst_n,
    input wire sample_tick, input wire signed [15:0] pcm,
    output reg [127:0] levels, output reg [127:0] peaks,
    output reg [3:0] beat
);
    localparam [3:0] IDLE=15;
    reg [3:0] phase;
    reg [4:0] band;
    reg signed [31:0] y1[0:31], y2[0:31];
    reg [31:0] energy[0:31];
    reg [3:0] height[0:31], peak[0:31], peak_hold[0:31];
    reg signed [31:0] x1, x2, delta_x, previous_y1, previous_y2;
    reg signed [31:0] operand_a, operand_b, filtered;
    reg signed [63:0] product, accumulator, result;
    wire signed [31:0] b0, a1, a2;
    spectrum_coeff_rom coefficients(.band(band), .b0(b0), .a1(a1), .a2(a2));
    wire signed [31:0] pcm_q12 = {{4{pcm[15]}}, pcm, 12'b0};
    wire signed [32:0] energy_difference = $signed({1'b0,product[31:0]}) - $signed({1'b0,energy[band]});
    reg [9:0] sample_div;
    reg refresh;
    reg [1:0] release_div;
    reg frame_tick;
    integer i;

    function signed [31:0] clamp_state;
        input signed [63:0] v;
        reg signed [63:0] shifted;
        begin
            shifted = v >>> 28;
            if (shifted > 64'sd2147483647) clamp_state=32'sh7fffffff;
            else if (shifted < -64'sd2147483648) clamp_state=32'sh80000000;
            else clamp_state=shifted[31:0];
        end
    endfunction
    function signed [31:0] pcm_for_square;
        input signed [31:0] v;
        reg signed [31:0] shifted;
        begin
            shifted = v >>> 12;
            if(shifted > 32767) pcm_for_square=32767;
            else if(shifted < -32768) pcm_for_square=-32768;
            else pcm_for_square=shifted;
        end
    endfunction
    // RMS thresholds 32,64,...4096: ~6 dB per row, no AGC/fake idle bars.
    function [3:0] energy_height;
        input [31:0] e;
        begin
            if(e>=16777216) energy_height=8;
            else if(e>=4194304) energy_height=7;
            else if(e>=1048576) energy_height=6;
            else if(e>=262144) energy_height=5;
            else if(e>=65536) energy_height=4;
            else if(e>=16384) energy_height=3;
            else if(e>=4096) energy_height=2;
            else if(e>=1024) energy_height=1;
            else energy_height=0;
        end
    endfunction
    wire [3:0] target_height = energy_height(energy[band]);
    // Visual smoothing only: <=1 row rise per 40 ms; 1 row fall per 80 ms.
    wire [3:0] next_height = target_height > height[band] ?
        (!release_div[0] ? height[band]+1'b1 : height[band]) :
        ((release_div==0 && target_height<height[band]) ? height[band]-1'b1 : height[band]);
    always @(posedge clk) begin
        if(!rst_n) begin
            phase<=IDLE; band<=0; x1<=0; x2<=0; delta_x<=0;
            operand_a<=0; operand_b<=0; product<=0; accumulator<=0;
            result<=0; filtered<=0; previous_y1<=0; previous_y2<=0;
            sample_div<=0; refresh<=0; release_div<=0; frame_tick<=0;
            levels<=0; peaks<=0;
            for(i=0;i<32;i=i+1) begin
                y1[i]<=0; y2[i]<=0; energy[i]<=0;
                height[i]<=0; peak[i]<=0; peak_hold[i]<=0;
            end
        end else begin
            frame_tick<=0;
            case(phase)
                IDLE: if(sample_tick) begin
                    delta_x<=pcm_q12-x2; x2<=x1; x1<=pcm_q12;
                    band<=0; phase<=0;
                    refresh <= sample_div==975;
                    if(sample_div==975) begin
                        sample_div<=0;
                        release_div<=release_div+1'b1; // 4 refreshes = ~80 ms.
                    end else sample_div<=sample_div+1'b1;
                end
                0: begin
                    operand_a<=b0; operand_b<=delta_x;
                    previous_y1<=y1[band]; previous_y2<=y2[band]; phase<=1;
                end
                1: begin product<=operand_a*operand_b; phase<=2; end
                2: begin accumulator<=product; operand_a<=a1; operand_b<=previous_y1; phase<=3; end
                3: begin product<=operand_a*operand_b; phase<=4; end
                4: begin accumulator<=accumulator-product; operand_a<=a2; operand_b<=previous_y2; phase<=5; end
                5: begin product<=operand_a*operand_b; phase<=6; end
                6: begin result<=accumulator-product; phase<=7; end
                7: begin filtered<=clamp_state(result); phase<=8; end
                8: begin
                    y1[band]<=filtered; y2[band]<=previous_y1;
                    operand_a<=pcm_for_square(filtered); operand_b<=pcm_for_square(filtered); phase<=9;
                end
                9: begin product<=operand_a*operand_b; phase<=10; end
                10: begin
                    // Signed subtraction is essential on decaying power.
                    energy[band] <= $signed({1'b0,energy[band]}) + (energy_difference >>> 9);
                    phase<=11;
                end
                11: begin
                    if(refresh) begin
                        height[band]<=next_height;
                        // Follow the visible column so the peak cannot jump ahead and flash.
                        if(next_height>=peak[band]) begin peak[band]<=next_height; peak_hold[band]<=10; end
                        else if(peak_hold[band]!=0) peak_hold[band]<=peak_hold[band]-1'b1;
                        else if(release_div==0 && peak[band]!=0) peak[band]<=peak[band]-1'b1;
                    end
                    if(band==31) phase<=12;
                    else begin band<=band+1'b1; phase<=0; end
                end
                12: begin
                    if(refresh) begin
                        for(i=0;i<32;i=i+1) begin
                            levels[i*4+:4]<=height[i]; peaks[i*4+:4]<=peak[i];
                        end
                        frame_tick<=1;
                    end
                    phase<=IDLE;
                end
                default: phase<=IDLE;
            endcase
        end
    end

    // Broadband onset follower: fast ~1.3 ms, slow ~84 ms, 160 ms lockout.
    // It decorates attacks (including piano); it does not estimate musical BPM.
    wire [15:0] magnitude = pcm[15] ? -pcm : pcm;
    wire signed [32:0] envelope_target = $signed({9'd0,magnitude,8'd0});
    reg signed [32:0] fast_envelope, slow_envelope;
    reg [12:0] refractory;
    always @(posedge clk) begin
        if(!rst_n) begin
            fast_envelope<=0; slow_envelope<=0; refractory<=0; beat<=0;
        end else begin
            if(frame_tick && beat!=0) beat<=beat-1'b1;
            if(sample_tick) begin
                fast_envelope<=fast_envelope+((envelope_target-fast_envelope) >>> 6);
                slow_envelope<=slow_envelope+((envelope_target-slow_envelope) >>> 12);
                if(refractory!=0) refractory<=refractory-1'b1;
                else if(fast_envelope > (slow_envelope <<< 1)+33'sd32768) begin
                    beat<=8; refractory<=7813;
                end
            end
        end
    end
endmodule
