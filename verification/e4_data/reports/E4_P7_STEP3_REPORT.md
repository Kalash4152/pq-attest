# E4 Report: PQ-Attest P7 Verification — Step 3: Authorization and Replay Reference Model

- **Engineer:** Engineer 4 (Python Verification Infrastructure)
- **Task:** Step 3 — Authorization and Replay Reference Model
- **Date:** 2026-11-03
- **Status:** PASS (30 / 30 Step 3 tests PASS, 162 / 162 overall repository tests PASS)

---

## 1. Executive Summary

In Step 3 of the P7 verification infrastructure re-baselining, we implemented an independent, stateful Python reference model for P7 security enforcement rules:
- Module: `verification/p7_security_model.py`
- Test Suite: `verification/tests/test_p7_security_model.py`
- Full Test Status: **162 / 162 PASS** across legacy and P7 verification suites (0 regressions).

The model faithfully mirrors the hardware security enforcement mechanisms specified across the dual-lane NoC RTL without collapsing distinct hardware fault domains into generic error codes.

---

## 2. Files Created and Modified

### Created Files:
1. `verification/p7_security_model.py`: Reference implementation of the 6-tile security state machine, peer replay state tracking, memory endpoint two-phase authorization enforcement, transaction tracker, and layer-specific rejection taxonomies.
2. `verification/tests/test_p7_security_model.py`: Comprehensive test suite containing 30 positive, negative, and mutation tests covering all 20 required verification scenarios.
3. `reports/E4_P7_STEP3_REPORT.md`: This Step 3 completion report.

### Modified Files:
- **None.** Step 1 files (`verification/p7_rtl_parser.py`, `verification/generated/p7_protocol_manifest.json`, `test_p7_rtl_parser.py`), Step 2 files (`verification/p7_packet_model.py`, `test_p7_packet_model.py`), and authoritative RTL files (`rtl/dual_lane/*`) remain completely untouched and unmodified.

---

## 3. Authoritative RTL References and Enforcement Rules

The model logic was derived directly from the following RTL source locations:

| Subsystem / Logic | RTL Source File | Line Range | Authoritative Hardware Behavior |
|---|---|---|---|
| **Tile Authorization & Gate** | `rtl/dual_lane/noc_attest_gate.sv` | 44–120 | Tile 4 (RoT) always authorized; Tile 3 attested via RoT GRANT with status=1; REVOKE or verifier failure/timeout de-authorizes; non-attestable tiles rejected with fault code 5. |
| **Replay & L2 Freshness** | `rtl/dual_lane/noc_l2_auth_p7.sv` | 265–295 | Checks order: MAC verification -> epoch match (reason 3) -> sequence monotonicity (reason 4). Zero sequence rejected. Sequence advances only on pass. |
| **Memory Endpoint Enforcement** | `rtl/dual_lane/pq_noc_subsystem_p7.sv` | 251–312 | Stand-in 1 KiB memory at Tile 2 (`0x2200_0000` to `0x2200_03FF`). Read checked at request HEAD; Read response checked at response HEAD (suppressed if revoked). Write checked at final data acceptance (no commit and suppressed response if revoked). |
| **Transaction Tracker** | `rtl/dual_lane/noc_network_interface_p7.sv` | 845–880 | 1-bit transaction tag (2 slots: tag 0, tag 1). Release on matching response type, destination, and tag. |
| **Ingress Filtering** | `rtl/dual_lane/noc_ingress_parser.sv` | 45–70 | Source address spoofing check (reason 9); header/length/VC check (reason 11). |

---

## 4. Architectural Highlights of the Reference Model

### A. 6-Tile Topology Authorization
- **Topology:**
  - Tile 0: CPU0 (Non-attestable, never authorized)
  - Tile 1: CPU1 (Non-attestable, never authorized)
  - Tile 2: MEMORY (Non-attestable, never authorized)
  - Tile 3: CRYPTO (Attestable, dynamic authorization)
  - Tile 4: RoT (Always authorized)
  - Tile 5: SPOOF (Non-attestable, never authorized)
- **Grant Validation:**
  - Tile 3 is authorized if and only if an authenticated `ATTEST_GRANT` message is received from issuer Tile 4 (RoT) with `status == 1`.
  - If issuer is not RoT -> `GateFaultReason.INVALID_ISSUER` (code 2).
  - If `status != 1` -> `GateFaultReason.INVALID_GRANT_STATUS` (code 3).
  - If target tile has `ATTESTABLE == 0` (Tiles 0, 1, 2, 5) -> `GateFaultReason.NON_ATTESTABLE_TILE` (code 5).
- **De-authorization Triggers:**
  - Valid `ATTEST_REVOKE` from RoT.
  - Verifier `trusted_fail` -> `GateFaultReason.TRUSTED_FAIL_OR_TIMEOUT` (code 4).
  - Verifier `trusted_timeout` -> `GateFaultReason.TRUSTED_FAIL_OR_TIMEOUT` (code 4).

### B. Control Direction Enforcement
Control messages are strictly point-to-point between RoT (Tile 4) and CRYPTO (Tile 3):
- `ATTEST_CHALLENGE`: Tile 4 -> Tile 3
- `ATTEST_RESPONSE`: Tile 3 -> Tile 4
- `ATTEST_GRANT`: Tile 4 -> Tile 3
- `ATTEST_REVOKE`: Tile 4 -> Tile 3
Any other source/destination pair for control traffic is rejected with `L2RejectReason.NON_PEER_CONTROL` (code 5).

### C. Replay Protection and Monotonicity
Maintained per-peer in `ReplayState`:
- **Boot Epoch:** Must match expected 80-bit epoch. Mismatches rejected with `L2RejectReason.EPOCH_MISMATCH` (code 3).
- **Sequence Number:**
  - Sequence `0` is strictly illegal and rejected with `L2RejectReason.SEQ_VIOLATION` (code 4).
  - Monotonicity: `seq > last_accepted_seq`. Decreasing or identical sequence rejected with `L2RejectReason.SEQ_VIOLATION` (code 4).
  - **State Invariance:** If any check fails, `last_accepted_seq` does **NOT** advance.

### D. Memory Endpoint Authorization and Two-Phase Enforcement
The reference model implements the stand-in 1 KiB memory at Tile 2 (`0x2200_0000` to `0x2200_03FF`):
1. **Window Alignment:** Address outside window or not 4-byte aligned returns `MemoryFaultReason.OUT_OF_WINDOW_ADDRESS` (code 13).
2. **Read Request (HEAD Check):**
   - Requester must be authorized at request HEAD.
   - If unauthorized: dropped at HEAD, returns `MemoryFaultReason.UNAUTHORIZED_ACCESS` (code 6), no response flit is generated.
3. **Read Response (HEAD Recheck / Suppression):**
   - Requester authorization is re-checked when read response HEAD is emitted.
   - If the requester was revoked between request and response: the response packet is **SUPPRESSED** (dropped), returning `MemoryFaultReason.UNAUTHORIZED_ACCESS` (code 6). Suppressed responses are never zero-filled or delivered.
4. **Write Request (Final Data Flit Acceptance Check):**
   - Authorization is checked when the final write data flit is accepted (`allowed_now = src_ok_now(mdest)`).
   - If the requester is unauthorized or revoked before the final flit: the write operation is aborted, the memory contents remain completely unmodified (no commit), and no write response is emitted, returning `MemoryFaultReason.UNAUTHORIZED_ACCESS` (code 6).

### E. Transaction Identity and Slot Management
- Implements 1-bit transaction tag tracking (`tag in {0, 1}`) with 2 available slots per source.
- Slot allocation succeeds only when an unused slot is available.
- Tag retirement requires an exact match on `(tag, expected_peer, expected_resp_type)`.
- Mismatched responses leave the pending slot active.
- Slot exhaustion raises `NIProtocolErrorReason.OUT_OF_TRANSACTION_SLOTS` (code 3).

---

## 5. Hardware Rejection Taxonomy Preserved

The reference model defines distinct enumerations matching hardware constants:

```python
class GateFaultReason(IntEnum):
    UNAUTHORIZED_ACCESS = 1
    INVALID_ISSUER = 2
    INVALID_GRANT_STATUS = 3
    TRUSTED_FAIL_OR_TIMEOUT = 4
    NON_ATTESTABLE_TILE = 5

class L2RejectReason(IntEnum):
    BAD_HEADER_LEN_PAD = 1
    MAC_MISMATCH = 2
    EPOCH_MISMATCH = 3
    SEQ_VIOLATION = 4
    NON_PEER_CONTROL = 5
    RATE_LIMIT = 6
    OCCUPANCY_DROP = 7
    PLAIN_CONTROL_DROP = 8

class IngressRejectReason(IntEnum):
    SRC_SPOOFING = 9
    INVALID_HDR_LEN_VC = 11

class MemoryFaultReason(IntEnum):
    UNAUTHORIZED_ACCESS = 6
    OUT_OF_WINDOW_ADDRESS = 13

class VerifierFailReason(IntEnum):
    TIMEOUT = 8
    BAD_HEADER_STATUS = 9
    FORMAT_OR_ABORT = 10
    MEASUREMENT_MISMATCH = 11
    TAG_MISMATCH = 12

class NIProtocolErrorReason(IntEnum):
    TAG_COLLISION = 1
    INVALID_RESPONSE_MATCH = 2
    OUT_OF_TRANSACTION_SLOTS = 3
```

---

## 6. Verification Coverage Matrix (20 Requirements)

All 20 specified verification scenarios plus mutation tests were implemented in `verification/tests/test_p7_security_model.py`:

| # | Requirement / Scenario | Test Method | Status |
|---|---|---|---|
| 1 | Valid GRANT authorizes tile 3 | `test_req1_valid_grant_authorizes_tile3` | PASS |
| 2 | Invalid GRANT (status != 1) does not authorize tile 3 | `test_req2_invalid_grant_status_does_not_authorize_tile3` | PASS |
| 3 | REVOKE removes authorization | `test_req3_revoke_removes_authorization` | PASS |
| 4 | Attestation failure removes authorization | `test_req4_attestation_failure_removes_authorization` | PASS |
| 5 | Timeout removes authorization | `test_req5_timeout_removes_authorization` | PASS |
| 6 | Tiles 0, 1, 2, and 5 cannot become authorized | `test_req6_non_attestable_tiles_cannot_become_authorized` | PASS |
| 7 | Invalid control-message direction | `test_req7_invalid_control_message_direction` | PASS |
| 8 | Correct boot epoch accepted | `test_req8_correct_boot_epoch` | PASS |
| 9 | Incorrect boot epoch rejected | `test_req9_incorrect_boot_epoch` | PASS |
| 10 | Sequence zero rejected | `test_req10_sequence_zero_rejected` | PASS |
| 11 | Repeated sequence rejected | `test_req11_repeated_sequence_rejected` | PASS |
| 12 | Decreasing sequence rejected | `test_req12_decreasing_sequence_rejected` | PASS |
| 13 | Increasing sequence accepted & advances state | `test_req13_increasing_sequence_advances_state` | PASS |
| 14 | Unauthorized memory read rejected at HEAD | `test_req14_unauthorized_memory_read` | PASS |
| 15 | Unauthorized memory write rejected before commit | `test_req15_unauthorized_memory_write` | PASS |
| 16 | Revocation between read request and response suppresses response | `test_req16_revocation_between_read_req_and_resp_suppressed` | PASS |
| 17 | Revocation between write request and final data word suppresses write | `test_req17_revocation_between_write_req_and_final_data` | PASS |
| 18 | Matching response terminates transaction slot | `test_req18_matching_response_terminates_transaction_slot` | PASS |
| 19 | Mismatched response leaves transaction pending | `test_req19_mismatched_response_leaves_transaction_pending` | PASS |
| 20 | Out-of-window memory access rejected | `test_req20_out_of_window_memory_access` | PASS |
| + | RoT invariant authorization | `test_rot_tile_always_authorized` | PASS |
| + | Unauthorized data traffic blocked at gate | `test_unauthorized_data_traffic_gate_blocked` | PASS |
| + | Non-attestable grant fault code 5 | `test_grant_to_non_attestable_tile_gate_fault` | PASS |
| + | Replay state does not advance on epoch mismatch | `test_replay_state_does_not_advance_on_epoch_failure` | PASS |
| + | Replay state does not advance on MAC failure | `test_replay_state_does_not_advance_on_mac_failure` | PASS |
| + | 2-slot exhaustion enforcement | `test_transaction_slot_exhaustion` | PASS |
| + | Double retirement prevention | `test_transaction_double_release_rejected` | PASS |
| + | End-to-end authorized write and read | `test_end_to_end_authorized_write_and_read` | PASS |
| + | Unaligned address rejection | `test_unaligned_memory_address_rejected` | PASS |
| + | Ingress source spoofing rejection | `test_ingress_source_spoofing` | PASS |

---

## 7. Cryptographic Equivalence Status

As required by project instructions:
- **`CRYPTO_EQUIVALENCE_STATUS: NOT VERIFIED`**
- The reference model verifies security state transitions, replay window tracking, and access enforcement.
- Cryptographic equivalence of the hardware KMAC128 absorption pipeline remains explicitly marked `NOT VERIFIED` until bit-exact hardware test vectors are co-simulated in subsequent verification steps.

---

## 8. Verification Regression Run

```text
============================= test session starts =============================
platform win32 -- Python 3.13.5, pytest-9.0.2, pluggy-1.6.0
collected 162 items

verification\test_generate_integration_scenarios.py .................    [ 10%]
verification\test_generate_noc_pair_matrix.py .........                  [ 16%]
verification\test_generate_noc_traffic.py .............                  [ 24%]
verification\test_p4_regression.py ...............                       [ 33%]
verification\test_sv_vector_bridge.py ........                           [ 38%]
verification\test_verify_noc_pair_matrix.py ...........                  [ 45%]
verification\test_verify_tile_map.py .....                               [ 48%]
verification\test_xy_route_oracle.py ................                    [ 58%]
verification\tests\test_crypto_compare.py .........                      [ 63%]
verification\tests\test_p7_packet_model.py ...................           [ 75%]
verification\tests\test_p7_rtl_parser.py ..........                      [ 81%]
verification\tests\test_p7_security_model.py ........................... [ 98%]
...                                                                      [100%]

============================= 162 passed in 2.77s =============================
```

---

## 9. Conclusion

Step 3 is complete. The authorization, replay, and memory enforcement rules of the P7 hardware have been captured into a clean, modular Python reference model with 100% test pass rate and full regression integrity.

