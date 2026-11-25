# merged_gui_runs.tcl - make the GUI buttons (Run Synthesis / Run Implementation / Generate Bitstream) build the COMBINED
# SoC (NoC + PQ-Attest + two RISC-V tiles, firmware v3 / profile 10) with the accepted release recipe. Claude, 2026-11-12, for Kalash.
#
# Vivado Tcl console, NOC_PQATTEST.xpr open:
#   source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/merged_gui_runs.tcl
# then press Generate Bitstream (or: gui_merged_build).
#
# What it does (nothing is deleted; the old runs synth_1 / impl_1 / ... stay, only "active" moves):
#   1. sources merged_project_update.tcl (backup of the .xpr, combined sets synchronised in place);
#   2. source set dl_gui_src = the combined list with the mesh replaced by its black-box declaration + the mesh netlist
#      checkpoint of the accepted release build (the release recipe synthesises the mesh separately, S4-F3);
#   3. runs synth_merged / impl_merged with the release options (-flatten_hierarchy rebuilt, AreaOptimized_high; opt Explore,
#      place ExtraTimingOpt, phys_opt AggressiveExplore, route AggressiveExplore, post-route phys_opt AggressiveExplore),
#      one thread, firmware image copied into the synthesis run, and the merged board GATE before write_bitstream
#      (a gate FAIL stops the run: no bitstream);
#   4. makes them the active runs.
# The gated batch route (final_project_update.tcl / merged_result) stays the reference for recorded evidence.
set gui_here [file normalize [file dirname [info script]]]
source [file join $gui_here merged_project_update.tcl]

set gui_dir  [file join $::mg_root NOC_PQATTEST.gui_merged]
set gui_dcp  [file join $gui_dir noc_mesh_3x2.dcp]
set rel_dir  [file join $::mg_root NOC_PQATTEST.runs_merged merged_board]
set rel_dcp  [file join $rel_dir s4f3_mesh.dcp]
set py C:/Users/kalas/AppData/Local/Programs/Python/Python313/python.exe
# the mesh checkpoint must come from an accepted, drift-free release build
set rel [exec $py -E [file join $::mg_root scripts merged_release.py] result 2>@1]
if {![string match "MERGED RELEASE PASS*" $rel]} { error "No accepted release build to take the mesh netlist from: $rel" }
if {![file isfile $rel_dcp]} { error "Mesh checkpoint missing: $rel_dcp (run final_project_update.tcl / merged_result first)" }
file mkdir $gui_dir
if {![file isfile $gui_dcp] || [file size $gui_dcp] != [file size $rel_dcp] || [file mtime $gui_dcp] < [file mtime $rel_dcp]} {
  file copy -force $rel_dcp $gui_dcp
}

set b [dict get $::merged_bit merged_board]
set mesh_sv {}; set gsrcs {}
foreach s [dict get $b sources] {
  if {[regexp {(^|/)noc_mesh_3x2\.sv$} $s]} { lappend mesh_sv $s } else { lappend gsrcs [file join $::mg_root $s] }
}
if {[llength $mesh_sv] != 1} { error "expected exactly one noc_mesh_3x2.sv in the combined list" }
set gbb [file join $::mg_root synth s4 noc_mesh_3x2_bb.sv]
set gmems [lmap m [dict get $b mem_init] {file join $::mg_root $m}]
set gs [mg_fileset -srcset dl_gui_src]
set d_gui [mg_sync_files $gs [concat $gsrcs [list $gbb $gui_dcp] $gmems]]
set_property verilog_define [dict get $b defines] $gs
set_property include_dirs [list [file join $::mg_root vectors] [file join $::mg_root sim_riscv include]] $gs
set_property top [dict get $b top] $gs
set_property USED_IN_SYNTHESIS false [get_files -of_objects $gs [file tail $gui_dcp]]   ;# synthesis sees the black box; implementation links the netlist

set part [get_property PART [current_project]]
if {[get_runs -quiet synth_merged] eq ""} {
  create_run synth_merged -flow [get_property FLOW [get_runs synth_1]] -srcset dl_gui_src -constrset dl_merged_xdc -part $part
}
if {[get_runs -quiet impl_merged] eq ""} {
  create_run impl_merged -parent_run synth_merged -flow [get_property FLOW [get_runs impl_1]] -constrset dl_merged_xdc -part $part
}
set sr [get_runs synth_merged]; set ir [get_runs impl_merged]
set_property AUTO_INCREMENTAL_CHECKPOINT 0 $sr
set_property -name {STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY} -value rebuilt -objects $sr
set_property -name {STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE} -value AreaOptimized_high -objects $sr
set_property STEPS.SYNTH_DESIGN.TCL.PRE [file join $gui_here gui_synth_pre.tcl] $sr
set_property STEPS.SYNTH_DESIGN.TCL.POST [file join $gui_here gui_synth_post.tcl] $sr   ;# links the mesh netlist into its black box
set_property STEPS.INIT_DESIGN.TCL.PRE  [file join $gui_here gui_impl_pre.tcl] $ir
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Explore $ir
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraTimingOpt $ir
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $ir
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $ir
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore $ir
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true $ir
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $ir
set_property STEPS.WRITE_BITSTREAM.TCL.PRE [file join $gui_here gui_bitstream_pre.tcl] $ir
current_run -synthesis $sr
current_run -implementation $ir
puts "GUI runs ready: synth_merged / impl_merged are ACTIVE (source set dl_gui_src: [llength [get_files -of_objects $gs]] files, changed now: $d_gui; top [dict get $b top])."
puts "Press Generate Bitstream (or type: gui_merged_build). The gate runs before the bitstream is written; a gate FAIL stops the run."

proc gui_merged_build {} {
  reset_run synth_merged
  launch_runs impl_merged -to_step write_bitstream -jobs 1
  puts "Building in the Design Runs tab (about 30 to 40 min). Bitstream: <project>.runs/impl_merged/pq_merged_board_top.bit"
}
