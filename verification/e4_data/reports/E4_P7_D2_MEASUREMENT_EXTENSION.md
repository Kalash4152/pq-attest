# PQ-Attest Engineer 4 — D2: 64-Byte IMEM Measurement Extension

**Date:** November 6, 2026  
**Author:** Engineer 4 (Antigravity Verification Pair)  
**Status:** COMPLETED & VERIFIED  
**Target:** D2: 64-Byte IMEM Measurement Window Verification & Traceability  

---

## 1. Executive Summary

This report documents the verification and extension of the Engineer 4 Python verification infrastructure to model and validate the **D2 measurement window requirement** in the merged PQ-Attest architecture.

The D2 specification expands the instruction memory (IMEM) measurement window from the historical 16-byte window to a complete **64-byte window**, bound to the K-3 16-byte configuration and 7-byte Tile ID.

### Key Architectural Metrics:
- **Tile ID length:** 7 bytes ASCII (e.g., `b"TILE_01"`).
- **K-3 Configuration length:** 16 bytes.
- **D2 IMEM measurement length:** 64 bytes (covering bytes 0 through 63).
- **Total measurement message length:** $7 + 16 + 64 = 87\text{ bytes}$.
- **Single-block bound:** $87 \le 135\text{ bytes}$ ($\text{sha3\_pkg::RATE\_BYTES} - 1 = 135$).
- **Hash function:** SHA3-256 (rate $r = 136$ bytes / 1088 bits; digest $d = 32$ bytes / 256 bits).
- **Keccak-f[1600] permutations:** Exactly 1 permutation required.
- **Byte 16..63 sensitivity:** 48/48 (100.0%) single-byte mutations verified to cause measurement divergence.

---

## 2. Source of Truth & Provenance

All reference models, differential test vectors, and golden digests were generated directly from the authoritative teammate reference:

- **Script:** `software/pq_attest_final/PQ_Attest/software/measurement_ref.py`  
- **Source Package:** `Pq_Attest_final.zip`  
- **Package SHA-256:** `047bb5a981050f11a572a60e850f7c7511ff5d636f7903c6a8d239891003c6a0`  
- **RTL Specifications:** `NOC_PQATTEST.srcs/sources_1/new/pq_measurement.sv` and `pq_measurement_pkg.sv`  

Cross-checks between the teammate reference and Python's standard `hashlib.sha3_256` confirmed 100% identical outputs across all vectors and sensitivity sweeps.

---

## 3. Mathematical & Algorithmic Formulation

The measurement digest $M$ is defined as:
$$M = \text{SHA3-256}(\text{TILE\_ID} \parallel \text{CONFIG} \parallel \text{IMEM})$$

Where:
- Raw byte concatenation is used with no delimiters, length prefixes, or separators.
- Byte ordering on RTL interfaces follows little-endian byte slicing: byte $i$ is at $[i \times 8 +: 8]$.
- In SHA3-256 with rate $r = 136$ bytes:
  - Input message length: $L = 87$ bytes.
  - Padding `pad10*1` appends domain separator byte `0x06` at byte 87, zero bytes for bytes 88..134, and delimiter byte `0x80` at byte 135.
  - The padded block occupies exactly 136 bytes, which absorbs entirely in **block 1**.
  - Permutation count: Exactly 1 call to Keccak-f[1600].
  - Multi-block absorption is unreachable because $87 \le 135$.

---

## 4. Authoritative Test Vectors (`vectors/d2_k3_64.json` & `d2_k3_64.svh`)

Twelve deterministic test vectors were generated and verified:

| Vector ID | Category | Tile ID | Config Length | IMEM Length | Total Length | SHA3-256 Digest (Printed Big-Endian) |
|:---|:---|:---:|:---:|:---:|:---:|:---|
| `V01_STD_TILE01` | Standard | `TILE_01` | 16 B | 64 B | 87 B | `5d44a067029ba92ba45ad0a87b229c4480e8d6cda2756f907afa8715ddc27ccb` |
| `V02_SENS_BYTE16` | Sensitivity (Byte 16) | `TILE_01` | 16 B | 64 B | 87 B | `6d90ae6252604c64839e5e32ce85383b477348d93b53e1a815b48f1006349d6c` |
| `V03_SENS_BYTE63` | Sensitivity (Byte 63) | `TILE_01` | 16 B | 64 B | 87 B | `174631d37e4c8ccf46935622ab9328d22e61f378ec6090d9720e65521f055e8e` |
| `V04_ALL_ZEROS_T00` | All Zeros | `TILE_00` | 16 B | 64 B | 87 B | `d8c85527028563cf8df9dbacccc37e692c195a11e52dc2438154463fe1aa34a6` |
| `V05_ALL_ZEROS_T01` | All Zeros | `TILE_01` | 16 B | 64 B | 87 B | `2bae00fb5e912aae2390a6f0769bb89b4a01bf7831f0ae62b7fed46f5ddaee7e` |
| `V06_ALL_ONES_T01` | All Ones (0xFF) | `TILE_01` | 16 B | 64 B | 87 B | `fe0b13a22f280b67231659ef3634ee0f2310d3a0ed84cfe9e390b3db4c369d48` |
| `V07_TILE_00` | Multi-Tile | `TILE_00` | 16 B | 64 B | 87 B | `78e7865ffba63d379e73bd8e34e9dbf82347ec5814365f3e19877fc00df4c6ef` |
| `V08_TILE_01` | Multi-Tile | `TILE_01` | 16 B | 64 B | 87 B | `5d44a067029ba92ba45ad0a87b229c4480e8d6cda2756f907afa8715ddc27ccb` |
| `V09_TILE_02` | Multi-Tile | `TILE_02` | 16 B | 64 B | 87 B | `9949649e3764d9d8fff262b86f9b3f9afa6acc1e14e5cfb9caef607c61cf9251` |
| `V10_TILE_03` | Multi-Tile | `TILE_03` | 16 B | 64 B | 87 B | `4fab4342988a1df1573f5e9db358af2c9a0d29de9dc39630660e5ff33db92e74` |
| `V11_TILE_04` | Multi-Tile | `TILE_04` | 16 B | 64 B | 87 B | `fa93548aea3adc4fab4b6cc27df2e4b9b2e6f4cdec50245eb7be4f0fd19c4059` |
| `V12_TILE_05` | Multi-Tile | `TILE_05` | 16 B | 64 B | 87 B | `728a503e5a6838ade3229e73caf46fae9687e807450acfbee802c9544454a84a` |

### SystemVerilog Header (`vectors/d2_k3_64.svh`):
- Formatted with RTL byte order: byte 0 at `[7:0]` (LSB end) to enable direct bitwise equality (`===`) in testbenches without runtime byte swapping.
- Includes macro constants, vector count (`D2_NUM_VECTORS = 12`), dimension constants (`D2_TOTAL_BYTES = 87`), vector arrays (`D2_TILE_IDS`, `D2_CONFIGS`, `D2_IMEMS`, `D2_EXPECTED_MEASUREMENTS`), and vector index decoding function `d2_vector_name()`.

---

## 5. Window Coverage & Sensitivity Analysis (Bytes 16..63)

To demonstrate that the expanded IMEM window (bytes 16..63) is actively incorporated into the measurement digest:
1. **Byte 16 Sensitivity Check:**
   - Byte 16 is the first byte beyond the historical 16-byte window (bytes 0..15).
   - Inverting byte 16 (`0x20 -> 0xDF`) changed digest from `5d44a067...` to `6d90ae62...`.
2. **Byte 63 Sensitivity Check:**
   - Byte 63 is the final byte of the 64-byte window.
   - Inverting byte 63 (`0x4F -> 0xB0`) changed digest from `5d44a067...` to `174631d3...`.
3. **Exhaustive Sensitivity Sweep (48/48 bytes):**
   - Every individual byte from index 16 to 63 was mutated in isolation.
   - **Result:** 48/48 single-byte mutations (100.0%) produced distinct, divergent SHA3-256 digests.
   - Zero collisions or blind spots detected across the entire expanded window.

---

## 6. Historical Continuity & Non-Equivalence

We compared the D2 64-byte measurement against the historical 16-byte measurement using the same prefix:

| Measurement Input | Components | Total Length | SHA3-256 Digest |
|:---|:---|:---:|:---|
| **Historical V01** | `TILE_01` (7 B) + Config (16 B) + IMEM[0..15] (16 B) | 39 B | `959b61960366c705b889e2c09ffaead296e296475f32a610732ab9eac293182a` |
| **D2 V01** | `TILE_01` (7 B) + Config (16 B) + IMEM[0..63] (64 B) | 87 B | `5d44a067029ba92ba45ad0a87b229c4480e8d6cda2756f907afa8715ddc27ccb` |
| **Zero-Padded 64B** | `TILE_01` (7 B) + Config (16 B) + IMEM[0..15] + $48 \times \text{0x00}$ | 87 B | `448651feffaeaf36f01df22205fe2df0ad19a777651a26ae99583b4fa8f7dc53` |

**Findings:**
- Historical 39-byte measurement matches golden `M01` in `software/measurement_ref.py` and `pq_measurement_tb.sv`.
- The expanded D2 measurement produces a completely distinct hash (`5d44a067...`), confirming that 64-byte measurement enforcement cannot be spoofed by replay of truncated 16-byte historical measurements or simple zero padding.

---

## 7. Requirement Traceability Matrix Update

The requirement matrix in `verification/p7_coverage_audit.py` was extended to track the D2 architectural requirement:

- **Requirement ID:** `REQ-D2-IMEM-64`
- **Group:** Group E: Verifier and I-6/I-7
- **Statement:** *"IMEM bytes 16..63 are included in the measurement (87-byte total input: 7-byte Tile ID + 16-byte Config + 64-byte IMEM)."*
- **Python Implementation:** `verification/p7_d2_measurement.py:compute_d2_measurement`
- **Test Mapping:** `verification/tests/test_p7_d2_measurement.py::test_imem_window_sensitivity_byte16_to_63_exhaustive`
- **RTL Evidence Reference:** `vectors/d2_k3_64.json & vectors/d2_k3_64.svh (teammate reference M-F1 R8)`
- **Status:** `COVERED`

### Updated Matrix Statistics:
- **Total Requirements:** 58 (expanded from 57).
- **Covered Requirements:** 58 / 58 (100.0%).
- **Group Breakdown:**
  - Group A (Packet and Protocol): 11 / 11 (100.0%)
  - Group B (Authentication and Freshness): 8 / 8 (100.0%)
  - Group C (Authorization): 9 / 9 (100.0%)
  - Group D (Memory Enforcement): 9 / 9 (100.0%)
  - Group E (Verifier and I-6/I-7): 12 / 12 (100.0%) [including `REQ-D2-IMEM-64`]
  - Group F (NI Transactions): 9 / 9 (100.0%)

---

## 8. Verification Results & Regression Execution

### 1. Dedicated D2 Pytest Suite (`verification/tests/test_p7_d2_measurement.py`):
```
collected 18 items
test_measurement_input_length_exact_87_bytes               PASSED
test_measurement_within_single_block_bound                PASSED
test_keccak_permutation_count_exactly_one                 PASSED
test_teammate_reference_availability_and_provenance       PASSED
test_teammate_reference_vs_hashlib_agreement              PASSED
test_imem_byte16_sensitivity                               PASSED
test_imem_byte63_sensitivity                               PASSED
test_imem_window_sensitivity_byte16_to_63_exhaustive       PASSED
test_vectors_d2_k3_64_json_integrity                      PASSED
test_vectors_d2_k3_64_svh_consistency                     PASSED
test_boundary_config_length_not_16_rejected               PASSED
test_boundary_imem_length_not_64_rejected                 PASSED
test_boundary_input_length_exceeding_135_rejected         PASSED
test_historical_16b_vs_d2_64b_measurement_non_equivalence PASSED
test_zero_padded_vs_d2_measurement_non_equivalence        PASSED
test_multi_tile_measurements_are_all_distinct             PASSED
test_generated_p7_d2_measurement_vectors_artifact         PASSED
test_generated_p7_d2_measurement_coverage_artifact        PASSED
============================== 18 passed in 0.37s ==============================
```

### 2. Full Regression Execution (`python verification/p7_regression.py --full`):
- **Stage 01 (ENV_DISCOVERY):** PASS (Python 3.13.5, win32).
- **Stage 02 (BASELINE_SNAPSHOT):** PASS (40 protected baseline files).
- **Stage 03 (PROTOCOL_EXTRACTION):** PASS.
- **Stage 04 (PROTOCOL_VALIDATION):** PASS.
- **Stage 05 (PACKET_MODEL_REGRESSION):** PASS (19 tests).
- **Stage 06 (SECURITY_MODEL_REGRESSION):** PASS (30 tests).
- **Stage 07 (DIFFERENTIAL_VECTORS):** PASS (12 tests).
- **Stage 08 (RELEASE_EVIDENCE_RECONCILE):** PASS (12 tests).
- **Stage 09 (INTEGRATION_SCENARIOS):** PASS (12 tests).
- **Stage 10 (COVERAGE_AUDIT):** PASS (4 tests, 58/58 requirements).
- **Stage 11 (MUTATION_ANALYSIS):** PASS (12 tests, 16/16 mutants killed).
- **Stage 12 (FULL_PYTEST):** PASS (**341 passed** in 20.7s).
- **Stage 13 (ARTIFACT_VALIDATION):** PASS (8/8 generated artifacts validated).
- **Stage 14 (HISTORICAL_INTEGRITY):** PASS (Zero protected files modified).
- **Stage 15 (FINAL_SUMMARY):** PASS.
- **Result:** **15 / 15 STAGES PASS**.

---

## 9. Deliverables Manifest

| Deliverable Path | Description | Status |
|:---|:---|:---:|
| `vectors/d2_k3_64.json` | 12 golden test vectors with parameters and hex digests | CREATED |
| `vectors/d2_k3_64.svh` | SystemVerilog header format with RTL byte-order literals | CREATED |
| `verification/p7_d2_measurement.py` | Reference model, vector generator & sensitivity engine | CREATED |
| `verification/tests/test_p7_d2_measurement.py` | 18 unit, boundary, sensitivity & integrity tests | CREATED |
| `verification/generated/p7_d2_measurement_vectors.json` | Generated vector manifest | GENERATED |
| `verification/generated/p7_d2_measurement_coverage.json` | Generated coverage & sensitivity report | GENERATED |
| `verification/p7_coverage_audit.py` | Updated RTM with `REQ-D2-IMEM-64` (58 requirements) | UPDATED |
| `verification/tests/test_p7_coverage_audit.py` | Updated unit tests asserting 58 requirements | UPDATED |
| `verification/p7_regression.py` | Updated artifact checks, Stage 10 & Stage 13 | UPDATED |
| `reports/E4_P7_D2_MEASUREMENT_EXTENSION.md` | Comprehensive engineering handoff report | COMPLETED |

---

## 10. Required Classification Disclosure

> **Classification Statement:**  
> Python measurement reference-model and differential-vector validation against the authoritative teammate reference. Existing registered RTL evidence is distinguished from newly generated Python results. This does not constitute new RTL simulation, formal proof or hardware validation.

---

## 11. Integrity Confirmation & Clean Stop

- **RTL Integrity:** Confirmed `git diff rtl/dual_lane` is completely clean (zero modifications to SystemVerilog sources).
- **Acceptance Harness Integrity:** Kalash's registered `e4_verification` acceptance harness was untouched.
- **Clean Stop:** Work concludes strictly at D2. Subsequent Brief v2 tasks have not been initiated.

