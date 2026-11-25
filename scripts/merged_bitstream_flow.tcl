# merged_bitstream_flow.tcl - MERGED-SoC bitstream with the registered S4 flow (copy of scripts/p7_bitstream_flow.tcl; only
# the source table differs: scripts/merged_bitstream_sources.tcl from scripts/make_merged_sources.py). NOT evidence.
#   vivado -mode batch -source scripts/merged_bitstream_flow.tcl -tclargs merged_board
# Output: NOC_PQATTEST.runs_merged/<name>/ (<top>.bit, utilization.rpt, utilization_hier.rpt, timing_summary.rpt, result.txt).
set root [file normalize [file join [file dirname [info script]] ..]]
set name [lindex $argv 0]
source [file join $root scripts merged_bitstream_sources.tcl]
if {![dict exists $::merged_bit $name]} { error "unknown bitstream $name (known: [dict keys $::merged_bit])" }
set b [dict get $::merged_bit $name]
set top [dict get $b top]
set part xc7a100tcsg324-1
set_param general.maxThreads 1
set out [file join $root NOC_PQATTEST.runs_merged $name]
foreach m [dict get $b mem_init] { file copy -force [file join $root $m] [pwd] }   ;# firmware images next to the run
file mkdir $out
set srcs [lmap s [dict get $b sources] {file join $root $s}]
set xdc  [file join $root [dict get $b xdc]]
set defs {}; foreach d [dict get $b defines] { lappend defs -verilog_define $d }
source [file join $root scripts s4_mesh_split.tcl]
s4_mesh_split $srcs [list $xdc] $top $part [concat [list -flatten_hierarchy rebuilt -directive AreaOptimized_high] $defs] $defs \
  [file join $root synth s4 noc_mesh_3x2_bb.sv] $out 0
opt_design -directive Explore
place_design -directive ExtraTimingOpt
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore
set u [report_utilization -return_string]
set t [report_timing_summary -return_string]
set f [open [file join $out utilization.rpt] w]; puts $f $u; close $f
set f [open [file join $out timing_summary.rpt] w]; puts $f $t; close $f
report_utilization -hierarchical -hierarchical_depth 4 -file [file join $out utilization_hier.rpt]
set lut NA; set ff NA; set wns NA; set whs NA
regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)} $u -> lut
regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)} $u -> ff
set p [get_timing_paths -setup -max_paths 1]; if {$p ne ""} { set wns [get_property SLACK $p] }
set h [get_timing_paths -hold -max_paths 1];  if {$h ne ""} { set whs [get_property SLACK $h] }
write_checkpoint -force [file join $out routed.dcp]
source [file join $root scripts merged_board_gate.tcl]
if {[merged_gate $top $out] ne "PASS"} { error "Merged board gate FAIL: bitstream withheld" }
set bit [file join $out $top.bit]
write_bitstream -force $bit
set line "$name: top $top  LUT $lut  FF $ff  WNS $wns ns  WHS $whs ns  bitstream $bit"
set f [open [file join $out result.txt] w]; puts $f $line; close $f
puts "MERGED_BITSTREAM $line"
