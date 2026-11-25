# N-13 isolated batch synthesis + implementation of a real-pin top (docs/decisions/I8_RELEASE_PLAN.md). Child of the
# scheduler (kind implementation). Non-project flow, explicit sources, no incremental checkpoint. Same synthesis options
# (-flatten_hierarchy none, timing-driven with the XDC read first) and the same S1-PNR-DIR directives as the P7 P&R
# checkpoint; real package pins instead of the OOC HD.CLK_SRC model.
source [lindex $argv 0]
if {![string match 2024.1* [version -short]]} { error "Wrong Vivado version" }
if {[llength [get_projects -quiet]]} { error "N-13 child must start without a project" }
if {![info exists SYNTH_MESH_SPLIT]} {
set_part $PART
read_verilog -sv $SOURCES
read_xdc $XDC
}
set flat none
if {[info exists SYNTH_FLATTEN]} { set flat $SYNTH_FLATTEN }   ;# S4-F1 (job field synth_flatten)
set opts [list -flatten_hierarchy $flat]
if {[info exists SYNTH_DIRECTIVE]} { lappend opts -directive $SYNTH_DIRECTIVE }   ;# S4-F2
if {[llength $INCLUDES]} { lappend opts -include_dirs $INCLUDES }
foreach d $DEFINES { lappend opts -verilog_define $d }
if {[info exists SYNTH_MESH_SPLIT]} {
  # S4-F3 (docs/decisions/S4_AREA_CONTRACT.md sec. 6): mesh synthesized alone with the release settings, linked in.
  source $SYNTH_MESH_SPLIT
  set mopts {}
  if {[llength $INCLUDES]} { lappend mopts -include_dirs $INCLUDES }
  foreach d $DEFINES { lappend mopts -verilog_define $d }
  s4_mesh_split $SOURCES [list $XDC] $TOP $PART $opts $mopts $SYNTH_MESH_BB $OUT 0
} else {
synth_design -top $TOP -part $PART {*}$opts
}
write_checkpoint -force [file join $OUT synth.dcp]
report_utilization -file [file join $OUT utilization_synth.rpt]
opt_design -directive Explore
place_design -directive ExtraTimingOpt
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore
if {[get_property PERIOD [get_clocks clk]] != 20.000} { error "Wrong clock target" }
report_design_analysis -congestion -complexity -timing -max_paths 20 -file [file join $OUT design_analysis_routed.rpt]
source $GATE
set verdict [n13_gate $TOP $OUT]
write_checkpoint -force [file join $OUT routed.dcp]
set f [open [file join $OUT scope.txt] w]
puts $f "N13_TOP=$TOP\nINCREMENTAL_DCP=NONE\nFLOW=S1-PNR-DIR directives, real pins\nVERDICT=$verdict"
close $f
