# A9 (brief v2): cpu_tile_noc out-of-context IMPLEMENTATION at 20 ns, xc7a100tcsg324-1, with the brief's structural checks.
# Lane 1, 2026-11-07. Usage: vivado -mode batch -source synth/riscv/a9_cpu_tile_noc_impl.tcl -tclargs <repo_root> <out_dir>
# IMEM / DMEM inside the module (inferred BRAM). OOC: assumed 5 ns input / output delays; not integrated timing.
set root [lindex $argv 0]; set out [lindex $argv 1]; file mkdir $out
set_param general.maxThreads 1   ;# no synthesis helper process (a helper-script read failure aborted the first run)
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
set latches [llength [all_latches]]
opt_design; place_design; route_design
report_utilization    -file [file join $out util.rpt]
report_timing_summary -file [file join $out timing.rpt]
report_drc            -file [file join $out drc.rpt]
report_methodology    -file [file join $out methodology.rpt]
set loops [llength [get_drc_violations -quiet -name LUTLP-1]]
set md    [llength [get_drc_violations -quiet -name MDRV-1]]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
set tns 0.0; regexp {\n\s+(-?[0-9.]+)\s+(-?[0-9.]+)\s+[0-9]+\s+[0-9]+\s+(-?[0-9.]+)} [report_timing_summary -return_string -no_detailed_paths] -> wns_r tns
set u [report_utilization -return_string]
set fh [open [file join $out metrics.txt] w]
foreach {k re} {LUT {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)} FF {\|\s*Slice Registers\s*\|\s*([0-9]+)} LUTRAM {\|\s*LUT as Memory\s*\|\s*([0-9]+)} BRAM {\|\s*Block RAM Tile\s*\|\s*([0-9.]+)} DSP {\|\s*DSPs\s*\|\s*([0-9]+)}} {
    set v NA; regexp $re $u -> v; puts $fh "$k=$v"
}
puts $fh "WNS=$wns"; puts $fh "WHS=$whs"; puts $fh "TNS=$tns"; puts $fh "LATCHES=$latches"; puts $fh "COMB_LOOPS_LUTLP1=$loops"; puts $fh "MULTI_DRIVEN_MDRV1=$md"
puts $fh "PERIOD_NS=20.000"; puts $fh "IMEM_INSIDE=YES"; puts $fh "STAGE=post-route OOC"
close $fh
