`timescale 1ns/1ps
module ui_controller_v2(
 input wire clk,rst_n,touch_update,input wire [9:0] contact_down,
 input wire [99:0] contact_x,contact_y,input wire [59:0] contact_id,
 input wire [1:0] guide_piece,
 input wire parameter_sync_enable,input wire [255:0] parameter_values,
 output wire parameter_valid,output reg [15:0] parameter_id,parameter_value,
 input wire parameter_ready,parameter_ack,
 output reg [2:0] page,output reg [1:0] octave_group,
 output reg [6:0] master_volume,piano_volume,
 output reg panic,output reg [31:0] desired_keys,
 output reg [3:0] touch_count,
 output reg [2:0] guide_action,output reg [1:0] guide_arg,
 output reg muted,output reg [2:0] fx_enabled,output reg [62:0] fx_values,
 output reg lissa_run,output reg [1:0] lissa_delay,
 output reg menu_open,flute_suona
);
 `include "src/ui_v2_layout.vh"
 `include "src/ui_wind_layout.vh"
 reg [3:0] state;
 reg [255:0] parameter_base,parameter_draft;reg [15:0] parameter_dirty;
 integer pi,pick;
 wire [62:0] authoritative_fx={parameter_values[240+:7],parameter_values[224+:7],parameter_values[208+:7],parameter_values[176+:7],parameter_values[160+:7],parameter_values[144+:7],parameter_values[112+:7],parameter_values[96+:7],parameter_values[80+:7]};
 wire [2:0] authoritative_enabled={parameter_values[192],parameter_values[128],parameter_values[64]};
 function [15:0] id_at(input integer n);begin if(n<4)id_at=n+1;else if(n<8)id_at=n+12;else if(n<12)id_at=n+24;else id_at=n+36;end endfunction
 always @*begin
  pick=0;for(integer k=15;k>=0;k=k-1)if(parameter_dirty[k])pick=k;
  parameter_id=id_at(pick);parameter_value=parameter_draft[pick*16+:16];
 end
 assign parameter_valid=parameter_sync_enable&&state==7&&parameter_dirty!=0;

 reg [3:0] slot,count;reg [9:0] downs;reg [99:0] xs,ys;reg [59:0] ids;
 reg [63:0] previous_ids,current_ids;reg inhibit;
 reg [2:0] wp,wa;reg [1:0] wg,warg;reg [6:0] wm,wk;reg wmenu,wpanic;
 reg [31:0] wkeys;reg [11:0] captures,wcaptures;reg [5:0] owners[0:11],wowners[0:11];
 reg wflute_suona;
 reg wmuted,wrun;reg [1:0] wdelay;reg [2:0] wenabled;reg [62:0] wvalues;
 integer fi,fc,fr,fxleft,fxrow;
 reg [9:0] tx,ty;reg [5:0] cid,key;reg down,fresh;integer j;
 reg [6:0] volume_slider,fx_slider0,fx_slider1,fx_slider2;
 wire [5:0] slot_id=ids[slot*6+:6];
 always @(posedge clk)begin
  panic<=0;guide_action<=0;
  if(!rst_n)begin
   parameter_base<=0;parameter_draft<=0;parameter_dirty<=0;
   state<=0;slot<=0;downs<=0;xs<=0;ys<=0;ids<=0;count<=0;
   previous_ids<=0;current_ids<=0;inhibit<=0;captures<=0;wcaptures<=0;
   flute_suona<=0;wflute_suona<=0;
   page<=0;octave_group<=2;master_volume<=127;piano_volume<=127;
   muted<=0;lissa_run<=1;lissa_delay<=2;fx_enabled<=0;fx_values<={7'd38,7'd51,7'd18,7'd38,7'd49,7'd40,7'd32,7'd42,7'd70};
   desired_keys<=0;touch_count<=0;guide_arg<=0;menu_open<=0;
   wp<=0;wg<=2;wm<=127;wk<=127;wa<=0;warg<=0;wmenu<=0;wpanic<=0;wkeys<=0;
   tx<=0;ty<=0;cid<=0;key<=63;down<=0;fresh<=0;
   for(j=0;j<12;j=j+1)begin owners[j]<=0;wowners[j]<=0;end
  end else case(state)
   0:begin
    if(parameter_sync_enable)begin
     master_volume<=parameter_values[0+:7];piano_volume<=parameter_values[16+:7];muted<=parameter_values[32];octave_group<=parameter_values[48+:2];fx_enabled<=authoritative_enabled;fx_values<=authoritative_fx;
     if(octave_group!=parameter_values[48+:2])begin desired_keys<=0;inhibit<=1;captures<=0;end
    end
    if(touch_update)begin downs<=contact_down;xs<=contact_x;ys<=contact_y;ids<=contact_id;slot<=0;count<=0;current_ids<=0;state<=1;end end
   1:begin if(downs[slot])begin current_ids[slot_id]<=1;count<=count+1'b1;end if(slot==9)state<=2;else slot<=slot+1'b1;end
   2:begin
    parameter_base<=parameter_values;wflute_suona<=flute_suona;
    wmuted<=parameter_sync_enable?parameter_values[32]:muted;wrun<=lissa_run;wdelay<=lissa_delay;wenabled<=parameter_sync_enable?authoritative_enabled:fx_enabled;wvalues<=parameter_sync_enable?authoritative_fx:fx_values;
    wp<=page;wg<=parameter_sync_enable?parameter_values[48+:2]:octave_group;wm<=parameter_sync_enable?parameter_values[0+:7]:master_volume;wk<=parameter_sync_enable?parameter_values[16+:7]:piano_volume;wa<=0;warg<=0;wmenu<=menu_open;wpanic<=0;wkeys<=0;
    for(j=0;j<12;j=j+1)begin wcaptures[j]<=captures[j]&&current_ids[owners[j]];wowners[j]<=owners[j];end
    slot<=0;state<=3;
   end
   3:begin tx<=xs[slot*10+:10];ty<=ys[slot*10+:10];cid<=slot_id;down<=downs[slot];fresh<=downs[slot]&&!previous_ids[slot_id];state<=4;end
   4:begin
    key<=ui_v2_key_at(page,guide_piece,tx,ty);
    volume_slider<=ui_v2_slider(tx);
    fx_slider0<=tx<129?0:ui_fx_slider(tx-10'd129);
    fx_slider1<=tx<432?0:ui_fx_slider(tx-10'd432);
    fx_slider2<=tx<735?0:ui_fx_slider(tx-10'd735);state<=5;
   end
   5:begin
    if(down)begin
     if(fresh)begin
      if(page!=5&&tx>=8&&tx<71)begin
       // Tone always opens the register tab; page 3 is phone + recording UI only.
       if(ty>=106&&ty<171)wp<=0;else if(ty>=179&&ty<244)wp<=1;else if(ty>=252&&ty<317)wp<=2;else if(ty>=325&&ty<390)wp<=3;else if(ty>=398&&ty<463)wp<=4;
       wmenu<=0;
      end else if(wmenu)begin
       wmenu<=0;
       if(page==2&&tx>=119&&tx<632&&ty>=151&&ty<227)begin wa<=3;warg<=ty<189?0:1;end
       if(page==5&&tx>=250&&tx<623&&ty>=56&&ty<132)begin wa<=3;warg<=ty<94?0:1;end
      end else if(page==0)begin
       if(tx>=725&&tx<869&&ty>=493&&ty<537)wp<=3;
       if(tx>=877&&tx<985&&ty>=493&&ty<537)wmuted<=!wmuted;
       if(tx>=895&&tx<947&&ty>=103&&ty<135)wdelay<=wdelay+1'b1;
       if(tx>=953&&tx<985&&ty>=103&&ty<135)wrun<=!wrun;
       if(tx>=807&&tx<943)begin
        if(ty>=385&&ty<421&&!wcaptures[0])begin wcaptures[0]<=1;wowners[0]<=cid;wm<=volume_slider;end
        if(ty>=421&&ty<457&&!wcaptures[1])begin wcaptures[1]<=1;wowners[1]<=cid;wk<=volume_slider;end
       end
      end else if(page==1||page==6||page==7)begin
       if(ty>=92&&ty<136)begin
        if(tx>=108&&tx<238)wp<=1;
        if(tx>=242&&tx<372)wp<=6;
        if(tx>=WIND_TAB_L&&tx<WIND_TAB_R)wp<=7;
       end
       if(page==1&&ty>=271&&ty<315)begin
        if(tx>=123&&tx<332)wg<=0;else if(tx>=340&&tx<548)wg<=1;else if(tx>=556&&tx<765)wg<=2;else if(tx>=773&&tx<981)wg<=3;
       end
       if(page==7&&ty>=WIND_CARD_T&&ty<WIND_CARD_B)begin
        if(tx>=WIND_FLUTE_L&&tx<WIND_FLUTE_R)wflute_suona<=0;
        else if(tx>=WIND_SUONA_L&&tx<WIND_SUONA_R)wflute_suona<=1;
       end
     if(page==6)for(fc=0;fc<3;fc=fc+1)begin
        fxleft=fc==0?129:fc==1?432:735;
        if(tx>=fxleft+173&&tx<fxleft+251&&ty>=161&&ty<205)wenabled[fc]<=!wenabled[fc];
        if(wenabled[fc])for(fr=0;fr<3;fr=fr+1)begin
         fi=3+fc*3+fr;fxrow=364+fr*50;
         if(tx>=fxleft-10&&tx<fxleft+251&&ty>=fxrow&&ty<fxrow+32&&!wcaptures[fi])begin
          wcaptures[fi]<=1;wowners[fi]<=cid;wvalues[(fi-3)*7+:7]<=fi<6?fx_slider0:fi<9?fx_slider1:fx_slider2;
         end
        end
       end
      end else if(page==2)begin
       if(tx>=119&&tx<632&&ty>=103&&ty<147)wmenu<=1;
       if(tx>=648&&tx<736&&ty>=107&&ty<143)begin wa<=4;warg<=0;end
       if(tx>=739&&tx<815&&ty>=107&&ty<143)begin wa<=4;warg<=1;end
       if(tx>=831&&tx<869&&ty>=105&&ty<145)wa<=5;
       if(tx>=947&&tx<985&&ty>=105&&ty<145)wa<=6;
       if(ty>=492&&ty<536)begin
        if(tx>=119&&tx<231)wa<=1;else if(tx>=239&&tx<293)wa<=2;
        else if(octave_group!=2&&guide_piece!=2&&tx>=301&&tx<395)wg<=2;
        else if(guide_piece<2&&tx>=(octave_group==2?301:403)&&tx<(octave_group==2?403:505))wp<=5;
       end
      end else if(page==5)begin
       if(tx>=24&&tx<64&&ty>=16&&ty<56)wp<=2;
       if(tx>=250&&tx<623&&ty>=17&&ty<55)wmenu<=1;
       if(tx>=643&&tx<725&&ty>=20&&ty<52)begin wa<=4;warg<=0;end
       if(tx>=728&&tx<810&&ty>=20&&ty<52)begin wa<=4;warg<=1;end
       if(ty>=556&&ty<592)begin
        if(tx>=24&&tx<132)begin if(octave_group!=2)wg<=2;else wa<=1;end
        else if(tx>=144&&tx<180)wa<=2;else if(tx>=196&&tx<226)wa<=5;else if(tx>=299&&tx<329)wa<=6;
       end
      end
     end
     if(page==0)begin
      if(wcaptures[0]&&cid==wowners[0])wm<=volume_slider;
      if(wcaptures[1]&&cid==wowners[1])wk<=volume_slider;
     end
     if(page==6)for(fi=3;fi<12;fi=fi+1)begin
      fxleft=fi<6?129:fi<9?432:735;
      if(wcaptures[fi]&&cid==wowners[fi]&&wenabled[(fi-3)/3])wvalues[(fi-3)*7+:7]<=fi<6?fx_slider0:fi<9?fx_slider1:fx_slider2;
     end
     if(!menu_open&&!wmenu&&!inhibit)begin
      if(key<32&&!(octave_group==0&&key<7))wkeys[key]<=1;
     end
    end
    if(slot==9)state<=6;else begin slot<=slot+1'b1;state<=3;end
   end
   6:begin
    parameter_draft<=parameter_base;
    parameter_draft[0+:16]<={9'b0,wm};parameter_draft[16+:16]<={9'b0,wk};parameter_draft[32+:16]<={15'b0,wmuted};parameter_draft[48+:16]<={14'b0,wg};
    parameter_draft[64+:16]<={15'b0,wenabled[0]};parameter_draft[128+:16]<={15'b0,wenabled[1]};parameter_draft[192+:16]<={15'b0,wenabled[2]};
    for(pi=0;pi<3;pi=pi+1)begin
     parameter_draft[(pi+5)*16+:16]<={9'b0,wvalues[pi*7+:7]};
     parameter_draft[(pi+9)*16+:16]<={9'b0,wvalues[(pi+3)*7+:7]};
     parameter_draft[(pi+13)*16+:16]<={9'b0,wvalues[(pi+6)*7+:7]};
    end
    flute_suona<=wflute_suona;
    muted<=wmuted;lissa_run<=wrun;lissa_delay<=wdelay;fx_enabled<=wenabled;fx_values<=wvalues;
    page<=wp;octave_group<=wg;master_volume<=wm;piano_volume<=wk;panic<=wpanic;menu_open<=wmenu;
    guide_action<=wa;guide_arg<=warg;touch_count<=count;previous_ids<=current_ids;
    inhibit<=(inhibit&&downs!=0)||wp!=page||wg!=octave_group||wmenu!=menu_open||wpanic;
    desired_keys<=((inhibit&&downs!=0)||wp!=page||wg!=octave_group||wmenu||wmenu!=menu_open||wpanic)?0:wkeys;
    captures<=(wp==0||wp==6)&&wp==page?wcaptures:0;for(j=0;j<12;j=j+1)owners[j]<=wowners[j];state<=parameter_sync_enable?9:0;
   end
   9:begin
    for(pi=0;pi<16;pi=pi+1)parameter_dirty[pi]<=parameter_draft[pi*16+:16]!=parameter_base[pi*16+:16];
    state<=7;
   end
   7:if(parameter_dirty==0)state<=0;else if(parameter_ready)begin parameter_dirty[pick]<=0;state<=8;end
   8:if(parameter_ack)state<=7;
   default:state<=0;
  endcase
 end
endmodule
