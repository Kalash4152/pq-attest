##=============================================================================
## create_p7_vivado_project.tcl
##
## Builds a SEPARATE Vivado 2024.1 project for the P7 design (M-F1 rev 7, I-5
## state) from the live repository files, by reference (nothing is copied).
##
## Why a separate project:
##   NOC_PQATTEST.xpr (official, last committed 041a036) is the rev-5 project:
##   top noc_mesh_synth_top, NOC_PKG.sv from NOC_PQATTEST.srcs/sources_1/new.
##   The P7 design uses rtl/dual_lane/NOC_PKG.sv, which declares the SAME
##   package name (noc_pkg). Both cannot sit in one fileset, so the official
##   project is left untouched and this script creates vivado_p7/.
##
## Source list = exactly the 51 files of the registered P7 P&R job
##   reports/dual_lane_10_20261023_121951_d99f256c/p7_subsystem_pnr/job.tcl
## (same order), taken from the live tree instead of the run snapshot.
## On 1 Nov 2026, 50 of 51 live files hash-match that run; the exception is
## rtl/dual_lane/noc_p7_pkg.sv (commit de2f2cc, elaboration-only bound check).
##
## Usage (from the repo root, when NO other Vivado/XSim job is running):
##   vivado -mode batch -source scripts/create_p7_vivado_project.tcl
## Optional: add  -tclargs run  to also launch synthesis + implementation.
##
## This project is for viewing, debugging and GUI work. Registered evidence
## still comes only from scripts/dual_lane.py.
##=============================================================================

set ROOT [file normalize [file join [file dirname [info script]] ..]]
set PROJ_DIR [file join $ROOT vivado_p7]
set PROJ_NAME NOC_PQATTEST_P7
set PART xc7a100tcsg324-1
set TOP pq_noc_subsystem_p7

if {[file exists [file join $PROJ_DIR $PROJ_NAME.xpr]]} {
  puts "ERROR: $PROJ_DIR/$PROJ_NAME.xpr already exists. Delete vivado_p7/ yourself first; this script never overwrites."
  exit 1
}

## --- design sources: same list and order as the registered P7 P&R job ---
set S  NOC_PQATTEST.srcs/sources_1/new
set D  rtl/dual_lane
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

## --- P7 simulation benches (compile set only; see note at the end) ---
set T NOC_PQATTEST.srcs/sim_1/new
set SIM_SRCS [list \
  $T/tb_pq_full_chain.sv $T/tb_n2p7_rtt.sv $T/tb_noc_n81_p7.sv $T/tb_ni_n81_p7.sv $T/tb_noc_hop_probes_p7.sv \
  $T/tb_noc_perf_p7.sv $T/tb_p7_c4.sv $T/tb_p7_gate_data.sv $T/tb_p7_ingress.sv $T/tb_p7_refuse_grant.sv \
  $T/tb_sys_f234_p7.sv $T/tb_l2p7_equiv.sv ]

set XDC scripts/d4_crypto_ooc.xdc

## --- check every file exists before creating anything ---
set missing 0
foreach f [concat $DESIGN_SRCS $SIM_SRCS [list $XDC]] {
  if {![file exists [file join $ROOT $f]]} { puts "MISSING: $f"; incr missing }
}
if {$missing} { puts "ERROR: $missing file(s) missing; nothing created."; exit 1 }

create_project $PROJ_NAME $PROJ_DIR -part $PART
set_property target_language Verilog [current_project]

## design (by reference: -norecurse, no import/copy)
add_files -fileset sources_1 -norecurse [lmap f $DESIGN_SRCS {file join $ROOT $f}]
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sources_1]]
set_property top $TOP [get_filesets sources_1]
set_property verilog_define {PQ_MAC_ON} [get_filesets sources_1]

## constraints: the same OOC XDC as the registered job (20 ns, 5 ns I/O budgets)
add_files -fileset constrs_1 -norecurse [file join $ROOT $XDC]

## simulation
add_files -fileset sim_1 -norecurse [lmap f $SIM_SRCS {file join $ROOT $f}]
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] -filter {FILE_TYPE == Verilog || FILE_TYPE == SystemVerilog}]
set_property verilog_define {PQ_MAC_ON} [get_filesets sim_1]
set_property top tb_pq_full_chain [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

## synthesis: same options as the registered job
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]

## implementation: directive set S1-PNR-DIR (DECISION_REGISTER, 2026-10-23)
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

puts "INFO: design files : [llength [get_files -of_objects [get_filesets sources_1]]]"
puts "INFO: sim files    : [llength [get_files -of_objects [get_filesets sim_1]]]"
puts "INFO: top          : [get_property top [get_filesets sources_1]]"
puts "INFO: project      : $PROJ_DIR/$PROJ_NAME.xpr"

if {[lsearch -exact $argv run] >= 0} {
  launch_runs impl_1 -jobs 2
  wait_on_run impl_1
  open_run impl_1
  report_utilization -file [file join $PROJ_DIR util_routed.rpt]
  report_timing_summary -file [file join $PROJ_DIR timing_routed.rpt]
  puts "INFO: implementation done; reports in vivado_p7/. This is NOT registered evidence."
}

## NOTE on simulation: the sim fileset compiles all P7 benches with PQ_MAC_ON.
## Individual registered jobs may need extra defines, generics or plusargs
## (see scripts/dual_lane_jobs.json). To reproduce one job exactly in the GUI,
## use scripts/make_vivado_sim_project.py (it built vivado_sim/n2p7_rtt).
close_project
