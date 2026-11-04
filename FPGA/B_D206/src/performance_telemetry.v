// 64-byte immutable snapshots at 50 Hz, CRC16-CCITT-FALSE, little-endian CRC.
module performance_telemetry #(
    parameter integer CLK_HZ=50000000,REPORT_HZ=50
)(
    input wire clk,rst_n,
    input wire [511:0] snapshot_in,
    output wire [7:0] tx_data,
    output wire tx_valid,
    input wire tx_ready
);
    reg [511:0] packet;
    reg [5:0] index;
    reg [15:0] crc,seq;
    reg [31:0] ticks,ms_ticks,uptime_ms;
    reg active;
    assign tx_valid=active;
    assign tx_data=(index==62) ? crc[7:0] : (index==63 ? crc[15:8] : packet[index*8+:8]);
    function [15:0] crc_byte;
        input [15:0] c;input [7:0] b;reg [15:0] v;integer k;
        begin
            v=c^{b,8'b0};
            for(k=0;k<8;k=k+1) v=v[15] ? (v<<1)^16'h1021 : v<<1;
            crc_byte=v;
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin packet<=0;index<=0;crc<=16'hffff;seq<=0;ticks<=0;active<=0;ms_ticks<=0;uptime_ms<=0;end
        else begin
            if(ms_ticks==CLK_HZ/1000-1) begin ms_ticks<=0;uptime_ms<=uptime_ms+1'b1;end
            else ms_ticks<=ms_ticks+1'b1;
            if(ticks==CLK_HZ/REPORT_HZ-1) begin
                ticks<=0;
                if(!active) begin
                    packet<=snapshot_in;
                    packet[0+:32]<=32'h40045aa5;
                    packet[4*8+:16]<=seq;
                    packet[44*8+:32]<=uptime_ms;
                    seq<=seq+1'b1;index<=0;crc<=16'hffff;active<=1;
                end
            end else ticks<=ticks+1'b1;
            if(active && tx_ready) begin
                if(index<62) crc<=crc_byte(crc,tx_data);
                if(index==63) begin active<=0;index<=0;end
                else index<=index+1'b1;
            end
        end
    end
endmodule
