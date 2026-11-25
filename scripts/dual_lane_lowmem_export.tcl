# Low-memory child wrapper (I-2, Kalash 2026-10-19): one Vivado worker thread in this
# child process, then the standard dual_lane_export.tcl child (argv is passed through).
# launch_runs subprocesses (mesh synth_1/impl_1) are separate Vivado processes and may
# not inherit this parameter.
set_param general.maxThreads 1
puts "DUAL_LANE_LOWMEM maxThreads=[get_param general.maxThreads]"
source [file join [file dirname [file normalize [info script]]] dual_lane_export.tcl]
