# test_merged_board_gate.tcl - negative tests for scripts/merged_board_gate.tcl (Lane 1 2026-11-07, I-17). Runs the gate on
# the routed checkpoint of an i17_merged_board run, unmodified and with three injected faults, each on a fresh copy:
#   BASE         unmodified                                   -> PASS
#   FW_ZEROED    every CPU A IMEM RAM INIT_00..INIT_3F set 0  -> FAIL "firmware not loaded"
#   EXTRA_CLOCK  extra 20 ns clock created on btn[0]          -> FAIL "unexpected clock"
#   FAST_BOARD   sys_clk_pin redefined at 5 ns (CLKOUT0 10 ns) -> FAIL "CLKOUT0 period"
# Usage: vivado -mode batch -source scripts/test_merged_board_gate.tcl -tclargs <routed.dcp> <out_dir> [<extra.xdc>]
# (<extra.xdc>: constraints read after open_checkpoint, e.g. to check a constraint fix on an existing routed design)
set dcp [lindex $argv 0]; set out [lindex $argv 1]; file mkdir $out
set extra [lindex $argv 2]
source [file join [file dirname [file normalize [info script]]] merged_board_gate.tcl]
set results {}
foreach {case expect pattern} {BASE PASS {} FW_ZEROED FAIL {firmware not loaded} FW_B_ZEROED FAIL {CPU B IMEM firmware not loaded} EXTRA_CLOCK FAIL {unexpected clock} EXTRA_FB_CLOCK FAIL {unexpected clock} FAST_BOARD FAIL {CLKOUT0 period}} {
  open_checkpoint $dcp
  if {$extra ne ""} { read_xdc $extra }
  switch $case {
    FW_ZEROED {
      foreach r [get_cells -hierarchical -filter {REF_NAME =~ RAMB* && NAME =~ *u_cpu_a*imem*}] {
        for {set i 0} {$i < 64} {incr i} { set_property -quiet [format INIT_%02X $i] 256'h0 $r }
      }
    }
    FW_B_ZEROED {
      foreach r [get_cells -hierarchical -filter {REF_NAME =~ RAMB* && NAME =~ *u_cpu_b*imem*}] {
        for {set i 0} {$i < 64} {incr i} { set_property -quiet [format INIT_%02X $i] 256'h0 $r }
      }
    }
    EXTRA_CLOCK { create_clock -name neg_extra -period 20.000 [get_ports {btn[0]}] }
    EXTRA_FB_CLOCK { create_clock -name neg_fb_clock -period 20.000 [get_ports {btn[0]}] }
    FAST_BOARD  { create_clock -name sys_clk_pin -period 5.000 -waveform {0 2.5} [get_ports CLK100MHZ] }
  }
  set d [file join $out $case]; file mkdir $d
  set v [merged_gate pq_merged_board_top $d]
  set fh [open [file join $d gate_summary.txt] r]; set s [read $fh]; close $fh
  set ok [expr {$v eq $expect && ($pattern eq "" || [string first $pattern $s] >= 0)}]
  lappend results "NEG $case verdict=$v expected=$expect [expr {$ok ? {OK} : {BAD}}]"
  close_design
}
# Identity control (not one of the six frozen cases): the gate asked for a different top module must FAIL "wrong design top".
open_checkpoint $dcp
if {$extra ne ""} { read_xdc $extra }
set d [file join $out IDENTITY_WRONG_TOP]; file mkdir $d
set v [merged_gate pq_not_the_merged_top $d]
set fh [open [file join $d gate_summary.txt] r]; set s [read $fh]; close $fh
set id_ok [expr {$v eq "FAIL" && [string first "wrong design top" $s] >= 0}]
close_design
set fh [open [file join $out negative_tests.txt] w]
foreach r $results { puts $fh $r; puts $r }
puts $fh "IDENTITY_CONTROL wrong_top verdict=$v [expr {$id_ok ? {OK} : {BAD}}]"; puts "IDENTITY_CONTROL wrong_top verdict=$v [expr {$id_ok ? {OK} : {BAD}}]"
set bad [expr {[llength [lsearch -all $results *BAD]] + ($id_ok ? 0 : 1)}]
puts $fh "GATE_NEGATIVE_TESTS: [expr {$bad ? {FAIL} : {PASS}}] ([expr {6 - $bad}]/6)"
puts "GATE_NEGATIVE_TESTS: [expr {$bad ? {FAIL} : {PASS}}] ([expr {6 - $bad}]/6)"
close $fh
