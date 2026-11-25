# merged_board_gate.tcl - harness gate for the MERGED SoC board top (pq_merged_board_top: NoC + PQ-Attest + two real RISC-V
# CPU tiles; Lane 1 2026-11-07, I-17). Runs on an OPEN routed design. Same criteria as the N-13 gate (WNS / WHS / WPWS >= 0,
# TNS / THS = 0, 0 route errors, 0 DRC errors, clean check_timing, every utilization metric parsed, LUT <= 47,550; parsing
# helpers n13_parse_dts / n13_util reused from n13_gate.tcl; n13_gate itself is not called because it names a clock "clk"
# and the merged design's clock is the MMCM output) plus two merged-board proofs:
#   MMCM clock proof  the design clock is the generated clock on the single MMCM's CLKOUT0, period 20.000 ns, master
#                     sys_clk_pin (CLK100MHZ, 10.000 ns); no other clock except the MMCM feedback;
#   firmware proof    CPU A's IMEM block RAMs carry a non-zero INIT image (the $readmemh firmware reached the netlist).
# Writes gate_summary.txt (with "clock period 20.000 ns" and a VERDICT line); returns PASS|FAIL.
# Self-contained (the harness copies only the gate script into the run snapshot; I-17 run 172810 failed sourcing
# n13_gate.tcl). The two helpers below are copied verbatim from scripts/n13_gate.tcl.
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

proc merged_gate {top out} {
  set fails {}
  if {[get_property PART [current_design]] ne "xc7a100tcsg324-1"} { lappend fails "wrong FPGA part" }
  # TOP is the top module; NAME is only the session label (netlist_1 after link_design, checkpoint_* after open_checkpoint).
  # I-25 run 124233 failed here on NAME although every physical criterion passed (Claude 2026-11-11).
  if {[get_property TOP [current_design]] ne $top} { lappend fails "wrong design top" }
  # ---- MMCM clock proof
  set mmcm [get_cells -hierarchical -quiet -filter {REF_NAME == MMCME2_BASE || REF_NAME == MMCME2_ADV}]
  if {[llength $mmcm] != 1} { lappend fails "MMCM count=[llength $mmcm]" }
  set gclk {}; set gname NA; set gper NA; set master NA; set mper NA
  if {[llength $mmcm] == 1} {
    set gclk [get_clocks -quiet -of_objects [get_pins -quiet [lindex $mmcm 0]/CLKOUT0]]
    if {[llength $gclk] != 1} { lappend fails "CLKOUT0 clocks=[llength $gclk]" } else {
      set gname [get_property NAME $gclk]
      set gper [get_property PERIOD $gclk]
      set master [get_property MASTER_CLOCK $gclk]
      if {$master ne ""} { set mper [get_property PERIOD [get_clocks $master]] }
      if {$gper != 20.000} { lappend fails "CLKOUT0 period=$gper" }
      if {![get_property IS_GENERATED $gclk]} { lappend fails "CLKOUT0 clock not generated" }
      if {$master ne "sys_clk_pin" || $mper != 10.000} { lappend fails "master=$master period=$mper" }
    }
  }
  set feedback_clocks {}
  if {[llength $mmcm] == 1} {
    set feedback_clocks [get_clocks -quiet -of_objects [get_pins -quiet [lindex $mmcm 0]/CLKFBOUT]]
  }
  foreach c [get_clocks -quiet] {
    set n [get_property NAME $c]
    if {$n ne "sys_clk_pin" && $n ne $gname} {
      if {[lsearch -exact $feedback_clocks $c] < 0 || ![get_property IS_GENERATED $c] ||
          [get_property MASTER_CLOCK $c] ne "sys_clk_pin"} { lappend fails "unexpected clock $n" }
    }
  }
  # ---- firmware proof: CPU A IMEM block RAMs initialised
  set rams [get_cells -hierarchical -quiet -filter {REF_NAME =~ RAMB* && NAME =~ *u_cpu_a*imem*}]
  set inited 0
  foreach r $rams {
    foreach p {INIT_00 INIT_01} {
      set v [get_property -quiet $p $r]
      set hex [string range $v [expr {[string first h $v] + 1}] end]
      if {[regexp {[1-9A-Fa-f]} $hex]} { incr inited; break }
    }
  }
  if {[llength $rams] == 0} { lappend fails "CPU A IMEM RAMs not found" } elseif {$inited == 0} { lappend fails "CPU A IMEM INIT all zero (firmware not loaded)" }
  set rams_b [get_cells -hierarchical -quiet -filter {REF_NAME =~ RAMB* && NAME =~ *u_cpu_b*imem*}]
  set inited_b 0
  foreach r $rams_b {
    foreach p {INIT_00 INIT_01} {
      set v [get_property -quiet $p $r]
      set hex [string range $v [expr {[string first h $v] + 1}] end]
      if {[regexp {[1-9A-Fa-f]} $hex]} { incr inited_b; break }
    }
  }
  if {[llength $rams_b] == 0 || $inited_b == 0} { lappend fails "CPU B IMEM firmware not loaded" }
  # Unused upper address banks may legitimately contain only zero initialization.
  # Source/image hashes identify the program; these checks establish that each CPU has loaded IMEM logic.
  # ---- N-13 criteria on the routed design
  set ts [report_timing_summary -max_paths 20 -report_unconstrained -check_timing_verbose -return_string]
  set fh [open [file join $out timing_summary_routed.rpt] w]; puts $fh $ts; close $fh
  set rs [report_route_status -return_string]
  set fh [open [file join $out route_status.rpt] w]; puts $fh $rs; close $fh
  set us [report_utilization -return_string]
  set fh [open [file join $out utilization_routed.rpt] w]; puts $fh $us; close $fh
  report_utilization -hierarchical -hierarchical_depth 6 -file [file join $out util_hier_routed.rpt]
  report_methodology -file [file join $out methodology_routed.rpt]
  report_clocks -file [file join $out clocks.rpt]
  set d [n13_parse_dts $ts]
  set ct {}
  foreach {all name n} [regexp -all -inline {[0-9]+\. checking (\w+) \(([0-9]+)\)} $ts] { if {$n != 0} { lappend ct "$name=$n" } }
  set route_err NA
  regexp {nets with routing errors[ .]*:\s*([0-9]+)} $rs -> route_err
  set drc_err NA
  if {![catch {report_drc -name mg_drc -file [file join $out drc_routed.rpt]}]} {
    if {[catch {set drc_err [llength [get_drc_violations -quiet -name mg_drc -filter {SEVERITY == Error}]]}]} { set drc_err NA }
  }
  foreach k {WNS WHS WPWS} { if {[dict get $d $k] < 0} { lappend fails "$k=[dict get $d $k]" } }
  foreach k {TNS THS} { if {[dict get $d $k] != 0} { lappend fails "$k=[dict get $d $k]" } }
  if {$route_err ne "0"} { lappend fails "route_errors=$route_err" }
  if {$drc_err ne "0"} { lappend fails "DRC_errors=$drc_err" }
  if {[llength $ct]} { lappend fails "check_timing: $ct" }
  foreach {k lbl} {LUT {Slice LUTs} LUTRAM {LUT as Distributed RAM} FF {Slice Registers} BRAM {Block RAM Tile} DSP {DSPs}} {
    if {![string is double -strict [n13_util $us $lbl]]} { lappend fails "utilization $k not parsed" }
  }
  set lut [n13_util $us {Slice LUTs}]
  if {![string is double -strict $lut] || $lut > 47550} { lappend fails "LUT=$lut > 47550 or not parsed" }
  # ---- summary
  set verdict [expr {[llength $fails] ? "FAIL" : "PASS"}]
  set L {}
  lappend L "MERGED BOARD GATE | top $top | [clock format [clock seconds]] | Vivado [version -short] | [get_property PART [current_design]]"
  lappend L "clock period $gper ns | MMCM CLKOUT0 clock $gname generated from $master ($mper ns) | flow S4 release (mesh split, rebuilt, AreaOptimized_high)"
  lappend L "MG_FW_IMEM_RAMS=[llength $rams]"
  lappend L "MG_FW_INITIALISED=$inited"
  lappend L "MG_FW_B_RAMS=[llength $rams_b]"
  lappend L "MG_FW_B_INITIALISED=$inited_b"
  foreach k {WNS TNS WHS THS WPWS} { lappend L "MG_$k=[dict get $d $k]" }
  lappend L "MG_ROUTE_ERRORS=$route_err"
  lappend L "MG_DRC_ERRORS=$drc_err"
  lappend L "MG_CHECK_TIMING=[expr {[llength $ct] ? [join $ct ,] : {clean}}]"
  foreach {k lbl} {LUT {Slice LUTs} LUTRAM {LUT as Distributed RAM} FF {Slice Registers} BRAM {Block RAM Tile} DSP {DSPs} IOB {Bonded IOB}} {
    lappend L "MG_$k=[n13_util $us $lbl]"
  }
  lappend L "VERDICT $verdict [expr {[llength $fails] ? "- $fails" : "- closed at 20 ns (MMCM), firmware in the netlist"}]"
  set fh [open [file join $out gate_summary.txt] w]; puts $fh [join $L "\n"]; close $fh
  puts [join $L "\n"]
  return $verdict
}
