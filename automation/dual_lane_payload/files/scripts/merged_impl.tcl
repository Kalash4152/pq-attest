# merged_impl.tcl - harness child (kind implementation) for the MERGED SoC board top (Lane 1 2026-11-07, I-17). Non-project
# batch flow with the same steps as scripts/merged_bitstream_flow.tcl (the release S4 flow that built the board image):
# mesh split + -flatten_hierarchy rebuilt -directive AreaOptimized_high, opt Explore, place ExtraTimingOpt, phys_opt
# AggressiveExplore, route AggressiveExplore, phys_opt AggressiveExplore. Then the merged board gate (job gate_script).
# Firmware: every *.hex in the job's include dirs is copied into the run directory first, so $readmemh("demo_fw.hex") in
# the CPU tiles resolves exactly as in the release flow (which copies mem_init files next to the run).
source [lindex $argv 0]
if {![string match 2024.1* [version -short]]} { error "Wrong Vivado version" }
if {[llength [get_projects -quiet]]} { error "merged child must start without a project" }
set_param general.maxThreads 1
set nhex 0
foreach d $INCLUDES { foreach h [glob -nocomplain -directory $d *.hex] { file copy -force $h [pwd]; incr nhex } }
if {$nhex == 0} { error "no firmware image (*.hex) in the include dirs" }
puts "MERGED_IMPL firmware images copied: $nhex"
set opts [list -flatten_hierarchy rebuilt -directive AreaOptimized_high]
if {[info exists SYNTH_FLATTEN]} { set opts [list -flatten_hierarchy $SYNTH_FLATTEN]; if {[info exists SYNTH_DIRECTIVE]} { lappend opts -directive $SYNTH_DIRECTIVE } }
set defs {}; foreach d $DEFINES { lappend defs -verilog_define $d }
if {![info exists SYNTH_MESH_SPLIT]} { error "merged board flow requires the S4 mesh split (job field synth_mesh_split)" }
source $SYNTH_MESH_SPLIT
s4_mesh_split $SOURCES [list $XDC] $TOP $PART [concat $opts $defs] $defs $SYNTH_MESH_BB $OUT 0
write_checkpoint -force [file join $OUT synth.dcp]
report_utilization -file [file join $OUT utilization_synth.rpt]
opt_design -directive Explore
place_design -directive ExtraTimingOpt
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore
source $GATE
set verdict [merged_gate $TOP $OUT]
if {$verdict eq "PASS"} { write_bitstream -force [file join $OUT $TOP.bit] }
write_checkpoint -force [file join $OUT routed.dcp]
set f [open [file join $OUT scope.txt] w]
puts $f "MERGED_TOP=$TOP\nFLOW=S4 release (merged_bitstream_flow.tcl steps)\nFIRMWARE_IMAGES=$nhex\nVERDICT=$verdict"
close $f
