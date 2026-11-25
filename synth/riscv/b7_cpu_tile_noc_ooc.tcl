# B7 (brief v2): cpu_tile_noc out-of-context synthesis at 20 ns, xc7a100tcsg324-1. Lane 1, 2026-11-07.
# Usage: vivado -mode batch -source synth/riscv/b7_cpu_tile_noc_ooc.tcl -tclargs <repo_root> <out_dir>
# BRAM stays INSIDE the module (IMEM 16 KB + DMEM 16 KB as inferred block RAM). Synthesis only, no P&R.
set root [lindex $argv 0]; set out [lindex $argv 1]; file mkdir $out
set rv [file join $root rtl riscv]
read_verilog -sv [file join $root rtl dual_lane NOC_PKG.sv]
read_verilog [file join $rv picorv32.v]
foreach f {picorv32_adapter addr_decode uart_tx uart_mmio gpio tile_status tile_top mem_bram tile_mem_wrapper tmem_app_bridge meas_window_reader cpu_tile_noc} {
    read_verilog -sv [file join $rv $f.sv]
}
synth_design -top cpu_tile_noc -part xc7a100tcsg324-1 -mode out_of_context
create_clock -name clk -period 20.000 [get_ports clk]
set_input_delay  -clock clk 5.0 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock clk 5.0 [get_ports -filter {DIRECTION == OUT}]
report_utilization    -file [file join $out util.rpt]
report_utilization -hierarchical -file [file join $out util_hier.rpt]
report_timing_summary -file [file join $out timing.rpt]
report_drc            -file [file join $out drc.rpt]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
set fh [open [file join $out metrics.txt] w]
foreach {k c} {LUT {Slice LUTs*} FF {Slice Registers*} LUTRAM {  LUT as Memory*} BRAM {Block RAM Tile*} DSP {DSPs*}} {
    set row [lsearch -inline -glob [split [report_utilization -return_string] "\n"] "| $c"]
    puts $fh "$k=[string trim [lindex [split $row |] 2]]"
}
puts $fh "WNS_SETUP_POST_SYNTH=$wns"; puts $fh "WHS_HOLD_POST_SYNTH=$whs"; puts $fh "PERIOD_NS=20.000"; puts $fh "BRAM_INSIDE=YES"
close $fh
