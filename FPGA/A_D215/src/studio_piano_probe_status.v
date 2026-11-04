`timescale 1ns/1ps
// Read-only evidence for a single physical-key test. Never drives audio/control.
// Keep NoteOn metadata after release; track the synth peak/active mask until
// the next physical NoteOn. Play one key alone when interpreting these fields.
module studio_piano_probe_status(
 input wire clk,rst_n,raw_press,sample_tick,
 input wire scan_valid,input wire [3:0] scan_kind,
 input wire [6:0] scan_key,scan_value,
 input wire mapped_valid,input wire [3:0] mapped_kind,
 input wire [6:0] mapped_key,input wire [1:0] octave_group,
 input wire [31:0] active,input wire signed [15:0] piano_pcm,
 output reg [6:0] last_key,last_velocity,last_mapped,
 output reg [1:0] last_group,
 output reg [31:0] active_seen,
 output reg [15:0] peak,raw_count,note_count
);
 reg have_note;
 wire [15:0] magnitude=piano_pcm[15]?(~piano_pcm+16'd1):piano_pcm;
 always @(posedge clk)begin
  if(!rst_n)begin
   last_key<=127;last_velocity<=0;last_mapped<=127;last_group<=2;
   active_seen<=0;peak<=0;raw_count<=0;note_count<=0;have_note<=0;
  end else begin
   if(raw_press)raw_count<=raw_count+1'b1;
   if(have_note)begin
    active_seen<=active_seen|active;
    if(sample_tick&&magnitude>peak)peak<=magnitude;
   end
   if(scan_valid&&scan_kind==9)begin
    last_key<=scan_key;last_velocity<=scan_value;last_group<=octave_group;
    last_mapped<=127;active_seen<=0;peak<=0;have_note<=1;
    note_count<=note_count+1'b1;
   end
   if(mapped_valid&&mapped_kind==9)last_mapped<=mapped_key;
  end
 end
endmodule
