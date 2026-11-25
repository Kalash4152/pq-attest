set dcp "C:/vivado_verilog_proj/NOC_PQATTEST/reports/dual_lane_10_20261103_134238_44759502/rel_p7_pnr/synth.dcp"
set out [file normalize [file dirname [info script]]]
proc metrics {tag out} {
  set ts [report_timing_summary -return_string -max_paths 1]
  set f [open [file join $out "$tag.timing.rpt"] w]; puts $f $ts; close $f
  set p [lindex [get_timing_paths -setup -max_paths 1] 0]
  set wns [get_property SLACK $p]
  set h [lindex [get_timing_paths -hold -max_paths 1] 0]
  set whs [get_property SLACK $h]
  set lv [get_property LOGIC_LEVELS $p]
  set dd [get_property DATAPATH_DELAY $p]
  set nd NA; catch {set nd [get_property DATAPATH_NET_DELAY $p]}
  set tns 0; foreach q [get_timing_paths -setup -max_paths 2000 -slack_lesser_than 0] { set tns [expr {$tns + [get_property SLACK $q]}] }
  set n05 [llength [get_timing_paths -setup -max_paths 5000 -nworst 1 -slack_lesser_than 0.5]]
  set n10 [llength [get_timing_paths -setup -max_paths 5000 -nworst 1 -slack_lesser_than 1.0]]
  set us [report_utilization -return_string]
  set lut NA; regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)} $us -> lut
  set ep [get_property NAME [get_property ENDPOINT_PIN $p]]
  set line "$tag WNS=$wns WHS=$whs TNS=$tns paths_lt_0.5ns=$n05 paths_lt_1.0ns=$n10 levels=$lv data=$dd net=$nd LUT=$lut end=$ep"
  set f [open [file join $out results.txt] a]; puts $f $line; close $f
  puts "PHASE0 $line"
}
foreach v {V4} {
  open_checkpoint $dcp
  set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]
  opt_design -directive Explore
  set pd ExtraTimingOpt
  if {$v eq "V2"} { set pd ExtraNetDelay_high }
  if {$v eq "V3"} { set pd AltSpreadLogic_high }
  if {$v eq "V4"} { set pd Explore }
  place_design -directive $pd
  if {$v eq "V1"} {
    set nets [get_nets -hier -filter {NAME =~ *_fifo/rd_ptr*}]
    puts "PHASE0 V1 replicating [llength $nets] rd_ptr nets"
    phys_opt_design -force_replication_on_nets $nets
  }
  phys_opt_design -directive AggressiveExplore
  route_design -directive AggressiveExplore
  phys_opt_design -directive AggressiveExplore
  metrics $v $out
  close_design
}
