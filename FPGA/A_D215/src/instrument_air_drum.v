`timescale 1ns/1ps
// Dual IMU instrument on the shared 50 MHz clock and 1024-cycle audio tick.
// Preserve source gestures, 32 voices, modes and drum effects. The common
// audio core owns both DACs, global volume and amplifier startup.
// Independent performance copy: telemetry is exported for a dedicated U15 UART.
module instrument_air_drum #(
    parameter integer CLK_HZ=50000000, VOICES=32,
    DEBOUNCE_TICKS=1000000, LONG_PRESS_TICKS=50000000,
    DEFAULT_MODE=0, AUTO_CONFIG=1, REMOTE_SYNTH=0
)(
    input wire clk,rst_n,sample_tick,key_s1_n,imu_rx,imu2_rx,
    input wire bank_set,bank_value,
    output wire imu_tx,imu2_tx,
    output wire signed [15:0] pcm,
    output wire [VOICES-1:0] active_mask,
    output wire [1:0] mode_out,imu_link,imu_configured,
    output wire bank_out,audio_fault,monitor_led_n,
    output wire led_event_valid,
    output wire hit_probe_pulse,
    output wire [1:0] led_event_zone,
    output wire [7:0] led_event_velocity,
    output wire [18:0] synth_event_data,output wire [7:0] synth_bend,synth_expression,
    output reg [511:0] monitor_snapshot
);
    wire signed [15:0] ax,ay,az,gx,gy,gz,roll,pitch,yaw;
    wire mv,av,link_ok,angles_fresh,configured,failed,hit;
    wire [7:0] strength,unused_drum_id,failed_reg;
    wire [15:0] imu_hits,frames,sums,formats,timeouts,uart_errors;
    air_drum_imu_core #(.CLK_HZ(CLK_HZ),.AUTO_CONFIG(AUTO_CONFIG),
        .COOLDOWN_MS(30),.QUIET_MS(30)) imu(
        .clk(clk),.rst_n(rst_n),.imu_rx(imu_rx),.imu_tx(imu_tx),
        .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.roll(roll),.pitch(pitch),.yaw(yaw),
        .motion_valid(mv),.angle_valid(av),.link_ok(link_ok),.angles_fresh(angles_fresh),
        .config_done(configured),.config_failed(failed),.config_failed_reg(failed_reg),
        .hit(hit),.strength(strength),.drum_id(unused_drum_id),.hit_count(imu_hits),
        .frame_count(frames),.checksum_errors(sums),.format_errors(formats),.timeouts(timeouts),.uart_errors(uart_errors));
    wire gesture_event;wire [1:0] gesture_zone,current_zone;
    wire [7:0] gesture_velocity,expression;wire signed [7:0] bend;
    wire signed [15:0] relative_yaw0,relative_yaw1;
    wire centered0,centered1;
    air_drum_expression control(.clk(clk),.rst_n(rst_n),.hit(hit),.angles_fresh(angles_fresh),
        .angle_valid(av),.roll(roll),.pitch(pitch),.yaw(yaw),.strength(strength),
        .event_valid(gesture_event),.event_zone(gesture_zone),.event_velocity(gesture_velocity),
        .bend(bend),.expression(expression),.current_zone(current_zone),
        .relative_yaw(relative_yaw0),.calibrated(centered0));
    wire signed [15:0] roll2,pitch2,yaw2;
    wire av2,angles_fresh2,link_ok2,configured2,failed2,hit2;
    wire [7:0] strength2;
    wire [15:0] imu_hits2,frames2;
    air_drum_imu_core #(.CLK_HZ(CLK_HZ),.AUTO_CONFIG(AUTO_CONFIG),
        .COOLDOWN_MS(30),.QUIET_MS(30)) imu2(
        .clk(clk),.rst_n(rst_n),.imu_rx(imu2_rx),.imu_tx(imu2_tx),
        .roll(roll2),.pitch(pitch2),.yaw(yaw2),.angle_valid(av2),
        .link_ok(link_ok2),.angles_fresh(angles_fresh2),
        .config_done(configured2),.config_failed(failed2),
        .hit(hit2),.strength(strength2),.hit_count(imu_hits2),.frame_count(frames2));
    wire gesture_event2;wire [1:0] gesture_zone2,current_zone2;
    wire [7:0] gesture_velocity2,expression2;wire signed [7:0] bend2;
    air_drum_expression control2(.clk(clk),.rst_n(rst_n),.hit(hit2),.angles_fresh(angles_fresh2),
        .angle_valid(av2),.roll(roll2),.pitch(pitch2),.yaw(yaw2),.strength(strength2),
        .event_valid(gesture_event2),.event_zone(gesture_zone2),.event_velocity(gesture_velocity2),
        .bend(bend2),.expression(expression2),.current_zone(current_zone2),
        .relative_yaw(relative_yaw1),.calibrated(centered1));
    // NEO S1 (Y12, legacy port key_s1_n): short release toggles bank/auditions.
    // Hold >=1s: next mode once. NEO S2 (AB13) resets to live mode.
    // Modes: 0 live, 1 automatic demo, 3 offline rhythm guide; spectrum test removed.
    (* syn_preserve=1 *) reg [1:0] key_sync;
    reg key_down,long_done;reg [31:0] debounce,held;
    reg bank;reg [1:0] mode,demo_zone;reg audition;
    reg [31:0] beat_count,led_hold;reg [3:0] beat_index;
    reg demo_event;reg [1:0] demo_event_zone;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            key_sync<=3;key_down<=0;long_done<=0;debounce<=0;held<=0;bank<=0;mode<=DEFAULT_MODE;
            audition<=0;beat_count<=0;beat_index<=0;demo_zone<=0;demo_event<=0;demo_event_zone<=0;led_hold<=0;
        end else begin
            key_sync<={key_sync[0],key_s1_n};audition<=0;demo_event<=0;
            if(led_hold!=0) led_hold<=led_hold-1'b1;
            if(bank_set)bank<=bank_value;
            if((!key_sync[1])!=key_down) begin
                if(debounce==DEBOUNCE_TICKS-1) begin
                    debounce<=0;key_down<=!key_sync[1];
                    if(key_sync[1] && !long_done) begin bank<=!bank;audition<=1;demo_zone<=demo_zone+1'b1;end
                    if(!key_sync[1]) begin held<=0;long_done<=0;end
                end else debounce<=debounce+1'b1;
            end else debounce<=0;
            if(key_down && !long_done) begin
                if(held==LONG_PRESS_TICKS-1) begin mode<=mode==0?1:mode==1?3:0;long_done<=1;beat_count<=0;beat_index<=0;end
                else held<=held+1'b1;
            end
            if(mode==1 || mode==3) begin
                if(beat_count==CLK_HZ/4-1) begin
                    beat_count<=0;beat_index<=beat_index+1'b1;
                    // 16-step kick/snare/hat rhythm, deterministic offline guide.
                    if(mode==1 || !beat_index[0]) begin
                        demo_event<=1;led_hold<=CLK_HZ/10;
                        demo_event_zone<=beat_index[1:0]==0 ? 0 : (beat_index[1:0]==2 ? 1 : 2);
                    end
                end else beat_count<=beat_count+1'b1;
            end else beat_count<=0;
        end
    end
    // Only boost live IMU strikes. Audition/demo stay at velocity 200.
    // Widen before multiplying, then saturate to retain velocity ordering.
    wire [8:0] boosted_gesture_velocity={gesture_velocity,1'b0};
    wire [7:0] live_velocity=boosted_gesture_velocity[8] ? 8'd255 : boosted_gesture_velocity[7:0];
    wire [8:0] boosted_gesture_velocity2={gesture_velocity2,1'b0};
    wire [7:0] live_velocity2=boosted_gesture_velocity2[8] ? 8'd255 : boosted_gesture_velocity2[7:0];
    wire event_valid,merge_overflow;wire [18:0] merged_event;
    wire [1:0] event_zone;wire [7:0] event_velocity,event_expression;wire event_bank;
    assign {event_bank,event_expression,event_zone,event_velocity}=merged_event;
    // Observe the same merged events that feed the sound engine; never stall it.
    assign led_event_valid=event_valid;
    // Accepted live IMU gesture, before event FIFO and remote synthesis.
    // Simultaneous sticks share a pulse; each asserted cycle is one event.
    assign hit_probe_pulse=rst_n && mode==0 && (gesture_event || gesture_event2);
    assign synth_event_data=merged_event;assign synth_bend=bend;assign synth_expression=expression;
    assign led_event_zone=event_zone;
    assign led_event_velocity=event_velocity;
    air_drum_event_merge merger(.clk(clk),.rst_n(rst_n),.enable(1'b1),
        .valid0(audition || demo_event),.valid1(mode==0 && gesture_event),.valid2(mode==0 && gesture_event2),
        .data0({bank,expression,(audition ? demo_zone : demo_event_zone),8'd200}),
        .data1({bank,expression,gesture_zone,live_velocity}),
        .data2({bank,expression2,gesture_zone2,live_velocity2}),
        .out_valid(event_valid),.out_data(merged_event),.overflow(merge_overflow));
    wire sample_ce=sample_tick;wire signed [15:0] dry,wet_pcm;wire dry_valid,wet_valid;
    // Retain original effect parameter sampling at the original dry-valid cycle.
    reg [9:0] original_valid_pipe;reg [7:0] original_wet;
    always @(posedge clk or negedge rst_n) begin
     if(!rst_n)begin original_valid_pipe<=0;original_wet<=0;end
     else begin original_valid_pipe<={original_valid_pipe[8:0],sample_ce};if(original_valid_pipe[9])original_wet<=expression;end
    end
    wire overflow;wire [15:0] audio_events;
    generate if(!REMOTE_SYNTH)begin:local_audio
    air_drum_synth #(.VOICES(VOICES)) synth(.clk(clk),.rst_n(rst_n),.sample_ce(sample_ce),
        .event_valid(event_valid),.event_zone(event_zone),.event_velocity(event_velocity),
        .bank(event_bank),.bend(bend),.expression(event_expression),.spectral_test(1'b0),
        .pcm(dry),.pcm_valid(dry_valid),.active_mask(active_mask),.overflow(overflow),.event_count(audio_events));
    air_drum_delay effect(.clk(clk),.rst_n(rst_n),.in_valid(dry_valid),.dry(dry),
        .wet(original_wet),.bypass(1'b0),.pcm(wet_pcm),.out_valid(wet_valid));
    wire signed [15:0] output_pcm;
    air_drum_master_gain master_gain(.pcm_in(wet_pcm),.bypass(1'b0),.pcm_out(output_pcm));
    assign pcm=output_pcm;
    end else begin:remote_audio
     assign dry=0;assign wet_pcm=0;assign dry_valid=0;assign wet_valid=0;assign active_mask=0;assign overflow=0;assign pcm=0;
     reg [15:0] accepted=0;always @(posedge clk)if(!rst_n)accepted<=0;else if(event_valid)accepted<=accepted+1'b1;
     assign audio_events=accepted;
    end endgenerate
    // Sticky deadline indicator: each requested sample must finish before next.
    reg pending_sample,deadline_error;reg [24:0] heartbeat;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin pending_sample<=0;deadline_error<=0;heartbeat<=0;end
        else begin
            heartbeat<=heartbeat+1'b1;
            if(wet_valid) pending_sample<=0;
            if(sample_ce&&!REMOTE_SYNTH) begin if(pending_sample) deadline_error<=1;pending_sample<=1;end
        end
    end
    assign mode_out=mode;
    assign bank_out=bank;
    assign imu_link={link_ok2,link_ok};
    assign imu_configured={configured2,configured};
    assign audio_fault=overflow|deadline_error|merge_overflow;
    reg [15:0] accepted_hits0,accepted_hits1,clip_count;
    reg [1:0] last_zone0,last_zone1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin accepted_hits0<=0;accepted_hits1<=0;clip_count<=0;last_zone0<=0;last_zone1<=0;end
        else begin
            if(mode==0 && gesture_event) begin accepted_hits0<=accepted_hits0+1'b1;last_zone0<=gesture_zone;end
            if(mode==0 && gesture_event2) begin accepted_hits1<=accepted_hits1+1'b1;last_zone1<=gesture_zone2;end
            if(wet_valid && mode!=2 && (wet_pcm>16'sd4095 || wet_pcm< -16'sd4096) && clip_count!=65535)
                clip_count<=clip_count+1'b1;
        end
    end
    // Byte layout is specified in monitor/PROTOCOL.txt. Header/time/CRC are
    // supplied by performance_telemetry; all values are latched atomically there.
    always @* begin
        monitor_snapshot=0;
        monitor_snapshot[6*8+:8]={3'b0,centered0,failed,angles_fresh,configured,link_ok};
        monitor_snapshot[7*8+:8]={3'b0,centered1,failed2,angles_fresh2,configured2,link_ok2};
        monitor_snapshot[8*8+:16]=relative_yaw0;
        monitor_snapshot[10*8+:16]=pitch;
        monitor_snapshot[12*8+:16]=roll;
        monitor_snapshot[14*8+:16]=relative_yaw1;
        monitor_snapshot[16*8+:16]=pitch2;
        monitor_snapshot[18*8+:16]=roll2;
        monitor_snapshot[20*8+:8]={6'b0,current_zone};
        monitor_snapshot[21*8+:8]={6'b0,current_zone2};
        monitor_snapshot[22*8+:8]=strength;
        monitor_snapshot[23*8+:8]=strength2;
        monitor_snapshot[24*8+:16]=accepted_hits0;
        monitor_snapshot[26*8+:16]=accepted_hits1;
        monitor_snapshot[28*8+:16]=audio_events;
        monitor_snapshot[30*8+:8]={6'b0,mode};
        monitor_snapshot[31*8+:8]={7'b0,bank};
        monitor_snapshot[32*8+:16]=16'd8192;
        monitor_snapshot[34*8+:16]=16'd1456;
        monitor_snapshot[36*8+:8]=8'd8;
        monitor_snapshot[37*8+:8]=8'd12;
        monitor_snapshot[38*8+:8]=8'h1b;
        monitor_snapshot[39*8+:8]={7'b0,audio_fault};
        monitor_snapshot[40*8+:16]=frames;
        monitor_snapshot[42*8+:16]=frames2;
        monitor_snapshot[48*8+:8]={6'b0,last_zone0};
        monitor_snapshot[49*8+:8]={6'b0,last_zone1};
        monitor_snapshot[50*8+:16]=clip_count;
        monitor_snapshot[56*8+:16]=16'had05;
    end
    // Internal status only: the integrated top deliberately leaves this open.
    assign monitor_led_n=!rst_n ? 1'b1 : (audio_fault ? ~heartbeat[23] :
        (mode==3 ? (led_hold==0) : ~(|active_mask)));
endmodule
