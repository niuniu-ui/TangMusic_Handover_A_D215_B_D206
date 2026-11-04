// Atomic touch state from B. The timeout clears only remote touch contacts;
// physical instruments, their notes and the A audio clock remain independent.
module studio_remote_touch #(parameter integer TIMEOUT=5000000)(
 input wire clk,rst_n,input wire [7:0] rx_byte,rx_index,input wire rx_valid,rx_done,
 output reg [273:0] touch_state=0,output reg updated=0,output wire alive,output reg [2047:0] peer_payload=0
);
 reg [2047:0] staging=0;reg [22:0] age=TIMEOUT;
 assign alive=age<TIMEOUT;
 always @(posedge clk)begin
  updated<=0;
  if(!rst_n)begin staging<=0;touch_state<=0;peer_payload<=0;age<=TIMEOUT;end
  else begin
   if(age<TIMEOUT)age<=age+1'b1;
   if(rx_valid)staging[rx_index*8+:8]<=rx_byte;
   if(rx_done)begin touch_state<=staging[273:0];peer_payload<=staging;updated<=1;age<=0;end
   else if(age==TIMEOUT-1)begin touch_state<=0;peer_payload<=0;updated<=1;end
  end
 end
endmodule

// B consumes A's display bundle plus a 32-sample, display-only PCM block.
// Samples are replayed with 512 host clocks between them, leaving time for
// the existing Lissajous rasterizer. They never drive a DAC or an audio FIFO.
module studio_remote_display #(parameter integer TIMEOUT=5000000)(
 input wire clk,rst_n,input wire [7:0] rx_byte,rx_index,input wire rx_valid,rx_done,
 output reg [1257:0] display_state=0,output reg sample_tick=0,
 output reg signed [15:0] pcm=0,output reg sample_reset=0,output wire alive,output reg [2047:0] peer_payload=0
);
 reg [2047:0] staging=0;
 reg [255:0] pcm_block=0;reg [31:0] last_block=0;reg have_block=0;
 reg [5:0] left=0;reg [8:0] spacing=0;reg [22:0] age=TIMEOUT;
 assign alive=age<TIMEOUT;
 always @(posedge clk)begin
  sample_tick<=0;sample_reset<=0;
  if(!rst_n)begin
   staging<=0;display_state<=0;peer_payload<=0;pcm_block<=0;last_block<=0;have_block<=0;left<=0;spacing<=0;age<=TIMEOUT;pcm<=0;sample_reset<=1;
  end else begin
   if(age<TIMEOUT)age<=age+1'b1;
   if(rx_valid)staging[rx_index*8+:8]<=rx_byte;
   if(left!=0)begin
    if(spacing==0)begin pcm<=pcm_block[15:0];pcm_block<=pcm_block>>16;left<=left-1'b1;sample_tick<=1;spacing<=511;end
    else spacing<=spacing-1'b1;
   end
   if(rx_done)begin
    display_state<=staging[1257:0];peer_payload<=staging;age<=0;
    if(!have_block||staging[1567:1536]!=last_block)begin
     if(!have_block||staging[1567:1536]!=last_block+1'b1)sample_reset<=1;
     last_block<=staging[1567:1536];have_block<=1;pcm_block<=staging[1535:1280];left<=16;spacing<=0;
    end
   end else if(age==TIMEOUT-1)begin
    display_state<=0;peer_payload<=0;have_block<=0;left<=0;pcm<=0;sample_tick<=0;sample_reset<=1;
   end
  end
 end
endmodule
