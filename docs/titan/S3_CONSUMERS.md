# S3 consumer audit — memory response control[9:1]

Scope: secure B0 source lists at Stage 1, including the I-9 NI, L2 pair and merged RISC-V core; the simulation-only S2 observer; active firmware sources and RISC-V fault/status exposure. NI, front end, bridge and firmware were traced through full-width wiring before classifying actual bit readers.

| Consumer or producer | Evidence | Current behavior for memory response [9:1] |
|---|---|---|
| NoC head type overlays | rtl/dual_lane/NOC_PKG.sv:232–243, 371–378 | Packed as unused in B0. [10] is ERR, [0] is the transaction tag. |
| Mesh, ingress parser/quarantine | rtl/dual_lane/noc_ingress_parser.sv:35–54; rtl/dual_lane/noc_ingress_quarantine.sv packet path | Transport / structural validation; no use of [9:1] to interpret a memory response. |
| NI response slot match and delivery | rtl/dual_lane/noc_network_interface_p7_i9.sv:889, 891–920, 1043, 1404, 1428 | Matches tag, source and type. Passes full control onward; [9:1] has no slot-matching role. |
| L2 wrapper and pair | rtl/dual_lane/noc_l2_auth_p7_i9.sv:308–317; rtl/dual_lane/noc_l2_p7_pair_i9.sv:48–58 | Passes the memory response control. Its authenticated attestation control packets are a separate message class. |
| Tile-2 front end | rtl/dual_lane/pq_noc_subsystem_p7_i9.sv:313–335 | Produces zero [9:1] for B0 responses. Request byte-strobe use of [10:7] applies only to write requests. |
| Gate and RoT verifier | rtl/dual_lane/noc_attest_gate.sv:38–46; rtl/dual_lane/pq_rot_verifier.sv:100–111 | High control bits have attestation-specific meaning. There is no memory response STATUS interpretation there. |
| CPU response export and wiring | rtl/dual_lane/pq_noc_subsystem_p7_i9.sv:369–378; rtl/dual_lane/merged/pq_soc_merged_core.sv:95,109,156; rtl/riscv/cpu_tile_noc.sv:142 | Forwards the full control bus without interpreting [9:1]. |
| TMEM bridge | rtl/riscv/tmem_app_bridge.sv:164–180 | Interprets ERR [10], the message, the source and abort/last. Current remote error kind is 3, timeout is 4. |
| Historical merged stub | rtl/dual_lane/merged/cpu_tile_noc_stub.sv:101–107 | Interprets ERR [10]. Outside the secure real-CPU B0 selection. |
| S2 checker and matched benchmark | rtl/dual_lane/titan/titan_mon_bind.sv:43–45; rtl/dual_lane/merged/tb_matched_memory_v10.sv | Checker reads tag [0]. Existing matched-memory data/latency observations do not consume [9:1]. |
| Firmware | sw/riscv/demo_fw_v3.S; sw/riscv/matched_memory_fw.S; sw/riscv/contention_fw.S; sw/riscv/status_regs.h:22–31 | Sees returned data, poison pattern, faults and status registers. No direct view of the raw NoC control field. |

## D5 downstream collision

The current bridge sideband design makes a new denial code visible once implemented. It also makes provisional bridge code 5 ambiguous in two common software interfaces:

1. Remote target error enters CPU tile via rtl/riscv/cpu_tile_noc.sv:110. On a faulting remote access, rtl/riscv/picorv32_adapter.sv:212–215 copies the supplied nonzero error into the poison result and common FAULT_CODE.
2. A local unmapped/refused access independently supplies FAULT_LOCAL=5 at rtl/riscv/picorv32_adapter.sv:53 and :230–233. sw/riscv/status_regs.h:27 names that code FAULT_LOCAL_UNMAPPED.
3. rtl/riscv/tile_status.sv:82,116 exposes common FAULT_CODE. rtl/riscv/tile_top.sv:169 separately exposes the bridge-only value in NI status register 0. A common-code/poison-only consumer cannot tell those two causes apart.

This affects the proposed S9 software-visible outcome interface. It does not invalidate the accepted B0 evidence or select a different encoding. Require a D5 decision and both signatures before dependent RTL.
