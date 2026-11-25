set out [file normalize [file dirname [info script]]]
foreach tag {S5 S7} {
  open_checkpoint [file join $out ${tag}_opt.dcp]
  set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]
  place_design -directive ExtraTimingOpt
  phys_opt_design -directive AggressiveExplore
  route_design -directive AggressiveExplore
  phys_opt_design -directive AggressiveExplore
  report_timing_summary -max_paths 10 -file [file join $out ${tag}_routed_timing.rpt]
  report_utilization -hierarchical -hierarchical_depth 6 -file [file join $out ${tag}_routed_util_hier.rpt]
  report_design_analysis -timing -max_paths 20 -file [file join $out ${tag}_routed_design_analysis.rpt]
  set us [report_utilization -return_string]
  set l NA; set f NA; regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)} $us -> l; regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)} $us -> f
  set p [lindex [get_timing_paths -setup -max_paths 1] 0]; set h [lindex [get_timing_paths -hold -max_paths 1] 0]
  set n05 [llength [get_timing_paths -setup -max_paths 5000 -nworst 1 -slack_lesser_than 0.5]]
  set line "$tag routed LUT=$l FF=$f WNS=[get_property SLACK $p] WHS=[get_property SLACK $h] paths_lt_0.5=$n05 end=[get_property NAME [get_property ENDPOINT_PIN $p]]"
  set fh [open [file join $out area_results.txt] a]; puts $fh $line; close $fh
  puts "AREA $line"
  close_design
}
