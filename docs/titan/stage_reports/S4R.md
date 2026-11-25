# S4 — PASS

- Source commit 88f50141441571643ac66439e01bd2bbe042c95a, run dual_lane_10_20261121_132528_82d7e76f.
- Accepted/fresh/reused 19/19/0 of 19.
- LUT/WNS not measured.
- Open blockers none for this gate.
- Next dependency S5 epoch stamp.
- HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

Vivado/XSim 2024.1 via `python -E scripts/dual_lane.py run --select I-T4R`. Elapsed job wall time 1348.8 s.

| Job | State | Frozen checks | Result or diagnostic |
|---|---|---:|---|
| it4r_epoch_unit | PASS_FRESH | 11 | PASS |
| it4r_kill_revoke | PASS_FRESH | 1 | CONTROL_EFFECTIVE |
| it4r_kill_held_high | PASS_FRESH | 1 | CONTROL_EFFECTIVE |
| it4r_kill_trusted_fail | PASS_FRESH | 1 | CONTROL_EFFECTIVE |
| it4r_mode4_smoke | PASS_FRESH | 4 | PASS |
| it4r_b0_closure | PASS_FRESH | 14 | PASS |
| it4r_b0_lifecycle | PASS_FRESH | 14 | PASS |
| it4r_b0_error | PASS_FRESH | 6 | PASS |
| it4r_b0_inflight | PASS_FRESH | 6 | PASS |
| it4r_b0_contention | PASS_FRESH | 8 | PASS |
| it4r_b0_phase_sweep | PASS_FRESH | 56 | PASS |
| it4r_b0_attack_approve_changed | PASS_FRESH | 6 | PASS |
| it4r_b0_attack_reject_changed | PASS_FRESH | 6 | PASS |
| it4r_b0_hasher | PASS_FRESH | 9 | PASS |
| it4r_b0_decoder | PASS_FRESH | 19 | PASS |
| it4r_b0_mmio_guard | PASS_FRESH | 3 | PASS |
| it4r_b0_i9_integ | PASS_FRESH | 13 | PASS |
| it4r_b0_matched_secure | PASS_FRESH | 8 | PASS |
| it4r_b0_matched_secure_contended | PASS_FRESH | 8 | PASS |

Raw evidence in S4R_evidence/dual_lane_10_20261121_132528_82d7e76f. Compared mode-zero results against the immutable S1 golden CSV and simulation observations: 14/14 matched. Generated variant provenance in scripts/titan/prepare_stage4r.py.

D10 uses the gate's registered authorized output directly. The effective epoch advances in its first high cycle and remains stable through a re-GRANT, REVOKE, trusted failure and timeout. All three new mutants were rejected by their targeted checks. The original S4 evidence and old-epoch design are retained at 58c3ee38. For the externally reported gate proofs and D10 receiving-path lower bound, see ARNAV_REVIEW_20261121.md and ATTEST_TIMING_FACTS.md. No local sv2v result is available.
