# Replacement: generates mutants from CURRENT router into private directories.
# Does not read mut/noc_router.sv.orig and NEVER writes the live router.
source [file join [file dirname [file normalize [info script]]] wp0_common.tcl]
wp0::n6_main
