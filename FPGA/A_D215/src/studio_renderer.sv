`timescale 1ns/1ps
module studio_renderer #(parameter ARTWORK_DDR=1)(
 input wire host_clk,host_rst_n,ui_mem_ready,ui_mem_done,ui_mem_error,input wire [255:0] ui_mem_read_data,
 output wire ui_mem_request,ui_mem_write,output wire [28:0] ui_mem_address,output wire [255:0] ui_mem_write_data,
 input wire [255:0] studio_state,
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
 wire [4:0] scene=about_open?14:page==0?0:page==1?1+{3'd0,octave_group}:
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
 integer left,top,label,kind,k,fc,fr,fxleft,value,cue,nn,wi,sp,field_x,field_y;
 reg [7:0] wa,wb;reg [5:0] column;reg [3:0] text_x;reg [9:0] text_dx;
 reg [16:0] number;
 reg text_on;reg [7:0] ascii;reg [5:0] key;reg [15:0] cue_word;
 reg [13:0] font_address,font_address_q;wire [15:0] font_word;
 reg [23:0] paint_s,ink_s;reg text_on_s;reg [10:0] ax_s;reg [9:0] ay_s;
 reg [9:0] left_s,top_s;reg [5:0] label_s;reg [3:0] kind_s;reg [16:0] number_s;
 reg de_s,hs_s,vs_s;
 studio_font letters(.clk(pixel_clk),.addr(font_address_q),.data(font_word));
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
  if(!about_open&&art_available)begin
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
   if(page==1||page==2)begin
    key=key_hit;
    // Highlight only the top/bottom strips, preserving printed pitch labels.
    wi=page==1?409:323;nn=page==1?513:443;
    case(key)1,3,5,8,10,13,15,17,20,22,25,27,29:nn=page==1?472:399;endcase
    if(key<32&&(ay<wi+5||ay>=nn-5))begin
     if(keys_down[key]&&(octave_group!=0||key>=7))paint=24'h82c4a1;
     else if(page==2&&target_keys[key]&&!blocked)paint=24'hb9dce6;
     if(page==2&&!phone_score&&feedback==2&&keys_down[key]&&!target_keys[key])paint=24'hefad87;
    end
   end
   // Compact drum-only calibration button beside the existing heading.
   if(page==5&&ax>=175&&ax<265&&ay>=146&&ay<188)begin
    paint=(ax<177||ax>=263||ay<148||ay>=186)?24'h77999b:24'hdceef2;
    if(ax>=180&&ax<260&&ay>=155&&ay<179)begin text_on=1;left=180;top=155;label=48;kind=0;ink=INK;end
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
      if(ax>=fxleft&&ax<fxleft+274&&ay>=wi-1&&ay<wi+3)paint=24'haabbb1;
      if(ax>=knob_left[fc*3+fr]&&ax<knob_right[fc*3+fr]&&ay>=wi-7&&ay<wi+9)paint=fx_enabled[fc]?24'h346e65:24'h82988e;
      if(ax>=fxleft+179&&ax<fxleft+275&&ay>=270+fr*87&&ay<294+fr*87)begin
       text_on=1;left=fxleft+179;top=270+fr*87;number=fx_numbers[fc*3+fr];
       kind=fc==0&&fr==1?6:fc==1&&fr==0?7:fc==2&&fr==0?8:1;
      end
     end
    end
   end
   if(page==2)begin
    if(ax>=65&&ax<257&&ay>=115&&ay<139)begin paint=PAPER;text_on=1;left=65;top=115;label=phone_score?42:piece==0?31:32;end
    if(ax>=312&&ax<536&&ay>=134&&ay<158)begin text_on=1;left=312;top=134;label=blocked?28:status==1?(phone_score?(studio_state[191]?29:30):37):status==2?36:status==3?27:41;end
    if(ax>=57&&ax<265&&ay>=183&&ay<219)begin
     if((tempo_mode&&ax>=162)||(!tempo_mode&&ax<160))paint=INK;
     if(ay>=188&&ay<212)begin text_on=1;left=ax<160?60:175;top=188;label=ax<160?29:30;ink=(ax<160)==!tempo_mode?PAPER:INK;end
    end
    if(ax>=112&&ax<176&&ay>=241&&ay<265)begin text_on=1;left=112;top=241;kind=2;number=bpm;end
    for(cue=0;cue<4;cue=cue+1)begin
     if(phone_score&&cue!=0)begin
      field_x=cue==1?574:cue==2?718:860;
      if(ax>=field_x&&ax<field_x+115&&ay>=142&&ay<174)begin paint=cue==1?24'he1ead6:24'heef1e7;text_on=1;left=field_x+10;top=144;label=44+cue;kind=0;ink=INK;end
     end
     field_x=cue==0?315:cue==1?603:cue==2?750:893;field_y=cue==0?178:190;
     if(ax>=field_x&&ax<field_x+64&&ay>=field_y&&ay<field_y+24)begin
      text_on=1;left=field_x;top=field_y;kind=3;cue_word=cues[cue*16+:16];number=cue_word[15]&&cue_word[5]?53+cue_word[4:0]:0;
     end
    end
    if(ax>=315&&ax<539&&ay>=248&&ay<272)begin text_on=1;left=315;top=248;kind=0;label=phone_score?43:blocked?28:status==1?25:status==3?27:41;end
    if(ax>=41&&ax<201&&ay>=467&&ay<515)begin
     paint=INK;if(ax>=53&&ay>=479&&ay<503)begin text_on=1;left=53;top=479;kind=0;label=blocked?28:status==1?25:status==2?26:24;ink=PAPER;end
    end
    if(phone_score&&ax>=720&&ax<1000&&ay>=450&&ay<520)begin paint=PAPER;text_on=ax>=735&&ax<875&&ay>=480&&ay<504;left=735;top=480;label=43;kind=0;end
    if(!phone_score&&ax>=748&&ax<796&&ay>=480&&ay<504)begin text_on=1;left=748;top=480;kind=2;number=correct;end
    if(!phone_score&&ax>=824&&ax<872&&ay>=480&&ay<504)begin text_on=1;left=824;top=480;kind=2;number=errors;end
    if(ax>=903&&ax<(phone_score?975:951)&&ay>=480&&ay<504)begin paint=PAPER;text_on=1;left=903;top=480;kind=phone_score?5:2;number=phone_score?studio_state[208:193]:step_index<total_steps?step_index+1:total_steps;end
    if(phone_score&&ax>=53&&ax<265&&ay>=183&&ay<270)begin paint=PAPER;ink=INK;text_on=ay>=188&&ay<212;left=60;top=188;label=43;kind=0;end
    if(phone_score&&ax>=210&&ax<300&&ay>=466&&ay<516)begin paint=PAPER;text_on=0;end
    if(phone_score&&ax>=41&&ax<201&&ay>=467&&ay<515)begin paint=INK;text_on=ax>=53&&ay>=479&&ay<503;left=53;top=479;label=studio_state[190]?44:43;kind=0;ink=PAPER;end
    if(menu_open&&ax>=53&&ax<269&&ay>=99&&ay<235)begin
     paint=PAPER;text_on=1;left=65;top=ay<167?116:184;label=ay<167?31:32;kind=0;
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
   if(page==4&&ax>=706&&ax<978&&ay>=375&&ay<399)begin text_on=1;left=706;top=375;label=rec_state==8?11:rec_state<2?34:35;end
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
 end
 // Geometry, text selection and glyph addressing are separate pipeline stages.
 always @(posedge pixel_clk)begin
  paint_s<=paint;ink_s<=ink;text_on_s<=text_on;ax_s<=ax;ay_s<=ay;
  left_s<=left;top_s<=top;label_s<=label;kind_s<=kind;number_s<=number;
  de_s<=ad;hs_s<=ah;vs_s<=av;
 end
 always @* begin
  glyph=0;ascii=32;
  text_dx=ax_s-left_s;
  column=kind_s==0?text_dx[9:4]:text_dx<12?0:text_dx<24?1:text_dx<36?2:text_dx<48?3:text_dx<60?4:text_dx<72?5:63;
  text_x=kind_s==0?text_dx[3:0]:column==0?text_dx:column==1?text_dx-12:column==2?text_dx-24:column==3?text_dx-36:column==4?text_dx-48:column==5?text_dx-60:0;
  if(text_on_s&&ay_s>=top_s&&ay_s<top_s+24&&ax_s>=left_s)begin
   case(kind_s)
    0:glyph=studio_char(label_s,column);
    1,2:begin ascii=column==0?(number_s>=100?digit(number_s/100):32):column==1?(number_s>=10?digit(number_s/10):32):column==2?digit(number_s):column==3&&kind_s==1?"%":32;glyph=studio_ascii(ascii);end
    3:begin ascii=number_s==0?"-":column==0?note_letter(number_s):column==1?(sharp(number_s)?"#":digit(number_s/12-1)):column==2&&sharp(number_s)?digit(number_s/12-1):32;glyph=studio_ascii(ascii);end
    4:begin ascii=column==0?digit(number_s/600):column==1?digit(number_s/60):column==2?":":column==3?digit((number_s%60)/10):column==4?digit(number_s):32;glyph=studio_ascii(ascii);end
    5:begin ascii=column==0?digit(number_s/10000):column==1?digit(number_s/1000):column==2?digit(number_s/100):column==3?digit(number_s/10):column==4?digit(number_s):32;glyph=studio_ascii(ascii);end
    6,8:begin ascii=column==0?digit(number_s/10):column==1?".":column==2?digit(number_s):column==3?(kind_s==6?"s":"H"):column==4&&kind_s==8?"z":32;glyph=studio_ascii(ascii);end
    7:begin ascii=column==0?(number_s>=1000?digit(number_s/1000):32):column==1?(number_s>=100?digit(number_s/100):32):column==2?digit(number_s/10):column==3?digit(number_s):column==4?"m":column==5?"s":32;glyph=studio_ascii(ascii);end
    9:begin
     if(number_s==0)ascii=column==0?"L":column==1?"O":column==2?"A":column==3?"D":32;
     else ascii=column==0?"E":column==1||column==2?"R":column==4?digit(number_s/10):column==5?digit(number_s):32;
     glyph=studio_ascii(ascii);
    end
    default:glyph=0;
   endcase
  end else glyph=0;
  font_address={glyph,6'b0}+((ay_s-top_s)&31)*2+(text_x>>3);
 end
 reg [23:0] paint_q,ink_q;reg [2:0] font_x_q;reg de_q,hs_q,vs_q;
 reg [23:0] paint_qq,ink_qq;reg [2:0] font_x_qq;reg de_qq,hs_qq,vs_qq;
 wire [1:0] alpha=font_word>>(font_x_qq*2);
 function [7:0] blend;input [7:0] a,b;input [1:0] c;reg [9:0] v;begin
  case(c)0:blend=a;1:begin v=a*3+b;blend=v[9:2];end 2:begin v=a+b*3;blend=v[9:2];end 3:blend=b;endcase
 end endfunction
 always @(posedge pixel_clk)begin
  font_address_q<=font_address;
  paint_q<=paint_s;ink_q<=ink_s;font_x_q<=text_x&7;de_q<=de_s;hs_q<=hs_s;vs_q<=vs_s;
  paint_qq<=paint_q;ink_qq<=ink_q;font_x_qq<=font_x_q;de_qq<=de_q;hs_qq<=hs_q;vs_qq<=vs_q;
  rgb<={blend(paint_qq[23:16],ink_qq[23:16],alpha),blend(paint_qq[15:8],ink_qq[15:8],alpha),blend(paint_qq[7:0],ink_qq[7:0],alpha)};
  out_de<=de_qq;out_hs<=hs_qq;out_vs<=vs_qq;
  if(reset)begin rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;end
 end
endmodule
