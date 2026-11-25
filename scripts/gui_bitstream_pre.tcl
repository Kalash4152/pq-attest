# Pre-bitstream hook of run impl_merged (scripts/merged_gui_runs.tcl): the merged board gate on the routed design.
# A gate FAIL raises an error, so write_bitstream does not run and no image is produced.
source [file join [file dirname [info script]] merged_board_gate.tcl]
set gui_gate_dir [file join [pwd] gate]; file mkdir $gui_gate_dir
set gui_verdict [merged_gate pq_merged_board_top $gui_gate_dir]
if {$gui_verdict ne "PASS"} { error "Merged board gate FAIL: bitstream withheld (see [file join $gui_gate_dir gate_summary.txt])" }
puts "GUI_GATE PASS (summary: [file join $gui_gate_dir gate_summary.txt])"
