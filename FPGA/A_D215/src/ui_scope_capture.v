`timescale 1ns/1ps
// Ping-pong capture: the displayed bank is immutable for the entire frame.
// The writer cannot reuse it until the reader accepts the new bank at vblank.
module ui_scope_capture #(
 // Display-only power-of-two gain, 0..8. Default 3 = 8x the old trace.
 // Apply before 8-bit quantization so quiet notes retain visible detail.
 parameter integer DISPLAY_GAIN_SHIFT = 3
)(
 input wire audio_clk,audio_reset,sample_tick,input wire signed [15:0] pcm,
 input wire pixel_clk,pixel_reset,frame_end,input wire [8:0] read_x,
 output reg [15:0] sample_pair
);
 reg [15:0] samples[0:1023] /* synthesis syn_ramstyle = "block_ram" */;
 reg write_bank=0,read_bank=1;
 reg [8:0] write_x=0;
 reg [7:0] previous_sample=0;
 reg request=0,acknowledge=0,published_bank=0;
 (* syn_preserve=1 *) reg [1:0] ack_sync=0,req_sync=0;
 reg waiting=0,valid_bank=0;
 // Read-only branch from the DAC sample; never feed this back into audio.
 // Saturate both polarities rather than wrapping loud chords across the plot.
 wire signed [15:0] scaled_pcm=pcm >>> (8-DISPLAY_GAIN_SHIFT);
 wire [7:0] amplitude=scaled_pcm>16'sd127 ? 8'h7f :
                      scaled_pcm< -16'sd128 ? 8'h80 : scaled_pcm[7:0];
 always @(posedge audio_clk) begin
  ack_sync<={ack_sync[0],acknowledge};
  if(audio_reset) begin
   write_bank<=0;write_x<=0;request<=0;published_bank<=0;
   previous_sample<=0;waiting<=0;ack_sync<=0;
  end else if(waiting) begin
   if(ack_sync[1]==request) begin waiting<=0;write_bank<=!write_bank;write_x<=0;previous_sample<=0;end
  end else if(sample_tick) begin
   samples[{write_bank,write_x}]<={write_x==0 ? amplitude : previous_sample,amplitude};
   previous_sample<=amplitude;
   if(write_x==511) begin request<=!request;published_bank<=write_bank;waiting<=1;end
   else write_x<=write_x+1'b1;
  end
 end
 always @(posedge pixel_clk) begin
  req_sync<={req_sync[0],request};
  sample_pair<=valid_bank ? samples[{read_bank,read_x}] : 16'b0;
  if(pixel_reset) begin
   req_sync<=0;acknowledge<=0;read_bank<=1;valid_bank<=0;sample_pair<=0;
  end else if(frame_end && req_sync[1]!=acknowledge) begin
   read_bank<=published_bank;acknowledge<=req_sync[1];valid_bank<=1;
  end
 end
endmodule
