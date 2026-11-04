// Drum events are timestamped by A's DAC sample clock. B returns 16-sample
// blocks with absolute sample tags; stale, missing or foreign blocks are silent.
module studio_drum_transport #(parameter integer LATENCY=128)(
 input wire clk,rst_n,sample_tick,recalibrate,event_valid,
 input wire [18:0] event_data,input wire [7:0] bend,expression,
 input wire peer_alive,input wire [2047:0] peer_payload,
 output reg [31:0] sample_index=0,output reg [255:0] event_slots=0,
 output reg [7:0] event_sequence=0,epoch=0,
 output wire signed [15:0] pcm,output wire [31:0] active_mask,
 output reg [31:0] underruns=0,output wire remote_fault
);
 reg [1:0] event_write=0;
 reg [15:0] valid_blocks=0;reg [31:0] tags[0:15];
 (* syn_ramstyle="block_ram" *) reg [15:0] samples[0:255];
 reg [15:0] sample_read=0;reg read_valid=0;
 wire [31:0] target=sample_index-LATENCY;
 wire compatible=peer_alive&&peer_payload[591:576]==16'hb2d1&&peer_payload[599:592]==epoch;
 wire valid_target=sample_index>=LATENCY&&valid_blocks[target[7:4]]&&tags[target[7:4]]=={target[31:4],4'b0};
 reg writing=0,have_return=0,locked=0;reg [3:0] copy_index=0;
 reg [255:0] copy_block=0;reg [31:0] copy_tag=0,last_tag=0;
 integer i;
 assign pcm=compatible&&read_valid?$signed(sample_read):16'sd0;
 assign active_mask=compatible?peer_payload[639:608]:32'd0;
 assign remote_fault=compatible&&(peer_payload[640]||underruns!=0);
 always @(posedge clk)begin
  sample_read<=samples[target[7:0]];read_valid<=valid_target;
  if(writing)samples[{copy_tag[7:4],copy_index}]<=copy_block[copy_index*16+:16];
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   sample_index<=0;event_slots<=0;event_sequence<=0;event_write<=0;epoch<=0;
   valid_blocks<=0;writing<=0;copy_index<=0;have_return<=0;locked<=0;underruns<=0;
   copy_block<=0;copy_tag<=0;last_tag<=0;for(i=0;i<16;i=i+1)tags[i]<=0;
  end else begin
   if(sample_tick)begin
    sample_index<=sample_index+1'b1;
    if(compatible&&valid_target)locked<=1;
    if(locked&&sample_index>=LATENCY&&!valid_target&&underruns!=32'hffffffff)underruns<=underruns+1'b1;
   end
   if(event_valid)begin
    event_slots[event_write*64+:64]<={13'd0,bend,event_data,(sample_index[15:0]+16'd1),(event_sequence+8'd1)};
    event_sequence<=event_sequence+1'b1;event_write<=event_write+1'b1;
   end
   if(!compatible)begin valid_blocks<=0;writing<=0;have_return<=0;locked<=0;end
   else if(writing)begin
    if(copy_index==15)begin valid_blocks[copy_tag[7:4]]<=1;tags[copy_tag[7:4]]<=copy_tag;writing<=0;end
    else copy_index<=copy_index+1'b1;
   end else if(!have_return||last_tag!=peer_payload[319:288])begin
    if(peer_payload[291:288]==0)begin
     copy_tag<=peer_payload[319:288];last_tag<=peer_payload[319:288];copy_block<=peer_payload[575:320];
     copy_index<=0;writing<=1;have_return<=1;valid_blocks[peer_payload[295:292]]<=0;
    end
   end
   if(recalibrate)begin
    epoch<=epoch+1'b1;event_sequence<=0;event_slots<=0;event_write<=0;
    valid_blocks<=0;writing<=0;have_return<=0;locked<=0;underruns<=0;
   end
  end
 end
endmodule
