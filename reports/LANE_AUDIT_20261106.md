# NoC + PQ-Attest lane audit against the original plan, 2026-11-06

Plan audited: `docs/CODEX_INSTRUCTIONS_R4_FINAL_2026-10-08.md` (five NoC + five PQ steps, increments I-1 to I-8), plus
Lane 1 of `docs/proposals/PLAN_NEXT10_ALL_LANES_20261030.md`. Evidence = the gate reports cited per row.
Status: HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

## Verdict

**All 10 packages of the original plan are accepted (NOC 5/5, PQ 5/5), and every Lane-1 step of the next-10 plan is
done or handed over, except step 10 (merge), which waits on the RISC-V package.** Four small items remain (section 3); none
is a build.

Note on the harness summary line `NOC_PACKAGES_ACCEPTED=0/5 / PQ_PACKAGES_ACCEPTED=0/5 / DUAL_LANE_STATUS=BLOCKED`
printed by every run: the scheduler judges packages per run, and an increment run marks every other package's jobs
BLOCKED, so no single run can show 5/5. Acceptance is recorded per package in the gate reports below (the same convention
is stated in reports/I3_REPORT_20261020.md, I4_REPORT_20261020.md and I8_GATE_20261103.md).

## 1. The ten packages

| Package | Plan content | Accepted in | Evidence |
|---|---|---|---|
| NOC-1 | K-4 files, duplicate-name preflight + self-test, n81_nitb 161/0, N-6 mutation, D7 five jobs, NI OOC / mesh reuse, tb6_1 cast, STATUS / STAGE_MAP / register | I-1 (24/24) | reports/I1_COMPLETION_20261009.md; tb6_1 L46 cast diagnosed and recorded as debt (no effect on exercised addresses): docs/BASELINE_CURRENT.md:17 |
| PQ-1 | V1-V10 (teammate ZIP pinned, KATs, adapters, profile split, 95/0 bit-exact, policy layer), 7 controller mutants, M-F1 rev 6, post_format_compat | I-2 (36/36) | reports/I2_REPORT_20261019.md (`PYTHON_RTL_COMPATIBILITY=MATCH`, `POLICY_LAYER: PASS`) |
| NOC-2 | 56-point performance plan, controls, N-7.5 runs, perf report | I-3 (22/22) | reports/I3_REPORT_20261020.md; Verilator cross-check **BLOCKED (tool not installed)**, as the plan required it to be reported |
| PQ-2 | endpoint qualification, behaviours, unit + system bench, 4 mutants | I-3 | reports/I3_REPORT_20261020.md (C-1 / C-2 implemented in I-6) |
| PQ-3 | five crypto tops OOC at 20 ns, latency | I-4 (33/33) | reports/I4_REPORT_20261020.md |
| NOC-3 | M-F1 rev 6 / rev 7, L2 authentication, attacks, bypass controls, latency / area vs NOC-2 | I-5 | reports/I5_GATE_20261029.md |
| NOC-4 | fault status connected, gate integrated, three mutants | I-6 (24/24) | reports/I6_GATE_20261103.md |
| PQ-4 | SEC-1 to SEC-4 + extra attacks on the real modules | I-7 (30/30, 8 controls killed) | reports/I7_GATE_20261103.md |
| PQ-5 | offline full chain, non-demo, teammate verifier + policy layer | I-7 (21/21) | reports/I7_GATE_20261103.md |
| NOC-5 | N-11, N-12 (73/73 one identity), N-13 secure + insecure at 20 ns, release manifest | I-8 (76/76) | reports/I8_GATE_20261103.md, releases/DUAL_LANE_10_20261103/ |

Beyond the plan (also done): S1 / S3 / S4 area and timing packages (S4: N-13 secure 32,708 LUT, WNS +0.275), release
bitstreams (36/36 project sims, 3 bitstreams, timing met), I-9 integration (60/60), I-10 D2 64-byte K-3 (6/6), E4 suite
vendored (224 / 15), merge-prep skeleton (reports/MERGE_PREP_20261106.md).

## 2. Lane 1 of the next-10 plan (2026-10-30)

| Step | Status |
|---|---|
| 1-3 I-6 spec, RTL, gate | DONE (I-6) |
| 4 Integration contract | DONE (M-F1 rev 8, signed 2026-11-05) |
| 5 TMEM <-> NI bridge | **Handed over**: D3 revised 2026-11-01, the bridge `tmem_app_bridge` is the RISC-V lane's (contract sec. 2) |
| 6-7 I-7 PQ-4, PQ-5 | DONE |
| 8-9 I-8 N-11 / N-12, N-13 | DONE |
| 10 Integration and merge | **Waiting on the RISC-V package** (skeleton ready, 29,420 LUT / WNS +0.337 with stub CPUs) |

## 3. Remaining items (none is a build)

| # | Item | Plan reference | What is left | Who |
|---|---|---|---|---|
| R1 | Zero-byte `pq_attest_request.sv` / `pq_attest_response.sv` still on disk (untracked); the plan says delete them and record it in the register. `pq_attest_protocol_pkg.sv` is disabled in the project (`UserDisabled = 1`) but not recorded as orphaned in the register | PQ-2 bullets 2-3 | delete the two empty files (or keep them) + one register row | **deferred**: deleted with Kalash approval, then restored the same day because the I-1 intake baseline guards every sources_1/new file (PQ2-FILES-DEFERRED); the orphan package stays recorded as excluded |
| R2 | `docs/STATUS.md` header was rev 20 (I-4, 2026-10-19) | NOC-1 step 7 (status kept current) | **fixed in this commit**: rev 21 summary at the top | done |
| R3 | Verilator cross-check | NOC-2 | BLOCKED: no Verilator on Windows (CLAUDE.md). Stays reported as BLOCKED, never as passed | none |
| R4 | Contract sec. 8 (attestation signals to the CPU) and C-10 (runtime config_len / imem_len ports) | M-F1 rev 8 | resolved at the merge, from the RISC-V package | merge |

Carried limitations (unchanged): L-1 split ambiguity (K-3; now 16 / 64), L-2 stateless reference verifier (policy layer
added), L-3 deterministic demo keys and nonce, L-4 135-byte SHA3 cap, L-5 working-tree byte reproducibility.
