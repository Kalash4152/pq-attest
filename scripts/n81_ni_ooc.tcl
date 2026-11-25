# N-8.1 step 10f: NI out-of-context (OOC) synthesis + timing, NON-PROJECT mode.
# Results are OOC ONLY - not integrated timing (N-8.1 sec.10). The NI<->router
# boundary path closes only in the integrated SoC top (N-14).
#
# Run from a Windows cmd prompt (NOT the GUI Tcl console - it builds its own
# in-memory project):
#   cd C:\vivado_verilog_proj\NOC_PQATTEST
#   C:\xilinx_vivado\Vivado\2024.1\bin\vivado.bat -mode batch -source scripts/n81_ni_ooc.tcl -log logs/n81_ni_ooc.log -nojournal
#
# I/O budget ASSUMPTION (stated, not measured): 20 ns clock; every input arrives
# 5 ns after the edge, every output must be ready 5 ns before the next edge.
# That leaves 10 ns for NI-internal combinational in->out paths (e.g.
# noc_rx_flit -> decode -> noc_rx_ready). The raw in->out path delay is also
# reported unconstrained (budget-independent) - that is the number to carry
# into N-14.
set R    C:/vivado_verilog_proj/NOC_PQATTEST
set S    $R/NOC_PQATTEST.srcs/sources_1/new
set OUT  $R/reports/n81_ni_ooc_[clock format [clock seconds] -format %Y-%m-%d]
file mkdir $OUT

set xdc $OUT/ni_ooc.xdc
set fh [open $xdc w]
puts $fh {create_clock -name clk -period 20.000 [get_ports clk]}
puts $fh {set_input_delay  -clock clk 5.000 [get_ports -filter {DIRECTION == IN && NAME != clk}]}
puts $fh {set_output_delay -clock clk 5.000 [get_ports -filter {DIRECTION == OUT}]}
close $fh

create_project -in_memory -part xc7a100tcsg324-1
read_verilog -sv [list $S/NOC_PKG.sv $S/noc_network_interface.sv]
read_xdc -mode out_of_context $xdc

synth_design -top noc_network_interface -part xc7a100tcsg324-1 -mode out_of_context \
    -generic LOCAL_TILE_ID=0 -generic WD_LIMIT=16

report_utilization               -file $OUT/utilization.rpt
report_utilization -hierarchical -file $OUT/util_hier.rpt
report_timing_summary -max_paths 20 -report_unconstrained -file $OUT/timing_summary.rpt
report_timing -from [all_inputs] -to [all_outputs] -max_paths 10 -file $OUT/in_to_out_paths.rpt
report_timing -max_paths 10 -sort_by group -file $OUT/worst_paths.rpt
report_methodology -file $OUT/methodology.rpt
write_checkpoint -force $OUT/ni_ooc_synth.dcp

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
set io  [get_timing_paths -from [all_inputs] -to [all_outputs] -max_paths 1]
set io_dly [expr {[llength $io] ? [get_property DATAPATH_DELAY $io] : "none"}]
set fh [open $OUT/ni_ooc_summary.txt w]
puts $fh "N-8.1 NI OOC synth (NOT integrated timing). budget: in 5 ns / out 5 ns @ 20 ns"
puts $fh "WNS_setup = $wns ns"
puts $fh "WHS_hold  = $whs ns"
puts $fh "worst in->out combinational datapath delay = $io_dly ns"
close $fh
puts "\n==== [file tail $OUT]/ni_ooc_summary.txt ===="
set fh [open $OUT/ni_ooc_summary.txt r]; puts [read $fh]; close $fh
