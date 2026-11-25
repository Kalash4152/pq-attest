# TITAN planned stop after Stage 5R

21 November 2026 IST. I-T4R and I-T5R passed. S6 and S8 await the 6 December G0 decision. Arnav's revision 11 signature remains pending. His r2 G0 scratch benches stopped at elaboration on undeclared load_row(0), and no G0 verdict is available. See S5R.md and ../G0_BENCH_FEEDBACK.md.

The S3 and S0 entries below are historical. Kalash resolved D5 with denial code 6 and authorized D10 requalification through S5R. The first S5 failure stays recorded in S5.md.

HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

---

# TITAN planned stop at the Stage 3 signature gate

21 November 2026 IST. S0, S1 and S2 are accepted. The S3 standalone package passed; authorization for dependent RTL is pending.

**D5:** The provisional bridge DENIED value 5 aliases the live adapter's local unmapped/refused value 5. Common STATUS_FAULT_CODE and poison output are ambiguous (rtl/riscv/picorv32_adapter.sv:53,212–215,230–233; sw/riscv/status_regs.h:27). The separate NI status register is bridge-specific. No production semantic change has been made.

**Next:** Kalash and Arnav decide the CPU-visible denial mapping and sign the updated draft before S4. See S3.md and ../S3_CONSUMERS.md.

HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

---

The Stage 0 stop below is historical. The authorized same-module-name file swap resolved it, with eight fresh jobs and four matched pairs recorded at e4c096d3.

# TITAN Stage 0 hard stop

21 November 2026 IST. First run dual_lane_10_20261120_205551_19008444. Stage 0 source commit 38c0dd0f, evidence commit b90fe06a.

- Four B0 jobs passed fresh, with frozen counts 6, 6, 8 and 56. Four T1 jobs were INVALID at elaboration. No T1 simulation completed, so no B0/T1 equivalence result exists.
- All four T1 job Tcl inputs list all four generated source files and TITAN_T1. The Vivado-exported XSim compile lists omit all four generated files. The later xvlog command has the macro enabled and xelab reports VRFC 10-2063, missing pq_noc_subsystem_p7_t1 in u_p7.
- The exporter calls update_compile_order before scripts-only export without setting the job's defines on sim_1. That explains why it resolves the B0 branch and drops the T1 sources before the later xvlog invocation. The proposed fix is to apply the existing job defines before Vivado computes simulation compile order, then prove that all four T1 sources reach the actual compile list and that the B0 export remains intact. This proposal has not been implemented or tested.
- Evidence lives under S0_evidence/dual_lane_10_20261120_205551_19008444. The exact exported project lists and compile commands for the failure are archived under S0_export_diagnosis.

## Branch provenance before Stage 1

The replay's Git commit is local to the replay. Its 15 Stage 0 input overlays are recorded by hash in S0_replay_inputs.json. The 48 protected input hashes match the frozen ledger in the replay.

Direct worktree audit yielded 17 byte mismatches consisting only of line endings and 3 absent protected files: pq_attest_protocol_pkg.sv, pq_attest_request.sv and pq_attest_response.sv. Changing autocrlf alone cannot supply the absent files. It also cannot guarantee each protected file has the exact expected original bytes. Before Stage 1, verify all 48 against the protected ledger and capture branch commit and raw-byte fingerprints together. Keep the live protected sources read-only. No worktree pruning.

## Decision needed

The owner requested a hard stop if any T1 job fails. Approve an exporter-only correction and a fresh Stage 0 rerun on the same assertion counts. Preserve the first failed record, then verify four paired results and their observed timings before starting Stage 1.

HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.
