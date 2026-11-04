`timescale 1ns/1ps
module studio_controller(
 input wire panel_valid,input wire [3:0] panel_code,output wire panel_ready,input wire drum_bank,
 input wire clk,rst_n,touch_update,remote_practice,input wire [9:0] contact_down,
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
 output reg menu_open,flute_suona,piano_house,
 input wire [3:0] rec_state,input wire rec_ready,rec_lease,rec_selected,rec_erase_accepted,input wire [31:0] rec_take,
 output reg rec_start,rec_stop,rec_erase,play_start,play_stop,slot_valid,slot_value,
 output reg [1:0] rec_confirm,output reg about_open,
 output reg [6:0] drum_volume,flute_volume,output reg bank_set,bank_value,output reg drum_recalibrate
) /* synthesis syn_romstyle="logic" */;
 `include "src/ui_v2_layout.vh"
 `include "src/studio_keys.vh"
 reg [3:0] state;
 reg [255:0] parameter_base,parameter_draft;reg [15:0] parameter_dirty;
 reg [3:0] parameter_pick;
 integer pi,pick;
 wire [62:0] authoritative_fx={parameter_values[240+:7],parameter_values[224+:7],parameter_values[208+:7],parameter_values[176+:7],parameter_values[160+:7],parameter_values[144+:7],parameter_values[112+:7],parameter_values[96+:7],parameter_values[80+:7]};
 wire [2:0] authoritative_enabled={parameter_values[192],parameter_values[128],parameter_values[64]};
 function [15:0] id_at(input integer n);begin if(n<4)id_at=n+1;else if(n<8)id_at=n+12;else if(n<12)id_at=n+24;else id_at=n+36;end endfunction
 always @*begin
  pick=0;for(integer k=15;k>=0;k=k-1)if(parameter_dirty[k])pick=k;
 end
 assign parameter_valid=parameter_sync_enable&&state==7&&parameter_dirty!=0;

 reg [3:0] slot,count;reg [9:0] downs;reg [99:0] xs,ys;reg [59:0] ids;
 reg [63:0] previous_ids,current_ids;reg inhibit;
 reg [2:0] wp,wa;reg [1:0] wg,warg;reg [6:0] wm,wk;reg wmenu,wpanic;
 reg [31:0] wkeys;reg [15:0] captures,wcaptures;reg [5:0] owners[0:15],wowners[0:15];
 reg wflute_suona;reg [6:0] wd,wf;reg [31:0] confirm_take;reg pending_record,overwrite_intent,intent_slot;
 reg wmuted,wrun;reg [1:0] wdelay;reg [2:0] wenabled;reg [62:0] wvalues;
 integer fi,fc,fr,fxleft,fxrow;
 reg [9:0] tx,ty;reg [5:0] cid,key;reg down,fresh;integer j;
 reg [6:0] volume_slider,piano_slider,drum_slider,flute_slider,fx_slider0,fx_slider1,fx_slider2;
 `include "src/studio_slider.vh"
 wire [5:0] slot_id=ids[slot*6+:6];
 assign panel_ready=state==0&&!remote_practice;
 function [6:0] panel_level(input [6:0] level,input decrease);
  begin panel_level=decrease?(level<4?0:level-7'd4):(level>123?127:level+7'd4);end
 endfunction
 always @(posedge clk)begin
  panic<=0;guide_action<=0;
  rec_start<=0;rec_stop<=0;rec_erase<=0;play_start<=0;play_stop<=0;slot_valid<=0;bank_set<=0;drum_recalibrate<=0;
  if(rst_n&&pending_record)begin
   if(rec_take!=confirm_take||rec_selected!=intent_slot)pending_record<=0;
   else if(rec_state==2&&rec_ready&&!rec_lease)begin rec_start<=1;pending_record<=0;end
  end
  if(rst_n&&rec_erase)begin
   if(rec_erase_accepted&&overwrite_intent&&rec_take==confirm_take&&rec_selected==intent_slot)pending_record<=1;
   overwrite_intent<=0;
  end
  if(rst_n&&rec_take!=confirm_take)rec_confirm<=0;
  if(!rst_n)begin
   parameter_base<=0;parameter_draft<=0;parameter_dirty<=0;
   parameter_pick<=0;parameter_id<=0;parameter_value<=0;
   rec_confirm<=0;confirm_take<=0;pending_record<=0;overwrite_intent<=0;intent_slot<=0;about_open<=0;slot_value<=0;
   bank_value<=0;drum_volume<=127;flute_volume<=127;wd<=127;wf<=127;
   state<=0;slot<=0;downs<=0;xs<=0;ys<=0;ids<=0;count<=0;
   previous_ids<=0;current_ids<=0;inhibit<=0;captures<=0;wcaptures<=0;
   flute_suona<=0;wflute_suona<=0;piano_house<=0;
   page<=0;octave_group<=2;master_volume<=127;piano_volume<=127;
   muted<=0;lissa_run<=1;lissa_delay<=2;fx_enabled<=0;fx_values<={7'd38,7'd51,7'd18,7'd38,7'd49,7'd40,7'd32,7'd42,7'd70};
   desired_keys<=0;touch_count<=0;guide_arg<=0;menu_open<=0;
   wp<=0;wg<=2;wm<=127;wk<=127;wa<=0;warg<=0;wmenu<=0;wpanic<=0;wkeys<=0;
   tx<=0;ty<=0;cid<=0;key<=63;down<=0;fresh<=0;
   for(j=0;j<16;j=j+1)begin owners[j]<=0;wowners[j]<=0;end
  end else if(remote_practice)begin page<=2;wp<=2;state<=0;desired_keys<=0;menu_open<=0;inhibit<=1;end
  else case(state)
   0:begin
    if(parameter_sync_enable)begin
     master_volume<=parameter_values[0+:7];piano_volume<=parameter_values[16+:7];muted<=parameter_values[32];octave_group<=parameter_values[48+:2];fx_enabled<=authoritative_enabled;fx_values<=authoritative_fx;
     if(octave_group!=parameter_values[48+:2])begin desired_keys<=0;inhibit<=1;captures<=0;end
    end
    if(panel_valid===1'b1)begin
     // Use the same acknowledged parameter path as touch and phone controls.
     // Only changed fields are submitted; unrelated phone settings stay intact.
     parameter_base<=parameter_values;parameter_draft<=parameter_values;
     case(panel_code)
      0,1:begin
       parameter_draft[16+:16]<={9'd0,panel_level(parameter_values[16+:7],panel_code[0])};
       if(parameter_sync_enable)state<=9;else piano_volume<=panel_level(piano_volume,panel_code[0]);
      end
      2,3:flute_volume<=panel_level(flute_volume,panel_code[0]);
      4,5:drum_volume<=panel_level(drum_volume,panel_code[0]);
      6,7:begin
       if(panel_code==6)begin
        if(parameter_values[48+:2]!=3)parameter_draft[48+:16]<={14'd0,parameter_values[48+:2]+2'd1};
        if(!parameter_sync_enable&&octave_group!=3)octave_group<=octave_group+1'b1;
       end else begin
        if(parameter_values[48+:2]!=0)parameter_draft[48+:16]<={14'd0,parameter_values[48+:2]-2'd1};
        if(!parameter_sync_enable&&octave_group!=0)octave_group<=octave_group-1'b1;
       end
       desired_keys<=0;captures<=0;inhibit<=1;
       if(parameter_sync_enable)state<=9;
      end
      8:begin bank_set<=1;bank_value<=!drum_bank;end
      9:flute_suona<=!flute_suona;
      default:begin end
     endcase
    end else if(touch_update)begin downs<=contact_down;xs<=contact_x;ys<=contact_y;ids<=contact_id;slot<=0;count<=0;current_ids<=0;state<=1;end end
   1:begin if(downs[slot])begin current_ids[slot_id]<=1;count<=count+1'b1;end if(slot==9)state<=2;else slot<=slot+1'b1;end
   2:begin
    parameter_base<=parameter_values;wflute_suona<=flute_suona;wd<=drum_volume;wf<=flute_volume;
    wmuted<=parameter_sync_enable?parameter_values[32]:muted;wrun<=lissa_run;wdelay<=lissa_delay;wenabled<=parameter_sync_enable?authoritative_enabled:fx_enabled;wvalues<=parameter_sync_enable?authoritative_fx:fx_values;
    wp<=page;wg<=parameter_sync_enable?parameter_values[48+:2]:octave_group;wm<=parameter_sync_enable?parameter_values[0+:7]:master_volume;wk<=parameter_sync_enable?parameter_values[16+:7]:piano_volume;wa<=0;warg<=0;wmenu<=menu_open;wpanic<=0;wkeys<=0;
    for(j=0;j<16;j=j+1)begin wcaptures[j]<=captures[j]&&current_ids[owners[j]];wowners[j]<=owners[j];end
    slot<=0;state<=3;
   end
   3:begin tx<=xs[slot*10+:10];ty<=ys[slot*10+:10];cid<=slot_id;down<=downs[slot];fresh<=downs[slot]&&!previous_ids[slot_id];state<=4;end
   4:begin
    key<=studio_key(page,tx,ty);
    volume_slider<=slider(tx,40,128);piano_slider<=slider(tx,334,180);
    drum_slider<=slider(tx,566,180);flute_slider<=slider(tx,798,180);
    fx_slider0<=slider(tx,45,274);fx_slider1<=slider(tx,374,274);fx_slider2<=slider(tx,703,274);state<=5;
   end
   5:begin
    if(down)begin
     if(fresh)begin
      if(ty>=542&&ty<590)begin
       if(tx>=24&&tx<208)wp<=0;else if(tx>=222&&tx<406)wp<=1;
       else if(tx>=420&&tx<604)wp<=2;else if(tx>=618&&tx<802)wp<=3;else if(tx>=816&&tx<1000)wp<=4;
       wmenu<=0;about_open<=0;rec_confirm<=0;
      end else if(tx>=966&&ty>=14&&ty<58)about_open<=!about_open;
      else if(about_open)about_open<=0;
      else if(rec_confirm!=0)begin
       if(ty>=330&&ty<386)begin
        if(tx>=530&&tx<714&&rec_take==confirm_take&&rec_state==5&&rec_ready&&!rec_lease)begin
         rec_erase<=1;overwrite_intent<=rec_confirm==2;intent_slot<=rec_selected;rec_confirm<=0;
        end else if(tx>=310&&tx<494)rec_confirm<=0;
       end
      end else if(wmenu)begin
       wmenu<=0;
       if(tx>=53&&tx<269&&ty>=99&&ty<235)begin wa<=3;warg<=ty<167?0:1;end
      end else if(page==0)begin
       if(tx>=186&&tx<289&&ty>=478&&ty<522)wmuted<=!wmuted;
       if(tx>=311&&tx<367&&ty>=89&&ty<133)wdelay<=wdelay+1'b1;
       if(tx>=374&&tx<417&&ty>=89&&ty<133)wrun<=!wrun;
       if(ty>=480&&ty<523)begin
        if(tx>=30&&tx<180&&!wcaptures[0])begin wcaptures[0]<=1;wowners[0]<=cid;wm<=volume_slider;end
        if(tx>=324&&tx<528&&!wcaptures[1])begin wcaptures[1]<=1;wowners[1]<=cid;wk<=piano_slider;end
        if(tx>=556&&tx<760&&!wcaptures[2])begin wcaptures[2]<=1;wowners[2]<=cid;wd<=drum_slider;end
        if(tx>=788&&tx<992&&!wcaptures[3])begin wcaptures[3]<=1;wowners[3]<=cid;wf<=flute_slider;end
       end
      end else if(page==1||page==5||page==6||page==7)begin
       if(ty>=80&&ty<116)begin
        if(tx>=28&&tx<158)wp<=1;else if(tx>=162&&tx<292)wp<=7;
        else if(tx>=296&&tx<426)wp<=5;else if(tx>=430&&tx<560)wp<=6;
       end
       if(page==5&&tx>=175&&tx<265&&ty>=146&&ty<188)drum_recalibrate<=1;
       if(page==1&&tx>=720&&tx<980&&ty>=146&&ty<188)piano_house<=tx>=850;
       if(page==1&&tx>=43&&tx<263)begin
        if(ty>=185&&ty<229)wg<=0;else if(ty>=233&&ty<277)wg<=1;
        else if(ty>=281&&ty<325)wg<=2;else if(ty>=329&&ty<373)wg<=3;
       end
       if((page==7||page==5)&&tx>=45&&tx<305)begin
        if(ty>=199&&ty<348)begin
         if(page==7)wflute_suona<=0;else begin bank_set<=1;bank_value<=0;end
        end else if(ty>=362&&ty<511)begin
         if(page==7)wflute_suona<=1;else begin bank_set<=1;bank_value<=1;end
        end
       end
       if(page==6)for(fc=0;fc<3;fc=fc+1)begin
        fxleft=fc==0?45:fc==1?374:703;
        if(tx>=fxleft+166&&tx<fxleft+276&&ty>=151&&ty<195)wenabled[fc]<=!wenabled[fc];
        for(fr=0;fr<3;fr=fr+1)begin
         fi=4+fc*3+fr;fxrow=291+fr*87;
         if(tx>=fxleft&&tx<fxleft+276&&ty>=fxrow&&ty<fxrow+45&&!wcaptures[fi])begin
          wcaptures[fi]<=1;wowners[fi]<=cid;wvalues[(fi-4)*7+:7]<=fc==0?fx_slider0:fc==1?fx_slider1:fx_slider2;
         end
        end
       end
      end else if(page==2)begin
       if(tx>=53&&tx<269&&ty>=99&&ty<171)wmenu<=1;
       if(ty>=183&&ty<219)begin
        if(tx>=57&&tx<160)begin wa<=4;warg<=0;end
        else if(tx>=162&&tx<265)begin wa<=4;warg<=1;end
       end
       if(ty>=232&&ty<274)begin if(tx>=54&&tx<98)wa<=5;else if(tx>=224&&tx<268)wa<=6;end
       if(ty>=467&&ty<515)begin
        if(tx>=41&&tx<201)begin if(octave_group!=2)wg<=2;else wa<=1;end
        else if(tx>=211&&tx<299)wa<=2;
       end
      end else if(page==3)begin
       if(ty>=92&&ty<136&&!rec_lease&&rec_ready&&(rec_state==2||rec_state==5))begin
        if(tx>=680&&tx<824)begin slot_valid<=1;slot_value<=0;end
        else if(tx>=834&&tx<978)begin slot_valid<=1;slot_value<=1;end
       end
       if(ty>=269&&ty<320)begin
        if(tx>=378&&tx<566)begin
         if(rec_state==3)rec_stop<=1;
         else if(rec_ready&&!rec_lease&&rec_state==2)rec_start<=1;
         else if(rec_ready&&!rec_lease&&rec_state==5)begin rec_confirm<=2;confirm_take<=rec_take;end
        end else if(tx>=582&&tx<770)begin
         if(rec_state==6||rec_state==7)play_stop<=1;
         else if(rec_state==5&&rec_ready&&!rec_lease)play_start<=1;
        end else if(tx>=786&&tx<974&&rec_ready&&!rec_lease&&rec_state==5)begin rec_confirm<=1;confirm_take<=rec_take;end
       end
      end
     end
     if(page==0)begin
      if(wcaptures[0]&&cid==wowners[0])wm<=volume_slider;
      if(wcaptures[1]&&cid==wowners[1])wk<=piano_slider;
      if(wcaptures[2]&&cid==wowners[2])wd<=drum_slider;
      if(wcaptures[3]&&cid==wowners[3])wf<=flute_slider;
     end
     if(page==6)for(fi=4;fi<13;fi=fi+1)
      if(wcaptures[fi]&&cid==wowners[fi])wvalues[(fi-4)*7+:7]<=fi<7?fx_slider0:fi<10?fx_slider1:fx_slider2;
     if(!menu_open&&!wmenu&&!inhibit&&!about_open&&rec_confirm==0)
      if(key<32&&!(octave_group==0&&key<7))wkeys[key]<=1;
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
    flute_suona<=wflute_suona;drum_volume<=wd;flute_volume<=wf;
    muted<=wmuted;lissa_run<=wrun;lissa_delay<=wdelay;fx_enabled<=wenabled;fx_values<=wvalues;
    page<=wp;octave_group<=wg;master_volume<=wm;piano_volume<=wk;panic<=wpanic;menu_open<=wmenu;
    guide_action<=wa;guide_arg<=warg;touch_count<=count;previous_ids<=current_ids;
    inhibit<=(inhibit&&downs!=0)||wp!=page||wg!=octave_group||wmenu!=menu_open||wpanic;
    desired_keys<=((inhibit&&downs!=0)||wp!=page||wg!=octave_group||wmenu||wmenu!=menu_open||wpanic)?0:wkeys;
    captures<=(wp==0||wp==6)&&wp==page?wcaptures:0;for(j=0;j<16;j=j+1)owners[j]<=wowners[j];state<=parameter_sync_enable?9:0;
   end
   9:begin
    for(pi=0;pi<16;pi=pi+1)parameter_dirty[pi]<=parameter_draft[pi*16+:16]!=parameter_base[pi*16+:16];
    state<=10;
   end
   // Register the selected request before exposing VALID to the protocol.
   // The dirty priority/mux no longer shares a cycle with parameter validation.
   10:begin parameter_pick<=pick;parameter_id<=id_at(pick);parameter_value<=parameter_draft[pick*16+:16];state<=7;end
   7:if(parameter_dirty==0)state<=0;else if(parameter_ready)begin parameter_dirty[parameter_pick]<=0;state<=8;end
   8:if(parameter_ack)state<=10;
   default:state<=0;
  endcase
 end
endmodule
