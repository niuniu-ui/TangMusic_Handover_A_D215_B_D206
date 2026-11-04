// Keep byte decisions separate so synthesis cannot form a 32-bit LUT ripple.
// Pure unsigned comparison, no added latency and no change to boundary values.
module studio_u32_ge(input wire [31:0] a,b,output wire ge);
 (* syn_keep=1 *) wire [3:0] byte_gt,byte_eq;
 genvar k;
 generate for(k=0;k<4;k=k+1)begin:bytes
  assign byte_gt[k]=a[k*8+:8]>b[k*8+:8];
  assign byte_eq[k]=a[k*8+:8]==b[k*8+:8];
 end endgenerate
 assign ge=byte_gt[3]||(byte_eq[3]&&byte_gt[2])||
  (byte_eq[3]&&byte_eq[2]&&byte_gt[1])||
  (byte_eq[3]&&byte_eq[2]&&byte_eq[1]&&byte_gt[0])||(&byte_eq);
endmodule
