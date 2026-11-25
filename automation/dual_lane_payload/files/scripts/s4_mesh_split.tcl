# S4-F3 mesh split (docs/decisions/S4_AREA_CONTRACT.md sec. 6). Sourced by the implementation children
# (scripts/d4_crypto_ooc_child.tcl, scripts/n13_impl.tcl) and by scripts/p7_bitstream_flow.tcl when a job sets
# synth_mesh_split. Replaces "read sources, read XDC, synth_design" with:
#   1. noc_mesh_3x2 alone, out of context, release settings (-flatten_hierarchy none, no directive, LINK_PIPE=1, 20 ns clk);
#   2. the rest with the caller's synthesis options (S4-F1 + F2), the mesh as a black box (bb declaration file);
#   3. link both checkpoints (mesh checkpoint scoped to the single noc_mesh_3x2 instance).
# Leaves the linked design open in an in-memory project. Fails closed on every structural doubt.
#   sources : the job's source list (must contain exactly one .../noc_mesh_3x2.sv)
#   xdcs    : constraint files for step 2 (the caller's, read before synthesis as in the unsplit flow)
#   opts    : the caller's synth_design options for step 2 (-mode / -flatten / -directive / defines / include dirs)
#   mopts   : defines / include dirs for step 1 only
#   ooc     : 1 = link out of context (OOC P&R jobs), 0 = in context (real-pin tops)
proc s4_mesh_split {sources xdcs top part opts mopts bb out ooc} {
  set mesh_files [lsearch -all -inline -regexp $sources {(^|[/\\])noc_mesh_3x2\.sv$}]
  if {[llength $mesh_files] != 1} { error "S4-F3: expected exactly one noc_mesh_3x2.sv in the sources, found [llength $mesh_files]" }
  if {![file isfile $bb]} { error "S4-F3: black-box declaration $bb missing" }
  # every instantiation of the mesh in the sources must be #(.LINK_PIPE(1'b1)) (step 1 synthesizes that configuration)
  set n_inst 0
  foreach s $sources {
    set f [open $s r]; set t [read $f]; close $f
    foreach {m} [regexp -all -inline {noc_mesh_3x2\s*(#\s*\([^;]*?\))?\s+\w+\s*\(} $t] {
      incr n_inst
      if {![regexp {#\s*\(\s*\.LINK_PIPE\s*\(\s*1'b1\s*\)\s*\)} $m]} { error "S4-F3: mesh instantiation without LINK_PIPE=1'b1 in $s" }
    }
  }
  if {$n_inst < 1} { error "S4-F3: no noc_mesh_3x2 instantiation found in the sources" }
  # step 1: the mesh, release settings
  set mxdc [file join $out s4f3_mesh_clk.xdc]
  set f [open $mxdc w]; puts $f {create_clock -name clk -period 20.000 [get_ports clk]}; close $f
  create_project -in_memory -part $part
  read_verilog -sv $sources
  read_xdc $mxdc
  # The 20 ns clock is for timing-driven mesh synthesis only. It must not travel in the mesh checkpoint: linked into a real-pin
  # top it would re-define clock "clk" on the mesh pin and leave the rest of the design unclocked (s4r_n13_* FAIL, 2026-11-05).
  set_property USED_IN_IMPLEMENTATION false [get_files $mxdc]
  synth_design -top noc_mesh_3x2 -part $part -mode out_of_context -flatten_hierarchy none -generic LINK_PIPE=1 {*}$mopts
  set mdcp [file join $out s4f3_mesh.dcp]
  write_checkpoint -force $mdcp
  report_utilization -file [file join $out s4f3_mesh_util.rpt]
  close_project
  # step 2: the rest, caller's options, mesh as a black box
  create_project -in_memory -part $part
  set srcs2 {}
  foreach s $sources { if {$s eq [lindex $mesh_files 0]} { lappend srcs2 $bb } else { lappend srcs2 $s } }
  read_verilog -sv $srcs2
  foreach x $xdcs { read_xdc $x }
  synth_design -top $top -part $part {*}$opts
  set bbc [get_cells -quiet -hierarchical -filter {REF_NAME == noc_mesh_3x2 || ORIG_REF_NAME == noc_mesh_3x2}]
  if {[llength $bbc] != 1} { error "S4-F3: expected exactly one noc_mesh_3x2 instance, found [llength $bbc]" }
  if {![get_property IS_BLACKBOX $bbc]} { error "S4-F3: $bbc is not a black box after step 2" }
  set cell [get_property NAME $bbc]
  set tdcp [file join $out s4f3_rest.dcp]
  write_checkpoint -force $tdcp
  close_project
  # step 3: link
  create_project -in_memory -part $part
  add_files [list $tdcp $mdcp]
  set_property SCOPED_TO_CELLS [list $cell] [get_files $mdcp]
  if {$ooc} { link_design -top $top -part $part -mode out_of_context } else { link_design -top $top -part $part }
  set nm [s4_mesh_split_check $cell]
  puts "S4F3_SPLIT mesh_cell=$cell mesh_cells=$nm instantiations=$n_inst"
  return $cell
}

# Post-link checks of the S4-F3 split (also used by the negative test scripts/test_s4_mesh_split.tcl). Returns the mesh cell count.
proc s4_mesh_split_check {cell} {
  set left [get_cells -quiet -hierarchical -filter {IS_BLACKBOX == 1}]
  if {[llength $left]} { error "S4-F3: black boxes left after link: $left" }
  set nm [llength [get_cells -quiet -hierarchical -filter "NAME =~ $cell/*"]]
  if {$nm < 1} { error "S4-F3: no cells under $cell after link" }
  # every clock must come from the caller's constraints: none may be sourced on or inside the mesh cell
  foreach c [get_clocks -quiet] {
    foreach sp [get_property SOURCE_PINS $c] {
      if {[string match "$cell/*" $sp]} { error "S4-F3: clock [get_property NAME $c] is sourced inside the mesh ($sp)" }
    }
  }
  if {![llength [get_clocks -quiet]]} { error "S4-F3: no clock after link" }
  return $nm
}
