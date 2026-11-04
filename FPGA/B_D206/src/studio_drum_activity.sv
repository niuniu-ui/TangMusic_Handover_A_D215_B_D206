// Display-only telemetry for the actual active synthesis components.
// The producer counts main oscillators and independent TDM partials; never
// infer this value by multiplying allocated note slots by four.
// At 50 MHz the ten 100 ms buckets cover approximately the latest 0.9--1.0 s.
// A maximum expires at a bucket boundary, so this is a quantized recent peak,
// not a lifetime maximum or a claim of an exact one-second sliding window.
module studio_drum_activity #(
 parameter integer BUCKET_CYCLES=5000000,
 parameter integer BUCKETS=10
)(
 input wire clk,rst_n,enable,
 input wire [7:0] active_count,
 output reg [7:0] current_count,peak_count
);
 localparam integer TW=BUCKET_CYCLES>1?$clog2(BUCKET_CYCLES):1;
 localparam integer IW=BUCKETS>1?$clog2(BUCKETS):1;
 reg [TW-1:0] bucket_timer;
 reg [IW-1:0] bucket_index;
 reg [7:0] bucket_max[0:BUCKETS-1];
 wire [IW-1:0] following_bucket=bucket_index==BUCKETS-1?0:bucket_index+1'b1;
 wire advance_bucket=bucket_timer==BUCKET_CYCLES-1;

 reg [7:0] recent_max;
 integer scan,clear_index;
 always @*begin
  recent_max=active_count;
  for(scan=0;scan<BUCKETS;scan=scan+1)
   // Retire the oldest bucket before publishing the new peak. An active
   // voice at the boundary belongs to the newly opened bucket.
   if(!(advance_bucket&&scan==following_bucket)&&bucket_max[scan]>recent_max)
    recent_max=bucket_max[scan];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   current_count<=0;peak_count<=0;bucket_timer<=0;bucket_index<=0;
   for(clear_index=0;clear_index<BUCKETS;clear_index=clear_index+1)bucket_max[clear_index]<=0;
  end else if(!enable)begin
   current_count<=0;peak_count<=0;bucket_timer<=0;bucket_index<=0;
   for(clear_index=0;clear_index<BUCKETS;clear_index=clear_index+1)bucket_max[clear_index]<=0;
  end else begin
   current_count<=active_count;peak_count<=recent_max;
   if(advance_bucket)begin
    bucket_timer<=0;bucket_index<=following_bucket;
    bucket_max[following_bucket]<=active_count;
   end else begin
    bucket_timer<=bucket_timer+1'b1;
    if(active_count>bucket_max[bucket_index])bucket_max[bucket_index]<=active_count;
   end
  end
 end
endmodule
