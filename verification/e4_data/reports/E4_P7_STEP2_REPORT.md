# E4 Report: PQ-Attest P7 Verification — Step 2: MAC Framing and Packet Reference Model

- **Engineer:** Engineer 4 (Python Verification Infrastructure)
- **Task:** Step 2 — MAC Framing and Packet Reference Model
- **Date:** 2026-11-03
- **Status:** PASS (29 / 29 Step 1 & 2 tests PASS, 132 / 132 overall verification tests PASS)

---

## 1. Executive Summary

In Step 2 of the P7 verification infrastructure re-baselining, we implemented the authoritative reference model for P7 packet construction, MAC framing, freshness metadata serialization, and packet validation:
- Module: `verification/p7_packet_model.py`
- Test Suite: `verification/tests/test_p7_packet_model.py`
- Protocol Configuration Input: `verification/generated/p7_protocol_manifest.json` (dynamically loaded, no hardcoded matrix)

The model strictly models the distinction between data-plane and control-plane traffic established in M-F1 rev 7:
1. **Control-plane messages** (`ATTEST_CHALLENGE`, `ATTEST_RESPONSE`, `ATTEST_GRANT`, `ATTEST_REVOKE`):
   - Carry exactly 4 trailing MAC words (128 bits) produced by the shared L2 KMAC engine.
   - Carry 160 bits (5 flits: F0–F4) of freshness overhead on the mesh wire (sequence, boot epoch, padding).
2. **Data-plane messages** (`MEM_RD_REQ`, `MEM_RD_RESP`, `MEM_WR_REQ`, `MEM_WR_RESP`):
   - Pure plain framing: 0 MAC words and 0 freshness overhead.
   - Any MAC or freshness present on data packets is rejected as a protocol violation.

---

## 2. Files Created and Modified

### Created Files:
1. `verification/p7_packet_model.py`: Reference model for packet metadata, flit serialization (NI and Wire), MAC framing, freshness formatting, and validation.
2. `verification/tests/test_p7_packet_model.py`: Comprehensive test suite testing all 8 message types, boundary conditions, and negative/mutation test cases.
3. `reports/E4_P7_STEP2_REPORT.md`: This Step 2 completion report.

### Modified Files:
- **None.** Step 1 files (`verification/p7_rtl_parser.py`, `verification/generated/p7_protocol_manifest.json`, `verification/tests/test_p7_rtl_parser.py`) and RTL source files were untouched.

---

## 3. Actual RTL Framing Rules Discovered

From inspection of `rtl/dual_lane/NOC_PKG.sv`, `rtl/dual_lane/noc_p7_pkg.sv`, `rtl/dual_lane/noc_network_interface_p7.sv`, and `rtl/dual_lane/noc_l2_auth_p7.sv`:

### A. Network Interface (NI) Framing:
- **HEAD Flit:**
  - `data[31:29]`: `dest_x` (3 bits)
  - `data[28:26]`: `dest_y` (3 bits)
  - `data[25:23]`: `src_x` (3 bits)
  - `data[22:20]`: `src_y` (3 bits)
  - `data[19:16]`: `msg_type` (4 bits)
  - `data[15:11]`: `length` (5 bits: NI packet length)
  - `data[10:0]`: `control` (11 bits)
- **Flit Types:**
  - Single-flit packet (`MEM_WR_RESP`, length = 1): `FLIT_HEAD_TAIL` (value 3)
  - Multi-flit packet: Flit 0 is `FLIT_HEAD` (0), Flits 1..N-2 are `FLIT_BODY` (1), Flit N-1 is `FLIT_TAIL` (2).
- **Region Ordering:**
  `[HEAD] -> [PAYLOAD (0..16 flits)] -> [MAC (0 or 4 flits)]`

### B. Wire (Mesh Link) Framing:
- **Data Plane (Types 0–3):**
  - Pass-through plain framing.
  - Wire length == NI length (2, 2, 3, 1 flits).
  - No freshness flits.
- **Control Plane (Types 4–7):**
  - `noc_l2_auth_p7` intercepts the packet at the L2 boundary.
  - Adjusts HEAD flit length: `length = ni_length + 5` (17, 26, 10, 10 flits).
  - Injects 5 freshness flits (`F0`–`F4`) immediately following the HEAD flit.
  - Flit order on wire:
    `[HEAD (wire_len)] -> [F0] -> [F1] -> [F2] -> [F3] -> [F4] -> [PAYLOAD] -> [MAC0] -> [MAC1] -> [MAC2] -> [MAC3 (TAIL)]`

---

## 4. Freshness Encoding

As verified in `noc_l2_auth_p7.sv` lines 83, 91, 115, 247:
- The freshness signal is packed as:
  ```systemverilog
  assign freshness = {16'b0, epoch_q, seq_q};
  ```
- Total width: 160 bits (5 x 32-bit words):
  - **F0 (`freshness[31:0]`):** `seq_q[31:0]` (low 32 bits of sequence number)
  - **F1 (`freshness[63:32]`):** `seq_q[63:32]` (high 32 bits of sequence number)
  - **F2 (`freshness[95:64]`):** `epoch_q[31:0]` (low 32 bits of boot epoch)
  - **F3 (`freshness[127:96]`):** `epoch_q[63:32]` (mid 32 bits of boot epoch)
  - **F4 (`freshness[159:128]`):** `{padding[15:0], epoch_q[79:64]}`:
    - bits `[15:0]`: `epoch_q[79:64]` (high 16 bits of boot epoch)
    - bits `[31:16]`: `16'b0` (required zero padding, asserted in receiver `hdr_bad`)
- Deserialization and validation:
  - Sequence: 64-bit unsigned integer (`0 <= seq < 2^64`)
  - Epoch: 80-bit unsigned integer (`0 <= epoch < 2^80`)
  - Padding: strictly 0; non-zero values trigger immediate rejection (`PacketValidationError`).

---

## 5. MAC Handling and Equivalence Status

### Hardware Framing and Flit Order:
- MAC tag is 128 bits (16 bytes).
- Serialized across 4 flits:
  - `MAC0`: `tag[31:0]`
  - `MAC1`: `tag[63:32]`
  - `MAC2`: `tag[95:64]`
  - `MAC3`: `tag[127:96]`
- In `noc_network_interface_p7.sv:495` and `noc_l2_auth_p7.sv:248`, words are transferred in increasing index order `0..3`.

### KMAC128 Transcript Specification:
Inspecting `l2_kmac_engine.sv` and `noc_l2_auth_p7.sv`:
1. **Key Input:** 256 bits (32 bytes): `K[4->3]` (for Tile 4 TX / Tile 3 RX) or `K[3->4]` (for Tile 3 TX / Tile 4 RX).
2. **Customization String / Domain:**
   `112'h31762d485455412d324c2d434f4e` -> little-endian bytes form ASCII string `b"NOC-L2-AUTH-v1"` (14 bytes).
3. **Transcript Assembly (24 + 4*pn bytes):**
   - Word 0: wire HEAD flit
   - Word 1: `{epoch[15:0], 8'd1 (version), 8'(VC)}`
   - Word 2: `epoch[47:16]`
   - Word 3: `epoch[79:48]`
   - Word 4: `seq[31:0]`
   - Word 5: `seq[63:32]`
   - Words 6..5+pn: payload flits `tp[0..pn-1]`
4. **Tag Truncation:** `tag_out[127:0]` (128-bit output).

### Equivalence Status:
- **Status:** **`NOT VERIFIED`**
- **Reason:** In accordance with task guidelines ("Do not claim cryptographic equivalence without matching the actual RTL encoding", "If any detail is unresolved, implement the framing interface but mark cryptographic equivalence as NOT VERIFIED"), cryptographic equivalence between the standalone `software/kmac128_ref.py` invocation and the synthesized multi-cycle `l2_kmac_engine` hardware is marked `NOT VERIFIED`. Full cryptographic equivalence sign-off will occur when end-to-end simulation vectors from the dual-lane testbenches are verified against the reference model in Step 4/5.

---

## 6. Test Results

### Step 1 & Step 2 Suites:
Run command:
```bash
python -m pytest verification/tests/test_p7_rtl_parser.py verification/tests/test_p7_packet_model.py -v
```

Execution result:
```text
============================= test session starts =============================
platform win32 -- Python 3.13.5, pytest-9.0.2, pluggy-1.6.0
rootdir: C:\Users\Arnav Bhandari\PQ_Attest
collected 29 items

verification/tests/test_p7_rtl_parser.py::test_correct_extraction_from_current_rtl PASSED [  3%]
verification/tests/test_p7_rtl_parser.py::test_missing_message_type PASSED                 [  6%]
verification/tests/test_p7_rtl_parser.py::test_duplicate_message_encoding PASSED         [ 10%]
verification/tests/test_p7_rtl_parser.py::test_unresolved_expression PASSED               [ 13%]
verification/tests/test_p7_rtl_parser.py::test_changed_freshness_expression PASSED       [ 17%]
verification/tests/test_p7_rtl_parser.py::test_changed_payload_length PASSED             [ 20%]
verification/tests/test_p7_rtl_parser.py::test_incorrect_mac_length PASSED               [ 24%]
verification/tests/test_p7_rtl_parser.py::test_missing_source_file PASSED                [ 27%]
verification/tests/test_p7_rtl_parser.py::test_malformed_systemverilog_declaration PASSED [ 31%]
verification/tests/test_p7_rtl_parser.py::test_cli_execution PASSED                       [ 34%]
verification/tests/test_p7_packet_model.py::test_all_eight_message_types_framing[MEM_RD_REQ-1-0-2-2-False] PASSED [ 37%]
verification/tests/test_p7_packet_model.py::test_all_eight_message_types_framing[MEM_RD_RESP-1-0-2-2-False] PASSED [ 41%]
verification/tests/test_p7_packet_model.py::test_all_eight_message_types_framing[MEM_WR_REQ-2-0-3-3-False] PASSED [ 44%]
verification/tests/test_p7_packet_model.py::test_all_eight_message_types_framing[MEM_WR_RESP-0-0-1-1-False] PASSED [ 48%]
verification/tests/test_p7_packet_model.py::test_all_eight_message_types_framing[ATTEST_CHALLENGE-7-4-12-17-True] PASSED [ 51%]
verification/tests/test_p7_packet_model.py::test_all_eight_message_types_framing[ATTEST_RESPONSE-16-4-21-26-True] PASSED [ 55%]
verification/tests/test_p7_packet_model.py::test_all_eight_message_types_framing[ATTEST_GRANT-0-4-5-10-True] PASSED [ 58%]
verification/tests/test_p7_packet_model.py::test_all_eight_message_types_framing[ATTEST_REVOKE-0-4-5-10-True] PASSED [ 62%]
verification/tests/test_p7_packet_model.py::test_freshness_serialization_and_boundaries PASSED [ 65%]
verification/tests/test_p7_packet_model.py::test_freshness_validation_rejections PASSED  [ 68%]
verification/tests/test_p7_packet_model.py::test_deterministic_round_trip_ni_and_wire PASSED [ 72%]
verification/tests/test_p7_packet_model.py::test_reject_incorrect_payload_length PASSED   [ 75%]
verification/tests/test_p7_packet_model.py::test_reject_incorrect_mac_length_control_packets PASSED [ 79%]
verification/tests/test_p7_packet_model.py::test_reject_unexpected_mac_on_data_packets PASSED [ 82%]
verification/tests/test_p7_packet_model.py::test_reject_corrupted_wire_length_field PASSED [ 86%]
verification/tests/test_p7_packet_model.py::test_reject_truncated_wire_packet PASSED      [ 89%]
verification/tests/test_p7_packet_model.py::test_reject_invalid_message_type PASSED       [ 93%]
verification/tests/test_p7_packet_model.py::test_reject_out_of_mesh_coordinates PASSED    [ 96%]
verification/tests/test_p7_packet_model.py::test_kmac_framing_interface_and_status PASSED [100%]

============================= 29 passed in 1.36s ==============================
```

### Full Repository Regression:
Run command:
```bash
python -m pytest
```

Execution result:
```text
collected 132 items

verification\test_generate_integration_scenarios.py .................    [ 12%]
verification\test_generate_noc_pair_matrix.py .........                  [ 19%]
verification\test_generate_noc_traffic.py .............                  [ 29%]
verification\test_p4_regression.py ...............                       [ 40%]
verification\test_sv_vector_bridge.py ........                           [ 46%]
verification\test_verify_noc_pair_matrix.py ...........                  [ 55%]
verification\test_verify_tile_map.py .....                               [ 59%]
verification\test_xy_route_oracle.py ................                    [ 71%]
verification\tests\test_crypto_compare.py .........                      [ 78%]
verification\tests\test_p7_packet_model.py ...................           [ 92%]
verification\tests\test_p7_rtl_parser.py ..........                      [100%]

============================= 132 passed in 5.45s =============================
```

Zero regressions observed across all 103 legacy and 29 Step 1 & 2 tests.

---

## 7. Negative and Mutation Test Coverage Matrix

Every validation rule was tested with targeted negative tests:

| Validation Rule | Target Failure Mode | Negative Test Name | Status |
|---|---|---|:---:|
| Exact Payload Length | Undersized payload (6 instead of 7) | `test_reject_incorrect_payload_length` | PASS |
| Exact Payload Length | Oversized payload (2 instead of 1) | `test_reject_incorrect_payload_length` | PASS |
| Control MAC Framing | Missing MAC (0 flits) on control packet | `test_reject_incorrect_mac_length_control_packets` | PASS |
| Control MAC Framing | Truncated MAC (3 flits) on control packet | `test_reject_incorrect_mac_length_control_packets` | PASS |
| Control MAC Framing | Extra MAC (5 flits) on control packet | `test_reject_incorrect_mac_length_control_packets` | PASS |
| Data MAC Prohibition | Unexpected MAC (4 flits) on data packet | `test_reject_unexpected_mac_on_data_packets` | PASS |
| Length Field Integrity | Corrupted length field in HEAD flit | `test_reject_corrupted_wire_length_field` | PASS |
| Wire Packet Bounds | Truncated wire packet flit stream | `test_reject_truncated_wire_packet` | PASS |
| Message Type Validity | Unknown message string name | `test_reject_invalid_message_type` | PASS |
| Message Type Validity | Out-of-bounds numeric encoding | `test_reject_invalid_message_type` | PASS |
| Mesh Coordinate Bounds | `dest_x` / `src_x` >= 3 | `test_reject_out_of_mesh_coordinates` | PASS |
| Mesh Coordinate Bounds | `dest_y` / `src_y` >= 2 | `test_reject_out_of_mesh_coordinates` | PASS |
| Freshness Padding | Non-zero padding in F4 flit | `test_freshness_validation_rejections` | PASS |
| Freshness Range | Sequence number >= 2^64 | `test_freshness_validation_rejections` | PASS |
| Freshness Range | Boot epoch >= 2^80 | `test_freshness_validation_rejections` | PASS |

---

## 8. Confirmation of Repository Integrity

- **RTL Integrity:** Confirmed via `git diff rtl/dual_lane` that zero RTL files were modified.
- **Historical rev-5 Artifacts:** Untouched and preserved.
- **Step 1 Outputs:** `p7_protocol_manifest.json` and `p7_rtl_parser.py` intact and used as input.

---

## 9. Conclusion

Step 2 is complete. The P7 packet reference model is operational, fully validated, and ready for use in subsequent transaction and integration verification steps.

