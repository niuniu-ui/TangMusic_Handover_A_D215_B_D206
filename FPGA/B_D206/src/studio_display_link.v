// Reuses the board-proven PHY configuration and RGMII half-cycle alignment.
module studio_display_link #(parameter integer ROLE=0,PERIOD=2500)(
 input wire clk,rst_n,input wire [2047:0] payload,input wire urgent,
 output wire [7:0] rx_byte,rx_index,output wire rx_valid,rx_done,link_up,
 output wire phy_clk,phy_rst_n,tx_clk,tx_ctl,output wire [3:0] txd,
 input wire rx_clk,rx_ctl,input wire [3:0] rxd,output wire phy_mdc,inout wire phy_mdio
);
 wire tx_internal,pll_locked;GMII_pll pll(.clkin(clk),.clkout0(tx_internal),.clkout1(),.locked(pll_locked));
 // The PHY reference is output-only. A registered /2 avoids allocating a
 // ninth PRIMARY clock on B (video, USB, DDR and RGMII already require eight).
 reg phy_reference=0;always @(posedge clk)phy_reference<=!phy_reference;
 assign phy_clk=phy_reference;
 reg [23:0] startup=0;
 always @(posedge clk)if(!rst_n||!pll_locked)startup<=0;else if(startup<5000000)startup<=startup+1'b1;
 wire ready=rst_n&&pll_locked&&startup==5000000;assign phy_rst_n=ready;
 reg [2:0] host_reset=0,tx_reset=0,rx_reset=0;
 always @(posedge clk or negedge ready)if(!ready)host_reset<=0;else host_reset<={host_reset[1:0],1'b1};
 always @(posedge tx_internal or negedge ready)if(!ready)tx_reset<=0;else tx_reset<={tx_reset[1:0],1'b1};
 always @(posedge rx_clk or negedge ready)if(!ready)rx_reset<=0;else rx_reset<={rx_reset[1:0],1'b1};
 wire mdio_ok,config_done,phy_link;wire [1:0] speed;
 phy_config phy(.clk(clk),.rst_n(host_reset[2]),.mdc(phy_mdc),.mdio(phy_mdio),.mdio_ok(mdio_ok),.config_done(config_done),.link_up(phy_link),.speed(speed));
 assign link_up=config_done&&mdio_ok&&phy_link&&speed==2;
 (* syn_preserve=1 *)reg [2:0] enabled_tx=0;
 always @(posedge tx_internal)if(!tx_reset[2])enabled_tx<=0;else enabled_tx<={enabled_tx[1:0],link_up};
 wire [7:0] tx_byte,aligned_data;wire tx_valid,aligned_valid,aligned_error,alignment_mode;
 wire [3:0] rx_low,rx_high;wire ctl_rise,ctl_fall;genvar g;
 generate for(g=0;g<4;g=g+1)begin:io_ddr
  wire unused;ODDR out_data(.Q0(txd[g]),.Q1(unused),.D0(tx_byte[g]),.D1(tx_byte[g+4]),.TX(1'b0),.CLK(tx_internal));
  IDDR in_data(.Q0(rx_low[g]),.Q1(rx_high[g]),.D(rxd[g]),.CLK(rx_clk));
 end endgenerate
 wire unused_ctl,unused_clock;
 ODDR out_control(.Q0(tx_ctl),.Q1(unused_ctl),.D0(tx_valid),.D1(tx_valid),.TX(1'b0),.CLK(tx_internal));
 ODDR out_clock(.Q0(tx_clk),.Q1(unused_clock),.D0(1'b1),.D1(1'b0),.TX(1'b0),.CLK(tx_internal));
 IDDR in_control(.Q0(ctl_rise),.Q1(ctl_fall),.D(rx_ctl),.CLK(rx_clk));
 rgmii_byte_align align(.clk(rx_clk),.rst_n(rx_reset[2]),.low(rx_low),.high(rx_high),.ctl_rise(ctl_rise),.ctl_fall(ctl_fall),
  .data(aligned_data),.valid(aligned_valid),.error(aligned_error),.mode(alignment_mode));
 wire [31:0] good_frames,bad_frames,dropped_frames;
 studio_net_frames #(.ROLE(ROLE),.PERIOD(PERIOD)) frames(.host_clk(clk),.host_rst_n(host_reset[2]),
  .tx_clk(tx_internal),.tx_rst_n(tx_reset[2]),.rx_clk(rx_clk),.rx_rst_n(rx_reset[2]),.enable(enabled_tx[2]),
  .payload(payload),.urgent(urgent),.tx_data(tx_byte),.tx_valid(tx_valid),
  .rx_data(aligned_data),.rx_valid(aligned_valid),.rx_error(aligned_error),
  .host_byte(rx_byte),.host_index(rx_index),.host_valid(rx_valid),.host_done(rx_done),
  .good_frames(good_frames),.bad_frames(bad_frames),.dropped_frames(dropped_frames));
endmodule
