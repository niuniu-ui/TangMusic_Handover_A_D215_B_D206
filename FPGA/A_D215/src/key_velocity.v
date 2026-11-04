// Measure two-contact travel in scan frames. Host converts frames to relative
// velocity after calibration. No USB/PC arrival time enters this measurement.
module velocity_key #(
    parameter integer TIMEOUT_TICKS = 10000,
    parameter integer CLOSE_FRAMES = 4,
    parameter integer OPEN_FRAMES = 8
)(
    input wire clk, rst, frame_valid,
    input wire [15:0] frame_tick,
    input wire [1:0] raw,
    output reg event_seq,
    output reg [15:0] delta_ticks,
    output reg [1:0] contact_order
);
    reg [1:0] stable;
    // Packed registers avoid inferring a two-word, multi-write block RAM.
    localparam integer MAX_CONFIRM = CLOSE_FRAMES > OPEN_FRAMES ? CLOSE_FRAMES : OPEN_FRAMES;
    localparam integer CW = MAX_CONFIRM > 1 ? $clog2(MAX_CONFIRM) : 1;
    localparam integer QW = OPEN_FRAMES > 0 ? $clog2(OPEN_FRAMES+1) : 1;
    reg [2*CW-1:0] count;
    reg [31:0] candidate;
    reg [31:0] closed_at;
    reg [QW-1:0] quiet;
    reg armed, done, waiting;
    reg [15:0] first_at;
    wire [15:0] ab = closed_at[31:16] - closed_at[15:0];
    wire [15:0] ba = closed_at[15:0] - closed_at[31:16];
    wire [15:0] interval = ab < ba ? ab : ba;
    wire [15:0] age = frame_tick - first_at;
    integer c;

    always @(posedge clk) begin
        if (rst) begin
            stable <= 0; quiet <= 0; armed <= 0; done <= 0; waiting <= 0;
            first_at <= 0; event_seq <= 0; delta_ticks <= 0; contact_order <= 0;
            count <= 0; candidate <= 0; closed_at <= 0;
        end else if (frame_valid) begin
            // Confirm for 0.8ms closed / 1.6ms open at the default frame rate.
            // Preserve the
            // first sample's time so debounce does not add to the interval.
            for (c=0;c<2;c=c+1) begin
                if (raw[c] == stable[c]) count[c*CW +:CW] <= 0;
                else begin
                    if (count[c*CW +:CW] == 0) candidate[c*16 +:16] <= frame_tick;
                    if (count[c*CW +:CW] == (raw[c] ? CLOSE_FRAMES-1 : OPEN_FRAMES-1)) begin
                        stable[c] <= raw[c]; count[c*CW +:CW] <= 0;
                        if (raw[c]) closed_at[c*16 +:16] <= CLOSE_FRAMES == 1 ? frame_tick : candidate[c*16 +:16];
                    end else count[c*CW +:CW] <= count[c*CW +:CW] + 1'b1;
                end
            end
            if (raw == 0) begin
                if (quiet < OPEN_FRAMES) quiet <= quiet + 1'b1;
            end else quiet <= 0;

            // A new strike requires complete release. A key held at power-on
            // has no measurable start time and must first be released.
            if (quiet == OPEN_FRAMES && stable == 0) begin
                armed <= 1; done <= 0; waiting <= 0;
            end else if (armed && !done) begin
                if (stable == 3) begin
                    event_seq <= ~event_seq; done <= 1;
                    if (interval > TIMEOUT_TICKS) begin
                        delta_ticks <= 16'hffff; contact_order <= 3;
                    end else begin
                        delta_ticks <= interval;
                        contact_order <= ab == 0 ? 0 : (ab < ba ? 1 : 2);
                    end
                end else if (stable != 0) begin
                    if (!waiting) begin
                        waiting <= 1;
                        first_at <= stable[0] ? closed_at[15:0] : closed_at[31:16];
                    end else if (age >= TIMEOUT_TICKS) begin
                        event_seq <= ~event_seq; done <= 1;
                        delta_ticks <= 16'hffff; contact_order <= 3;
                    end
                end
            end
        end
    end
endmodule

module key_velocity #(
    parameter integer TIMEOUT_TICKS = 10000,
    parameter integer CLOSE_FRAMES = 4,
    parameter integer OPEN_FRAMES = 8
)(
    input wire clk, rst, frame_valid,
    input wire [63:0] contacts,
    output reg [31:0] velocity_seq,
    output reg [511:0] velocity_ticks,
    output reg [63:0] velocity_order,
    output reg frame_done,
    output reg overflow
);
    // One transition datapath, with 32 independent key states in block RAM.
    // A whole frame needs < 100 clocks (production scan interval: 10000).
    // Wide result buses are coherent when frame_done is asserted.
    localparam integer MAX_CONFIRM=CLOSE_FRAMES>OPEN_FRAMES?CLOSE_FRAMES:OPEN_FRAMES;
    localparam integer CW=MAX_CONFIRM>1?$clog2(MAX_CONFIRM):1;
    localparam integer QW=OPEN_FRAMES>0?$clog2(OPEN_FRAMES+1):1;
    localparam integer SW=104+2*CW+QW;
    localparam INIT=0,IDLE=1,READ_WAIT=2,EXECUTE=3,WRITE_BACK=4;
    reg [2:0] phase;
    reg [4:0] cursor,read_address;
    reg [15:0] frame_tick,current_tick,pending_tick;
    reg [63:0] current_contacts,pending_contacts;
    reg pending;
    reg [SW-1:0] states[0:31] /* synthesis syn_ramstyle="block_ram" */;
    reg [SW-1:0] read_state,write_state;
    function [SW-1:0] advance_key;
        input [SW-1:0] previous;input [1:0] raw;input [15:0] tick;
        reg [1:0] stable,stable_n,order,order_n;
        reg [QW-1:0] quiet,quiet_n;
        reg armed,armed_n,done,done_n,waiting,waiting_n,seq,seq_n;
        reg [15:0] first_at,first_n,delta,delta_n,ab,ba,interval,age;
        reg [2*CW-1:0] count,count_n;
        reg [31:0] candidate,candidate_n,closed_at,closed_n;
        integer c;
        begin
            {stable,quiet,armed,done,waiting,first_at,seq,delta,order,count,candidate,closed_at}=previous;
            stable_n=stable;quiet_n=quiet;armed_n=armed;done_n=done;waiting_n=waiting;
            first_n=first_at;seq_n=seq;delta_n=delta;order_n=order;count_n=count;candidate_n=candidate;closed_n=closed_at;
            ab=closed_at[31:16]-closed_at[15:0];ba=closed_at[15:0]-closed_at[31:16];interval=ab<ba?ab:ba;age=tick-first_at;
            for(c=0;c<2;c=c+1)begin
                if(raw[c]==stable[c])count_n[c*CW+:CW]=0;
                else begin
                    if(count[c*CW+:CW]==0)candidate_n[c*16+:16]=tick;
                    if(count[c*CW+:CW]==(raw[c]?CLOSE_FRAMES-1:OPEN_FRAMES-1))begin
                        stable_n[c]=raw[c];count_n[c*CW+:CW]=0;
                        if(raw[c])closed_n[c*16+:16]=CLOSE_FRAMES==1?tick:candidate[c*16+:16];
                    end else count_n[c*CW+:CW]=count[c*CW+:CW]+1'b1;
                end
            end
            if(raw==0)begin if(quiet<OPEN_FRAMES)quiet_n=quiet+1'b1;end else quiet_n=0;
            // All decisions intentionally use OLD state, matching the original
            // 32 parallel nonblocking state machines exactly at frame boundaries.
            if(quiet==OPEN_FRAMES&&stable==0)begin armed_n=1;done_n=0;waiting_n=0;end
            else if(armed&&!done)begin
                if(stable==3)begin
                    seq_n=~seq;done_n=1;
                    if(interval>TIMEOUT_TICKS)begin delta_n=16'hffff;order_n=3;end
                    else begin delta_n=interval;order_n=ab==0?0:(ab<ba?1:2);end
                end else if(stable!=0)begin
                    if(!waiting)begin waiting_n=1;first_n=stable[0]?closed_at[15:0]:closed_at[31:16];end
                    else if(age>=TIMEOUT_TICKS)begin seq_n=~seq;done_n=1;delta_n=16'hffff;order_n=3;end
                end
            end
            advance_key={stable_n,quiet_n,armed_n,done_n,waiting_n,first_n,seq_n,delta_n,order_n,count_n,candidate_n,closed_n};
        end
    endfunction
    wire [SW-1:0] next_state=advance_key(read_state,current_contacts[1:0],current_tick);
    always @(posedge clk)begin
        read_state<=states[read_address];
        if(!rst&&phase==INIT)states[cursor]<=0;
        else if(!rst&&phase==WRITE_BACK)states[cursor]<=write_state;
    end
    always @(posedge clk)begin
        if(rst)begin
            phase<=INIT;cursor<=0;read_address<=0;frame_tick<=0;current_tick<=0;pending_tick<=0;
            current_contacts<=0;pending_contacts<=0;pending<=0;write_state<=0;
            velocity_seq<=0;velocity_ticks<=0;velocity_order<=0;frame_done<=0;overflow<=0;
        end else begin
            frame_done<=0;
            case(phase)
                INIT:if(cursor==31)begin cursor<=0;phase<=IDLE;end else cursor<=cursor+1'b1;
                IDLE:if(pending)begin
                    current_contacts<=pending_contacts;current_tick<=pending_tick;pending<=0;
                    cursor<=0;read_address<=0;phase<=READ_WAIT;
                end
                READ_WAIT:phase<=EXECUTE;
                EXECUTE:begin
                    write_state<=next_state;
                    velocity_seq<={next_state[82+2*CW],velocity_seq[31:1]};
                    velocity_ticks<={next_state[66+2*CW+:16],velocity_ticks[511:16]};
                    velocity_order<={next_state[64+2*CW+:2],velocity_order[63:2]};
                    phase<=WRITE_BACK;
                end
                WRITE_BACK:begin
                    if(cursor==31)begin frame_done<=1;phase<=IDLE;end
                    else begin cursor<=cursor+1'b1;read_address<=cursor+1'b1;current_contacts<=current_contacts>>2;phase<=READ_WAIT;end
                end
                default:phase<=INIT;
            endcase
            if(frame_valid)begin
                frame_tick<=frame_tick+1'b1;
                if(pending&&phase!=IDLE)overflow<=1;
                else begin pending<=1;pending_contacts<=contacts;pending_tick<=frame_tick;end
            end
        end
    end
endmodule
