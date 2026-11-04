// Private layer-2 display link. Little-endian payload bytes; standard Ethernet FCS.
localparam integer UI_PAYLOAD_BYTES=256, UI_BODY_BYTES=286, UI_FRAME_BYTES=290;
function [31:0] ui_crc;
 input [31:0] previous; input [7:0] value; reg [31:0] c; integer k;
 begin c=previous^{24'd0,value}; for(k=0;k<8;k=k+1)c=c[0]?((c>>1)^32'hedb88320):(c>>1); ui_crc=c; end
endfunction
function [7:0] ui_header;
 input sender; input [31:0] seq; input [8:0] offset;
 begin case(offset)
  0,1,2,3,4,5:ui_header=8'hff;
  6:ui_header=2;7:ui_header=8'h54;8:ui_header=8'h4d;9,10:ui_header=0;11:ui_header=sender?2:1;
  12:ui_header=8'h88;13:ui_header=8'hb5;
  14:ui_header=8'h54;15:ui_header=8'h4d;16:ui_header=8'h55;17:ui_header=8'h49;
  18:ui_header=1;19:ui_header={7'd0,sender};20:ui_header=1;21:ui_header=0;
  22:ui_header=seq[31:24];23:ui_header=seq[23:16];24:ui_header=seq[15:8];25:ui_header=seq[7:0];
  26:ui_header=~seq[31:24];27:ui_header=~seq[23:16];28:ui_header=~seq[15:8];29:ui_header=~seq[7:0];
  default:ui_header=0;
 endcase end
endfunction
