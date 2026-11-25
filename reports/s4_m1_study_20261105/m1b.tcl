set out [file normalize [file dirname [info script]]]
source [file join $out srcs.tcl]
create_project -in_memory -part xc7a100tcsg324-1
read_verilog -sv [concat [lrange $top_srcs 0 1] [list [file join $out mesh_bb.sv]] [lrange $top_srcs 2 end]]
read_xdc C:/vivado_verilog_proj/NOC_PQATTEST/scripts/d4_crypto_ooc.xdc
synth_design -top pq_noc_subsystem_p7 -part xc7a100tcsg324-1 -mode out_of_context -flatten_hierarchy rebuilt -directive AreaOptimized_high -verilog_define PQ_MAC_ON
puts "M1 bb pins: [llength [get_pins mesh/*]]"
write_checkpoint -force [file join $out top.dcp]
close_project
create_project -in_memory -part xc7a100tcsg324-1
add_files [list [file join $out top.dcp] [file join $out mesh.dcp]]
set_property SCOPED_TO_CELLS {mesh} [get_files [file join $out mesh.dcp]]
link_design -top pq_noc_subsystem_p7 -part xc7a100tcsg324-1 -mode out_of_context
puts "M1 black boxes left: [llength [get_cells -hier -filter {IS_BLACKBOX == 1}]] mesh cells: [llength [get_cells -hier -filter {NAME =~ mesh/*}]]"
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]
opt_design -directive Explore
place_design -directive ExtraTimingOpt
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore
report_timing_summary -max_paths 10 -file [file join $out M1_timing.rpt]
report_utilization -hierarchical -hierarchical_depth 4 -file [file join $out M1_util_hier.rpt]
set us [report_utilization -return_string]
set l NA; set f NA; regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)} $us -> l; regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)} $us -> f
set p [lindex [get_timing_paths -setup -max_paths 1] 0]; set h [lindex [get_timing_paths -hold -max_paths 1] 0]
set line "M1 routed LUT=$l FF=$f WNS=[get_property SLACK $p] WHS=[get_property SLACK $h] levels=[get_property LOGIC_LEVELS $p] end=[get_property NAME [get_property ENDPOINT_PIN $p]]"
set fh [open [file join $out m1_results.txt] w]; puts $fh $line; close $fh
puts "RESULT $line"
