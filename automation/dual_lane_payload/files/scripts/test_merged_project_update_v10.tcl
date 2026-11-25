# Configure the combined design twice in an isolated project; never opens or saves the owner's project.
set root [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
create_project NOC_PQATTEST [file join $out project] -part xc7a100tcsg324-1
set ::env(MG_ROOT) $root
set ::final_update_only 1
source [file join $root scripts final_project_update.tcl]
set expected [lsort [lmap s [concat [dict get $b sources] [dict get $b mem_init]] {mg_norm [file join $root $s]}]]
set actual [lsort [lmap s [get_files -norecurse -of_objects [get_filesets dl_merged_src]] {mg_norm $s}]]
if {$expected ne $actual} { error "combined source/firmware list mismatch" }
if {[get_property top [get_filesets dl_merged_src]] ne "pq_merged_board_top"} { error "wrong combined top" }
if {[lsort [get_property verilog_define [get_filesets dl_merged_src]]] ne [lsort [dict get $b defines]]} { error "wrong combined defines" }
if {[get_property top [get_filesets dl_merged_real]] ne "tb_merged_closure_v10"} { error "wrong lifecycle simulation top" }
if {[get_property xsim.simulate.runtime [get_filesets dl_merged_real]] ne "all"} { error "simulation runtime is not bounded by bench finish" }
set count [llength $actual]
source [file join $root scripts final_project_update.tcl]
if {$d_src ne {0 0}} { error "second update was not idempotent" }
if {[llength [get_files -norecurse -of_objects [get_filesets dl_merged_src]]] != $count} { error "source count changed on replay" }
set f [open [file join $out project_update_result.txt] w]
puts $f "MERGED_PROJECT_COPY: PASS source_and_firmware_files=$count idempotent=YES"
close $f
puts "MERGED_PROJECT_COPY: PASS source_and_firmware_files=$count idempotent=YES"
close_project
