# User entrypoint. GUI project is never modified or closed by child jobs.
source [file join [file dirname [file normalize [info script]]] dual_lane_common.tcl]
dual_lane::run all
