# Replacement for the archived n81_xsim.tcl. Run in Windows Vivado 2024.1,
# project open, no simulation open. Requires the adjacent WP-0 helper files.
source [file join [file dirname [file normalize [info script]]] wp0_common.tcl]
wp0::n81_main
