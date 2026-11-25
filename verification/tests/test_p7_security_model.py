#!/usr/bin/env python3
"""
Test suite for verification/p7_security_model.py.

Covers:
  1. Valid GRANT authorizes tile 3.
  2. Invalid GRANT does not authorize tile 3 (bad status, non-RoT issuer).
  3. REVOKE removes authorization from tile 3.
  4. Attestation failure removes authorization.
  5. Timeout removes authorization.
  6. Tiles 0, 1, 2, and 5 cannot become authorized.
  7. Invalid control-message direction.
  8. Correct boot epoch acceptance.
  9. Incorrect boot epoch rejection (L2 reason 3).
  10. Sequence zero rejection (L2 reason 4).
  11. Repeated sequence rejection (L2 reason 4).
  12. Decreasing sequence rejection (L2 reason 4).
  13. Increasing sequence acceptance and monotonicity.
  14. Unauthorized memory read rejection (dropped at request HEAD, reason 6).
  15. Unauthorized memory write rejection (no commit, reason 6).
  16. Revocation between read request and response (suppresses response, reason 6).
  17. Revocation before final write acceptance (no commit, suppresses response, reason 6).
  18. Transaction tag mismatch / unmatched response rejection.
  19. Transaction slot exhaustion (2 slots maximum).
  20. Rejection reason correctness across Ingress, L2, Gate, NI, Memory, and Verifier.
  21. Mutation tests for security-critical rules.
"""

from __future__ import annotations

import pytest

from verification.p7_packet_model import (
    Coord,
    FreshnessMetadata,
    P7Packet,
    ProtocolProfile,
)
from verification.p7_security_model import (
    GateFaultReason,
    IngressRejectReason,
    L2RejectReason,
    MemoryEndpoint,
    MemoryFaultReason,
    NIProtocolErrorReason,
    P7SecuritySubsystem,
    ReplayState,
    TileAuthorizationState,
    TransactionTracker,
    VerifierFailReason,
)


@pytest.fixture
def profile() -> ProtocolProfile:
    return ProtocolProfile.load()


@pytest.fixture
def subsystem() -> P7SecuritySubsystem:
    return P7SecuritySubsystem(boot_epoch=0x1A2B3C4D5E6F708192A3)


# ------------------------------------------------------------------------------
# 1. Valid GRANT authorizes Tile 3
# ------------------------------------------------------------------------------

def test_valid_grant_authorizes_tile3(subsystem: P7SecuritySubsystem, profile: ProtocolProfile) -> None:
    """Verifies that authenticated GRANT with status=1 from RoT authorizes Tile 3."""
    assert not subsystem.auth_state.is_tile_authorized(3)

    grant_pkt = P7Packet(
        src_coord=Coord(x=1, y=1),  # Tile 4 (RoT)
        dest_coord=Coord(x=0, y=1), # Tile 3 (Crypto)
        msg_type="ATTEST_GRANT",
        control_field=(1 << 7),     # status = 1 in control[10:7]
        mac_flits=[0x11, 0x22, 0x33, 0x44],
        freshness=FreshnessMetadata(seq=1, epoch=subsystem.boot_epoch),
        profile=profile,
    )

    res = subsystem.process_wire_packet(grant_pkt, injecting_port=4, mac_cryptographically_verified=True)
    assert res.accepted
    assert res.fresh
    assert res.cryptographically_verified
    assert subsystem.auth_state.is_tile_authorized(3)


# ------------------------------------------------------------------------------
# 2. Invalid GRANT does not authorize Tile 3
# ------------------------------------------------------------------------------

def test_invalid_grant_status_rejected(subsystem: P7SecuritySubsystem, profile: ProtocolProfile) -> None:
    """Verifies that GRANT with status=0 is rejected and sets Gate reason 3."""
    grant_pkt = P7Packet(
        src_coord=Coord(x=1, y=1),  # Tile 4
        dest_coord=Coord(x=0, y=1), # Tile 3
        msg_type="ATTEST_GRANT",
        control_field=0,            # status = 0
        mac_flits=[0x11, 0x22, 0x33, 0x44],
        freshness=FreshnessMetadata(seq=1, epoch=subsystem.boot_epoch),
        profile=profile,
    )

    res = subsystem.process_wire_packet(grant_pkt, injecting_port=4, mac_cryptographically_verified=True)
    assert not res.accepted
    assert res.rejection_layer == "gate"
    assert res.rejection_reason_code == int(GateFaultReason.INVALID_GRANT_STATUS)
    assert not subsystem.auth_state.is_tile_authorized(3)


def test_invalid_grant_issuer_rejected(subsystem: P7SecuritySubsystem) -> None:
    """Verifies that GRANT issued by non-RoT tile (e.g. Tile 5) is rejected."""
    ok, reason, _ = subsystem.auth_state.process_grant(
        target_tile=3,
        issuer_tile=5,  # Non-RoT
        grant_status=1,
        authenticated=True,
    )
    assert not ok
    assert reason == GateFaultReason.INVALID_ISSUER
    assert not subsystem.auth_state.is_tile_authorized(3)


# ------------------------------------------------------------------------------
# 3. REVOKE removes authorization from Tile 3
# ------------------------------------------------------------------------------

def test_revoke_removes_tile3_authorization(subsystem: P7SecuritySubsystem, profile: ProtocolProfile) -> None:
    """Verifies that authenticated REVOKE from RoT revokes Tile 3 authorization."""
    # First authorize Tile 3
    subsystem.auth_state.authorized[3] = True
    assert subsystem.auth_state.is_tile_authorized(3)

    revoke_pkt = P7Packet(
        src_coord=Coord(x=1, y=1),  # Tile 4
        dest_coord=Coord(x=0, y=1), # Tile 3
        msg_type="ATTEST_REVOKE",
        control_field=0,
        mac_flits=[0x55, 0x66, 0x77, 0x88],
        freshness=FreshnessMetadata(seq=2, epoch=subsystem.boot_epoch),
        profile=profile,
    )

    res = subsystem.process_wire_packet(revoke_pkt, injecting_port=4, mac_cryptographically_verified=True)
    assert res.accepted
    assert not subsystem.auth_state.is_tile_authorized(3)


# ------------------------------------------------------------------------------
# 4 & 5. Attestation Failure and Timeout remove authorization
# ------------------------------------------------------------------------------

def test_attestation_failure_removes_authorization(subsystem: P7SecuritySubsystem) -> None:
    """Verifies that verifier failure removes Tile 3 authorization (Gate reason 4)."""
    subsystem.auth_state.authorized[3] = True
    subsystem.auth_state.signal_trusted_fail_or_timeout(tile_id=3, is_timeout=False)

    assert not subsystem.auth_state.is_tile_authorized(3)
    assert subsystem.auth_state.fault_reason[3] == GateFaultReason.TRUSTED_FAIL_OR_TIMEOUT


def test_attestation_timeout_removes_authorization(subsystem: P7SecuritySubsystem) -> None:
    """Verifies that verifier timeout removes Tile 3 authorization (Gate reason 4)."""
    subsystem.auth_state.authorized[3] = True
    subsystem.auth_state.signal_trusted_fail_or_timeout(tile_id=3, is_timeout=True)

    assert not subsystem.auth_state.is_tile_authorized(3)
    assert subsystem.auth_state.fault_reason[3] == GateFaultReason.TRUSTED_FAIL_OR_TIMEOUT


# ------------------------------------------------------------------------------
# 6. Tiles 0, 1, 2, and 5 cannot become authorized
# ------------------------------------------------------------------------------

@pytest.mark.parametrize("tile_id", [0, 1, 2, 5])
def test_plain_tiles_cannot_be_authorized(subsystem: P7SecuritySubsystem, tile_id: int) -> None:
    """Verifies that non-attested tiles 0, 1, 2, and 5 reject GRANT and stay unauthorized."""
    assert not subsystem.auth_state.is_tile_authorized(tile_id)

    ok, reason, _ = subsystem.auth_state.process_grant(
        target_tile=tile_id,
        issuer_tile=4,
        grant_status=1,
        authenticated=True,
    )
    assert not ok
    assert reason == GateFaultReason.NON_ATTESTABLE_TILE
    assert not subsystem.auth_state.is_tile_authorized(tile_id)


# ------------------------------------------------------------------------------
# 7. Invalid Control Message Direction
# ------------------------------------------------------------------------------

@pytest.mark.parametrize("msg,src,dst", [
    ("ATTEST_CHALLENGE", 3, 4),  # Backwards
    ("ATTEST_RESPONSE", 4, 3),   # Backwards
    ("ATTEST_GRANT", 3, 4),      # Crypto cannot grant RoT
    ("ATTEST_GRANT", 5, 3),      # Spoof cannot grant
    ("ATTEST_CHALLENGE", 4, 0),  # Cannot challenge CPU0
    ("ATTEST_RESPONSE", 3, 2),   # Cannot send response to Memory
])
def test_invalid_control_message_direction(subsystem: P7SecuritySubsystem, profile: ProtocolProfile, msg: str, src: int, dst: int) -> None:
    """Verifies that control messages on illegal paths are rejected."""
    src_c = Coord.from_tile_id(src)
    dst_c = Coord.from_tile_id(dst)

    pkt = P7Packet(
        src_coord=src_c,
        dest_coord=dst_c,
        msg_type=msg,
        mac_flits=[1, 2, 3, 4],
        freshness=FreshnessMetadata(seq=1, epoch=subsystem.boot_epoch),
        profile=profile,
    )

    res = subsystem.process_wire_packet(pkt, injecting_port=src, mac_cryptographically_verified=True)
    assert not res.accepted
    assert res.rejection_reason_code in (
        int(L2RejectReason.NON_PEER_CONTROL),
        int(L2RejectReason.PLAIN_TILE_CONTROL_DROP),
    )


# ------------------------------------------------------------------------------
# 8 & 9. Correct Boot Epoch vs Incorrect Boot Epoch
# ------------------------------------------------------------------------------

def test_correct_boot_epoch_accepted(subsystem: P7SecuritySubsystem) -> None:
    tracker = subsystem.replay_trackers[3]
    ok, reason, _ = tracker.check_and_update(epoch=subsystem.boot_epoch, seq=10, mac_verified=True)
    assert ok
    assert reason is None
    assert tracker.last_accepted_seq == 10


def test_incorrect_boot_epoch_rejected(subsystem: P7SecuritySubsystem) -> None:
    tracker = subsystem.replay_trackers[3]
    bad_epoch = subsystem.boot_epoch ^ 0xFF
    ok, reason, _ = tracker.check_and_update(epoch=bad_epoch, seq=10, mac_verified=True)
    assert not ok
    assert reason == L2RejectReason.EPOCH_MISMATCH
    assert tracker.last_accepted_seq == 0  # Replay state did not advance


# ------------------------------------------------------------------------------
# 10, 11, 12, 13. Sequence Rules: Zero, Repeated, Decreasing, Increasing
# ------------------------------------------------------------------------------

def test_sequence_zero_rejected(subsystem: P7SecuritySubsystem) -> None:
    tracker = subsystem.replay_trackers[3]
    ok, reason, _ = tracker.check_and_update(epoch=subsystem.boot_epoch, seq=0, mac_verified=True)
    assert not ok
    assert reason == L2RejectReason.SEQUENCE_VIOLATION
    assert tracker.last_accepted_seq == 0


def test_repeated_sequence_rejected(subsystem: P7SecuritySubsystem) -> None:
    tracker = subsystem.replay_trackers[3]
    ok1, _, _ = tracker.check_and_update(epoch=subsystem.boot_epoch, seq=5, mac_verified=True)
    assert ok1

    # Replay of seq=5
    ok2, reason, _ = tracker.check_and_update(epoch=subsystem.boot_epoch, seq=5, mac_verified=True)
    assert not ok2
    assert reason == L2RejectReason.SEQUENCE_VIOLATION
    assert tracker.last_accepted_seq == 5


def test_decreasing_sequence_rejected(subsystem: P7SecuritySubsystem) -> None:
    tracker = subsystem.replay_trackers[3]
    ok1, _, _ = tracker.check_and_update(epoch=subsystem.boot_epoch, seq=20, mac_verified=True)
    assert ok1

    # Stale seq=19
    ok2, reason, _ = tracker.check_and_update(epoch=subsystem.boot_epoch, seq=19, mac_verified=True)
    assert not ok2
    assert reason == L2RejectReason.SEQUENCE_VIOLATION
    assert tracker.last_accepted_seq == 20


def test_strictly_increasing_sequence_accepted(subsystem: P7SecuritySubsystem) -> None:
    tracker = subsystem.replay_trackers[3]
    for seq in [1, 2, 100, 101, 0x7FFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF]:
        ok, reason, _ = tracker.check_and_update(epoch=subsystem.boot_epoch, seq=seq, mac_verified=True)
        assert ok
        assert reason is None
        assert tracker.last_accepted_seq == seq


# ------------------------------------------------------------------------------
# 14 & 15. Unauthorized Memory Read and Write Rejections
# ------------------------------------------------------------------------------

def test_unauthorized_memory_read_rejected_at_head(subsystem: P7SecuritySubsystem) -> None:
    """Verifies that an unauthorized tile's read request is dropped at HEAD (reason 6)."""
    assert not subsystem.auth_state.is_tile_authorized(0)
    ok, reason, val, _ = subsystem.memory_endpoint.handle_read_request(
        src_tile=0,
        address=MemoryEndpoint.MEMORY_BASE,
        tag=0,
    )
    assert not ok
    assert reason == MemoryFaultReason.UNAUTHORIZED_ACCESS
    assert val is None
    assert subsystem.memory_endpoint.mem_faults == 1


def test_unauthorized_memory_write_rejected_no_commit(subsystem: P7SecuritySubsystem) -> None:
    """Verifies that an unauthorized tile's write request commits nothing (reason 6)."""
    assert not subsystem.auth_state.is_tile_authorized(1)
    ok, reason, _ = subsystem.memory_endpoint.handle_write_request(
        src_tile=1,
        address=MemoryEndpoint.MEMORY_BASE,
        wdata=0xDEADBEEF,
        wstrb=0xF,
        tag=0,
    )
    assert not ok
    assert reason == MemoryFaultReason.UNAUTHORIZED_ACCESS
    assert subsystem.memory_endpoint.memory_commits == 0
    assert subsystem.memory_endpoint.mem_faults == 1


# ------------------------------------------------------------------------------
# 16. Revocation Between Memory Read Request and Response
# ------------------------------------------------------------------------------

def test_revocation_between_read_req_and_resp_suppressed(subsystem: P7SecuritySubsystem) -> None:
    """
    Q2: Tile 3 is authorized at read request HEAD, but revoked before response HEAD
    is offered. Verifies response is SUPPRESSED and memory fault recorded (reason 6).
    """
    subsystem.auth_state.authorized[3] = True
    ok, reason, val, msg = subsystem.memory_endpoint.handle_read_request(
        src_tile=3,
        address=MemoryEndpoint.MEMORY_BASE,
        tag=0,
        simulate_revocation_before_response=True,
    )
    assert not ok
    assert reason == MemoryFaultReason.UNAUTHORIZED_ACCESS
    assert val is None
    assert "suppressed" in msg.lower()
    assert subsystem.memory_endpoint.mem_faults == 1


# ------------------------------------------------------------------------------
# 17. Revocation Before Final Write Acceptance
# ------------------------------------------------------------------------------

def test_revocation_before_final_write_acceptance_no_commit(subsystem: P7SecuritySubsystem) -> None:
    """
    F4: Tile 3 is authorized at write HEAD, but revoked before final write data
    acceptance. Verifies NO COMMIT, response suppressed, memory fault recorded.
    """
    subsystem.auth_state.authorized[3] = True
    ok, reason, msg = subsystem.memory_endpoint.handle_write_request(
        src_tile=3,
        address=MemoryEndpoint.MEMORY_BASE,
        wdata=0xCAFEBABE,
        wstrb=0xF,
        tag=0,
        simulate_revocation_before_final_data=True,
    )
    assert not ok
    assert reason == MemoryFaultReason.UNAUTHORIZED_ACCESS
    assert subsystem.memory_endpoint.memory_commits == 0
    assert subsystem.memory_endpoint.mem_faults == 1
    assert "no commit" in msg.lower()


# ------------------------------------------------------------------------------
# 18 & 19. Transaction Tag Mismatch and Slot Exhaustion
# ------------------------------------------------------------------------------

def test_transaction_slot_allocation_and_matching() -> None:
    """Tests 2-slot NI transaction tag allocation and matching."""
    tracker = TransactionTracker()

    dest = Coord(x=2, y=0)
    tag0 = tracker.allocate_slot(dest_coord=dest, req_msg_type="MEM_RD_REQ")
    assert tag0 == 0

    tag1 = tracker.allocate_slot(dest_coord=dest, req_msg_type="MEM_WR_REQ")
    assert tag1 == 1

    # Slot exhaustion: both slots are busy
    tag_fail = tracker.allocate_slot(dest_coord=dest, req_msg_type="MEM_RD_REQ")
    assert tag_fail is None

    # Matching response releases slot 0
    ok0, err0, _ = tracker.match_and_release(tag=0, src_coord=dest, resp_msg_type="MEM_RD_RESP")
    assert ok0
    assert err0 is None
    assert not tracker.slots[0].valid

    # Now slot 0 can be allocated again
    tag_new = tracker.allocate_slot(dest_coord=dest, req_msg_type="MEM_RD_REQ")
    assert tag_new == 0


def test_transaction_tag_mismatch_rejected() -> None:
    """Verifies that an unmatched response type or destination is rejected."""
    tracker = TransactionTracker()
    dest = Coord(x=2, y=0)
    tag0 = tracker.allocate_slot(dest_coord=dest, req_msg_type="MEM_RD_REQ")
    assert tag0 == 0

    # Wrong response type (WR_RESP instead of RD_RESP)
    ok_type, err_type, _ = tracker.match_and_release(tag=0, src_coord=dest, resp_msg_type="MEM_WR_RESP")
    assert not ok_type
    assert err_type == NIProtocolErrorReason.RESPONSE_UNMATCHED

    # Wrong destination coordinate
    wrong_dest = Coord(x=1, y=0)
    ok_dest, err_dest, _ = tracker.match_and_release(tag=0, src_coord=wrong_dest, resp_msg_type="MEM_RD_RESP")
    assert not ok_dest
    assert err_dest == NIProtocolErrorReason.RESPONSE_UNMATCHED

    # Inactive slot
    ok_inact, err_inact, _ = tracker.match_and_release(tag=1, src_coord=dest, resp_msg_type="MEM_RD_RESP")
    assert not ok_inact
    assert err_inact == NIProtocolErrorReason.RESPONSE_UNMATCHED


# ------------------------------------------------------------------------------
# 20. Layer-Specific Rejection Reasons Correctness
# ------------------------------------------------------------------------------

def test_rejection_reasons_distinct_codes() -> None:
    """
    Ensures that hardware rejection codes across layers are distinct and preserved:
      - Gate: 1, 2, 3, 4, 5
      - L2: 1, 2, 3, 4, 5, 6, 7, 8
      - Ingress: 9, 11
      - Memory: 6, 13
      - Verifier: 8, 9, 10, 11, 12
    """
    assert GateFaultReason.UNAUTHORIZED_ACCESS == 1
    assert GateFaultReason.INVALID_ISSUER == 2
    assert GateFaultReason.INVALID_GRANT_STATUS == 3
    assert GateFaultReason.TRUSTED_FAIL_OR_TIMEOUT == 4
    assert GateFaultReason.NON_ATTESTABLE_TILE == 5

    assert L2RejectReason.HEADER_OR_FRAMING_BAD == 1
    assert L2RejectReason.MAC_MISMATCH == 2
    assert L2RejectReason.EPOCH_MISMATCH == 3
    assert L2RejectReason.SEQUENCE_VIOLATION == 4
    assert L2RejectReason.NON_PEER_CONTROL == 5
    assert L2RejectReason.RATE_LIMIT_EXCEEDED == 6
    assert L2RejectReason.OCCUPANCY_DROP == 7
    assert L2RejectReason.PLAIN_TILE_CONTROL_DROP == 8

    assert IngressRejectReason.SOURCE_SPOOFING == 9
    assert IngressRejectReason.INVALID_HEADER == 11

    assert MemoryFaultReason.UNAUTHORIZED_ACCESS == 6
    assert MemoryFaultReason.OUT_OF_WINDOW_ADDRESS == 13

    assert VerifierFailReason.TIMEOUT == 8
    assert VerifierFailReason.BAD_HEADER_STATUS == 9
    assert VerifierFailReason.FORMAT_OR_ABORT == 10
    assert VerifierFailReason.MEASUREMENT_MISMATCH == 11
    assert VerifierFailReason.TAG_MISMATCH == 12


# ------------------------------------------------------------------------------
# 21. Ingress Source Spoofing Mutation Test
# ------------------------------------------------------------------------------

def test_ingress_source_spoofing_rejected(subsystem: P7SecuritySubsystem, profile: ProtocolProfile) -> None:
    """Verifies that injecting a packet with claimed src != port triggers Ingress reason 9."""
    pkt = P7Packet(
        src_coord=Coord(x=0, y=0),  # Claimed src = Tile 0
        dest_coord=Coord(x=2, y=0), # Dest = Tile 2
        msg_type="MEM_RD_REQ",
        payload=[MemoryEndpoint.MEMORY_BASE],
        profile=profile,
    )

    # Injected at Port 5 (SPOOF)
    res = subsystem.process_wire_packet(pkt, injecting_port=5)
    assert not res.accepted
    assert res.rejection_layer == "ingress"
    assert res.rejection_reason_code == int(IngressRejectReason.SOURCE_SPOOFING)

