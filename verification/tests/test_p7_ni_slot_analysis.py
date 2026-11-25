"""
verification/tests/test_p7_ni_slot_analysis.py
==============================================
PQ-Attest P7 NI Slot-Leak Analysis Tests — Step 13.

Engineer 4 Verification Infrastructure.

Tests:
1. Scenario 1: Normal completion.
2. Scenario 2: Two outstanding slots (capacity saturation).
3. Scenario 3: One lost response recovery.
4. Scenario 4: Both lost responses recovery.
5. Scenario 5: Exact 600-cycle timeout release boundary.
6. Scenario 6: Reset with one occupied slot.
7. Scenario 7: Reset with both occupied slots.
8. Scenario 8: Late response classification and drop.
9. Scenario 9: Stale response rejection on tag reuse.
10. Scenario 10: 10 repeated timeout/reuse cycles (zero cumulative leak).
11. Scenario 11: Unexpected response with unmapped tag.
12. Scenario 12: Backpressure rejection when table is full.
13. Scenario 13: Duplicate response release idempotence.
14. Scenario 14: Boundary allocation handling.
15. Invariants verification (INV_MAX_CAPACITY, INV_NO_PERMANENT_LEAK).
16. Results manifest generation and schema check.
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
from verification.p7_ni_slot_analysis import (
    BENCH_TIMEOUT_CYCLES,
    MERGED_NI_SLOT_TIMEOUT_CYCLES,
    NISlotLeakAnalyzer,
    generate_ni_slot_analysis_manifest,
    validate_step13_timeout_metadata,
)


@pytest.fixture
def analyzer():
    return NISlotLeakAnalyzer(slot_timeout=600)


def test_scenario_01_normal_completion(analyzer):
    res = analyzer.scenario_01_normal_completion()
    assert res.passed is True
    assert res.final_occupancy == 0


def test_scenario_02_two_outstanding_slots(analyzer):
    res = analyzer.scenario_02_two_outstanding_slots()
    assert res.passed is True
    assert res.final_occupancy == 0


def test_scenario_03_one_lost_response(analyzer):
    res = analyzer.scenario_03_one_lost_response()
    assert res.passed is True
    assert res.final_occupancy == 0


def test_scenario_04_both_lost_responses(analyzer):
    res = analyzer.scenario_04_both_lost_responses()
    assert res.passed is True
    assert res.final_occupancy == 0


def test_scenario_05_timeout_boundary(analyzer):
    res = analyzer.scenario_05_timeout()
    assert res.passed is True
    assert res.final_occupancy == 0


def test_scenario_06_reset_one_occupied(analyzer):
    res = analyzer.scenario_06_reset_one_occupied()
    assert res.passed is True
    assert res.final_occupancy == 0


def test_scenario_07_reset_both_occupied(analyzer):
    res = analyzer.scenario_07_reset_both_occupied()
    assert res.passed is True
    assert res.final_occupancy == 0


def test_scenario_08_late_response(analyzer):
    res = analyzer.scenario_08_late_response()
    assert res.passed is True
    assert res.final_occupancy == 0


def test_scenario_09_stale_response_tag_reuse(analyzer):
    res = analyzer.scenario_09_stale_response_tag_reuse()
    assert res.passed is True
    assert res.final_occupancy == 0


def test_scenario_10_repeated_timeout_reuse_cycles(analyzer):
    res = analyzer.scenario_10_repeated_timeout_reuse_cycles()
    assert res.passed is True
    assert res.final_occupancy == 0


def test_scenario_11_unexpected_response(analyzer):
    res = analyzer.scenario_11_unexpected_response()
    assert res.passed is True
    assert res.final_occupancy == 1  # Unrelated active slot remains untouched


def test_scenario_12_backpressure(analyzer):
    res = analyzer.scenario_12_backpressure()
    assert res.passed is True
    assert res.final_occupancy == 2  # Remains at capacity


def test_scenario_13_duplicate_release(analyzer):
    res = analyzer.scenario_13_duplicate_release()
    assert res.passed is True
    assert res.final_occupancy == 0


def test_scenario_14_invalid_allocation(analyzer):
    res = analyzer.scenario_14_invalid_allocation()
    assert res.passed is True
    assert res.final_occupancy == 0


def test_all_14_scenarios_pass_in_suite(analyzer):
    data = analyzer.run_all_scenarios()
    assert data["summary"]["total_scenarios"] == 14
    assert data["summary"]["passed_scenarios"] == 14
    assert data["summary"]["overall_status"] == "PASS"

    # Check invariants
    invs = data["invariants"]
    assert invs["INV_MAX_CAPACITY"]["status"] == "PASS"
    assert invs["INV_NO_PERMANENT_LEAK"]["status"] == "PASS"
    assert invs["INV_RESET_CLEANUP"]["status"] == "PASS"


def test_ni_slot_analysis_manifest_generation(tmp_path):
    out_file = tmp_path / "ni_slot_analysis.json"
    data = generate_ni_slot_analysis_manifest(out_file)

    assert out_file.exists()
    assert data["summary"]["overall_status"] == "PASS"
    assert len(data["scenarios"]) == 14
    assert "safety_statement" in data["metadata"]
    assert "liveness_statement" in data["metadata"]


def test_step13_timeout_metadata_unambiguity_and_conflation_prevention():
    """Verify bench (600) vs merged (8192) timeouts, provenance, and conflation rejection."""
    # 1. Distinct constants
    assert BENCH_TIMEOUT_CYCLES == 600
    assert MERGED_NI_SLOT_TIMEOUT_CYCLES == 8192
    assert BENCH_TIMEOUT_CYCLES != MERGED_NI_SLOT_TIMEOUT_CYCLES

    analyzer = NISlotLeakAnalyzer(slot_timeout=BENCH_TIMEOUT_CYCLES)
    data = analyzer.run_all_scenarios()
    meta = data["metadata"]

    # 2. Metadata completeness and distinction
    assert meta["bench_timeout_cycles"] == 600
    assert meta["merged_ni_slot_timeout_cycles"] == 8192
    assert meta["timeout_applied_cycles"] == 600
    assert meta["timeout_applied_kind"] == "BENCH"

    # Provenance
    prov = meta["timeout_provenance"]
    assert "bench_timeout_cycles" in prov
    assert "merged_ni_slot_timeout_cycles" in prov
    assert "tb_i9_integ.sv" in prov["bench_timeout_cycles"]["source"]
    assert prov["bench_timeout_cycles"]["classification"] == "CONFIGURATION_PARAMETER"
    assert "E4_FINAL_INTAKE" in prov["merged_ni_slot_timeout_cycles"]["source"]
    assert prov["merged_ni_slot_timeout_cycles"]["classification"] == "REVIEWER_STATED_CONFIGURATION"

    # 3. Validation failure on conflation
    conflated = dict(meta)
    conflated["bench_timeout_cycles"] = 8192
    with pytest.raises(ValueError, match="conflated"):
        validate_step13_timeout_metadata(conflated)

    # Missing fields
    missing_bench = dict(meta)
    del missing_bench["bench_timeout_cycles"]
    with pytest.raises(ValueError, match="Missing"):
        validate_step13_timeout_metadata(missing_bench)

    missing_merged = dict(meta)
    del missing_merged["merged_ni_slot_timeout_cycles"]
    with pytest.raises(ValueError, match="Missing"):
        validate_step13_timeout_metadata(missing_merged)

    # Missing provenance
    bad_prov = dict(meta)
    bad_prov["timeout_provenance"] = {}
    with pytest.raises(ValueError, match="missing bench or merged"):
        validate_step13_timeout_metadata(bad_prov)

    # 4. Verification that every scenario specifies the applied timeout kind
    for s in data["scenarios"]:
        assert s["timeout_applied_cycles"] == 600
        assert s["timeout_applied_kind"] == "BENCH"

    # 5. Check merged analyzer execution correctly tags MERGED
    merged_analyzer = NISlotLeakAnalyzer(slot_timeout=MERGED_NI_SLOT_TIMEOUT_CYCLES)
    merged_data = merged_analyzer.run_all_scenarios()
    assert merged_data["metadata"]["timeout_applied_cycles"] == 8192
    assert merged_data["metadata"]["timeout_applied_kind"] == "MERGED"
    for s in merged_data["scenarios"]:
        assert s["timeout_applied_cycles"] == 8192
        assert s["timeout_applied_kind"] == "MERGED"

