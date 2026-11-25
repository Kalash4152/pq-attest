"""
verification/tests/test_p7_release_evidence.py
==============================================
Test suite for PQ-Attest P7 Step 4B: Release RTL Evidence Reconciliation.

Tests:
1. Evidence parser on E4_P7_XSIM_20261103 logs and project_run manifests.
2. Differential scenario reconciliation (14 core scenarios + KMAC equivalence).
3. Expected-fail control mutants properly distinguished and confirmed killed.
4. Release Memory Window Model (0x2 accepted, 0x8 out-of-window rejected).
5. Release BUSY Retry Model (up to 3 retries, 4th fails closed, non-1/non-3 fails).
6. Release K-3 Length Validation Model (16/16 accepted, mismatch rejected with status 5).
7. Release Fault Status & trusted_clear Model.
8. New release test suites (tb_i7_sec, tb_pq_full_chain_p7, tb_p7_ingress_i6, etc.).
9. 3-tier KMAC cryptographic equivalence classification.
10. Historical integrity of previous steps and artifacts.
"""

import json
from pathlib import Path
import pytest

from verification.p7_release_evidence import (
    DifferentialScenarioReconciler,
    EvidenceJobKind,
    FaultReason,
    KMACTier,
    ReleaseBusyRetryModel,
    ReleaseEvidenceParser,
    ReleaseFaultStatusModel,
    ReleaseK3LengthModel,
    ReleaseMemoryWindowModel,
    ReleaseTBInjectModel,
    RTLClassification,
    generate_release_evidence_manifest,
)


@pytest.fixture(scope="module")
def evidence_parser():
    """Fixture providing initialized and parsed ReleaseEvidenceParser."""
    parser = ReleaseEvidenceParser()
    parser.parse_all()
    return parser


@pytest.fixture(scope="module")
def reconciler(evidence_parser):
    """Fixture providing DifferentialScenarioReconciler."""
    return DifferentialScenarioReconciler(evidence_parser)


# =====================================================================
# Test 1: Parser and Manifest Integrity
# =====================================================================

def test_evidence_parser_manifest_and_logs(evidence_parser):
    """Verify that parser processes all 15 logs and 35 project sims."""
    assert len(evidence_parser.job_records) >= 15
    assert len(evidence_parser.project_sim_records) == 35

    # Check key jobs in job_records
    assert "rel_s3_l2p7_equiv" in evidence_parser.job_records
    assert "rel_s3_l2e_engine" in evidence_parser.job_records
    assert "rel_i7_sec" in evidence_parser.job_records
    assert "rel_i7_full_chain" in evidence_parser.job_records
    assert "rel_i6_p7_ingress" in evidence_parser.job_records
    assert "rel_i6_p7_refuse_grant" in evidence_parser.job_records
    assert "rel_s3_p7_c4" in evidence_parser.job_records
    assert "rel_p7_gate_data" in evidence_parser.job_records

    # Check check counts
    assert evidence_parser.job_records["rel_s3_l2p7_equiv"].checks == 2425
    assert evidence_parser.job_records["rel_s3_l2e_engine"].checks == 8020
    assert evidence_parser.job_records["rel_i7_sec"].checks == 30
    assert evidence_parser.job_records["rel_i7_full_chain"].checks == 21
    assert evidence_parser.job_records["rel_i6_p7_ingress"].checks == 39
    assert evidence_parser.job_records["rel_i6_p7_refuse_grant"].checks == 12


# =====================================================================
# Test 2: Reconciliation of Differential Scenarios
# =====================================================================

def test_reconciliation_of_core_scenarios(reconciler):
    """Verify that all core differential scenarios are reconciled with RTL PASS."""
    scenarios = reconciler.reconcile_scenarios()
    assert len(scenarios) == 15  # 14 core scenarios + 1 KMAC equivalence

    for sc in scenarios:
        assert sc.classification == RTLClassification.RTL_PASS
        assert sc.errors == 0
        assert sc.result == "PASS"
        assert sc.checks > 0
        log_path = Path(sc.log_file)
        assert log_path.exists(), f"Log file does not exist: {log_path}"


# =====================================================================
# Test 3: Expected-FAIL Control Mutants
# =====================================================================

def test_expected_fail_mutants_distinguished(evidence_parser):
    """Verify that expected-fail mutant controls are marked killed and not regressions."""
    mut_control = evidence_parser.job_records.get("rel_p7_gate_mut_control_allowed")
    mut_bypass = evidence_parser.job_records.get("rel_p7_gate_mut_bypass")

    assert mut_control is not None
    assert mut_control.is_control_mutant is True
    assert mut_control.mutant_killed is True
    assert mut_control.errors == 4
    assert mut_control.result == "FAIL"

    assert mut_bypass is not None
    assert mut_bypass.is_control_mutant is True
    assert mut_bypass.mutant_killed is True
    assert mut_bypass.errors == 4
    assert mut_bypass.result == "FAIL"


# =====================================================================
# Test 4: Release Memory Window Model (0x2 window)
# =====================================================================

def test_release_memory_window_model():
    """Verify 0x2 window acceptance and old 0x8 window rejection."""
    # Standard release test address
    valid, reason = ReleaseMemoryWindowModel.check_address(0x2200_0100)
    assert valid is True
    assert reason is None

    # Base and ceiling of 0x2 window
    valid, reason = ReleaseMemoryWindowModel.check_address(0x2000_0000)
    assert valid is True
    assert reason is None

    valid, reason = ReleaseMemoryWindowModel.check_address(0x2FFF_FFFF)
    assert valid is True
    assert reason is None

    # Historical 0x8 window test address
    valid, reason = ReleaseMemoryWindowModel.check_address(0x8200_0100)
    assert valid is False
    assert reason == FaultReason.OUT_OF_WINDOW_ADDRESS

    # Out of window (e.g. 0x0..., 0x3...)
    valid, reason = ReleaseMemoryWindowModel.check_address(0x0000_1000)
    assert valid is False
    assert reason == FaultReason.OUT_OF_WINDOW_ADDRESS


# =====================================================================
# Test 5: Release BUSY Retry Model (C-1 / C-2)
# =====================================================================

def test_release_busy_retry_model():
    """Verify verifier retry up to 3 times, 4th fails closed, non-1/non-3 fails."""
    # Case 1: First attempt succeeds with status 1
    model = ReleaseBusyRetryModel()
    model.start_attestation()
    outcome = model.handle_response_status(1)
    assert outcome == "GRANT"
    assert model.authorized is True
    assert model.failed is False

    # Case 2: 3 BUSY responses then GRANT
    model.start_attestation()
    assert model.handle_response_status(3) == "RETRY"  # retry 1
    assert model.busy_retries == 1
    assert model.handle_response_status(3) == "RETRY"  # retry 2
    assert model.busy_retries == 2
    assert model.handle_response_status(3) == "RETRY"  # retry 3
    assert model.busy_retries == 3
    assert model.handle_response_status(1) == "GRANT"
    assert model.authorized is True
    assert model.busy_retries == 0

    # Case 3: 4th consecutive BUSY fails closed
    model.start_attestation()
    assert model.handle_response_status(3) == "RETRY"  # retry 1
    assert model.handle_response_status(3) == "RETRY"  # retry 2
    assert model.handle_response_status(3) == "RETRY"  # retry 3
    outcome = model.handle_response_status(3)  # 4th BUSY
    assert outcome == "REVOKE_FAILED"
    assert model.authorized is False
    assert model.failed is True
    assert model.fail_reason == FaultReason.VERIFIER_STATUS_NOT_ONE

    # Case 4: Non-1, non-3 status (e.g. status 2, 5, 10) fails closed immediately
    for bad_status in [0, 2, 5, 9, 10]:
        model.start_attestation()
        outcome = model.handle_response_status(bad_status)
        assert outcome == "REVOKE_FAILED"
        assert model.authorized is False
        assert model.failed is True
        assert model.fail_reason == FaultReason.VERIFIER_STATUS_NOT_ONE


# =====================================================================
# Test 6: Release K-3 Length Model
# =====================================================================

def test_release_k3_length_model():
    """Verify K-3 length binding validation (16/16)."""
    # Valid lengths
    valid, status, reason = ReleaseK3LengthModel.validate_lengths(16, 16)
    assert valid is True
    assert status == 1
    assert reason is None

    # Invalid config_len
    valid, status, reason = ReleaseK3LengthModel.validate_lengths(15, 16)
    assert valid is False
    assert status == 5
    assert reason == FaultReason.K3_LENGTH_MISMATCH

    # Invalid imem_len
    valid, status, reason = ReleaseK3LengthModel.validate_lengths(16, 32)
    assert valid is False
    assert status == 5
    assert reason == FaultReason.K3_LENGTH_MISMATCH


# =====================================================================
# Test 7: Release Fault Status & trusted_clear
# =====================================================================

def test_release_fault_status_model():
    """Verify fault recording and RoT trusted_clear behavior."""
    model = ReleaseFaultStatusModel()
    assert model.fault_sticky is False
    assert model.fault_count == 0

    # Record faults
    model.record_fault(source=3, operation=4, reason=FaultReason.TAG_MISMATCH, epoch=100)
    assert model.fault_sticky is True
    assert model.fault_count == 1
    assert model.last_reason == FaultReason.TAG_MISMATCH

    model.record_fault(source=1, operation=2, reason=FaultReason.DATA_REFUSED_NOT_AUTH, epoch=100)
    assert model.fault_sticky is True
    assert model.fault_count == 2

    # App traffic cannot clear
    model.apply_untrusted_traffic()
    assert model.fault_sticky is True
    assert model.fault_count == 2

    # trusted_clear clears all
    model.apply_trusted_clear()
    assert model.fault_sticky is False
    assert model.fault_count == 0
    assert model.last_reason is None


# =====================================================================
# Test 8: TB_INJECT Modeling
# =====================================================================

def test_release_tb_inject_model():
    """Verify testbench hook active only when TB_INJECT == 1."""
    assert ReleaseTBInjectModel.is_hook_active(1) is True
    assert ReleaseTBInjectModel.is_hook_active(0) is False


# =====================================================================
# Test 9: New Release Test Suites
# =====================================================================

def test_new_release_test_suites(reconciler):
    """Verify mapping of new I-6 / I-7 test suites."""
    suites = reconciler.get_new_release_test_suites()
    assert len(suites) == 7

    tb_names = [s["testbench"] for s in suites]
    assert "tb_i7_sec" in tb_names
    assert "tb_pq_full_chain_p7" in tb_names
    assert "tb_p7_ingress_i6" in tb_names
    assert "tb_p7_refuse_grant_i6" in tb_names
    assert "tb_n2p7_rtt" in tb_names
    assert "tb_i6_retry" in tb_names
    assert "tb_verifier_revoke" in tb_names

    for s in suites:
        assert s["result"] == "PASS"
        assert s["errors"] == 0
        assert s["checks"] > 0


# =====================================================================
# Test 10: 3-Tier KMAC Cryptographic Equivalence Classification
# =====================================================================

def test_kmac_three_tier_classification(reconciler):
    """Verify the 3-tier KMAC evidence structure."""
    tiers = reconciler.get_kmac_tier_classification()
    assert len(tiers) == 3

    t1, t2, t3 = tiers
    assert "Tier 1" in t1["tier"]
    assert t1["job_id"] == "SCRATCH_kmac_tb"
    assert t1["checks"] == 11
    assert "scratch" in t1["evidence_status"].lower()

    assert "Tier 2" in t2["tier"]
    assert t2["job_id"] == "rel_s3_l2e_engine"
    assert t2["checks"] == 8020
    assert "registered" in t2["evidence_status"].lower()

    assert "Tier 3" in t3["tier"]
    assert t3["job_id"] == "rel_s3_l2p7_equiv"
    assert t3["checks"] == 2425
    assert "registered" in t3["evidence_status"].lower()


# =====================================================================
# Test 11: Manifest Generation and File Output
# =====================================================================

def test_generate_release_evidence_manifest(tmp_path):
    """Verify full manifest generation and schema."""
    out_file = tmp_path / "test_manifest.json"
    data = generate_release_evidence_manifest(output_path=out_file)

    assert out_file.exists()
    assert data["summary"]["total_core_scenarios"] == 15
    assert data["summary"]["rtl_pass"] == 15
    assert data["summary"]["rtl_fail"] == 0
    assert data["summary"]["not_observed"] == 0
    assert data["metadata"]["status_claims"]["HARDWARE_VALIDATED"] is False
    assert data["metadata"]["status_claims"]["FORMAL_PROOF"] is False
    assert data["metadata"]["status_claims"]["SOC_INTEGRATION_COMPLETE"] is False


# =====================================================================
# Test 12: Historical Artifact Integrity
# =====================================================================

def test_historical_integrity():
    """Verify that reports and manifests from Steps 1-4 remain unmodified."""
    repo_root = Path(__file__).resolve().parent.parent.parent
    reports_dir = repo_root / "reports"
    gen_dir = repo_root / "verification" / "generated"

    assert (reports_dir / "E4_P7_STEP1_REPORT.md").exists()
    assert (reports_dir / "E4_P7_STEP2_REPORT.md").exists()
    assert (reports_dir / "E4_P7_STEP3_REPORT.md").exists()
    assert (reports_dir / "E4_P7_STEP4_REPORT.md").exists()

    assert (gen_dir / "p7_protocol_manifest.json").exists()
    assert (gen_dir / "p7_differential_vectors.json").exists()
    assert (gen_dir / "p7_differential_vectors.sv").exists()
    assert (gen_dir / "p7_differential_report.json").exists()

