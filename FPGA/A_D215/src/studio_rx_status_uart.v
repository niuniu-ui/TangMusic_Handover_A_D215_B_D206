`timescale 1ns/1ps
// Read-only host-domain diagnostics; does not backpressure network or audio.
module studio_rx_status_uart #(
 parameter integer CLK_HZ=50000000,BAUD=115200,REPORT_CYCLES=50000000
)(input wire clk,rst_n,link_up,peer_alive,received,pcm_peer,
 input wire [3:0] usb_status,input wire [9:0] down,x,y,input wire [7:0] event_sequence,
 input wire [6:0] piano_key,piano_velocity,piano_mapped,piano_level,master_level,
 input wire [1:0] piano_group,input wire [31:0] piano_active,
 input wire [15:0] piano_peak,raw_count,note_count,input wire muted,
 output wire tx);
 localparam integer N=121,BIT_CYCLES=(CLK_HZ+BAUD/2)/BAUD;
 reg [N*8-1:0] message=0;reg [7:0] bytes_left=0;reg [3:0] bits_left=0;
 reg [9:0] shift=10'h3ff;reg [31:0] report_timer=0,bit_timer=0;
 reg [15:0] good=0;
 assign tx=shift[0];
 function [7:0] hex_digit;input [3:0] value;begin hex_digit=value<10?8'h30+value:8'h41+value-10;end endfunction
 function [7:0] digit;input value;begin digit=value?"1":"0";end endfunction
 always @(posedge clk)begin
  if(!rst_n)begin
   message<=0;bytes_left<=0;bits_left<=0;shift<=10'h3ff;report_timer<=0;bit_timer<=0;good<=0;
  end else begin
   if(received&&good!=65535)good<=good+1'b1;
   if(report_timer==REPORT_CYCLES-1)report_timer<=0;else report_timer<=report_timer+1'b1;
   if(bits_left!=0)begin
    if(bit_timer==0)begin shift<={1'b1,shift[9:1]};bits_left<=bits_left-1'b1;bit_timer<=BIT_CYCLES-1;end
    else bit_timer<=bit_timer-1'b1;
   end else if(bytes_left!=0)begin
    shift<={1'b1,message[N*8-1-:8],1'b0};message<=message<<8;
    bytes_left<=bytes_left-1'b1;bits_left<=10;bit_timer<=BIT_CYCLES-1;
   end
   if(report_timer==REPORT_CYCLES-1&&bytes_left==0&&bits_left==0)begin
    message<={"ARX0 L=",digit(link_up)," R=",digit(peer_alive)," G=",
     hex_digit(good[15:12]),hex_digit(good[11:8]),hex_digit(good[7:4]),hex_digit(good[3:0]),
     " S=",hex_digit(usb_status)," D=",hex_digit({2'b0,down[9:8]}),hex_digit(down[7:4]),hex_digit(down[3:0]),
     " X=",hex_digit({2'b0,x[9:8]}),hex_digit(x[7:4]),hex_digit(x[3:0]),
     " Y=",hex_digit({2'b0,y[9:8]}),hex_digit(y[7:4]),hex_digit(y[3:0]),
     " E=",hex_digit(event_sequence[7:4]),hex_digit(event_sequence[3:0])," P=",digit(pcm_peer),
     " K=",
     hex_digit({1'b0,piano_key[6:4]}),
     hex_digit(piano_key[3:0]),
     " V=",
     hex_digit({1'b0,piano_velocity[6:4]}),
     hex_digit(piano_velocity[3:0]),
     " M=",
     hex_digit({1'b0,piano_mapped[6:4]}),
     hex_digit(piano_mapped[3:0]),
     " O=",
     hex_digit({2'b0,piano_group[1:0]}),
     " A=",
     hex_digit(piano_active[31:28]),
     hex_digit(piano_active[27:24]),
     hex_digit(piano_active[23:20]),
     hex_digit(piano_active[19:16]),
     hex_digit(piano_active[15:12]),
     hex_digit(piano_active[11:8]),
     hex_digit(piano_active[7:4]),
     hex_digit(piano_active[3:0]),
     " Q=",
     hex_digit(piano_peak[15:12]),
     hex_digit(piano_peak[11:8]),
     hex_digit(piano_peak[7:4]),
     hex_digit(piano_peak[3:0]),
     " RC=",
     hex_digit(raw_count[15:12]),
     hex_digit(raw_count[11:8]),
     hex_digit(raw_count[7:4]),
     hex_digit(raw_count[3:0]),
     " NC=",
     hex_digit(note_count[15:12]),
     hex_digit(note_count[11:8]),
     hex_digit(note_count[7:4]),
     hex_digit(note_count[3:0]),
     " PV=",
     hex_digit({1'b0,piano_level[6:4]}),
     hex_digit(piano_level[3:0]),
     " MV=",
     hex_digit({1'b0,master_level[6:4]}),
     hex_digit(master_level[3:0]),
     " U=",
     digit(muted),
     8'h0d,
     8'h0a};
    bytes_left<=N;good<=0;
   end
  end
 end
endmodule
