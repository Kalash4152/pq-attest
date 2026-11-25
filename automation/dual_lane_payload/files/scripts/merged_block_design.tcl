# merged_block_design.tcl - add the reference block design of the combined SoC to the OPEN NOC_PQATTEST project.
# Claude, 2026-11-12, for Kalash. Vivado 2024.1. For documentation (paper figure / diagram); not a build path.
#
# Vivado Tcl console, NOC_PQATTEST.xpr open:
#   source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/merged_block_design.tcl
#
# What it does (nothing is deleted or re-pointed; the active runs synth_merged / impl_merged and their source set
# dl_gui_src are not touched, so the Generate Bitstream flow and its bitstream are unaffected):
#   1. backs up the .xpr;
#   2. creates source set dl_bd_src = the combined source list + firmware image + the plain-Verilog shell
#      synth/merged/pq_merged_board_bd_ref.v (pass-through, no logic);
#   3. creates block design pq_merged_bd in that set: ONE module-reference cell u_soc (the unmodified board top) and the
#      seven board ports; validates, saves, generates the wrapper pq_merged_bd_wrapper (top of dl_bd_src only);
#   4. puts the active source set back to what it was and leaves the diagram open.
# Sourcing it again only re-opens the diagram.

proc pq_merged_bd {} {
  proc bd_fail {msg} { error "MERGED_BD FAILED: $msg" }
  set P [current_project -quiet]
  if {$P eq ""} { bd_fail "open NOC_PQATTEST.xpr first" }
  if {[get_property NAME $P] ne "NOC_PQATTEST"} { bd_fail "current project is [get_property NAME $P], not NOC_PQATTEST" }
  if {![string match "2024.1*" [version -short]]} { bd_fail "Vivado [version -short]; verified with 2024.1 only" }
  set root [file dirname [file dirname [file normalize [info script]]]]
  set name pq_merged_bd
  set setn dl_bd_src

  if {[llength [get_files -quiet $name.bd]] != 0} {
    open_bd_design [get_files $name.bd]
    puts "MERGED_BD: block design $name already exists (source set $setn); diagram opened, nothing changed."
    return
  }
  foreach r [get_runs -quiet] {
    if {[get_property STATUS $r] in {"Running" "Queued..."} || [string match "Running*" [get_property STATUS $r]]} {
      bd_fail "run $r is busy ([get_property STATUS $r]); wait for it to finish"
    }
  }

  # ---------------------------------------------------------------- files (same generated list as the release)
  set gen [file join $root scripts merged_bitstream_sources.tcl]
  if {![file isfile $gen]} { bd_fail "missing $gen" }
  source $gen
  set b    [dict get $::merged_bit merged_board]
  if {[dict get $b top] ne "pq_merged_board_top"} { bd_fail "combined top is [dict get $b top]" }
  set srcs [lmap s [dict get $b sources] {file join $root $s}]
  set mems [lmap m [dict get $b mem_init] {file join $root $m}]
  set ref  [file join $root synth merged pq_merged_board_bd_ref.v]
  set inc  [list [file join $root vectors] [file join $root sim_riscv include]]
  foreach f [concat $srcs $mems [list $ref]] { if {![file isfile $f]} { bd_fail "missing file $f" } }

  set xpr [file join [get_property DIRECTORY $P] NOC_PQATTEST.xpr]
  set bak "$xpr.bak_bd_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"
  file copy -force $xpr $bak
  puts "MERGED_BD: backup $bak"

  set act_src   [current_fileset -srcset]
  set act_synth [current_run -synthesis]
  set act_impl  [current_run -implementation]

  if {[llength [get_filesets -quiet $setn]] != 0} { bd_fail "source set $setn exists without the block design; remove it by hand first" }
  set fs [create_fileset -srcset $setn]
  add_files -norecurse -fileset $fs [concat $srcs [list $ref] $mems]
  foreach m $mems { set_property file_type {Memory Initialization Files} [get_files -of_objects $fs [file tail $m]] }
  set_property verilog_define [dict get $b defines] $fs
  set_property include_dirs $inc $fs
  set_property top pq_merged_board_bd_ref $fs
  update_compile_order -fileset $fs

  # ---------------------------------------------------------------- block design (created in dl_bd_src)
  # Vivado creates a block design in the source set of the ACTIVE synthesis run (a source set cannot be made current by
  # itself). Run synth_bd exists only to select dl_bd_src here; it is never launched, and the active runs are restored below.
  if {[llength [get_runs -quiet synth_bd]] == 0} {
    create_run synth_bd -flow [get_property FLOW [get_runs $act_synth]] -srcset $setn \
      -constrset [get_property CONSTRSET [get_runs $act_synth]] -part [get_property PART $P]
  }
  current_run -synthesis [get_runs synth_bd]
  if {[current_fileset -srcset] ne $setn} { bd_fail "could not select source set $setn (active: [current_fileset -srcset])" }
  create_bd_design $name
  set cell [create_bd_cell -type module -reference pq_merged_board_bd_ref u_soc]
  set want {CLK100MHZ {I 1} btn {I 3} sw {I 1} led {O 4} led0_r {O 1} led0_g {O 1} uart_rxd_out {O 1}}
  if {[llength [get_bd_pins -of_objects $cell]] != [dict size $want]} { bd_fail "u_soc pins: [get_bd_pins -of_objects $cell]" }
  dict for {p spec} $want {
    lassign $spec dir w
    set pin [get_bd_pins u_soc/$p]
    if {[llength $pin] != 1} { bd_fail "pin u_soc/$p not found" }
    if {[get_property DIR $pin] ne $dir} { bd_fail "pin u_soc/$p direction [get_property DIR $pin], expected $dir" }
    set l [get_property LEFT $pin]; set r [get_property RIGHT $pin]
    set pw [expr {$l eq "" ? 1 : abs($l - $r) + 1}]
    if {$pw != $w} { bd_fail "pin u_soc/$p width $pw, expected $w" }
  }
  create_bd_port -dir I -type clk -freq_hz 100000000 CLK100MHZ
  create_bd_port -dir I -from 2 -to 0 btn
  create_bd_port -dir I -from 0 -to 0 sw
  create_bd_port -dir O -from 3 -to 0 led
  create_bd_port -dir O led0_r
  create_bd_port -dir O led0_g
  create_bd_port -dir O uart_rxd_out
  dict for {p spec} $want { connect_bd_net [get_bd_ports $p] [get_bd_pins u_soc/$p] }
  foreach pin [get_bd_pins -of_objects $cell] {
    set n [get_bd_nets -of_objects $pin]
    if {[llength $n] != 1 || [llength [get_bd_ports -of_objects $n]] != 1} { bd_fail "pin $pin is not connected to exactly one port" }
  }
  regenerate_bd_layout
  validate_bd_design
  save_bd_design

  set bdf [get_files $name.bd]
  if {[llength [get_files -of_objects $fs $name.bd]] != 1} { bd_fail "$name.bd is not in source set $setn" }
  set_property synth_checkpoint_mode None $bdf
  generate_target all $bdf
  set wrap [make_wrapper -files $bdf -top]
  add_files -norecurse -fileset $fs $wrap
  set_property top ${name}_wrapper $fs
  update_compile_order -fileset $fs

  # ---------------------------------------------------------------- put the project state back, then verify it
  current_run -synthesis $act_synth
  current_run -implementation $act_impl
  if {[current_fileset -srcset] ne $act_src}        { bd_fail "active source set is [current_fileset -srcset], was $act_src" }
  if {[current_run -synthesis] ne $act_synth}       { bd_fail "active synthesis run changed" }
  if {[current_run -implementation] ne $act_impl}   { bd_fail "active implementation run changed" }
  foreach r [list $act_synth $act_impl] {
    set rs [get_property SRCSET [get_runs $r]]
    if {$rs eq $setn} { bd_fail "run $r now uses $setn" }
    puts "MERGED_BD: run $r source set $rs, status [get_property STATUS [get_runs $r]], needs_refresh [get_property NEEDS_REFRESH [get_runs $r]]"
  }
  puts "MERGED_BD DONE: block design $name in source set $setn (cell u_soc, top ${name}_wrapper of that set only)."
  puts "Active source set $act_src and runs $act_synth / $act_impl unchanged. Diagram: IP INTEGRATOR > Open Block Design."
}
pq_merged_bd
