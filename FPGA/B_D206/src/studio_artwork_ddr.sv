// Lossless DDR-backed tile artwork. Two eight-line strips share 16 KiB with the
// boot decoder's history. The next strip is filled while the current is scanned.
module studio_artwork_ddr(
 input wire clk,reset,host_clk,host_rst_n,input wire [4:0] scene,
 input wire [10:0] x,input wire [9:0] y,input wire de,hs,vs,
 output reg [23:0] rgb,output wire [10:0] px,output wire [9:0] py,
 output wire out_de,out_hs,out_vs,available,output wire [7:0] error,
 output wire request,write_request,output wire [28:0] address,output wire [255:0] write_data,
 input wire mem_ready,mem_done,mem_error,input wire [255:0] read_data,
 output reg [31:0] underruns,output wire boot_ready,output wire [31:0] boot_bytes
);
 `include "src/studio_asset_config.vh"
 `include "src/studio_colors.vh"
 wire [UI_STREAM_AW-1:0] rom_address;wire [7:0] rom_byte,boot_fault;
 wire [11:0] history_address;wire [31:0] history_write,history_read;wire [3:0] history_mask;
 wire loader_request;wire [28:0] loader_address;wire [255:0] loader_data;
 studio_asset_stream compressed(.clk(host_clk),.addr(rom_address),.data(rom_byte));
 studio_asset_loader #(.RAW_BYTES(UI_RAW_BYTES),.PACKED_BYTES(UI_PACKED_BYTES),.STREAM_AW(UI_STREAM_AW),.EXPECTED_CRC(UI_RAW_CRC),.BASE_WORD(UI_DDR_BASE_WORD)) loader(
  .clk(host_clk),.rst_n(host_rst_n),.rom_address(rom_address),.rom_data(rom_byte),
  .history_address(history_address),.history_write_data(history_write),.history_write_mask(history_mask),.history_read_data(history_read),
  .request(loader_request),.address(loader_address),.write_data(loader_data),.mem_ready(mem_ready),.mem_done(mem_done),.mem_error(mem_error),
  .ready(boot_ready),.fault(boot_fault),.bytes_written(boot_bytes));

 (* syn_preserve=1 *) reg [12:0] command_mailbox;
 reg request_toggle,ack_toggle,pending;
 (* syn_preserve=1 *) reg [1:0] request_sync,ack_sync,boot_sync;
 reg [7:0] error_meta,error_sync;
 reg [7:0] cache_fault;
 reg [4:0] wanted_scene;
 reg [6:0] stripe_tag[0:1];reg [1:0] valid;reg running;
 wire channel_idle=request_toggle==ack_sync[1];
 wire [6:0] stripe=y[9:3];wire [6:0] next_stripe=stripe==74?0:stripe+1'b1;
 wire hit0=valid[0]&&stripe_tag[0]==stripe;
 wire hit1=valid[1]&&stripe_tag[1]==stripe;
 wire pixel_bank=!hit0&&hit1;
 wire pixel_ok=running&&scene==wanted_scene&&y<600&&(hit0||hit1);
 wire next_present=(valid[0]&&stripe_tag[0]==next_stripe)||(valid[1]&&stripe_tag[1]==next_stripe);
 task launch;input [6:0] s;input bank;begin
  command_mailbox<={wanted_scene,s,bank};request_toggle<=~request_toggle;pending<=1;valid[bank]<=0;
 end endtask
 always @(posedge clk)begin
  if(reset)begin
   request_toggle<=0;command_mailbox<=0;ack_sync<=0;boot_sync<=0;pending<=0;error_meta<=0;error_sync<=0;
   wanted_scene<=31;stripe_tag[0]<=127;stripe_tag[1]<=127;valid<=0;running<=0;underruns<=0;
  end else begin
   ack_sync<={ack_sync[0],ack_toggle};boot_sync<={boot_sync[0],boot_ready};
   error_meta<=boot_fault!=0?boot_fault:cache_fault;error_sync<=error_meta;
   if(pending&&channel_idle)begin
    pending<=0;
    if(command_mailbox[12:8]==wanted_scene&&error_sync==0)begin
     valid[command_mailbox[0]]<=1;stripe_tag[command_mailbox[0]]<=command_mailbox[7:1];
    end
   end
   if(scene!=wanted_scene)begin wanted_scene<=scene;valid<=0;running<=0;end
   else if(!boot_sync[1]||error_sync!=0)begin valid<=0;running<=0;end
   else if(!running)begin
    if(!pending&&channel_idle)begin
     if(!valid[0]||stripe_tag[0]!=0)launch(0,0);
     else if(!valid[1]||stripe_tag[1]!=1)launch(1,1);
     else if(y>=600)running<=1;
    end
   end else if(de&&x==0&&y[2:0]==0)begin
    if(!hit0&&!hit1)begin running<=0;valid<=0;underruns<=underruns+1'b1;end
    else if(!next_present&&!pending&&channel_idle)launch(next_stripe,!pixel_bank);
   end
  end
 end
 assign error=error_sync;

 localparam H_IDLE=0,H_ROW_REQ=1,H_ROW_WAIT=2,H_MAP_REQ=3,H_MAP_WAIT=4,H_TILE_REQ=5,H_TILE_WAIT=6,H_WRITE=7,H_DONE=8,H_MAP_STORE=9,H_ID_REQ=10,H_ID_WAIT=11;
 reg [3:0] state;reg [4:0] fill_scene;reg [6:0] fill_stripe,tile_column;reg fill_bank,active_toggle;
 reg [63:0] segments;reg [1:0] group;reg half;reg [3:0] pixel_step;
 reg [15:0] current_tile;reg [255:0] tile_data,map_data;reg [2:0] map_step;
 reg cache_request;reg [28:0] cache_address;reg bad_map;
 wire [15:0] segment_id=segments[group*16+:16];
 wire [7:0] codes=tile_data[32+pixel_step*8+:8];
 wire [31:0] pixel_write={tile_data[codes[7:6]*8+:8],tile_data[codes[5:4]*8+:8],tile_data[codes[3:2]*8+:8],tile_data[codes[1:0]*8+:8]};
 // IDs occupy the final 64 words of the FREE strip bank. Pixel generation first
 // reaches them at tile 96; it only overwrites already-consumed IDs. At tile 127
 // the final IDs have been latched before the last words are replaced by pixels.
 wire [10:0] map_store_address=11'd1984+{5'd0,group,half,map_step};
 wire [10:0] map_read_address=11'd1984+{5'd0,tile_column[6:1]};
 wire [11:0] cache_host_address=state==H_MAP_STORE?{fill_bank,map_store_address}:
  (state==H_ID_REQ||state==H_ID_WAIT)?{fill_bank,map_read_address}:{fill_bank,pixel_step[3:1],tile_column,pixel_step[0]};
 wire [31:0] cache_write=state==H_MAP_STORE?map_data[map_step*32+:32]:pixel_write;
 always @*begin bad_map=0;for(integer k=0;k<16;k=k+1)if(read_data[k*16+:16]>=UI_TILE_COUNT)bad_map=1;end
 always @(posedge host_clk)begin
  if(!host_rst_n)begin
   request_sync<=0;ack_toggle<=0;active_toggle<=0;state<=H_IDLE;fill_scene<=0;fill_stripe<=0;fill_bank<=0;
   segments<=0;group<=0;half<=0;pixel_step<=0;tile_column<=0;tile_data<=0;map_data<=0;map_step<=0;current_tile<=0;cache_request<=0;cache_address<=0;cache_fault<=0;
  end else begin
   request_sync<={request_sync[0],request_toggle};cache_request<=0;
   case(state)
    H_IDLE:if(boot_ready&&cache_fault==0&&request_sync[1]!=ack_toggle)begin
     fill_scene<=command_mailbox[12:8];fill_stripe<=command_mailbox[7:1];fill_bank<=command_mailbox[0];active_toggle<=request_sync[1];
     state<=H_ROW_REQ;
    end
    H_ROW_REQ:begin
     if(fill_scene>=UI_SCENE_COUNT||fill_stripe>=75)begin cache_fault<=8'h10;state<=H_DONE;end
     else if(mem_ready)begin cache_address<=UI_DDR_BASE_WORD+{16'd0,fill_scene,fill_stripe[6:2],3'b000};cache_request<=1;state<=H_ROW_WAIT;end
    end
    H_ROW_WAIT:if(mem_done)begin
     if(mem_error)begin cache_fault<=8'h11;state<=H_DONE;end
     else begin segments<=read_data>>(fill_stripe[1:0]*64);group<=0;half<=0;state<=H_MAP_REQ;end
    end
    H_MAP_REQ:if(mem_ready)begin
     if(segment_id>=UI_SEGMENT_COUNT)begin cache_fault<=8'h12;state<=H_DONE;end
     else begin cache_address<=UI_SEGMENTS_BASE_WORD+{9'd0,segment_id,4'b0000}+{25'd0,half,3'b000};cache_request<=1;state<=H_MAP_WAIT;end
    end
    H_MAP_WAIT:if(mem_done)begin
     if(mem_error||bad_map)begin cache_fault<=mem_error?8'h11:8'h13;state<=H_DONE;end
     else begin map_data<=read_data;map_step<=0;state<=H_MAP_STORE;end
    end
    H_MAP_STORE:begin
     if(map_step!=7)map_step<=map_step+1'b1;
     else begin
      if(!half)begin half<=1;state<=H_MAP_REQ;end
      else if(group!=3)begin group<=group+1'b1;half<=0;state<=H_MAP_REQ;end
      else begin tile_column<=0;state<=H_ID_REQ;end
     end
    end
    H_ID_REQ:state<=H_ID_WAIT;
    H_ID_WAIT:begin current_tile<=history_read>>(tile_column[0]*16);state<=H_TILE_REQ;end
    H_TILE_REQ:if(mem_ready)begin cache_address<=UI_TILES_BASE_WORD+{10'd0,current_tile,3'b000};cache_request<=1;state<=H_TILE_WAIT;end
    H_TILE_WAIT:if(mem_done)begin
     if(mem_error)begin cache_fault<=8'h11;state<=H_DONE;end
     else begin tile_data<=read_data;pixel_step<=0;state<=H_WRITE;end
    end
    H_WRITE:begin
     if(pixel_step!=15)pixel_step<=pixel_step+1'b1;
     else if(tile_column!=127)begin tile_column<=tile_column+1'b1;state<=H_ID_REQ;end
     else state<=H_DONE;
    end
    H_DONE:begin ack_toggle<=active_toggle;state<=H_IDLE;end
    default:state<=H_IDLE;
   endcase
  end
 end
 assign request=boot_ready?cache_request:loader_request;
 assign write_request=!boot_ready;
 assign address=boot_ready?cache_address:loader_address;
 assign write_data=loader_data;

 wire [31:0] pixel_word;
 studio_cache_ram cache(
  .host_clk(host_clk),.host_address(boot_ready?cache_host_address:history_address),
  .host_write_data(boot_ready?cache_write:history_write),.host_write_mask(boot_ready?((state==H_WRITE||state==H_MAP_STORE)?4'b1111:4'b0000):history_mask),.host_read_data(history_read),
  .pixel_clk(clk),.pixel_address({pixel_bank,y[2:0],x[9:2]}),.pixel_read_data(pixel_word));
 reg [10:0] xx[0:3];reg [9:0] yy[0:3];reg [3:0] dd,hh,vv,ok;reg [7:0] pixel_index;reg [23:0] colour;integer d;
 always @(posedge clk)begin
  xx[0]<=x;yy[0]<=y;for(d=1;d<4;d=d+1)begin xx[d]<=xx[d-1];yy[d]<=yy[d-1];end
  dd<={dd[2:0],de};hh<={hh[2:0],hs};vv<={vv[2:0],vs};ok<={ok[2:0],pixel_ok};
  pixel_index<=pixel_word>>(xx[0][1:0]*8);colour<=studio_color(pixel_index[6:0]);rgb<=ok[2]?colour:24'hfafbf2;
  if(reset)begin dd<=0;hh<=0;vv<=0;ok<=0;rgb<=24'hfafbf2;end
 end
 assign px=xx[3];assign py=yy[3];assign out_de=dd[3];assign out_hs=hh[3];assign out_vs=vv[3];assign available=ok[3];
endmodule
