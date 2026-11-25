"""
Unit and regression tests for P7 Differential Verification Framework
(verification/p7_differential.py).
"""

import json
from pathlib import Path
import pytest

from verification.p7_differential import (
    ComparisonStatus,
    DeterministicVector,
    DiffObservation,
    P7DifferentialComparator,
    P7SimLogParser,
    P7VectorBridge,
    P7VectorGenerator,
    TESTBENCH_INTERFACES,
)
from verification.p7_packet_model import ProtocolProfile
from verification.p7_security_model import (
    GateFaultReason,
    L2RejectReason,
    MemoryFaultReason,
    NIProtocolErrorReason,
)


@pytest.fixture
def workspace_root():
    return Path(__file__).resolve().parents[2]


@pytest.fixture
def comparator(workspace_root):
    return P7DifferentialComparator(workspace_root)


@pytest.fixture
def vec_gen():
    return P7VectorGenerator()


# ==============================================================================
# 1. Testbench Catalog Tests
# ==============================================================================

def test_testbench_interfaces_catalog():
    """Verify that all required P7 testbenches and signals are cataloged."""
    expected_tbs = {
        "tb_l2p7_equiv",
        "tb_ni_n81_p7",
        "tb_p7_gate_data",
        "tb_p7_refuse_grant",
        "tb_p7_ingress",
        "tb_p7_c4",
        "kmac_tb",
    }
    assert expected_tbs.issubset(TESTBENCH_INTERFACES.keys())

    # Verify key signals exist with expected widths
    l2_sigs = TESTBENCH_INTERFACES["tb_l2p7_equiv"]
    assert l2_sigs["pnf"].width == 36
    assert l2_sigs["pwhy"].width == 4
    assert l2_sigs["prej"].width == 32
    assert l2_sigs["tag_q"].width == 128
    assert l2_sigs["rfresh"].width == 160

    gate_sigs = TESTBENCH_INTERFACES["tb_p7_gate_data"]
    assert gate_sigs["authorized"].width == 6
    assert gate_sigs["memory_commits"].width == 32


# ==============================================================================
# 2. Vector Generation Tests
# ==============================================================================

def test_deterministic_vector_generation(vec_gen):
    """Verify that all 14 required security/protocol scenarios are generated."""
    vectors = vec_gen.generate_all_scenarios()
    assert len(vectors) == 14

    scen_ids = [v.scenario_id for v in vectors]
    expected_ids = [
        "SCEN_01_VALID_CONTROL_PACKET",
        "SCEN_02_INVALID_MAC",
        "SCEN_03_INCORRECT_EPOCH",
        "SCEN_04_SEQUENCE_ZERO",
        "SCEN_05_REPLAYED_SEQUENCE",
        "SCEN_06_VALID_GRANT",
        "SCEN_07_INVALID_GRANT",
        "SCEN_08_REVOKE",
        "SCEN_09_UNAUTHORIZED_MEM_READ",
        "SCEN_10_UNAUTHORIZED_MEM_WRITE",
        "SCEN_11_REVOCATION_DURING_READ",
        "SCEN_12_REVOCATION_DURING_WRITE",
        "SCEN_13_TAG_MISMATCH",
        "SCEN_14_SLOT_EXHAUSTION",
    ]
    for exp_id in expected_ids:
        assert exp_id in scen_ids

    # Check wire lengths of control messages (must have +5 freshness overhead)
    scen1 = next(v for v in vectors if v.scenario_id == "SCEN_01_VALID_CONTROL_PACKET")
    assert scen1.expected_verdict == "ACCEPT"
    assert len(scen1.wire_flits) == 17  # 12 NI + 5 freshness
    assert len(scen1.ni_flits) == 12


# ==============================================================================
# 3. Vector Bridge & Export Tests
# ==============================================================================

def test_vector_serialization_json(vec_gen, tmp_path):
    """Test exporting vectors to JSON and round-tripping."""
    vectors = vec_gen.generate_all_scenarios()
    json_file = tmp_path / "test_vectors.json"
    P7VectorBridge.export_to_json(vectors, json_file)

    assert json_file.exists()
    data = json.loads(json_file.read_text(encoding="utf-8"))
    assert len(data) == 14
    assert data[0]["scenario_id"] == "SCEN_01_VALID_CONTROL_PACKET"


def test_vector_serialization_sv(vec_gen, tmp_path):
    """Test exporting vectors to SystemVerilog stimulus package."""
    vectors = vec_gen.generate_all_scenarios()
    sv_file = tmp_path / "test_vectors.sv"
    P7VectorBridge.export_to_sv(vectors, sv_file)

    assert sv_file.exists()
    content = sv_file.read_text(encoding="utf-8")
    assert "package p7_diff_vectors_pkg;" in content
    assert "localparam int NUM_VECTORS = 14;" in content
    assert "32'h" in content


# ==============================================================================
# 4. Simulation Output Parser Tests
# ==============================================================================

def test_sim_log_parser_valid_log(workspace_root):
    """Verify parsing of actual RTL simulation log `logs/s3_kmac_2026-09-23.log`."""
    log_path = workspace_root / "logs" / "s3_kmac_2026-09-23.log"
    result = P7SimLogParser.parse_log(log_path)

    assert result["exists"] is True
    assert result["errors"] == 0
    assert result["checks"] == 11
    assert result["status"] == "PASS"
    assert any("L=128 KAT (out_len_sel low)" in line for line in result["passed_checks"])


def test_sim_log_parser_missing_log(tmp_path):
    """Verify graceful handling when a simulation log is missing."""
    log_path = tmp_path / "non_existent.log"
    result = P7SimLogParser.parse_log(log_path)
    assert result["exists"] is False
    assert result["status"] == "NOT_FOUND"
    assert result["checks"] == 0


def test_sim_log_parser_error_detection(tmp_path):
    """Verify that errors and fatal terminations in a log are accurately extracted."""
    bad_log = tmp_path / "bad_sim.log"
    bad_log.write_text(
        "PASS: test 1\n"
        "[FAIL] GATE_DATA_REFUSED_0 authorized=1\n"
        "CHECKS : 2\n"
        "ERRORS : 1\n"
        "RESULT : FAIL\n",
        encoding="utf-8",
    )
    result = P7SimLogParser.parse_log(bad_log)
    assert result["exists"] is True
    assert result["errors"] == 1
    assert result["checks"] == 2
    assert result["status"] == "FAIL"
    assert len(result["failed_checks"]) == 1


# ==============================================================================
# 5. MAC Cryptographic Equivalence Tests
# ==============================================================================

def test_mac_cryptographic_equivalence(comparator):
    """
    CRITICAL: Verify bit-exact cryptographic equivalence between Python KMAC128
    and RTL hardware outputs across all KAT vectors.
    """
    res = comparator.verify_mac_cryptographic_equivalence()
    assert res["status"] == "PASS"
    assert res["matched_kats"] == 6
    assert res["total_kats"] == 6
    assert res["l128_absorbed_status"] == "VERIFIED_EQUIVALENT"

    # Specific check for Test 6 (L=128 KAT, out_len_sel low)
    kat6 = next(k for k in res["kat_results"] if k["kat_id"] == "TB_TEST_6_L128")
    assert kat6["matched"] is True
    assert kat6["python_output_le"] == "0x1f2915cfef11bdfabebf8e536b71fa30"


# ==============================================================================
# 6. Differential Suite & Scenario Evaluations
# ==============================================================================

def test_differential_evaluations_count_and_status(comparator):
    """
    Verify that all 14 scenarios + crypto equiv are evaluated, and unexecuted
    XSim testbenches are correctly categorized as NOT OBSERVED rather than fake PASS.
    """
    observations = comparator.evaluate_scenarios()
    assert len(observations) == 15

    # Exactly 1 PASS (KMAC crypto equivalence confirmed against logs/s3_kmac_2026-09-23.log)
    pass_obs = [o for o in observations if o.status == ComparisonStatus.PASS]
    assert len(pass_obs) == 1
    assert pass_obs[0].scenario_id == "SCEN_CRYPTO_KMAC128_EQUIV"

    # Exactly 14 NOT OBSERVED (because batch XSim executable is not present on this host)
    not_obs = [o for o in observations if o.status == ComparisonStatus.NOT_OBSERVED]
    assert len(not_obs) == 14

    # 0 false FAILs
    fail_obs = [o for o in observations if o.status == ComparisonStatus.FAIL]
    assert len(fail_obs) == 0


def test_scenario_rejection_reasons(vec_gen):
    """Verify expected rejection reasons for negative security scenarios."""
    vectors = {v.scenario_id: v for v in vec_gen.generate_all_scenarios()}

    # MAC mismatch -> L2 reason 2
    assert vectors["SCEN_02_INVALID_MAC"].expected_reason == int(L2RejectReason.MAC_MISMATCH)

    # Epoch mismatch -> L2 reason 3
    assert vectors["SCEN_03_INCORRECT_EPOCH"].expected_reason == int(L2RejectReason.EPOCH_MISMATCH)

    # Sequence violation -> L2 reason 4
    assert vectors["SCEN_04_SEQUENCE_ZERO"].expected_reason == int(L2RejectReason.SEQUENCE_VIOLATION)
    assert vectors["SCEN_05_REPLAYED_SEQUENCE"].expected_reason == int(L2RejectReason.SEQUENCE_VIOLATION)

    # Invalid grant status -> Gate fault 3
    assert vectors["SCEN_07_INVALID_GRANT"].expected_reason == int(GateFaultReason.INVALID_GRANT_STATUS)

    # Unauthorized memory -> Memory fault 6
    assert vectors["SCEN_09_UNAUTHORIZED_MEM_READ"].expected_reason == int(MemoryFaultReason.UNAUTHORIZED_ACCESS)
    assert vectors["SCEN_10_UNAUTHORIZED_MEM_WRITE"].expected_reason == int(MemoryFaultReason.UNAUTHORIZED_ACCESS)


def test_full_differential_suite_run(comparator, tmp_path):
    """Test full execution of the differential runner and report generation."""
    report = comparator.run_full_differential_suite(output_dir=tmp_path)
    assert report["summary"]["total_evaluations"] == 15
    assert report["summary"]["pass_count"] == 1
    assert report["summary"]["not_observed_count"] == 14
    assert report["summary"]["fail_count"] == 0
    assert report["summary"]["mac_cryptographic_equivalence"] == "PASS"

    # Verify generated report file
    report_file = tmp_path / "p7_differential_report.json"
    assert report_file.exists()


def test_authoritative_kmac_reference_binding():
    """
    Verify that the differential verification framework is actively bound to
    the authoritative teammate KMAC reference and NOT the demoted repo reference.
    """
    from verification.p7_kmac_adapter import get_kmac_reference_metadata

    meta = get_kmac_reference_metadata()
    assert meta["status"] == "AUTHORITATIVE_PINNED"
    assert meta["authoritative_reference"]["sha256"] == "ac8076e665b6b838c58b9b3458b6e3cd16101fbab4dc0d90fbc78f90497ce394"
    assert meta["authoritative_reference"]["source_archive_sha256"] == "047bb5a981050f11a572a60e850f7c7511ff5d636f7903c6a8d239891003c6a0"
    assert "software/pq_attest_final/PQ_Attest/software/kmac128_ref.py" in meta["authoritative_reference"]["path"]
    assert meta["demoted_reference"]["status"] == "DEMOTED_SUPPLEMENTARY_KAT_ONLY"

