namespace eval dual_lane { variable root [file dirname [file dirname [file normalize [info script]]]] }
proc dual_lane::run {{selection all}} {
  variable root
  if {[llength [info commands version]] && ![string match 2024.1* [version -short]]} {
    error "Use Vivado 2024.1"
  }
  if {[llength [info commands current_project]] && [current_project -quiet] ne ""} {
    set p [current_project]
    if {[file normalize [get_property DIRECTORY $p]] ne $root} { error "Open project does not match launcher root" }
    if {[get_property PART $p] ne "xc7a100tcsg324-1"} { error "Wrong open-project part" }
    if {[llength [current_sim -quiet]]} { error "Close the active simulation before starting" }
  }
  # The Python scheduler enforces the active Revision 4 increment and checks
  # active module/package names before every job, including evidence reuse.
  # It also guards installation, source identity, timeouts and isolated exports.
  set python C:/Users/kalas/AppData/Local/Programs/Python/Python313/python.exe
  if {![file isfile $python]} { error "Configured Python missing; update dual_lane_config.json and this bootstrap" }
  set channel [open |[list $python -u [file join $root scripts dual_lane.py] run --select $selection] r]
  fconfigure $channel -buffering line -blocking 0
  set ::dual_lane_done 0
  fileevent $channel readable [list dual_lane::stream $channel]
  vwait ::dual_lane_done
  fileevent $channel readable {}
  fconfigure $channel -blocking 1
  if {[catch {close $channel} message]} { error "Dual-lane execution incomplete/failed: $message. Read reports/dual_lane_latest.json" }
}
proc dual_lane::stream {channel} {
  while {[gets $channel line] >= 0} { puts $line }
  if {[eof $channel]} { set ::dual_lane_done 1 }
}
