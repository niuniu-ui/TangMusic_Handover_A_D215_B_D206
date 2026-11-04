`timescale 1ns/1ps
module flute_keys #(parameter integer CLK_HZ=50000000, STABLE_MS=3)(
    input wire clk,rst_n,input wire [7:0] keys_n,
    output reg [7:0] pressed
);
    (* syn_preserve=1 *) reg [7:0] sync1,sync2;
    reg [31:0] tick;
    reg [15:0] count[0:7];
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            sync1<=8'hff;sync2<=8'hff;pressed<=0;tick<=0;
            for(i=0;i<8;i=i+1) count[i]<=0;
        end else begin
            sync1<=keys_n;sync2<=sync1;
            if(tick==CLK_HZ/1000-1) begin
                tick<=0;
                for(i=0;i<8;i=i+1) begin
                    if((!sync2[i])==pressed[i]) count[i]<=0;
                    else if(count[i]==STABLE_MS-1) begin pressed[i]<=!sync2[i];count[i]<=0;end
                    else count[i]<=count[i]+1'b1;
                end
            end else tick<=tick+1'b1;
        end
    end
endmodule
