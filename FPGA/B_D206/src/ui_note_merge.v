`timescale 1ns/1ps
// Physical MIDI keeps its original cycle and priority. Touch events use a
// ready/valid handshake, so a simultaneous physical message never drops them.
// Separate ownership masks stop one input releasing the other's held note.
module ui_note_merge #(parameter [3:0] MIDI_CHANNEL_ZERO=4'd0)(
 input wire clk,rst_n,panic,clear_owners,
 input wire physical_valid, input wire [3:0] physical_kind,physical_channel,
 input wire [6:0] physical_key,physical_value,
 input wire touch_valid, input wire [3:0] touch_kind,
 input wire [6:0] touch_key,touch_value, output wire touch_ready,
 output wire event_valid, output wire [3:0] event_kind,channel_zero,
 output wire [6:0] key_or_cc,value
);
 reg [127:0] physical_held,touch_held;
 wire take_touch=!physical_valid && touch_valid;
 assign touch_ready=!physical_valid && !panic && !clear_owners && rst_n;
 wire off_physical=physical_channel==MIDI_CHANNEL_ZERO &&
     (physical_kind==8 || (physical_kind==9 && physical_value==0));
 wire off_touch=touch_kind==8 || (touch_kind==9 && touch_value==0);
 wire suppress=physical_valid ? (off_physical && touch_held[physical_key]) :
                               (off_touch && physical_held[touch_key]);
 assign event_valid=panic || ((physical_valid || take_touch) && !suppress);
 assign event_kind=panic ? 4'hb : physical_valid ? physical_kind : touch_kind;
 assign channel_zero=panic ? MIDI_CHANNEL_ZERO : physical_valid ? physical_channel : MIDI_CHANNEL_ZERO;
 assign key_or_cc=panic ? 7'd120 : physical_valid ? physical_key : touch_key;
 assign value=panic ? 7'd0 : physical_valid ? physical_value : touch_value;
 always @(posedge clk) begin
  if(!rst_n || panic || clear_owners) begin physical_held<=0;touch_held<=0;end
  else begin
   if(physical_valid && physical_channel==MIDI_CHANNEL_ZERO) begin
    if(physical_kind==9 && physical_value!=0) physical_held[physical_key]<=1;
    else if(off_physical) physical_held[physical_key]<=0;
    else if(physical_kind==11 && (physical_key==120 || physical_key==123)) begin
     physical_held<=0;touch_held<=0;
    end
   end
   if(touch_valid && touch_ready) touch_held[touch_key]<=!off_touch;
  end
 end
endmodule
