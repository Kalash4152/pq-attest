# E4 Report: PQ-Attest P7 Verification — Step 1: Live RTL Protocol Extraction

- **Engineer:** Engineer 4 (Python Verification Infrastructure)
- **Task:** Step 1 — Live RTL Protocol Extraction
- **Date:** 2026-11-03
- **Status:** PASS (10 / 10 Step 1 tests PASS, 113 / 113 overall verification tests PASS)

---

## 1. Executive Summary

As part of the re-baselining of Engineer 4's verification tooling from the rev-5 baseline to the M-F1 rev 7 (P7) architecture, we designed and implemented an authoritative SystemVerilog protocol extraction parser:
- Tool: `verification/p7_rtl_parser.py`
- Manifest: `verification/generated/p7_protocol_manifest.json`
- Test Suite: `verification/tests/test_p7_rtl_parser.py`

The parser extracts message encodings, payload lengths, MAC lengths, NI packet lengths, wire lengths, virtual channel mappings, freshness overhead, and relevant topology constants directly from the live SystemVerilog RTL source files (`NOC_PKG.sv`, `noc_p7_pkg.sv`, and `noc_l2_auth_p7.sv`). It never relies on hardcoded values, defaults, or stale rev-5 assumptions.

Every extracted parameter is mapped to its exact source file, line number, and raw RTL declaration snippet.

---

## 2. Files Created and Modified

### Created Files:
1. `verification/p7_rtl_parser.py`: Authoritative SystemVerilog protocol parser, expression evaluator, validator, and manifest generator.
2. `verification/generated/p7_protocol_manifest.json`: Machine-readable protocol manifest containing extracted protocol values, origin declarations, and validation results.
3. `verification/tests/test_p7_rtl_parser.py`: Pytest suite covering baseline extraction, mutation tests against temporary copies, and CLI verification.
4. `reports/E4_P7_STEP1_REPORT.md`: This comprehensive step 1 completion report.

### Modified Files:
- **None.** No existing files were modified.

---

## 3. Extracted Protocol Values

The parser extracted the following protocol matrix directly from the RTL sources:

| Message Name | Enc | VC | VC ID | Payload (flits) | MAC (flits) | NI Length (flits) | Freshness (flits) | Wire Length (flits) | Validation Status |
|---|:---:|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `MEM_RD_REQ` | 0 | `VC_REQUEST` | 0 | 1 | 0 | 2 | 0 | 2 | PASS |
| `MEM_RD_RESP` | 1 | `VC_RESPONSE` | 1 | 1 | 0 | 2 | 0 | 2 | PASS |
| `MEM_WR_REQ` | 2 | `VC_REQUEST` | 0 | 2 | 0 | 3 | 0 | 3 | PASS |
| `MEM_WR_RESP` | 3 | `VC_RESPONSE` | 1 | 0 | 0 | 1 | 0 | 1 | PASS |
| `ATTEST_CHALLENGE` | 4 | `VC_ATTESTATION` | 2 | 7 | 4 | 12 | 5 | 17 | PASS |
| `ATTEST_RESPONSE` | 5 | `VC_ATTESTATION` | 2 | 16 | 4 | 21 | 5 | 26 | PASS |
| `ATTEST_GRANT` | 6 | `VC_ATTESTATION` | 2 | 0 | 4 | 5 | 5 | 10 | PASS |
| `ATTEST_REVOKE` | 7 | `VC_ATTESTATION` | 2 | 0 | 4 | 5 | 5 | 10 | PASS |

### Protocol Constants Extracted:
- `MESH_X`: 3
- `MESH_Y`: 2
- `NUM_TILES`: 6
- `NUM_PORTS`: 5
- `FLIT_WIDTH`: 32 bits
- `NUM_VC`: 3
- `VC0_DEPTH`: 4
- `VC1_DEPTH`: 4
- `VC2_DEPTH`: 4
- `FIFO_DEPTH`: 4
- `MAC_TAG_BITS`: 128 bits
- `MAC_FLITS_FULL`: 4 flits
- Freshness Overhead: 5 flits (parsed expression: `5` in `extend()`)

---

## 4. Source Declarations Used

The parser verified and traced each extracted value to its declaration in the source RTL:

1. **Message Enums (`msg_type_e`)** — `rtl/dual_lane/NOC_PKG.sv`:
   - Line 176: `MSG_MEM_RD_REQ = 4'd0`
   - Line 177: `MSG_MEM_RD_RESP = 4'd1`
   - Line 178: `MSG_MEM_WR_REQ = 4'd2`
   - Line 179: `MSG_MEM_WR_RESP = 4'd3`
   - Line 181: `MSG_ATTEST_CHALLENGE = 4'd4`
   - Line 182: `MSG_ATTEST_RESPONSE = 4'd5`
   - Line 183: `MSG_ATTEST_GRANT = 4'd6`
   - Line 184: `MSG_ATTEST_REVOKE = 4'd7`

2. **Virtual Channels (`vc_e`)** — `rtl/dual_lane/NOC_PKG.sv`:
   - Line 165: `VC_REQUEST = 'd0`
   - Line 166: `VC_RESPONSE = 'd1`
   - Line 167: `VC_ATTESTATION = 'd2`

3. **VC Mapping (`message_to_vc`)** — `rtl/dual_lane/NOC_PKG.sv`:
   - Lines 578-581: `MSG_MEM_RD_REQ, MSG_MEM_WR_REQ: return VC_REQUEST;`
   - Lines 582-585: `MSG_MEM_RD_RESP, MSG_MEM_WR_RESP: return VC_RESPONSE;`
   - Lines 586-591: `MSG_ATTEST_CHALLENGE, MSG_ATTEST_RESPONSE, MSG_ATTEST_GRANT, MSG_ATTEST_REVOKE: return VC_ATTESTATION;`

4. **Payload Flits (`message_payload_flits`)** — `rtl/dual_lane/NOC_PKG.sv`:
   - Line 610: `MSG_MEM_RD_REQ: return 5'd1;`
   - Line 611: `MSG_MEM_RD_RESP: return 5'd1;`
   - Line 612: `MSG_MEM_WR_REQ: return 5'd2;`
   - Line 613: `MSG_MEM_WR_RESP: return 5'd0;`
   - Line 615: `MSG_ATTEST_CHALLENGE: return 5'd7;`
   - Line 616: `MSG_ATTEST_RESPONSE: return 5'd16;`
   - Line 617: `MSG_ATTEST_GRANT: return 5'd0;`
   - Line 618: `MSG_ATTEST_REVOKE: return 5'd0;`

5. **P7 Control Plane & MAC Lengths** — `rtl/dual_lane/noc_p7_pkg.sv`:
   - Lines 7-9: `function automatic logic is_control(input msg_type_e t); return t[3:2] == 2'b01; endfunction`
   - Lines 10-12: `function automatic int unsigned p7_mac_flits(input msg_type_e t); return is_control(t) ? MAC_FLITS_FULL : 0; endfunction`
   - Lines 14-16: `function automatic logic [4:0] p7_length(input msg_type_e t); return 5'd1 + message_payload_flits(t) + 5'(p7_mac_flits(t)); endfunction`

6. **Freshness Length Extension** — `rtl/dual_lane/noc_l2_auth_p7.sv`:
   - Lines 88-90:
     ```systemverilog
     function automatic head_flit_t extend(input head_flit_t h);
       head_flit_t v; v=h; v.length=h.length+5; return v;
     endfunction
     ```
     Parsed expression: `5` added to `h.length`. Evaluated dynamically to `5`.

---

## 5. Test Results

### Step 1 Test Suite: `verification/tests/test_p7_rtl_parser.py`
Run command:
```bash
python -m pytest verification/tests/test_p7_rtl_parser.py -v
```

Execution result:
```text
============================= test session starts =============================
platform win32 -- Python 3.13.5, pytest-9.0.2, pluggy-1.6.0
rootdir: C:\Users\Arnav Bhandari\PQ_Attest
collected 10 items

verification/tests/test_p7_rtl_parser.py::test_correct_extraction_from_current_rtl PASSED [ 10%]
verification/tests/test_p7_rtl_parser.py::test_missing_message_type PASSED                 [ 20%]
verification/tests/test_p7_rtl_parser.py::test_duplicate_message_encoding PASSED         [ 30%]
verification/tests/test_p7_rtl_parser.py::test_unresolved_expression PASSED               [ 40%]
verification/tests/test_p7_rtl_parser.py::test_changed_freshness_expression PASSED       [ 50%]
verification/tests/test_p7_rtl_parser.py::test_changed_payload_length PASSED             [ 60%]
verification/tests/test_p7_rtl_parser.py::test_incorrect_mac_length PASSED               [ 70%]
verification/tests/test_p7_rtl_parser.py::test_missing_source_file PASSED                [ 80%]
verification/tests/test_p7_rtl_parser.py::test_malformed_systemverilog_declaration PASSED [ 90%]
verification/tests/test_p7_rtl_parser.py::test_cli_execution PASSED                       [100%]

============================= 10 passed in 1.20s ==============================
```

### Full Verification Regression Suite:
Run command:
```bash
python -m pytest
```

Execution result:
```text
collected 113 items

verification\test_generate_integration_scenarios.py .................    [ 15%]
verification\test_generate_noc_pair_matrix.py .........                  [ 23%]
verification\test_generate_noc_traffic.py .............                  [ 34%]
verification\test_p4_regression.py ...............                       [ 47%]
verification\test_sv_vector_bridge.py ........                           [ 54%]
verification\test_verify_noc_pair_matrix.py ...........                  [ 64%]
verification\test_verify_tile_map.py .....                               [ 69%]
verification\test_xy_route_oracle.py ................                    [ 83%]
verification\tests\test_crypto_compare.py .........                      [ 91%]
verification\tests\test_p7_rtl_parser.py ..........                      [100%]

============================= 113 passed in 5.11s =============================
```

All 103 preexisting regression tests continue to pass with 0 regressions.

---

## 6. Mutation-Test Results

All mutations were performed strictly on isolated temporary files created under pytest's `tmp_path`. The live RTL in `rtl/dual_lane` was never touched:

1. **Missing Message Type (`test_missing_message_type`):**
   - Mutation: Removed `MSG_ATTEST_REVOKE = 4'd7` from `NOC_PKG.sv`.
   - Result: **KILLED** — Parser raised `SVParserError("Missing required message type 'ATTEST_REVOKE' in msg_type_e")` identifying `NOC_PKG.sv`.
2. **Duplicate Message Encoding (`test_duplicate_message_encoding`):**
   - Mutation: Changed `MSG_ATTEST_REVOKE = 4'd7` to `MSG_ATTEST_REVOKE = 4'd6` (colliding with `MSG_ATTEST_GRANT`).
   - Result: **KILLED** — Parser raised `SVParserError("Duplicate message encoding 6 for 'MSG_ATTEST_REVOKE' and 'MSG_ATTEST_GRANT'")`.
3. **Unresolved Expression (`test_unresolved_expression`):**
   - Mutation: Changed `localparam int unsigned MAC_TAG_BITS = 128;` to `= UNDEFINED_CONST_XYZ;`.
   - Result: **KILLED** — Parser raised `SVParserError("Unresolved identifier 'UNDEFINED_CONST_XYZ'")` referencing line 86.
4. **Changed Freshness Expression (`test_changed_freshness_expression`):**
   - Mutation: Changed `v.length=h.length+5;` in `noc_l2_auth_p7.sv` to `v.length=h.length+8;`.
   - Result: **KILLED** — Parser extracted freshness overhead `8` (raw expression `'8'`), computed wire length `20` for `ATTEST_CHALLENGE`, flagged status `MISMATCH`, and reported validation mismatch `ATTEST_CHALLENGE.wire_length: parsed 20 != expected 17` without altering parsed values.
5. **Changed Payload Length (`test_changed_payload_length`):**
   - Mutation: Changed `MSG_ATTEST_CHALLENGE` payload from `5'd7` to `5'd9`.
   - Result: **KILLED** — Parser extracted payload `9`, computed NI length `14` and wire length `19`, and flagged mismatches for payload, NI length, and wire length.
6. **Incorrect MAC Length (`test_incorrect_mac_length`):**
   - Mutation: Changed `MAC_TAG_BITS = 128` to `256`, resulting in `MAC_FLITS_FULL = 8`.
   - Result: **KILLED** — Parser extracted MAC length `8`, NI length `16`, wire length `21`, and flagged status `MISMATCH`.
7. **Missing Source File (`test_missing_source_file`):**
   - Mutation: Passed non-existent file path `DOES_NOT_EXIST.sv`.
   - Result: **KILLED** — Parser raised `SVParserError("Missing required source file")` immediately without crashing or substituting defaults.
8. **Malformed SystemVerilog Declaration (`test_malformed_systemverilog_declaration`):**
   - Mutation: Replaced valid enum declaration with malformed syntax (`MSG_MEM_RD_REQ === 4'd0,`).
   - Result: **KILLED** — Parser raised `SVParserError("Malformed enum item name")` identifying line and declaration.

---

## 7. Parser Scope and Limitations

1. **Target RTL Scope:** The parser is designed for the authoritative P7 NoC files (`NOC_PKG.sv`, `noc_p7_pkg.sv`, and `noc_l2_auth_p7.sv`).
2. **Expression Evaluator:** Supports standard IEEE 1800 constant expressions, binary/decimal/hex literals, casting, `$clog2`, `$bits` for packed types, and dependency-ordered topological resolution. Arbitrary dynamic procedural code outside constant functions is not intended to be evaluated by this parser.
3. **Preprocessor:** Handles conditional compilation directives (`` `ifdef `` / `` `else `` / `` `endif ``) preserving exact source line numbers; defaults to `PQ_MAC_ON = True` as required by the P7 specification.

---

## 8. Confirmation of Project Integrity

- **RTL files unmodified:** Verified with `git status` and `git diff rtl/dual_lane` (0 changes).
- **Historical artifacts unmodified:** All reports, past increments (I-4, I-5), and frozen teammate reference files remain byte-identical.
- **Portability:** Path handling uses `pathlib.Path` with POSIX normalization in the JSON manifest for cross-platform Linux/Windows compatibility.

---

## 9. Conclusion

Step 1 is complete. The P7 RTL Protocol Parser is operational, fully tested, and generates the authoritative manifest directly from the live SystemVerilog source files. We are ready to proceed to Step 2.

