// Render against A's sample tags; preserve the 16-sample block protocol.
module studio_remote_drum(
 input wire clk,rst_n,peer_alive,input wire [2047:0] peer_payload,
 input wire [1:0] test_mode,
 output reg [255:0] pcm_block=0,output reg [31:0] block_start=0,
 output reg block_valid=0,output reg [7:0] epoch=0,
 output wire [31:0] active_mask,note_active_mask,
 output wire [7:0] component_count,
 output wire fault,output reg [31:0] faults=0
);
 localparam WAITING=0,EVENTS=1,SAMPLE=2,RESULT=3,REST=4;
 // 10.24us render spacing; A still outputs one sample every 20.48us.
 localparam integer RENDER_SPACING=512;
 reg [2:0] state=WAITING;reg synced=0,engine_reset=1;
 reg [1:0] engine_mode=0;
 // Continuous decode also defines time-zero PLAY and legacy floating inputs.
 wire [1:0] requested_mode=(test_mode===2'd1)?2'd1:
   (test_mode===2'd2)?2'd2:(test_mode===2'd3)?2'd3:2'd0;
 reg [31:0] render_index=0;reg [7:0] accepted_sequence=0;
 reg resume_barrier=0;reg [31:0] resume_snapshot=0;
 reg [9:0] spacing=0;reg [255:0] building=0;
 reg event_valid=0,sample_ce=0;reg [18:0] event_data=0;
 wire compatible=peer_alive&&peer_payload[1887:1872]==16'hd2a1;
 wire [31:0] requested=peer_payload[1599:1568];
 wire [7:0] next_sequence=accepted_sequence+8'd1;
 wire [1:0] slot=(next_sequence-8'd1)&3;
 wire [63:0] queued=peer_payload[1600+slot*64+:64];
 wire [7:0] latest_sequence=peer_payload[1863:1856];
 wire [7:0] remote_epoch=peer_payload[1871:1864];
 wire [7:0] backlog=latest_sequence-accepted_sequence;
 wire event_due=queued[7:0]==next_sequence&&$signed(queued[23:8]-render_index[15:0])<=0;
 wire [31:0] behind=requested-render_index;
 wire engine_run=rst_n&&!engine_reset;
 wire testing=engine_mode!=0;
 wire signed [15:0] dry,wet,boosted;
 wire signed [21:0] main_sum;
 wire signed [23:0] partial_sum;
 wire dry_valid,partial_valid,partial_ready,partial_fault,synth_overflow;
 wire [31:0] main_active,tail_active;
 wire [6:0] partial_count;
 wire [15:0] event_count;
 wire note_launch;wire [4:0] note_slot;wire [18:0] note_data;
 air_drum_synth engine(.clk(clk),.rst_n(engine_run),.sample_ce(sample_ce),.event_valid(event_valid),
  .bank(event_data[18]),.expression(event_data[17:10]),.event_zone(event_data[9:8]),.event_velocity(event_data[7:0]),
  .bend(peer_payload[1927:1920]),.spectral_test(testing),.pcm(dry),.pcm_valid(dry_valid),.active_mask(main_active),
  .overflow(synth_overflow),.event_count(event_count),.mix_sum(main_sum),
  .note_launch(note_launch),.note_slot(note_slot),.note_data(note_data));
 air_drum_partial_bank partials(.clk(clk),.rst_n(engine_run),.sample_ce(sample_ce),
  .note_launch(note_launch),.note_slot(note_slot),.note_data(note_data),
  .bend(peer_payload[1927:1920]),.test_mode(engine_mode),
  .pcm_sum(partial_sum),.pcm_valid(partial_valid),.ready(partial_ready),
  .active_count(partial_count),.note_tail_mask(tail_active),.fault(partial_fault),.busy());
 assign note_active_mask=testing?32'd0:(main_active|tail_active);
 // Preserve the original 32-bit external packet field as NOTE state.
 assign active_mask=note_active_mask;
 reg [5:0] main_count;integer n;
 always @*begin
  main_count=0;
  for(n=0;n<32;n=n+1)main_count=main_count+main_active[n];
 end
 assign component_count=!engine_run||!partial_ready?8'd0:
   ({2'b0,main_count}+{1'b0,partial_count});

 // Join completed samples, using the original UNSATURATED main sum.
 reg have_main=0,have_partials=0,mix_valid=0;
 reg signed [21:0] held_main=0;
 reg signed [23:0] held_partials=0;
 reg signed [15:0] mix_pcm=0;
 wire signed [24:0] combined=$signed({{3{held_main[21]}},held_main})+
                            $signed({held_partials[23],held_partials});
 wire signed [27:0] extended={{3{combined[24]}},combined};
 wire signed [27:0] normal_scaled=((extended<<<2)+extended)>>>3;
 wire signed [27:0] test_scaled=extended>>>2;
 function signed [15:0] clip(input signed [27:0] value);
  begin clip=value>32767?16'sh7fff:value< -32768?16'sh8000:value[15:0];end
 endfunction
 always @(posedge clk)begin
  mix_valid<=0;
  if(!engine_run)begin
   have_main<=0;have_partials<=0;held_main<=0;held_partials<=0;mix_pcm<=0;
  end else begin
   if(sample_ce)begin have_main<=0;have_partials<=0;end
   if(dry_valid)begin held_main<=main_sum;have_main<=1;end
   if(partial_valid)begin held_partials<=partial_sum;have_partials<=1;end
   if(have_main&&have_partials)begin
    mix_pcm<=clip(testing?test_scaled:normal_scaled);
    mix_valid<=1;have_main<=0;have_partials<=0;
   end
  end
 end
 wire wet_valid;
 air_drum_delay effect(.clk(clk),.rst_n(engine_run),.in_valid(mix_valid),.dry(mix_pcm),
  .wet(peer_payload[1935:1928]),.bypass(testing),.pcm(wet),.out_valid(wet_valid));
 air_drum_master_gain gain(.pcm_in(wet),.bypass(testing),.pcm_out(boosted));
 assign fault=synth_overflow||partial_fault||faults!=0;
 always @(posedge clk)begin
  event_valid<=0;sample_ce<=0;
  if(!rst_n)begin
   state<=WAITING;synced<=0;engine_reset<=1;engine_mode<=0;render_index<=0;accepted_sequence<=0;
   spacing<=0;building<=0;pcm_block<=0;block_start<=0;block_valid<=0;epoch<=0;faults<=0;event_data<=0;
   resume_barrier<=0;resume_snapshot<=0;
  end else if(!compatible)begin synced<=0;engine_reset<=1;block_valid<=0;state<=WAITING;resume_barrier<=0;end
  else if(!synced||epoch!=remote_epoch)begin
   epoch<=remote_epoch;engine_mode<=requested_mode;
   render_index<=requested>32?((requested-32)&32'hfffffff0):0;
   accepted_sequence<=latest_sequence;engine_reset<=1;synced<=1;block_valid<=0;
   state<=WAITING;building<=0;spacing<=0;faults<=0;resume_barrier<=0;
  end else if(engine_mode!=requested_mode)begin
   // Clear pending hits/results on a mode change. Keep the last COMPLETE
   // tagged block until its replacement, preserving A's playback history.
   engine_mode<=requested_mode;engine_reset<=1;accepted_sequence<=latest_sequence;
   // On exit, consume the FIRST newer A snapshot as an event baseline too.
   // It may still contain hits generated during the test but delivered late.
   resume_barrier<=testing&&(requested_mode==0);resume_snapshot<=requested;
   render_index<=requested>32?((requested-32)&32'hfffffff0):0;
   state<=WAITING;building<=0;spacing<=0;
  end else begin
   engine_reset<=0;
   if(testing||resume_barrier)accepted_sequence<=latest_sequence;
   if(resume_barrier&&requested!=resume_snapshot)resume_barrier<=0;
   if(spacing!=0)spacing<=spacing-1'b1;
   if(behind>256||(!testing&&!resume_barrier&&backlog>4))begin
    if(faults!=32'hffffffff)faults<=faults+1'b1;
    render_index<=requested>32?((requested-32)&32'hfffffff0):0;
    accepted_sequence<=latest_sequence;engine_reset<=1;block_valid<=0;state<=WAITING;building<=0;spacing<=0;
   end else case(state)
    WAITING:if(partial_ready&&requested>16&&render_index+16<requested&&spacing==0)state<=EVENTS;
    EVENTS:begin
     if(!testing&&!resume_barrier&&backlog!=0&&event_due)begin
      event_data<=queued[42:24];event_valid<=1;accepted_sequence<=next_sequence;
     end else state<=SAMPLE;
    end
    SAMPLE:begin sample_ce<=1;spacing<=RENDER_SPACING;state<=RESULT;end
    RESULT:if(wet_valid)begin
     building[render_index[3:0]*16+:16]<=boosted;
     if(render_index[3:0]==15)begin
      pcm_block<={boosted,building[239:0]};block_start<={render_index[31:4],4'b0};block_valid<=1;
     end
     render_index<=render_index+1'b1;state<=REST;
    end
    REST:if(spacing==0)state<=WAITING;
    default:state<=WAITING;
   endcase
  end
 end
endmodule
