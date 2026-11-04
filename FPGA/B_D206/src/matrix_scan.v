// 8 driven rows, 8 active-low sense columns; two adjacent contacts per key.
// drive_low is an output-enable mask: the physical pin must drive 0 or Z only.
module matrix_scan #(
    parameter integer RELEASE_CYCLES = 750,
    parameter integer SETTLE_CYCLES = 500,
    parameter integer DEBOUNCE_FRAMES = 10
)(
    input wire clk,
    input wire rst,
    input wire [7:0] sense_in,
    input wire [7:0] drive_in,
    output wire [7:0] drive_low,
    output reg [31:0] keys,
    output reg [63:0] contacts,
    output reg frame_valid,
    output reg [7:0] idle_low,
    output reg [7:0] drive_fail
);
    localparam integer MAX_CYCLES = RELEASE_CYCLES > SETTLE_CYCLES ? RELEASE_CYCLES : SETTLE_CYCLES;
    localparam integer CW = MAX_CYCLES > 1 ? $clog2(MAX_CYCLES) : 1;
    localparam integer DW = DEBOUNCE_FRAMES > 1 ? $clog2(DEBOUNCE_FRAMES) : 1;
    (* syn_preserve = 1 *) reg [7:0] sense_meta, sense_sync;
    (* syn_preserve = 1 *) reg [7:0] drive_meta, drive_sync;
    reg active;
    reg [2:0] row;
    reg [CW-1:0] ticks;
    reg [DW-1:0] count [0:31];
    reg [7:0] idle_accum, fail_accum;
    wire [7:0] closed = ~sense_sync;
    wire [7:0] row_mask = 8'b1 << row;
    assign drive_low = (active && !rst) ? row_mask : 8'b0;
    integer k;
    integer key_idx;

    always @(posedge clk) begin
        if (rst) begin
            sense_meta <= 8'hff;
            sense_sync <= 8'hff;
            drive_meta <= 8'hff;
            drive_sync <= 8'hff;
        end else begin
            sense_meta <= sense_in;
            sense_sync <= sense_meta;
            drive_meta <= drive_in;
            drive_sync <= drive_meta;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            active <= 0;
            row <= 0;
            ticks <= 0;
            keys <= 0;
            contacts <= 0;
            frame_valid <= 0;
            idle_accum <= 0;
            fail_accum <= 0;
            idle_low <= 0;
            drive_fail <= 0;
            for (k = 0; k < 32; k = k + 1) count[k] <= 0;
        end else begin
            frame_valid <= 0;
            if (!active) begin
                if (ticks == RELEASE_CYCLES-1) begin
                    ticks <= 0;
                    active <= 1;
                    // Measure columns with ALL rows released, before driving.
                    if (row == 0) begin
                        idle_accum <= ~sense_sync;
                        fail_accum <= 0;
                    end else idle_accum <= idle_accum | ~sense_sync;
                end else ticks <= ticks + 1'b1;
            end else begin
                if (ticks == SETTLE_CYCLES-1) begin
                    ticks <= 0;
                    active <= 0;
                    contacts[row*8 +: 8] <= closed;
                    fail_accum <= fail_accum | (drive_sync & row_mask);
                    for (k = 0; k < 4; k = k + 1) begin
                        key_idx = row*4 + k;
                        // Press = either contact; release = both contacts open.
                        if ((|closed[k*2 +: 2]) == keys[key_idx]) begin
                            count[key_idx] <= 0;
                        end else if (count[key_idx] == DEBOUNCE_FRAMES-1) begin
                            keys[key_idx] <= |closed[k*2 +: 2];
                            count[key_idx] <= 0;
                        end else count[key_idx] <= count[key_idx] + 1'b1;
                    end
                    if (row == 7) begin
                        frame_valid <= 1;
                        idle_low <= idle_accum;
                        drive_fail <= fail_accum | (drive_sync & row_mask);
                    end
                    row <= row + 1'b1;
                end else ticks <= ticks + 1'b1;
            end
        end
    end
endmodule
