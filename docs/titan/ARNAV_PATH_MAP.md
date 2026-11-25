# TITAN paths for Arnav's verification repository

Kalash's branch is kalash/titan-rtl. Arnav owns arnav/titan-verif in his separate PQ_Attest repository. Use the export MANIFEST.txt to pin copied sources to the Kalash commit and TITAN baseline. Source and report paths below are relative to Kalash's worktree.

| Arnav path or expectation | Kalash path | Status |
|---|---|---|
| scripts/titan/run_regress.ps1 and run_unit.ps1 as evidence | scripts/dual_lane.py run --select I-Tn | Evidence through the registered runner. scripts/titan/run_regress.ps1 is an optional wrapper. |
| sim_logs/titan/regress_0_golden.csv | docs/titan/S1_GOLDEN.csv | Frozen S1 mode-zero observations. |
| sim/titan/titan_finality_monitor.sv | rtl/dual_lane/titan/titan_finality_monitor.sv and titan_mon_bind.sv | S2 simulation-only. |
| Monitor CSV | docs/titan/MONITOR_EVENTS.md and S2_evidence under docs/titan/stage_reports | See extraction procedure and reported scope. |
| docs/titan/02_INTERFACES_v2.md rev A | docs/decisions/M-F1-rev11-TITAN-EPOCH-STATUS.md | Kalash signed. Arnav signature pending. DENIED is CPU code 6. |
| Package and standalone proof targets | rtl/dual_lane/titan_pkg.sv and rtl/dual_lane/titan/titan_*.sv | S3 package, then one target per block. Check the current stage report. |
| TITAN_T1 define in merged core | Explicit same-module-name file swaps, scripts/prepare_titan.py and the stage-specific generators | D1. No macro-based hierarchy switch. |
| formal/smoke/gate_converted.v | rtl/dual_lane/noc_attest_gate.sv and rtl/dual_lane/NOC_PKG.sv | Convert the pinned B0 inputs with the proof target note. Arnav's converted file and commit 81d88e6 belong to his repository. |
| Mutation source list | mutants/s4_mutants.json onward | Exact source anchors and targeted checks. Apply to temporary copies only. |
| Dates / handoff notes | docs/titan/stage_reports/Sn.md and _export/arnav/ | Exports follow accepted stage gates. S6 and S8 await the G0 decision. |

Keep bounds separate from measured latency. The minimum gap between accepted epoch updates must include back-to-back GRANT/REVOKE as supported by the verifier, transport and gate. A 232-cycle revocation observation cannot establish that gap. A 64-update wrap interval must be strictly greater than the permitted 8,192-cycle lifetime under the proposed comparison. The signed revocation bound is 1,500 cycles. Neither the proposed 128-cycle jitter nor the 1,720-cycle completion claim has current evidence here. Credit conservation remains P6=X. Existing-gate proofs do not establish TITAN properties.

Arnav r2 FORMAL_FLOW.md pins both baseline input SHA-256 values from ARNAV_GATE_PROOF_TARGET.md and records sv2v v0.0.13. Both match the shipped Git blobs and live files. Existing gate U-class proofs are attributed to Arnav. Local TITAN FORMAL_PROOF remains NO.

The D10 target replaces the earlier tracker for current proofs. Use rtl/dual_lane/titan/titan_epoch_tracker_r1.sv from the S4R archive. Its effective epoch advances in the first authorized cycle; the counter settles on the next clock edge. The original S4 tracker and its PASS remain historical under the original accepted-message rule.
