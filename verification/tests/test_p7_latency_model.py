"""
verification/tests/test_p7_latency_model.py
===========================================
PQ-Attest P7 Latency and Timeout Model Tests — Step 12 (Evidence-Grounded).

Engineer 4 Verification Infrastructure.

Tests:
1. Architectural and registered evidence classification integrity (MEASURED_REGISTERED, DERIVED_ANALYTICAL_BOUND, UNKNOWN).
2. Scenario 1: Nominal arrival before timeout (cycle 118 < 600).
3. Scenario 2: Boundary arrival (cycle 599).
4. Scenario 3: Response after timeout (cycle 605) safely dropped.
5. Scenario 4: Missing response causes autonomous timeout release at cycle 600.
6. Scenario 5: Slot reallocation succeeds immediately after timeout release.
7. Scenario 6: Late response arrival does not corrupt unallocated slot.
8. Scenario 7: Stale response for older tag rejected after slot reuse.
9. Scenario 8: Reset with outstanding requests immediately clears both slots.
10. Scenario 9: BUSY retry bounded by 3, 4th consecutive BUSY fails closed.
11. Manifest generation, legitimate wait calculation, and schema validation.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from verification.p7_paths import get_default_paths
from verification.p7_latency_model import (
    ARCHITECTURAL_LATENCY_COMPONENTS,
    ARBITER_APPLICABILITY,
    AUTHORITATIVE_INPUTS,
    BENCH_TIMEOUT_CYCLES,
    BRIDGE_TIMEOUT_PROPOSED_CYCLES,
    EvidenceClass,
    LatencyCategory,
    LatencyTimeoutModel,
    MERGED_NI_SLOT_TIMEOUT_CYCLES,
    VERIFIER_TIMEOUT_CYCLES,
    build_timeout_registry,
    compute_worst_legitimate_cpu_wait,
    generate_latency_coverage_manifest,
    generate_latency_results_manifest,
    run_all_latency_scenarios,
    validate_timeout_metadata,
)


def test_latency_components_classification_integrity():
    """Verify registered evidence classifications, round-trip 1204, and timeout parameters."""
    components = ARCHITECTURAL_LATENCY_COMPONENTS
    assert "ni_injection" in components
    assert "ni_slot_timeout" in components
    assert "bridge_timeout" in components
    assert "unbounded_congestion_tail" in components

    # Verify NI timeout parameter in merged build is 8192 (reviewer-stated configuration)
    assert components["ni_slot_timeout"].nominal_cycles == 8192
    assert components["ni_slot_timeout"].category == EvidenceClass.REVIEWER_STATED_CONFIGURATION

    # Verify bridge timeout parameter is 4096 (proposed recommendation)
    assert components["bridge_timeout"].nominal_cycles == 4096
    assert components["bridge_timeout"].category == EvidenceClass.PROPOSED_RECOMMENDATION

    # Verify unknown contention tail is explicitly None / UNKNOWN
    tail = components["unbounded_congestion_tail"]
    assert tail.nominal_cycles is None
    assert tail.category == EvidenceClass.UNKNOWN

    # Verify authoritative registered evidence from Kalash: both NONE and LOADED conditions
    inputs = AUTHORITATIVE_INPUTS
    assert inputs["full_subsystem_attestation_rtt_none"].nominal_cycles == 1204
    assert inputs["full_subsystem_attestation_rtt_none"].category == EvidenceClass.MEASURED_REGISTERED
    assert inputs["full_subsystem_attestation_rtt_none"].condition.startswith("NONE")
    assert inputs["full_subsystem_attestation_rtt_loaded_max"].nominal_cycles == 1206
    assert inputs["full_subsystem_attestation_rtt_loaded_max"].category == EvidenceClass.MEASURED_REGISTERED
    assert inputs["full_subsystem_attestation_rtt_loaded_max"].condition.startswith("LOADED")
    assert inputs["c4_revoke_max"].nominal_cycles == 486
    assert inputs["c4_revoke_bound"].nominal_cycles == 1500
    assert inputs["arbiter_p_bound"].nominal_cycles == 269
    assert inputs["arbiter_q_bound"].nominal_cycles == 792
    assert inputs["arbiter_j_bound"].nominal_cycles == 128
    assert inputs["n_outstanding"].nominal_cycles == 2
    assert inputs["verifier_timeout"].nominal_cycles == 100000


def test_scenario_1_nominal_arrival_before_timeout():
    """Verify nominal response at cycle 118 (<600) retires successfully."""
    m = LatencyTimeoutModel(ni_timeout=600)
    assert m.allocate_slot(0, 0x10)
    m.advance_cycles(118)
    accepted, verdict = m.receive_response(0, 0x10)
    assert accepted is True
    assert verdict == "SUCCESS_RETIRED"
    assert m.slots[0].allocated is False


def test_scenario_2_boundary_arrival():
    """Verify response at cycle 599 immediately before 600 is accepted."""
    m = LatencyTimeoutModel(ni_timeout=600)
    m.allocate_slot(0, 0x20)
    m.advance_cycles(599)
    accepted, verdict = m.receive_response(0, 0x20)
    assert accepted is True
    assert verdict == "SUCCESS_RETIRED"


def test_scenario_3_response_after_timeout_dropped():
    """Verify response arriving at cycle 605 (>600) is dropped."""
    m = LatencyTimeoutModel(ni_timeout=600)
    m.allocate_slot(0, 0x30)
    m.advance_cycles(605)
    accepted, verdict = m.receive_response(0, 0x30)
    assert accepted is False
    assert verdict == "DROPPED_SLOT_EMPTY_OR_TIMED_OUT"


def test_scenario_4_missing_response_autonomous_release():
    """Verify lost response causes autonomous slot release at exactly cycle 600."""
    m = LatencyTimeoutModel(ni_timeout=600)
    m.allocate_slot(1, 0x40)
    m.advance_cycles(599)
    assert m.slots[1].allocated is True

    m.advance_cycles(1)  # Reaches cycle 600
    assert m.slots[1].allocated is False
    assert m.slots[1].release_reason == "TIMEOUT"


def test_scenario_5_slot_reallocation_after_timeout():
    """Verify slot can be immediately re-allocated once timed out."""
    m = LatencyTimeoutModel(ni_timeout=600)
    m.allocate_slot(0, 0x50)
    m.advance_cycles(600)
    # Slot 0 timed out, reallocate with new tag
    realloc = m.allocate_slot(0, 0x51)
    assert realloc is True
    assert m.slots[0].tag == 0x51
    assert m.slots[0].allocated is True


def test_scenario_6_late_response_dropped_safely():
    """Verify arrival of late response after timeout does not corrupt state."""
    m = LatencyTimeoutModel(ni_timeout=600)
    m.allocate_slot(0, 0x60)
    m.advance_cycles(750)
    acc, verd = m.receive_response(0, 0x60)
    assert acc is False
    assert m.slots[0].allocated is False


def test_scenario_7_stale_response_tag_mismatch():
    """Verify stale response for previous tag is rejected after slot reuse."""
    m = LatencyTimeoutModel(ni_timeout=600)
    m.allocate_slot(0, 0x70)
    m.advance_cycles(600)  # tag 0x70 times out
    m.allocate_slot(0, 0x71)  # tag 0x71 allocated
    # Response for old tag 0x70 arrives
    acc, verd = m.receive_response(0, 0x70)
    assert acc is False
    assert verd == "DROPPED_STALE_TAG_MISMATCH"
    # Active allocation for 0x71 remains intact
    assert m.slots[0].allocated is True
    assert m.slots[0].tag == 0x71


def test_scenario_8_reset_immediate_cleanup():
    """Verify hardware reset immediately clears both slots."""
    m = LatencyTimeoutModel(ni_timeout=600)
    m.allocate_slot(0, 0x80)
    m.allocate_slot(1, 0x81)
    m.advance_cycles(50)
    assert m.slots[0].allocated and m.slots[1].allocated

    m.apply_reset()
    assert not m.slots[0].allocated
    assert not m.slots[1].allocated
    assert m.slots[0].release_reason == "RESET_CLEARED"
    assert m.slots[1].release_reason == "RESET_CLEARED"


def test_scenario_9_busy_retry_exhaustion():
    """Verify BUSY retries: 0..3 permitted, 4th consecutive BUSY fails closed."""
    res = run_all_latency_scenarios()["scenario_9_busy_retry_exhaustion"]
    assert res["status"] == "PASS"
    records = res["records"]
    assert len(records) == 5
    assert records[0]["verdict"] == "RETRY_PERMITTED"
    assert records[3]["verdict"] == "RETRY_PERMITTED"
    assert records[4]["verdict"] == "RETRY_EXHAUSTED"
    assert records[4]["outcome"] == "FAIL_CLOSED_REVOKE_REASON_9"


def test_latency_manifests_generation(tmp_path):
    """Verify generation of p7_latency_model_results.json, coverage json, and worst legitimate wait."""
    f1 = tmp_path / "latency_results.json"
    f2 = tmp_path / "latency_coverage.json"

    d1 = generate_latency_results_manifest(f1)
    d2 = generate_latency_coverage_manifest(f2)

    assert f1.exists()
    assert f2.exists()
    assert len(d1["scenarios"]) == 9
    assert d2["scenario_coverage"]["coverage_pct"] == 100.0

    # Validate worst legitimate wait composition (loaded-max 1206 + 28 = 1234 nominal)
    wait = d1["worst_legitimate_cpu_wait"]
    assert wait["totals"]["nominal_legitimate_wait"] == 1234
    assert wait["totals"]["reference_none_condition_wait"] == 1232
    assert wait["totals"]["contention_wait_arbiter_p"] == 1503
    assert wait["totals"]["contention_wait_c4_max"] == 1720
    assert wait["totals"]["extreme_bound_c4"] == 2734
    assert wait["timeout_evaluation"]["registered_bridge_timeout"] == 4096
    assert wait["timeout_evaluation"]["approved_by_kalash"] is False
    assert wait["timeout_evaluation"]["bridge_timeout_status"] == "PROPOSED_PENDING_KALASH_APPROVAL"
    assert wait["timeout_evaluation"]["margin_over_c4_max"] > 2.0
    assert wait["timeout_evaluation"]["recommendation"] == "RETAIN_4096"


def test_step12_timeout_distinctions_and_arbiter_applicability():
    """Verify distinct timeouts and explicit arbiter bounds applicability."""
    # 1. Distinct timeout constants
    assert BENCH_TIMEOUT_CYCLES == 600
    assert MERGED_NI_SLOT_TIMEOUT_CYCLES == 8192
    assert BRIDGE_TIMEOUT_PROPOSED_CYCLES == 4096
    assert VERIFIER_TIMEOUT_CYCLES == 100000

    # Ensure none are conflated
    timeouts = [BENCH_TIMEOUT_CYCLES, MERGED_NI_SLOT_TIMEOUT_CYCLES, BRIDGE_TIMEOUT_PROPOSED_CYCLES, VERIFIER_TIMEOUT_CYCLES]
    assert len(set(timeouts)) == 4

    # 2. Timeout registry checks
    reg = build_timeout_registry()
    assert reg["hierarchy_checks"]["merged_ni_slot_timeout_gt_bridge_timeout"] is True
    assert reg["hierarchy_checks"]["bridge_timeout_lt_verifier_timeout"] is True
    assert reg["hierarchy_checks"]["bench_timeout_ne_merged_timeout"] is True

    # 3. validate_timeout_metadata error handling
    valid_meta = {
        "bench_timeout_cycles": 600,
        "merged_ni_slot_timeout_cycles": 8192,
        "timeout_applied_cycles": 600,
        "timeout_applied_kind": "BENCH",
        "timeout_provenance": {
            "bench_timeout_cycles": {"source": "tb_i9_integ.sv", "classification": "CONFIG"},
            "merged_ni_slot_timeout_cycles": {"source": "M-F1 rev 8", "classification": "CONFIG"},
        },
    }
    validate_timeout_metadata(valid_meta)

    # Conflation failure test
    conflated = dict(valid_meta)
    conflated["bench_timeout_cycles"] = 8192
    with pytest.raises(ValueError, match="conflated"):
        validate_timeout_metadata(conflated)

    # Missing field test
    missing = dict(valid_meta)
    del missing["bench_timeout_cycles"]
    with pytest.raises(ValueError, match="missing timeout field"):
        validate_timeout_metadata(missing)

    # Wrong applied timeout test
    wrong_applied = dict(valid_meta)
    wrong_applied["timeout_applied_cycles"] = 8192
    with pytest.raises(ValueError, match="does not match 600"):
        validate_timeout_metadata(wrong_applied)

    # Missing provenance test
    no_prov = dict(valid_meta)
    no_prov["timeout_provenance"] = {}
    with pytest.raises(ValueError, match="missing provenance"):
        validate_timeout_metadata(no_prov)

    # 4. Arbiter applicability documentation
    bounds = {entry["bound"]: entry for entry in ARBITER_APPLICABILITY}
    assert "J_MAX" in bounds
    assert "P" in bounds
    assert "Q" in bounds
    assert "CPU memory request path" in bounds

    # J_MAX is inside jobs, not added separately
    assert bounds["J_MAX"]["cycles"] == 128
    assert bounds["J_MAX"]["added_to_cpu_wait_total"] is False

    # P is applied once as contention bound
    assert bounds["P"]["cycles"] == 269
    assert bounds["P"]["added_to_cpu_wait_total"] is True

    # Q is for non-RoT response traffic, not added directly to P contention scenario
    assert bounds["Q"]["cycles"] == 792
    assert bounds["Q"]["added_to_cpu_wait_total"] is False

    # CPU memory request is plain data in P7
    assert bounds["CPU memory request path"]["traversed_by_cpu_memory_request"] is False
    assert bounds["CPU memory request path"]["added_to_cpu_wait_total"] is False
