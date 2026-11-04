`timescale 1ns/1ps
// Dedicated direct-connect FS host for the measured 222a:0001 firmware.
// No hubs, low/high-speed, generic HID, keyboard or mouse support.
// Both standard control-transfer status stages and endpoint DATA toggles are
// implemented. Physical reset/re-enumeration recovers unplug and protocol errors.
module usb_touch_host #(
    parameter integer ATTACH_CYCLES = 6000000,
    parameter integer RESET_CYCLES = 720000,
    parameter integer RECOVER_CYCLES = 600000,
    parameter integer FRAME_CYCLES = 60000,
    parameter integer DISCONNECT_CYCLES = 9000
)(
    input wire clk, reset,
    input wire dp_i, dm_i,
    output wire dp_o, dm_o, oe,
    output reg [1:0] status, // 0 absent, 1 enumerating, 2 ready, 3 fault/retry
    output wire pressed,
    output wire [9:0] touch_x, touch_y,
    output wire [3:0] contacts,
    output wire updated,
    output reg [7:0] error_count,
    output wire [9:0] contact_down,
    output wire [99:0] contact_x, contact_y,
    output wire [59:0] contact_id
);
    localparam ATTACH=0, BUS_RESET=1, RECOVER=2, SETUP_READY=3, SETUP_WAIT=4,
               READ_READY=5, READ_WAIT=6, COPY_DESC=7, STATUS_READY=8, STATUS_WAIT=9,
               NEXT_CONTROL=10, ADDRESS_WAIT=11, POLL_READY=12, POLL_WAIT=13,
               COPY_REPORT=14, COMMIT_REPORT=15, FAULT=16, REPORT_ARM=17;
    reg [4:0] state;
    reg [23:0] delay_count;
    reg [19:0] retry_delay;
    reg [15:0] frame_cycle;
    reg [10:0] frame_number;
    reg frame_pending, sof_busy;
    reg [13:0] disconnected;
    reg [10:0] enumeration_ms;
    reg [3:0] poll_ms;
    reg [2:0] control_step;
    reg [6:0] device_address, descriptor_offset;
    reg [5:0] read_index;
    reg [6:0] copy_length;
    reg ctrl_toggle, poll_toggle, descriptor_bad;
    reg [3:0] failures;
    reg transaction_start;
    reg [1:0] transaction_kind;
    reg [3:0] transaction_ep;
    wire transaction_busy, transaction_done;
    wire [1:0] result;
    wire packet_toggle;
    wire [6:0] packet_length;
    wire [7:0] read_data;
    wire phy_dp, phy_dm, phy_oe, line_j, line_se0;
    reg [63:0] setup_data;
    wire bus_reset = state == BUS_RESET;
    wire engine_reset = reset || state == ATTACH || bus_reset || state == FAULT;
    assign oe = bus_reset || phy_oe;
    assign dp_o = bus_reset ? 1'b0 : phy_dp;
    assign dm_o = bus_reset ? 1'b0 : phy_dm;
    wire frame_enabled = state != ATTACH && state != BUS_RESET && state != FAULT;
    wire frame_tick = frame_cycle == FRAME_CYCLES-1;
    wire ready_state = state == RECOVER || state == SETUP_READY || state == READ_READY ||
                       state == STATUS_READY || state == ADDRESS_WAIT || state == POLL_READY;
    wire read_control = control_step == 0 || control_step == 2;
    wire [6:0] descriptor_size = control_step == 0 ? 7'd18 : 7'd84;
    wire [6:0] absolute_index = descriptor_offset + {1'b0,read_index};
    wire [7:0] descriptor_end = {1'b0,descriptor_offset} + {1'b0,packet_length};

    always @* begin
        case (control_step)
            0: setup_data = {16'd18,16'd0,16'h0100,8'h06,8'h80}; // GET_DEVICE
            1: setup_data = {16'd0,16'd0,16'd1,8'h05,8'h00}; // SET_ADDRESS
            2: setup_data = {16'd84,16'd0,16'h0200,8'h06,8'h80}; // GET_CONFIG
            3: setup_data = {16'd0,16'd0,16'd1,8'h09,8'h00}; // SET_CONFIG
            4: setup_data = {16'd0,16'd0,16'd0,8'h0a,8'h21}; // SET_IDLE(interface 0)
            default: setup_data = {16'd0,16'd0,16'd1,8'h0b,8'h21}; // SET_PROTOCOL(report)
        endcase
    end
    usb_fs_transaction transaction(.clk(clk), .reset(engine_reset), .start(transaction_start),
        .kind(transaction_kind), .address(device_address), .endpoint(transaction_ep),
        .frame_number(frame_number), .setup_data(setup_data), .dp_i(dp_i), .dm_i(dm_i),
        .dp_o(phy_dp), .dm_o(phy_dm), .oe(phy_oe), .line_j(line_j), .line_se0(line_se0),
        .busy(transaction_busy), .done(transaction_done), .result(result),
        .data_toggle(packet_toggle), .data_length(packet_length), .read_index(read_index), .read_data(read_data));

    // Exact measured configuration: three HID interfaces, touchscreen endpoint
    // 81h, max packet 64, interval 10 ms. Refuse a different firmware layout.
    function [7:0] expected_config;
        input [6:0] n;
        reg [671:0] bytes_le;
        begin
            bytes_le = 672'h0a004003830507004e220121011121090002010301000204090a004003820507002e220121011121090001010301000104090a00400381050702ed2201210111210900000103010000040932a000010300540209;
            expected_config = bytes_le[8*n +: 8];
        end
    endfunction
    reg report_begin, report_commit;
    wire report_rejected;
    touch_report parser(.clk(clk), .reset(reset || status != 2), .begin_report(report_begin),
        .byte_valid(state == COPY_REPORT), .byte_index(read_index), .byte_data(read_data),
        .commit(report_commit), .updated(updated), .rejected(report_rejected),
        .pressed(pressed), .x(touch_x), .y(touch_y), .contacts(contacts),
        .contact_down(contact_down), .contact_x(contact_x), .contact_y(contact_y), .contact_id(contact_id));

    // A task here only schedules a transaction; it has no synthesizable delay.
    task launch;
        input [1:0] kind; input [3:0] ep; input [4:0] next_state;
        begin transaction_kind <= kind; transaction_ep <= ep; transaction_start <= 1; state <= next_state; end
    endtask
    task retry;
        input [4:0] next_state;
        begin
            retry_delay <= FRAME_CYCLES;
            if (result == 1) state <= next_state;
            else begin
                error_count <= error_count + 1'b1;
                failures <= failures + 1'b1;
                if (failures == 7) begin state <= FAULT; delay_count <= 0; status <= 3; end
                else state <= next_state;
            end
        end
    endtask

    always @(posedge clk) begin
        transaction_start <= 0; report_begin <= 0; report_commit <= 0;
        if (reset) begin
            state <= ATTACH; status <= 0; delay_count <= 0; retry_delay <= 0;
            frame_cycle <= 0; frame_number <= 0; frame_pending <= 0; sof_busy <= 0;
            disconnected <= 0; enumeration_ms <= 0; poll_ms <= 0;
            control_step <= 0; device_address <= 0; descriptor_offset <= 0;
            read_index <= 0; copy_length <= 0; ctrl_toggle <= 1; poll_toggle <= 0;
            descriptor_bad <= 0; failures <= 0; error_count <= 0;
            transaction_kind <= 0; transaction_ep <= 0;
        end else begin
            if (retry_delay != 0) retry_delay <= retry_delay - 1'b1;
            if (!frame_enabled) begin
                frame_cycle <= 0; frame_number <= 0; frame_pending <= 0; sof_busy <= 0;
                enumeration_ms <= 0; disconnected <= 0;
            end else begin
                if (frame_tick) begin
                    frame_cycle <= 0; frame_number <= frame_number + 1'b1; frame_pending <= 1;
                    if (status == 1) enumeration_ms <= enumeration_ms + 1'b1;
                    if (poll_ms < 10) poll_ms <= poll_ms + 1'b1;
                end else frame_cycle <= frame_cycle + 1'b1;
                if (!oe && line_se0) disconnected <= disconnected + 1'b1;
                else disconnected <= 0;
            end
            if (sof_busy) begin
                if (transaction_done) sof_busy <= 0;
            end else if (ready_state && frame_pending && !transaction_busy && !transaction_start) begin
                transaction_kind <= 3; transaction_ep <= 0; transaction_start <= 1;
                sof_busy <= 1; frame_pending <= frame_tick;
            end else case(state)
                ATTACH: begin
                    device_address <= 0; control_step <= 0; failures <= 0; retry_delay <= 0;
                    if (line_j) begin
                        if (delay_count == ATTACH_CYCLES-1) begin
                            state <= BUS_RESET; delay_count <= 0; status <= 1;
                        end else delay_count <= delay_count + 1'b1;
                    end else delay_count <= 0;
                end
                BUS_RESET: begin
                    if (delay_count == RESET_CYCLES-1) begin state <= RECOVER; delay_count <= 0; end
                    else delay_count <= delay_count + 1'b1;
                end
                RECOVER: begin
                    if (delay_count >= RECOVER_CYCLES-1) begin state <= SETUP_READY; delay_count <= 0; end
                    else delay_count <= delay_count + 1'b1;
                end
                SETUP_READY: if (retry_delay == 0) begin
                    descriptor_offset <= 0; descriptor_bad <= 0; ctrl_toggle <= 1;
                    launch(1,0,SETUP_WAIT);
                end
                SETUP_WAIT: if (transaction_done) begin
                    if (result == 0) begin failures <= 0; state <= read_control ? READ_READY : STATUS_READY; end
                    else if (result == 2 && control_step >= 4) state <= NEXT_CONTROL;
                    else retry(SETUP_READY);
                end
                READ_READY: if (retry_delay == 0) launch(0,0,READ_WAIT);
                READ_WAIT: if (transaction_done) begin
                    if (result != 0) retry(READ_READY);
                    else if (packet_toggle != ctrl_toggle) begin state <= READ_READY; retry_delay <= FRAME_CYCLES; end
                    else if (packet_length == 0 || descriptor_end > {1'b0,descriptor_size}) begin
                        state <= FAULT; status <= 3; delay_count <= 0;
                    end else begin
                        failures <= 0; ctrl_toggle <= !ctrl_toggle;
                        read_index <= 0; copy_length <= packet_length; state <= COPY_DESC;
                    end
                end
                COPY_DESC: begin
                    if (control_step == 0) begin
                        case(absolute_index)
                            0: if(read_data != 18) descriptor_bad <= 1;
                            1: if(read_data != 1) descriptor_bad <= 1;
                            7: if(read_data != 64) descriptor_bad <= 1;
                            8: if(read_data != 8'h2a) descriptor_bad <= 1;
                            9: if(read_data != 8'h22) descriptor_bad <= 1;
                            10: if(read_data != 1) descriptor_bad <= 1;
                            11: if(read_data != 0) descriptor_bad <= 1;
                            17: if(read_data != 1) descriptor_bad <= 1;
                            default: ;
                        endcase
                    end else if (read_data != expected_config(absolute_index)) descriptor_bad <= 1;
                    if ({1'b0,read_index} + 1'b1 == copy_length) begin
                        descriptor_offset <= descriptor_offset + copy_length;
                        if (descriptor_offset + copy_length == descriptor_size) state <= STATUS_READY;
                        else if (copy_length != 64) begin state <= FAULT; status <= 3; delay_count <= 0; end
                        else state <= READ_READY;
                    end else read_index <= read_index + 1'b1;
                end
                STATUS_READY: if (retry_delay == 0) launch(read_control ? 2 : 0,0,STATUS_WAIT);
                STATUS_WAIT: if (transaction_done) begin
                    if (result == 2 && control_step >= 4) state <= NEXT_CONTROL;
                    else if (result != 0) retry(STATUS_READY);
                    else if (descriptor_bad || (!read_control && (packet_length != 0 || !packet_toggle))) begin
                        state <= FAULT; status <= 3; delay_count <= 0;
                    end else begin failures <= 0; state <= NEXT_CONTROL; end
                end
                NEXT_CONTROL: begin
                    if (control_step == 5) begin
                        status <= 2; poll_toggle <= 0; poll_ms <= 10; state <= POLL_READY;
                    end else begin
                        control_step <= control_step + 1'b1; state <= SETUP_READY;
                        if (control_step == 1) begin device_address <= 1; delay_count <= 0; state <= ADDRESS_WAIT; end
                    end
                end
                ADDRESS_WAIT: begin
                    if (delay_count >= 2*FRAME_CYCLES) state <= SETUP_READY;
                    else delay_count <= delay_count + 1'b1;
                end
                POLL_READY: if (poll_ms >= 10 && retry_delay == 0) begin poll_ms <= 0; launch(0,1,POLL_WAIT); end
                POLL_WAIT: if (transaction_done) begin
                    state <= POLL_READY;
                    if (result == 1) failures <= 0;
                    else if (result != 0) retry(POLL_READY);
                    else begin
                        failures <= 0;
                        if (packet_toggle == poll_toggle) begin
                            poll_toggle <= !poll_toggle;
                            if (packet_length == 52) begin report_begin <= 1; read_index <= 0; state <= REPORT_ARM; end
                            else error_count <= error_count + 1'b1;
                        end
                    end
                end
                REPORT_ARM: state <= COPY_REPORT;
                COPY_REPORT: begin
                    if (read_index == 51) state <= COMMIT_REPORT;
                    else read_index <= read_index + 1'b1;
                end
                COMMIT_REPORT: begin report_commit <= 1; state <= POLL_READY; end
                FAULT: begin
                    if (delay_count >= ATTACH_CYCLES) begin state <= ATTACH; delay_count <= 0; end
                    else delay_count <= delay_count + 1'b1;
                end
                default: state <= ATTACH;
            endcase
            if (report_rejected) error_count <= error_count + 1'b1;
            if (frame_enabled && disconnected >= DISCONNECT_CYCLES) begin
                state <= ATTACH; status <= 0; delay_count <= 0; transaction_start <= 0;
            end else if (status == 1 && enumeration_ms >= 1500) begin
                state <= FAULT; status <= 3; delay_count <= 0; transaction_start <= 0;
            end
        end
    end
endmodule
