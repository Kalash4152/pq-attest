# PQ-Attest Engineer 4 — Final Execution Report: Step 12 Latency & Step 13 Timeout Corrections

**Author:** PQ-Attest Engineer 4 (Antigravity Verification Pair)  
**Recipient:** Kalash Bheda (Lane 1, NoC Subsystem & PQ-Attest Architecture)  
**Date:** 6 November 2026  
**Status:** COMPLETE — Re-Verified & Evidence-Grounded  
**Target Harness:** `e4_verification_v2` (acceptance baseline preserved and expanded to 389 unit tests)

---

## 1. Exact Files Changed

The following files were modified to implement the required evidence corrections and timeout disambiguations:

1. [`verification/p7_latency_model.py`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/p7_latency_model.py):
   - Added distinct models for `full_subsystem_attestation_rtt_loaded_max` (1,206 cycles) and `full_subsystem_attestation_rtt_none` (1,204 cycles).
   - Grounded worst legitimate CPU wait calculation on the 1,206-cycle LOADED maximum.
   - Refined evidentiary classifications (`MEASURED_REGISTERED`, `DERIVED_ANALYTICAL_BOUND`, `ANALYTICAL_ASSUMPTION`, `CONTRACT_ESTIMATE`, `CONFIGURATION_PARAMETER`, `REVIEWER_STATED_CONFIGURATION`, `PROPOSED_RECOMMENDATION`).
   - Added explicit arbiter bounds applicability table (`ARBITER_APPLICABILITY`) documenting P, Q, and J_MAX.
   - Added `validate_timeout_metadata` and `build_timeout_registry`.
2. [`verification/tests/test_p7_latency_model.py`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/tests/test_p7_latency_model.py):
   - Updated test assertions for 1,206 cycles LOADED max ($W_{\text{nominal}} = 1,234$ cycles) and 1,204 cycles NONE reference ($1,232$ cycles).
   - Added `test_step12_timeout_distinctions_and_arbiter_applicability` verifying distinct timeout values, conflation rejection, and arbiter applicability rules.
3. [`verification/p7_ni_slot_analysis.py`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/p7_ni_slot_analysis.py):
   - Exposed explicit `bench_timeout_cycles` (600) and `merged_ni_slot_timeout_cycles` (8,192) in metadata.
   - Added `timeout_provenance`, `timeout_applied_cycles`, and `timeout_applied_kind` (`"BENCH"`).
   - Added `validate_step13_timeout_metadata`.
4. [`verification/tests/test_p7_ni_slot_analysis.py`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/tests/test_p7_ni_slot_analysis.py):
   - Added `test_step13_timeout_metadata_unambiguity_and_conflation_prevention` testing timeout distinction, metadata provenance, and conflation failure.
5. [`verification/p7_report_figures.py`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/p7_report_figures.py):
   - Updated Figure 06 rendering to display 1,206-cycle LOADED max hold ($W_{\text{nominal}} = 1,234$ cycles, $W_{\text{contention\_C4}} = 1,720$ cycles) and labelled 1,204-cycle NONE reference.
6. [`reports/E4_P7_STEP12_LATENCY_TIMEOUT.md`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/reports/E4_P7_STEP12_LATENCY_TIMEOUT.md):
   - Replaced preliminary numbers with 1,206c LOADED max vs 1,204c NONE distinction, recalculated scenario totals, and added Section 4.3 (Arbiter bounds applicability).
7. [`reports/E4_P7_STEP13_NI_SLOT_LEAK.md`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/reports/E4_P7_STEP13_NI_SLOT_LEAK.md):
   - Added Section 2.1 detailing the explicit distinction between bench timeout (600c) and merged NI timeout (8,192c) with evidentiary provenance.
8. [`verification/build_corrected_handoff.py`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/build_corrected_handoff.py):
   - Updated target archive to `E4_P7_CORRECTED_HANDOFF_FINAL_20261106.zip` with matching sidecar and external manifest.

---

## 2. Exact Measured Latency Values & Condition Labels

From `reports/I5_GATE_20261029.md` (Table "Sec. 9 coverage / n2p7_rtt", run `dual_lane_10_20261029_140104_d9fb229d`):

| Condition Label | Observed Samples | Mean | Maximum | Segment Breakdown | Model Role |
|---|---|---:|---:|---|---|
| **`NONE`** (unloaded) | `[1204, 1204, 1204, 1204]` | 1,204.0c | 1,204c | start $\to$ CHALLENGE: 208c<br>CHALLENGE $\to$ RESPONSE: 524c<br>RESPONSE $\to$ GRANT: 350c<br>GRANT $\to$ delivered: 122c | **Labelled Reference** |
| **`LOADED`** (writes + raw-port flood) | `[1206, 1206, 1205, 1205]` | 1,205.5c | **1,206c** | start $\to$ CHALLENGE: 208c<br>CHALLENGE $\to$ RESPONSE: 524–525c<br>RESPONSE $\to$ GRANT: 350c<br>GRANT $\to$ delivered: 123–124c | **Selected Model Input** |

**Selection Rationale:** Because Step 12 establishes the **worst legitimate CPU wait** at Tile 3 to bound `BRIDGE_TIMEOUT`, the **1,206-cycle LOADED maximum** is selected as the primary attestation port-hold input. The 1,204-cycle measurement represents the unloaded baseline and is preserved as a labelled reference.

---

## 3. Recalculated Scenario Totals & Margins

Adding the sequential 28-cycle service path ($3\text{c NI} + 11\text{c fwd} + 2\text{c BRAM} + 11\text{c rev} + 1\text{c egress}$) to the selected port-hold input yields:

| Scenario | Calculation | Wait (Cycles) | Margin vs Proposed `BRIDGE_TIMEOUT = 4,096` |
|---|---|---:|---:|
| **Nominal Legitimate Wait (LOADED max hold)** | $1,206 + 28$ | **1,234** | **3.32x** (+232%) |
| *Reference NONE Wait* | $1,204 + 28$ | *1,232* | *3.32x* (+232%) |
| **Arbiter Class P Contention** | $1,234 + 269$ | **1,503** | **2.73x** (+173%) |
| **C4 Revocation Maximum** | $1,234 + 486$ | **1,720** | **2.38x** (+138%) |
| **Contract R7.6a Analytical Estimate** | $2,700 + 28$ | **2,728** | **1.50x** (+50%) |
| **Extreme Contractual C4 Bound** | $1,234 + 1,500$ | **2,734** | **1.50x** (+50%) |
| **Global Verifier Separation** | $100,000 / 4,096$ | — | **24.4x** (+2,341%) |

All safety margins comfortably exceed $1.0\times$, supporting the technical recommendation to retain `BRIDGE_TIMEOUT = 4,096` (PROPOSED, pending Kalash approval per contract D7).

---

## 4. Explanation of Arbiter Bounds Applicability (P, Q, J)

| Bound | Cycles | Classification | In CPU Path? | Added to CPU Wait? | Technical Rationale |
|---|---:|---|:---:|:---:|---|
| **$J_{\text{MAX}}$** | 128 | `DERIVED_ANALYTICAL_BOUND` | No | **No** | Frozen ceiling for a single KMAC128 job (M-F1 R7.6). Single job durations are already encompassed inside the measured attestation hold (1,204c / 1,206c) and within the $P$ and $Q$ bounds. Adding $J_{\text{MAX}}$ separately would double count. |
| **$P$** | 269 | `DERIVED_ANALYTICAL_BOUND` | No | **Yes** (in P contention scenario) | Upper bound on engine wait for RoT-class traffic at Tile 3 ($r_0, r_1$). Applied once as a conservative single-wait contention increment ($W_{\text{contention\_P}} = 1,503$c). |
| **$Q$** | 792 | `DERIVED_ANALYTICAL_BOUND` | No | **No** (captured in contract estimate) | Starvation ceiling for non-RoT traffic at Tile 4 ($r_2, r_3$: RESPONSE MAC and verify). Affects attestation duration under starvation load; reflected in the contract analytical estimate (~2,700c) rather than added directly to the measured P scenario. |
| **CPU Data Path** | — | `EVIDENCE_NOTE` | No | **No** | CPU memory requests travel on plain data VCs in P7 (VC 0) and do not use the shared L2 KMAC engine. They never encounter KMAC engine arbitration. |

---

## 5. Explicit Bench vs Merged NI Timeout Distinction

| Identifier | Value | Classification | Source / Provenance | Usage |
|---|---:|---|---|---|
| `bench_timeout_cycles` | **600** | `CONFIGURATION_PARAMETER` | `tb_i9_integ.sv`:5, `result.json` in `dual_lane_10_20261106_163900_ff77f562`, `I9_GATE_20261105.md` | Used in all 14 Step 13 simulation sequences and Step 12 timeout scenarios |
| `merged_ni_slot_timeout_cycles` | **8,192** | `REVIEWER_STATED_CONFIGURATION` | `E4_FINAL_INTAKE_20261106.md` / `E4_FINAL_RESPONSE_20261106.md` (citing M-F1 rev 8) | Referenced in timeout hierarchy only; RTL default is 0 (off); not synthesized |

Both values are emitted as explicit fields in `p7_ni_slot_analysis.json` and `p7_latency_model_results.json`. Every scenario record contains `timeout_applied_cycles: 600` and `timeout_applied_kind: "BENCH"`. Unit tests reject conflation or missing provenance.

---

## 6. Focused Test Results

- **Step 12 Tests (`verification/tests/test_p7_latency_model.py`):** **12 / 12 passed** (0 failed, 0 skipped).
- **Step 13 Tests (`verification/tests/test_p7_ni_slot_analysis.py`):** **17 / 17 passed** (0 failed, 0 skipped).

---

## 7. Full-Suite Test Count & Result

Command: `python -m pytest verification -q`  
Result: **389 passed in 9.43s** (0 failed, 0 skipped).

---

## 8. Full Regression Stage Count & Result

Command: `python verification/p7_regression.py --full`  
Result: **15 / 15 stages passed** (0 failed, 0 skipped, run ID: `e4_p7_run_1793976525`).

---

## 9. S4 and Nov 3 Validation-Only Results

- **S4 Baseline Validation:** `python verification/p7_regression.py --validate-only --baseline s4`  
  Result: **PASS (6 passed, 0 failed, 9 skipped by design)**.
- **Nov 3 Baseline Validation:** `python verification/p7_regression.py --validate-only --baseline nov3`  
  Result: **PASS (6 passed, 0 failed, 9 skipped by design)**.

---

## 10. F3 Portability Validation Result

Command:  
`python verification/p7_regression.py --quick --repo-root "c:\Users\Arnav Bhandari\PQ_Attest" --data-dir "c:\Users\Arnav Bhandari\PQ_Attest" --out "c:\Users\Arnav Bhandari\PQ_Attest\verification\generated"`  
Result: **PASS (11 passed, 0 failed, 4 skipped by design)**.

---

## 11. Confirmation: Frozen Harness Unchanged

The registered acceptance harness `e4_verification` and `e4_verification_v2` definitions in `E4_EVIDENCE_20261106` were not modified. The original 224-test and 387-test frozen registered runs remain intact in historical evidence packages.

---

## 12. Confirmation: Zero RTL Changes

- `git diff -- rtl/dual_lane`: **0 modifications (empty output)**.
- Evidence baselines: S4 and Nov 3 protected file SHA-256 checks pass with 0 hash discrepancies.

---

## 13. Mandatory Verification Disclaimers

In strict adherence to verification integrity and evidentiary boundaries:
- **Classification:** Python model checking. Not RTL simulation, not hardware, not formal.
- **`HARDWARE_VALIDATED=NO`** — No silicon or FPGA board-level execution conducted in this scope.
- **`SOC_INTEGRATION_COMPLETE=NO`** — RISC-V CPU core integration and software driver stack remain outside E4 scope.
- **`FORMAL_PROOF=NO`** — Formal mathematical model checking was not executed.
- **`RTL_MODIFICATIONS=0`** — Zero modifications were made to protected dual-lane RTL.
- **`PYTHON_MUTANTS_ARE_RTL_MUTANTS=NO`** — Python reference model mutants are not RTL mutants.
- **`SYNTHETIC_STIMULUS_IS_RTL_EVIDENCE=NO`** — Synthetic test stimuli are quarantined from registered simulation evidence.

---

## 14. Final Handoff Package & Identifiers

- **Final Archive Name:** `E4_P7_CORRECTED_HANDOFF_FINAL_20261106.zip`
- **Archive Size:** 850,025 bytes
- **SHA-256 Digest:** `f7e52a23e9c413da52e6172016eeac1f056998c4118e3844b81b67db01fbeeab`
- **External Sidecar Name:** `E4_P7_CORRECTED_HANDOFF_FINAL_20261106.zip.sha256`
- **External Manifest Name:** `E4_P7_CORRECTED_HANDOFF_FINAL_20261106.manifest.json`
- **Internal Manifest Path:** `verification/generated/e4_corrected_handoff_manifest.json` (224 files cataloged)

---

## 15. Independent Package Verification

Package verification was executed via `python verification/build_corrected_handoff.py --verify`:
- **Verification Status:** `PASS`
- **Defects / Problems:** `[]` (0 problems)
- **Archive Entries Verified:** 226 entries
- **Manifest Entries Checked:** 224 files (100% match on presence, size, and SHA-256 hash)
- **Sidecar Agreement:** Exact match between `Get-FileHash` and sidecar text file.

---

## 16. Git Revision & Working Tree Status

- **Final Commit SHA:** `b2511f5577b13d7f052ba1400b49965ad063f39a` (`b2511f5`)
- **Historical Commit Base:** `00d58c1417fe8c049d78ba63038abfd24ee69811` (`00d58c1`)
- **Commit Message:** `fix(e4): correct Step 12 latency inputs, document arbiter bounds and disambiguate Step 13 timeouts`
- **Protected RTL Diff:** Empty (`git diff -- rtl/dual_lane` = 0 modifications).
- **Working Tree:** Clean of tracked changes.
