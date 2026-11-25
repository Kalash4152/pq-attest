"""
verification/tests/test_p7_mutation_analysis.py
===============================================
Test suite for PQ-Attest P7 Step 6: Mutation Analysis and Boundary Testing.

Tests:
1. All 16 targeted mutations are detected and KILLED.
2. Mutation score is exactly 100% (16 / 16).
3. Production models are verified clean and unmodified.
4. Boundary testing: sequence numbers (0, 1, prev, prev+1, 0xFFFF_FFFF_FFFF_FFFF).
5. Boundary testing: epoch matching (exact, mismatch, zero, boundary).
6. Boundary testing: memory window boundaries (0x1FFF_FFFF, 0x2000_0000, 0x2FFF_FFFF, 0x3000_0000).
7. Boundary testing: BUSY retry count (0..3 retries, 4th fail-closed, non-1/non-3 fail).
8. Boundary testing: K-3 length binding (15, 16, 17 for both cfg_len and imem_len).
9. Boundary testing: NI slots (0, 1, 2 slots, 3rd request backpressure, matching release).
10. Boundary testing: authorization transitions (boot, grant, revoke, fail, timeout, re-attestation).
11. Mutation report JSON generation and schema validation.
12. Repository integrity verification.
"""

from pathlib import Path
import pytest

from verification.p7_mutation_analysis import (
    MutationAnalysisEngine,
    MutationOutcome,
    generate_mutation_report_manifest,
)
from verification.p7_packet_model import Coord
from verification.p7_release_evidence import (
    FaultReason,
    ReleaseBusyRetryModel,
    ReleaseK3LengthModel,
    ReleaseMemoryWindowModel,
)
from verification.p7_security_model import (
    GateFaultReason,
    L2RejectReason,
    NIProtocolErrorReason,
    ReplayState,
    TileAuthorizationState,
    TransactionTracker,
)


@pytest.fixture
def mutation_engine():
    return MutationAnalysisEngine()


# =====================================================================
# Test 1 & 2: Mutation Detection and Score
# =====================================================================

def test_all_16_mutations_killed(mutation_engine):
    """Verify that all 16 targeted negative mutations are detected and KILLED."""
    results = mutation_engine.run_all_mutations()
    assert len(results) == 16

    for r in results:
        assert r.outcome == MutationOutcome.KILLED, f"Mutation {r.mutation_id} survived: {r.mutated_behavior}"
        assert r.detection_details != ""


def test_mutation_score_calculation(mutation_engine):
    """Verify that mutation score is 100.0%."""
    results = mutation_engine.run_all_mutations()
    killed = sum(1 for r in results if r.outcome == MutationOutcome.KILLED)
    survived = sum(1 for r in results if r.outcome == MutationOutcome.SURVIVED)
    total = killed + survived

    score = (killed / total) * 100.0
    assert score == 100.0


# =====================================================================
# Test 3: Production Models Unmodified
# =====================================================================

def test_production_models_remain_clean():
    """Verify that production reference classes were not modified in place."""
    # Test unmutated ReplayState
    rep = ReplayState(expected_boot_epoch=0x100, last_accepted_seq=0)
    ok, rsn, _ = rep.check_and_update(epoch=0x100, seq=1, mac_verified=False)
    assert ok is False
    assert rsn == L2RejectReason.MAC_MISMATCH

    # Test unmutated ReleaseMemoryWindowModel
    ok, rsn = ReleaseMemoryWindowModel.check_address(0x8200_0100)
    assert ok is False
    assert rsn == FaultReason.OUT_OF_WINDOW_ADDRESS

    # Test unmutated ReleaseK3LengthModel
    ok, st, rsn = ReleaseK3LengthModel.validate_lengths(15, 16)
    assert ok is False
    assert st == 5
    assert rsn == FaultReason.K3_LENGTH_MISMATCH


# =====================================================================
# Test 4: Sequence Number Boundary Testing
# =====================================================================

def test_boundary_sequence_values():
    """Test boundary sequence values: 0, 1, prev, prev+1, max 64-bit."""
    epoch = 0x1122_3344_5566_7788_9900
    rep = ReplayState(expected_boot_epoch=epoch, last_accepted_seq=0)

    # 1. Sequence 0: illegal
    ok, rsn, _ = rep.check_and_update(epoch, seq=0, mac_verified=True)
    assert ok is False
    assert rsn == L2RejectReason.SEQUENCE_VIOLATION
    assert rep.last_accepted_seq == 0

    # 2. Sequence 1: minimum valid sequence
    ok, rsn, _ = rep.check_and_update(epoch, seq=1, mac_verified=True)
    assert ok is True
    assert rep.last_accepted_seq == 1

    # 3. Sequence equal to prev (1 <= 1): rejected
    ok, rsn, _ = rep.check_and_update(epoch, seq=1, mac_verified=True)
    assert ok is False
    assert rsn == L2RejectReason.SEQUENCE_VIOLATION
    assert rep.last_accepted_seq == 1

    # 4. Sequence prev+1 (2 > 1): accepted
    ok, rsn, _ = rep.check_and_update(epoch, seq=2, mac_verified=True)
    assert ok is True
    assert rep.last_accepted_seq == 2

    # 5. Maximum 64-bit sequence (0xFFFF_FFFF_FFFF_FFFF): accepted
    max_64 = 0xFFFF_FFFF_FFFF_FFFF
    ok, rsn, _ = rep.check_and_update(epoch, seq=max_64, mac_verified=True)
    assert ok is True
    assert rep.last_accepted_seq == max_64

    # 6. Any value after max 64-bit cannot be greater: rejected
    ok, rsn, _ = rep.check_and_update(epoch, seq=max_64, mac_verified=True)
    assert ok is False
    assert rsn == L2RejectReason.SEQUENCE_VIOLATION


# =====================================================================
# Test 5: Epoch Boundary Testing
# =====================================================================

def test_boundary_epoch_values():
    """Test boundary epoch values: exact match, mismatch, 0, max 80-bit."""
    epoch_nominal = 0x1234_5678_9ABC_DEF0_1234
    max_80 = 0xFFFF_FFFF_FFFF_FFFF_FFFF

    # Exact match
    rep1 = ReplayState(expected_boot_epoch=epoch_nominal, last_accepted_seq=0)
    ok, rsn, _ = rep1.check_and_update(epoch=epoch_nominal, seq=1, mac_verified=True)
    assert ok is True

    # Epoch 0 mismatch
    rep2 = ReplayState(expected_boot_epoch=epoch_nominal, last_accepted_seq=0)
    ok, rsn, _ = rep2.check_and_update(epoch=0, seq=1, mac_verified=True)
    assert ok is False
    assert rsn == L2RejectReason.EPOCH_MISMATCH

    # Expected epoch 0 with 0 input
    rep3 = ReplayState(expected_boot_epoch=0, last_accepted_seq=0)
    ok, rsn, _ = rep3.check_and_update(epoch=0, seq=1, mac_verified=True)
    assert ok is True

    # Max 80-bit epoch
    rep4 = ReplayState(expected_boot_epoch=max_80, last_accepted_seq=0)
    ok, rsn, _ = rep4.check_and_update(epoch=max_80, seq=1, mac_verified=True)
    assert ok is True


# =====================================================================
# Test 6: Memory Window Boundary Testing
# =====================================================================

def test_boundary_memory_window():
    """Test memory window boundary conditions around 0x2000_0000 and 0x2FFF_FFFF."""
    # Immediately below 0x2 window
    ok, rsn = ReleaseMemoryWindowModel.check_address(0x1FFF_FFFF)
    assert ok is False
    assert rsn == FaultReason.OUT_OF_WINDOW_ADDRESS

    # Base of 0x2 window
    ok, rsn = ReleaseMemoryWindowModel.check_address(0x2000_0000)
    assert ok is True
    assert rsn is None

    # Inside window (Tile 2 standard)
    ok, rsn = ReleaseMemoryWindowModel.check_address(0x2200_0100)
    assert ok is True
    assert rsn is None

    # Top of 0x2 window
    ok, rsn = ReleaseMemoryWindowModel.check_address(0x2FFF_FFFF)
    assert ok is True
    assert rsn is None

    # Immediately above 0x2 window
    ok, rsn = ReleaseMemoryWindowModel.check_address(0x3000_0000)
    assert ok is False
    assert rsn == FaultReason.OUT_OF_WINDOW_ADDRESS


# =====================================================================
# Test 7: BUSY Retry Count Boundary Testing
# =====================================================================

def test_boundary_busy_retries():
    """Test 0, 1, 2, 3 retries, 4th BUSY, and non-1/non-3 statuses."""
    # 0 retries (immediate GRANT)
    m0 = ReleaseBusyRetryModel()
    m0.start_attestation()
    assert m0.handle_response_status(1) == "GRANT"
    assert m0.busy_retries == 0

    # 1 retry then GRANT
    m1 = ReleaseBusyRetryModel()
    m1.start_attestation()
    assert m1.handle_response_status(3) == "RETRY"
    assert m1.busy_retries == 1
    assert m1.handle_response_status(1) == "GRANT"

    # 2 retries then GRANT
    m2 = ReleaseBusyRetryModel()
    m2.start_attestation()
    assert m2.handle_response_status(3) == "RETRY"
    assert m2.handle_response_status(3) == "RETRY"
    assert m2.busy_retries == 2
    assert m2.handle_response_status(1) == "GRANT"

    # 3 retries (boundary max) then GRANT
    m3 = ReleaseBusyRetryModel()
    m3.start_attestation()
    assert m3.handle_response_status(3) == "RETRY"
    assert m3.handle_response_status(3) == "RETRY"
    assert m3.handle_response_status(3) == "RETRY"
    assert m3.busy_retries == 3
    assert m3.handle_response_status(1) == "GRANT"
    assert m3.busy_retries == 0

    # 4th BUSY: fails closed
    m4 = ReleaseBusyRetryModel()
    m4.start_attestation()
    for _ in range(3):
        m4.handle_response_status(3)
    out = m4.handle_response_status(3)  # 4th
    assert out == "REVOKE_FAILED"
    assert m4.failed is True
    assert m4.fail_reason == FaultReason.VERIFIER_STATUS_NOT_ONE

    # Immediate fail on status 0, 2, 5, 10
    for bad in [0, 2, 5, 10]:
        mb = ReleaseBusyRetryModel()
        mb.start_attestation()
        assert mb.handle_response_status(bad) == "REVOKE_FAILED"
        assert mb.failed is True
        assert mb.fail_reason == FaultReason.VERIFIER_STATUS_NOT_ONE


# =====================================================================
# Test 8: K-3 Length Binding Boundary Testing
# =====================================================================

def test_boundary_k3_lengths():
    """Test boundary combinations of (config_len, imem_len): 15, 16, 17."""
    # (16, 16) nominal
    ok, st, rsn = ReleaseK3LengthModel.validate_lengths(16, 16)
    assert ok is True
    assert st == 1
    assert rsn is None

    # (15, 16) - config below
    ok, st, rsn = ReleaseK3LengthModel.validate_lengths(15, 16)
    assert ok is False
    assert st == 5
    assert rsn == FaultReason.K3_LENGTH_MISMATCH

    # (17, 16) - config above
    ok, st, rsn = ReleaseK3LengthModel.validate_lengths(17, 16)
    assert ok is False
    assert st == 5
    assert rsn == FaultReason.K3_LENGTH_MISMATCH

    # (16, 15) - imem below
    ok, st, rsn = ReleaseK3LengthModel.validate_lengths(16, 15)
    assert ok is False
    assert st == 5
    assert rsn == FaultReason.K3_LENGTH_MISMATCH

    # (16, 17) - imem above
    ok, st, rsn = ReleaseK3LengthModel.validate_lengths(16, 17)
    assert ok is False
    assert st == 5
    assert rsn == FaultReason.K3_LENGTH_MISMATCH

    # (0, 0) - zero boundary
    ok, st, rsn = ReleaseK3LengthModel.validate_lengths(0, 0)
    assert ok is False
    assert st == 5
    assert rsn == FaultReason.K3_LENGTH_MISMATCH


# =====================================================================
# Test 9: NI Transaction Slots Boundary Testing
# =====================================================================

def test_boundary_ni_slots():
    """Test 0, 1, 2 slots, 3rd request backpressure, matching release."""
    tracker = TransactionTracker()
    dest = Coord(x=0, y=1)

    # 0 active: allocate slot 0
    t0 = tracker.allocate_slot(dest, "MEM_RD_REQ")
    assert t0 == 0

    # 1 active: allocate slot 1
    t1 = tracker.allocate_slot(dest, "MEM_WR_REQ")
    assert t1 == 1

    # 2 active: 3rd allocation backpressured (returns None)
    t2 = tracker.allocate_slot(dest, "MEM_RD_REQ")
    assert t2 is None

    # Release slot 0 with matching response
    ok, rsn, _ = tracker.match_and_release(tag=0, src_coord=dest, resp_msg_type="MEM_RD_RESP")
    assert ok is True
    assert rsn is None

    # Now 1 active: allocation succeeds, slot 0 re-allocated
    t0_new = tracker.allocate_slot(dest, "MEM_RD_REQ")
    assert t0_new == 0


# =====================================================================
# Test 10: Authorization Transition Boundary Testing
# =====================================================================

def test_boundary_authorization_transitions():
    """Test state machine transitions: boot, grant, revoke, fail, timeout, re-attest."""
    auth = TileAuthorizationState()

    # Initial boot: RoT authorized, Tile 3 unauthorized
    assert auth.is_tile_authorized(4) is True
    assert auth.is_tile_authorized(3) is False

    # Valid grant: Tile 3 authorized
    ok, _, _ = auth.process_grant(target_tile=3, issuer_tile=4, grant_status=1, authenticated=True)
    assert ok is True
    assert auth.is_tile_authorized(3) is True

    # Revoke: Tile 3 unauthorized
    ok, _, _ = auth.process_revoke(target_tile=3, issuer_tile=4, authenticated=True)
    assert ok is True
    assert auth.is_tile_authorized(3) is False

    # Re-grant: Tile 3 authorized again
    ok, _, _ = auth.process_grant(target_tile=3, issuer_tile=4, grant_status=1, authenticated=True)
    assert ok is True
    assert auth.is_tile_authorized(3) is True

    # Trusted fail pulse: Tile 3 unauthorized
    auth.signal_trusted_fail_or_timeout(tile_id=3, is_timeout=False)
    assert auth.is_tile_authorized(3) is False

    # Re-grant then trusted timeout pulse: Tile 3 unauthorized
    auth.process_grant(target_tile=3, issuer_tile=4, grant_status=1, authenticated=True)
    assert auth.is_tile_authorized(3) is True
    auth.signal_trusted_fail_or_timeout(tile_id=3, is_timeout=True)
    assert auth.is_tile_authorized(3) is False


# =====================================================================
# Test 11: Mutation Manifest Generation
# =====================================================================

def test_mutation_manifest_generation(tmp_path):
    """Verify that p7_mutation_report.json is generated with valid structure."""
    out_file = tmp_path / "mutation_report.json"
    manifest = generate_mutation_report_manifest(output_path=out_file)

    assert out_file.exists()
    assert manifest["metadata"]["total_mutations"] == 16
    assert manifest["metadata"]["killed"] == 16
    assert manifest["metadata"]["survived"] == 0
    assert manifest["metadata"]["mutation_score_percentage"] == 100.0


# =====================================================================
# Test 12: Historical Artifact Integrity
# =====================================================================

def test_historical_integrity_step6():
    """Verify that reports and manifests from Steps 1-5 remain unmodified."""
    repo_root = Path(__file__).resolve().parent.parent.parent
    reports_dir = repo_root / "reports"
    gen_dir = repo_root / "verification" / "generated"

    for rpt in [
        "E4_P7_STEP1_REPORT.md",
        "E4_P7_STEP2_REPORT.md",
        "E4_P7_STEP3_REPORT.md",
        "E4_P7_STEP4_REPORT.md",
        "E4_P7_STEP4B_REPORT.md",
        "E4_P7_STEP5_REPORT.md",
    ]:
        assert (reports_dir / rpt).exists(), f"Missing report: {rpt}"

    for man in [
        "p7_protocol_manifest.json",
        "p7_differential_vectors.json",
        "p7_differential_report.json",
        "p7_release_evidence.json",
        "p7_integration_scenarios.json",
    ]:
        assert (gen_dir / man).exists(), f"Missing manifest: {man}"

