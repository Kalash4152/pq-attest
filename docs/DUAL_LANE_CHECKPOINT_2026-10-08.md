# Dual-lane checkpoint — 2026-10-08

Work stopped at Kalash's request. This is a saved working-tree checkpoint, not a Git commit or a completed release. The approved offline profile is recorded in `docs/decisions/dual_lane_config.json`. The original production RTL, existing local edits, deleted documents and historical evidence are preserved. New secure variants use explicit isolated source lists under `rtl/dual_lane/`.

## Implemented and saved

- Documented the accepted seven-word challenge, measurement/tag response, trusted demo provisioning, L2 counter/boot epoch and drain/retry policy before implementing their variants.
- Added independent Python attestation, full-chain and L2 packet oracles with immutable JSON/SystemVerilog vectors.
- Implemented a demo subsystem with the actual mesh and NIs, full-packet L2 authentication before NI delivery, replay checks, attestation endpoint, RoT verifier and authorization/revocation gates.
- Added isolated XSim export, process supervision, source/evidence identity checks, guarded installation and explicit package dependency reporting. The launcher exists at `scripts/run_dual_lane_10.tcl`.
- Prepared performance and dedicated L2 benches, performance reporting and OOC scripts. Preparation alone is not execution evidence.
- Fixed package reporting so an individual full-chain PASS cannot accept PQ-5 while upstream packages remain unaccepted. Added a regression check for that condition.
- Refreshed the guarded payload to include the unfinished L2 bench and this checkpoint. No new FPGA run was started during wrap-up.

## Evidence at the checkpoint

| Item | Result and limit |
|---|---|
| Fresh full-chain XSim | `PASS_FRESH`, 16 checks / 0 errors, `DEMO=1`, 20 ns simulation clock. Challenge/response and independent response comparison; grant, authorized memory write and NI slot retirement; spoof containment, replay rejection, revocation, substituted measurement rejection, retry, reset and old-boot replay rejection. |
| Latest evidence directory | `reports/dual_lane_10_20261008_150300_5231be0b/`. Read `summary.md`, `status.json`, `job_matrix.csv` and `full_chain/result.json`. |
| N-8.1 historical evidence | Ten matching jobs are `PASS_REUSED`. The eleventh (`n81_nitb`) is INVALID because the live `ni_tb.sv` differs from the archived build. Its local content was preserved. |
| N-6 historical mutation campaign | All five reuse records remain INVALID because `wp0_common.tcl` differs from the archived identity. The old campaign and logs remain intact. This is not a demonstrated RTL failure. |
| Independent Python oracle | Stage 5/6/7 compatibility vectors (6/6/8), width/invalid-input checks and eight complete 776-bit compositions passed. Full-chain and L2 vector generation/checking have separate Python results. These do not qualify unexecuted RTL benches. |
| Earlier golden XSim | Raw 95/0 functional result exists in run `144615_bf288411`, but the gate is INVALID because the approved configuration changed during that run. It is not accepted evidence. Run `144410_81040756` also remains preserved and invalid. |
| Wrap-up software checks | See `automation/dual_lane_payload/checkpoint.json` and `checkpoint_checks/` for actual test counts, exit codes, preflight and protected-source comparison. These checks do not prove RTL correctness. |
| Overall result | Latest run remains FAIL; NOC packages accepted 0/5, PQ packages accepted 0/5. PQ-5 is BLOCKED by prerequisites despite its individual demo test passing. |

## Remaining work and future execution order

1. **NOC-1 baseline reconciliation:** preserve the current NI bench under a recovery copy, then reconcile its intended top/source list against the archived version; run only evidence that cannot be reused. Prepare fresh N-6 controls/mutations under the current helper and execute the five-job D7 session, NI OOC and qualified mesh build. Do not discard local edits or blindly restore deleted documents. The legacy standalone `scripts/d7_regression.tcl` remains unchanged; the new scheduler has its own isolated D7 jobs.
2. **PQ-1 oracle and interface closure:** publish the consolidated M-F1 interface revision; inspect and compare any recovered original reference in `Pq_Attest_final.zip`; run the 95-check golden bench, seven targeted mutants and final control on one fixed identity; qualify compatibility under the new packet format.
3. **NOC-2 and PQ-2 in parallel:** compile and validate the prepared performance bench, then execute all 56 points with accounting, drain/liveness checks and effective controls. Independently complete endpoint unit/backpressure/reset/error tests and its four targeted mutations. No performance curves are accepted yet.
4. **PQ-3 OOC feasibility:** execute crypto/controller/endpoint synthesis, check constraints and untrimmed child engines, and record resources, setup/hold timing, DRC and methodology diagnostics. OOC cannot establish integrated 50 MHz timing.
5. **NOC-3 and NOC-4 enforcement closure:** register and compile the unfinished dedicated L2 bench; compare its wire packets with the Python oracle; complete effective MAC, sequence, epoch and identity controls. Integrate the currently unconnected fault/status block and test trusted issuer, clear, reset, failure, timeout and revocation behavior. Audit reset/epoch persistence, receiver overload and truncated-packet recovery.
6. **PQ-4 / N-11 shared attack matrix:** execute each attack and an effective targeted bypass control through the complete NoC path. Review the placeholder `security_e1_e4` name against the actual handoff attack definitions before claiming historical coverage.
7. **PQ-5, then NOC-5 release:** rerun the complete offline chain after prerequisites are accepted; execute final reset/stress/compatibility regression; synthesize and route the entire mesh + NI + L2 + endpoint + verifier + gates at 20 ns. Report utilization and timing. A negative WNS/WHS, unconstrained path or implementation failure stays open. Produce the reproducible release only after the required gates close.

The existing launcher is the resume entrypoint in Vivado 2024.1:

```tcl
source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/run_dual_lane_10.tcl
```

It runs prepared jobs and reports incomplete gates; it does not implement the remaining work by itself. All six offline-profile choices are approved. Production key provisioning, persistent boot-epoch generation, hardware validation and SoC integration remain outside this checkpoint's claims.

## Recovery and preservation

`automation/dual_lane_payload/baseline_before.json` preserves intake hashes and Git state. `update_manifest.json` pins the saved payload. `checkpoint.json` records the final source comparison, saved files and evidence hashes. Preserve the three existing run directories, including failures; any source/config/tool changes require identity matching before reuse.

The installation rollback journal covers only files actually written by the installer. Development files already present when the installer ran are not rollback entries. An interrupted pending install must be resumed and inspected before rollback; direct rollback of a pending write is not qualified yet. The scheduler's interrupt/recovery path and comprehensive OOC adjudication also need further qualification before release.
