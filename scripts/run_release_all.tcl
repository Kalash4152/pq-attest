# run_release_all.tcl - ONE command for the whole NOC_PQATTEST release inside the open Vivado project:
#   STEP 1  update check: the P7 design sets (dl_p7_src, dl_p7_board_src, dl_p7_area_src, dl_p7_soc_src) and the bitstream
#           source file scripts/p7_bitstream_sources.tcl must hold exactly the S4 list (S3 + I-6 + I-7 RTL + S4-A5 KMAC variants; the RTL itself is edited in place on disk, so the project picks it up) and every release
#           simulation set must exist. If anything differs, the project update (scripts/update_NOC_PQATTEST_xpr.tcl) is applied
#           here and the check is repeated.
#   STEP 2  runs every release test bench (dl_s4_* / dl_rel_* = the I-5 .. I-8 P7 checks, those touching KMAC re-run on the S4
#           list, plus dl_p7_board_smoke / dl_p7_area_smoke / dl_p7_soc_smoke).
#   STEP 3  verifies them together: a bench is OK only if RESULT : PASS, ERRORS : 0, no TB_TIMEOUT and CHECKS equals the
#           frozen count from the registry (scripts/release_expected.tcl). One table, one verdict.
#   STEP 4  if every bench is OK, builds the three bitstreams with the registered S4 flow (scripts/build_release_bitstreams.tcl,
#           mesh split + rebuilt + AreaOptimized_high): p7_soc (SoC-profile accurate area), p7_area (all exports), p7_board
#           (demo), and prints area / timing. If any bench is not OK, it stops before the bitstreams
#           (set ::rel_force_bitstream 1 before sourcing to build anyway).
# Usage: Vivado with NOC_PQATTEST.xpr open, Tcl console:
#          source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/run_release_all.tcl
#        or batch (project closed):  vivado -mode batch -source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/run_release_all.tcl
# Options: ::rel_filter (glob on simset names, default *), ::rel_skip_bitstream 1, ::rel_force_bitstream 1,
#          ::rel_verify_only 1 (no simulations: re-verify the simulate.log files of the last run, then STEP 4).
# Takes several hours (simulations ~1.5-2 h, bitstreams ~1.5-2 h); the GUI is busy meanwhile. The negative controls
# (mutants) are not in the project; they run in the registered harness only. Not registered evidence.
set root [file normalize [file join [file dirname [info script]] ..]]
if {[current_project -quiet] eq ""} { open_project [file join $root NOC_PQATTEST.xpr] }
if {[get_property NAME [current_project]] ne "NOC_PQATTEST"} { error "Open NOC_PQATTEST.xpr first" }
foreach v {rel_filter rel_skip_bitstream rel_force_bitstream rel_verify_only} d {* 0 0 0} { if {![info exists ::$v]} { set ::$v $d } }
source [file join $root scripts release_expected.tcl]

# ---------------- STEP 1: update check
proc rel_check {root} {
  set bad {}
  dict for {fs want} $::rel_sources {
    if {[get_filesets -quiet $fs] eq ""} { lappend bad "$fs missing"; continue }
    set have [lsort [lmap f [get_files -quiet -of_objects [get_filesets $fs]] {file normalize $f}]]
    set exp  [lsort [lmap s $want {file normalize [file join $root $s]}]]
    if {$have ne $exp} { lappend bad "$fs differs from the S4 list" }
  }
  dict for {ss n} $::rel_expected { if {[get_filesets -quiet $ss] eq ""} { lappend bad "$ss missing" } }
  # S4: the P7 bitstreams use the registered flow; their source lists must equal the design sets
  set bs [file join $root scripts p7_bitstream_sources.tcl]
  if {![file isfile $bs]} { lappend bad "scripts/p7_bitstream_sources.tcl missing" } else {
    source $bs
    foreach {n fs} {p7_soc dl_p7_soc_src p7_area dl_p7_area_src p7_board dl_p7_board_src} {
      if {![dict exists $::p7_bit $n] || ![dict exists $::rel_sources $fs] ||
          [lsort [dict get $::p7_bit $n sources]] ne [lsort [dict get $::rel_sources $fs]]} { lappend bad "bitstream $n sources differ from $fs" }
    }
  }
  return $bad
}
puts "\n=== STEP 1: project update check ==="
set bad [rel_check $root]
if {[llength $bad]} {
  puts "Project not on the S4 sources ([join $bad {; }]): applying scripts/update_NOC_PQATTEST_xpr.tcl"
  source [file join $root scripts update_NOC_PQATTEST_xpr.tcl]
  set bad [rel_check $root]
  if {[llength $bad]} { error "Project still differs after the update: [join $bad {; }]" }
}
puts "STEP 1 OK: P7 design sets and bitstream sources = S4 list; [dict size $::rel_expected] release simulation sets present"

# ---------------- STEP 3 rule (same as the harness judge, scripts/dual_lane_verify.py):
#   positive bench: RESULT PASS, ERRORS 0, CHECKS = frozen count, every required line present the required number of times;
#   expected-FAIL control (registry tb_control): RESULT FAIL, CHECKS = frozen count, ERRORS = the control's count, every
#   oracle line exactly once, every [FAIL] line allow-listed, no forbidden line. Never a TB_TIMEOUT / fatal.
proc rel_verify {n log launch_err} {
  set want [dict get $::rel_expected $n]
  set checks NA; set errors NA; set result NA; set t ""; set why {}
  if {[file exists $log]} {
    set f [open $log r]; set t [read $f]; close $f
    regexp -line {^CHECKS\s*:\s*(\d+)} $t -> checks
    regexp -line {^ERRORS\s*:\s*(\d+)} $t -> errors
    regexp -line {^RESULT\s*:\s*(\w+)} $t -> result
  }
  if {$launch_err ne ""} { lappend why $launch_err }
  if {[regexp -nocase -line {global timeout|TB_TIMEOUT|FATAL:|\[FATAL\]} $t]} { lappend why "timeout / fatal" }
  if {$checks ne $want} { lappend why "CHECKS $checks != $want" }
  set kind positive
  if {[dict exists $::rel_controls $n]} {
    set kind control
    set c [dict get $::rel_controls $n]
    if {$result ne "FAIL"} { lappend why "control not effective (RESULT $result)" }
    if {$errors ne [dict get $c errors]} { lappend why "ERRORS $errors != [dict get $c errors]" }
    foreach p [dict get $c oracle] { set k [regexp -all -line -- $p $t]; if {$k != 1} { lappend why "oracle seen $k times" } }
    foreach l [regexp -all -inline -line {^\[FAIL\][^\n]*} $t] {
      set hit 0; foreach a [dict get $c allowed] { if {[regexp -- $a $l]} { set hit 1 } }
      if {!$hit} { lappend why "unexpected: [string range $l 0 60]" }
    }
    foreach p [dict get $c forbid] { if {[regexp -line -- $p $t]} { lappend why "forbidden line present" } }
  } else {
    if {$result ne "PASS"} { lappend why "RESULT $result" }
    if {$errors ne "0"} { lappend why "ERRORS $errors" }
  }
  if {[dict exists $::rel_required $n]} {
    foreach pc [dict get $::rel_required $n] {
      lassign $pc p cnt; set k [regexp -all -line -- $p $t]
      if {$k != $cnt} { lappend why "required line seen $k / $cnt" }
    }
  }
  set ok [expr {[llength $why] == 0}]
  set note [expr {$ok ? ($kind eq "control" ? "expected-FAIL control: effective" : "") : [join $why {; }]}]
  return [list $ok [format "%-4s %-40s CHECKS %6s / %-6s ERRORS %-4s RESULT %-5s %s" [expr {$ok ? "OK" : "BAD"}] $n $checks $want $errors $result $note]]
}

# ---------------- STEP 2 + 3: run every release bench, verify against the frozen counts
set simdir [file join [get_property DIRECTORY [current_project]] NOC_PQATTEST.sim]
set sets [lsort [lsearch -all -inline -glob [dict keys $::rel_expected] $::rel_filter]]
set rows {}; set nok 0; set nbad 0; set i 0
foreach n $sets {
  incr i
  set log [file join $simdir $n behav xsim simulate.log]
  set launch_err ""
  if {$::rel_verify_only} {
    if {![file exists $log]} { set launch_err "no simulate.log yet (run without ::rel_verify_only first)" }
  } else {
  puts "\n=== STEP 2: simulation $i / [llength $sets]: $n ==="
  current_fileset -simset [get_filesets $n]
  file delete -force $log
  # Vivado writes the compile / elaborate / simulate scripts; this script runs them (output to <step>.stdout.txt in the run
  # directory). Same in the GUI and in batch, and no simulator window is opened.
  # Script generation only (no simulation yet): one retry if Vivado's generator fails (seen once, 2026-11-05, Vivado 12-8089 on
  # the first set of a session; the same set generated and passed on its own). The bench is still judged only on its log.
  set gen_err [catch {launch_simulation -simset [get_filesets $n] -mode behavioral -scripts_only} e]
  if {$gen_err} {
    puts "NOTE: simulation script generation for $n failed ([lindex [split $e \n] 0]); retrying once"
    set gen_err [catch {launch_simulation -simset [get_filesets $n] -mode behavioral -scripts_only} e]
  }
  if {$gen_err} {
    set launch_err [lindex [split $e \n] 0]
  } else {
    set d [file join $simdir $n behav xsim]
    set here [pwd]; cd $d
    foreach b {compile elaborate simulate} {
      if {[catch {exec cmd.exe /c [file nativename [file join $d $b.bat]] > [file join $d $b.stdout.txt] 2>@1} e]} {
        set launch_err "$b step failed (see [file join $d $b.stdout.txt])"; break
      }
    }
    cd $here
  }
  }
  lassign [rel_verify $n $log $launch_err] ok line
  if {$ok} { incr nok } else { incr nbad }
  lappend rows $line
}
if {!$::rel_verify_only} { current_fileset -simset [get_filesets sim_1] }
set verdict [expr {$nbad == 0 && [llength $sets] > 0 ? "ALL VERIFIED" : "NOT VERIFIED"}]
set rpt [file join $root reports release_project_sims.txt]
set f [open $rpt w]
puts $f "NOC_PQATTEST release simulations in the project, [clock format [clock seconds]]"
foreach r $rows { puts $f $r }
puts $f "STEP 3 VERDICT: $verdict  ($nok OK, $nbad BAD of [llength $sets])"
close $f
puts "\n==================== STEP 3: release simulations, verified together ===================="
foreach r $rows { puts $r }
puts "STEP 3 VERDICT: $verdict  ($nok OK, $nbad BAD of [llength $sets]; table saved in $rpt)"
puts "========================================================================================"

# ---------------- STEP 4: bitstreams
if {$::rel_skip_bitstream} {
  puts "STEP 4 skipped (::rel_skip_bitstream 1)"
} elseif {$nbad && !$::rel_force_bitstream} {
  puts "STEP 4 NOT RUN: $nbad bench(es) not verified. Fix them, or set ::rel_force_bitstream 1 and source again."
} else {
  puts "\n=== STEP 4: bitstreams, registered S4 flow (p7_soc SoC-profile area, p7_area all exports, p7_board demo) ==="
  source [file join $root scripts build_release_bitstreams.tcl]
}
