# PQ-Attest Engineer 4 — Step 11: Link Monitor

**Date:** November 6, 2026  
**Author:** Engineer 4 (Antigravity Verification Pair)  
**Status:** COMPLETED & VERIFIED  
**Deliverables:**
- `verification/p7_link_monitor.py`
- `verification/tests/test_p7_link_monitor.py`
- `verification/generated/p7_link_monitor_results.json`
- `reports/E4_P7_STEP11_LINK_MONITOR.md`

---

## 1. Executive Summary

Step 11 implements a trace-based NoC link verification monitor (`P7LinkMonitor`) to inspect flit transfers, handshake semantics, ordering invariants, and credit bounds across physical links.

The monitor supports:
- Ready/valid handshakes.
- Data stability under backpressure (`valid=1, ready=0`).
- Flit ordering (`HEAD` $\to$ `BODY`* $\to$ `TAIL`, or atomic `HEAD_TAIL`).
- Packet boundaries (`AM-3` convention: packets end only on `TAIL` or `HEAD_TAIL`).
- Virtual Channel (VC) identity consistency (`VC_REQUEST`, `VC_RESPONSE`, `VC_ATTESTATION`).
- Credit accounting (`VC_DEPTH = 4`, detection of underflow and overflow).
- Reset deassertion (`valid == 0` during active-low `rst_n == 0`).
- Missing or malformed trace fields.

---

## 2. Trace Provenance & Classification

In accordance with verification guidelines:
- **Trace Classification:** Deterministic synthetic fixtures are labeled `SYNTHETIC_TEST_INPUT`.
- **RTL Evidence Distinction:** These synthetic monitor checks provide protocol invariant testing and are explicitly distinguished from registered Vivado/XSim simulation evidence.
- **Trace Adapters:** Implemented `CSVTraceAdapter` to parse cycle-by-cycle link traces and `SyntheticTraceGenerator` to produce deterministic scenarios.

---

## 3. Protocol Rules & Invariants Checked

| Rule ID | Invariant Statement | Violation Signature |
|:---|:---|:---|
| `RULE_RESET_VALID` | `valid` must be 0 while `rst_n == 0`. | Valid asserted during active reset. |
| `RULE_BACKPRESSURE_STABILITY` | When `valid=1` and `ready=0`, flit payload and metadata must remain unchanged until `ready=1`. | Data or VC changed during stall. |
| `RULE_BACKPRESSURE_VALID` | `valid` cannot drop from 1 to 0 during an unaccepted stall cycle. | Valid deasserted before handshake. |
| `RULE_FLIT_ORDERING` | Flits must follow `HEAD` $\to$ `BODY`* $\to$ `TAIL` or `HEAD_TAIL`. | Orphan BODY/TAIL, or nested HEAD. |
| `RULE_VC_CONSISTENCY` | All flits in a single packet must share identical `vc_id`. | VC ID altered mid-packet. |
| `RULE_VC_VALID_RANGE` | `vc_id` must be in `0..NUM_VC-1` (`0..2`). | Unknown VC index. |
| `RULE_CREDIT_ACCOUNTING` | Credit balance must remain bounded within `[0..VC_DEPTH]`. | Credit underflow or credit overflow. |
| `RULE_UNTERMINATED_PACKET` | Trace must not terminate with an unclosed packet in flight. | Missing TAIL at simulation boundary. |
| `RULE_MALFORMED_FLIT` | Valid transfers must not contain `None` or unparseable fields. | Missing type/VC/data. |

---

## 4. Test & Verification Results

All 12 unit and integration tests in `verification/tests/test_p7_link_monitor.py` passed:
- `test_clean_multi_packet_trace_passes`: PASS (0 violations across reset, single-flit, multi-flit, and backpressure transfers).
- `test_reset_violation_detection`: PASS (caught `RULE_RESET_VALID`).
- `test_backpressure_data_mutation_detection`: PASS (caught `RULE_BACKPRESSURE_DATA_MUTATION`).
- `test_backpressure_valid_deassertion_detection`: PASS (caught `RULE_BACKPRESSURE_VALID_DEASSERTION`).
- `test_orphan_flit_ordering_violations`: PASS (caught `RULE_ORPHAN_BODY`).
- `test_nested_head_violation`: PASS (caught `RULE_NESTED_HEAD`).
- `test_vc_switch_mid_packet_violation`: PASS (caught `RULE_VC_SWITCH_MID_PACKET`).
- `test_credit_overflow_and_underflow`: PASS (caught `RULE_CREDIT_OVERFLOW` and `RULE_CREDIT_UNDERFLOW`).
- `test_unterminated_packet_at_trace_end`: PASS (caught `RULE_UNTERMINATED_PACKET`).
- `test_malformed_flit_fields_handled`: PASS (caught `RULE_MALFORMED_FLIT`).
- `test_csv_trace_adapter`: PASS (parsed synthetic CSV trace correctly).
- `test_link_monitor_manifest_generation`: PASS (manifest generated with valid schema).

---

## 5. Artifact Manifest

The link monitor results manifest is generated at:
`verification/generated/p7_link_monitor_results.json`
Recording transaction counts, backpressure cycles, violations, and first failure cycles across clean and negative test suites.

