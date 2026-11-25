"""
verification/tests/test_p7_link_monitor.py
==========================================
PQ-Attest P7 Link Monitor Tests — Step 11: Trace-Based Verification Suite.

Engineer 4 Verification Infrastructure.

Tests:
1. Clean multi-packet handshake and backpressure monitoring (0 violations).
2. Reset violation detection (valid asserted during rst_n=0).
3. Data mutation under backpressure violation detection.
4. Valid deassertion under backpressure violation detection.
5. Flit ordering violations (orphan body, orphan tail, nested head).
6. Virtual channel consistency violations (VC switch mid-packet).
7. Credit accounting violations (credit overflow, credit underflow).
8. Unterminated packet detection at trace end.
9. Malformed / missing flit attribute handling.
10. CSV adapter parsing and verification.
11. Results manifest generation and provenance validation.
"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path
import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from verification.p7_paths import get_default_paths
from verification.p7_link_monitor import (
    CSVTraceAdapter,
    FlitType,
    LinkCycleEvent,
    P7LinkMonitor,
    SyntheticTraceGenerator,
    TraceProvenance,
    VirtualChannel,
    execute_link_monitor_suite,
    generate_link_monitor_manifest,
)


def test_clean_multi_packet_trace_passes():
    """Verify clean trace with reset, backpressure, atomic and multi-flit transfers has zero violations."""
    mon = P7LinkMonitor(port_name="test_clean")
    events = SyntheticTraceGenerator.generate_clean_multi_packet_trace()
    for ev in events:
        mon.step(ev)
    res = mon.finish()

    assert res["status"] == "PASS"
    assert res["statistics"]["total_violations"] == 0
    assert res["statistics"]["packets_completed"] == 2
    assert res["statistics"]["handshake_transfers"] == 4
    assert res["statistics"]["backpressure_cycles"] == 2
    assert res["statistics"]["first_failure_cycle"] is None


def test_reset_violation_detection():
    """Verify asserting valid during reset (rst_n=0) is caught."""
    mon = P7LinkMonitor(port_name="test_reset")
    events = SyntheticTraceGenerator.generate_faulty_trace("RESET_VALID")
    for ev in events:
        mon.step(ev)
    res = mon.finish()

    assert res["status"] == "FAIL"
    assert res["statistics"]["total_violations"] > 0
    rules = [v["rule_id"] for v in res["violations"]]
    assert "RULE_RESET_VALID" in rules


def test_backpressure_data_mutation_detection():
    """Verify modifying flit data during backpressure stall is caught."""
    mon = P7LinkMonitor(port_name="test_bp_mut")
    events = SyntheticTraceGenerator.generate_faulty_trace("BACKPRESSURE_MUTATION")
    for ev in events:
        mon.step(ev)
    res = mon.finish()

    assert res["status"] == "FAIL"
    rules = [v["rule_id"] for v in res["violations"]]
    assert "RULE_BACKPRESSURE_DATA_MUTATION" in rules


def test_backpressure_valid_deassertion_detection():
    """Verify deasserting valid during backpressure stall before ready handshake is caught."""
    mon = P7LinkMonitor(port_name="test_bp_deassert")
    # Cycle 0: reset
    mon.step(LinkCycleEvent(cycle=0, rst_n=0, valid=0, ready=1))
    # Cycle 1: active valid=1, ready=0
    mon.step(LinkCycleEvent(cycle=1, rst_n=1, valid=1, ready=0, flit_type=0, vc_id=0, flit_data=0x1111))
    # Cycle 2: valid dropped to 0 before ready was asserted
    mon.step(LinkCycleEvent(cycle=2, rst_n=1, valid=0, ready=1))
    res = mon.finish()

    assert res["status"] == "FAIL"
    rules = [v["rule_id"] for v in res["violations"]]
    assert "RULE_BACKPRESSURE_VALID_DEASSERTION" in rules


def test_orphan_flit_ordering_violations():
    """Verify receiving body or tail flits without preceding head is caught."""
    mon = P7LinkMonitor(port_name="test_orphan")
    events = SyntheticTraceGenerator.generate_faulty_trace("ORPHAN_BODY")
    for ev in events:
        mon.step(ev)
    res = mon.finish()

    assert res["status"] == "FAIL"
    rules = [v["rule_id"] for v in res["violations"]]
    assert "RULE_ORPHAN_BODY" in rules


def test_nested_head_violation():
    """Verify receiving HEAD without terminating prior packet with TAIL is caught."""
    mon = P7LinkMonitor(port_name="test_nested")
    mon.step(LinkCycleEvent(cycle=0, rst_n=1, valid=1, ready=1, flit_type=0, vc_id=0, flit_data=0x10))
    mon.step(LinkCycleEvent(cycle=1, rst_n=1, valid=1, ready=1, flit_type=0, vc_id=0, flit_data=0x20))
    res = mon.finish()

    assert res["status"] == "FAIL"
    rules = [v["rule_id"] for v in res["violations"]]
    assert "RULE_NESTED_HEAD" in rules


def test_vc_switch_mid_packet_violation():
    """Verify switching VC ID across flits of a single packet is caught."""
    mon = P7LinkMonitor(port_name="test_vc_switch")
    events = SyntheticTraceGenerator.generate_faulty_trace("VC_SWITCH")
    for ev in events:
        mon.step(ev)
    res = mon.finish()

    assert res["status"] == "FAIL"
    rules = [v["rule_id"] for v in res["violations"]]
    assert "RULE_VC_SWITCH_MID_PACKET" in rules


def test_credit_overflow_and_underflow():
    """Verify credit balance violations (overflow above depth, underflow below 0)."""
    # 1. Overflow
    mon1 = P7LinkMonitor(port_name="test_cred_ovf", vc_depth=4)
    mon1.step(LinkCycleEvent(cycle=0, rst_n=1, valid=0, ready=1, credits=1))
    res1 = mon1.finish()
    assert "RULE_CREDIT_OVERFLOW" in [v["rule_id"] for v in res1["violations"]]

    # 2. Underflow: send 5 flits on VC 0 without credit returns (depth is 4)
    mon2 = P7LinkMonitor(port_name="test_cred_unf", vc_depth=4)
    mon2.step(LinkCycleEvent(cycle=0, rst_n=1, valid=1, ready=1, flit_type=0, vc_id=0, flit_data=0x1))
    mon2.step(LinkCycleEvent(cycle=1, rst_n=1, valid=1, ready=1, flit_type=1, vc_id=0, flit_data=0x2))
    mon2.step(LinkCycleEvent(cycle=2, rst_n=1, valid=1, ready=1, flit_type=1, vc_id=0, flit_data=0x3))
    mon2.step(LinkCycleEvent(cycle=3, rst_n=1, valid=1, ready=1, flit_type=1, vc_id=0, flit_data=0x4))
    # 5th flit triggers underflow
    mon2.step(LinkCycleEvent(cycle=4, rst_n=1, valid=1, ready=1, flit_type=2, vc_id=0, flit_data=0x5))
    res2 = mon2.finish()
    assert "RULE_CREDIT_UNDERFLOW" in [v["rule_id"] for v in res2["violations"]]


def test_unterminated_packet_at_trace_end():
    """Verify trace terminating with an unclosed packet is caught."""
    mon = P7LinkMonitor(port_name="test_unterminated")
    events = SyntheticTraceGenerator.generate_faulty_trace("UNTERMINATED_PACKET")
    for ev in events:
        mon.step(ev)
    res = mon.finish()

    assert res["status"] == "FAIL"
    rules = [v["rule_id"] for v in res["violations"]]
    assert "RULE_UNTERMINATED_PACKET" in rules


def test_malformed_flit_fields_handled():
    """Verify missing/None flit fields when valid=1 are flagged."""
    mon = P7LinkMonitor(port_name="test_malformed")
    mon.step(LinkCycleEvent(cycle=0, rst_n=1, valid=1, ready=1, flit_type=None, vc_id=None, flit_data=None))
    res = mon.finish()

    assert res["status"] == "FAIL"
    rules = [v["rule_id"] for v in res["violations"]]
    assert "RULE_MALFORMED_FLIT" in rules


def test_csv_trace_adapter(tmp_path):
    """Verify CSV adapter can parse CSV file and feed the monitor."""
    csv_file = tmp_path / "link_trace.csv"
    with open(csv_file, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["cycle", "rst_n", "valid", "ready", "flit_type", "vc_id", "flit_data", "credits"])
        writer.writerow([0, 0, 0, 1, "", "", "", ""])
        writer.writerow([1, 1, 1, 1, 3, 0, "0x12345678", ""])

    events = CSVTraceAdapter.parse(csv_file)
    assert len(events) == 2

    mon = P7LinkMonitor(port_name="test_csv")
    for ev in events:
        mon.step(ev)
    res = mon.finish()
    assert res["status"] == "PASS"


def test_link_monitor_manifest_generation(tmp_path):
    """Verify p7_link_monitor_results.json generation and provenance."""
    out_file = tmp_path / "link_monitor_results.json"
    data = generate_link_monitor_manifest(out_file)

    assert out_file.exists()
    assert data["metadata"]["provenance"] == TraceProvenance.SYNTHETIC_TEST_INPUT.value
    assert "clean_multi_packet" in data["scenarios"]
    assert data["scenarios"]["clean_multi_packet"]["status"] == "PASS"
    assert data["scenarios"]["reset_valid"]["status"] == "FAIL"

