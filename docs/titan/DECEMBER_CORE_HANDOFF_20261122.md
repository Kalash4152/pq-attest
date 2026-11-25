# TITAN December core handoff | 22 November 2026

**Working scope: revision-10 B0, S4R epoch tracker and S5R request stamping.** Kalash authorized proceeding with the agreed core work. S7 stays conditional. S6 and S8 stay deferred. This record does not represent a joint G0 signature. Record Kalash's and Arnav's scope confirmation by November 30 using the disposition below. Target the engineering handoff by December 31.

## Baseline and reproduction

| Record | Exact source | Accepted archived results | Registered command |
|---|---|---|---|
| B0 | titan-base-20261119, b9e41c383473802267c8c3d604e329770d708ab5 | 55 pinned RTL file hashes verified against the B0 replay bytes | Use the original source manifest in ARNAV_NOC_FILE_LIST_20261121.md. |
| S4R | 88f50141441571643ac66439e01bd2bbe042c95a | 19 fresh, 14/14 B0 comparisons | python -E scripts/dual_lane.py run --select I-T4R |
| S5R | 3d6f5123611056c7f191f8a8bacc80d3fbb414d8 | 20 fresh, 14/14 B0 comparisons | python -E scripts/dual_lane.py run --select I-T5R |

Use Vivado/XSim 2024.1. Replay from the matching byte-preserved stage roots at C:/vivado_verilog_proj/_t4rr and _t5rr, with the archived REPLAY_IDENTITY.json and protected overlays. Stage reports include the root run IDs. Run preflight and verify source identity before any registered rerun. Keep the existing registry and expected counts. Both archived comparison sets agree across all 14 entries after removing the stage prefix. The archived protected comparisons show zero changes among 48 files for each run.

The independent authorized transaction and interval checks passed 6/6 with 28 contiguous observer samples. The bridge fixture passed 19/19 at its reduced timeout. These are local scratch diagnostics. The archive includes raw logs and the ordinary-transaction events.

## November 27 case disposition and November 30 decision

- Silent denial remains unaccepted. In the archived SD log, SD_TILE3_GRANT1 and SD_REVOKED_MIDFLIGHT both failed. The handoff reports occupancy over 600 cycles. The B0 front end has response-suppression branches, while the NI has a stale-to-free path on the second age expiry when aging progresses. The record does not tie a validated denial to a complete response interval and actual slot retirement. A permanent leak claim is unsupported.
- M1 and M2 remain inconclusive in the intended profile. The old M2's initial setup check sampled authority too early. The newer source addresses that assumption. M3 remains inconclusive for the combined CPU-visible timeout and memory-side effect. P6 and A-WRAP remain open.
- Adopt the core-only scope at the decision cutoff unless existing SD evidence substantiates the bounded response and retirement claim and Kalash approves S7. For S7, freeze the expected outcome and check counts in advance. Require one reason-coded response, matching identity, expected memory behavior and retirement. S8 is read filtering. S9 owns the software error mapping.
- Arnav's outstanding review is concurrence on the evidence and deliverable scope. Local Vivado diagnostics are Kalash's lane. The combined team is outside the G0 decision dependency.

## Release boundary

The present archive is the core evidence and replay handoff for review. Archived registered runs establish the accepted increment results. The archive does not represent a fresh integrated December candidate, final Vivado source-set configuration, or bitstream. Freeze the chosen revision and integration manifest after the joint scope decision. Use the final Tcl setup and manual bitstream workflow when that candidate passes its integrated checks.

HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.


Fresh harness preflights passed at the pinned commits. S4R checked 342 guarded files and 779 source lists. S5R checked 346 guarded files and 799 source lists. The registered simulations cited above are archived acceptances.
