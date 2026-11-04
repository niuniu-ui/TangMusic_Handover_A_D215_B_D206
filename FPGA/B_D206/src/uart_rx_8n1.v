// Asynchronous 3.3 V UART input, LSB first, 8N1. No flow control.
module uart_rx_8n1 #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200
)(
    input wire clk, input wire rst_n, input wire rx,
    output reg [7:0] data, output reg valid, output reg frame_error
);
    localparam integer BIT_CYCLES = (CLK_HZ + BAUD/2) / BAUD;
    localparam integer TIMER_W = $clog2(BIT_CYCLES + 1);
    localparam [2:0] IDLE=0, START=1, DATA=2, STOP=3, WAIT_HIGH=4;
    (* syn_preserve = 1 *) reg rx_meta, rx_sync;
    reg [2:0] state;
    reg [TIMER_W-1:0] timer;
    reg [2:0] bit_index;
    reg [7:0] shift;

    always @(posedge clk) begin
        if (!rst_n) begin rx_meta <= 1'b1; rx_sync <= 1'b1; end
        else begin rx_meta <= rx; rx_sync <= rx_meta; end
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= WAIT_HIGH;
            timer <= 0; bit_index <= 0; shift <= 0;
            data <= 0; valid <= 0; frame_error <= 0;
        end else begin
            valid <= 0; frame_error <= 0;
            case (state)
                WAIT_HIGH: if (rx_sync) state <= IDLE;
                IDLE: if (!rx_sync) begin
                    timer <= BIT_CYCLES/2-1;
                    state <= START;
                end
                START: if (timer != 0) timer <= timer-1'b1;
                    else if (!rx_sync) begin
                        timer <= BIT_CYCLES-1; bit_index <= 0; state <= DATA;
                    end else state <= IDLE; // Reject short start glitches.
                DATA: if (timer != 0) timer <= timer-1'b1;
                    else begin
                        shift[bit_index] <= rx_sync;
                        timer <= BIT_CYCLES-1;
                        if (bit_index == 7) state <= STOP;
                        else bit_index <= bit_index+1'b1;
                    end
                STOP: if (timer != 0) timer <= timer-1'b1;
                    else if (rx_sync) begin
                        data <= shift; valid <= 1; state <= IDLE;
                    end else begin
                        frame_error <= 1; state <= WAIT_HIGH;
                    end // A sustained break produces one error, then waits for high.
                default: state <= WAIT_HIGH;
            endcase
        end
    end
endmodule
