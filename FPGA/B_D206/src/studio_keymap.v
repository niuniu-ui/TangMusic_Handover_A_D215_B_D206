// Physical note-off uses the pitch latched at note-on, including across map changes.
module studio_keymap(
 input wire clk,rst_n,clear,input wire [255:0] mapping,
 input wire in_valid,input wire [3:0] in_kind,input wire [6:0] in_key,in_value,
 output reg out_valid,output reg [3:0] out_kind,output reg [6:0] out_key,out_value,
 output reg [31:0] mapped_down
);
 reg [6:0] held[0:31];reg [31:0] held_valid;
 wire valid_key=in_key>=41&&in_key<=72;wire [4:0] index=in_key-7'd41;
 wire [7:0] mapped=mapping[index*8+:8];integer i;
 always @(posedge clk)begin
  out_valid<=0;
  if(!rst_n||clear)begin mapped_down<=0;held_valid<=0;out_kind<=0;out_key<=0;out_value<=0;for(i=0;i<32;i=i+1)held[i]<=41+i;end
  else if(in_valid)begin
   out_valid<=1;out_kind<=in_kind;out_value<=in_value;out_key<=in_key;
   if(valid_key&&(in_kind==8||in_kind==9))begin
    if(in_kind==9&&in_value!=0&&mapped>=53&&mapped<=84)begin
     held[index]<=mapped-12;held_valid[index]<=1;out_key<=mapped-12;mapped_down[mapped-53]<=1;
    end else if(held_valid[index])begin
     out_key<=held[index];held_valid[index]<=0;mapped_down[held[index]-41]<=0;
    end else begin out_valid<=0;end
   end
  end
 end
endmodule
