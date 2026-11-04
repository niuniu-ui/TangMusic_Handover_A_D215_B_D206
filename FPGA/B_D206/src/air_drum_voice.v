`timescale 1ns/1ps
// Complete independent DDS, noise source, frequency control and ADSR per voice.
// Fs = 50 MHz / 1024 = 48828.125 Hz. No recorded audio is stored.
module air_drum_voice #(parameter integer INDEX=0, SHARED_GAIN=1)(
    input wire clk,rst_n,sample_ce,note_on,
    input wire [1:0] zone, input wire [7:0] velocity,
    input wire bank, input wire signed [7:0] bend,
    input wire [7:0] expression, input wire spectral_test,
    output reg signed [15:0] pcm, output wire active,
    output wire signed [12:0] shared_wave, output wire [15:0] shared_env, output wire [7:0] shared_gain
);
    reg [31:0] phase, increment, base_increment;
    reg [22:0] noise;
    reg [15:0] envelope, sustain_level, attack_step, decay_step, release_step;
    reg [16:0] gate_left;
    reg [2:0] state;
    reg [1:0] kind;
    reg voice_bank;
    reg [7:0] gain;
    reg signed [12:0] wave;
    reg [15:0] env_pipe;
    reg [7:0] gain_pipe;
    reg [15:0] env_pipe2;
    // Exact reassociation: (wave * velocity) * envelope. 13x9 ->22, then
    // 22x17 ->39 fits two 27x18 DSPs, avoiding a 30x9 wide multiplier.
    // All intermediate bits and the original three-cycle latency are retained.
    reg signed [21:0] velocity_product;
    reg signed [38:0] gain_product;
    reg [2:0] ce_pipe;
    localparam OFF=0,ATTACK=1,DECAY=2,SUSTAIN=3,RELEASE=4;
    assign active=(state!=OFF) || spectral_test;
    assign shared_wave=wave; assign shared_env=env_pipe; assign shared_gain=gain_pipe;
    // Quarter-wave sine, 128 steps per period. Constant single-cycle waveform.
    function signed [12:0] sine;
        input [6:0] address;
        reg [4:0] x; reg signed [12:0] v;
        begin
            x=address[5] ? ~address[4:0] : address[4:0];
            case(x)
                0:v=0; 1:v=101; 2:v=201; 3:v=300; 4:v=399; 5:v=497;
                6:v=594; 7:v=689; 8:v=783; 9:v=874; 10:v=965; 11:v=1052;
                12:v=1137; 13:v=1219; 14:v=1298; 15:v=1375; 16:v=1448;
                17:v=1517; 18:v=1583; 19:v=1645; 20:v=1703; 21:v=1757;
                22:v=1806; 23:v=1851; 24:v=1892; 25:v=1927; 26:v=1959;
                27:v=1985; 28:v=2008; 29:v=2025; 30:v=2037; default:v=2045;
            endcase
            sine=address[6] ? -v : v;
        end
    endfunction
    function [31:0] hz_to_increment;
        input integer hz;
        // 2^32/Fs = 87960.93022208; 64-bit elaboration constant arithmetic.
        reg [63:0] wide,converted;
        begin wide=hz*64'd87960930222; converted=wide/1000000;hz_to_increment=converted[31:0];end
    endfunction
    // Fit one DSP and isolate mode/bend fanout from the 32-bit phase adder.
    // Discarding low 8 frequency bits changes pitch by <0.001 Hz.
    reg signed [32:0] bend_delta;
    reg [31:0] adjusted_increment,phase_step;
    wire [31:0] test_increment=hz_to_increment(220+INDEX*37);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            phase<=0;increment<=0;base_increment<=0;noise<=23'h12345+INDEX;
            bend_delta<=0;adjusted_increment<=0;phase_step<=0;
            envelope<=0;sustain_level<=0;attack_step<=0;decay_step<=0;release_step<=0;
            gate_left<=0;state<=OFF;kind<=0;voice_bank<=0;gain<=0;
            wave<=0;env_pipe<=0;gain_pipe<=0;env_pipe2<=0;
            velocity_product<=0;gain_product<=0;pcm<=0;ce_pipe<=0;
        end else begin
            bend_delta<=$signed({1'b0,increment[31:8]}) * bend;
            adjusted_increment<=increment+bend_delta[31:0];
            phase_step<=spectral_test ? test_increment : adjusted_increment;
            ce_pipe<={ce_pipe[1:0],sample_ce};
            if(sample_ce) begin
                phase<=phase+phase_step;
                noise<={noise[21:0],noise[22]^noise[17]};
                if(spectral_test) begin wave<=sine(phase[31:25]) >>> 2;env_pipe<=16'd65535;gain_pipe<=8'd255; end
                else begin
                    if(voice_bank) wave<=sine(phase[31:25]) + (sine(phase[30:24]) >>> 2);
                    else case(kind)
                        0,3:wave<=sine(phase[31:25]);
                        1:wave<=(sine(phase[31:25]) >>> 1)+($signed({noise[22],noise[22:12]}) >>> 1);
                        default:wave<=$signed({noise[22],noise[22:12]});
                    endcase
                    env_pipe<=envelope;gain_pipe<=gain;
                end
                if(gate_left!=0) gate_left<=gate_left-1'b1;
                if(!voice_bank && kind==0 && increment>base_increment)
                    increment<=increment-((increment-base_increment)>>7)-1'b1;
                case(state)
                    ATTACK:if(envelope>=65535-attack_step) begin envelope<=65535;state<=DECAY;end
                           else envelope<=envelope+attack_step;
                    DECAY:if(envelope<=sustain_level+decay_step) begin envelope<=sustain_level;state<=SUSTAIN;end
                          else envelope<=envelope-decay_step;
                    SUSTAIN:envelope<=sustain_level;
                    RELEASE:if(envelope<=release_step) begin envelope<=0;state<=OFF;end
                            else envelope<=envelope-release_step;
                    default:envelope<=0;
                endcase
                if(gate_left==1 && state!=OFF) state<=RELEASE;
            end
            // Events are synchronous and accepted independently of sample_ce.
            if(note_on) begin
                kind<=zone;voice_bank<=bank;gain<=velocity;phase<=0;envelope<=0;state<=ATTACK;
                attack_step<=bank ? 16'd1024 : 16'd8192;
                decay_step<=bank ? 16'd16 : (zone==2 ? 16'd160 : 16'd24);
                sustain_level<=bank ? 16'd8192 : 16'd4096;
                release_step<=bank ? 16'd4 : (zone==2 ? 16'd32 : 16'd8);
                gate_left<=bank ? (17'd12000+{expression,6'b0}) : (17'd1600+{expression,4'b0});
                if(bank) case(zone)
                    0:begin increment<=hz_to_increment(262);base_increment<=hz_to_increment(262);end
                    1:begin increment<=hz_to_increment(330);base_increment<=hz_to_increment(330);end
                    2:begin increment<=hz_to_increment(392);base_increment<=hz_to_increment(392);end
                    3:begin increment<=hz_to_increment(523);base_increment<=hz_to_increment(523);end
                endcase
                else case(zone)
                    0:begin increment<=hz_to_increment(150);base_increment<=hz_to_increment(55);end
                    1:begin increment<=hz_to_increment(180);base_increment<=hz_to_increment(180);end
                    2:begin increment<=hz_to_increment(7000);base_increment<=hz_to_increment(7000);end
                    3:begin increment<=hz_to_increment(110);base_increment<=hz_to_increment(110);end
                endcase
            end
            if(!SHARED_GAIN && ce_pipe[0]) begin velocity_product<=wave*$signed({1'b0,gain_pipe});env_pipe2<=env_pipe;end
            if(!SHARED_GAIN && ce_pipe[1]) gain_product<=velocity_product*$signed({1'b0,env_pipe2});
            if(!SHARED_GAIN && ce_pipe[2]) pcm<=gain_product >>> 24;
        end
    end
endmodule
