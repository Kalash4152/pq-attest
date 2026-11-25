# Phase-5 isolated GUI-run test. Execute only after I-27 and fresh release gates PASS.
set root C:/vivado_verilog_proj/NOC_PQATTEST
set out C:/vivado_verilog_proj/_r10main
open_project [file join $root NOC_PQATTEST.xpr]
set ::env(MG_ROOT) $root
source [file join $root scripts merged_gui_runs.tcl]
source [file join $root scripts merged_gui_runs.tcl]
if {$d_gui ne {0 0}} { error "second GUI source sync not idempotent" }
if {[get_property NAME [current_run -synthesis]] ne "synth_merged"} { error "wrong active synthesis" }
if {[get_property NAME [current_run -implementation]] ne "impl_merged"} { error "wrong active implementation" }
if {[llength [get_files -of_objects [get_filesets dl_gui_src]]] != 73} { error "wrong GUI source count" }
if {[dict get $b mem_init] ne {sw/riscv/demo_fw_v3.hex}} { error "wrong GUI firmware" }
if {[dict get $b mem_init] ne {sw/riscv/demo_fw_v3.hex}} { error "wrong GUI firmware" }
gui_merged_build
wait_on_run impl_merged
if {[get_property STATUS [get_runs impl_merged]] ne "write_bitstream Complete!"} { error "GUI implementation incomplete" }
set run_dir [get_property DIRECTORY [get_runs impl_merged]]
if {![file isfile [file join $run_dir pq_merged_board_top.bit]]} { error "GUI bitstream missing" }
set f [open [file join $run_dir gate gate_summary.txt] r];set g [read $f];close $f
if {![regexp -line {^VERDICT PASS } $g]} { error "GUI gate missing PASS" }
open_run impl_merged
if {[get_property TOP [current_design]] ne "pq_merged_board_top"} { error "wrong implemented top" }
# Review diagnostics in both child runs and the parent log; do not suppress critical warnings.
foreach audit_log [list [file join $out gui_vivado.log] [file join [get_property DIRECTORY [get_runs synth_merged]] runme.log] [file join $run_dir runme.log]] {
  if {![file isfile $audit_log]} { error "GUI audit log missing: $audit_log" }
  set audit_f [open $audit_log r];set audit_text [read $audit_f];close $audit_f
  if {[regexp -line {^(CRITICAL WARNING:|ERROR:)} $audit_text]} { error "GUI diagnostics require review: $audit_log" }
}
puts "R10_MAIN_GUI: PASS idempotent=YES sources=73 whole_design_opened=YES"
close_design
close_project

