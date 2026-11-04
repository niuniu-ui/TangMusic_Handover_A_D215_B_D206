`timescale 1ns/1ps
// Piano LED Native AB R04: A(21),B(15),A(21),B(15),A(21),T(3).
// 32 semitone keys F3..C6, three consecutive GRB pixels per physical key.
// One serialized key-map lookup is shared by every key to keep logic small.
module ws2812_keyboard_guide #(
 parameter integer FRAME_CYCLES=500000,
 parameter integer ANIMATION_FRAMES=8
)(
 input wire clk,rst_n,guide_enabled,
 input wire [31:0] target_keys,keys_down,
 input wire [255:0] keymap_values,
 output reg din
);
 localparam IDLE=0,LATCH=1,MAP_KEY=2,LOAD=3,SEND=4;
 localparam FRAME_W=$clog2(FRAME_CYCLES+1);
 reg [2:0] state;
 reg [FRAME_W-1:0] frame_counter;
 reg [14:0] reset_counter;
 reg [4:0] key_index,bit_index;
 reg [1:0] key_pixel;
 reg [5:0] bit_cycle;
 reg [7:0] mapped_note;
 reg [23:0] shift_word;
 reg [31:0] targets,pressed,correct_latched,frame_correct;
 reg [255:0] mapping;
 reg guiding;
 reg [1:0] animation_phase,frame_phase;
 reg [$clog2(ANIMATION_FRAMES+1)-1:0] animation_count;
 wire [7:0] gradient_green=key_index[4] ? 8'd0 : 8'd30-({3'b0,key_index[3:0],1'b0});
 wire [7:0] gradient_red=key_index[4] ? {3'b0,key_index[3:0],1'b0} : 8'd0;
 wire [23:0] idle_color={gradient_green,gradient_red,8'd24}; // fixed gradient by key
 wire idle_pixel=key_pixel==frame_phase;
 wire guide_pixel=key_pixel==(2-frame_phase);
 wire mapped_valid=mapped_note>=53&&mapped_note<=84;
 wire [4:0] note_index=mapped_note-8'd53;
 wire wanted=mapped_valid&&targets[note_index];
 wire held=mapped_valid&&pressed[note_index];
 wire correct=mapped_valid&&frame_correct[note_index];
 wire [23:0] grb=guiding&&held&&correct?24'h180000:
  wanted?24'h101800:
  held?(guiding?24'h001000:idle_color):24'h000000;
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;frame_counter<=0;reset_counter<=0;key_index<=0;key_pixel<=0;
   bit_index<=23;bit_cycle<=0;mapped_note<=0;shift_word<=0;targets<=0;
   pressed<=0;mapping<=0;guiding<=0;din<=0;animation_phase<=0;frame_phase<=0;animation_count<=0;
  end else begin
   if(!guide_enabled)correct_latched<=0;
   else correct_latched<=(correct_latched|(target_keys&keys_down))&keys_down;
   if(frame_counter<FRAME_CYCLES-1)frame_counter<=frame_counter+1'b1;
   case(state)
    IDLE:begin
     din<=0;
     if(frame_counter==FRAME_CYCLES-1)begin
      frame_counter<=0;reset_counter<=0;key_index<=0;key_pixel<=0;
      targets<=guide_enabled?target_keys:32'b0;pressed<=keys_down;
      frame_correct<=guide_enabled?((correct_latched|(target_keys&keys_down))&keys_down):32'b0;
      mapping<=keymap_values;guiding<=guide_enabled;frame_phase<=animation_phase;
      if(animation_count==ANIMATION_FRAMES-1)begin
       animation_count<=0;animation_phase<=animation_phase==2?0:animation_phase+1'b1;
      end else animation_count<=animation_count+1'b1;
      state<=LATCH;
     end
    end
    LATCH:begin
     din<=0;
     if(reset_counter==19999)begin reset_counter<=0;state<=MAP_KEY;end
     else reset_counter<=reset_counter+1'b1;
    end
    MAP_KEY:begin mapped_note<=mapping[key_index*8+:8];state<=LOAD;end
    LOAD:begin shift_word<=grb;bit_index<=23;bit_cycle<=0;state<=SEND;end
    SEND:begin
     // Mini-V3: 0=0.32/0.94us, 1=0.64/0.62us; reset low=400us.
     din<=bit_cycle<(shift_word[23]?32:16);
     if(bit_cycle==62)begin
      bit_cycle<=0;
      if(bit_index!=0)begin shift_word<={shift_word[22:0],1'b0};bit_index<=bit_index-1'b1;end
      else if(key_pixel!=2)begin key_pixel<=key_pixel+1'b1;state<=LOAD;end
      else if(key_index!=31)begin key_pixel<=0;key_index<=key_index+1'b1;state<=MAP_KEY;end
      else state<=IDLE;
     end else bit_cycle<=bit_cycle+1'b1;
    end
    default:begin din<=0;state<=IDLE;frame_counter<=0;end
   endcase
  end
 end
endmodule





