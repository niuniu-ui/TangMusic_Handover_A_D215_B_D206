// B-board 128-point FFT; samples and stage results use four inferred BSRAM blocks.
// Two complex ping-pong banks, synchronous two-port block RAM.
module studio_lab_fft(
 input wire clk,rst_n,sample_tick,sample_reset,input wire signed [15:0] pcm,
 output reg [127:0] levels,output reg frame_valid,overflow
);
 localparam CAPTURE=0,CALC=1,DRAIN=2,PUBLISH=3,PUB_DRAIN=4;
 reg [2:0] state=CAPTURE,stage=0;
 reg [6:0] input_index=0,base=0,offset=0,half=1;
 reg src_bank=0,pipe_valid=0,pub_valid=0;
 reg [6:0] pipe_a=0,pipe_b=0,pipe_tw=0;
 reg [5:0] bin=0,pipe_bin=0;
 reg [127:0] shadow=0;
 function [6:0] rev7(input [6:0] v);begin rev7={v[0],v[1],v[2],v[3],v[4],v[5],v[6]};end endfunction
 wire [6:0] ia=base+offset,ib=base+offset+half;
 wire [6:0] tw_idx=offset << (6-stage);
 reg [6:0] a0,b0,a1,b1;
 reg w0a,w0b,w1a,w1b;
 reg [31:0] d0a,d0b,d1a,d1b;
 reg [31:0] q0a,q0b,q1a,q1b;
 (* syn_ramstyle="block_ram" *) reg [31:0] mem0[0:127];
 (* syn_ramstyle="block_ram" *) reg [31:0] mem1[0:127];
 always @(posedge clk)begin if(w0a)begin mem0[a0]<=d0a;q0a<=d0a;end else q0a<=mem0[a0];end
 always @(posedge clk)begin if(w0b)begin mem0[b0]<=d0b;q0b<=d0b;end else q0b<=mem0[b0];end
 always @(posedge clk)begin if(w1a)begin mem1[a1]<=d1a;q1a<=d1a;end else q1a<=mem1[a1];end
 always @(posedge clk)begin if(w1b)begin mem1[b1]<=d1b;q1b<=d1b;end else q1b<=mem1[b1];end
 wire [31:0] qa=src_bank?q1a:q0a,qb=src_bank?q1b:q0b;
 // A continuous function evaluates the constant ROM at time zero as well as
 // on index changes. pipe_tw can stay zero for the entire first FFT stage.
 // Keep Verilog-2001 syntax for the project's Gowin synthesis language mode.
 function [31:0] twiddle_value;
  input [6:0] index;
  reg signed [15:0] tw_re,tw_im;
  begin
   case(index)
    `include "src/studio_lab_twiddle.vh"
    default:begin tw_re=0;tw_im=0;end
   endcase
   twiddle_value={tw_re,tw_im};
  end
 endfunction
 wire [31:0] twiddle_bits=twiddle_value(pipe_tw);
 wire signed [15:0] tw_re=twiddle_bits[31:16],tw_im=twiddle_bits[15:0];
 wire signed [15:0] ar=qa[31:16],ai=qa[15:0],br=qb[31:16],bi=qb[15:0];
 wire signed [31:0] mrr=br*tw_re,mii=bi*tw_im,mri=br*tw_im,mir=bi*tw_re;
 wire signed [32:0] trw=$signed({mrr[31],mrr})-$signed({mii[31],mii});
 wire signed [32:0] tiw=$signed({mri[31],mri})+$signed({mir[31],mir});
 wire signed [17:0] tr=trw>>>15,ti=tiw>>>15;
 wire signed [18:0] pre=$signed(ar)+$signed(tr),mre=$signed(ar)-$signed(tr);
 wire signed [18:0] pim=$signed(ai)+$signed(ti),mim=$signed(ai)-$signed(ti);
 wire [31:0] outa={pre[16:1],pim[16:1]},outb={mre[16:1],mim[16:1]};
 wire [16:0] abs_re=ar[15]?-{{1{ar[15]}},ar}:{{1{ar[15]}},ar};
 wire [16:0] abs_im=ai[15]?-{{1{ai[15]}},ai}:{{1{ai[15]}},ai};
 wire [17:0] magnitude={1'b0,abs_re}+{1'b0,abs_im};
 function [3:0] bar(input [17:0] mag);
  begin if(mag>=8192)bar=15;else if(mag>=4096)bar=14;else if(mag>=2048)bar=12;
   else if(mag>=1024)bar=10;else if(mag>=512)bar=8;else if(mag>=256)bar=6;
   else if(mag>=128)bar=4;else if(mag>=64)bar=2;else bar=0;end
 endfunction
 always @*begin
  a0=0;b0=0;a1=0;b1=0;w0a=0;w0b=0;w1a=0;w1b=0;d0a=0;d0b=0;d1a=0;d1b=0;
  if(state==CAPTURE&&sample_tick)begin a0=rev7(input_index);w0a=1;d0a={pcm,16'b0};end
  if(state==CALC)begin
   if(src_bank)begin a1=ia;b1=ib;end else begin a0=ia;b0=ib;end
  end
  if(pipe_valid&&(state==CALC||state==DRAIN))begin
   if(src_bank)begin a0=pipe_a;b0=pipe_b;w0a=1;w0b=1;d0a=outa;d0b=outb;end
   else begin a1=pipe_a;b1=pipe_b;w1a=1;w1b=1;d1a=outa;d1b=outb;end
  end
  if(state==PUBLISH)begin if(src_bank)a1=bin+1'b1;else a0=bin+1'b1;end
 end
 always @(posedge clk)begin
  frame_valid<=0;
  if(!rst_n||sample_reset)begin
   input_index<=0;base<=0;offset<=0;half<=1;stage<=0;bin<=0;src_bank<=0;
   pipe_valid<=0;pub_valid<=0;levels<=0;shadow<=0;state<=CAPTURE;overflow<=0;
  end else begin
   if(sample_tick&&state!=CAPTURE)overflow<=1;
   case(state)
    CAPTURE:if(sample_tick)begin
     if(input_index==127)begin input_index<=0;base<=0;offset<=0;half<=1;stage<=0;src_bank<=0;state<=CALC;end
     else input_index<=input_index+1'b1;
    end
    CALC:begin
     pipe_valid<=1;pipe_a<=ia;pipe_b<=ib;pipe_tw<=tw_idx;
     if(offset+1'b1==half)begin
      offset<=0;
      if(({1'b0,base}+({1'b0,half}<<1))>=128)begin base<=0;state<=DRAIN;end
      else base<=base+(half<<1);
     end else offset<=offset+1'b1;
    end
    DRAIN:begin
     pipe_valid<=0;src_bank<=!src_bank;
     if(stage==6)begin state<=PUBLISH;bin<=0;pub_valid<=0;shadow<=0;end
     else begin stage<=stage+1'b1;half<=half<<1;state<=CALC;end
    end
    PUBLISH:begin
     if(pub_valid)shadow[pipe_bin*4+:4]<=bar(magnitude);
     pub_valid<=1;pipe_bin<=bin;
     if(bin==31)state<=PUB_DRAIN;else bin<=bin+1'b1;
    end
    PUB_DRAIN:begin
     levels<={bar(magnitude),shadow[123:0]};frame_valid<=1;state<=CAPTURE;pub_valid<=0;
    end
    default:state<=CAPTURE;
   endcase
  end
 end
endmodule
