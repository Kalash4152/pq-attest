# pq_merged_board_io_delays.xdc - I-17 (Lane 1 2026-11-07): explicit I/O delays relative to the design clock (MMCM CLKOUT0,
# 20 ns) so check_timing is complete. The paths stay FALSE (pq_merged_board_arty.xdc): the board I/O are asynchronous
# (btn / sw through 2-flop synchronizers; led / led0_* / uart_rxd_out drive a human and a 115,200-baud USB-UART).
set mg_clk [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *u_mmcm/CLKOUT0}]]
set_input_delay  -clock $mg_clk 0.000 [get_ports {btn[*] sw[*]}]
set_output_delay -clock $mg_clk 0.000 [get_ports {led[*] led0_r led0_g uart_rxd_out}]
