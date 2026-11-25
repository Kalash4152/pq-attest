# gui_synth_post.tcl - post-hook of synth_merged (sourced at the end of the run, after its checkpoint is written): put the mesh
# netlist of the accepted release build into its black-box cell, as step 3 of the release recipe does (s4_mesh_split.tcl).
# The run checkpoint then holds the whole design, so implementation and the schematic views need nothing extra.
set gsp_dcp [file join [file dirname [file dirname [file normalize [info script]]]] NOC_PQATTEST.gui_merged noc_mesh_3x2.dcp]
if {![file isfile $gsp_dcp]} { error "GUI_SYNTH_POST: mesh checkpoint missing: $gsp_dcp (source merged_gui_runs.tcl first)" }
set gsp_c [get_cells -quiet -hierarchical -filter {REF_NAME == noc_mesh_3x2 || ORIG_REF_NAME == noc_mesh_3x2}]
if {[llength $gsp_c] != 1} { error "GUI_SYNTH_POST: expected exactly one noc_mesh_3x2 instance, found [llength $gsp_c]" }
if {![get_property IS_BLACKBOX $gsp_c]} { error "GUI_SYNTH_POST: $gsp_c is not a black box after synthesis" }
set gsp_name [get_property NAME $gsp_c]
read_checkpoint -cell $gsp_c $gsp_dcp
# read_checkpoint invalidates Tcl handles to design objects: look the cell up again by name
set gsp_c [get_cells $gsp_name]
if {[get_property IS_BLACKBOX $gsp_c]} { error "GUI_SYNTH_POST: $gsp_name is still a black box after reading $gsp_dcp" }
set gsp_n [llength [get_cells -quiet -hierarchical -filter "NAME =~ $gsp_name/* && IS_PRIMITIVE"]]
if {$gsp_n < 1000} { error "GUI_SYNTH_POST: mesh has only $gsp_n primitive cells after linking" }
# Vivado sources this hook AFTER the run has written its checkpoint and utilization report: write both again, complete.
set gsp_top [get_property TOP [current_design]]
write_checkpoint -force -noxdef [file join [pwd] $gsp_top.dcp]
report_utilization -file [file join [pwd] ${gsp_top}_utilization_synth.rpt]
puts "GUI_SYNTH_POST mesh_cell=$gsp_name mesh_cells=$gsp_n checkpoint rewritten"
