# Self-test of n13_gate.tcl n13_util (run with Vivado tclsh): tclsh86t test_n13_util.tcl n13_gate.tcl <utilization_routed.rpt>
# Positive rows of the N-13 secure run 130942 and a negative (absent row -> NA, which the gate fails as not parsed).
source [lindex $argv 0]
set f [open [lindex $argv 1]]; set us [read $f]; close $f
set ok 1
foreach {lbl want} {{Slice LUTs} 38054 {LUT as Distributed RAM} 2014 {Slice Registers} 35857 {Block RAM Tile} 0.5 {DSPs} 0} {
  set got [n13_util $us $lbl]; puts "$lbl -> $got (want $want)"; if {$got ne $want} {set ok 0}
}
set neg [n13_util "| Something else | 1 |" {Slice LUTs}]
puts "negative (absent row) -> $neg"; if {$neg ne "NA" || [string is double -strict $neg]} {set ok 0}
puts [expr {$ok ? "N13_UTIL_TEST: PASS" : "N13_UTIL_TEST: FAIL"}]
