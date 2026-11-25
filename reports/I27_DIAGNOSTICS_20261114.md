# I-27 diagnostics review (partial; 14 Nov)

Baseline abc90d1d; run dual_lane_10_20261114_073825_0fc50ad4. Applies to completed jobs only.

- Vivado 12-13340: GCC auto-discovery warning. Compilation/elaboration actually completed and snapshots executed;
  this warning did not prevent those results. Retained in raw logs; no diagnostic suppression added.
- VRFC 10-3380, rtl/dual_lane/SHA3_256_xp.sv:70: ctrl_state declaration follows a simulation-only assertion.
  This is the existing D-12 portability issue explicitly deferred to ASIC start by the approved blueprint.
- VRFC 10-2649, rtl/riscv/tmem_app_bridge.sv:117: enum output assigned a conditional expression choosing
  MSG_MEM_WR_REQ/MSG_MEM_RD_REQ. Existing code, unchanged by revision 10; qualified relaxed compilation retained.
  Both selected values are valid message kinds. Existing FPGA flow accepts it; strict-tool portability remains a
  documented adaptation concern, not a new hardware modification in this scope.

No new warning-suppression options were introduced. Final synthesis/timing warning review is still pending.
