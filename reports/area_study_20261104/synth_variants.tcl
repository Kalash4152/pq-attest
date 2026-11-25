set out [file normalize [file dirname [info script]]]
set srcs [list "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/NOC_PKG.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/noc_p7_pkg.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/NOC_FIFO.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/NOC_CROSSBAR.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/NOC_XY_ROUTING.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/NOC_arbiter.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/allocator.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/noc_credit_counter.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/NOC_DATAPTAH.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/noc_router.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/noc_mesh_3x2.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/noc_addr_decoder.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/pq_keccak_pkg.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/SHA3_PKG.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/kmac_pkg.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/pq_kdf_pkg.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/pq_measurement_pkg.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/pqattest_stg7_pkg.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/pq_keccak_theta.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/pq_keccak_rho.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/pq_keccak_pi.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/pq_keccak_chi.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/pq_keccak_iota.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/pq_keccak_round.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/pq_keccak_f1600.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/SHA3_PAD.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/SHA3_ABSORB.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/SHA3_256.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/kmac_encode.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/kmac_absorb.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/kmac_128.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/pq_kdf.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/pq_measurement.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new/pqattest_stg7.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/SHA3_256_xp.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/kmac_128_xp.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/pq_kmac_share_xp.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/pq_measurement_xp.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/pq_attest_protocol_s3.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/pq_kmac_share.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/pq_kdf_xk.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/pq_attestation_tag_xk.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/noc_network_interface_p7.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/l2_arbiter.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/l2_kmac_engine.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/noc_l2_auth_p7.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/noc_l2_p7_pair.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/noc_ingress_quarantine.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/noc_ingress_parser.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/pq_attest_endpoint.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/noc_attest_gate.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/noc_fault_status.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/pq_rot_verifier.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/rst_bridge.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/rtl/dual_lane/pq_noc_subsystem_p7.sv" "C:/vivado_verilog_proj/NOC_PQATTEST/vivado_sim/_area/pq_p7_pruned.sv"]
proc lut {} { set us [report_utilization -return_string]; set l NA; set f NA; set m NA
  regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)} $us -> l; regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)} $us -> f
  regexp {\|\s*LUT as Distributed RAM\s*\|\s*([0-9]+)} $us -> m; return "LUT=$l FF=$f LUTRAM=$m" }
create_project -in_memory -part xc7a100tcsg324-1
read_verilog -sv $srcs
read_xdc C:/vivado_verilog_proj/NOC_PQATTEST/scripts/d4_crypto_ooc.xdc
synth_design -top pq_noc_subsystem_p7 -part xc7a100tcsg324-1 -mode out_of_context -flatten_hierarchy none -verilog_define PQ_MAC_ON 
set a [lut]
opt_design -directive Explore
set b [lut]
report_utilization -hierarchical -hierarchical_depth 6 -file [file join $out S0_util_hier_opt.rpt]
set f [open [file join $out area_results.txt] a]; puts $f "S0 top=pq_noc_subsystem_p7 flatten=none default | synth $a | opt $b"; close $f
puts "AREA S0 synth $a opt $b"
close_project
create_project -in_memory -part xc7a100tcsg324-1
read_verilog -sv $srcs
read_xdc C:/vivado_verilog_proj/NOC_PQATTEST/scripts/d4_crypto_ooc.xdc
synth_design -top pq_noc_subsystem_p7 -part xc7a100tcsg324-1 -mode out_of_context -flatten_hierarchy rebuilt -verilog_define PQ_MAC_ON 
set a [lut]
opt_design -directive Explore
set b [lut]
report_utilization -hierarchical -hierarchical_depth 6 -file [file join $out S1_util_hier_opt.rpt]
set f [open [file join $out area_results.txt] a]; puts $f "S1 top=pq_noc_subsystem_p7 flatten=rebuilt default | synth $a | opt $b"; close $f
puts "AREA S1 synth $a opt $b"
close_project
create_project -in_memory -part xc7a100tcsg324-1
read_verilog -sv $srcs
read_xdc C:/vivado_verilog_proj/NOC_PQATTEST/scripts/d4_crypto_ooc.xdc
synth_design -top pq_noc_subsystem_p7 -part xc7a100tcsg324-1 -mode out_of_context -flatten_hierarchy none -verilog_define PQ_MAC_ON -directive AreaOptimized_high
set a [lut]
opt_design -directive Explore
set b [lut]
report_utilization -hierarchical -hierarchical_depth 6 -file [file join $out S2_util_hier_opt.rpt]
set f [open [file join $out area_results.txt] a]; puts $f "S2 top=pq_noc_subsystem_p7 flatten=none -directive AreaOptimized_high | synth $a | opt $b"; close $f
puts "AREA S2 synth $a opt $b"
close_project
create_project -in_memory -part xc7a100tcsg324-1
read_verilog -sv $srcs
read_xdc C:/vivado_verilog_proj/NOC_PQATTEST/scripts/d4_crypto_ooc.xdc
synth_design -top pq_noc_subsystem_p7 -part xc7a100tcsg324-1 -mode out_of_context -flatten_hierarchy rebuilt -verilog_define PQ_MAC_ON -directive AreaOptimized_high
set a [lut]
opt_design -directive Explore
set b [lut]
report_utilization -hierarchical -hierarchical_depth 6 -file [file join $out S3_util_hier_opt.rpt]
set f [open [file join $out area_results.txt] a]; puts $f "S3 top=pq_noc_subsystem_p7 flatten=rebuilt -directive AreaOptimized_high | synth $a | opt $b"; close $f
puts "AREA S3 synth $a opt $b"
close_project
create_project -in_memory -part xc7a100tcsg324-1
read_verilog -sv $srcs
read_xdc C:/vivado_verilog_proj/NOC_PQATTEST/scripts/d4_crypto_ooc.xdc
synth_design -top pq_p7_pruned -part xc7a100tcsg324-1 -mode out_of_context -flatten_hierarchy rebuilt -verilog_define PQ_MAC_ON 
set a [lut]
opt_design -directive Explore
set b [lut]
report_utilization -hierarchical -hierarchical_depth 6 -file [file join $out S4_util_hier_opt.rpt]
set f [open [file join $out area_results.txt] a]; puts $f "S4 top=pq_p7_pruned flatten=rebuilt default | synth $a | opt $b"; close $f
puts "AREA S4 synth $a opt $b"
close_project
