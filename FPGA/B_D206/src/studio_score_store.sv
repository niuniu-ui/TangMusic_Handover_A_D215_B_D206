`timescale 1ns/1ps
// Committed scores are read locally for visual guidance; this does not synthesize audio.
module studio_score_store #(parameter integer MAX_NOTES=1024,US_CYCLES=50)(
 input wire clk,rst_n,abort_upload,busy_external,stop_guide,
 input wire [1:0] octave_group,input wire [31:0] keys_down,
 input wire request,input wire [15:0] command,payload_length,input wire [559:0] payload,
 output reg done,output reg [15:0] result,output reg [31:0] detail,
 output reg [5:0] reply_length,output reg [159:0] reply,
 output reg loaded,active,waiting,completed,output reg [31:0] target_keys,
 output reg [31:0] elapsed_us,output reg [15:0] current_note,total_notes,
 output wire [31:0] score_duration
);
 localparam IDLE=0,DONE=1,WRITE=2,READ_SET=3,READ_WAIT=4,READ_GET=5,VALIDATE=6,CLEAR_END=7;
 reg [3:0] state;reg uploading,validate_read,next_valid;
 reg [31:0] serial,object_id,total_bytes,next_offset,duration,expected_crc,crc;
 reg [15:0] count,record_index,write_length,write_index;
 reg [13:0] read_address,record_address;reg [3:0] byte_index;
 reg [7:0] memory[0:MAX_NOTES*10-1] /* synthesis syn_ramstyle="block_ram" */;
 reg [7:0] read_byte;reg [79:0] word;
 reg [31:0] last_start,hit_mask;
 // One expiry comparator scans 32 keys in 0.64 us at 50 MHz. The target mask
 // guards uninitialized RAM. Validation clears its separate table per upload.
 reg [31:0] end_by_key[0:31] /* synthesis syn_ramstyle="block_ram" */;
 reg [31:0] last_end[0:31] /* synthesis syn_ramstyle="block_ram" */;
 reg [31:0] expiry_end,last_end_q;
 reg [4:0] expiry_cursor,expiry_key,clear_key,last_written_key;
 reg last_written;
 reg [7:0] last_note;reg [31:0] next_start,next_end;reg [4:0] next_key;
 reg [$clog2(US_CYCLES+1)-1:0] us_counter;
 wire [31:0] note_start=word[31:0],note_duration=word[63:32];
 wire [7:0] note_pitch=word[71:64],note_velocity=word[79:72];
 wire [32:0] note_end={1'b0,note_start}+{1'b0,note_duration};
 wire [4:0] note_key=note_pitch-8'd53;
 wire publish_note=state==IDLE&&!request&&active&&next_valid&&next_start<=elapsed_us;
 wire record_valid=note_pitch>=53&&note_pitch<=84&&note_velocity!=0&&note_velocity<=127&&
   note_duration!=0&&note_end<=duration&&
   (record_index==0||note_start>last_start||(note_start==last_start&&note_pitch>last_note));
 assign score_duration=duration;
 function [15:0] p16(input integer a);p16=payload[a*8+:16];endfunction
 function [31:0] p32(input integer a);p32=payload[a*8+:32];endfunction
 function [31:0] crc_byte(input [31:0] c,input [7:0] b);
  reg [31:0] v;integer k;begin v=c^b;for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;end
 endfunction
 task ok(input [5:0] n);begin done<=1;result<=0;detail<=0;reply_length<=n;state<=DONE;end endtask
 task reject(input [15:0] code,input [31:0] why);begin done<=1;result<=code;detail<=why;reply_length<=0;state<=DONE;end endtask
 task info;begin reply<={32'b0,loaded?8'd1:8'd0,8'd10,loaded?count:16'd0,loaded?expected_crc:32'd0,loaded?duration:32'd0,loaded?object_id:32'd0};ok(20);end endtask
 task begin_read(input [13:0] address,input check);
  begin record_address<=address;byte_index<=0;word<=0;validate_read<=check;state<=READ_SET;end
 endtask
 always @(posedge clk)begin
  read_byte<=memory[read_address];
  if(rst_n&&state==WRITE&&!abort_upload)memory[next_offset+write_index]<=payload[(10+write_index)*8+:8];
  expiry_end<=end_by_key[expiry_cursor];
  last_end_q<=last_end[note_key];
  if(rst_n&&publish_note)end_by_key[next_key]<=next_end;
  if(rst_n&&!abort_upload)begin
   if(state==CLEAR_END)last_end[clear_key]<=0;
   else if(state==VALIDATE&&validate_read&&record_valid&&note_start>=last_end_q)
    last_end[note_key]<=note_end[31:0];
  end
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;done<=0;result<=0;detail<=0;reply_length<=0;reply<=0;serial<=0;object_id<=0;
   loaded<=0;active<=0;waiting<=0;completed<=0;uploading<=0;next_offset<=0;total_bytes<=0;duration<=0;expected_crc<=0;count<=0;
   target_keys<=0;elapsed_us<=0;current_note<=0;total_notes<=0;us_counter<=0;hit_mask<=0;next_valid<=0;
   record_index<=0;write_index<=0;write_length<=0;read_address<=0;record_address<=0;byte_index<=0;word<=0;crc<=0;last_start<=0;last_note<=0;validate_read<=0;
   next_start<=0;next_end<=0;next_key<=0;
   expiry_cursor<=0;expiry_key<=0;clear_key<=0;last_written<=0;last_written_key<=0;
  end else begin
   expiry_cursor<=expiry_cursor+1'b1;expiry_key<=expiry_cursor;
   last_written<=publish_note;if(publish_note)last_written_key<=next_key;
   hit_mask<=(hit_mask|keys_down)&target_keys;
   if(active)begin
    if(us_counter==US_CYCLES-1)begin
     us_counter<=0;
     if(!waiting||((hit_mask|keys_down)&target_keys)==target_keys)elapsed_us<=elapsed_us+1'b1;
    end else us_counter<=us_counter+1'b1;
    // Suppress stale read-during-write data after a new note replaces this key.
    if(target_keys[expiry_key]&&elapsed_us>=expiry_end&&
       !(last_written&&last_written_key==expiry_key))target_keys[expiry_key]<=0;
    if(elapsed_us>=duration)begin active<=0;completed<=1;target_keys<=0;next_valid<=0;end
   end
   case(state)
    IDLE:if(request)begin
     reply<=0;result<=0;detail<=0;
     case(command)
      16'h0201:begin
       if(payload_length!=14)reject(3,14);
       else if(busy_external||active||uploading)reject(6,0);
       else if(p16(4)==0||p16(4)>MAX_NOTES||p32(0)!=p16(4)*10||p32(6)==0||p32(6)>120000000)reject(4,32'hffffffff);
       else if(serial==32'hffffffff)reject(10,0);
       else begin
        serial<=serial+1'b1;object_id<=serial+1'b1;count<=p16(4);total_bytes<=p32(0);duration<=p32(6);expected_crc<=p32(10);
        next_offset<=0;loaded<=0;uploading<=1;completed<=0;total_notes<=0;reply<={96'b0,32'b0,serial+1'b1};ok(8);
       end
      end
      16'h0202:begin
       if(payload_length<11||payload_length>60||p16(8)==0||p16(8)>50||payload_length!=10+p16(8))reject(3,50);
       else if(!uploading||p32(0)!=object_id)reject(5,object_id);
       else if(p32(4)!=next_offset)reject(11,next_offset);
       else if({1'b0,next_offset}+p16(8)>total_bytes)reject(4,next_offset);
       else begin write_length<=p16(8);write_index<=0;state<=WRITE;end
      end
      16'h0203:begin
       if(payload_length!=4)reject(3,4);
       else if(!uploading||p32(0)!=object_id)reject(5,object_id);
       else if(next_offset!=total_bytes)reject(11,next_offset);
       else begin crc<=32'hffffffff;record_index<=0;last_start<=0;last_note<=0;clear_key<=0;state<=CLEAR_END;end
      end
      16'h0204:begin
       if(payload_length!=4)reject(3,4);
       else if(!uploading||p32(0)!=object_id)reject(5,object_id);
       else begin uploading<=0;loaded<=0;ok(0);end
      end
      16'h0205:if(payload_length!=0)reject(3,0);else info();
      16'h0220:begin
       if(payload_length!=9)reject(3,9);
       else if(!loaded||p32(0)!=object_id||p32(4)!=expected_crc)reject(14,object_id);
       else if(active||busy_external)reject(6,0);
       else if(octave_group!=2||payload[64+:8]>1)reject(4,2);
       else begin
        active<=1;waiting<=payload[64];completed<=0;elapsed_us<=0;current_note<=0;record_index<=0;us_counter<=0;target_keys<=0;hit_mask<=0;next_valid<=0;
        reply<={128'b0,object_id};ok(4);
       end
      end
      16'h0221:begin
       if(payload_length!=4)reject(3,4);
       else if(!loaded||p32(0)!=object_id)reject(14,object_id);
       else begin active<=0;target_keys<=0;next_valid<=0;reply<={128'b0,object_id};ok(4);end
      end
      16'h0222:begin
       if(payload_length!=0)reject(3,0);
       else begin reply<={count,current_note,7'b0,loaded,7'b0,completed,7'b0,waiting,7'b0,active,target_keys,elapsed_us,object_id};ok(20);end
      end
      default:reject(7,0);
     endcase
    end else if(active)begin
     if(next_valid&&next_start<=elapsed_us)begin
      target_keys[next_key]<=next_end>elapsed_us;hit_mask[next_key]<=0;
      next_valid<=0;current_note<=record_index; // record_index counts records already prefetched
     end else if(!next_valid&&record_index<count)begin begin_read(record_index*10,0);end
    end
    CLEAR_END:if(clear_key==31)begin_read(0,1);else clear_key<=clear_key+1'b1;
    WRITE:if(write_index+1==write_length)begin
     next_offset<=next_offset+write_length;reply<={96'b0,next_offset+write_length,object_id};ok(8);
    end else write_index<=write_index+1'b1;
    READ_SET:begin read_address<=record_address+byte_index;state<=READ_WAIT;end
    READ_WAIT:state<=READ_GET;
    READ_GET:begin
     word[byte_index*8+:8]<=read_byte;if(validate_read)crc<=crc_byte(crc,read_byte);
     if(byte_index==9)state<=VALIDATE;else begin byte_index<=byte_index+1'b1;state<=READ_SET;end
    end
    VALIDATE:if(validate_read)begin
     if(!record_valid)begin uploading<=0;reject(4,record_index);end
     else if(note_start<last_end_q)begin uploading<=0;reject(17,record_index);end
     else if(record_index+1==count)begin
      uploading<=0;
      if((~crc)!=expected_crc)reject(12,~crc);
      else begin loaded<=1;total_notes<=count;reply<={32'b0,8'd1,8'd10,count,expected_crc,duration,object_id};ok(20);end
     end else begin
      last_start<=note_start;last_note<=note_pitch;record_index<=record_index+1'b1;begin_read(record_address+10,1);
     end
    end else begin next_start<=note_start;next_end<=note_end[31:0];next_key<=note_key;next_valid<=1;record_index<=record_index+1'b1;state<=IDLE;end
    DONE:if(!request)begin done<=0;state<=IDLE;end
    default:state<=IDLE;
   endcase
   if(stop_guide||octave_group!=2)begin active<=0;target_keys<=0;next_valid<=0;end
   if(abort_upload)begin
    uploading<=0;done<=0;
    if(uploading||state==DONE)state<=IDLE;
   end
  end
 end
endmodule
