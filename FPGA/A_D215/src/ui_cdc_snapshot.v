`timescale 1ns/1ps
// One coherent held-word mailbox. Source state may change while busy; the
// latest complete state is published again when the acknowledgement returns.
module ui_cdc_snapshot #(parameter WIDTH=32)(
    input wire src_clk, src_reset, dst_clk, dst_reset,
    input wire [WIDTH-1:0] src_data,
    output reg [WIDTH-1:0] dst_data,
    output reg dst_updated
);
    // This is the physical held-data boundary used by the SDC constraints.
    // Do not absorb these flops into upstream DSP output registers or merge
    // them across the handshake: their names and hold semantics must survive.
    (* syn_preserve=1, syn_keep=1 *) reg [WIDTH-1:0] mailbox = 0;
    reg request = 0, acknowledge = 0;
    (* syn_preserve=1 *) reg [1:0] req_sync = 0, ack_sync = 0;
    always @(posedge src_clk) begin
        ack_sync <= {ack_sync[0],acknowledge};
        if(src_reset) begin request<=0; mailbox<=0; ack_sync<=0; end
        else if(ack_sync[1]==request) begin mailbox<=src_data; request<=!request; end
    end
    always @(posedge dst_clk) begin
        req_sync <= {req_sync[0],request};
        dst_updated<=0;
        if(dst_reset) begin req_sync<=0; acknowledge<=0; dst_data<=0; end
        else if(req_sync[1]!=acknowledge) begin
            dst_data<=mailbox; acknowledge<=req_sync[1]; dst_updated<=1;
        end
    end
endmodule
