# PQ-Attest P7 Verification — Step 5 Report: Release-Aware End-to-End Integration Regression

**Date:** 2026-11-04  
**Author:** Engineer 4 (Python Verification Infrastructure)  
**Task:** Step 5 — Release-Aware End-to-End Integration Regression  
**Evidence Package:** `E4_P7_XSIM_20261103.zip` (`E4_P7_XSIM_20261103/`)  
**Run Identity:** `reports/dual_lane_10_20261103_140235_46039411`  
**Git Provenance:** Commit `19f06a0`, Release `f99e0d5`  
**Status Claims:**
- `HARDWARE_VALIDATED: NO`
- `FORMAL_PROOF: NO`
- `SOC_INTEGRATION_COMPLETE: NO`

---

## 1. Executive Summary

In Step 5, Engineer 4 constructed a unified P7 integration scenario suite that exercises the entire security lifecycle using the latest I-6/I-7 release architecture and the validated Vivado/XSim release evidence.

The integration suite models complete stateful flows across all subsystem layers:
- Reset and power-on state machine initialization
- Cryptographic attestation challenge and response handshakes
- Dual-lane NoC packet framing and L2 wire authentication
- Dynamic tile authorization, revoking, and fail-closed transitions
- Memory access enforcement with side-effect commit gating
- Replay protection with strict sequence monotonicity and epoch binding
- Verifier bounded BUSY retries (up to 3 retries, 4th fails closed)
- K-3 configuration length binding enforcement (16 / 16 words)
- Memory window relocation to `A[31:28] == 4'h2` (standard test address `0x2200_0100`)
- Subsystem fault-status register accounting and `trusted_clear` security boundary
- NI 2-slot transaction tag matching and slot exhaustion containment

All 20 required integration scenarios were modeled in `verification/p7_integration_scenarios.py`, mapped directly to authoritative release simulation logs, and verified with **20 / 20 Python PASS** and **20 / 20 RTL PASS**. The dedicated integration test suite (`verification/tests/test_p7_integration_scenarios.py`) passed **12 / 12 tests**, and the full repository regression suite now passes **197 / 197 tests** in under 4.0 seconds.

---

## 2. Reconciled Architecture & Security Properties

The integration framework strictly enforces the authoritative rules defined in the I-6 and I-7 contracts:

1. **Memory Window Relocation (`C-5`):**
   - Strictly enforced at `A[31:28] == 4'h2` (`0x2000_0000` to `0x2FFF_FFFF`).
   - Standard test address: `0x2200_0100` (Region 0x2, Tile 2, offset 0x0100).
   - Historical address `0x8200_0100` triggers fault reason 13 (`OUT_OF_WINDOW_ADDRESS`) and error reply `0x400`; memory remains completely unmodified.

2. **Bounded Verifier BUSY Retry (`C-1 / C-2`):**
   - Up to 3 retries (`MAX_BUSY_RETRIES = 3`) using the identical outstanding challenge (same epoch, nonce, and derived key; no new KDF).
   - A 4th consecutive BUSY response fails closed: `authorized = 0`, `REVOKE` issued, `fail_reason = 9` (`VERIFIER_STATUS_NOT_ONE`).
   - Any response status $\ne 1$ and $\ne 3$ (e.g. status 2, 5, 10) fails closed immediately (`fail_reason = 9`).

3. **K-3 Length Binding Enforcement:**
   - Constants provisioned in hardware: `K3_CONFIG_LEN = 16`, `K3_IMEM_LEN = 16`.
   - When `K3_ENFORCE = 1`, any valid challenge presenting `config_len != 16` or `imem_len != 16` is answered with status 5 (`MALFORMED`), increments `rejected_count`, and pulses `k3_fault` (fault reason 7: `K3_LENGTH_MISMATCH`). The verifier fails closed on status 5.

4. **Fault-Status Accounting & `trusted_clear` Boundary:**
   - Subsystem ports capture 13 distinct fault reasons.
   - `trusted_clear` input is strictly restricted to the RoT security domain; normal application packets and untrusted tiles have zero capability to clear sticky fault flags or counters.

5. **Synthesis Invariance of `TB_INJECT`:**
   - Parameter `TB_INJECT = 1` enables stimulus injection only within dedicated simulation benches (`tb_i7_sec`, etc.).
   - In production synthesis (`TB_INJECT = 0`), the injection hooks collapse into direct wires with zero logic or timing overhead.

---

## 3. 20-Flow Integration Scenario Coverage & Reconciliation

Each scenario defines an end-to-end stateful flow executed against the Python reference engine and mapped to Kalash's release simulation logs.

| Flow | Scenario ID | Name | Initial State | Expected Rejection / Outcome | Related RTL Evidence | Python Result | RTL Status |
|:---:|---|---|---|---|---|:---:|:---:|
| 1 | `INT_01` | `INITIAL_BOOT` | Cold boot / reset | RoT auth=1, Tile 3 auth=0, commits=0 | `rel_i7_full_chain`<br>(21 checks, 0 err) | **PASS** | **RTL PASS** |
| 2 | `INT_02` | `CHALLENGE_GENERATION` | Booted / Verifier idle | Challenge issued, cfg=16, imem=16 | `rel_i7_full_chain`<br>(21 checks, 0 err) | **PASS** | **RTL PASS** |
| 3 | `INT_03` | `ATTESTATION_RESPONSE_SUCCESS` | Challenge outstanding | Verifier outcome GRANT, meas/tag match | `rel_i7_full_chain`<br>(21 checks, 0 err) | **PASS** | **RTL PASS** |
| 4 | `INT_04` | `VALID_GRANT` | Verifier outcome GRANT | Gate accepts GRANT, Tile 3 auth=1 | `rel_s3_p7_c4`<br>(18 checks, 0 err) | **PASS** | **RTL PASS** |
| 5 | `INT_05` | `AUTHORIZED_MEM_READ` | Tile 3 authorized | Read at 0x2200_0100 succeeds | `rel_i7_full_chain`<br>(21 checks, 0 err) | **PASS** | **RTL PASS** |
| 6 | `INT_06` | `AUTHORIZED_MEM_WRITE` | Tile 3 authorized | Write commits (commits=1, data=CAFEBABE) | `rel_i7_sec`<br>(30 checks, 0 err) | **PASS** | **RTL PASS** |
| 7 | `INT_07` | `INVALID_MAC` | Tile 3 authorized | L2 rejects with `MAC_MISMATCH`, seq holds | `rel_s3_l2p7_equiv`<br>(2425 checks, 0 err) | **PASS** | **RTL PASS** |
| 8 | `INT_08` | `INCORRECT_EPOCH` | Boot epoch set | L2 rejects with `EPOCH_MISMATCH`, seq holds | `rel_s3_l2p7_equiv`<br>(2425 checks, 0 err) | **PASS** | **RTL PASS** |
| 9 | `INT_09` | `SEQUENCE_REPLAY` | Last accepted seq=1 | L2 rejects with `SEQUENCE_VIOLATION`, seq holds | `rel_s3_l2p7_equiv`<br>(2425 checks, 0 err) | **PASS** | **RTL PASS** |
| 10 | `INT_10` | `INVALID_GRANT` | Target Tile 0 (plain) | Gate rejects with `NON_ATTESTABLE_TILE` | `rel_i6_p7_refuse_grant`<br>(12 checks, 0 err) | **PASS** | **RTL PASS** |
| 11 | `INT_11` | `REVOKE` | Tile 3 authorized | Gate accepts REVOKE, Tile 3 auth=0 | `rel_s3_p7_c4`<br>(18 checks, 0 err) | **PASS** | **RTL PASS** |
| 12 | `INT_12` | `UNAUTHORIZED_MEM_ACCESS_AFTER_REVOKE` | Tile 3 revoked | Blocked at gate, commits unmodified (1) | `rel_p7_gate_data`<br>(4 checks, 0 err) | **PASS** | **RTL PASS** |
| 13 | `INT_13` | `SPOOFED_TILE_CONTROL_ATTEMPT` | Tile 5 (SPOOF) | Ingress quarantine drops (reason 9) | `rel_i6_p7_ingress`<br>(39 checks, 0 err) | **PASS** | **RTL PASS** |
| 14 | `INT_14` | `BUSY_RETRY_EVENTUAL_SUCCESS` | Verifier retry=0 | Retried twice with same challenge; 3rd grants | `dl_rel_i6_retry`<br>(24 checks, 0 err) | **PASS** | **RTL PASS** |
| 15 | `INT_15` | `FOURTH_BUSY_FAIL_CLOSED` | Verifier retry=3 | 4th BUSY fails closed (reason 9, REVOKE) | `dl_rel_i6_retry`<br>(24 checks, 0 err) | **PASS** | **RTL PASS** |
| 16 | `INT_16` | `K3_CONFIG_LENGTH_MISMATCH` | Challenge cfg_len=15 | Status 5 MALFORMED, fault 7 K3 mismatch | `rel_i7_sec`<br>(30 checks, 0 err) | **PASS** | **RTL PASS** |
| 17 | `INT_17` | `MEMORY_WINDOW_REJECTION` | Address 0x8200_0100 | Rejected with fault 13, reply 0x400 | `rel_i7_sec`<br>(30 checks, 0 err) | **PASS** | **RTL PASS** |
| 18 | `INT_18` | `TRANSACTION_TAG_MISMATCH` | Slot 0 active | Mismatched src/type rejected, slot held | `rel_n81p7_ni_t0w16`<br>(126 checks, 0 err) | **PASS** | **RTL PASS** |
| 19 | `INT_19` | `SLOT_EXHAUSTION` | Slots 0 & 1 active | 3rd request rejected with backpressure | `rel_n81p7_ni_t0w16`<br>(126 checks, 0 err) | **PASS** | **RTL PASS** |
| 20 | `INT_20` | `RECOVERY_AFTER_NEW_ATTESTATION` | Tile 3 revoked | Re-challenge + genuine response grants; write ok | `rel_i7_sec`<br>(30 checks, 0 err) | **PASS** | **RTL PASS** |

---

## 4. Key Security Invariants Verified

### A. Memory Non-Mutability Under Invalid Operations
The memory endpoint state machine guarantees that under all invalid conditions (unauthorized tile, post-revocation request, illegal memory window, or unaligned address), `memory_commits` remains strictly unchanged and buffer memory contains zero partial or corrupted writes. Verified in `test_invalid_operations_do_not_change_memory`.

### B. Strict Replay Monotonicity
The L2 replay tracker validates the strict check sequence:
$$\text{MAC Verified} \longrightarrow \text{Epoch Match} \longrightarrow \text{Sequence} > \text{Last Accepted}$$
Sequence zero is unconditionally rejected. If any check fails, the packet is discarded and `last_accepted_seq` does not advance. Verified in `test_replay_state_monotonicity`.

### C. Revocation Containment
Once an authenticated `REVOKE` is processed by the gate at Tile 3, both read requests and write requests are blocked at the gate. Furthermore, if revocation occurs while a read request is in-flight, response delivery is suppressed at the response HEAD offer; if revocation occurs while write data is streaming, side-effect commit is suppressed at final data word acceptance. Verified in `test_revoke_prevents_subsequent_access`.

### D. BUSY Retries and Fail-Closed Boundary
BUSY retries preserve exact challenge parameters ($\text{epoch}, \text{nonce}, \text{cfg\_len}, \text{imem\_len}$) across up to 3 retry attempts. The 4th consecutive BUSY response transitions the verifier to `failed = True` and asserts `fail_reason = 9`, issuing an automatic REVOKE and preventing unauthorized access. Verified in `test_busy_retries_preserve_challenge_identity` and `test_fourth_busy_fails_closed`.

### E. Recovery Authorization Boundary
After a revocation, access cannot be restored through invalid grants, unauthorized tile spoofing, or corrupted packets. Tile authorization can be re-established only through a complete, genuine attestation challenge/response cycle followed by an authenticated GRANT from RoT (Tile 4). Verified in `test_recovery_only_through_valid_authorization`.

---

## 5. Verification Test Suite Results

The dedicated integration test suite and full repository regression were executed using pytest:

### Integration Suite (`test_p7_integration_scenarios.py`)
```
verification/tests/test_p7_integration_scenarios.py::test_all_20_scenarios_execute_and_pass PASSED
verification/tests/test_p7_integration_scenarios.py::test_invalid_operations_do_not_change_memory PASSED
verification/tests/test_p7_integration_scenarios.py::test_replay_state_monotonicity PASSED
verification/tests/test_p7_integration_scenarios.py::test_revoke_prevents_subsequent_access PASSED
verification/tests/test_p7_integration_scenarios.py::test_busy_retries_preserve_challenge_identity PASSED
verification/tests/test_p7_integration_scenarios.py::test_fourth_busy_fails_closed PASSED
verification/tests/test_p7_integration_scenarios.py::test_memory_window_boundaries PASSED
verification/tests/test_p7_integration_scenarios.py::test_transaction_tag_matching PASSED
verification/tests/test_p7_integration_scenarios.py::test_recovery_only_through_valid_authorization PASSED
verification/tests/test_p7_integration_scenarios.py::test_negative_and_mutation_controls PASSED
verification/tests/test_p7_integration_scenarios.py::test_manifest_generation PASSED
verification/tests/test_p7_integration_scenarios.py::test_historical_integrity PASSED

============================= 12 passed in 0.33s ==============================
```

### Full Repository Regression Suite
```
collected 197 items

verification\test_generate_integration_scenarios.py .................    [  8%]
verification\test_generate_noc_pair_matrix.py .........                  [ 13%]
verification\test_generate_noc_traffic.py .............                  [ 19%]
verification\test_p4_regression.py ...............                       [ 27%]
verification\test_sv_vector_bridge.py ........                           [ 31%]
verification\test_verify_noc_pair_matrix.py ...........                  [ 37%]
verification\test_verify_tile_map.py .....                               [ 39%]
verification\test_xy_route_oracle.py ................                    [ 47%]
verification\tests\test_crypto_compare.py .........                      [ 52%]
verification\tests\test_p7_differential.py ...........                   [ 57%]
verification\tests\test_p7_integration_scenarios.py ............         [ 63%]
verification\tests\test_p7_packet_model.py ...................           [ 73%]
verification\tests\test_p7_release_evidence.py ............              [ 79%]
verification\tests\test_p7_rtl_parser.py ..........                      [ 84%]
verification\tests\test_p7_security_model.py ........................... [ 98%]
...                                                                      [100%]

============================= 197 passed in 3.97s =============================
```

---

## 6. Deliverables Inventory

| File | Purpose | Status |
|---|---|---|
| [`verification/p7_integration_scenarios.py`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/p7_integration_scenarios.py) | Unified 20-scenario stateful integration engine and runner | Complete |
| [`verification/tests/test_p7_integration_scenarios.py`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/tests/test_p7_integration_scenarios.py) | Comprehensive pytest test suite (12 tests) | 12 / 12 PASS |
| [`verification/generated/p7_integration_scenarios.json`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/generated/p7_integration_scenarios.json) | Complete JSON manifest of all 20 stateful scenarios and metadata | Generated |
| [`reports/E4_P7_STEP5_REPORT.md`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/reports/E4_P7_STEP5_REPORT.md) | Formal engineering report documenting Step 5 results | Complete |

---

## 7. Verification Boundaries & Repository Integrity

1. **Hardware Validation & Proof Limits:**
   - Python simulation and XSim differential verification do not constitute board hardware validation (`HARDWARE_VALIDATED: NO`).
   - Formal mathematical verification of all state spaces has not been performed (`FORMAL_PROOF: NO`).
   - Complete SoC integration with external processor complexes has not been undertaken (`SOC_INTEGRATION_COMPLETE: NO`).
2. **Repository Integrity:**
   - All RTL source files under `rtl/dual_lane/` remain completely untouched and clean.
   - All historical Step 1 through Step 4B reports and vector files remain untouched and preserved.

