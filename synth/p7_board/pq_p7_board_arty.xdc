## D5 board constraints for pq_p7_board_top on Arty A7-100T (xc7a100tcsg324-1).
## Pins verbatim from Digilent Arty-A7-100-Master.xdc (github.com/Digilent/digilent-xdc, fetched 2026-11-02).
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports CLK100MHZ]
create_clock -name sys_clk_pin -period 10.000 -waveform {0 5} [get_ports CLK100MHZ]
## The 50 MHz (20 ns) design clock is the MMCM CLKOUT0, derived automatically by Vivado.

set_property -dict { PACKAGE_PIN D9  IOSTANDARD LVCMOS33 } [get_ports {btn[0]}]
set_property -dict { PACKAGE_PIN C9  IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]
set_property -dict { PACKAGE_PIN B9  IOSTANDARD LVCMOS33 } [get_ports {btn[2]}]
set_property -dict { PACKAGE_PIN A8  IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN C11 IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN G6  IOSTANDARD LVCMOS33 } [get_ports led0_r]

## Buttons and switches are asynchronous (2-FF synchronised in the wrapper); LEDs are status only.
set_false_path -from [get_ports {btn[*] sw[*]}]
set_false_path -to   [get_ports {led[*] led0_r}]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
