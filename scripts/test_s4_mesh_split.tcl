# Negative test for the S4-F3 post-link checks (scripts/s4_mesh_split.tcl, proc s4_mesh_split_check). Links the two checkpoints
# of the FAILED run s4r_n13_secure (2026-11-05, mesh checkpoint still carrying its synthesis clock) and requires the check to
# refuse them. Usage: vivado -mode batch -source scripts/test_s4_mesh_split.tcl -tclargs <rest.dcp> <mesh.dcp> <cell> <top>
lassign $argv rest mesh cell top
source [file join [file dirname [info script]] s4_mesh_split.tcl]
create_project -in_memory -part xc7a100tcsg324-1
add_files [list $rest $mesh]
set_property SCOPED_TO_CELLS [list $cell] [get_files $mesh]
link_design -top $top -part xc7a100tcsg324-1
foreach c [get_clocks -quiet] { puts "CLOCK [get_property NAME $c] sources=[get_property SOURCE_PINS $c]" }
if {[catch {s4_mesh_split_check $cell} e]} {
  puts "REFUSED: $e"
  puts [expr {[string match "*sourced inside the mesh*" $e] ? "TEST_S4F3_CLOCK_CHECK: PASS" : "TEST_S4F3_CLOCK_CHECK: FAIL (wrong reason)"}]
} else { puts "TEST_S4F3_CLOCK_CHECK: FAIL (accepted a mesh-sourced clock)" }
