# Engineer 4: PQ-Attest P7 Verification — S4 Release Evidence Reconciliation Report

**Document ID:** `reports/E4_P7_S4_RECONCILIATION.md`  
**Author:** Engineer 4 (Python Verification Lead)  
**Date:** November 5, 2026  
**Status:** BLOCKED (Package Acceptance and Python/RTL Compatibility Pending)  
**Evidence Package:** `PQ_Attest_S4_Evidence_20261105.zip` (unpacked at `PQ_Attest_S4_Evidence/`)  
**Active Increment:** `S4` (Area Optimization & Synthesis Restructuring)  

---

## 1. Executive Summary & Purpose

This report documents Engineer 4's official audit and reconciliation of the **S4 release evidence package** (`PQ_Attest_S4_Evidence_20261105.zip`). The S4 increment introduces the S4-A5 KMAC transform (removing redundant 1,600-bit Keccak state-reg copies in KMAC cores) and the S4-F1/F2/F3 synthesis restructuring flow (splitting mesh synthesis from surrounding wrapper logic to meet area constraints).

In accordance with strict verification protocol:
1. **Registered S4 Run Status:** The primary registered XSim run (`dual_lane_10_20261105_023806_ae7d5152`) is formally recorded as **BLOCKED** (`status: BLOCKED`, `increment_status: NOT_RUN`). This is due to 4 implementation jobs remaining unexecuted within that simulation batch, and 368 prerequisite jobs remaining blocked outside the active S4 increment.
2. **Package Acceptance:** Formal acceptance of the S4 release package and complete Python/RTL cross-plane compatibility sign-off remain **PENDING**.
3. **No Hardware Claim:** `HARDWARE_VALIDATED = NO`, `FORMAL_PROOF = NO`, `SOC_INTEGRATION_COMPLETE = NO`.
4. **Source Code Preservation:** Zero modifications have been made to repository RTL (`rtl/dual_lane/*.sv`). The historical November 3 baseline has been fully preserved.

---

## 2. S4 Source Inventory & Classification

An exhaustive cryptographic audit was conducted on all 111 unique source files cataloged in `01_s4_source_list/s4_unique_sources_live_sha256.csv` against the authoritative source tree in `02_sources/`.

### Source Verification Summary

| Source Classification | File Count | Verified SHA-256 | Verified Bytes | Status |
| :--- | :---: | :---: | :---: | :---: |
| **SystemVerilog RTL** | 62 | 62 / 62 | 62 / 62 | **PASS** |
| **SystemVerilog Testbench** | 21 | 21 / 21 | 21 / 21 | **PASS** |
| **Python Software / Scripts** | 18 | 18 / 18 | 18 / 18 | **PASS** |
| **JSON Metadata / Provenance** | 5 | 5 / 5 | 5 / 5 | **PASS** |
| **SystemVerilog Headers (`.svh`)** | 3 | 3 / 3 | 3 / 3 | **PASS** |
| **Vector / Memory Data (`.mem`)** | 2 | 2 / 2 | 2 / 2 | **PASS** |
| **TOTAL UNIQUE SOURCES** | **111** | **111 / 111 (100%)** | **111 / 111 (100%)** | **PASS** |

The generated machine-readable catalog is archived at:
[`verification/generated/p7_s4_source_manifest.json`](file:///C:/Users/Arnav%20Bhandari/PQ_Attest/verification/generated/p7_s4_source_manifest.json)

---

## 3. A5 KMAC Provenance & Variant Validation

The S4 increment introduces two optimized KMAC hardware variants under the S4-A5 area contract (`docs/decisions/S4_AREA_CONTRACT.md`):
- `rtl/dual_lane/kmac_128_a5.sv`: Standalone KMAC core eliminating the secondary 1,600-bit state copy.
- `rtl/dual_lane/kmac_128_xp_a5.sv`: Permutation-export KMAC core sharing Keccak permutation instances.

Both variants were audited against `02_sources/rtl/dual_lane/s4_provenance.json` and `02_sources/A5_PROVENANCE_CHECK.txt`.

### Provenance Audit Matrix

| Hardware Variant Path | Base Source File | Pinned Source SHA-256 | Verified Output SHA-256 | Match |
| :--- | :--- | :--- | :--- | :---: |
| `rtl/dual_lane/kmac_128_a5.sv` | `kmac_128.sv` | `796164790af7073a6260b561e9ac943a3291cfa278e5d3d6a8709fd2dafe0a72` | `4b5c867d5cffc5ca2811ef785b0bb381f5b5a1be401ae3d85c1fc3f6671685bb` | **VALID** |
| `rtl/dual_lane/kmac_128_xp_a5.sv`| `kmac_128.sv` | `796164790af7073a6260b561e9ac943a3291cfa278e5d3d6a8709fd2dafe0a72` | `e0302fd5503dc5ddd322432731016e8a7d3d335d9f829bfbf51ab34461017b04` | **VALID** |

*Provenance Finding:* The on-disk variants are byte-exact reproductions of the pinned source edits. No hand-edits or uncommitted changes exist.

---

## 4. Registered S4 Job Accounting & Execution Status

A complete reconciliation of the Vivado/XSim job registry (`registry.json`) and run execution manifest (`status.json`) was performed for run `dual_lane_10_20261105_023806_ae7d5152`.

```
                    S4 REGISTERED JOB ACCOUNTING BREAKDOWN
+-----------------------------------------------------------------------------------+
| Total Registry Jobs                                                    : 434      |
+-----------------------------------------------------------------------------------+
  |
  +-- Active S4 Increment Jobs                                            :  66      |
  |     |-- PASS_FRESH (Simulation, Variant & Controls)                   :  62      |
  |     +-- NOT_RUN (Implementation Jobs in this batch)                   :   4      |
  |
  +-- Out-of-Scope BLOCKED Jobs                                           : 368      |
        (Reason: "outside active S4; later increment requires accepted prerequisite")
```

### Detailed Breakdown:

1. **62 PASS_FRESH Simulation & Verification Jobs:**
   - 54 release simulation testbenches (including `s4_i7_sec`, `s4_i7_full_chain`, `s4_i6_retry`, `s4_i6_gate`, `s4_i6_p7_ingress`, `s4_s3_l2p7_equiv`, `s4_s3_l2e_engine`, `s4_p7_gate_data`, `s4_s2_attacks`, etc.).
   - 5 Python dependency checks (including `s4_s2_vectors_check`, `s4_s3_variant`, `s4_i6_retry_vectors`, `s4_i7_vectors`).
   - 2 A5 hardware control mutants confirmed killed:
     * `s4_mut_absorb_zero_core` (**PASS_FRESH**)
     * `s4_mut_absorb_zero_xp` (**PASS_FRESH**)
   - 1 provenance validation check: `s4_variant` (**PASS_FRESH**).

2. **4 NOT_RUN Implementation Jobs in the Registered Simulation Run:**
   - In the registered simulation batch `023806_ae7d5152`, the four long-running place-and-route jobs were marked `NOT_RUN`:
     * `s4r_p7_pnr`
     * `s4r_soc_pnr`
     * `s4r_n13_secure`
     * `s4r_n13_insecure`
   - These 4 jobs were subsequently executed as isolated standalone runs under `04_registered_impl_runs/`:
     * `run_033916_71a1eedc`: `s4r_p7_pnr` (PASS_FRESH, 32,457 LUT, WNS +0.334 ns)
     * `run_035324_bf4d9cea`: `s4r_soc_pnr` (PASS_FRESH, 32,042 LUT, WNS +0.038 ns)
     * `run_040617_08dd583e`: `s4r_n13_secure` (PASS_FRESH, 32,708 LUT, -14.0%, WNS +0.275 ns)
     * `run_042159_0fe3d737`: `s4r_n13_insecure` (PASS_FRESH, 11,708 LUT, WNS +0.237 ns)

3. **368 Out-of-Scope BLOCKED Jobs:**
   - All 368 jobs outside increment S4 remain explicitly blocked pending accepted prerequisites.

The generated machine-readable evidence summary is archived at:
[`verification/generated/p7_s4_evidence_summary.json`](file:///C:/Users/Arnav%20Bhandari/PQ_Attest/verification/generated/p7_s4_evidence_summary.json)

---

## 5. Multi-Baseline Integrity Architecture

To support evolving release baselines without compromising historical auditability, the regression runner (`verification/p7_regression.py`) has been updated to support explicit release baselines:

```bash
# Verify against historical November 3 baseline (38 files: dual_lane RTL & reports)
python verification/p7_regression.py --baseline nov3

# Verify against new S4 baseline (111 unique sources & A5 provenance)
python verification/p7_regression.py --baseline s4

# Exhaustively verify both November 3 and S4 baselines simultaneously
python verification/p7_regression.py --baseline all
```

### Baseline Configuration Matrix

| Baseline Identifier | Scope of Protection | Integrity Validation Mechanism |
| :--- | :--- | :--- |
| **`nov3`** (Historical) | 31 `rtl/dual_lane/*.sv` files + Steps 1–8 reports | SHA-256 comparison against November 3 baseline hashes |
| **`s4`** (S4 Increment) | 111 unique S4 sources + A5 KMAC provenance files | Manifest cross-check against `s4_unique_sources_live_sha256.csv` |
| **`all`** (Exhaustive) | Both November 3 RTL/reports AND all S4 evidence assets | Dual-plane SHA-256 cryptographic verification |

---

## 6. Audit of Step 8 Handoff Corrections

In accordance with Section 10 of the reconciliation directives, the final handoff report [`reports/E4_P7_STEP8_FINAL_HANDOFF.md`](file:///C:/Users/Arnav%20Bhandari/PQ_Attest/reports/E4_P7_STEP8_FINAL_HANDOFF.md) was updated with the following specific amendments:

1. **Removal of CDC Claim:** Removed Section 7.B.2 referencing clock-domain crossing (CDC) and asynchronous crypto-accelerator handshakes, as clock domain crossings are outside the single-clock synchronous NoC verification scope.
2. **Replacement of Hardware-Ready Terminology:** Replaced all occurrences of "Hardware-Ready Architectural Claims" with the precise standard: **"Python Reference-Model Agreement with Registered XSim Results"**.
3. **Classification of Python-Model Mutants:** Explicitly designated the 16 Step 6 mutants (**MUT-01 through MUT-16**) as **Python reference-model mutants** designed to test the vigilance and fail-closed properties of the Python security model.
4. **Delineation from RTL Mutation Evidence:** Clarified the boundary between Python reference-model test sensitivity and registered SystemVerilog RTL mutant jobs executed in Vivado/XSim (e.g. `rel_p7_gate_mut_bypass`, `s4_mut_absorb_zero_core`).

---

## 7. Next Steps & Prerequisites for Brief v2

Before proceeding with the new feature implementations outlined in Brief v2, the following engineering prerequisites are established:
1. S4 release package reconciliation is complete from Engineer 4's perspective.
2. Formal acceptance of increment S4 across the joint engineering team must occur.
3. Top-level integration of S4 bitstreams and project sources into `NOC_PQATTEST.xpr` remains to be finalized by the project lead.
4. All 231 repository unit and regression tests pass cleanly under `pytest`.

*Sign-Off:*  
**Engineer 4 (Python Verification Lead)**  
*November 5, 2026*

