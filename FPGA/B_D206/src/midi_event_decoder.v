// MIDI channel messages 8n/9n/An/Bn, with optional running status.
// Retain the raw channel status across complete events, including velocity-0
// Note On releases. Realtime bytes never change the pending message/status.
// Unsupported statuses (including SysEx/common) cancel the retained status.
module midi_event_decoder #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200,
    parameter integer GAP_TIMEOUT_MS = 10
)(
    input wire clk, input wire rst_n, input wire uart_rx,
    output reg event_valid,
    output reg [3:0] event_kind, channel_zero,
    output reg [6:0] key_or_cc, value,
    output reg [31:0] event_count, byte_count, framing_errors, timeout_errors
) /* synthesis syn_preserve = 1 */;
    localparam integer GAP_CYCLES = (CLK_HZ/1000)*GAP_TIMEOUT_MS;
    localparam integer GAP_W = $clog2(GAP_CYCLES+1);
    wire [7:0] rx_data;
    wire rx_valid, rx_error;
    reg [1:0] phase;
    reg [7:0] status;
    reg status_valid;
    reg [6:0] first_data;
    reg [GAP_W-1:0] gap_timer;
    uart_rx_8n1 #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
        .clk(clk), .rst_n(rst_n), .rx(uart_rx), .data(rx_data),
        .valid(rx_valid), .frame_error(rx_error)
    );
    always @(posedge clk) begin
        if (!rst_n) begin
            phase <= 0; status <= 0; status_valid <= 0; first_data <= 0; gap_timer <= 0;
            event_valid <= 0; event_kind <= 0; channel_zero <= 0;
            key_or_cc <= 0; value <= 0;
            event_count <= 0; byte_count <= 0;
            framing_errors <= 0; timeout_errors <= 0;
        end else begin
            event_valid <= 0;
            if (rx_error) begin
                phase <= 0; status_valid <= 0; gap_timer <= 0;
                framing_errors <= framing_errors+1'b1;
            end else if (rx_valid) begin
                byte_count <= byte_count+1'b1;
                gap_timer <= 0;
                if (rx_data >= 8'hF8) begin
                    // Realtime messages can occur between the three bytes.
                end else if (rx_data[7]) begin
                    if (rx_data[7:4] >= 4'h8 && rx_data[7:4] <= 4'hB) begin
                        status <= rx_data; status_valid <= 1; phase <= 1;
                    end else begin phase <= 0; status_valid <= 0; end
                end else if (phase == 1 || (phase == 0 && status_valid)) begin
                    first_data <= rx_data[6:0]; phase <= 2;
                end else if (phase == 2) begin
                    event_kind <= (status[7:4] == 4'h9 && rx_data == 0) ? 4'h8 : status[7:4];
                    channel_zero <= status[3:0]; key_or_cc <= first_data;
                    value <= rx_data[6:0]; event_valid <= 1;
                    event_count <= event_count+1'b1; phase <= 0;
                end
            end else if (phase != 0) begin
                if (gap_timer == GAP_CYCLES-1) begin
                    phase <= 0; status_valid <= 0; gap_timer <= 0;
                    timeout_errors <= timeout_errors+1'b1;
                end else gap_timer <= gap_timer+1'b1;
            end else gap_timer <= 0; // Idle running status is not a partial packet.
        end
    end
endmodule
