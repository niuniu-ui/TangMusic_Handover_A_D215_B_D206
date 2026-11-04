// Four independent groups replace the 32-deep priority/count chain.
module score_cues_fast(input wire [31:0] targets,output reg [63:0] cues);
 function [22:0] pack8;
  input [7:0] bits;integer i;reg [2:0] count;reg [19:0] indices;
  begin count=0;indices=0;for(i=0;i<8;i=i+1)if(bits[i]&&count<4)begin case(count) 0:indices[4:0]=i;1:indices[9:5]=i;2:indices[14:10]=i;default:indices[19:15]=i;endcase count=count+1'b1;end pack8={count,indices};end
 endfunction
 function [4:0] pick;
  input [22:0] packval;input [2:0] idx;reg [19:0] indices;
  begin indices=packval[19:0];case(idx)0:pick=indices[4:0];1:pick=indices[9:5];2:pick=indices[14:10];default:pick=indices[19:15];endcase end
 endfunction
 reg [22:0] p0,p1,p2,p3;reg [3:0] n0,n1,n2,n3;reg [4:0] idx;integer k;
 always @*begin
  p0=pack8(targets[7:0]);p1=pack8(targets[15:8]);p2=pack8(targets[23:16]);p3=pack8(targets[31:24]);
  n0=p0[22:20];n1=n0+p1[22:20];n2=n1+p2[22:20];n3=n2+p3[22:20];cues=0;idx=0;
  for(k=0;k<4;k=k+1)begin
   if(k<n0)begin idx=pick(p0,k);cues[k*16+:16]=16'h8020|idx;end
   else if(k<n1)begin idx=pick(p1,k-n0)+8;cues[k*16+:16]=16'h8020|idx;end
   else if(k<n2)begin idx=pick(p2,k-n1)+16;cues[k*16+:16]=16'h8020|idx;end
   else if(k<n3)begin idx=pick(p3,k-n2)+24;cues[k*16+:16]=16'h8020|idx;end
  end
 end
endmodule
