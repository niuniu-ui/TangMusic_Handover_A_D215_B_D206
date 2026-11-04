create_clock -name clk_50m -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
create_generated_clock -name pixel_51m25 -source [get_ports {clk}] -multiply_by 41 -divide_by 40 [get_pins {u_pll/PLL_inst/CLKOUT0}]
create_generated_clock -name serial_256m25 -source [get_ports {clk}] -multiply_by 41 -divide_by 8 [get_pins {u_pll/PLL_inst/CLKOUT1}]
create_generated_clock -name reset_51m25 -source [get_ports {clk}] -multiply_by 41 -divide_by 40 -phase 9 [get_pins {u_pll/PLL_inst/CLKOUT2}]
# Reserve additional pixel setup/hold margin without changing the video rate.
set_clock_uncertainty -setup 0.250 -to [get_clocks {pixel_51m25}]
set_clock_uncertainty -hold 0.050 -to [get_clocks {pixel_51m25}]
set_false_path -to [get_pins {u_tx/*serial_reset_pipe*/PRESET}]
create_generated_clock -name usb_60m -source [get_ports {clk}] -multiply_by 6 -divide_by 5 [get_pins {u_usb_pll/PLL_inst/CLKOUT0}]
set_false_path -from [get_ports {usb1_dp usb1_dm usb2_dp usb2_dm}] -to [get_pins {host*/transaction/phy/*_sync_0_s0/D}]
set_false_path -to [get_pins {pixel_reset_pipe*_s0/CLEAR usb_reset_pipe*_s0/CLEAR}]
set_false_path -to [get_pins {touch_cdc/req_sync_0_s0/D touch_cdc/ack_sync_0_s0/D}]
set_false_path -to [get_pins {state_cdc/req_sync_0_s0/D state_cdc/ack_sync_0_s0/D}]
set_false_path -to [get_pins {extra_cdc/req_sync_0_s0/D extra_cdc/ack_sync_0_s0/D}]
set_false_path -to [get_pins {scope/req_sync_0_s0/D scope/ack_sync_0_s0/D}]
set_false_path -to [get_pins {usb_ready50_0_s0/D}]
set_max_delay 19.0 -from [get_pins {touch_cdc/mailbox*/Q}] -to [get_pins {touch_cdc/dst_data_*_s0/D}]
set_max_delay 19.0 -from [get_pins {state_cdc/mailbox*/Q}] -to [get_pins {state_cdc/dst_data_*_s0/D}]
set_max_delay 19.0 -from [get_pins {extra_cdc/mailbox*/Q}] -to [get_pins {extra_cdc/dst_data_*_s0/D}]
set_max_delay 19.0 -from [get_pins {scope/published_bank_s0/Q}] -to [get_pins {scope/read_bank_s0/D}]
set_false_path -hold -from [get_pins {touch_cdc/mailbox*/Q}] -to [get_pins {touch_cdc/dst_data_*_s0/D}]
set_false_path -hold -from [get_pins {state_cdc/mailbox*/Q}] -to [get_pins {state_cdc/dst_data_*_s0/D}]
set_false_path -hold -from [get_pins {extra_cdc/mailbox*/Q}] -to [get_pins {extra_cdc/dst_data_*_s0/D}]
set_false_path -hold -from [get_pins {scope/published_bank_s0/Q}] -to [get_pins {scope/read_bank_s0/D}]
report_timing -setup -from_clock [get_clocks {clk_50m}] -to_clock [get_clocks {clk_50m}] -max_paths 15
report_timing -setup -from_clock [get_clocks {pixel_51m25}] -to_clock [get_clocks {pixel_51m25}] -max_paths 15
set_false_path -to [get_pins {lissa/req_sync_0_s0/D lissa/ack_sync_0_s0/D}]
set_max_delay 19.0 -from [get_pins {lissa/published_bank_s0/Q}] -to [get_pins {lissa/read_bank_s0/D}]
set_false_path -hold -from [get_pins {lissa/published_bank_s0/Q}] -to [get_pins {lissa/read_bank_s0/D}]
create_clock -name clk400 -period 2.5 -waveform {0 1.25} [get_nets {memory_clk}]
create_clock -name mem100 -period 10 -waveform {0 5} [get_pins {u_ddr3/gw3_top/u_ddr_phy_top/fclkdiv/CLKOUT}]
set_clock_groups -exclusive -group [get_clocks {clk400}] -group [get_clocks {clk_50m mem100}]
set_false_path -from [get_pins {u_ddr3/gw3_top/u_ddr_phy_top/ddr_rsti_reg_*_s0/Q}] -to [get_clocks {mem100}]
set_false_path -to [get_pins {u_ddr3/gw3_top/u_ddr_phy_top/ddr_sync/recalib_s_0_s0/D u_ddr3/gw3_top/u_ddr_phy_top/wloadn_3_s0/D}]
set_false_path -to [get_pins {ui_bridge/req_sync_0_s0/D ui_bridge/ack_sync_0_s0/D ui_bridge/cal_sync_0_s0/D}]
set_false_path -to [get_pins {ui_bridge/mem_reset_0_s0/CLEAR ui_bridge/mem_reset_1_s0/CLEAR}]
set_max_delay -to [get_pins {ui_bridge/mem_data_*/D}] 10
set_false_path -hold -to [get_pins {ui_bridge/mem_data_*/D}]
set_max_delay -to [get_pins {ui_bridge/mem_addr_*/D}] 10
set_false_path -hold -to [get_pins {ui_bridge/mem_addr_*/D}]
set_max_delay -from [get_pins {ui_bridge/held_write_s0/Q}] -to [get_pins {ui_bridge/verify_write_s0/D}] 10
set_false_path -hold -from [get_pins {ui_bridge/held_write_s0/Q}] -to [get_pins {ui_bridge/verify_write_s0/D}]
set_max_delay -to [get_pins {ui_bridge/read_data_*/D}] 10
set_false_path -hold -to [get_pins {ui_bridge/read_data_*/D}]
set_max_delay -from [get_pins {ui_bridge/ack_error_s0/Q}] -to [get_pins {ui_bridge/error_s0/D}] 10
set_false_path -hold -from [get_pins {ui_bridge/ack_error_s0/Q}] -to [get_pins {ui_bridge/error_s0/D}]
set_false_path -to [get_pins {renderer/*artwork/request_sync_0_s0/D renderer/*artwork/ack_sync_0_s0/D renderer/*artwork/boot_sync_0_s0/D renderer/*artwork/error_meta*_s0/D}]
set_max_delay 19.0 -from [get_pins {renderer/*artwork/command_mailbox*/Q}] -to [get_pins {renderer/*artwork/fill_scene*/D renderer/*artwork/fill_stripe*/D renderer/*artwork/fill_bank*/D}]
set_false_path -hold -from [get_pins {renderer/*artwork/command_mailbox*/Q}] -to [get_pins {renderer/*artwork/fill_scene*/D renderer/*artwork/fill_stripe*/D renderer/*artwork/fill_bank*/D}]
report_timing -setup -from_clock [get_clocks {mem100}] -to_clock [get_clocks {mem100}] -max_paths 15
set_false_path -to [get_pins {diagnostics/meta_*_s0/D wave_pixel_reset_0*/D}]

# Independent PHY RX clock and the locally generated TX clock.
create_clock -name rx125 -period 8.000 [get_ports {rx_clk}]
# Regenerated PLL output is the timing root for this independent RAM/toggle
# domain; keep the real 8 ns period and account for residual clock uncertainty.
create_clock -name tx125 -period 8.000 -waveform {0.000 4.000} [get_pins {net/pll/PLL_inst/CLKOUT0}]
set_clock_uncertainty -setup 0.200 -to [get_clocks {tx125}]
set_clock_uncertainty -hold 0.050 -to [get_clocks {tx125}]
# phy_clk is an output-only divided data flop. It is timed as a clk_50m data path.
set_max_delay 20.000 -to [get_ports {phy_clk}]
set_false_path -to [get_pins {net/host_reset*_s0/CLEAR net/tx_reset*_s0/CLEAR net/rx_reset*_s0/CLEAR}]
set_false_path -to [get_pins {net/enabled_tx_0_s0/D net/frames/tx_req_sync_0_s0/D net/frames/tx_ack_sync_0_s0/D net/frames/rx_req_sync_0_s0/D net/frames/rx_ack_sync_0_s0/D}]
# TX payload crosses through a dual-clock RAM. The source writes the full
# packet before request; it cannot overwrite until the frame is acknowledged.
# Bank ownership is immutable until the host has drained and acknowledged it.
set_max_delay 19.000 -from [get_pins {net/frames/published_bank*/Q}] -to [get_pins {net/frames/read_address*/D}]
set_false_path -hold -from [get_pins {net/frames/published_bank*/Q}] -to [get_pins {net/frames/read_address*/D}]
