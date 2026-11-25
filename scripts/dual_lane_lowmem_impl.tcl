# Low-memory child wrapper (I-2, Kalash 2026-10-19): one Vivado worker thread in this
# child process, then the standard dual_lane_impl.tcl child (argv is passed through).
# launch_runs subprocesses (synth_1, impl_1) are separate Vivado processes: an execution
# trace on launch_runs installs a TCL.PRE hook on each run's first step that sets
# general.maxThreads 1 inside that subprocess and logs it (DUAL_LANE_LOWMEM_HOOK).
# synth_1 and impl_1 already run strictly one after the other (wait_on_run between them).
set_param general.maxThreads 1
puts "DUAL_LANE_LOWMEM maxThreads=[get_param general.maxThreads]"
source [lindex $argv 0]
set ::dl_lowmem_hook [file normalize [file join $OUT lowmem_maxthreads_hook.tcl]]
set fh [open $::dl_lowmem_hook w]
puts $fh "set_param general.maxThreads 1"
puts $fh "puts \"DUAL_LANE_LOWMEM_HOOK maxThreads=\[get_param general.maxThreads\]\""
close $fh
proc ::dl_lowmem_on_launch {cmd op} {
    set run [lindex $cmd 1]
    switch -- $run {
        synth_1 { set_property STEPS.SYNTH_DESIGN.TCL.PRE $::dl_lowmem_hook [get_runs synth_1] }
        impl_1  { set_property STEPS.INIT_DESIGN.TCL.PRE  $::dl_lowmem_hook [get_runs impl_1] }
        default { error "lowmem wrapper: unexpected run $run" }
    }
    puts "DUAL_LANE_LOWMEM hook installed on $run"
}
trace add execution launch_runs enter ::dl_lowmem_on_launch
source [file join [file dirname [file normalize [info script]]] dual_lane_impl.tcl]
