`timescale 1ns/1ps
// 20Hz fixed 16-byte binary frames. Snapshot prevents mixed measurements.
module flute_telemetry #(parameter integer CLK_HZ=50000000)(
    input wire clk,rst_n,input wire [7:0] keys,gain,
    input wire [6:0] note,input wire calibrated,gate,fault,fingering_valid,
    input wire [11:0] pressure,supply,baseline,delta,
    input wire tx_ready,output wire tx_valid,output reg [7:0] tx_data
);
    reg [31:0] timer;reg busy;reg [4:0] index;reg [7:0] seq,sum;
    reg [7:0] snapshot[0:13];integer i;
    assign tx_valid=busy;
    always @* begin
        case(index)
            0:tx_data=8'h46;1:tx_data=8'h4c;
            15:tx_data=sum;
            default:tx_data=snapshot[index-2];
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin timer<=0;busy<=0;index<=0;seq<=0;sum<=0;
            for(i=0;i<14;i=i+1) snapshot[i]<=0;
        end else begin
            if(timer==CLK_HZ/20-1) begin
                timer<=0;
                if(!busy) begin
                    snapshot[0]<=seq;seq<=seq+1'b1;
                    snapshot[1]<={4'b0,fingering_valid,fault,gate,calibrated};
                    snapshot[2]<=keys;snapshot[3]<={1'b0,note};snapshot[4]<=gain;
                    snapshot[5]<=pressure[7:0];snapshot[6]<={4'b0,pressure[11:8]};
                    snapshot[7]<=supply[7:0];snapshot[8]<={4'b0,supply[11:8]};
                    snapshot[9]<=baseline[7:0];snapshot[10]<={4'b0,baseline[11:8]};
                    snapshot[11]<=delta[7:0];snapshot[12]<={4'b0,delta[11:8]};
                    busy<=1;index<=0;sum<=0;
                end
            end else timer<=timer+1'b1;
            if(busy && tx_ready) begin
                sum<=sum+tx_data;
                if(index==15) begin busy<=0;index<=0;end else index<=index+1'b1;
            end
        end
    end
endmodule
