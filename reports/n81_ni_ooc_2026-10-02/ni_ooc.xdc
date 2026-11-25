create_clock -name clk -period 20.000 [get_ports clk]
set_input_delay  -clock clk 5.000 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock clk 5.000 [get_ports -filter {DIRECTION == OUT}]
