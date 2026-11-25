# Isolated I-1 mesh-only implementation. Run by scheduler in a child process.
source [lindex $argv 0]
if {![string match 2024.1* [version -short]]} { error "Wrong Vivado version" }
if {[llength [get_projects -quiet]] || $TOP ne "noc_mesh_synth_top"} { error "Wrong mesh child context" }
create_project mesh_gate [file join $OUT workspace] -part $PART
add_files -norecurse $SOURCES
add_files -fileset constrs_1 -norecurse $XDC
set_property top $TOP [get_filesets sources_1]
update_compile_order -fileset sources_1
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
# New isolated directory: no incremental checkpoint is supplied or inherited.
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis incomplete" }
launch_runs impl_1 -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Implementation incomplete" }
open_run impl_1
if {[get_property PERIOD [get_clocks clk]] != 20.000} { error "Wrong clock target" }
source $GATE
set verdict [n25_gate impl_1 $OUT]
set f [open [file join $OUT timing_summary_routed.rpt] r]
set timing [read $f]
close $f
if {![regexp -nocase {Design State\s*:\s*Physopt postRoute} $timing]} {
  error "Chosen strategy did not reach the historical post-route PhysOpt state"
}
write_checkpoint [file join $OUT routed.dcp]
set f [open [file join $OUT scope.txt] w]
puts $f "MESH_ONLY\nNI_CRYPTO_INCLUDED=NO\nINCREMENTAL_DCP=NONE\nVERDICT=$verdict"
close $f
close_project
