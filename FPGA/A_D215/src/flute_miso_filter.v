`timescale 1ns/1ps
// Synchronize first, then reject narrow pulses with a five-sample majority.
// At 21MHz the latency is below 0.4us; SPI100kHz supplies a 5us half-cycle.
module flute_miso_filter(input wire clk,rst_n,miso_raw,output wire miso_clean);
    (* syn_preserve=1 *) reg [1:0] sync=0;
    reg [4:0] window=0;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin sync<=0;window<=0;end
        else begin sync<={sync[0],miso_raw};window<={window[3:0],sync[1]};end
    wire [2:0] ones={2'b0,window[0]}+{2'b0,window[1]}+{2'b0,window[2]}+
        {2'b0,window[3]}+{2'b0,window[4]};
    assign miso_clean=ones>=3;
endmodule
