// B-board practice and sound laboratory. Piano keys are reported by A;
// B synthesizes drums and returns PCM to A's final mix and recording path.
module studio_extra_control #(parameter integer CLK_HZ=50000000)(
 input wire clk,rst_n,alive,input wire [2:0] base_page,input wire [1:0] octave_group,
 input wire [31:0] piano_keys,input wire [273:0] touch,output wire [273:0] touch_to_a,
 output reg [1:0] mode,game_state,output reg [15:0] elapsed_ms,expected_ms,score,
 output reg [7:0] hits,misses,wrong,perfects,combo,max_combo,
 output reg [5:0] index,output reg [7:0] pending,output reg [2:0] song,output wire cal_recent,
 output reg game_menu,game_complete,output reg [2:0] judgement,
 output reg [15:0] beat_phase_ms,output reg [7:0] beat_index,
 output wire [2:0] count_in,output reg beat_pulse,output wire [7:0] practice_bpm,
 output reg [1:0] test_mode
);
 `include "src/studio_game_songs.vh"
 localparam IDLE=0,PLAY=1,PAUSE=2,DONE=3;
 localparam integer MS_DIV=CLK_HZ/1000;
 localparam integer CW=($clog2(MS_DIV)<1)?1:$clog2(MS_DIV);
 reg [CW-1:0] divider=0;
 wire ms_tick=divider==MS_DIV-1;
 wire down=|touch[9:0];
 wire [9:0] tx=touch[19:10],ty=touch[119:110];
 reg was_down=0,holdoff=0;
 reg [10:0] cal_timer=0;
 reg [8:0] judge_timer=0;
 reg [15:0] next_beat_ms=0;
 reg event_perfect=1,event_clean=1,last_closed=0;
 assign cal_recent=cal_timer!=0;
 assign practice_bpm=game_bpm(song);
 assign count_in=game_state==PLAY&&beat_index<4?(3'd4-beat_index[2:0]):3'd0;
 wire fresh=down&&!was_down;
 wire entry_zone=base_page==2&&ty<60&&tx>=170&&tx<285;
 // Page 3 removes this contact individually below, preserving a second
 // finger on a recording control. Other pages keep their existing behavior.
 wire hidden_info_zone=mode!=1&&!(mode==0&&base_page==3)&&ty>=14&&ty<58&&tx>=966;
 wire suppress=(mode==1)||holdoff||(down&&(entry_zone||hidden_info_zone));
 // B-only proxy adjustments. Preserve the external payload, IDs and every
 // unrelated contact; page 3 retains its original forwarding behavior.
 reg [273:0] mapped_touch;integer contact;
 always @*begin
  mapped_touch=touch;
  for(contact=0;contact<10;contact=contact+1)begin
   // Local spectral controls never enter A's touch-command stream. Keep
   // page 3 and every unrelated contact bit-for-bit compatible with D203.
   if(mode==2&&base_page==4&&touch[contact]&&
      touch[110+contact*10+:10]>=14&&touch[110+contact*10+:10]<58&&
      ((touch[10+contact*10+:10]>=360&&touch[10+contact*10+:10]<500)||
       (touch[10+contact*10+:10]>=510&&touch[10+contact*10+:10]<650)||
       (touch[10+contact*10+:10]>=660&&touch[10+contact*10+:10]<800)||
       (touch[10+contact*10+:10]>=810&&touch[10+contact*10+:10]<950)))
    mapped_touch[contact]=0;
   // Remove the hidden legacy Lissajous-delay command with its old hitbox.
   if(mode==0&&base_page==0&&touch[contact]&&
      touch[10+contact*10+:10]>=311&&touch[10+contact*10+:10]<367&&
      touch[110+contact*10+:10]>=89&&touch[110+contact*10+:10]<133)
    mapped_touch[contact]=0;
   // Every pixel of the complete calibration button maps to A's existing
   // command hitbox. Preserve contact IDs, other contacts and packet layout.
   if(mode==0&&base_page==5&&touch[contact]&&
      touch[10+contact*10+:10]>=171&&touch[10+contact*10+:10]<284&&
      touch[110+contact*10+:10]>=145&&touch[110+contact*10+:10]<190)begin
    mapped_touch[10+contact*10+:10]=10'd220;
    mapped_touch[110+contact*10+:10]=10'd166;
   end
   // The removed information icon has no remaining touch command, including
   // when it is a second contact beside another control.
   if(mode==0&&base_page==3&&touch[contact]&&
      touch[10+contact*10+:10]>=966&&
      touch[110+contact*10+:10]>=14&&touch[110+contact*10+:10]<58)
    mapped_touch[contact]=0;
  end
 end
 assign touch_to_a=suppress?{mapped_touch[273:10],10'd0}:mapped_touch;
 // Select a named level on a new contact; holding or dragging cannot cycle it.
 // Leaving the laboratory, loss of the peer, and reset all return to music.
 reg [9:0] test_previous_down=0;integer test_contact,cal_contact;
 always @(posedge clk)begin
  if(!rst_n)begin test_mode<=0;test_previous_down<=0;end
  else begin
   test_previous_down<=touch[9:0];
   if(!alive||base_page!=4||mode!=2)test_mode<=0;
   else for(test_contact=0;test_contact<10;test_contact=test_contact+1)
    if(touch[test_contact]&&!test_previous_down[test_contact]&&
       touch[110+test_contact*10+:10]>=14&&touch[110+test_contact*10+:10]<58)begin
     if(touch[10+test_contact*10+:10]>=360&&touch[10+test_contact*10+:10]<500)test_mode<=0;
     else if(touch[10+test_contact*10+:10]>=510&&touch[10+test_contact*10+:10]<650)test_mode<=1;
     else if(touch[10+test_contact*10+:10]>=660&&touch[10+test_contact*10+:10]<800)test_mode<=2;
     else if(touch[10+test_contact*10+:10]>=810&&touch[10+test_contact*10+:10]<950)test_mode<=3;
    end
  end
 end
 // C4 D4 E4 F4 G4 A4 B4 C5, using the original default mapping.
 wire [7:0] keys={piano_keys[19],piano_keys[18],piano_keys[16],piano_keys[14],
                  piano_keys[12],piano_keys[11],piano_keys[9],piano_keys[7]};
 reg [7:0] previous_keys=0;
 wire [7:0] strikes=keys&~previous_keys;
 wire [7:0] window_ms=game_window_ms(song,index);
 wire [16:0] elapsed_ext={1'b0,elapsed_ms},expected_ext={1'b0,expected_ms};
 wire time_window=beat_index>=4&&elapsed_ext+window_ms>=expected_ext&&elapsed_ext<=expected_ext+window_ms;
 wire perfect=elapsed_ext+17'd90>=expected_ext&&elapsed_ext<=expected_ext+17'd90;
 wire [7:0] matched=time_window?(strikes&pending):8'd0;
 wire [7:0] remaining=pending&~matched;
 wire hit=(pending!=0)&&(|matched)&&(remaining==0);
 wire [7:0] wrong_keys=time_window?(strikes&~pending):strikes;
 wire perfect_hit=perfect&&event_perfect&&event_clean&&wrong_keys==0;
 wire [2:0] chosen_song=ty<174?0:ty<218?1:ty<262?2:ty<306?3:ty<350?4:ty<394?5:ty<438?6:7;
 function [3:0] count8(input [7:0] a);
  integer i;begin count8=0;for(i=0;i<8;i=i+1)count8=count8+a[i];end
 endfunction
 function [7:0] sat8_add(input [7:0] value,input [3:0] amount);
  reg [8:0] total;begin total={1'b0,value}+amount;sat8_add=total[8]?8'hff:total[7:0];end
 endfunction
 always @(posedge clk)begin
  if(!rst_n)begin
   divider<=0;mode<=0;game_state<=IDLE;elapsed_ms<=0;expected_ms<=game_onset_ms(0,0);score<=0;
   hits<=0;misses<=0;wrong<=0;perfects<=0;combo<=0;max_combo<=0;index<=0;pending<=0;song<=0;
   was_down<=0;holdoff<=0;previous_keys<=0;cal_timer<=0;game_menu<=0;game_complete<=0;judgement<=0;judge_timer<=0;
   beat_phase_ms<=0;beat_index<=0;beat_pulse<=0;next_beat_ms<=game_beat_time_ms(0,1);
   event_perfect<=1;event_clean<=1;last_closed<=0;
  end else begin
   beat_pulse<=0;
   if(ms_tick)divider<=0;else divider<=divider+1'b1;
   if(ms_tick&&cal_timer!=0)cal_timer<=cal_timer-1'b1;
   if(ms_tick&&judge_timer!=0)begin judge_timer<=judge_timer-1'b1;if(judge_timer==1)judgement<=0;end
   if(mode==0&&base_page==5)for(cal_contact=0;cal_contact<10;cal_contact=cal_contact+1)
    if(touch[cal_contact]&&!test_previous_down[cal_contact]&&
       touch[10+cal_contact*10+:10]>=171&&touch[10+cal_contact*10+:10]<284&&
       touch[110+cal_contact*10+:10]>=145&&touch[110+cal_contact*10+:10]<190)cal_timer<=1200;
   was_down<=down;previous_keys<=keys;
   if(!down)holdoff<=0;
   if(mode!=1)begin if(base_page==4)mode<=2;else mode<=0;end
   if(fresh)begin
    if(mode==0&&entry_zone)begin mode<=1;holdoff<=1;game_state<=IDLE;game_menu<=0;end
    else if(mode==1&&ty<60&&tx>=286&&tx<400)begin mode<=0;holdoff<=1;game_state<=IDLE;game_menu<=0;end
    else if(mode==1&&game_menu)begin
     game_menu<=0;
     if(tx>=470&&tx<688&&ty>=130&&ty<482)begin
      song<=chosen_song;
      game_state<=IDLE;game_complete<=0;elapsed_ms<=0;expected_ms<=game_onset_ms(chosen_song,0);score<=0;hits<=0;misses<=0;
      wrong<=0;perfects<=0;combo<=0;max_combo<=0;index<=0;pending<=0;judgement<=0;
      beat_phase_ms<=0;beat_index<=0;next_beat_ms<=game_beat_time_ms(chosen_song,1);
      event_perfect<=1;event_clean<=1;last_closed<=0;
     end
    end else if(mode==1&&tx>=523&&tx<679&&ty>=92&&ty<124&&game_state!=PLAY)game_menu<=1;
    else if(mode==1&&ty>=349&&ty<391)begin
     if(tx>=824&&tx<900)begin if(game_state==PLAY)game_state<=PAUSE;else if(game_state==PAUSE)game_state<=PLAY;end
     else if(tx>=905&&tx<981&&(game_state==PLAY||game_state==PAUSE))begin game_state<=DONE;game_complete<=0;end
     else if(tx>=735&&tx<819&&game_state!=PLAY&&game_state!=PAUSE&&alive&&octave_group==2)begin
      elapsed_ms<=0;expected_ms<=game_onset_ms(song,0);score<=0;hits<=0;misses<=0;wrong<=0;perfects<=0;
      combo<=0;max_combo<=0;index<=0;pending<=game_pattern(song,0);game_state<=PLAY;game_complete<=0;judgement<=0;
      beat_phase_ms<=0;beat_index<=0;beat_pulse<=1;next_beat_ms<=game_beat_time_ms(song,1);
      event_perfect<=1;event_clean<=1;last_closed<=0;
     end
    end
   end
   if(mode==1&&game_state==PLAY)begin
    if(!alive||octave_group!=2)game_state<=PAUSE;
    else begin
     if(ms_tick)begin
      elapsed_ms<=elapsed_ms+1'b1;
      if(elapsed_ext+17'd1>={1'b0,next_beat_ms})begin
       beat_index<=beat_index+1'b1;beat_phase_ms<=0;beat_pulse<=1;
       next_beat_ms<=game_beat_time_ms(song,beat_index+8'd2);
      end else beat_phase_ms<=beat_phase_ms+1'b1;
     end
     // Partial chord presses accumulate, but only the complete target scores.
     if(|matched)begin pending<=remaining;if(!perfect)event_perfect<=0;end
     if(hit)begin
      pending<=0;hits<=sat8_add(hits,1);combo<=sat8_add(combo,1);
      if(sat8_add(combo,1)>max_combo)max_combo<=sat8_add(combo,1);
      if(perfect_hit)perfects<=sat8_add(perfects,1);
      judgement<=perfect_hit?1:2;judge_timer<=300;
      score<=score+(perfect_hit?16'd100:16'd60);
     end
     // Four preparation beats are unscored; wrong keys thereafter are counted.
     if(beat_index>=4&&|wrong_keys)begin
      wrong<=sat8_add(wrong,count8(wrong_keys));combo<=0;judgement<=3;judge_timer<=300;event_clean<=0;
     end
     if(ms_tick&&elapsed_ext>=expected_ext+window_ms&&!last_closed)begin
      if(remaining!=0)begin misses<=sat8_add(misses,1);combo<=0;judgement<=4;judge_timer<=300;end
      if(index+1'b1>=game_length(song))begin pending<=0;last_closed<=1;end
      else begin
       index<=index+1'b1;expected_ms<=game_onset_ms(song,index+1'b1);
       pending<=game_pattern(song,index+1'b1);event_perfect<=1;event_clean<=1;
      end
     end
     // Finish after the final note's written duration, not just its hit window.
     if(ms_tick&&elapsed_ext+17'd1>={1'b0,game_end_ms(song)})begin
      game_state<=DONE;pending<=0;game_complete<=1;
     end
    end
   end
  end
 end
endmodule
