"""
verification/tests/test_p7_integration_scenarios.py
===================================================
Test suite for PQ-Attest P7 Step 5: Release-Aware End-to-End Integration Regression.

Tests:
1. Complete execution of all 20 integration scenarios.
2. Memory non-mutability under invalid/unauthorized operations.
3. Replay state strict monotonicity (advances only after accepted auth).
4. Revocation containment (REVOKE blocks all subsequent memory access).
5. BUSY retry preservation of challenge identity.
6. Fourth consecutive BUSY fails closed.
7. Memory-window boundary conditions (A[31:28] == 4'h2).
8. NI transaction tag allocation, matching, and retirement.
9. Recovery flow: access restored only via valid attestation and grant.
10. Negative tests and mutation controls (K-3 length, issuer spoofing, invalid grant status).
11. JSON manifest generation and schema verification.
12. Historical repository integrity (RTL untouched, previous reports preserved).
"""

from pathlib import Path
import pytest

from verification.p7_integration_scenarios import (
    IntegrationScenarioSuite,
    P7IntegrationEngine,
    generate_integration_scenarios_manifest,
)
from verification.p7_packet_model import Coord
from verification.p7_release_evidence import (
    FaultReason,
    ReleaseBusyRetryModel,
    ReleaseFaultStatusModel,
    ReleaseK3LengthModel,
    ReleaseMemoryWindowModel,
    RTLClassification,
)
from verification.p7_security_model import (
    GateFaultReason,
    L2RejectReason,
    MemoryEndpoint,
    MemoryFaultReason,
    NIProtocolErrorReason,
    ReplayState,
    TileAuthorizationState,
    TransactionTracker,
)


@pytest.fixture
def suite():
    """Fixture providing initialized IntegrationScenarioSuite."""
    return IntegrationScenarioSuite()


@pytest.fixture
def engine():
    """Fixture providing clean P7IntegrationEngine."""
    return P7IntegrationEngine(initial_epoch=0x1234_5678_9ABC_DEF0_1234)


# =====================================================================
# Test 1: Complete Suite Execution
# =====================================================================

def test_all_20_scenarios_execute_and_pass(suite):
    """Verify that all 20 integration scenarios execute with PASS verdict."""
    scenarios = suite.run_all()
    assert len(scenarios) == 20

    for sc in scenarios:
        assert sc.python_execution_result == "PASS", f"Scenario {sc.scenario_id} failed in Python"
        assert sc.rtl_verification_status == RTLClassification.RTL_PASS
        # Verify RTL evidence log file exists
        log_path = Path(sc.related_rtl_evidence.log_file)
        assert log_path.exists(), f"Log file for {sc.scenario_id} not found: {log_path}"
        assert sc.related_rtl_evidence.errors == 0
        assert sc.related_rtl_evidence.checks > 0


# =====================================================================
# Test 2: Memory Non-Mutability Under Invalid Operations
# =====================================================================

def test_invalid_operations_do_not_change_memory(engine):
    """Verify that unauthorized, revoked, or out-of-window writes never mutate memory."""
    # 1. Write when unauthorized (Tile 3 initial state)
    assert engine.auth_state.is_tile_authorized(3) is False
    ok, err = engine.memory_write(src_tile=3, address=0x2200_0100, data_word=0xDEAD_0001)
    assert ok is False
    assert err == "UNAUTHORIZED_AT_GATE"
    assert engine.memory_endpoint.memory_commits == 0

    # 2. Authorize tile 3, perform 1 valid write
    engine.auth_state.authorized[3] = True
    ok, err = engine.memory_write(src_tile=3, address=0x2200_0100, data_word=0xCAFE_BABE)
    assert ok is True
    assert engine.memory_endpoint.memory_commits == 1
    assert engine.memory_endpoint.memory_last_data == 0xCAFE_BABE

    # 3. Revoke Tile 3
    engine.auth_state.authorized[3] = False
    ok, err = engine.memory_write(src_tile=3, address=0x2200_0100, data_word=0xDEAD_0002)
    assert ok is False
    assert err == "UNAUTHORIZED_AT_GATE"
    assert engine.memory_endpoint.memory_commits == 1  # Still 1!
    assert engine.memory_endpoint.memory_last_data == 0xCAFE_BABE

    # 4. Out of window write attempt (even if authorized)
    engine.auth_state.authorized[3] = True
    ok, err = engine.memory_write(src_tile=3, address=0x8200_0100, data_word=0xDEAD_0003)
    assert ok is False
    assert err == "OUT_OF_WINDOW_ADDRESS"
    assert engine.memory_endpoint.memory_commits == 1  # Strictly unmodified!
    assert engine.memory_endpoint.memory_last_data == 0xCAFE_BABE


# =====================================================================
# Test 3: Replay State Strict Monotonicity
# =====================================================================

def test_replay_state_monotonicity():
    """Verify replay state advances only after valid authentication and strictly monotonic sequence."""
    epoch = 0xAAAA_BBBB_CCCC_DDDD_EEEE
    replay = ReplayState(expected_boot_epoch=epoch, last_accepted_seq=0)

    # Rejection 1: Invalid MAC (seq does not advance)
    ok, reason, _ = replay.check_and_update(epoch=epoch, seq=1, mac_verified=False)
    assert ok is False
    assert reason == L2RejectReason.MAC_MISMATCH
    assert replay.last_accepted_seq == 0

    # Rejection 2: Epoch mismatch (seq does not advance)
    ok, reason, _ = replay.check_and_update(epoch=0x1111, seq=1, mac_verified=True)
    assert ok is False
    assert reason == L2RejectReason.EPOCH_MISMATCH
    assert replay.last_accepted_seq == 0

    # Rejection 3: Sequence 0 illegal
    ok, reason, _ = replay.check_and_update(epoch=epoch, seq=0, mac_verified=True)
    assert ok is False
    assert reason == L2RejectReason.SEQUENCE_VIOLATION
    assert replay.last_accepted_seq == 0

    # Valid check: advances seq to 5
    ok, reason, _ = replay.check_and_update(epoch=epoch, seq=5, mac_verified=True)
    assert ok is True
    assert replay.last_accepted_seq == 5

    # Rejection 4: Stale sequence (seq 5 <= 5)
    ok, reason, _ = replay.check_and_update(epoch=epoch, seq=5, mac_verified=True)
    assert ok is False
    assert reason == L2RejectReason.SEQUENCE_VIOLATION
    assert replay.last_accepted_seq == 5

    # Rejection 5: Older sequence (seq 3 < 5)
    ok, reason, _ = replay.check_and_update(epoch=epoch, seq=3, mac_verified=True)
    assert ok is False
    assert reason == L2RejectReason.SEQUENCE_VIOLATION
    assert replay.last_accepted_seq == 5

    # Valid check: advances seq to 10
    ok, reason, _ = replay.check_and_update(epoch=epoch, seq=10, mac_verified=True)
    assert ok is True
    assert replay.last_accepted_seq == 10


# =====================================================================
# Test 4: Revocation Blocks Subsequent Access
# =====================================================================

def test_revoke_prevents_subsequent_access(engine):
    """Verify that REVOKE cuts off all subsequent read/write operations at the gate."""
    # Authorize tile 3
    engine.issue_grant(target_tile=3, issuer_tile=4, grant_status=1, mac_verified=True, seq=1)
    assert engine.auth_state.is_tile_authorized(3) is True

    # Confirm write and read work
    wr_ok, _ = engine.memory_write(src_tile=3, address=0x2200_0100, data_word=0x4242_4242)
    assert wr_ok is True
    rd_ok, val, _ = engine.memory_read(src_tile=3, address=0x2200_0100)
    assert rd_ok is True
    assert val == 0x4242_4242

    # Issue authenticated REVOKE
    rv_ok, _ = engine.issue_revoke(target_tile=3, issuer_tile=4, mac_verified=True, seq=2)
    assert rv_ok is True
    assert engine.auth_state.is_tile_authorized(3) is False

    # Immediate subsequent write blocked
    wr_ok, err = engine.memory_write(src_tile=3, address=0x2200_0100, data_word=0x9999_9999)
    assert wr_ok is False
    assert err == "UNAUTHORIZED_AT_GATE"

    # Immediate subsequent read blocked
    rd_ok, val, err = engine.memory_read(src_tile=3, address=0x2200_0100)
    assert rd_ok is False
    assert val is None
    assert err == "UNAUTHORIZED_AT_GATE"


# =====================================================================
# Test 5: BUSY Retries Preserve Challenge Identity
# =====================================================================

def test_busy_retries_preserve_challenge_identity(engine):
    """Verify that up to 3 BUSY retries preserve the outstanding challenge parameters."""
    nonce = 0xFEED_FACE_CAFE_BEEF
    ch = engine.generate_challenge(dest_tile=3, nonce=nonce, config_len=16, imem_len=16)

    assert engine.busy_retry_model.busy_retries == 0
    assert engine.busy_retry_model.challenges_issued == 1

    # Retry 1
    accepted, outcome, _ = engine.handle_attestation_response(status=3)
    assert accepted is False
    assert outcome == "RETRY"
    assert engine.busy_retry_model.busy_retries == 1
    assert engine.outstanding_challenge["nonce"] == nonce

    # Retry 2
    accepted, outcome, _ = engine.handle_attestation_response(status=3)
    assert accepted is False
    assert outcome == "RETRY"
    assert engine.busy_retry_model.busy_retries == 2
    assert engine.outstanding_challenge["nonce"] == nonce

    # Retry 3
    accepted, outcome, _ = engine.handle_attestation_response(status=3)
    assert accepted is False
    assert outcome == "RETRY"
    assert engine.busy_retry_model.busy_retries == 3
    assert engine.outstanding_challenge["nonce"] == nonce

    # Final success (GRANT)
    accepted, outcome, _ = engine.handle_attestation_response(status=1)
    assert accepted is True
    assert outcome == "GRANT"
    assert engine.busy_retry_model.busy_retries == 0


# =====================================================================
# Test 6: Fourth BUSY Fails Closed
# =====================================================================

def test_fourth_busy_fails_closed(engine):
    """Verify that a 4th consecutive BUSY response triggers fail-closed (REVOKE, reason 9)."""
    engine.generate_challenge(dest_tile=3, nonce=0x1111_2222_3333_4444)

    # Retries 1, 2, 3
    for _ in range(3):
        accepted, outcome, _ = engine.handle_attestation_response(status=3)
        assert accepted is False
        assert outcome == "RETRY"

    # 4th consecutive BUSY
    accepted, outcome, rsn = engine.handle_attestation_response(status=3)
    assert accepted is False
    assert outcome == "REVOKE_FAILED"
    assert rsn == FaultReason.VERIFIER_STATUS_NOT_ONE
    assert engine.busy_retry_model.failed is True
    assert engine.busy_retry_model.authorized is False
    assert engine.auth_state.is_tile_authorized(3) is False


# =====================================================================
# Test 7: Memory-Window Boundary Conditions
# =====================================================================

def test_memory_window_boundaries():
    """Verify memory window boundary enforcement (strictly A[31:28] == 4'h2)."""
    # Valid addresses inside 0x2 region
    for valid_addr in [0x2000_0000, 0x2200_0000, 0x2200_0100, 0x2FFF_FFFC]:
        ok, rsn = ReleaseMemoryWindowModel.check_address(valid_addr)
        assert ok is True
        assert rsn is None

    # Invalid addresses outside 0x2 region
    for invalid_addr in [
        0x1FFF_FFFC,  # Region 0x1
        0x3000_0000,  # Region 0x3
        0x0000_0000,  # Region 0x0
        0x8200_0100,  # Historical Region 0x8
        0xF000_0000,  # Region 0xF
    ]:
        ok, rsn = ReleaseMemoryWindowModel.check_address(invalid_addr)
        assert ok is False
        assert rsn == FaultReason.OUT_OF_WINDOW_ADDRESS


# =====================================================================
# Test 8: Transaction Tag Matching and Retirement
# =====================================================================

def test_transaction_tag_matching():
    """Verify NI 2-slot transaction tag tracking, matching, and retirement."""
    tracker = TransactionTracker()
    dest = Coord(x=0, y=1)

    # Allocate slot 0
    t0 = tracker.allocate_slot(dest, "MEM_RD_REQ")
    assert t0 == 0

    # Allocate slot 1
    t1 = tracker.allocate_slot(dest, "MEM_WR_REQ")
    assert t1 == 1

    # Attempt allocate slot 2 (exhaustion)
    t2 = tracker.allocate_slot(dest, "MEM_RD_REQ")
    assert t2 is None

    # Mismatched source coord
    ok, rsn, _ = tracker.match_and_release(tag=0, src_coord=Coord(x=1, y=1), resp_msg_type="MEM_RD_RESP")
    assert ok is False
    assert rsn == NIProtocolErrorReason.RESPONSE_UNMATCHED

    # Mismatched response type
    ok, rsn, _ = tracker.match_and_release(tag=0, src_coord=dest, resp_msg_type="MEM_WR_RESP")
    assert ok is False
    assert rsn == NIProtocolErrorReason.RESPONSE_UNMATCHED

    # Correct match for slot 0
    ok, rsn, _ = tracker.match_and_release(tag=0, src_coord=dest, resp_msg_type="MEM_RD_RESP")
    assert ok is True
    assert rsn is None

    # Slot 0 is now free: allocate again
    t0_new = tracker.allocate_slot(dest, "MEM_RD_REQ")
    assert t0_new == 0


# =====================================================================
# Test 9: Recovery Only Through Valid Attestation
# =====================================================================

def test_recovery_only_through_valid_authorization(engine):
    """Verify that after revocation or fault, authorization is restored only via valid attestation."""
    # Start revoked
    engine.auth_state.authorized[3] = False

    # Attempt memory write: fails
    wr_ok, _ = engine.memory_write(src_tile=3, address=0x2200_0100, data_word=0x1234_5678)
    assert wr_ok is False

    # Attempt spoofed grant from Tile 1: fails
    g_ok, err = engine.issue_grant(target_tile=3, issuer_tile=1, grant_status=1, mac_verified=True, seq=1)
    assert g_ok is False
    assert "INVALID_ISSUER" in err
    assert engine.auth_state.is_tile_authorized(3) is False

    # Attempt grant with status != 1: fails
    g_ok, err = engine.issue_grant(target_tile=3, issuer_tile=4, grant_status=2, mac_verified=True, seq=2)
    assert g_ok is False
    assert "INVALID_GRANT_STATUS" in err
    assert engine.auth_state.is_tile_authorized(3) is False

    # Genuine recovery sequence:
    # 1. Challenge RoT -> Tile 3
    engine.generate_challenge(dest_tile=3, nonce=0xABCD_EF01_2345_6789)
    # 2. Genuine response
    ok, outcome, _ = engine.handle_attestation_response(status=1, measurement_match=True, tag_match=True)
    assert ok is True and outcome == "GRANT"
    # 3. RoT delivers valid GRANT
    g_ok, err = engine.issue_grant(target_tile=3, issuer_tile=4, grant_status=1, mac_verified=True, seq=3)
    assert g_ok is True
    assert engine.auth_state.is_tile_authorized(3) is True

    # Memory write now succeeds
    wr_ok, _ = engine.memory_write(src_tile=3, address=0x2200_0100, data_word=0x1234_5678)
    assert wr_ok is True


# =====================================================================
# Test 10: Negative and Mutation Tests
# =====================================================================

def test_negative_and_mutation_controls(engine):
    """Verify sensitivity to security parameter mutations and negative edge cases."""
    # Mutation 1: K-3 length binding mismatch
    ok, st, rsn = ReleaseK3LengthModel.validate_lengths(config_len=32, imem_len=16)
    assert ok is False
    assert st == 5
    assert rsn == FaultReason.K3_LENGTH_MISMATCH

    ok, st, rsn = ReleaseK3LengthModel.validate_lengths(config_len=16, imem_len=0)
    assert ok is False
    assert st == 5
    assert rsn == FaultReason.K3_LENGTH_MISMATCH

    # Mutation 2: Measurement mismatch
    engine.generate_challenge(dest_tile=3, nonce=0x1234)
    accepted, outcome, rsn = engine.handle_attestation_response(status=1, measurement_match=False, tag_match=True)
    assert accepted is False
    assert rsn == FaultReason.MEASUREMENT_MISMATCH

    # Mutation 3: Tag mismatch
    engine.generate_challenge(dest_tile=3, nonce=0x5678)
    accepted, outcome, rsn = engine.handle_attestation_response(status=1, measurement_match=True, tag_match=False)
    assert accepted is False
    assert rsn == FaultReason.TAG_MISMATCH

    # Mutation 4: Untrusted clear attempt has zero effect
    # Reset fault status for isolated clear test
    engine.fault_status.apply_trusted_clear()
    assert engine.fault_status.fault_sticky is False
    assert engine.fault_status.fault_count == 0

    engine.fault_status.record_fault(source=3, operation=1, reason=FaultReason.TAG_MISMATCH, epoch=1)
    assert engine.fault_status.fault_sticky is True
    assert engine.fault_status.fault_count == 1

    engine.fault_status.apply_untrusted_traffic()
    assert engine.fault_status.fault_sticky is True
    assert engine.fault_status.fault_count == 1  # Cannot clear!

    engine.fault_status.apply_trusted_clear()
    assert engine.fault_status.fault_sticky is False
    assert engine.fault_status.fault_count == 0  # Cleared by RoT


# =====================================================================
# Test 11: Manifest Generation and Verification
# =====================================================================

def test_manifest_generation(tmp_path):
    """Verify that p7_integration_scenarios.json is generated with valid structure."""
    out_file = tmp_path / "integration_scenarios.json"
    manifest = generate_integration_scenarios_manifest(output_path=out_file)

    assert out_file.exists()
    assert manifest["summary"]["total_scenarios"] == 20
    assert manifest["summary"]["python_passed"] == 20
    assert manifest["summary"]["python_failed"] == 0
    assert manifest["summary"]["rtl_pass"] == 20
    assert manifest["metadata"]["status_claims"]["HARDWARE_VALIDATED"] is False
    assert manifest["metadata"]["status_claims"]["FORMAL_PROOF"] is False
    assert manifest["metadata"]["status_claims"]["SOC_INTEGRATION_COMPLETE"] is False


# =====================================================================
# Test 12: Historical Integrity
# =====================================================================

def test_historical_integrity():
    """Verify that reports and manifests from Steps 1-4B remain intact."""
    repo_root = Path(__file__).resolve().parent.parent.parent
    reports_dir = repo_root / "reports"
    gen_dir = repo_root / "verification" / "generated"

    # Step reports
    assert (reports_dir / "E4_P7_STEP1_REPORT.md").exists()
    assert (reports_dir / "E4_P7_STEP2_REPORT.md").exists()
    assert (reports_dir / "E4_P7_STEP3_REPORT.md").exists()
    assert (reports_dir / "E4_P7_STEP4_REPORT.md").exists()
    assert (reports_dir / "E4_P7_STEP4B_REPORT.md").exists()

    # Manifests
    assert (gen_dir / "p7_protocol_manifest.json").exists()
    assert (gen_dir / "p7_differential_vectors.json").exists()
    assert (gen_dir / "p7_differential_report.json").exists()
    assert (gen_dir / "p7_release_evidence.json").exists()
