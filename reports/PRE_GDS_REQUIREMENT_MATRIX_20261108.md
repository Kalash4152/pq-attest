# Requirement closure working matrix

This is an execution matrix, not a whole-project sign-off. No missing evidence is inferred to be PASS. Historical accepted runs retain their original source identities. Final regression and final FPGA implementation remain mandatory after the selected changes.

| Requirement | Present evidence | Remaining closure |
|---|---|---|
| Original R4 NoC and PQ packages | Historical I-1–I-8 and S4 gates | Map individual signed requirements and requalify affected final-source closure |
| App RX, shared BRAM, NI slot recovery | I-9, I-10 | Final-source and active-revoke recovery tests |
| E4 model verification | I-12 389 pytest / 15 stages | Preserve Python-vs-RTL distinction and collect final evidence links |
| A1 registered-ready capture guard | I-14 / I-16 and causal mutant | Include unchanged checks in final regression |
| A2 conformance / A4 latency stress | Prior scratch campaigns | Registered counted seed/transaction evidence and operation-size/alignment audit |
| A3 CPU IRQ handler and next-instruction ordering | I-18 10 checks plus IRQ-disconnect control; I-19 reuses fresh matched CPU rerun | IRQ-return firmware I-20 and final merged tests |
| A5 two programs and assertions | I-16 | Final source requalification |
| A6 reset, identities, decoder | I-13 / I-16 / I-19 | Final matrix reset-at-protocol-phase audit |
| A7 16 KB memories and second read port | I-13 / I-16 | Final profile/reproducibility; no whole-program integrity claim |
| A8 bounded firmware and post-revoke retry | I-20 in progress | Full text, IRQ return, refusal and recovery gate |
| A9 CPU tile implementation | Historical A9 + I-17 combined implementation | New release build after RTL/profile changes |
| A10 reproducible submission | Review ZIP and original intake manifests | Path-preserving release with clean replay |
| B1 bridge authorization, framing and timeout | I-13 / I-14; I-19 timeout propagation | Merged active timeout/revoke tests and boundary matrix |
| B2 CPU integration | I-13–I-16; I-19 CPU wrapper | Final merged image/profile integration |
| B3 measurement reader | I-13 / I-14 control | New qualified config/measurement profile and final co-sim |
| B4 STATUS and NI status MMIO | I-13 STATUS; I-19 NI MMIO/counter/debug controls | Final map/header documentation |
| B5 protocol checker | I-14 | Reconcile stale scratch-only notes; final merged binding/coverage audit |
| B6 real merged co-simulation | I-15 / I-16 | Error response, active revoke, contention, post-revoke CPU retry/re-attestation |
| B7 tile synthesis | Historical B7/A9 | Final version resource evidence |
| Build acceptance and project update | I-17 historical gate | Unify actual bitstream path with gate, both-CPU firmware provenance, overlap guard, negative automation tests |
| Research baseline and latency | Historical subsystem secure/insecure measurements | Matched combined two-CPU secure/insecure runs and final raw data |
| Board observations | Owner-reported earlier-image PASS | Owner programs exact final hash; itemized UART/LED/revoke/re-attest record |

HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO for this closure work. Existing owner-reported board evidence is separate. ASIC part G is excluded from this execution authorization.
