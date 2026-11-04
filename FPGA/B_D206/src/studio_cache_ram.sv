// Four byte lanes: 16 KiB total. Host port is read/write; pixel port is read-only.
// At boot, host uses individual byte writes for LZ history. Afterwards each write
// stores four adjacent palette indices. No cache data is copied at the handover.
module studio_cache_ram(
 input wire host_clk,input wire [11:0] host_address,
 input wire [31:0] host_write_data,input wire [3:0] host_write_mask,
 output wire [31:0] host_read_data,
 input wire pixel_clk,input wire [11:0] pixel_address,output wire [31:0] pixel_read_data
);
 genvar lane;
 generate for(lane=0;lane<4;lane=lane+1)begin:bytes
  (* syn_ramstyle="block_ram" *) reg [7:0] memory[0:4095];
  reg [7:0] host_q,pixel_q;
  always @(posedge host_clk)begin
   // GW5AST DPB supports normal/write-through, not read-before-write (mode 2).
   // No client consumes host_q during a write; explicit bypass infers mode 1.
   if(host_write_mask[lane])begin
    memory[host_address]<=host_write_data[lane*8+:8];
    host_q<=host_write_data[lane*8+:8];
   end else host_q<=memory[host_address];
  end
  always @(posedge pixel_clk)pixel_q<=memory[pixel_address];
  assign host_read_data[lane*8+:8]=host_q;
  assign pixel_read_data[lane*8+:8]=pixel_q;
 end endgenerate
endmodule
