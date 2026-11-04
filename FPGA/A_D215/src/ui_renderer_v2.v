`timescale 1ns/1ps
module ui_renderer_v2(
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
);
 `include "src/ui_v2_layout.vh"
 `include "src/ui_wind_layout.vh"
 `include "src/ui_v2_render_map.vh"
 `include "src/ui_v2_font.vh"
 `include "src/ui_fx_math.vh"
 `include "src/ui_plot_math.vh"
 localparam LIME=24'h42bff5,CYAN=24'h8edccc,ORANGE=24'hf09b7c,
  WHITE=24'heef4f8,MUTED=24'h9eb0bd,PANEL=24'h1a252e,DARK=24'h10181f;
 wire [4:0] scene=page==0?0:(page==1||page==7)?5'd1+octave_group:page==6?5:page==2?5'd6+octave_group:page==5?5'd15+octave_group:page==3?19:20;
 wire [23:0] art;wire [10:0] ax;wire [9:0] ay;wire ad,ah,av;
 ui_artwork artwork(.clk(pixel_clk),.reset(reset),.scene(scene),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),
  .rgb(art),.px(ax),.py(ay),.out_de(ad),.out_hs(ah),.out_vs(av));
 reg [10:0] px;reg [9:0] py;reg [23:0] background;reg pd,ph,pv;
 reg [5:0] spectrum_column;
 // Decode the key overlay during the artwork ROM's existing latency.
 // Keep the final RGB/sync latency at ten clocks. The frame-atomic UI state
 // is constant while these pixels are in flight.
 reg [5:0] key0;
 reg [9:0] key_y0,key_y1,key_top1,key_bottom1;
 reg key_held1,key_target1,key_cue1;
 reg key_held2,key_target2,key_cue2,key_border2,key_hint2;
 reg [2:0] key_paint3,key_paint4,key_paint5;
 reg [9:0] key_top_next,key_bottom_next;
 always @* begin
  key_top_next=page==1?10'd409:page==2?10'd269:10'd400;
  key_bottom_next=page==1?10'd513:page==2?10'd421:10'd544;
  case(key0)
   1,3,5,8,10,13,15,17,20,22,25,27,29:
    key_bottom_next=page==1?10'd472:page==2?10'd363:10'd490;
   default:begin end
  endcase
 end
 always @(posedge pixel_clk) begin
  key0<=ui_v2_key_at(page,piece,x[9:0],y);key_y0<=y;
  key_y1<=key_y0;key_top1<=key_top_next;key_bottom1<=key_bottom_next;
  key_held1<=key0<32&&(octave_group!=0||key0>=7)&&keys_down[key0];
  key_target1<=key0<32&&target_keys[key0];
  key_cue1<=key0<32&&key0==cues[20:16];
  key_held2<=key_held1;key_target2<=key_target1;key_cue2<=key_cue1;
  key_border2<=key_y1>=key_bottom1-10'd8||key_y1<key_top1+10'd5;
  key_hint2<=key_y1==key_bottom1-10'd4||key_y1==key_top1+10'd2;
  if(key_held2&&key_border2)
   key_paint3<=page==1?1:(status==1&&!blocked&&!key_target2?2:3);
  else if((page==2||page==5)&&key_target2&&key_border2)key_paint3<=1;
  else if(page==2&&!blocked&&cues[31]&&cues[21]&&key_cue2&&key_hint2)key_paint3<=4;
  else key_paint3<=0;
  key_paint4<=key_paint3;key_paint5<=key_paint4;
  if(reset)begin
   key0<=63;key_held1<=0;key_target1<=0;key_cue1<=0;
   key_held2<=0;key_target2<=0;key_cue2<=0;
   key_border2<=0;key_hint2<=0;key_paint3<=0;key_paint4<=0;key_paint5<=0;
  end
 end
 reg [9:0] wave_a1,wave_b1,wave_low2,wave_high2,wave_low3,wave_high3,wave_low4,wave_high4,wave_low5,wave_high5;
 reg [4:0] lissa_pipe;
 reg [9:0] spectrum_floor[0:31],echo_left[0:5],echo_floor[0:5];
 reg [5:0] chorus_phase0;reg signed [6:0] chorus_sine1;reg signed [15:0] chorus_product2;
 reg signed [10:0] chorus_y3,chorus_y4,chorus_y5;
 reg [7:0] reverb_x0;reg [15:0] reverb_product1;reg [5:0] reverb_height2;
 reg [9:0] reverb_floor3,reverb_floor4,reverb_floor5;
 reg [9:0] guide_cue_left[0:3],guide_cue_top[0:3];
 reg [10:0] fx_number[0:8];reg [9:0] fx_center[0:8];
 integer fx_i;
 reg [10:0] slider0,slider1;reg [9:0] guide_progress,flow_progress;
 always @(posedge pixel_clk)begin
  px<=ax;py<=ay;background<=art;pd<=ad;ph<=ah;pv<=av;
  spectrum_column<=ui_spectrum_column(ax);
  lissa_pipe<={lissa_pipe[3:0],lissa_pixel};
  // Six clocks from raster input to paint. Narrow arithmetic and registers
  // keep parameter-preview multiplication out of the final RGB selection.
  chorus_phase0<=(x[5:0]-6'd56)*(3'd1+{1'b0,fx_values[48:47]});
  chorus_sine1<=fx_sine(chorus_phase0);
  chorus_product2<=$signed(chorus_sine1)*($signed({2'b0,fx_values[55:49]})+9'sd8);
  chorus_y3<=11'sd294+(chorus_product2>>>8);chorus_y4<=chorus_y3;chorus_y5<=chorus_y4;
  reverb_x0<=x[7:0]-8'd154;
  reverb_product1<=reverb_x0*(8'd128-{1'b0,fx_values[13:7]});
  reverb_height2<=reverb_product1[15:8]>=43?6'd1:6'd44-reverb_product1[13:8];
  reverb_floor3<=10'd317-reverb_height2;reverb_floor4<=reverb_floor3;reverb_floor5<=reverb_floor4;
  for(fx_i=0;fx_i<32;fx_i=fx_i+1)spectrum_floor[fx_i]<=10'd512-({6'b0,spectrum[fx_i*4+:4]}*4'd5);
  for(fx_i=0;fx_i<6;fx_i=fx_i+1)begin
   echo_left[fx_i]<=10'd460+fx_i*(7'd16+{1'b0,fx_values[27:22]});
   echo_floor[fx_i]<=fx_i==0?10'd273:10'd317-((14'd40*fx_values[34:28])>>(6+fx_i));
  end
  for(fx_i=0;fx_i<4;fx_i=fx_i+1)begin
   guide_cue_left[fx_i]<=fx_i==0?132:fx_i==1?456:fx_i==2?639:823;
   guide_cue_top[fx_i]<=166;
  end
  for(fx_i=0;fx_i<9;fx_i=fx_i+1)begin
   fx_number[fx_i]<=fx_numeric(fx_i,fx_values[fx_i*7+:7]);
   fx_center[fx_i]<=(fx_i<3?129:fx_i<6?432:735)+fx_offset(fx_values[fx_i*7+:7]);
  end
  wave_a1<=ui_wave_y(scope_pair[15:8]);wave_b1<=ui_wave_y(scope_pair[7:0]);
  wave_low2<=wave_a1<wave_b1?wave_a1:wave_b1;wave_high2<=wave_a1>wave_b1?wave_a1:wave_b1;
  wave_low3<=wave_low2;wave_high3<=wave_high2;wave_low4<=wave_low3;wave_high4<=wave_high3;wave_low5<=wave_low4;wave_high5<=wave_high4;
  slider0<=817+ui_slider_offset(master_percent);slider1<=817+ui_slider_offset(piano_percent);
  guide_progress<=ui_guide_progress(progress_percent);flow_progress<=ui_flow_progress(progress_percent);
  if(reset)begin pd<=0;ph<=0;pv<=0;end
 end
 reg [23:0] paint,ink;reg [2:0] text_kind;reg [10:0] text_value;
 reg [9:0] text_dx;reg [4:0] text_dy;reg text_large;reg [2:0] text_digits;
 // One text request is selected per pixel, then one shared glyph ROM is read.
 task caption;input [5:0] id;input integer left,top;input [23:0] color;input integer extent;
 begin if(px>=left&&px<left+extent&&py>=top&&py<top+16)begin
  text_kind=1;text_value={2'b0,id};text_dx=px-left;text_dy=py-top;text_large=0;ink=color;
 end end endtask
 task large_caption;input [5:0] id;input integer left,top;input [23:0] color;input integer extent;
 begin if(px>=left&&px<left+extent&&py>=top&&py<top+32)begin
  text_kind=1;text_value={2'b0,id};text_dx=px-left;text_dy=py-top;text_large=1;ink=color;
 end end endtask
 task character;input [7:0] ascii;input integer left,top;input [23:0] color;
 begin if(px>=left&&px<left+8&&py>=top&&py<top+16)begin
  text_kind=4;text_value=ascii;text_dx=px-left;text_dy=py-top;text_large=0;ink=color;
 end end endtask
 task number;input [10:0] value;input [2:0] digits;input integer left,top;input double_size;input [23:0] color;
 begin if(px>=left&&px<left+digits*(double_size?16:8)&&py>=top&&py<top+(double_size?32:16))begin
  text_kind=2;text_value=value;text_digits=digits;text_dx=px-left;text_dy=py-top;text_large=double_size;ink=color;
 end end endtask
 task note_name;input [4:0] k;input integer left,top;input [23:0] color;
 begin if(px>=left&&px<left+24&&py>=top&&py<top+16)begin
  text_kind=3;text_value={3'b0,k};text_dx=px-left;text_dy=py-top;text_large=0;ink=color;
 end end endtask
 task slider;input [10:0] center;input integer yy,xl,xr;input enabled;
 reg signed [12:0] ddx,ddy;reg [4:0] radius;
 begin
  ddx=$signed({2'b0,px})-$signed({2'b0,center});ddy=$signed({3'b0,py})-yy;
  radius=(ddy>=-3&&ddy<=3)?9:(ddy>=-6&&ddy<=6)?8:(ddy>=-8&&ddy<=8)?6:3;
  if(px>=xl&&px<=xr&&py>=yy-2&&py<=yy+2)paint=px<=center&&enabled?LIME:24'h304451;
  if(ddy>=-9&&ddy<=9&&ddx>=-$signed({1'b0,radius})&&ddx<=$signed({1'b0,radius}))paint=enabled?LIME:MUTED;
 end endtask
 integer i,cx,cy,bot,top,left,right,dx,dy,level,bar_index,cue_left,curve,fx_col,fx_row,decay_level,interval;
 reg [31:0] bw;reg [19:0] bounds;reg [15:0] cue;
 wire [9:0] low_y=wave_low5,high_y=wave_high5;
 reg [5:0] state_caption,feedback_caption,button_caption;
 reg [23:0] state_color,bar_color;
 reg [9:0] bar_left[0:9],bar_right[0:9];reg signed [11:0] bar_top[0:9],bar_bottom[0:9];
 reg [4:0] bar_key[0:9];reg [1:0] bar_result[0:9];reg [9:0] bar_valid;
 // Hit comparisons and relative glyph coordinates are registered alongside
 // the artwork, before bar priority and the fixed status/menu overlays.
 reg [9:0] flow_hit,flow_edge,flow_label;
 reg [9:0] flow_dx[0:9];reg [4:0] flow_dy[0:9];
 integer hit_i;
 always @(posedge pixel_clk)begin
  for(hit_i=0;hit_i<10;hit_i=hit_i+1)begin
   flow_hit[hit_i]<=bar_valid[hit_i]&&ax>=bar_left[hit_i]&&ax<bar_right[hit_i]&&ay>=82&&ay<400&&$signed({2'b0,ay})>=bar_top[hit_i]&&$signed({2'b0,ay})<bar_bottom[hit_i];
   flow_edge[hit_i]<=$signed({2'b0,ay})<bar_top[hit_i]+12'sd2||$signed({2'b0,ay})>=bar_bottom[hit_i]-12'sd2||ax<bar_left[hit_i]+11'd1||ax>=bar_right[hit_i]-11'd1;
   flow_label[hit_i]<=bar_bottom[hit_i]-bar_top[hit_i]>=24&&ax>=bar_left[hit_i]+11'd2&&ax<bar_left[hit_i]+11'd26&&$signed({2'b0,ay})>=bar_top[hit_i]+12'sd5&&$signed({2'b0,ay})<bar_top[hit_i]+12'sd21;
   flow_dx[hit_i]<=ax-bar_left[hit_i]-11'd2;
   flow_dy[hit_i]<=ay-bar_top[hit_i]-12'sd5;
  end
 end
 integer bi;reg [31:0] pre_bar;reg [19:0] pre_bounds;reg signed [11:0] pre_bottom;
 always @(posedge pixel_clk)begin
  state_caption<=blocked?10:status==0?5:status==2?8:status==3?9:tempo_mode?7:6;
  feedback_caption<=blocked?20:cues[12:11]==1?43:feedback==1?17:feedback==2?18:feedback==3?19:status==3?32:status==0?21:16;
  button_caption<=blocked&&page==5?33:status==1?12:status==2?13:status==3?14:11;
  state_color<=blocked||feedback==2?ORANGE:status==1?LIME:MUTED;
  for(bi=0;bi<10;bi=bi+1)begin
   pre_bar=bars[bi*32+:32];pre_bounds=flow_key_bounds(pre_bar[4:0]);
   pre_bottom=12'sd82+$signed(pre_bar[16:6]);
   bar_left[bi]<=pre_bounds[9:0]+3;bar_right[bi]<=pre_bounds[19:10]-3;
   bar_bottom[bi]<=pre_bottom;bar_top[bi]<=pre_bottom-$signed({4'b0,pre_bar[24:17]});
   bar_valid[bi]<=pre_bar[5];bar_key[bi]<=pre_bar[4:0];bar_result[bi]<=pre_bar[26:25];
  end
 end
 always @*begin
  paint=background;ink=WHITE;text_kind=0;text_value=0;text_dx=0;text_dy=0;text_large=0;text_digits=0;
  cx=0;cy=0;bot=0;top=0;left=0;right=0;dx=0;dy=0;level=0;bar_index=0;cue_left=0;bw=0;bounds=0;cue=0;bar_color=LIME;
  curve=0;fx_col=0;fx_row=0;decay_level=0;interval=0;
  if(pd)begin
   if(page!=5&&px>=877&&px<883&&py>=47&&py<53)
    paint=usb_status[1:0]==2||usb_status[3:2]==2?LIME:usb_status==0?MUTED:ORANGE;
   // Keep the engraved note names visible; target and held strips have
   // different colors and are drawn using the same hit map as touch input.
   case(key_paint5)
    1:paint=LIME;2:paint=ORANGE;3:paint=CYAN;4:paint=MUTED;
    default:begin end
   endcase
   case(page)
    0:begin
    slider(slider0,403,817,933,1);slider(slider1,439,817,933,1);
    number(master_percent,3,951,396,0,LIME);number(piano_percent,3,951,432,0,LIME);
    number({4'b0,touch_count},2,928,364,0,LIME);number({1'b0,voice_count},2,972,364,0,LIME);
    if(px>=121&&px<679&&py>=149&&py<328&&py>=low_y&&py<=high_y)paint=LIME;
    if(spectrum_column[5]&&py>=435&&py<512)begin
     if(py>=spectrum_floor[spectrum_column[4:0]])paint=LIME;
    end
    if(px>=791&&px<919&&py>=159&&py<287&&lissa_pipe[4])paint=CYAN;
    number(lissa_delay==0?8:lissa_delay==1?16:lissa_delay==2?32:64,2,900,112,0,LIME);caption(40,923,112,MUTED,12);
    if(px>=959&&px<978&&py>=111&&py<128)begin
     if(lissa_run)begin if((px>=961&&px<965)||(px>=971&&px<975))paint=LIME;end
     else if(px-960<=((py<=119)?py-110:128-py)*2)paint=LIME;
    end
    if(px>=725&&px<873&&py>=357&&py<382)paint=PANEL;
    caption(muted?37:36,725,361,muted?ORANGE:WHITE,60);
    if(px>=877&&px<985&&py>=493&&py<537)paint=muted?24'h42302c:24'h16405a;
    caption(muted?35:34,muted?903:915,507,muted?ORANGE:LIME,48);
   end
    6:begin
    for(i=0;i<3;i=i+1)begin
     left=i==0?302:i==1?605:908;
     if(px>=left&&px<left+78&&py>=161&&py<205)paint=fx_enabled[i]?24'h16405a:PANEL;
     caption(fx_enabled[i]?38:39,left+20,175,fx_enabled[i]?LIME:MUTED,36);
    end
    for(i=0;i<9;i=i+1)begin
     left=i<3?129:i<6?432:735;top=380+(i%3)*50;
     slider(fx_center[i],top,left,left+240,fx_enabled[i/3]);
     if(i==1||i==6)begin
      number(fx_number[i]/10,1,left+200,top-34,0,fx_enabled[i/3]?LIME:MUTED);
      character(".",left+208,top-34,MUTED);number(fx_number[i]%10,1,left+216,top-34,0,fx_enabled[i/3]?LIME:MUTED);
      if(i==1)character("s",left+240,top-34,MUTED);
      else begin character("H",left+232,top-34,MUTED);character("z",left+240,top-34,MUTED);end
     end else begin
      number(fx_number[i],i==3?4:3,left+192,top-34,0,fx_enabled[i/3]?LIME:MUTED);
      if(i==3)begin character("m",left+232,top-34,MUTED);character("s",left+240,top-34,MUTED);end
      else character("%",left+240,top-34,MUTED);
     end
    end
    // Parameter diagrams; the three effects process the piano audio only.
    if(px>=154&&px<345&&py>=272&&py<317)begin
     dx=px-154;
     if((dx&7)<2&&py>=reverb_floor5)paint=fx_enabled[0]?LIME:MUTED;
    end
    if(px>=457&&px<648&&py>=272&&py<317)begin
     for(i=0;i<6;i=i+1)begin
      if(px>=echo_left[i]&&px<echo_left[i]+10'd3&&py>=echo_floor[i])paint=fx_enabled[1]?LIME:MUTED;
     end
    end
    if(px>=760&&px<951&&py>=272&&py<317)begin
     curve=chorus_y5;
     if(py>=curve-1&&py<=curve+1)paint=fx_enabled[2]?LIME:MUTED;
    end
   end
    2:begin
    caption({4'b0,piece}+1,135,117,WHITE,180);
    caption(state_caption,367,168,state_color,60);number(bpm,3,880,115,0,WHITE);
    character("B",907,115,MUTED);character("P",915,115,MUTED);character("M",923,115,MUTED);
    if(py>=139&&py<143&&((!tempo_mode&&px>=648&&px<736)||(tempo_mode&&px>=739&&px<815)))paint=LIME;
    for(i=0;i<4;i=i+1)begin
     cue=cues[i*16+:16];cue_left=guide_cue_left[i];top=guide_cue_top[i];
     caption(i==0?22:23,cue_left,top,MUTED,24);
     if(cue[15])begin
      if(cue[5])note_name(cue[4:0],cue_left,top+20,i==0?LIME:WHITE);
     end
    end
    if(cues[15])begin
     if(cues[5])begin caption(30,119,426,MUTED,48);note_name(cues[4:0],172,426,LIME);end
    end
    caption(feedback_caption,132,212,state_color,348);
    caption(24,590,508,MUTED,24);number({1'b0,correct},2,620,508,0,LIME);
    caption(25,665,508,MUTED,24);number({1'b0,missed},2,695,508,0,ORANGE);
    caption(26,740,508,MUTED,24);number({1'b0,errors},3,770,508,0,ORANGE);
    caption(button_caption,135,506,blocked?MUTED:DARK,48);
    number({2'b0,step_index<total_steps?step_index+1'b1:total_steps},2,905,507,0,WHITE);
    number({2'b0,total_steps},2,961,507,0,MUTED);character("/",943,507,MUTED);
    if(py>=478&&py<482&&px>=119&&px<119+guide_progress)paint=LIME;
   end
    5:begin
    // Falling bars are precomputed in the audio/control clock domain.
    for(i=0;i<10;i=i+1)begin
     if(flow_hit[i])begin
      bar_color=bar_result[i]==1?CYAN:bar_result[i]==2?ORANGE:LIME;
      paint=flow_edge[i]?WHITE:bar_color;
      if(flow_label[i])begin text_kind=3;text_value={6'b0,bar_key[i]};text_dx=flow_dx[i];text_dy=flow_dy[i];text_large=0;ink=DARK;end
     end
    end
    caption({4'b0,piece}+1,266,27,WHITE,180);
    if(py>=50&&py<53&&((!tempo_mode&&px>=643&&px<725)||(tempo_mode&&px>=728&&px<810)))paint=LIME;
    // Clear a small status strip so a falling note cannot obscure the labels.
    if(py>=89&&py<113&&((px>=40&&px<205)||(px>=732&&px<990)))begin paint=DARK;text_kind=0;end
    caption(state_caption,50,93,state_color,60);
    caption(24,740,93,MUTED,24);number({1'b0,correct},2,766,93,0,LIME);
    caption(25,820,93,MUTED,24);number({1'b0,missed},2,846,93,0,ORANGE);
    caption(26,900,93,MUTED,24);number({1'b0,errors},3,926,93,0,ORANGE);
    caption(button_caption,34,566,blocked?MUTED:DARK,48);number(bpm,3,236,565,0,WHITE);
    number({2'b0,step_index<total_steps?step_index+1'b1:total_steps},2,353,562,0,WHITE);
    number({2'b0,total_steps},2,394,562,0,MUTED);
    character("/",379,562,MUTED);
    number({1'b0,progress_percent},3,854,562,0,LIME);
    character("%",880,562,MUTED);
    if(py>=583&&py<586&&px>=353&&px<353+flow_progress)paint=LIME;
    if(status!=1||blocked)begin
     if(px>=312&&px<712&&py>=206&&py<282)begin paint=PANEL;text_kind=0;end
     caption(state_caption,470,216,state_color,60);
     caption(feedback_caption,348,246,MUTED,348);
    end
   end
    default:begin end
   endcase
   // Third tone tab. Only page 7 replaces the content below the existing header.
   if(page==1||page==6||page==7)begin
    if(px>=WIND_TAB_L&&px<WIND_TAB_R&&py>=WIND_TAB_T&&py<WIND_TAB_B)paint=page==7?24'h16405a:PANEL;
    caption(44,417,106,page==7?LIME:MUTED,48);
   end
   if(page==7)begin
    // Redraw the first two tabs as inactive; keep their original hit regions.
    if(px>=108&&px<372&&py>=92&&py<136)begin paint=PANEL;text_kind=0;end
    caption(53,161,106,MUTED,48);caption(54,295,106,MUTED,48);
    if(px>=95&&py>=144&&py<556)begin paint=DARK;text_kind=0;end
    large_caption(55,135,170,WHITE,192);caption(52,733,183,MUTED,216);
    if(py>=WIND_CARD_T&&py<WIND_CARD_B)begin
     if(px>=WIND_FLUTE_L&&px<WIND_FLUTE_R)paint=flute_suona?PANEL:24'h16405a;
     if(px>=WIND_SUONA_L&&px<WIND_SUONA_R)paint=flute_suona?24'h473126:PANEL;
    end
    large_caption(45,165,258,flute_suona?WHITE:LIME,96);
    large_caption(46,589,258,flute_suona?ORANGE:WHITE,96);
    caption(57,165,305,MUTED,120);caption(56,589,305,MUTED,120);
    caption(flute_suona?48:47,165,356,flute_suona?MUTED:LIME,120);
    caption(flute_suona?47:48,589,356,flute_suona?ORANGE:MUTED,120);
    if(px>=135&&px<963&&py>=430&&py<514)paint=PANEL;
    caption(49,155,446,WHITE,120);caption(50,315,446,CYAN,144);caption(51,559,446,ORANGE,144);
    caption(58,155,482,MUTED,480);
   end
   // Touch-friendly song selector uses the controller's exact popup bounds.
   if(menu_open&&(page==2||page==5))begin
    left=page==2?119:250;right=page==2?632:623;top=page==2?151:56;bot=page==2?227:132;
    if(px>=left&&px<right&&py>=top&&py<bot)begin
     paint=PANEL;text_kind=0;
     for(i=0;i<2;i=i+1)begin
      if(py>=top+i*38&&py<top+(i+1)*38)paint=piece==i?24'h16405a:PANEL;
      caption(i+1,left+16,top+i*38+11,piece==i?LIME:WHITE,180);
     end
    end
   end
  end else begin paint=0;text_kind=0;end
 end
 // Four clocks after the artwork/predecode: request, glyph selection,
 // synchronous ROM, RGB. Total DE/HS/VS/RGB latency is ten clocks.
 reg [23:0] color_a,color_b,color_c,ink_a,ink_b,ink_c;
 reg [2:0] kind_a;reg [10:0] value_a;reg [9:0] dx_a;reg [4:0] dy_a;
 reg large_a;reg [2:0] digits_a;reg [3:0] col_b,col_c;
 reg enable_b,enable_c;reg [11:0] font_addr;wire [15:0] font_data;
 reg da,ha,va,db,hb,vb,dc,hc,vc;
 reg [7:0] glyph;reg [6:0] char_index;reg [9:0] sx;reg [3:0] sy,fc,decimal_digit;
 reg valid_glyph;
 always @*begin
  sx=large_a?dx_a>>1:dx_a;sy=large_a?dy_a>>1:dy_a;
  char_index=kind_a==1?sx/12:sx>>3;fc=kind_a==1?sx%12:sx[2:0];
  glyph=0;valid_glyph=kind_a!=0;decimal_digit=0;
  case(kind_a)
   1:glyph=ui_string_char(value_a[5:0],char_index[5:0]);
   2:begin
    if(char_index+1==digits_a)decimal_digit=value_a%10;
    else if(char_index+2==digits_a)decimal_digit=(value_a/10)%10;else if(char_index+3==digits_a)decimal_digit=(value_a/100)%10;else decimal_digit=value_a/1000;
    glyph=ui_ascii(8'd48+decimal_digit);
    if((char_index+2==digits_a&&value_a<10)||(char_index+3==digits_a&&value_a<100)||(char_index+4==digits_a&&value_a<1000))valid_glyph=0;
   end
   3:glyph=ui_note_char(value_a[4:0],octave_group,char_index[1:0]);
   4:glyph=ui_ascii(value_a);
   default:valid_glyph=0;
  endcase
 end
 ui_font_rom font(.clk(pixel_clk),.addr(font_addr),.data(font_data));
 always @(posedge pixel_clk)begin
  color_a<=paint;ink_a<=ink;kind_a<=text_kind;value_a<=text_value;dx_a<=text_dx;dy_a<=text_dy;
  large_a<=text_large;digits_a<=text_digits;da<=pd;ha<=ph;va<=pv;
  font_addr<={glyph,sy};col_b<=fc;enable_b<=valid_glyph;color_b<=color_a;ink_b<=ink_a;db<=da;hb<=ha;vb<=va;
  col_c<=col_b;enable_c<=enable_b;color_c<=color_b;ink_c<=ink_b;dc<=db;hc<=hb;vc<=vb;
  rgb<=dc?(enable_c&&font_data[15-col_c]?ink_c:color_c):24'b0;out_de<=dc;out_hs<=hc;out_vs<=vc;
  if(reset)begin da<=0;db<=0;dc<=0;ha<=0;hb<=0;hc<=0;va<=0;vb<=0;vc<=0;out_de<=0;out_hs<=0;out_vs<=0;rgb<=0;end
 end
endmodule
