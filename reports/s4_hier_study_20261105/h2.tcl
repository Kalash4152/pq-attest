set out [file normalize [file dirname [info script]]]
source [file join $out srcs.tcl]
create_project -in_memory -part xc7a100tcsg324-1
read_verilog -sv $srcs
read_xdc C:/vivado_verilog_proj/NOC_PQATTEST/scripts/d4_crypto_ooc.xdc
read_xdc [file join $out keep_routers.xdc]
set_property USED_IN_IMPLEMENTATION false [get_files keep_routers.xdc]
synth_design -top pq_noc_subsystem_p7 -part xc7a100tcsg324-1 -mode out_of_context -flatten_hierarchy rebuilt -directive AreaOptimized_high -verilog_define PQ_MAC_ON
puts "H2 KEEP cells: [llength [get_cells -hier -filter {KEEP_HIERARCHY == TRUE}]]"
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]
opt_design -directive Explore
place_design -directive ExtraTimingOpt
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore
report_timing_summary -max_paths 10 -file [file join $out H2_timing.rpt]
report_utilization -hierarchical -hierarchical_depth 4 -file [file join $out H2_util_hier.rpt]
set us [report_utilization -return_string]
set l NA; set f NA; regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)} $us -> l; regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)} $us -> f
set p [lindex [get_timing_paths -setup -max_paths 1] 0]; set h [lindex [get_timing_paths -hold -max_paths 1] 0]
set line "H2 routed LUT=$l FF=$f WNS=[get_property SLACK $p] WHS=[get_property SLACK $h] levels=[get_property LOGIC_LEVELS $p] end=[get_property NAME [get_property ENDPOINT_PIN $p]]"
set fh [open [file join $out h2_results.txt] w]; puts $fh $line; close $fh
puts "RESULT $line"
