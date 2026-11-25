# Approved A to F execution tracker

Baseline: e17a369e, noc/credit-integration. Owner authorization: Kalash, 2026-11-08, approval of final roadmap. Contract: docs/decisions/M-F1-rev9-RTL-CLOSURE.md.

| Milestone | State | Exit evidence |
|---|---|---|
| Scope and contract | Written before dependent changes | M-F1 revision 9 |
| Real CPU error acceptance I-18 | PASS 2/2 fresh | reports/I18_GATE_20261108.md; real-core faults and causal IRQ control |
| RTL parameter/debug/NI status/config changes | Parameter/debug/NI PASS; config qualification next | reports/I19_GATE_20261108.md |
| Firmware v2 and provisioning | I-20 PASS 3/3 | reports/I20_GATE_20261108.md; reference, 12 real-CPU checks, IRQ control |
| Merged active traffic/revoke/error/contention | Step 5 PASS: I-21 and I-23 | Lifecycle/error plus accepted in-flight revoke and contention controls |
| Coverage matrix and affected regression | Not started | Requirement-to-evidence table and gate |
| Vivado build hardening and final image | I-22 validator unit gate PASS; integration/build still pending | reports/I22_GATE_20261109.md |
| Secure/insecure research measurements | Not started | Matched configuration/raw data |
| Reproducible release and final Tcl | Not started | Clean replay, hashes, documentation |
| Exact final-image board observations | Owner action pending final image | Kalash's observations, not agent inference |

HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO. Historical owner-reported board PASS is preserved separately. No claim of completion until exit evidence exists. Existing .xpr/user working-tree changes are preserved.
