`timescale 1ns/1ps
// Multi-Touch-V5000 222a:0001, report 15h, 52 bytes. Field positions were
// measured using Windows HidP capabilities, not inferred from screen EDID.
module touch_report (
    input wire clk, reset, begin_report, byte_valid, commit,
    input wire [5:0] byte_index,
    input wire [7:0] byte_data,
    output reg updated, rejected, pressed,
    output reg [9:0] x, y,
    output reg [3:0] contacts,
    output reg [9:0] contact_down,
    output reg [99:0] contact_x, contact_y,
    output reg [59:0] contact_id
);
    reg [7:0] id, count, status;
    reg [15:0] raw_x;
    reg [7:0] y_low;
    reg [2:0] field;
    reg found, invalid;
    reg [9:0] candidate_x, candidate_y;
    reg [5:0] received;
    reg [3:0] slot;
    reg [9:0] pending_down;
    reg [99:0] pending_x, pending_y;
    reg [59:0] pending_id;
    reg [63:0] seen_ids;
    wire [15:0] raw_y = {byte_data,y_low};
    always @(posedge clk) begin
        updated <= 0; rejected <= 0;
        if (reset) begin
            pressed <= 0; x <= 512; y <= 300; contacts <= 0;
            id <= 0; count <= 0; status <= 0; raw_x <= 0; y_low <= 0;
            field <= 0; found <= 0; invalid <= 0; received <= 0;
            candidate_x <= 0; candidate_y <= 0;
            contact_down <= 0; contact_x <= 0; contact_y <= 0; contact_id <= 0;
            pending_down <= 0; pending_x <= 0; pending_y <= 0; pending_id <= 0;
            seen_ids <= 0; slot <= 0;
        end else begin
            if (begin_report) begin
                found <= 0; invalid <= 0; field <= 0; received <= 0;
                pending_down <= 0; pending_x <= 0; pending_y <= 0; pending_id <= 0;
                seen_ids <= 0; slot <= 0;
            end
            if (byte_valid) begin
                if (byte_index != received) invalid <= 1;
                received <= received + 1'b1;
                if (byte_index == 0) id <= byte_data;
                else if (byte_index == 51) count <= byte_data;
                else begin
                    field <= field == 4 ? 3'd0 : field + 3'd1;
                    case (field)
                        0: status <= byte_data;
                        1: raw_x[7:0] <= byte_data;
                        2: raw_x[15:8] <= byte_data;
                        3: y_low <= byte_data;
                        4: begin
                            slot <= slot + 1'b1;
                            if (slot >= 10) invalid <= 1;
                            else begin
                                pending_id[slot*6 +: 6] <= status[5:0];
                                if (status[6]) begin
                                    if (raw_x > 1024 || raw_y > 600 || seen_ids[status[5:0]]) invalid <= 1;
                                    seen_ids[status[5:0]] <= 1;
                                    pending_down[slot] <= 1;
                                    pending_x[slot*10 +: 10] <= raw_x >= 1024 ? 10'd1023 : raw_x[9:0];
                                    pending_y[slot*10 +: 10] <= raw_y >= 600 ? 10'd599 : raw_y[9:0];
                                    if (!found) begin
                                        found <= 1;
                                        candidate_x <= raw_x >= 1024 ? 10'd1023 : raw_x[9:0];
                                        candidate_y <= raw_y >= 600 ? 10'd599 : raw_y[9:0];
                                    end
                                end
                            end
                        end
                        default: invalid <= 1;
                    endcase
                end
            end
            if (commit) begin
                if (id == 8'h15 && count <= 10 && received == 52 && !invalid) begin
                    contacts <= count[3:0]; pressed <= found && count != 0; updated <= 1;
                    contact_down <= count != 0 ? pending_down : 10'b0;
                    contact_x <= pending_x; contact_y <= pending_y; contact_id <= pending_id;
                    if (found && count != 0) begin x <= candidate_x; y <= candidate_y; end
                end else rejected <= 1;
            end
        end
    end
endmodule
