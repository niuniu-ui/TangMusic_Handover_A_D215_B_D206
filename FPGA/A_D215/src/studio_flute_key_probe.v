`timescale 1ns/1ps
// Read-only, pre-debounce key timing probe on the existing 50 MHz clock.
// Every newly observed active-low key produces one asserted clock cycle.
// This is independent of breath, fingering, calibration and musical debounce.
// Two synchronizer stages plus registered edge detection give approximately
// 40--60 ns from an asynchronous input transition to the pulse, not 3 ms.
// Consecutive-cycle events can form adjacent high cycles; no event is stretched
// or deliberately delayed to insert a low gap. Simultaneous keys share a pulse.
module studio_flute_key_probe(
 input wire clk,rst_n,
 input wire [7:0] keys_n,
 output reg press_pulse,
 output reg [7:0] new_pressed
);
 (* syn_preserve=1 *) reg [7:0] keys_meta,keys_sync;
 reg [7:0] keys_previous;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   keys_meta<=8'hff;keys_sync<=8'hff;keys_previous<=8'hff;
   press_pulse<=1'b0;new_pressed<=8'h00;
  end else begin
   keys_meta<=keys_n;keys_sync<=keys_meta;keys_previous<=keys_sync;
   new_pressed<=keys_previous&~keys_sync;
   press_pulse<=|(keys_previous&~keys_sync);
  end
 end
endmodule
