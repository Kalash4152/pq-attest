# Source from the existing main Vivado GUI. No exit/quit and no GUI child process channels.
set final_root [file normalize [file join [file dirname [info script]] ..]]
set final_python C:/Users/kalas/AppData/Local/Programs/Python/Python313/python.exe
set final_project [current_project -quiet]
if {$final_project eq "" || [get_property NAME $final_project] ne "NOC_PQATTEST"} {
  error "Open the intended NOC_PQATTEST.xpr before sourcing this update."
}
set final_copy_test [expr {[info exists ::final_update_only] && $::final_update_only &&
                         [info exists ::env(MG_ROOT)] && [string equal -nocase [file normalize $::env(MG_ROOT)] $final_root]}]
if {!$final_copy_test && ![string equal -nocase [file normalize [get_property DIRECTORY $final_project]] $final_root]} {
  error "This update belongs to $final_root/NOC_PQATTEST.xpr; a different project copy is open."
}
if {![file isfile $final_python]} { error "Configured Python is missing: $final_python" }
foreach checker {check_closure_profile_v10.py check_merged_board_profile_v10.py} {
  puts [exec $final_python -E [file join $final_root scripts $checker] 2>@1]
}
source [file join $final_root scripts merged_project_update.tcl]
if {![info exists ::final_update_only] || !$::final_update_only} {
  merged_build
  puts "Combined project updated. Build started separately; use merged_result for its gated outcome."
} else {
  puts "Combined project updated; build deliberately omitted for the isolated update test."
}
