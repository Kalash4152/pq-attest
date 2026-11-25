# n13_gate.tcl - N-13 gate on an OPEN routed design (R4 NOC-5: WNS/WHS/WPWS >= 0, TNS/THS = 0, 0 route / DRC errors, no
# unexplained unconstrained paths). Every check_timing category must be 0 (all I/O are constrained in the XDC). For the
# secure top the full-subsystem LUT must be <= 47,550 (CLAUDE.md hard stop). Writes gate_summary.txt; returns PASS|FAIL.
proc n13_parse_dts {s} {
  set lines [split $s "\n"]
  set i [lsearch -regexp $lines {^\s*WNS\(ns\)}]
  if {$i < 0} { error "Design Timing Summary not found" }
  for {set k [expr {$i+1}]} {$k < [llength $lines]} {incr k} {
    set l [string trim [lindex $lines $k]]
    if {[regexp {^-?[0-9]} $l]} { break }
  }
  set v [regexp -all -inline {\S+} $l]
  if {[llength $v] < 12} { error "DTS row malformed: $l" }
  return [dict create WNS [lindex $v 0] TNS [lindex $v 1] WHS [lindex $v 4] THS [lindex $v 5] WPWS [lindex $v 8]]
}
proc n13_util {s label} {
  set re "\\|\\s*[string map {( \\( ) \\) . \\. * \\*} $label]\\*?\\s*\\|\\s*(\[0-9.\]+)\\s*\\|"
  if {[regexp $re $s -> n]} { return $n }
  return NA
}
proc n13_gate {top out} {
  set ts [report_timing_summary -max_paths 20 -report_unconstrained -check_timing_verbose -return_string]
  set fh [open [file join $out timing_summary_routed.rpt] w]; puts $fh $ts; close $fh
  set rs [report_route_status -return_string]
  set fh [open [file join $out route_status.rpt] w]; puts $fh $rs; close $fh
  set us [report_utilization -return_string]
  set fh [open [file join $out utilization_routed.rpt] w]; puts $fh $us; close $fh
  report_utilization -hierarchical -hierarchical_depth 6 -file [file join $out util_hier_routed.rpt]
  report_methodology -file [file join $out methodology_routed.rpt]
  report_power -file [file join $out power_routed.rpt]
  report_control_sets -file [file join $out control_sets.rpt]
  set d [n13_parse_dts $ts]
  set ct {}
  foreach {all name n} [regexp -all -inline {[0-9]+\. checking (\w+) \(([0-9]+)\)} $ts] { if {$n != 0} { lappend ct "$name=$n" } }
  set route_err NA
  regexp {nets with routing errors[ .]*:\s*([0-9]+)} $rs -> route_err
  set drc_err NA
  if {![catch {report_drc -name n13_drc -file [file join $out drc_routed.rpt]}]} {
    if {[catch {set drc_err [llength [get_drc_violations -quiet -name n13_drc -filter {SEVERITY == Error}]]}]} { set drc_err NA }
  }
  set lut [n13_util $us {Slice LUTs}]
  set wp [lindex [get_timing_paths -setup -max_paths 1 -nworst 1] 0]
  set wsp [get_property NAME [get_property STARTPOINT_PIN $wp]]
  set wep [get_property NAME [get_property ENDPOINT_PIN $wp]]
  set fails {}
  foreach k {WNS WHS WPWS} { if {[dict get $d $k] < 0} { lappend fails "$k=[dict get $d $k]" } }
  foreach k {TNS THS} { if {[dict get $d $k] != 0} { lappend fails "$k=[dict get $d $k]" } }
  if {$route_err ne "0"} { lappend fails "route_errors=$route_err" }
  if {$drc_err ne "0"} { lappend fails "DRC_errors=$drc_err" }
  if {[llength $ct]} { lappend fails "check_timing: $ct" }
  # every utilization metric must parse as a number (a parse failure must never pass silently)
  foreach {k lbl} {LUT {Slice LUTs} LUTRAM {LUT as Distributed RAM} FF {Slice Registers} BRAM {Block RAM Tile} DSP {DSPs}} {
    if {![string is double -strict [n13_util $us $lbl]]} { lappend fails "utilization $k not parsed" }
  }
  if {$top eq "pq_p7_n13_top" && (![string is double -strict $lut] || $lut > 47550)} { lappend fails "LUT=$lut > 47550 or not parsed" }
  set verdict [expr {[llength $fails] ? "FAIL" : "PASS"}]
  set L {}
  lappend L "N-13 GATE | top $top | [clock format [clock seconds]] | Vivado [version -short] | [get_property PART [current_design]]"
  lappend L "clock period [get_property PERIOD [get_clocks clk]] ns | flow S1-PNR-DIR directives, real pins, no incremental DCP"
  lappend L "N13_WNS=[dict get $d WNS]"
  lappend L "N13_TNS=[dict get $d TNS]"
  lappend L "N13_WHS=[dict get $d WHS]"
  lappend L "N13_THS=[dict get $d THS]"
  lappend L "N13_WPWS=[dict get $d WPWS]"
  lappend L "N13_ROUTE_ERRORS=$route_err"
  lappend L "N13_DRC_ERRORS=$drc_err"
  lappend L "N13_CHECK_TIMING=[expr {[llength $ct] ? [join $ct ,] : {clean}}]"
  lappend L "N13_LUT=$lut"
  lappend L "N13_LUTRAM=[n13_util $us {LUT as Distributed RAM}]"
  lappend L "N13_FF=[n13_util $us {Slice Registers}]"
  lappend L "N13_BRAM=[n13_util $us {Block RAM Tile}]"
  lappend L "N13_DSP=[n13_util $us {DSPs}]"
  lappend L "N13_IOB=[n13_util $us {Bonded IOB}]"
  lappend L "N13_WORST=$wsp -> $wep"
  lappend L "VERDICT $verdict [expr {[llength $fails] ? "- $fails" : "- closed at 20 ns"}]"
  set fh [open [file join $out gate_summary.txt] w]; puts $fh [join $L "\n"]; close $fh
  puts [join $L "\n"]
  return $verdict
}
