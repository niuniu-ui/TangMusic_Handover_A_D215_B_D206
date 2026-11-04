`timescale 1ns/1ps
module instrument_guide #(parameter integer PHASE_LIMIT=46875000)(
 input wire clk,rst_n,input wire [2:0] page,input wire [1:0] octave_group,
 input wire [2:0] action,input wire [1:0] argument,input wire menu_open,
 input wire [31:0] keys_down,key_strike,
 output reg [1:0] piece,status,output reg tempo_mode,output reg [7:0] bpm,
 output reg [5:0] step_index,output wire [5:0] total_steps,
 output reg signed [15:0] position,
 output reg [6:0] correct,missed,errors,output reg [1:0] feedback,
 output wire blocked,output wire [31:0] target_keys,
 output reg [319:0] bars,output reg [63:0] cues,output reg [6:0] progress_percent
);
 `include "src/guide_song_rom.vh"
 reg [25:0] phase;
 wire [26:0] phase_sum={1'b0,phase}+bpm;
 wire subbeat=phase_sum>=PHASE_LIMIT;
 reg [31:0] old_keys;wire [31:0] presses=(keys_down&~old_keys)|key_strike;
 reg [2:0] old_page;reg [1:0] old_group;
 reg key_hit,scored;reg [41:0] hit_bits,miss_bits;
 reg [15:0] ms_count;reg [9:0] feedback_ms;
 wire [31:0] event_now=guide_event(piece,step_index),event_next=guide_event(piece,step_index+1'b1);
 wire [11:0] onset=event_now[30:19];wire [7:0] duration=event_now[18:11];
 wire [4:0] key=event_now[4:0];wire key_valid=event_now[5];
 wire [31:0] wanted_keys=key_valid?(32'b1<<key):0;
 wire at_line=step_index<total_steps && (page==5 ?
  (tempo_mode ? position>=$signed({4'b0,onset})-$signed({10'b0,guide_window(bpm)}) && position<=$signed({4'b0,onset})+$signed({10'b0,guide_window(bpm)}):position>=$signed({4'b0,onset})) : 1'b1);
 wire key_ok=!key_valid||((key_hit||presses[key])&&keys_down[key]);
 // Two compact hint bits travel with the current cue through the frame mailbox.
 wire [1:0] cue_hint=status!=1||tempo_mode||!at_line||blocked?0:
  key_valid&&keys_down[key]&&!key_hit&&!presses[key]?1:0;
 wire any_press=|presses;
 wire expired=tempo_mode&&step_index<total_steps&&
  (page==5 ? position>$signed({4'b0,onset})+$signed({10'b0,guide_window(bpm)}):position>=$signed({4'b0,onset})+$signed({8'b0,duration}));
 assign blocked=octave_group!=2;
 assign total_steps=guide_length(piece);
 assign target_keys=(!blocked&&status!=3&&(page!=5||at_line))?wanted_keys:0;
 function [6:0] inc;input [6:0] n;begin inc=n==127?127:n+1'b1;end endfunction
 task reset_transport;
 begin status<=0;step_index<=0;position<=page==5?-16'sd128:16'sd0;phase<=0;correct<=0;missed<=0;errors<=0;feedback<=0;feedback_ms<=0;key_hit<=0;scored<=0;hit_bits<=0;miss_bits<=0;end
 endtask
 always @(posedge clk)begin
  old_keys<=keys_down;old_page<=page;old_group<=octave_group;
  if(!rst_n)begin
   piece<=0;tempo_mode<=0;bpm<=80;old_keys<=0;old_page<=0;old_group<=2;ms_count<=0;reset_transport();
  end else begin
   if(ms_count==49999)begin ms_count<=0;if(feedback_ms!=0)feedback_ms<=feedback_ms-1'b1;else feedback<=0;end else ms_count<=ms_count+1'b1;
   if(status==1&&!menu_open&&(page==2||page==5)&&!blocked)begin
    phase<=subbeat?phase_sum-PHASE_LIMIT:phase_sum[25:0];
    if(subbeat&&(tempo_mode||step_index==total_steps||(page==5&&position<$signed({4'b0,onset}))))position<=position+1'b1;
    if(expired)begin
     if(!scored)begin missed<=inc(missed);miss_bits[step_index]<=1;end
     step_index<=step_index+1'b1;key_hit<=0;scored<=0;
    end else if(any_press&&step_index<total_steps&&!scored)begin
     if(!at_line)begin feedback<=3;feedback_ms<=750;end
     else begin
      if(|(presses&~wanted_keys))begin errors<=inc(errors);feedback<=2;feedback_ms<=750;end
      if(key_valid&&presses[key])key_hit<=1;
      if(key_ok)begin
       correct<=inc(correct);feedback<=1;feedback_ms<=750;hit_bits[step_index]<=1;
       if(!tempo_mode||page==5)begin
        step_index<=step_index+1'b1;key_hit<=0;
        if(page!=5&&!tempo_mode)begin
         position<=$signed({4'b0,event_next[30:19]});
         if(step_index+1'b1==total_steps)begin status<=3;position<=$signed({3'b0,guide_end(piece)});end
        end
       end else scored<=1;
      end
     end
    end
    if(step_index>=total_steps&&position>=$signed({3'b0,guide_end(piece)}))begin status<=3;position<=$signed({3'b0,guide_end(piece)});end
   end
   if((page!=2&&page!=5)||menu_open)begin if(status==1)status<=2;key_hit<=0;end
   if(page!=old_page&&(page==5||old_page==5))reset_transport();
   if(octave_group!=old_group)reset_transport();
   case(action)
    1:if(!blocked)begin
      if(status==1)status<=2;
      else if(status==3)begin reset_transport();status<=1;end
      else status<=1;
      key_hit<=0;
    end
    2:reset_transport();
    3:begin piece<=argument<2?argument:0;reset_transport();end
    4:if(tempo_mode!=argument[0])begin tempo_mode<=argument[0];reset_transport();end
    5:if(bpm>40)bpm<=bpm-5;
    6:if(bpm<160)bpm<=bpm+5;
    default:begin end
   endcase
  end
 end
 // Ten lookahead rectangles are built using one ROM/multiplier datapath.
 // The complete set is published together, never half-updated per frame.
 reg [3:0] slot;
 reg [5:0] base_index;reg [1:0] base_piece;reg signed [15:0] base_position;
 reg base_blocked;reg [41:0] base_hits,base_misses;reg [319:0] pending_bars;
 reg [63:0] pending_cues;
 wire [6:0] look_index={1'b0,base_index}+slot-7'd2;
 wire [31:0] look_event=guide_event(base_piece,look_index[5:0]);
 wire look_valid=!look_index[6]&&look_index<guide_length(base_piece)&&look_event[5]&&!base_blocked;
 wire signed [16:0] distance=$signed({5'b0,look_event[30:19]})-$signed({base_position[15],base_position});
 wire signed [26:0] scaled_distance=distance*17'sd318;
 wire signed [26:0] local_bottom=27'sd318-(scaled_distance>>>9);
 // The local score format currently contains only one- and two-beat notes.
 // Exact floor((duration-8)*318/512), without a multiplier/packed CDC flop.
 wire [7:0] height=look_event[18:11]==128?8'd74:look_event[18:11]==64?8'd34:8'd0;
 wire [1:0] result=look_index<42?(base_hits[look_index]?1:base_misses[look_index]?2:0):0;
 wire [31:0] look_word={5'b0,result,height,local_bottom[10:0],look_valid&&local_bottom>-256&&local_bottom<574,look_event[4:0]};
 wire [31:0] cue_event=guide_event(base_piece,base_index+slot-1'b1);
 reg [18:0] progress_scaled;
 always @(posedge clk)begin
  if(!rst_n)begin slot<=0;bars<=0;cues<=0;pending_bars<=0;pending_cues<=0;progress_percent<=0;progress_scaled<=0;base_index<=0;base_piece<=0;base_position<=0;base_blocked<=0;base_hits<=0;base_misses<=0;end
  else if(slot==0)begin
   base_index<=step_index;base_piece<=piece;base_position<=position;base_blocked<=blocked;base_hits<=hit_bits;base_misses<=miss_bits;slot<=1;pending_cues<=0;
   progress_scaled<=position<0?0:position*7'd100;
   progress_percent<=status==3?100:(piece==0?progress_scaled/3072:progress_scaled/1024);
  end else begin
   // slot 1 is the previous event; slot 2 is the current event.
   pending_bars[(slot-1)*32+:32]<=look_word;
   if(slot<=4)pending_cues[(slot-1)*16+:16]<=base_index+slot-1<guide_length(base_piece)?{1'b1,2'b0,slot==1?cue_hint:2'b0,cue_event[10:0]}:0;
   if(slot==10)begin bars<={look_word,pending_bars[287:0]};cues<=pending_cues;slot<=0;end else slot<=slot+1'b1;
  end
 end
endmodule
