## Combined SoC constraints for pq_merged_board_top on Arty A7-100T (xc7a100tcsg324-1). Evidence is in the gate reports.
## Clock, buttons, sw[0], led[3:0], led0_r: identical to synth/p7_board/pq_p7_board_arty.xdc (Digilent master XDC, fetched
## 2026-11-02). New (M-F1 rev 8 sec. 10): led0_g = F6 and uart_rxd_out = D10 (FPGA TX to the USB-UART), checked against
## github.com/Digilent/digilent-xdc Arty-A7-100-Master.xdc on 2026-11-06 (lines 'Sch=led0_g', 'Sch=uart_rxd_out').
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports CLK100MHZ]
create_clock -name sys_clk_pin -period 10.000 -waveform {0 5} [get_ports CLK100MHZ]
## The 50 MHz (20 ns) design clock is the MMCM CLKOUT0, derived automatically by Vivado.

set_property -dict { PACKAGE_PIN D9  IOSTANDARD LVCMOS33 } [get_ports {btn[0]}]
set_property -dict { PACKAGE_PIN C9  IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]
set_property -dict { PACKAGE_PIN B9  IOSTANDARD LVCMOS33 } [get_ports {btn[2]}]
set_property -dict { PACKAGE_PIN A8  IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN G6  IOSTANDARD LVCMOS33 } [get_ports led0_r]
set_property -dict { PACKAGE_PIN F6  IOSTANDARD LVCMOS33 } [get_ports led0_g]
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports uart_rxd_out]

## Buttons and the switch are asynchronous (2-FF synchronised in the wrapper); LEDs and UART TX are registered outputs.
set_false_path -from [get_ports {btn[*] sw[*]}]
set_false_path -to   [get_ports {led[*] led0_r led0_g uart_rxd_out}]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# I-17 (Lane 1 2026-11-07): explicit I/O delays relative to the design clock (MMCM CLKOUT0,
# 20 ns) so check_timing is complete. The paths stay FALSE (pq_merged_board_arty.xdc): the board I/O are asynchronous
# (btn / sw through 2-flop synchronizers; led / led0_* / uart_rxd_out drive a human and a 115,200-baud USB-UART).
set mg_clk [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *u_mmcm/CLKOUT0}]]
set_input_delay  -clock $mg_clk 0.000 [get_ports {btn[*] sw[*]}]
set_output_delay -clock $mg_clk 0.000 [get_ports {led[*] led0_r led0_g uart_rxd_out}]
