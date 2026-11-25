# PQ-Attest Engineer 4 — Step 17: Report Figures

**Date:** November 6, 2026  
**Author:** Engineer 4 (Antigravity Verification Pair)  
**Status:** COMPLETED & VERIFIED  
**Deliverables:**
- `verification/p7_report_figures.py`
- `verification/tests/test_p7_report_figures.py`
- `verification/generated/p7_report_figure_manifest.json`
- `reports/E4_P7_STEP17_REPORT_FIGURES.md`
- `reports/figures/` (10 SVG vector diagrams)

---

## 1. Executive Summary

Step 17 provides reproducible, high-fidelity SVG figures visualising core architectural, protocol, verification, and performance aspects of the PQ-Attest project.

All figures explicitly embed their provenance category:
- **`MEASURED_RTL_DATA`**: Data derived from Vivado timing runs or XSim simulation logs.
- **`SPECIFIED_VALUES`**: Architectural values codified in frozen specifications and contracts.
- **`PYTHON_MODEL_OUTPUT`**: Results generated from the verified Python reference model.
- **`SYNTHETIC_TEST_INPUT`**: Deterministic synthetic stimuli used for protocol monitoring.

---

## 2. Generated Figure Inventory

| Figure ID | Filename | Title | Provenance | Source File(s) | Units / Scope |
|:---|:---|:---|:---:|:---|:---|
| **FIG_01** | `fig01_pair_matrix.svg` | Six-Tile Directed Communication Pair Matrix | `SPECIFIED_VALUES` | `verification/p7_pair_matrix.py` | 30 legal pairs, 6 diagonal self-pairs |
| **FIG_02** | `fig02_requirement_coverage.svg` | Requirement Traceability Matrix Coverage | `PYTHON_MODEL_OUTPUT` | `verification/p7_coverage_audit.py` | 58/58 requirements (100.0%) across Groups A–F |
| **FIG_03** | `fig03_mutation_results.svg` | Python Mutation Sensitivity Analysis | `PYTHON_MODEL_OUTPUT` | `p7_mutation_analysis.py`, `p7_i9_model.py` | 16 core + 8 I-9 mutants killed (100% score) |
| **FIG_04** | `fig04_ni_slot_occupancy.svg` | NI Slot Occupancy Lifecycle | `PYTHON_MODEL_OUTPUT` | `verification/p7_ni_slot_analysis.py` | Slot occupancy (0, 1, 2) over clock cycles |
| **FIG_05** | `fig05_timeout_behavior.svg` | NI Slot Timeout & Stale Response Discard | `SPECIFIED_VALUES` | `verification/p7_latency_model.py` | Two-slot tracking (`N_OUTSTANDING=2`), 8,192c merged watchdog, 600c bench, `I9_SLOT_HELD`, `SLOT_RECOVER`, `STALE_DROPPED` |
| **FIG_06** | `fig06_latency_breakdown.svg` | Attestation Latency & Legitimate CPU Wait Breakdown | `DERIVED` | `verification/p7_latency_model.py` | Measured 1,204c attestation RTT + transport (1,232c nominal, 1,718c C4 max) vs 4,096c `BRIDGE_TIMEOUT` (2.38x margin) |
| **FIG_07** | `fig07_link_monitor.svg` | NoC Link Monitor Rule Verifications | `SYNTHETIC_TEST_INPUT` | `verification/p7_link_monitor.py` | Invariant checks across NoC links |
| **FIG_08** | `fig08_d2_sensitivity.svg` | D2 48-Byte IMEM Sensitivity Verification | `PYTHON_MODEL_OUTPUT` | `verification/p7_d2_measurement.py` | 48/48 mutated bytes divergent (100%) |
| **FIG_09** | `fig09_regression_status.svg` | PQ-Attest Regression Suite Execution Status | `PYTHON_MODEL_OUTPUT` | `verification/p7_regression.py` | Complete 15/15 stages PASS |
| **FIG_10** | `fig10_performance_curves.svg` | Measured Timing Slack Distribution | `MEASURED_RTL_DATA` | `reports/n25_2026-09-23/paths_lt3ns.csv` | Measured path slack (ns) distribution |

---

## 3. Provenance & Artifact Integrity

Every figure is backed by exact source tracking and cryptographic hashing in:
`verification/generated/p7_report_figure_manifest.json`

Zero measurements were fabricated; where empirical RTL timing was available (`paths_lt3ns.csv`), exact path values were parsed and plotted. Where parameters are architectural specifications, they are labeled `SPECIFIED_VALUES` or `PYTHON_MODEL_OUTPUT`.

