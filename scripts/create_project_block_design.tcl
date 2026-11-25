# create_project_block_design.tcl - IP Integrator block design of the combined SoC (NoC + PQ-Attest + two RISC-V tiles).
# Claude, 2026-11-12, for Kalash. Vivado 2024.1, xc7a100tcsg324-1.
#
# Creates a NEW, separate project (the main NOC_PQATTEST project is not opened or changed) holding block design
# "pq_merged_bd": ONE module-reference cell "u_soc" (the unmodified board top pq_merged_board_top through the plain-Verilog
# shell synth/merged/pq_merged_board_bd_ref.v) and the seven board ports. No Xilinx IP is added: the design has none
# (the MMCM and the two BUFGs are primitives inside the board top; reset, debounce and all buses are plain RTL).
#
# Run (no project open):   source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/create_project_block_design.tcl
#   or batch:              vivado -mode batch -source <this file>
# Options (environment variables, all optional):
#   BD_PROJ_DIR   project directory to create   (default: <repo>/../NOC_PQATTEST_bd; must not exist)
#   BD_SKIP_ELAB  1 = skip the RTL elaboration check at the end
# This project is for the block diagram and structural checks. The gated release bitstream flow stays
# final_project_update.tcl / merged_gui_runs.tcl (it synthesises the mesh separately; this project does not).

proc bd_fail {msg} { error "CREATE_BD FAILED: $msg" }

# Everything runs inside one procedure so that no global Tcl variable of this script exists while Vivado loads IP Integrator.
proc pq_create_bd {} {
# ------------------------------------------------------------------ environment
set bd_ver [version -short]
if {![string match "2024.1*" $bd_ver]} { bd_fail "Vivado $bd_ver; this script was verified with 2024.1 only" }
if {[llength [get_projects -quiet]] != 0} { bd_fail "a project is open; close it (File > Close Project) or use a fresh Vivado" }
set bd_root [file dirname [file dirname [file normalize [info script]]]]
set bd_part xc7a100tcsg324-1
if {[llength [get_parts -quiet $bd_part]] != 1} { bd_fail "part $bd_part is not installed" }
set bd_dir [file normalize [file join $bd_root .. NOC_PQATTEST_bd]]
if {[info exists ::env(BD_PROJ_DIR)] && $::env(BD_PROJ_DIR) ne ""} { set bd_dir [file normalize $::env(BD_PROJ_DIR)] }
if {[file exists $bd_dir]} { bd_fail "$bd_dir already exists; delete it or set BD_PROJ_DIR to a new directory" }

# ------------------------------------------------------------------ source list (same generated list as the release)
set bd_gen [file join $bd_root scripts merged_bitstream_sources.tcl]
if {![file isfile $bd_gen]} { bd_fail "missing $bd_gen (python scripts/make_merged_sources.py)" }
source $bd_gen
set bd_b    [dict get $::merged_bit merged_board]
set bd_top  [dict get $bd_b top]
if {$bd_top ne "pq_merged_board_top"} { bd_fail "combined top is $bd_top, expected pq_merged_board_top" }
set bd_srcs [lmap s [dict get $bd_b sources] {file join $bd_root $s}]
set bd_mems [lmap m [dict get $bd_b mem_init] {file join $bd_root $m}]
set bd_xdc  [file join $bd_root [dict get $bd_b xdc]]
set bd_ref  [file join $bd_root synth merged pq_merged_board_bd_ref.v]
set bd_inc  [list [file join $bd_root vectors] [file join $bd_root sim_riscv include]]
foreach f [concat $bd_srcs $bd_mems [list $bd_xdc $bd_ref]] { if {![file isfile $f]} { bd_fail "missing file $f" } }
foreach d $bd_inc { if {![file isdirectory $d]} { bd_fail "missing include directory $d" } }

# ------------------------------------------------------------------ project
create_project NOC_PQATTEST_bd $bd_dir -part $bd_part
set_property target_language Verilog [current_project]
add_files -norecurse -fileset sources_1 [concat $bd_srcs [list $bd_ref] $bd_mems]
# firmware images: Vivado does not know ".hex"; without this type $readmemh cannot find the file (Synth 8-4445)
foreach m $bd_mems { set_property file_type {Memory Initialization Files} [get_files $m] }
set_property verilog_define [dict get $bd_b defines] [get_filesets sources_1]
set_property include_dirs $bd_inc [get_filesets sources_1]
add_files -norecurse -fileset constrs_1 $bd_xdc
update_compile_order -fileset sources_1

# ------------------------------------------------------------------ block design
set bd_name pq_merged_bd
create_bd_design $bd_name
set bd_cell [create_bd_cell -type module -reference pq_merged_board_bd_ref u_soc]

# the cell must expose exactly the board top's ports (name, direction, width)
set bd_want {CLK100MHZ {I 1} btn {I 3} sw {I 1} led {O 4} led0_r {O 1} led0_g {O 1} uart_rxd_out {O 1}}
set bd_have [get_bd_pins -of_objects $bd_cell]
if {[llength $bd_have] != [expr {[dict size $bd_want]}]} {
  bd_fail "u_soc has [llength $bd_have] pins, expected [dict size $bd_want]: $bd_have"
}
dict for {p spec} $bd_want {
  lassign $spec dir w
  set pin [get_bd_pins u_soc/$p]
  if {[llength $pin] != 1} { bd_fail "pin u_soc/$p not found" }
  if {[get_property DIR $pin] ne $dir} { bd_fail "pin u_soc/$p direction [get_property DIR $pin], expected $dir" }
  set l [get_property LEFT $pin]; set r [get_property RIGHT $pin]
  set pw [expr {$l eq "" ? 1 : abs($l - $r) + 1}]
  if {$pw != $w} { bd_fail "pin u_soc/$p width $pw, expected $w" }
}

# external ports: same names as the board top, so synth/merged/pq_merged_board_arty.xdc applies unchanged
create_bd_port -dir I -type clk -freq_hz 100000000 CLK100MHZ
create_bd_port -dir I -from 2 -to 0 btn
create_bd_port -dir I -from 0 -to 0 sw
create_bd_port -dir O -from 3 -to 0 led
create_bd_port -dir O led0_r
create_bd_port -dir O led0_g
create_bd_port -dir O uart_rxd_out
dict for {p spec} $bd_want { connect_bd_net [get_bd_ports $p] [get_bd_pins u_soc/$p] }

# every pin of the cell must be on a net that reaches a port
foreach pin [get_bd_pins -of_objects $bd_cell] {
  set n [get_bd_nets -of_objects $pin]
  if {[llength $n] != 1 || [llength [get_bd_ports -of_objects $n]] != 1} { bd_fail "pin $pin is not connected to exactly one port" }
}

regenerate_bd_layout
validate_bd_design
save_bd_design

# ------------------------------------------------------------------ outputs, wrapper, top
set bd_file [get_files $bd_name.bd]
# one global synthesis of the whole design (not a separate out-of-context run for the cell)
set_property synth_checkpoint_mode None $bd_file
generate_target all $bd_file
set bd_wrap [make_wrapper -files $bd_file -top]
add_files -norecurse -fileset sources_1 $bd_wrap
update_compile_order -fileset sources_1
set_property top ${bd_name}_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1
if {[get_property top [get_filesets sources_1]] ne "${bd_name}_wrapper"} { bd_fail "top is not ${bd_name}_wrapper" }

# ------------------------------------------------------------------ elaboration check (no synthesis, no implementation)
if {[info exists ::env(BD_SKIP_ELAB)] && $::env(BD_SKIP_ELAB) eq "1"} {
  puts "CREATE_BD: elaboration check skipped (BD_SKIP_ELAB=1)"
} else {
  synth_design -rtl -rtl_skip_mlo -name rtl_1 -top ${bd_name}_wrapper -part $bd_part
  foreach {what filt want} {
    {board top}         {ORIG_REF_NAME == pq_merged_board_top || REF_NAME == pq_merged_board_top} 1
    {merged core}       {ORIG_REF_NAME == pq_soc_merged_core  || REF_NAME == pq_soc_merged_core}  1
    {CPU tiles}         {ORIG_REF_NAME == cpu_tile_noc        || REF_NAME == cpu_tile_noc}        2
    {NoC mesh}          {ORIG_REF_NAME == noc_mesh_3x2        || REF_NAME == noc_mesh_3x2}        1
    {MMCM}              {REF_NAME =~ MMCME2_*}                                                     1
    {BUFG}              {REF_NAME == BUFG}                                                         2
  } {
    set n [llength [get_cells -hierarchical -filter $filt]]
    if {$n != $want} { bd_fail "elaborated design has $n x $what, expected $want" }
    puts "CREATE_BD: elaborated $what = $n"
  }
  set bd_ports [lsort [get_property NAME [get_ports]]]
  set bd_exp   [lsort {CLK100MHZ btn[0] btn[1] btn[2] sw[0] led[0] led[1] led[2] led[3] led0_r led0_g uart_rxd_out}]
  if {$bd_ports ne $bd_exp} { bd_fail "top-level ports are $bd_ports, expected $bd_exp" }
  # clocks from the unchanged XDC: 100 MHz board clock, MMCM feedback, 50 MHz design clock; nothing else
  set bd_clk {}
  foreach c [get_clocks] { lappend bd_clk "[get_property NAME $c]=[get_property PERIOD $c]" }
  set bd_clk [lsort $bd_clk]
  if {$bd_clk ne [lsort {sys_clk_pin=10.000 clk_fb=10.000 clk50_mmcm=20.000}]} { bd_fail "clocks are $bd_clk" }
  puts "CREATE_BD: clocks $bd_clk"
  close_design
}

puts "CREATE_BD DONE: project $bd_dir, block design $bd_name (cell u_soc), top ${bd_name}_wrapper."
puts "Open the diagram: Flow Navigator > IP INTEGRATOR > Open Block Design. Full hierarchy: RTL ANALYSIS > Open Elaborated Design."
}
pq_create_bd
