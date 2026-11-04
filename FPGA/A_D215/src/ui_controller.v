`timescale 1ns/1ps
module ui_controller(
 input wire clk,rst_n,touch_update,
 input wire [9:0] contact_down,
 input wire [99:0] contact_x,contact_y,
 input wire [59:0] contact_id,
 output reg [2:0] page, output reg plot,octave_high,
 output reg [6:0] volume, output reg panic,
 output wire note_valid, input wire note_ready,
 output wire [3:0] note_kind, output wire [6:0] note_key,note_value,
 output reg [31:0] desired_notes,
 output reg [3:0] touch_count
);
 `include "src/ui_layout.vh"
 `include "src/ui_math.vh"
 // Load, decode and apply each contact separately. A report is committed
 // atomically after 43 clocks (<0.9 us), well before the next USB poll.
 reg [2:0] state=0;
 reg [3:0] slot;
 reg [9:0] downs;
 reg [99:0] xs,ys;
 reg [59:0] ids;
 reg [63:0] previous_ids,current_ids;
 reg inhibit_until_release,volume_capture;
 reg [5:0] volume_owner;
 reg [31:0] sent_notes;
 reg [2:0] work_page,next_page;
 reg work_plot,work_octave,work_inhibit,work_capture,work_panic;
 reg next_plot,next_octave,next_capture,next_panic;
 reg [6:0] work_volume,next_volume;
 reg [5:0] work_owner,next_owner;
 reg [31:0] work_notes,next_notes;
 reg [3:0] work_count;
 wire [5:0] slot_id=ids[slot*6 +:6];
 reg [9:0] tx,ty;
 reg [5:0] cid;
 reg contact_pressed;
 reg [4:0] key_index;
 always @* begin
  next_page=work_page;next_plot=work_plot;next_octave=work_octave;
  next_volume=work_volume;next_capture=work_capture;next_owner=work_owner;
  next_panic=work_panic;next_notes=work_notes;
  if(contact_pressed) begin
   if(!previous_ids[cid]) begin
    if(tx>=8 && tx<71) begin
     if(ty>=106 && ty<171) next_page=0;
     else if(ty>=179 && ty<244) next_page=1;
     else if(ty>=252 && ty<317) next_page=2;
     else if(ty>=325 && ty<390) next_page=3;
     else if(ty>=398 && ty<463) next_page=4;
    end else if(page==0) begin
     if(ty>=241 && ty<277 && tx>=121 && tx<151) next_plot=0;
     if(ty>=241 && ty<277 && tx>=161 && tx<191) next_plot=1;
     if(ty>=401 && ty<433 && tx>=543 && tx<577) next_octave=0;
     if(ty>=401 && ty<433 && tx>=627 && tx<661) next_octave=1;
     if(ty>=484 && ty<530 && tx>=893 && tx<981) next_panic=1;
     if(ty>=180 && ty<218 && tx>=701 && tx<991 && !work_capture) begin
      next_capture=1;next_owner=cid;
     end
    end
   end
   if(page==0 && next_capture && cid==next_owner) begin
    next_volume=ui_slider_volume(tx);
   end
   if(page==0 && !(next_capture && cid==next_owner) && key_index<13)
    next_notes[7+key_index+(octave_high ? 12 : 0)]=1;
  end
 end
 always @(posedge clk) begin
  panic<=0;
  if(!rst_n) begin
   state<=0;slot<=0;downs<=0;xs<=0;ys<=0;ids<=0;
   tx<=0;ty<=0;cid<=0;contact_pressed<=0;key_index<=31;
   page<=0;plot<=0;octave_high<=0;volume<=127;previous_ids<=0;current_ids<=0;
   inhibit_until_release<=0;volume_capture<=0;volume_owner<=0;
   desired_notes<=0;touch_count<=0;
   work_page<=0;work_plot<=0;work_octave<=0;work_volume<=127;
   work_owner<=0;work_capture<=0;work_panic<=0;work_inhibit<=0;work_notes<=0;work_count<=0;
  end else case(state)
   0:if(touch_update) begin
    downs<=contact_down;xs<=contact_x;ys<=contact_y;ids<=contact_id;
    slot<=0;current_ids<=0;work_count<=0;state<=1;
   end
   1:begin
    if(downs[slot]) begin current_ids[slot_id]<=1;work_count<=work_count+1'b1;end
    if(slot==9)state<=2;else slot<=slot+1'b1;
   end
   2:begin
    work_page<=page;work_plot<=plot;work_octave<=octave_high;work_volume<=volume;
    work_capture<=volume_capture && current_ids[volume_owner];work_owner<=volume_owner;
    work_inhibit<=inhibit_until_release && downs!=0;work_panic<=0;work_notes<=0;
    slot<=0;state<=5;
   end
   3:begin
    work_page<=next_page;work_plot<=next_plot;work_octave<=next_octave;
    work_volume<=next_volume;work_capture<=next_capture;work_owner<=next_owner;
    work_panic<=next_panic;work_notes<=next_notes;
    if(slot==9)state<=4;else begin slot<=slot+1'b1;state<=5;end
   end
   5:begin
    tx<=xs[slot*10 +:10];ty<=ys[slot*10 +:10];cid<=slot_id;
    contact_pressed<=downs[slot];state<=6;
   end
   6:begin key_index<=ui_key_at(tx,ty);state<=3;end
   4:begin
    page<=work_page;plot<=work_plot;octave_high<=work_octave;
    // Mute has priority over the captured slider regardless of contact order.
    volume<=work_panic ? 7'd0 : work_volume;panic<=work_panic;
    volume_capture<=work_capture && !work_panic;volume_owner<=work_owner;
    previous_ids<=current_ids;touch_count<=work_count;
    inhibit_until_release<=work_inhibit || work_panic || work_page!=page || work_octave!=octave_high;
    desired_notes<=(work_inhibit || work_panic || work_page!=page || work_octave!=octave_high || work_page!=0)
                   ? 32'b0 : work_notes;
    state<=0;
   end
   default:state<=0;
  endcase
 end
 reg found,send_on;
 reg [4:0] send_index;
 integer n;
 always @* begin
  found=0;send_on=0;send_index=0;
  // Release all obsolete notes before adding notes, including octave/page changes.
  for(n=0;n<32;n=n+1) if(!found && sent_notes[n] && !desired_notes[n]) begin
   found=1;send_index=n;send_on=0;
  end
  for(n=0;n<32;n=n+1) if(!found && !sent_notes[n] && desired_notes[n]) begin
   found=1;send_index=n;send_on=1;
  end
 end
 // Register the selected event before ownership merging and voice decoding.
 // A target commit cancels an unsent event and selection resumes from the
 // new atomic target on the next clock. Physical MIDI still has priority.
 reg queued_valid,queued_on;
 reg [4:0] queued_index;
 reg [6:0] queued_key;
 assign note_valid=queued_valid && rst_n && !panic && state!=4;
 assign note_kind=queued_on ? 4'h9 : 4'h8;
 assign note_key=queued_key;
 assign note_value=queued_on ? 7'd100 : 7'd0;
 always @(posedge clk) begin
  if(!rst_n || panic) begin
   sent_notes<=0;queued_valid<=0;queued_on<=0;queued_index<=0;queued_key<=0;
  end else if(state==4) queued_valid<=0;
  else if(note_valid && note_ready) begin
   sent_notes[queued_index]<=queued_on;queued_valid<=0;
  end else if(!queued_valid && found) begin
   queued_valid<=1;queued_on<=send_on;queued_index<=send_index;queued_key<=7'd41+send_index;
  end
 end
endmodule
