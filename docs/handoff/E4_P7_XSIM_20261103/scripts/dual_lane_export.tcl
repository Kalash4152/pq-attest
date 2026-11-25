# Child-only Vivado export/OOC build. Never source this in the user's GUI.
source [lindex $argv 0]
if {![string match 2024.1* [version -short]]} { error "Wrong Vivado version" }
if {[llength [get_projects -quiet]]} { error "Child must start without a project" }
if {$KIND eq "simulation"} {
  create_project dual_job [file join $OUT workspace] -part $PART
  set_property target_simulator XSim [current_project]
  add_files -fileset sim_1 -norecurse $SOURCES
  set fs [get_filesets sim_1]
  set_property top $TOP $fs
  set_property top_lib xil_defaultlib $fs
  set_property include_dirs $INCLUDES $fs
  set_property xsim.simulate.runtime 25ms $fs
  update_compile_order -fileset sim_1
  launch_simulation -simset sim_1 -mode behavioral -scripts_only -absolute_path
  set fh [open [file join $OUT export-path.txt] w]
  puts $fh [file normalize [file join $OUT workspace dual_job.sim sim_1 behav xsim]]
  close $fh
} elseif {$KIND eq "ooc"} {
  create_project -in_memory -part $PART
  read_verilog -sv $SOURCES
  synth_design -top $TOP -part $PART -mode out_of_context -flatten_hierarchy none {*}$GENERICS
  create_clock -name clk -period 20.000 [get_ports clk]
  set_input_delay -clock clk 5.000 [get_ports -filter {DIRECTION == IN && NAME != clk}]
  set_output_delay -clock clk 5.000 [get_ports -filter {DIRECTION == OUT}]
  report_utilization -file $OUT/utilization.rpt
  report_utilization -hierarchical -file $OUT/util_hier.rpt
  report_timing_summary -check_timing_verbose -report_unconstrained -max_paths 20 -file $OUT/timing_summary.rpt
  report_timing -max_paths 10 -file $OUT/worst_paths.rpt
  report_timing -from [all_inputs] -to [all_outputs] -max_paths 10 -file $OUT/in_to_out.rpt
  report_methodology -file $OUT/methodology.rpt
  report_drc -file $OUT/drc.rpt
  write_checkpoint $OUT/synth.dcp
  set fh [open $OUT/metrics.txt w]
  puts $fh "SCOPE=OOC\nCLOCK_NS=20\nINPUT_BUDGET_NS=5\nOUTPUT_BUDGET_NS=5"
  puts $fh "LATCHES=[llength [get_cells -hier -filter {REF_NAME =~ LD*}]]"
  puts $fh "WNS=[get_property SLACK [get_timing_paths -setup -max_paths 1]]"
  puts $fh "WHS=[get_property SLACK [get_timing_paths -hold -max_paths 1]]"
  puts $fh "CELLS=[llength [get_cells -hier]]"
  close $fh
} else { error "Unknown child job kind $KIND" }
close_project
