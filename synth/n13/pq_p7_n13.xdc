## N-13 real-pin constraints (Kalash 2026-11-02: shift chain + MISR top). Part xc7a100tcsg324-1, ONE clock at 20 ns: the
## design clock is unchanged (no MMCM, no clock change). Pins are Arty A7-100T package pins of the D5 board wrapper; this is
## an implementation-timing vehicle (N-13), not a board design. Every I/O is timed: 5 ns budgets as the OOC flows.
create_clock -name clk -period 20.000 [get_ports clk]
set_property -dict {PACKAGE_PIN E3  IOSTANDARD LVCMOS33} [get_ports clk]
set_property -dict {PACKAGE_PIN D9  IOSTANDARD LVCMOS33} [get_ports rst]
set_property -dict {PACKAGE_PIN A8  IOSTANDARD LVCMOS33} [get_ports sdi]
set_property -dict {PACKAGE_PIN C11 IOSTANDARD LVCMOS33} [get_ports sen]
set_property -dict {PACKAGE_PIN H5  IOSTANDARD LVCMOS33} [get_ports sdo]
set_input_delay  -clock clk 5.000 [get_ports {rst sdi sen}]
set_output_delay -clock clk 5.000 [get_ports sdo]
