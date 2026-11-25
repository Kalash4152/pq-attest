# S5 — PASS

- Source commit 3d6f5123611056c7f191f8a8bacc80d3fbb414d8, run dual_lane_10_20261121_135030_abd7e1b2.
- Accepted/fresh/reused 20/20/0 of 20.
- LUT/WNS not measured.
- Open blockers none for this gate.
- Next dependency G0 evidence and decision. S6/S8 held.
- HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

Vivado/XSim 2024.1 via `python -E scripts/dual_lane.py run --select I-T5R`. Elapsed job wall time 1394.4 s.

| Job | State | Frozen checks | Result or diagnostic |
|---|---|---:|---|
| it5r_pkg_portable | PASS_FRESH | 2067 | PASS |
| it5r_stamp_unit | PASS_FRESH | 5 | PASS |
| it5r_kill_no_hold | PASS_FRESH | 1 | CONTROL_EFFECTIVE |
| it5r_kill_non_memory | PASS_FRESH | 1 | CONTROL_EFFECTIVE |
| it5r_kill_trust_app | PASS_FRESH | 1 | CONTROL_EFFECTIVE |
| it5r_stamp_wire | PASS_FRESH | 7 | PASS |
| it5r_b0_closure | PASS_FRESH | 14 | PASS |
| it5r_b0_lifecycle | PASS_FRESH | 14 | PASS |
| it5r_b0_error | PASS_FRESH | 6 | PASS |
| it5r_b0_inflight | PASS_FRESH | 6 | PASS |
| it5r_b0_contention | PASS_FRESH | 8 | PASS |
| it5r_b0_phase_sweep | PASS_FRESH | 56 | PASS |
| it5r_b0_attack_approve_changed | PASS_FRESH | 6 | PASS |
| it5r_b0_attack_reject_changed | PASS_FRESH | 6 | PASS |
| it5r_b0_hasher | PASS_FRESH | 9 | PASS |
| it5r_b0_decoder | PASS_FRESH | 19 | PASS |
| it5r_b0_mmio_guard | PASS_FRESH | 3 | PASS |
| it5r_b0_i9_integ | PASS_FRESH | 13 | PASS |
| it5r_b0_matched_secure | PASS_FRESH | 8 | PASS |
| it5r_b0_matched_secure_contended | PASS_FRESH | 8 | PASS |

Raw evidence in S5R_evidence/dual_lane_10_20261121_135030_abd7e1b2. Compared mode-zero results against the immutable S1 golden CSV and simulation observations: 14/14 matched. Generated variant provenance in scripts/titan/prepare_stage5r.py.

The first I-T5 run remains invalid at 10d1da82. Its two-tag check sampled after the L2 wrapper accepted the second app payload, before T_PREP and T_ISSUE allowed the inner NI to allocate the second slot. The later timeout produced no normal final ERRORS count. I-T5R uses a new job ID with the same seven checks. The bench holds the first response until actual simultaneous slot occupancy, verifies both wire tags and epochs, and bounds each transaction wait.

Observed both_live=1 with tags 0 and 1, 50 stalled cycles, and 1,000 of 1,000 randomized wire HEADs (514 writes, 486 reads). The subsystem stall included a re-GRANT while already authorized, which keeps the epoch under D10. The standalone stamp check separately changed the epoch input during a stall and verified first-valid hold. All three stamp mutations were caught. The package portability rerun passed 2,067 checks. sv2v was unavailable locally.

G0 scratch disposition: four Arnav r2 benches compiled but stopped at elaboration on undeclared load_row(0); no simulation verdicts. See G0_BENCH_FEEDBACK.md. Arnav signature, A-WRAP lifetime assumptions, and P6 remain pending. S6 and S8 await the 6 December G0 decision.
