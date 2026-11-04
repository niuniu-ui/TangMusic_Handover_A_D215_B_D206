`timescale 1ns/1ps
// 96 real additional DDS components: addresses {note[4:0], component[1:0]},
// component 0 is unused (the original 32-voice engine owns that component).
// All audio/state work uses the existing host clock. Three clocks per address
// plus guard/drain finish in 396 clocks for the original CE+1 launch timing.
// The wrapper reserves 512 clocks; overlapping sample strobes report a fault.
// State RAM is initialized serially and uses an explicit WRITE_FIRST template.
module air_drum_partial_bank(
 input wire clk,rst_n,sample_ce,note_launch,
 input wire [4:0] note_slot,input wire [18:0] note_data,
 input wire signed [7:0] bend,input wire [1:0] test_mode,
 output reg signed [23:0] pcm_sum,
 output reg pcm_valid,ready,output wire busy,
 output reg [6:0] active_count,output reg [31:0] note_tail_mask,
 output reg fault
);
 localparam BOOT=0,INITIALIZE=1,IDLE=2,GUARD=3,READ=4,BEND=5,WRITE=6,DRAIN=7;
 localparam OFF=0,ATTACK=1,DECAY=2,SUSTAIN=3,RELEASE=4;
 // phase32 / FCW32 / envelope16 / gate17 / ADSR3 / velocity8 / bank1 /
 // zone2 / fresh1. Each active component owns every one of these state fields.
 reg [111:0] state_ram[0:127] /* synthesis syn_ramstyle="block_ram" */;
 reg [111:0] state_q;
 reg [2:0] state;
 reg [6:0] initialize_index,cursor;
 reg [1:0] mode;
 reg [3:0] guard_count;
 reg signed [7:0] bend_snapshot;
 reg pending_note;reg [4:0] pending_slot;reg [18:0] pending_data;
 reg [1:0] pending_component;
 wire [1:0] component=cursor[1:0];
 wire [31:0] q_phase=state_q[31:0],q_step=state_q[63:32];
 wire [15:0] q_env=state_q[79:64];
 wire [16:0] q_gate=state_q[96:80];
 wire [2:0] q_stage=state_q[99:97];
 wire [7:0] q_gain=state_q[107:100];
 wire q_bank=state_q[108],q_fresh=state_q[111];
 wire [1:0] q_zone=state_q[110:109];
 assign busy=state>=GUARD;

 function [31:0] test_step;input [6:0] index;begin case(index)
    7'd0: test_step=32'd19351404;
    7'd1: test_step=32'd22605959;
    7'd2: test_step=32'd25860513;
    7'd3: test_step=32'd29115067;
    7'd4: test_step=32'd32369622;
    7'd5: test_step=32'd35624176;
    7'd6: test_step=32'd38878731;
    7'd7: test_step=32'd42133285;
    7'd8: test_step=32'd45387839;
    7'd9: test_step=32'd48642394;
    7'd10: test_step=32'd51896948;
    7'd11: test_step=32'd55151503;
    7'd12: test_step=32'd58406057;
    7'd13: test_step=32'd61660612;
    7'd14: test_step=32'd64915166;
    7'd15: test_step=32'd68169720;
    7'd16: test_step=32'd71424275;
    7'd17: test_step=32'd74678829;
    7'd18: test_step=32'd77933384;
    7'd19: test_step=32'd81187938;
    7'd20: test_step=32'd84442493;
    7'd21: test_step=32'd87697047;
    7'd22: test_step=32'd90951601;
    7'd23: test_step=32'd94206156;
    7'd24: test_step=32'd97460710;
    7'd25: test_step=32'd100715265;
    7'd26: test_step=32'd103969819;
    7'd27: test_step=32'd107224373;
    7'd28: test_step=32'd110478928;
    7'd29: test_step=32'd113733482;
    7'd30: test_step=32'd116988037;
    7'd31: test_step=32'd120242591;
    7'd32: test_step=32'd123497146;
    7'd33: test_step=32'd126751700;
    7'd34: test_step=32'd130006254;
    7'd35: test_step=32'd133260809;
    7'd36: test_step=32'd136515363;
    7'd37: test_step=32'd139769918;
    7'd38: test_step=32'd143024472;
    7'd39: test_step=32'd146279026;
    7'd40: test_step=32'd149533581;
    7'd41: test_step=32'd152788135;
    7'd42: test_step=32'd156042690;
    7'd43: test_step=32'd159297244;
    7'd44: test_step=32'd162551799;
    7'd45: test_step=32'd165806353;
    7'd46: test_step=32'd169060907;
    7'd47: test_step=32'd172315462;
    7'd48: test_step=32'd175570016;
    7'd49: test_step=32'd178824571;
    7'd50: test_step=32'd182079125;
    7'd51: test_step=32'd185333679;
    7'd52: test_step=32'd188588234;
    7'd53: test_step=32'd191842788;
    7'd54: test_step=32'd195097343;
    7'd55: test_step=32'd198351897;
    7'd56: test_step=32'd201606452;
    7'd57: test_step=32'd204861006;
    7'd58: test_step=32'd208115560;
    7'd59: test_step=32'd211370115;
    7'd60: test_step=32'd214624669;
    7'd61: test_step=32'd217879224;
    7'd62: test_step=32'd221133778;
    7'd63: test_step=32'd224388332;
    7'd64: test_step=32'd227642887;
    7'd65: test_step=32'd230897441;
    7'd66: test_step=32'd234151996;
    7'd67: test_step=32'd237406550;
    7'd68: test_step=32'd240661105;
    7'd69: test_step=32'd243915659;
    7'd70: test_step=32'd247170213;
    7'd71: test_step=32'd250424768;
    7'd72: test_step=32'd253679322;
    7'd73: test_step=32'd256933877;
    7'd74: test_step=32'd260188431;
    7'd75: test_step=32'd263442986;
    7'd76: test_step=32'd266697540;
    7'd77: test_step=32'd269952094;
    7'd78: test_step=32'd273206649;
    7'd79: test_step=32'd276461203;
    7'd80: test_step=32'd279715758;
    7'd81: test_step=32'd282970312;
    7'd82: test_step=32'd286224866;
    7'd83: test_step=32'd289479421;
    7'd84: test_step=32'd292733975;
    7'd85: test_step=32'd295988530;
    7'd86: test_step=32'd299243084;
    7'd87: test_step=32'd302497639;
    7'd88: test_step=32'd305752193;
    7'd89: test_step=32'd309006747;
    7'd90: test_step=32'd312261302;
    7'd91: test_step=32'd315515856;
    7'd92: test_step=32'd318770411;
    7'd93: test_step=32'd322024965;
    7'd94: test_step=32'd325279519;
    7'd95: test_step=32'd328534074;
    7'd96: test_step=32'd331788628;
    7'd97: test_step=32'd335043183;
    7'd98: test_step=32'd338297737;
    7'd99: test_step=32'd341552292;
    7'd100: test_step=32'd344806846;
    7'd101: test_step=32'd348061400;
    7'd102: test_step=32'd351315955;
    7'd103: test_step=32'd354570509;
    7'd104: test_step=32'd357825064;
    7'd105: test_step=32'd361079618;
    7'd106: test_step=32'd364334172;
    7'd107: test_step=32'd367588727;
    7'd108: test_step=32'd370843281;
    7'd109: test_step=32'd374097836;
    7'd110: test_step=32'd377352390;
    7'd111: test_step=32'd380606945;
    7'd112: test_step=32'd383861499;
    7'd113: test_step=32'd387116053;
    7'd114: test_step=32'd390370608;
    7'd115: test_step=32'd393625162;
    7'd116: test_step=32'd396879717;
    7'd117: test_step=32'd400134271;
    7'd118: test_step=32'd403388825;
    7'd119: test_step=32'd406643380;
    7'd120: test_step=32'd409897934;
    7'd121: test_step=32'd413152489;
    7'd122: test_step=32'd416407043;
    7'd123: test_step=32'd419661598;
    7'd124: test_step=32'd422916152;
    7'd125: test_step=32'd426170706;
    7'd126: test_step=32'd429425261;
    7'd127: test_step=32'd432679815;
    default:test_step=0;
 endcase end endfunction

 // Normal modal frequencies remain below 10.94 kHz even at maximum +25% bend.
 // They are independent phase accumulators, never extra reads of one phase.
 function [31:0] normal_step;input timbre;input [1:0] zone,part;begin
  case({timbre,zone,part})
    5'd1: normal_step=32'd7212796; // 82 Hz
    5'd2: normal_step=32'd12050647; // 137 Hz
    5'd3: normal_step=32'd19263443; // 219 Hz
    5'd5: normal_step=32'd23749451; // 270 Hz
    5'd6: normal_step=32'd35624176; // 405 Hz
    5'd7: normal_step=32'd47498902; // 540 Hz
    5'd9: normal_step=32'd307863255; // 3500 Hz
    5'd10: normal_step=32'd461794883; // 5250 Hz
    5'd11: normal_step=32'd769658139; // 8750 Hz
    5'd13: normal_step=32'd14513553; // 165 Hz
    5'd14: normal_step=32'd24189255; // 275 Hz
    5'd15: normal_step=32'd38702809; // 440 Hz
    5'd17: normal_step=32'd34568645; // 393 Hz
    5'd18: normal_step=32'd48378511; // 550 Hz
    5'd19: normal_step=32'd64563322; // 734 Hz
    5'd21: normal_step=32'd43540660; // 495 Hz
    5'd22: normal_step=32'd60956924; // 693 Hz
    5'd23: normal_step=32'd81275899; // 924 Hz
    5'd25: normal_step=32'd51721026; // 588 Hz
    5'd26: normal_step=32'd72391845; // 823 Hz
    5'd27: normal_step=32'd96581101; // 1098 Hz
    5'd29: normal_step=32'd68961369; // 784 Hz
    5'd30: normal_step=32'd96581101; // 1098 Hz
    5'd31: normal_step=32'd128774801; // 1464 Hz
    default:normal_step=0;
  endcase
 end endfunction

 function [111:0] initialized_word;
  input [6:0] address;input [1:0] requested_mode;
  reg [111:0] value;reg [6:0] ordinal;begin
   value=0;ordinal=address[6:2]*3+address[1:0]-1;
   if(address[1:0]!=0&&(requested_mode==3||(requested_mode==2&&ordinal<32)))begin
    value[63:32]=test_step(ordinal+7'd32);value[79:64]=16'hffff;
    value[99:97]=SUSTAIN;value[107:100]=8'hff;
   end
   initialized_word=value;
  end
 endfunction
 function [111:0] note_word;
  input [18:0] data;input [1:0] part;
  reg [111:0] value;reg [16:0] gate_length;begin
   value=0;
   gate_length=data[18]?(17'd12000+{data[17:10],6'b0}):(17'd1600+{data[17:10],4'b0});
   if(part==2)gate_length=gate_length-(gate_length>>3);
   else if(part==3)gate_length=gate_length-(gate_length>>2);
   value[63:32]=normal_step(data[18],data[9:8],part);
   value[96:80]=gate_length;value[99:97]=ATTACK;
   value[107:100]=data[7:0];value[108]=data[18];value[110:109]=data[9:8];
   // A launch normally arrives one cycle after this sample's strobe. Do not
   // advance a freshly initialized component one sample before the old engine.
   value[111]=1'b1;note_word=value;
  end
 endfunction
 function signed [12:0] sine;input [6:0] address;
  reg [4:0] x;reg signed [12:0] value;begin
   x=address[5]?~address[4:0]:address[4:0];
   case(x)
    0:value=0;1:value=101;2:value=201;3:value=300;4:value=399;5:value=497;
    6:value=594;7:value=689;8:value=783;9:value=874;10:value=965;11:value=1052;
    12:value=1137;13:value=1219;14:value=1298;15:value=1375;16:value=1448;
    17:value=1517;18:value=1583;19:value=1645;20:value=1703;21:value=1757;
    22:value=1806;23:value=1851;24:value=1892;25:value=1927;26:value=1959;
    27:value=1985;28:value=2008;29:value=2025;30:value=2037;default:value=2045;
   endcase
   sine=address[6]?-value:value;
  end
 endfunction
 function [15:0] attack_rate;input timbre;input [1:0] part;begin
  attack_rate=timbre?(part==1?1024:part==2?768:512):(part==1?4096:part==2?2048:1024);
 end endfunction
 function [15:0] decay_rate;input timbre;input [1:0] zone,part;begin
  decay_rate=timbre?(part==1?12:part==2?18:24):zone==2?(part==1?128:part==2?160:192):(part==1?32:part==2?40:48);
 end endfunction
 function [15:0] sustain_level;input timbre;input [1:0] part;begin
  sustain_level=timbre?(part==1?12288:part==2?8192:4096):(part==1?4096:part==2?2048:1024);
 end endfunction
 function [15:0] release_rate;input timbre;input [1:0] zone,part;begin
  release_rate=timbre?(part==1?8:part==2?12:16):zone==2?(part==1?64:part==2?96:128):(part==1?16:part==2?24:32);
 end endfunction

 reg [15:0] env_advanced;reg [16:0] gate_advanced;reg [2:0] stage_advanced;
 reg [15:0] a,d,s,r;
 always @*begin
  env_advanced=q_env;gate_advanced=q_gate;stage_advanced=q_stage;
  a=attack_rate(q_bank,component);d=decay_rate(q_bank,q_zone,component);
  s=sustain_level(q_bank,component);r=release_rate(q_bank,q_zone,component);
  if(component!=0&&!q_fresh&&mode==0)begin
   if(q_gate!=0)gate_advanced=q_gate-1'b1;
   case(q_stage)
    ATTACK:if(q_env>=16'hffff-a)begin env_advanced=16'hffff;stage_advanced=DECAY;end
           else env_advanced=q_env+a;
    DECAY:if(q_env<=s+d)begin env_advanced=s;stage_advanced=SUSTAIN;end
          else env_advanced=q_env-d;
    SUSTAIN:env_advanced=s;
    RELEASE:if(q_env<=r)begin env_advanced=0;stage_advanced=OFF;end
            else env_advanced=q_env-r;
    default:env_advanced=0;
   endcase
   if(q_gate==1&&q_stage!=OFF)stage_advanced=RELEASE;
  end
 end
 reg [31:0] phase_base;
 reg signed [32:0] bend_product;
 reg [15:0] env_write;reg [16:0] gate_write;reg [2:0] stage_write;
 reg [23:0] gain_envelope;
 wire eligible=component!=0&&!q_fresh&&q_stage!=OFF&&q_gain!=0&&
  gain_envelope>=(mode!=0?24'd32833:component==1?24'd32816:24'd65632);
 wire signed [12:0] waveform=eligible?(mode==0?sine(q_phase[31:25]):(sine(q_phase[31:25])>>>2)):13'sd0;
 wire applying_note=pending_note&&(state==IDLE||state==GUARD)&&mode==0;
 reg ram_write;reg [6:0] ram_address;reg [111:0] ram_value;
 always @*begin
  ram_write=0;ram_address=cursor;ram_value=state_q;
  if(state==INITIALIZE)begin ram_write=1;ram_address=initialize_index;ram_value=initialized_word(initialize_index,mode);end
  else if(applying_note)begin ram_write=1;ram_address={pending_slot,pending_component};ram_value=note_word(pending_data,pending_component);end
  else if(state==WRITE)begin
   ram_write=1;
   ram_value[31:0]=phase_base+bend_product[31:0];
   ram_value[79:64]=env_write;ram_value[96:80]=gate_write;
   ram_value[99:97]=stage_write;ram_value[111]=0;
  end
 end
 // GW5AST WRITE_FIRST, one physical state-RAM port. No async array reset,
 // no simultaneous unrelated event write and per-sample state write.
 always @(posedge clk)begin
  if(ram_write)begin state_ram[ram_address]<=ram_value;state_q<=ram_value;end
  else if(state==READ)state_q<=state_ram[cursor];
 end

 reg [2:0] valid_pipe,last_pipe;
 reg [1:0] weight1,weight2,weight3;
 reg signed [21:0] velocity_product;
 reg [15:0] env1;
 reg signed [38:0] envelope_product;
 reg signed [15:0] voice_value;
 reg signed [23:0] accumulator;
 reg [6:0] active_work;reg [31:0] tail_work;
 wire issue=state==WRITE;
 function signed [23:0] weighted_value;input signed [15:0] value;input [1:0] shift;
  reg signed [23:0] wide;begin
   wide={{8{value[15]}},value};
   weighted_value=wide<0?-((-wide)>>>shift):(wide>>>shift);
  end
 endfunction
 wire signed [23:0] total=accumulator+weighted_value(voice_value,weight3);

 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=BOOT;initialize_index<=0;cursor<=0;mode<=0;guard_count<=0;bend_snapshot<=0;
   pending_note<=0;pending_slot<=0;pending_data<=0;pending_component<=1;
   phase_base<=0;bend_product<=0;env_write<=0;gate_write<=0;stage_write<=0;gain_envelope<=0;
   valid_pipe<=0;last_pipe<=0;weight1<=0;weight2<=0;weight3<=0;
   velocity_product<=0;env1<=0;envelope_product<=0;voice_value<=0;
   accumulator<=0;active_work<=0;tail_work<=0;
   pcm_sum<=0;pcm_valid<=0;ready<=0;active_count<=0;note_tail_mask<=0;fault<=0;
  end else begin
   pcm_valid<=0;
   valid_pipe<={valid_pipe[1:0],issue};
   last_pipe<={last_pipe[1:0],issue&&cursor==127};
   if(issue)begin
    velocity_product<=waveform*$signed({1'b0,q_gain});env1<=q_env;
    weight1<=mode==0?(component==1?2:3):0;
    if(eligible)begin active_work<=active_work+1'b1;if(mode==0)tail_work[cursor[6:2]]<=1'b1;end
   end
   if(valid_pipe[0])begin envelope_product<=velocity_product*$signed({1'b0,env1});weight2<=weight1;end
   if(valid_pipe[1])begin voice_value<=envelope_product>>>24;weight3<=weight2;end
   if(valid_pipe[2])begin
    accumulator<=total;
    if(last_pipe[2])begin
     pcm_sum<=total;pcm_valid<=1;active_count<=active_work;note_tail_mask<=tail_work;state<=IDLE;
    end
   end
   if(sample_ce&&(!ready||busy))fault<=1;
   case(state)
    BOOT:begin mode<=test_mode;initialize_index<=0;state<=INITIALIZE;end
    INITIALIZE:if(initialize_index==127)begin ready<=1;state<=IDLE;end else initialize_index<=initialize_index+1'b1;
    IDLE:begin
     if(test_mode!=mode)begin
      ready<=0;mode<=test_mode;initialize_index<=0;pending_note<=0;
      active_count<=0;note_tail_mask<=0;state<=INITIALIZE;
     end else if(sample_ce&&ready)begin
      bend_snapshot<=mode==0?bend:8'sd0;guard_count<=0;cursor<=0;
      accumulator<=0;active_work<=0;tail_work<=0;state<=GUARD;
     end
    end
    GUARD:if(guard_count==7&&!pending_note&&!note_launch)state<=READ;
          else if(guard_count!=7)guard_count<=guard_count+1'b1;
    READ:state<=BEND;
    BEND:begin
     if(q_fresh||q_stage==OFF||component==0)begin phase_base<=q_phase;bend_product<=0;end
     else begin
      phase_base<=q_phase+q_step;
      bend_product<=$signed({1'b0,q_step[31:8]})*$signed(bend_snapshot);
     end
     env_write<=env_advanced;gate_write<=gate_advanced;stage_write<=stage_advanced;
     gain_envelope<=q_gain*q_env;state<=WRITE;
    end
    WRITE:if(cursor==127)state<=DRAIN;else begin cursor<=cursor+1'b1;state<=READ;end
    default:begin end
   endcase
   if(applying_note)begin
    if(pending_component==3)begin pending_note<=0;pending_component<=1;end
    else pending_component<=pending_component+1'b1;
   end
   // A single mailbox is enough for the original one-launch-per-sample core.
   // Later asynchronous launches are deferred until the sweep finishes.
   if(note_launch&&mode==0)begin
    if(!ready||(pending_note&&!(applying_note&&pending_component==3)))fault<=1;
    else begin pending_note<=1;pending_slot<=note_slot;pending_data<=note_data;pending_component<=1;end
   end
  end
 end
endmodule

