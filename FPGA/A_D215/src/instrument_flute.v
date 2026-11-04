`timescale 1ns/1ps
// CA77 acquisition and clean voice on the instrument's common 50 MHz clock.
// The existing PT8211 sample_tick sets the exact 1024-cycle stereo frame.
// No separate oscillator, DAC or asynchronous audio crossing is required.
module instrument_flute #(
    parameter integer CLK_HZ=50000000, FRAME_CYCLES=1024
)(
    input wire clk,rst_n,sample_tick,
    input wire timbre_suona,
    input wire [7:0] keys_n,
    input wire spi_miso,
    output wire spi_cs_n,spi_clk,spi_mosi,uart_tx,status_led,
    output wire signed [15:0] pcm,
    output wire [7:0] pressed,gain,
    output wire [6:0] note,
    output wire voice_active,calibrated,breath_gate,fault,fingering_valid
);
    wire miso_voted;
    flute_miso_filter input_filter(.clk(clk),.rst_n(rst_n),
        .miso_raw(spi_miso),.miso_clean(miso_voted));
    flute_keys #(.CLK_HZ(CLK_HZ)) keys(.clk(clk),.rst_n(rst_n),
        .keys_n(keys_n),.pressed(pressed));
    flute_fingering finger(.clk(clk),.rst_n(rst_n),.pressed(pressed),
        .note(note),.fingering_valid(fingering_valid));
    wire [11:0] pressure,supply,baseline,filtered,delta;
    wire pair_valid;
    flute_adc #(.CLK_HZ(CLK_HZ),.SPI_HZ(100000),.PAIR_HZ(1000)) adc(
        .clk(clk),.rst_n(rst_n),.miso(miso_voted),.cs_n(spi_cs_n),
        .sck(spi_clk),.mosi(spi_mosi),.pressure(pressure),.supply(supply),
        .pair_valid(pair_valid));
    flute_breath #(.CLK_HZ(CLK_HZ),.CAL_SAMPLES(128),.WARMUP_SAMPLES(16),
        .FULL_LEVEL(1200),.DROP_BAD_SAMPLES(1),.MEDIAN_FILTER(1),.MIN_PRESSURE(1)) breath(
        .clk(clk),.rst_n(rst_n),.sample_valid(pair_valid),.pressure(pressure),.supply(supply),
        .calibrated(calibrated),.gate(breath_gate),.fault(fault),.baseline(baseline),
        .filtered(filtered),.delta(delta),.gain(gain));
    wire voice_gate,test_mode;
    wire [7:0] voice_gain;
    wire [6:0] voice_note;
    // Preserve CA77's quiet start and three low-volume confirmation tones.
    // The common audio core owns PA_EN and both DAC serializers.
    flute_audio_control #(.SAMPLE_HZ((CLK_HZ+FRAME_CYCLES/2)/FRAME_CYCLES)) audio_control(
        .clk(clk),.rst_n(rst_n),.sample_ce(sample_tick),.breath_gain(gain),
        .finger_note(note),.calibrated(calibrated),.breath_gate(breath_gate),.fault(fault),
        .amp_enable(),.voice_gate(voice_gate),.test_mode(test_mode),
        .voice_gain(voice_gain),.voice_note(voice_note));
    flute_voice_select #(.CLK_HZ(CLK_HZ),.FRAME_CYCLES(FRAME_CYCLES)) voice(
        .clk(clk),.rst_n(rst_n),.sample_ce(sample_tick),.gate(voice_gate),
        .gain(voice_gain),.note(voice_note),.pure_tone(test_mode),.timbre_suona(timbre_suona),.active(voice_active),.pcm(pcm));
    reg [25:0] heartbeat;
    always @(posedge clk) begin
        if(!rst_n || heartbeat==CLK_HZ-1) heartbeat<=0;
        else heartbeat<=heartbeat+1'b1;
    end
    assign status_led=calibrated ? ~voice_gate : heartbeat<CLK_HZ/2;
    assign uart_tx=1'b1; // Desktop flute monitoring removed.
endmodule
