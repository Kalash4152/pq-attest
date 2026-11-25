# No-Vivado static self-test for reports/i2_p2/d4_crypto_ooc.tcl.
# Usage: tclsh selftest_d4_parsers.tcl <repo_root>
# Loads the script in library mode (procedures only; the launcher and child
# bodies are NOT run), then exercises the report parsers on the real Vivado
# 2024.1 reports that ni_ooc produced in I-1. This proves parser/format
# compatibility only. It is NOT synthesis evidence.
set root [file normalize [lindex $argv 0]]
set script [file join $root reports i2_p2 d4_crypto_ooc.tcl]
set fh [open $script r]; set text [read $fh]; close $fh
set fails 0
proc check {cond name} {
  global fails
  if {[uplevel 1 [list expr $cond]]} { puts "PASS $name" } else { puts "FAIL $name"; incr fails }
}
check [info complete $text] "info complete d4_crypto_ooc.tcl"
set fh [open [file join $root scripts d4_crypto_ooc.xdc] r]; set xdc [read $fh]; close $fh
check [info complete $xdc] "info complete d4_crypto_ooc.xdc"

set ::d4ooc_library_only 1
source $script

set ni [file join $root reports dual_lane_10_20261008_235701_d7b8ee31 ni_ooc]
proc slurp {p} { set f [open $p r]; set s [read $f]; close $f; return $s }
set us [slurp [file join $ni utilization.rpt]]
set ts [slurp [file join $ni timing_summary.rpt]]
set ms [slurp [file join $ni methodology.rpt]]

check {[d4ooc::util_row $us {Slice LUTs}] eq "412"} "util LUT=412"
check {[d4ooc::util_row $us {LUT as Logic}] eq "388"} "util LUT_LOGIC=388"
check {[d4ooc::util_row $us {LUT as Distributed RAM}] eq "24"} "util LUTRAM=24"
check {[d4ooc::util_row $us {LUT as Shift Register}] eq "0"} "util SRL=0"
check {[d4ooc::util_row $us {Slice Registers}] eq "266"} "util FF=266"
check {[d4ooc::util_row $us {Block RAM Tile}] eq "0"} "util BRAM=0"
check {[d4ooc::util_row $us {DSPs}] eq "0"} "util DSP=0"
check {[d4ooc::util_row $us {No Such Row}] eq "NA"} "util absent row -> NA"

set d [d4ooc::parse_dts $ts]
check {[dict get $d WNS] eq "4.464" && [dict get $d WHS] eq "0.263"} "DTS WNS/WHS match ni_ooc metrics.txt"
check {[dict get $d TNS] eq "0.000" && [dict get $d TNS_TOT] eq "1297"} "DTS TNS/endpoints"

set ct [d4ooc::parse_check_timing $ts]
check {[dict size $ct] >= 10} "check_timing: >=10 categories parsed ([dict size $ct])"
check {[d4ooc::unconstrained_total $ct] == 0} "check_timing: ni_ooc unconstrained total 0"
set bad "1. checking no_clock (0)\n5. checking no_input_delay (3)\n6. checking no_output_delay (2)\n"
check {[d4ooc::unconstrained_total [d4ooc::parse_check_timing $bad]] == 5} "check_timing: synthetic 3+2 -> 5"
check {[catch {d4ooc::parse_check_timing "nothing here"}]} "check_timing: missing section is an error"

lassign [d4ooc::parse_methodology $ms] total rules
check {$total eq "494" && $rules eq "XDCH-2/Warning:494"} "methodology: $total $rules"

foreach top {pq_kdf pq_measurement pq_attestation_tag pq_attestation_controller pq_attest_endpoint} {
  set rows [d4ooc::expected_children $top]
  set paths {}
  foreach r $rows { lappend paths [lindex $r 0] }
  check {[llength $paths] == [llength [lsort -unique $paths]] && [llength $paths] > 0} "expected children unique for $top ([llength $paths])"
  puts "  $top: [join $paths { }]"
}
check {[catch {d4ooc::expected_children noc_network_interface}]} "unknown top rejected"

# Every expected path must be a chain of instance names that exists in the RTL:
# "<module> [#(...)] <inst> (" in the parent module's file.
set src [file join $root NOC_PQATTEST.srcs sources_1 new]
set rtl ""
foreach f [glob -directory $src *.sv] { append rtl [slurp $f] "\n" }
append rtl [slurp [file join $root rtl dual_lane pq_attest_endpoint.sv]]
foreach top {pq_kdf pq_measurement pq_attestation_tag pq_attestation_controller pq_attest_endpoint} {
  foreach r [d4ooc::expected_children $top] {
    lassign $r path module
    set inst [lindex [split $path /] end]
    set re "(?w)^\\s*${module}\\s*(#\\s*\\(\[^;\]*?\\))?\\s*${inst}\\s*\\("
    check [regexp $re $rtl] "RTL instantiates $module $inst ($top: $path)"
  }
}
puts "SELFTEST_FAILS=$fails"
exit [expr {$fails ? 1 : 0}]
