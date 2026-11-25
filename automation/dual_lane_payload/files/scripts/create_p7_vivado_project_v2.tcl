##=============================================================================
## create_p7_vivado_project_v2.tcl
##
## Builds a SEPARATE Vivado 2024.1 project vivado_p7/NOC_PQATTEST_P7.xpr for the P7 design (I-5 state) from the live
## repository files, by reference (nothing copied). NOC_PQATTEST.xpr is not touched.
##
## Design = the 51 files of the registered P7 P&R job p7_subsystem_pnr (scripts/dual_lane_jobs.json), same order,
## top pq_noc_subsystem_p7, PQ_MAC_ON, constraints scripts/d4_crypto_ooc.xdc, synth -mode out_of_context
## -flatten_hierarchy none, implementation directives S1-PNR-DIR.
##
## Simulation = the six registered P7 benches whose source list is exactly that design plus one testbench
## (n2p7_rtt, p7_gate_data, p7_refuse_grant, p7_c4, p7_ingress, f234_p7), with their include dirs and
## the .mem-free base configurations. Switch bench with:  p7_sim <top>   (default top tb_n2p7_rtt)
## Other benches (variants, older revisions): use scripts/update_NOC_PQATTEST_xpr.tcl in NOC_PQATTEST.xpr.
##
## Changes from create_p7_vivado_project.tcl (Claude chat):
##  - works when pasted or sourced in the GUI Tcl console (fixed repo path; [info script] is empty when pasted)
##  - leaves the project OPEN (the original ended with close_project, so the GUI showed nothing)
##  - errors stop the script with a message instead of `exit 1` (which quits Vivado)
##  - sim set limited to benches that compile against this design (the original added tb_pq_full_chain and
##    tb_l2p7_equiv, which need rev-5 files not in this project, and set no include dirs or run time)
##
## Use: Vivado GUI, Tcl console:  source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/create_p7_vivado_project_v2.tcl
## Not evidence: registered results come only from scripts/dual_lane.py.
##=============================================================================

set ROOT C:/vivado_verilog_proj/NOC_PQATTEST
if {![file isdirectory $ROOT/rtl/dual_lane]} { error "Repository not found at $ROOT" }
set PROJ_DIR $ROOT/vivado_p7
set PROJ_NAME NOC_PQATTEST_P7
set PART xc7a100tcsg324-1
set TOP pq_noc_subsystem_p7

if {[file exists $PROJ_DIR/$PROJ_NAME.xpr]} {
  puts "INFO: $PROJ_DIR/$PROJ_NAME.xpr already exists; opening it instead of rebuilding."
  puts "INFO: to rebuild, close it, delete the vivado_p7 folder yourself, and source this script again."
  if {[current_project -quiet] ne ""} { close_project }
  open_project $PROJ_DIR/$PROJ_NAME.xpr
  return
}

set S NOC_PQATTEST.srcs/sources_1/new
set D rtl/dual_lane
set DESIGN_SRCS [list \
  $D/NOC_PKG.sv $D/noc_p7_pkg.sv \
  $S/NOC_FIFO.sv $S/NOC_CROSSBAR.sv $S/NOC_XY_ROUTING.sv $S/NOC_arbiter.sv $S/allocator.sv \
  $S/noc_credit_counter.sv $S/NOC_DATAPTAH.sv $S/noc_router.sv $S/noc_mesh_3x2.sv $S/noc_addr_decoder.sv \
  $S/pq_keccak_pkg.sv $S/SHA3_PKG.sv $S/kmac_pkg.sv $S/pq_kdf_pkg.sv $S/pq_measurement_pkg.sv $S/pqattest_stg7_pkg.sv \
  $S/pq_keccak_theta.sv $S/pq_keccak_rho.sv $S/pq_keccak_pi.sv $S/pq_keccak_chi.sv $D/pq_keccak_iota.sv \
  $S/pq_keccak_round.sv $S/pq_keccak_f1600.sv $D/SHA3_PAD.sv $S/SHA3_ABSORB.sv $S/SHA3_256.sv \
  $S/kmac_encode.sv $S/kmac_absorb.sv $S/kmac_128.sv $S/pq_kdf.sv $D/pq_measurement.sv $S/pqattest_stg7.sv \
  $D/pq_attest_protocol.sv $D/pq_kmac_share.sv $D/pq_kdf_xk.sv $D/pq_attestation_tag_xk.sv \
  $D/noc_network_interface_p7.sv $D/l2_arbiter.sv $D/l2_kmac_engine.sv $D/noc_l2_auth_p7.sv $D/noc_l2_p7_pair.sv \
  $D/noc_ingress_quarantine.sv $D/noc_ingress_parser.sv $D/pq_attest_endpoint.sv $D/noc_attest_gate.sv \
  $D/noc_fault_status.sv $D/pq_rot_verifier.sv $D/rst_bridge.sv $D/pq_noc_subsystem_p7.sv ]
set T NOC_PQATTEST.srcs/sim_1/new
set SIM_SRCS [list $T/tb_n2p7_rtt.sv $T/tb_p7_gate_data.sv $T/tb_p7_refuse_grant.sv $T/tb_p7_c4.sv \
  $T/tb_p7_ingress.sv $T/tb_sys_f234_p7.sv]
set SIM_INCS [list vectors sim/dual_lane/f234]
set XDC scripts/d4_crypto_ooc.xdc

set missing {}
foreach f [concat $DESIGN_SRCS $SIM_SRCS $SIM_INCS [list $XDC]] { if {![file exists $ROOT/$f]} { lappend missing $f } }
if {[llength $missing]} { error "Missing in $ROOT: $missing (nothing created)" }

if {[current_project -quiet] ne ""} { puts "INFO: closing [current_project] (saved automatically)"; close_project }
create_project $PROJ_NAME $PROJ_DIR -part $PART
set_property target_language Verilog [current_project]

add_files -fileset sources_1 -norecurse [lmap f $DESIGN_SRCS {file join $ROOT $f}]
set_property top $TOP [get_filesets sources_1]
set_property verilog_define {PQ_MAC_ON} [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse $ROOT/$XDC

set sim [get_filesets sim_1]
add_files -fileset sim_1 -norecurse [lmap f $SIM_SRCS {file join $ROOT $f}]
set_property verilog_define {PQ_MAC_ON} $sim
set_property include_dirs [lmap f $SIM_INCS {file join $ROOT $f}] $sim
set_property include_dirs [lmap f $SIM_INCS {file join $ROOT $f}] [get_filesets sources_1]
set_property top tb_n2p7_rtt $sim
set_property top_lib xil_defaultlib $sim
set_property -name {xsim.simulate.runtime} -value {70ms} -objects $sim
set_property -name {xsim.simulate.log_all_signals} -value {false} -objects $sim

set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]
set impl [get_runs impl_1]
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Explore $impl
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraTimingOpt $impl
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $impl
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true $impl
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

proc p7_sim {top} {
  set_property top $top [get_filesets sim_1]
  update_compile_order -fileset sim_1
  launch_simulation -simset [get_filesets sim_1] -mode behavioral
}

puts "INFO: project  : $PROJ_DIR/$PROJ_NAME.xpr (open)"
puts "INFO: design   : [llength [get_files -of_objects [get_filesets sources_1]]] files, top [get_property top [get_filesets sources_1]]"
puts "INFO: sim      : [llength [get_files -of_objects $sim]] files, top [get_property top $sim], run 70ms"
puts "INFO: simulate : p7_sim tb_n2p7_rtt | tb_p7_gate_data | tb_p7_refuse_grant | tb_p7_c4 | tb_p7_ingress | tb_sys_f234"
puts "INFO: synth/impl: Flow Navigator > Run Implementation (run it with no other Vivado/XSim open). Not evidence."
