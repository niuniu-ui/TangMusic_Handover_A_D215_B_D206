`timescale 1ns/1ps
// DVI TMDS encoding, registered output, least significant bit sent first.
// The running disparity resets on every blanking/control symbol.
module tmds_encoder (
    input wire pixel_clk,
    input wire reset,
    input wire de,
    input wire [7:0] data,
    input wire [1:0] control,
    output reg [9:0] symbol
);
    reg [8:0] qm;
    integer i, ones_data, ones_qm;
    reg use_xnor;
    reg signed [5:0] disparity = 0;
    reg signed [5:0] balance;
    always @* begin
        ones_data = 0;
        for (i = 0; i < 8; i = i + 1) ones_data = ones_data + data[i];
        use_xnor = (ones_data > 4) || ((ones_data == 4) && !data[0]);
        qm[0] = data[0];
        for (i = 1; i < 8; i = i + 1)
            qm[i] = qm[i-1] ^ data[i] ^ use_xnor;
        qm[8] = !use_xnor;
        ones_qm = 0;
        for (i = 0; i < 8; i = i + 1) ones_qm = ones_qm + qm[i];
        balance = $signed({1'b0, ones_qm[3:0], 1'b0}) - 6'sd8;
    end
    always @(posedge pixel_clk) begin
        if (reset) begin
            symbol <= 10'b1101010100;
            disparity <= 0;
        end else if (!de) begin
            case (control)
                2'b00: symbol <= 10'b1101010100;
                2'b01: symbol <= 10'b0010101011;
                2'b10: symbol <= 10'b0101010100;
                2'b11: symbol <= 10'b1010101011;
            endcase
            disparity <= 0;
        end else if ((disparity == 0) || (balance == 0)) begin
            symbol <= {~qm[8], qm[8], (qm[8] ? qm[7:0] : ~qm[7:0])};
            if (qm[8]) disparity <= disparity + balance;
            else       disparity <= disparity - balance;
        end else if (((disparity > 0) && (balance > 0)) ||
                     ((disparity < 0) && (balance < 0))) begin
            symbol <= {1'b1, qm[8], ~qm[7:0]};
            disparity <= disparity - balance + (qm[8] ? 6'sd2 : 6'sd0);
        end else begin
            symbol <= {1'b0, qm[8], qm[7:0]};
            disparity <= disparity + balance - (qm[8] ? 6'sd0 : 6'sd2);
        end
    end
endmodule
