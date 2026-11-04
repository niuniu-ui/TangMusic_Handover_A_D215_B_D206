`timescale 1ns/1ps
module studio_renderer #(parameter ARTWORK_DDR=1)(
 input wire host_clk,host_rst_n,ui_mem_ready,ui_mem_done,ui_mem_error,input wire [255:0] ui_mem_read_data,
 output wire ui_mem_request,ui_mem_write,output wire [28:0] ui_mem_address,output wire [255:0] ui_mem_write_data,
 input wire [255:0] studio_state,
 input wire [1:0] extra_mode,extra_game_state,extra_octave,
 input wire extra_game_menu,extra_game_complete,input wire [2:0] extra_judgement,input wire [7:0] extra_drum_voices,
 input wire [7:0] extra_drum_peak,input wire [15:0] extra_beat_phase,
 input wire [7:0] extra_beat_index,extra_practice_bpm,input wire [2:0] extra_count_in,
 input wire [1:0] extra_test_mode,input wire [7:0] extra_component_count,
 input wire [12:0] extra_design_kosc,
 input wire extra_alive,extra_fft_overflow,extra_cal_recent,
 input wire [6:0] extra_voice_count,
 input wire [15:0] extra_elapsed,extra_expected,extra_score,
 input wire [7:0] extra_hits,extra_misses,extra_wrong,extra_perfects,extra_combo,
 input wire [5:0] extra_index,input wire [7:0] extra_pending,input wire [2:0] extra_song,
 input wire [127:0] extra_fft,
 input wire pixel_clk,reset,flute_suona,input wire [2:0] page,input wire [1:0] octave_group,
 input wire [6:0] master_percent,piano_percent,
 input wire [3:0] touch_count,input wire [6:0] voice_count,
 input wire [31:0] keys_down,
 input wire [3:0] usb_status,input wire [127:0] spectrum,
 input wire [9:0] contact_down,input wire [99:0] contact_x,contact_y,
 input wire [1:0] piece,status,feedback,input wire tempo_mode,blocked,menu_open,
 input wire [7:0] bpm,input wire [5:0] step_index,total_steps,
 input wire signed [15:0] position,input wire [6:0] correct,missed,errors,progress_percent,
 input wire [31:0] target_keys,
 input wire [319:0] bars,input wire [63:0] cues,
 input wire [10:0] x,input wire [9:0] y,input wire de,hs,vs,
 input wire [15:0] scope_pair,
 input wire muted,lissa_run,lissa_pixel,input wire [1:0] lissa_delay,
 input wire [2:0] fx_enabled,input wire [62:0] fx_values,
 output reg [23:0] rgb,output reg out_de,out_hs,out_vs
) /* synthesis syn_romstyle="logic" */;
 `include "src/studio_keys.vh"
 `include "src/studio_text.vh"
 `include "src/ui_fx_math.vh"
 `include "src/studio_display_lookup.vh"
 localparam INK=24'h24464b,PAPER=24'hfafbf2,CYAN=24'hb9dce6,GREEN=24'hdce7cb,ORANGE=24'hefd0bb,VIOLET=24'he3daed;
 wire [3:0] rec_state=studio_state[3:0];wire [7:0] rec_fault=studio_state[11:4];
 wire selected=studio_state[12],lease=studio_state[13],saved=studio_state[14];
 wire link_up=studio_state[144],app_up=studio_state[145],drum_bank=studio_state[160];
 wire [6:0] drum_percent=studio_state[152:146],flute_percent=studio_state[159:153];
 wire [1:0] confirm=studio_state[162:161];wire about_open=studio_state[163];
 wire [7:0] seconds=studio_state[188:181];
 wire phone_score=studio_state[189];
 wire [4:0] scene=extra_mode==1?15:about_open?14:page==0?0:page==1?1+{3'd0,octave_group}:
  page==7?(flute_suona?6:5):page==5?(drum_bank?8:7):page==6?9:page==2?(piece==1?11:10):page==3?12:13;
 wire [23:0] art_raw;wire [10:0] ax_raw;wire [9:0] ay_raw;wire ad_raw,ah_raw,av_raw;
 reg [23:0] art;reg [10:0] ax;reg [9:0] ay;reg ad,ah,av;reg [5:0] key_hit;
 wire art_available_raw;wire [7:0] art_error;reg art_available;
 generate if(ARTWORK_DDR)begin:external_art
  studio_artwork_ddr artwork(.clk(pixel_clk),.reset(reset),.host_clk(host_clk),.host_rst_n(host_rst_n),.scene(scene),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),
   .rgb(art_raw),.px(ax_raw),.py(ay_raw),.out_de(ad_raw),.out_hs(ah_raw),.out_vs(av_raw),.available(art_available_raw),.error(art_error),
   .request(ui_mem_request),.write_request(ui_mem_write),.address(ui_mem_address),.write_data(ui_mem_write_data),
   .mem_ready(ui_mem_ready),.mem_done(ui_mem_done),.mem_error(ui_mem_error),.read_data(ui_mem_read_data),.underruns(),.boot_ready(),.boot_bytes());
 end else begin:rom_reference
  studio_artwork artwork(.clk(pixel_clk),.reset(reset),.scene(scene),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),
   .rgb(art_raw),.px(ax_raw),.py(ay_raw),.out_de(ad_raw),.out_hs(ah_raw),.out_vs(av_raw));
  assign art_available_raw=1'b1;assign art_error=0;
  assign ui_mem_request=0;assign ui_mem_write=0;assign ui_mem_address=0;assign ui_mem_write_data=0;
 end endgenerate

 wire [5:0] key_raw=studio_key(page,ax_raw[9:0],ay_raw);
 reg key_strip_take_raw,key_strip_take;
 reg [23:0] key_strip_color_raw,key_strip_color;
 reg [9:0] key_strip_top,key_strip_bottom;
 always @*begin
  key_strip_take_raw=0;key_strip_color_raw=PAPER;
  key_strip_top=page==1?409:323;key_strip_bottom=page==1?513:443;
  case(key_raw)1,3,5,8,10,13,15,17,20,22,25,27,29:key_strip_bottom=page==1?472:399;endcase
  if((page==1||page==2)&&key_raw<32&&(ay_raw<key_strip_top+5||ay_raw>=key_strip_bottom-5))begin
   if(keys_down[key_raw]&&(octave_group!=0||key_raw>=7))begin key_strip_take_raw=1;key_strip_color_raw=24'h82c4a1;end
   else if(page==2&&target_keys[key_raw]&&!blocked)begin key_strip_take_raw=1;key_strip_color_raw=24'hb9dce6;end
   if(page==2&&!phone_score&&feedback==2&&keys_down[key_raw]&&!target_keys[key_raw])begin key_strip_take_raw=1;key_strip_color_raw=24'hefad87;end
  end
 end
 always @(posedge pixel_clk)begin key_strip_take<=key_strip_take_raw;key_strip_color<=key_strip_color_raw;end
 reg [15:0] scope_delay[0:3];reg [3:0] lissa_delay_pipe;integer di;
 reg [10:0] fx_numbers[0:8];integer fx_i;reg [62:0] last_fx_values;
 reg [8:0] knob_offset[0:8];reg [7:0] mix_offset[0:3];reg [7:0] wave_a,wave_b;
 reg [10:0] mix_left[0:3],mix_right[0:3],knob_left[0:8],knob_right[0:8];integer mi;
 reg [23:0] plot_paint;reg spectrum_hit;integer bin;
 function [8:0] spectrum_bottom;input [3:0] level;begin case(level)
  0:spectrum_bottom=335;1:spectrum_bottom=330;2:spectrum_bottom=325;3:spectrum_bottom=320;
  4:spectrum_bottom=315;5:spectrum_bottom=310;6:spectrum_bottom=305;7:spectrum_bottom=300;
  8:spectrum_bottom=295;9:spectrum_bottom=290;10:spectrum_bottom=285;11:spectrum_bottom=280;
  12:spectrum_bottom=275;13:spectrum_bottom=270;14:spectrum_bottom=265;15:spectrum_bottom=260;
 endcase end endfunction
 always @*begin
  spectrum_hit=0;
  for(bin=0;bin<32;bin=bin+1)
   spectrum_hit=spectrum_hit||(ax_raw>=567+bin*13&&ax_raw<576+bin*13&&ax_raw<979&&ay_raw>=spectrum_bottom(spectrum[bin*4+:4]));
  plot_paint=art_raw;
  if(page==0&&!about_open)begin
   // Light axes stay behind the actual audio trajectory.
   if((ax_raw>=228&&ax_raw<230&&ay_raw>=145&&ay_raw<341)||
      (ax_raw>=124&&ax_raw<325&&ay_raw>=244&&ay_raw<246))plot_paint=24'h7aafb8;
   if(ax_raw>=132&&ax_raw<324&&ay_raw>=148&&ay_raw<340&&lissa_delay_pipe[2])plot_paint=24'h276b7b;
   if(ax_raw>=567&&ax_raw<979&&ay_raw>=93&&ay_raw<178&&
     ((ay_raw>=wave_a&&ay_raw<=wave_b)||(ay_raw>=wave_b&&ay_raw<=wave_a)))plot_paint=24'h397658;
   if(ay_raw>=251&&ay_raw<336&&spectrum_hit)plot_paint=24'h9a6d51;
  end
 end
 always @(posedge pixel_clk)begin
  art<=plot_paint;ax<=ax_raw;ay<=ay_raw;ad<=ad_raw;ah<=ah_raw;av<=av_raw;art_available<=art_available_raw;
  key_hit<=studio_key(page,ax_raw[9:0],ay_raw);
  scope_delay[0]<=scope_pair;for(di=1;di<4;di=di+1)scope_delay[di]<=scope_delay[di-1];
  lissa_delay_pipe<={lissa_delay_pipe[2:0],lissa_pixel};
  wave_a<=studio_wave_y(scope_delay[1][7:0]);wave_b<=studio_wave_y(scope_delay[1][15:8]);
  mix_offset[0]<=studio_master_offset(master_percent);mix_offset[1]<=studio_mix_offset(piano_percent);
  mix_offset[2]<=studio_mix_offset(drum_percent);mix_offset[3]<=studio_mix_offset(flute_percent);
  for(mi=0;mi<4;mi=mi+1)begin
   mix_left[mi]<=(mi==0?40:mi==1?334:mi==2?566:798)+mix_offset[mi]-3;
   mix_right[mi]<=(mi==0?40:mi==1?334:mi==2?566:798)+mix_offset[mi]+5;
  end
  for(mi=0;mi<9;mi=mi+1)begin
   knob_left[mi]<=(mi<3?45:mi<6?374:703)+knob_offset[mi]-4;
   knob_right[mi]<=(mi<3?45:mi<6?374:703)+knob_offset[mi]+5;
  end
  for(fx_i=0;fx_i<9;fx_i=fx_i+1)knob_offset[fx_i]<=studio_fx_offset(fx_values[fx_i*7+:7]);
  if(reset||last_fx_values!=fx_values)begin
   last_fx_values<=fx_values;
   for(fx_i=0;fx_i<9;fx_i=fx_i+1)fx_numbers[fx_i]<=fx_numeric(fx_i,fx_values[fx_i*7+:7]);
  end
 end
 reg [23:0] paint,ink;reg [7:0] glyph;
 wire extra_take_raw,extra_text_on_raw;
 wire [23:0] extra_color_raw,extra_ink_raw;
 wire [9:0] extra_left_raw,extra_top_raw;
 wire [6:0] extra_label_raw;wire [3:0] extra_kind_raw;
 wire [16:0] extra_number_raw;
 reg extra_take,extra_text_on;
 reg [23:0] extra_color,extra_ink;
 reg [9:0] extra_left,extra_top;
 reg [6:0] extra_label;reg [3:0] extra_kind;
 reg [16:0] extra_number;
 // Reuse the existing artwork alignment register: calculate extra geometry
 // one stage earlier, then register its fields alongside art/ax/ay. This
 // separates game/FFT geometry from the renderer's field priority mux without
 // adding latency or changing the pixel coordinate associated with a field.
 always @(posedge pixel_clk)begin
  extra_take<=extra_take_raw;extra_text_on<=extra_text_on_raw;
  extra_color<=extra_color_raw;extra_ink<=extra_ink_raw;
  extra_left<=extra_left_raw;extra_top<=extra_top_raw;
  extra_label<=extra_label_raw;extra_kind<=extra_kind_raw;extra_number<=extra_number_raw;
 end
 studio_extra_graphics extra_graphics(.x(ax_raw),.y(ay_raw),.page(page),.mode(extra_mode),
  .game_state(extra_game_state),.octave_group(extra_octave),.alive(extra_alive),
  .game_menu(extra_game_menu),.game_complete(extra_game_complete),.judgement(extra_judgement),.drum_voices(extra_drum_voices),.flute_active(studio_state[226]),
  .drum_peak(extra_drum_peak),.beat_phase(extra_beat_phase),.beat_index(extra_beat_index),.count_in(extra_count_in),.practice_bpm(extra_practice_bpm),
  .test_mode(extra_test_mode),.component_count(extra_component_count),.design_kosc(extra_design_kosc),
  .fft_overflow(extra_fft_overflow),.voice_count(extra_voice_count),.elapsed(extra_elapsed),
  .expected(extra_expected),.score(extra_score),.hits(extra_hits),.misses(extra_misses),
  .combo(extra_combo),.wrong(extra_wrong),.perfects(extra_perfects),.song(extra_song),.note_index(extra_index),.pending(extra_pending),.fft_levels(extra_fft),
  .take(extra_take_raw),.color(extra_color_raw),.ink(extra_ink_raw),.text_on(extra_text_on_raw),
  .left(extra_left_raw),.top(extra_top_raw),.label(extra_label_raw),.kind(extra_kind_raw),.number(extra_number_raw));
 integer left,top,label,kind,k,fc,fr,fxleft,value,cue,nn,wi,sp,field_x,field_y;
 reg [7:0] wa,wb;reg [5:0] column;reg [3:0] text_x;reg [9:0] text_dx;
 reg [16:0] number;
 reg text_on;reg [7:0] ascii;reg large_text;reg [1:0] font_scale;reg [9:0] font_dx,font_y;reg [5:0] key;reg [15:0] cue_word;
 reg [13:0] font_address_q;wire [15:0] font_word;
 reg [10:0] large_address_q;wire [15:0] large_word;reg use_large;
 reg [5:0] big_column,big_x,big_y;
 reg [23:0] paint_s,ink_s;reg text_on_s;reg [10:0] ax_s;reg [9:0] ay_s;
 reg [9:0] left_s,top_s;reg [6:0] label_s;reg [3:0] kind_s;reg [16:0] number_s;
 reg de_s,hs_s,vs_s;
 studio_font letters(.clk(pixel_clk),.addr(font_address_q),.data(font_word));
 studio_large_font large_letters(.clk(pixel_clk),.addr(large_address_q),.data(large_word));
 function [7:0] digit;input [16:0] n;begin digit=48+(n%10);end endfunction
 function [7:0] note_letter;input [6:0] n;begin case(n%12)
  0,1:note_letter="C";2,3:note_letter="D";4:note_letter="E";5,6:note_letter="F";7,8:note_letter="G";9,10:note_letter="A";default:note_letter="B";
 endcase end endfunction
 function sharp;input [6:0] n;begin sharp=n%12==1||n%12==3||n%12==6||n%12==8||n%12==10;end endfunction
 // One font lookup is shared by all text fields. The renderer is a fixed stream,
 // independent of DDR3 and recording bandwidth. All inputs are frame-atomic.
 always @* begin
  paint=art;ink=INK;text_on=0;left=0;top=0;label=0;number=0;kind=0;
  key=63;cue_word=0;value=0;cue=0;nn=0;wi=0;wa=0;wb=0;sp=0;fxleft=0;field_x=0;field_y=0;
  if(!about_open&&art_available&&extra_mode!=1)begin
   // Restore the same 24-pixel dotted canvas over the obsolete information
   // icon and its white patch on the interconnect page. No recording fields.
   if(page==3&&ax>=805&&ax<1001&&ay>=8&&ay<64)begin
    paint=24'hf3f3ec;
    if((ay==15||ay==16||ay==39||ay==40||ay==63)&&
       ((ax>=807&&ax<809)||(ax>=831&&ax<833)||(ax>=855&&ax<857)||
        (ax>=879&&ax<881)||(ax>=903&&ax<905)||(ax>=927&&ax<929)||
        (ax>=951&&ax<953)||(ax>=975&&ax<977)||(ax>=999&&ax<1001)))paint=24'hd1d9ce;
   end
   if(page==0)begin
    for(k=0;k<4;k=k+1)begin
     field_x=k==0?40:k==1?334:k==2?566:798;value=k==0?master_percent:k==1?piano_percent:k==2?drum_percent:flute_percent;
     wi=k==0?128:180;
     if(ax>=field_x&&ax<field_x+wi&&ay>=498&&ay<503)paint=k==0?24'he8f6df:24'h306777;
     if(ax>=mix_left[k]&&ax<mix_right[k]&&ay>=491&&ay<510)paint=k==0?24'he8f6df:24'h306777;
     field_x=k==0?226:k==1?466:k==2?698:930;
     if(ax>=field_x&&ax<field_x+64&&ay>=444&&ay<468)begin text_on=1;left=field_x;top=444;number=value;kind=1;ink=k==0?PAPER:INK;end
    end
    if(ax>=186&&ax<289&&ay>=478&&ay<522)begin
     paint=muted?24'ha75d49:24'h3a6870;
     if(ax>=202&&ax<282&&ay>=490&&ay<514)begin text_on=1;left=202;top=490;label=muted?23:22;kind=0;ink=PAPER;end
    end
    if(ax>=375&&ax<416&&ay>=90&&ay<132)begin paint=24'hdceef2;
     if(ax>=380&&ay>=99&&ay<123)begin text_on=1;left=380;top=99;label=lissa_run?36:37;kind=0;end
    end
   end
   if(key_strip_take)paint=key_strip_color;
   if(page==5&&ax>=171&&ax<284&&ay>=145&&ay<190)begin
    // Connection/centering flags are not a calibration-complete ACK.
    paint=extra_cal_recent?GREEN:24'hc5e1df;
    if(ax==171||ax==283||ay==145||ay==189)paint=24'h96b6b1;
    if(ax>=(extra_cal_recent?195:211)&&ax<276&&ay>=155&&ay<179)begin
     text_on=1;left=extra_cal_recent?195:211;top=155;label=extra_cal_recent?86:48;kind=0;
    end
   end
   if(page==1&&ax>=724&&ax<977&&ay>=150&&ay<184)begin
    paint=(ax<850)==!studio_state[225]?24'h25565a:24'hedf4e8;ink=(ax<850)==!studio_state[225]?PAPER:INK;
    if(ay>=154&&ay<178)begin
     text_on=1;left=ax<850?755:874;top=154;kind=0;label=ax<850?95:96;
    end
   end
   if(page==6)begin
    for(fc=0;fc<3;fc=fc+1)begin
     fxleft=fc==0?45:fc==1?374:703;
     if(ax>=fxleft+166&&ax<fxleft+276&&ay>=151&&ay<195)begin
      paint=fx_enabled[fc]?24'hc5e6d6:PAPER;
      if(ax>=fxleft+177&&ay>=161&&ay<185)begin text_on=1;left=fxleft+177;top=161;label=fx_enabled[fc]?21:20;kind=0;end
     end
     for(fr=0;fr<3;fr=fr+1)begin
      value=fx_values[(fc*3+fr)*7+:7];wi=314+fr*87;
      // Own the entire dynamic field, not just foreground glyph pixels.
      // This also clears old/default values on a differently generated atlas.
      if(ax>=fxleft+174&&ax<fxleft+278&&ay>=266+fr*87&&ay<301+fr*87)begin paint=PAPER;text_on=0;end
      if(ax>=fxleft-5&&ax<fxleft+280&&ay>=wi-11&&ay<wi+13)paint=PAPER;
      if(ax>=fxleft&&ax<fxleft+275&&ay>=wi-1&&ay<wi+3)paint=24'haabbb1;
      if(ax>=fxleft&&ax<knob_left[fc*3+fr]+4&&ay>=wi-1&&ay<wi+3)paint=fx_enabled[fc]?24'h438578:24'h8ea69a;
      if(ax>=knob_left[fc*3+fr]&&ax<knob_right[fc*3+fr]&&ay>=wi-7&&ay<wi+9&&
         (ax>=knob_left[fc*3+fr]+2&&ax<knob_right[fc*3+fr]-2||ay>=wi-5&&ay<wi+7))paint=fx_enabled[fc]?24'h346e65:24'h82988e;
      if(ax>=fxleft+179&&ax<fxleft+275&&ay>=270+fr*87&&ay<294+fr*87)begin
       text_on=1;left=fxleft+179;top=270+fr*87;number=fx_numbers[fc*3+fr];
       kind=fc==0&&fr==1?6:fc==1&&fr==0?7:fc==2&&fr==0?8:1;
      end
     end
    end
   end
   if(page==2)begin
    if(ax>=65&&ax<243&&ay>=110&&ay<134)begin text_on=1;left=65;top=110;label=phone_score?42:piece==0?31:32;end
    if(ax>=57&&ax<265&&ay>=183&&ay<219)begin
     paint=(ax<160)==!tempo_mode?INK:PAPER;
     if(ay>=188&&ay<212)begin text_on=1;left=ax<160?60:175;top=188;label=ax<160?29:30;ink=(ax<160)==!tempo_mode?PAPER:INK;end
    end
    if(ax>=112&&ax<160&&ay>=241&&ay<265)begin paint=24'hf1f5ec;text_on=1;left=112;top=241;kind=2;number=bpm;end
    if(ax>=320&&ax<440&&ay>=166&&ay<214)begin paint=GREEN;text_on=1;left=320;top=166;kind=2;number=correct;end
    if(ax>=668&&ax<788&&ay>=166&&ay<214)begin paint=24'hefd8c4;ink=24'h875d4b;text_on=1;left=668;top=166;kind=2;number=errors;end
    if(ax>=372&&ax<530&&ay>=240&&ay<264)begin
     paint=GREEN;text_on=1;left=372;top=240;kind=blocked?0:3;label=28;
     cue_word=cues[15:0];number=cue_word[15]&&cue_word[5]?53+cue_word[4:0]:0;
    end
    if(ax>=41&&ax<201&&ay>=467&&ay<515)begin
     paint=INK;if(ax>=53&&ay>=479&&ay<503)begin text_on=1;left=53;top=479;label=blocked?28:status==1?25:status==2?26:24;ink=PAPER;end
    end
    if(ax>=903&&ax<975&&ay>=480&&ay<504)begin text_on=1;left=903;top=480;kind=15;number={5'd0,(step_index<total_steps?step_index+6'd1:total_steps),total_steps};end
    if(menu_open&&ax>=53&&ax<269&&ay>=99&&ay<235)begin
     paint=(piece==0&&ay<167)||(piece==1&&ay>=167)?GREEN:PAPER;
     text_on=1;left=65;top=ay<167?116:184;label=ay<167?31:32;kind=0;
    end
   end
   if(page==3)begin
    if(ax>=46&&ax<302&&ay>=143&&ay<167)begin text_on=1;left=46;top=143;label=app_up?3:link_up?2:1;end
    if(ax>=378&&ax<650&&ay>=151&&ay<175)begin
     text_on=1;left=378;top=151;label=rec_state<2?4:rec_state==2?5:rec_state==3?6:rec_state==4?7:rec_state==5?8:rec_state==6?9:rec_state==7?10:rec_state==8?11:12;
    end
    if(ax>=680&&ax<978&&ay>=92&&ay<136)begin
     if((selected?ax>=834:ax<824)&&(ay<96||ay>=132))paint=24'h286e77;
    end
    if(ax>=680&&ax<760&&ay>=188&&ay<212)begin text_on=1;left=680;top=188;kind=4;number=seconds;end
    if(ax>=378&&ax<978&&ay>=238&&ay<247)begin paint=24'hd4dfd0;if(ax<378+seconds*5)paint=24'h347e79;end
    if(ax>=378&&ax<650&&ay>=486&&ay<510)begin text_on=1;left=378;top=486;label=saved?13:lease?15:14;end
    if(ax>=780&&ax<860&&ay>=486&&ay<510)begin text_on=1;left=780;top=486;kind=5;number=studio_state[143:112]>>10;end
    if(rec_fault!=0&&ax>=900&&ax<948&&ay>=151&&ay<175)begin text_on=1;left=900;top=151;kind=2;number=rec_fault;ink=24'ha14f3c;end
   end
   if((page==5||page==7)&&ax>=700&&ax<972&&ay>=152&&ay<176)begin
    text_on=1;left=700;top=152;label=page==7?(studio_state[165]?40:studio_state[164]?38:39):41;
   end

   if(confirm!=0&&ax>=288&&ax<736&&ay>=206&&ay<410)begin
    paint=PAPER;text_on=0;
    if(ax>=320&&ax<704&&ay>=243&&ay<267)begin text_on=1;left=320;top=243;label=confirm==1?16:17;kind=0;end
    if(ay>=330&&ay<386)begin
     if(ax>=310&&ax<494)paint=24'hdce7cb;else if(ax>=530&&ax<714)paint=24'hefd0bb;
     if(ax>=365&&ax<429&&ay>=345&&ay<369)begin text_on=1;left=365;top=345;label=18;kind=0;end
     if(ax>=585&&ax<649&&ay>=345&&ay<369)begin text_on=1;left=585;top=345;label=19;kind=0;end
    end
   end
  end
  if(!art_available)begin
   paint=PAPER;text_on=0;
   if(ax>=464&&ax<536&&ay>=288&&ay<312)begin text_on=1;left=464;top=288;kind=9;number=art_error;end
  end
  if(extra_take&&art_available)begin
   paint=extra_color;ink=extra_ink;text_on=extra_text_on;
   left=extra_left;top=extra_top;label=extra_label;kind=extra_kind;number=extra_number;
  end
 end
 // Geometry, text selection and glyph addressing are separate pipeline stages.
 always @(posedge pixel_clk)begin
  paint_s<=paint;ink_s<=ink;text_on_s<=text_on;ax_s<=ax;ay_s<=ay;
  left_s<=left;top_s<=top;label_s<=label;kind_s<=kind;number_s<=number;
  de_s<=ad;hs_s<=ah;vs_s<=av;
 end

 // PIPELINED_FORMAT: numeric conversion never shares a path with pixel columns.
 function [7:0] format_ascii;
  input [3:0] knd;input [16:0] n;input [5:0] col;
  input is_large;input [1:0] md;reg [7:0] ascii;
  begin ascii=32;
   case(knd)
    0:ascii=32;
    1,2:begin
     if(is_large&&md==1)ascii=n>=100?(col==0?digit(n/100):col==1?digit(n/10):col==2?digit(n):32):n>=10?(col==0?digit(n/10):col==1?digit(n):32):col==0?digit(n):32;
     else if(is_large)ascii=n>=100?(col==0?digit(n/100):col==1?digit(n/10):col==2?digit(n):32):col==0?(md==2&&n<10?32:digit(n/10)):col==1?digit(n):32;
     else ascii=col==0?(n>=100?digit(n/100):32):col==1?(n>=10?digit(n/10):32):col==2?digit(n):col==3&&knd==1?"%":32;end
    3:begin ascii=n==0?"-":col==0?note_letter(n):col==1?(sharp(n)?"#":digit(n/12-1)):col==2&&sharp(n)?digit(n/12-1):32;end
    4:begin ascii=col==0?digit(n/600):col==1?digit(n/60):col==2?":":col==3?digit((n%60)/10):col==4?digit(n):32;end
    5:begin
     if(md==2)begin
      if(n>=10000)ascii=col==0?digit(n/10000):col==1?digit(n/1000):col==2?digit(n/100):col==3?digit(n/10):col==4?digit(n):32;
      else if(n>=1000)ascii=col==0?digit(n/1000):col==1?digit(n/100):col==2?digit(n/10):col==3?digit(n):32;
      else if(n>=100)ascii=col==0?digit(n/100):col==1?digit(n/10):col==2?digit(n):32;
      else if(n>=10)ascii=col==0?digit(n/10):col==1?digit(n):32;
      else ascii=col==0?digit(n):32;
     end else if(md==1)begin
      if(n>=1000)ascii=col==0?digit(n/1000):col==1?digit(n/100):col==2?digit(n/10):col==3?digit(n):32;
      else if(n>=100)ascii=col==0?digit(n/100):col==1?digit(n/10):col==2?digit(n):32;
      else if(n>=10)ascii=col==0?digit(n/10):col==1?digit(n):32;
      else ascii=col==0?digit(n):32;
     end else ascii=col==0?digit(n/10000):col==1?digit(n/1000):col==2?digit(n/100):col==3?digit(n/10):col==4?digit(n):32;
     end
    6,8:begin ascii=col==0?digit(n/10):col==1?".":col==2?digit(n):col==3?(knd==6?"s":"H"):col==4&&knd==8?"z":32;end
    7:begin ascii=col==0?(n>=1000?digit(n/1000):32):col==1?(n>=100?digit(n/100):32):col==2?digit(n/10):col==3?digit(n):col==4?"m":col==5?"s":32;end
    9:begin
     if(n==0)ascii=col==0?"L":col==1?"O":col==2?"A":col==3?"D":32;
     else ascii=col==0?"E":col==1||col==2?"R":col==4?digit(n/10):col==5?digit(n):32;
     
    end
    10:begin
     ascii=col==0?"H":col==1?"o":col==2?"u":col==3?"s":col==4?"e":col==5?"P":col==6?"i":col==7?"a":col==8?"n":col==9?"o":32;
     
    end
    11:begin
     ascii=col==0?"F":col==1?"F":col==2?"T":col==3?"1":col==4?"2":col==5?"8":32;
     
    end
    12:begin
     if(n==1)ascii=col==0?"P":col==1?"E":col==2?"R":col==3?"F":col==4?"E":col==5?"C":col==6?"T":32;
     else ascii=col==0?"N":col==1?"O":col==2?"R":col==3?"M":col==4?"A":col==5?"L":32;
     
    end
    13:begin
     if(n>=10)ascii=col==0?digit(n/10):col==1?digit(n):col==2?"k":32;
     else ascii=col==0?digit(n):col==1?"k":32;
     
    end
    14:begin ascii=col==0?(n==0?"X":"Y"):32;end
    15:begin
     if(md==2&&page==4)ascii=col==0?"/":col==1?"1":col==2?"2":col==3?"8":32;
     else ascii=col==0?digit(n[11:6]/10):col==1?digit(n[11:6]):col==2?"/":col==3?digit(n[5:0]/10):col==4?digit(n[5:0]):32;end
    default:ascii=32;
   endcase
   format_ascii=ascii;
  end
 endfunction
 wire [1:0] format_scale=(kind_s==2&&((extra_mode!=1&&page==2&&top_s==166)||(extra_mode==2&&top_s==126)||(extra_mode==1&&top_s==276)))?3:
  extra_mode==1&&(kind_s==2||kind_s==5)&&(top_s==166||top_s==250)?2:1;
 reg [79:0] formatted_f,glyphs_f;reg [1:0] format_scale_f;
 reg [23:0] paint_f,ink_f;reg text_on_f;
 reg [10:0] ax_f;reg [9:0] ay_f,left_f,top_f;
 reg [6:0] label_f;reg [3:0] kind_f;reg de_f,hs_f,vs_f;integer fmt_i;
 always @(posedge pixel_clk)begin
  for(fmt_i=0;fmt_i<10;fmt_i=fmt_i+1)begin
   formatted_f[fmt_i*8+:8]<=format_ascii(kind_s,number_s,fmt_i,format_scale!=1,extra_mode);
   glyphs_f[fmt_i*8+:8]<=studio_ascii(format_ascii(kind_s,number_s,fmt_i,format_scale!=1,extra_mode));
  end
  format_scale_f<=format_scale;
  paint_f<=paint_s;ink_f<=ink_s;text_on_f<=text_on_s;
  ax_f<=ax_s;ay_f<=ay_s;left_f<=left_s;top_f<=top_s;label_f<=label_s;kind_f<=kind_s;
  de_f<=de_s;hs_f<=hs_s;vs_f<=vs_s;
 end
 always @* begin
  glyph=0;ascii=32;
  text_dx=ax_f-left_f;
  font_scale=format_scale_f;
  large_text=font_scale!=1;
  font_dx=text_dx;font_y=ay_f-top_f;
  // Large digits use their own ROM. Select columns directly in screen pixels;
  // no per-pixel division by three is needed for a discarded small-font path.
  column=kind_f==0?font_dx[9:4]:large_text?(font_scale==3?
    (text_dx<30?0:text_dx<60?1:text_dx<90?2:text_dx<120?3:text_dx<150?4:63):
    (text_dx<20?0:text_dx<40?1:text_dx<60?2:text_dx<80?3:text_dx<100?4:63)):
    font_dx<12?0:font_dx<24?1:font_dx<36?2:font_dx<48?3:font_dx<60?4:font_dx<72?5:font_dx<84?6:font_dx<96?7:font_dx<108?8:font_dx<120?9:63;
  text_x=kind_f==0?font_dx[3:0]:large_text?0:font_dx-column*12;
  if(text_on_f&&ay_f>=top_f&&ay_f<top_f+(large_text?48:24)&&ax_f>=left_f)begin
   if(kind_f==0)glyph=studio_char(label_f,column);
   else begin
    ascii=column<10?formatted_f[column*8+:8]:8'd32;
    glyph=column<10?glyphs_f[column*8+:8]:8'd0;
   end
  end else glyph=0;
  big_column=column;
  big_x=font_scale==3?text_dx-big_column*30:((text_dx-big_column*20)*3)>>1;
  big_y=font_scale==3?ay_f-top_f:((ay_f-top_f)*3)>>1;
  use_large=large_text&&text_on_f&&ascii>=48&&ascii<=57&&big_column<5&&ay_f>=top_f&&ay_f<top_f+(font_scale==3?48:32);
 end
 // A separate glyph-address stage prevents geometry, decimal selection and
 // the font-bank address addition from forming one long pixel-clock path.
 reg [7:0] glyph_t;reg [4:0] font_y_t;reg [3:0] text_x_t,digit_t;
 reg [5:0] big_y_t;reg [1:0] big_part_t;reg [2:0] big_bit_t;reg use_large_t;
 reg [23:0] paint_t,ink_t;reg de_t,hs_t,vs_t;
 always @(posedge pixel_clk)begin
  glyph_t<=glyph;font_y_t<=font_y;text_x_t<=text_x;digit_t<=ascii-48;
  big_y_t<=big_y;big_part_t<=big_x[4:3];big_bit_t<=big_x[2:0];use_large_t<=use_large;
  paint_t<=paint_f;ink_t<=ink_f;de_t<=de_f;hs_t<=hs_f;vs_t<=vs_f;
 end
 reg [23:0] paint_q,ink_q;reg [2:0] font_x_q;reg de_q,hs_q,vs_q;
 reg [23:0] paint_qq,ink_qq;reg [2:0] font_x_qq;reg de_qq,hs_qq,vs_qq;
 reg use_large_q,use_large_qq;
 wire [1:0] alpha=(use_large_qq?large_word:font_word)>>(font_x_qq*2);
 function [7:0] blend;input [7:0] a,b;input [1:0] c;reg [9:0] v;begin
  case(c)0:blend=a;1:begin v=a*3+b;blend=v[9:2];end 2:begin v=a+b*3;blend=v[9:2];end 3:blend=b;endcase
 end endfunction
 always @(posedge pixel_clk)begin
  font_address_q<={glyph_t,6'b0}+{8'd0,font_y_t,1'b0}+text_x_t[3];
  large_address_q<=use_large_t?{digit_t,7'd0}+{1'b0,digit_t,6'd0}+{3'd0,big_y_t,2'd0}+big_part_t:0;
  paint_q<=paint_t;ink_q<=ink_t;font_x_q<=use_large_t?big_bit_t:text_x_t[2:0];use_large_q<=use_large_t;de_q<=de_t;hs_q<=hs_t;vs_q<=vs_t;
  paint_qq<=paint_q;ink_qq<=ink_q;font_x_qq<=font_x_q;use_large_qq<=use_large_q;de_qq<=de_q;hs_qq<=hs_q;vs_qq<=vs_q;
  rgb<={blend(paint_qq[23:16],ink_qq[23:16],alpha),blend(paint_qq[15:8],ink_qq[15:8],alpha),blend(paint_qq[7:0],ink_qq[7:0],alpha)};
  out_de<=de_qq;out_hs<=hs_qq;out_vs<=vs_qq;
  if(reset)begin rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;end
 end
endmodule
