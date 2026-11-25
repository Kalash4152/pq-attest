# PQ-Attest Engineer 4 — F1: Pinned KMAC Reference Correction Report

**Date:** 2026-11-06  
**Author:** Engineer 4 (Python Verification Team)  
**Task:** F1 (Pinned KMAC Reference Correction)  
**Status:** COMPLETE (Cryptographic Reference Replaced & Validated)  
**Target Architecture:** PQ-Attest P7 Dual-Lane Security Infrastructure  
**Git HEAD Revision:** `b62b78de2005d67539a9941d9a9c65bb4497db5f`  

---

## 1. Executive Summary & Objective

In accordance with Kalash's November 6 architectural review, Engineer 4's Python verification infrastructure has been updated to disconnect from the older, demoted reference implementation (`software/kmac128_ref.py`) and bind exclusively to the authoritative teammate reference:

```
software/pq_attest_final/PQ_Attest/software/kmac128_ref.py
```

This authoritative reference derives from the pinned teammate package `Pq_Attest_final.zip` (SHA-256: `047bb5a981050f11a572a60e850f7c7511ff5d636f7903c6a8d239891003c6a0`).

A dedicated, isolated adapter module (`verification/p7_kmac_adapter.py`) was introduced to govern all cryptographic calls from the packet model, differential verification suite, vector comparator, and unit tests. The adapter validates the cryptographic identity of the teammate reference, prevents bytecode writing into the immutable source tree, and strictly forbids silent fallback to the demoted reference.

---

## 2. Cryptographic Reference Provenance

### 2.1 File Hashes and Provenance

| Role | Repository Path | SHA-256 Digest | Size (Bytes) | Status |
|---|---|---|---|---|
| **Authoritative KMAC Reference** | `software/pq_attest_final/PQ_Attest/software/kmac128_ref.py` | `ac8076e665b6b838c58b9b3458b6e3cd16101fbab4dc0d90fbc78f90497ce394` | 10,861 | **PINNED_AUTHORITATIVE** |
| **Authoritative Keccak Companion** | `software/pq_attest_final/PQ_Attest/software/keccak_ref.py` | `80cbd3a8c2cc73065ab153be7ba21c204c5d529f3951c1f7187ea9580baa1824` | 5,017 | **PINNED_AUTHORITATIVE** |
| **Source Archive Package** | `Pq_Attest_final.zip` (registered in vectors) | `047bb5a981050f11a572a60e850f7c7511ff5d636f7903c6a8d239891003c6a0` | — | **AUTHORITATIVE_SOURCE** |
| **Demoted Reference File** | `software/kmac128_ref.py` | `73d9b064b6b546fede85ed182259d7ed33f8e0d9ec512abee57db6827b5bde62` | 7,436 | **DEMOTED (Supplementary KAT Only)** |

### 2.2 Preserved Demoted Reference Analysis
The demoted file `software/kmac128_ref.py` was retained in the repository in accordance with Section 2 instructions because it serves as an offline supplementary KAT test file. However, it is no longer in the active verification import path and any attempt to load it via `p7_kmac_adapter` raises a fatal `ReferenceIdentityError`.

---

## 3. Adapter Architecture & Import Locations

### 3.1 Need for Adapter
An adapter (`verification/p7_kmac_adapter.py`) was implemented because:
1. **Isolated Path Resolution:** The authoritative teammate reference relies on companion modules (`keccak_ref`) located within its own folder structure. The adapter dynamically ensures that module imports resolve strictly within `pq_attest_final` rather than picking up conflicting top-level modules.
2. **Bytecode Protection:** The adapter sets `sys.dont_write_bytecode = True` so that `.pyc` files are not created inside immutable reference trees.
3. **Cryptographic Identity Enforcement:** On load, the adapter verifies the exact SHA-256 hash of the target module (`ac8076e6...`), guaranteeing that neither corrupted files nor the demoted reference (`73d9b064...`) can ever be loaded.
4. **Strict Type & Boundary Checking:** It adds strict argument checking (ensuring `bytes` keys, positive integer lengths, non-negative lengths) required by test suites.

### 3.2 Updated Import Locations

The following verification infrastructure files were updated to replace `from software.kmac128_ref import kmac128`:

1. [`verification/p7_packet_model.py`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/p7_packet_model.py):
   - Old: `from software.kmac128_ref import kmac128`
   - New: `from verification.p7_kmac_adapter import kmac128`
2. [`verification/p7_differential.py`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/p7_differential.py):
   - Old: `from software.kmac128_ref import kmac128`
   - New: `from verification.p7_kmac_adapter import kmac128`
3. [`verification/crypto_compare.py`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/crypto_compare.py):
   - Added: `from verification.p7_kmac_adapter import kmac128, derive_tile_key, get_kmac_reference_metadata`
4. [`verification/tests/test_p7_differential.py`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/tests/test_p7_differential.py):
   - Added explicit assertion `test_authoritative_kmac_reference_binding()` confirming active binding to the authoritative reference.

---

## 4. Cryptographic Equivalence & KAT Verification

The authoritative teammate reference was validated against both international standards and RTL simulation outputs:

### 4.1 NIST SP 800-185 KMAC128 Sample Vectors
- **Sample 1** (Key = `0x40..0x5F`, Msg = `0x00010203`, Custom = `""`, OutLen = 32):  
  Output: `e5780b0d3ea6f7d3a429c5706aa43a00fadbd7d49628839e3187243f456ee14e` (**PASS**)
- **Sample 2** (Key = `0x40..0x5F`, Msg = `0x00010203`, Custom = `"My Tagged Application"`, OutLen = 32):  
  Output: `3b1fba963cd8b0b59e8c1a6d71888b7143651af8ba0a7070c0979e2811324aa5` (**PASS**)
- **Sample 3** (Key = `0x40..0x5F`, Msg = 200-byte increment, Custom = `"My Tagged Application"`, OutLen = 32):  
  Output: `1f5b4e6cca02209e0dcb5ca635b89a15e271ecc760071dfd805faa38f9729230` (**PASS**)

### 4.2 RTL Testbench Known-Answer Tests (6 TB Vectors)
All 6 RTL testbench vectors from `kmac_tb.sv` and `logs/s3_kmac_2026-09-23.log` were verified bit-exact:
- `TB_TEST_1` (Empty message, empty custom): `0x973ad9b322481f9e...` (**MATCHED**)
- `TB_TEST_2` (16-byte message, empty custom): `0x350e8bd95e6df79c...` (**MATCHED**)
- `TB_TEST_3` (16-byte message, "Custom"): `0x29b7bd43a1df5e4f...` (**MATCHED**)
- `TB_TEST_4` (Maximum v1 lengths): `0x556c806a871cc489...` (**MATCHED**)
- `TB_TEST_5` (16-byte key boundary): `0xf1501b0abeb87226...` (**MATCHED**)
- `TB_TEST_6_L128` (L=128 KAT, 16-byte output): `0x1f2915cfef11bdfabebf8e536b71fa30` (**MATCHED**)

### 4.3 P7 Protocol Packet MAC & Domain Separation
- Wire customization string `b"NOC-L2-AUTH-v1"` confirmed to produce distinct cryptographic tags from default customization.
- Byte ordering verified little-endian across all four 32-bit flits ($4 \times 32 = 128$ bits).

---

## 5. Regression and Test Results

### 5.1 Focused KMAC Tests
- `verification/tests/test_p7_kmac_adapter.py`: **9 passed in 0.22s**
- `verification/tests/test_p7_differential.py`: **12 passed in 0.35s**
- `verification/tests/test_p7_packet_model.py`: **19 passed in 0.18s**

### 5.2 Full Pytest Suite
Command:
```bash
python -m pytest verification -q
```
Result: **269 passed in 8.01s** (0 failed, 0 skipped).  
Delta: +10 tests over Step 3 (9 new in `test_p7_kmac_adapter.py`, 1 new binding check in `test_p7_differential.py`).

### 5.3 S4 Validation-Only Regression
Command:
```bash
python verification/p7_regression.py --validate-only --baseline s4
```
Result: **PASS** (6 passed, 0 failed, 9 skipped).

### 5.4 November 3 Validation-Only Regression
Command:
```bash
python verification/p7_regression.py --validate-only --baseline nov3
```
Result: **PASS** (6 passed, 0 failed, 9 skipped).

### 5.5 Full Pipeline Regression
Command:
```bash
python verification/p7_regression.py --full
```
Result: **15 / 15 Stages PASS** (0 failed, 0 skipped, 269/269 pytest passed, 0 historical file hash modifications).

---

## 6. Generated Artifacts

- [`verification/p7_kmac_adapter.py`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/p7_kmac_adapter.py): Authoritative KMAC reference adapter.
- [`verification/tests/test_p7_kmac_adapter.py`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/tests/test_p7_kmac_adapter.py): Unit test suite for KMAC reference binding and KATs.
- [`verification/generated/p7_kmac_reference_provenance.json`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/generated/p7_kmac_reference_provenance.json): Machine-readable provenance and self-test manifest.
- [`reports/E4_P7_F1_KMAC_REFERENCE_CORRECTION.md`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/reports/E4_P7_F1_KMAC_REFERENCE_CORRECTION.md): This report.

---

## 7. Remaining Limitations & Verification Classification

> **Python cryptographic reference correction and test validation. This does not constitute new RTL simulation, formal proof or hardware validation.**

- The Python reference model reproduces NIST SP 800-185 KMAC128 and RTL testbench outputs bit-for-bit.
- Software reference equivalence does not eliminate physical hardware clock domain crossing hazards, synthesis timing violations, or power/area tradeoffs.
- No RTL files were modified in this task (`rtl/dual_lane` remains untouched).

