#!/usr/bin/env python3
"""
Test suite for verification/p7_packet_model.py.

Validates:
  - All 8 P7 message types (data and control planes).
  - Exact payload length enforcement.
  - MAC framing (exactly 4 flits for control, 0 for data).
  - Freshness serialization and deserialization (160 bits: 16-bit pad, 80-bit epoch, 64-bit seq).
  - Boundary values for epoch (0, 2^80 - 1) and seq (0, 2^64 - 1).
  - Rejection of negative/mutation cases:
      * incorrect payload lengths
      * incorrect MAC lengths
      * incorrect NI lengths
      * incorrect wire lengths
      * invalid message types
      * invalid freshness padding/widths
      * out-of-bounds coordinates
  - Deterministic packet round-trip serialization (NI and Wire).
  - KMAC framing interface and explicit NOT VERIFIED equivalence status.
"""

from __future__ import annotations

import pytest

from verification.p7_packet_model import (
    CRYPTO_EQUIVALENCE_STATUS,
    Coord,
    Flit,
    FlitType,
    FreshnessMetadata,
    P7Packet,
    PacketValidationError,
    ProtocolProfile,
    compute_p7_kmac128_tag,
    compute_p7_l2_transcript,
)


@pytest.fixture
def profile() -> ProtocolProfile:
    """Loads protocol profile dynamically from Step 1 manifest."""
    return ProtocolProfile.load()


# ------------------------------------------------------------------------------
# 1. All Eight Message Types: Exact Payload and Framing
# ------------------------------------------------------------------------------

@pytest.mark.parametrize("msg_name,exp_payload_len,exp_mac_len,exp_ni_len,exp_wire_len,is_ctrl", [
    ("MEM_RD_REQ", 1, 0, 2, 2, False),
    ("MEM_RD_RESP", 1, 0, 2, 2, False),
    ("MEM_WR_REQ", 2, 0, 3, 3, False),
    ("MEM_WR_RESP", 0, 0, 1, 1, False),
    ("ATTEST_CHALLENGE", 7, 4, 12, 17, True),
    ("ATTEST_RESPONSE", 16, 4, 21, 26, True),
    ("ATTEST_GRANT", 0, 4, 5, 10, True),
    ("ATTEST_REVOKE", 0, 4, 5, 10, True),
])
def test_all_eight_message_types_framing(
    profile: ProtocolProfile,
    msg_name: str,
    exp_payload_len: int,
    exp_mac_len: int,
    exp_ni_len: int,
    exp_wire_len: int,
    is_ctrl: bool,
) -> None:
    """Verifies that each message type conforms to dynamic manifest specifications."""
    payload = [0x1000 + i for i in range(exp_payload_len)]
    mac_flits = [0xA0 + i for i in range(exp_mac_len)] if is_ctrl else []
    freshness = FreshnessMetadata(seq=42, epoch=0x123456789ABCDEF01234) if is_ctrl else None

    pkt = P7Packet(
        src_coord=Coord(x=0, y=1),  # Tile 3
        dest_coord=Coord(x=1, y=1), # Tile 4
        msg_type=msg_name,
        payload=payload,
        control_field=0x7A,
        mac_flits=mac_flits,
        freshness=freshness,
        profile=profile,
    )

    pkt.validate(wire_mode=True)
    assert pkt.is_control == is_ctrl
    assert pkt.ni_length == exp_ni_len
    assert pkt.wire_length == exp_wire_len
    assert len(pkt.payload) == exp_payload_len
    assert len(pkt.mac_flits) == exp_mac_len


# ------------------------------------------------------------------------------
# 2. Freshness Serialization, Deserialization, and Boundaries
# ------------------------------------------------------------------------------

def test_freshness_serialization_and_boundaries() -> None:
    """Tests 160-bit freshness flit layout and boundary values."""
    # Zero boundary
    f_zero = FreshnessMetadata(seq=0, epoch=0, padding=0)
    words_zero = f_zero.to_flits()
    assert words_zero == [0, 0, 0, 0, 0]
    f_zero_rt = FreshnessMetadata.from_flits(words_zero)
    assert f_zero_rt.seq == 0
    assert f_zero_rt.epoch == 0
    assert f_zero_rt.padding == 0

    # Max boundaries: 64-bit seq, 80-bit epoch
    max_seq = (1 << 64) - 1
    max_epoch = (1 << 80) - 1
    f_max = FreshnessMetadata(seq=max_seq, epoch=max_epoch, padding=0)
    words_max = f_max.to_flits()
    assert words_max[0] == 0xFFFFFFFF
    assert words_max[1] == 0xFFFFFFFF
    assert words_max[2] == 0xFFFFFFFF
    assert words_max[3] == 0xFFFFFFFF
    assert words_max[4] == 0x0000FFFF  # padding=0 (bits 31:16), epoch high (bits 15:0)

    f_max_rt = FreshnessMetadata.from_flits(words_max)
    assert f_max_rt.seq == max_seq
    assert f_max_rt.epoch == max_epoch
    assert f_max_rt.padding == 0

    # Arbitrary known pattern
    f_val = FreshnessMetadata(seq=0x11223344_55667788, epoch=0x0102_03040506_0708090A)
    words = f_val.to_flits()
    assert words[0] == 0x55667788
    assert words[1] == 0x11223344
    assert words[2] == 0x0708090A
    assert words[3] == 0x03040506
    assert words[4] == 0x00000102

    f_rt = FreshnessMetadata.from_flits(words)
    assert f_rt.seq == f_val.seq
    assert f_rt.epoch == f_val.epoch


def test_freshness_validation_rejections() -> None:
    """Verifies that invalid freshness values are rejected."""
    # Non-zero padding
    with pytest.raises(PacketValidationError, match="Freshness padding must be 0"):
        FreshnessMetadata(seq=1, epoch=1, padding=0x12).validate()

    # Out of range seq (> 64 bits)
    with pytest.raises(PacketValidationError, match="Sequence number .* out of 64-bit range"):
        FreshnessMetadata(seq=1 << 64, epoch=1).validate()

    # Negative seq
    with pytest.raises(PacketValidationError, match="Sequence number .* out of 64-bit range"):
        FreshnessMetadata(seq=-1, epoch=1).validate()

    # Out of range epoch (> 80 bits)
    with pytest.raises(PacketValidationError, match="Boot epoch .* out of 80-bit range"):
        FreshnessMetadata(seq=1, epoch=1 << 80).validate()

    # Deserializing non-zero padding from flit F4
    bad_f4_words = [0, 0, 0, 0, 0x00010000]  # padding = 1
    with pytest.raises(PacketValidationError, match="Freshness padding must be 0"):
        FreshnessMetadata.from_flits(bad_f4_words)

    # Wrong number of flits
    with pytest.raises(PacketValidationError, match="Expected 5 freshness flits"):
        FreshnessMetadata.from_flits([0, 0, 0, 0])


# ------------------------------------------------------------------------------
# 3. Deterministic Serialization & Deserialization Round-Trip
# ------------------------------------------------------------------------------

def test_deterministic_round_trip_ni_and_wire(profile: ProtocolProfile) -> None:
    """Tests bit-exact deterministic serialization and deserialization for all types."""
    for msg_name in ["MEM_RD_REQ", "MEM_WR_REQ", "MEM_WR_RESP", "ATTEST_CHALLENGE", "ATTEST_RESPONSE", "ATTEST_GRANT"]:
        spec = profile.get_msg_spec(msg_name)
        payload = [0xDEAD0000 + i for i in range(spec["payload_flits"])]
        mac_flits = [0xCAFE0000 + i for i in range(spec["mac_flits"])] if spec["is_control"] else []
        freshness = FreshnessMetadata(seq=101, epoch=0x5555_AAAA_1234_5678_9ABC) if spec["is_control"] else None

        pkt = P7Packet(
            src_coord=Coord(x=0, y=0),
            dest_coord=Coord(x=2, y=1),
            msg_type=msg_name,
            payload=payload,
            control_field=0x123,
            mac_flits=mac_flits,
            freshness=freshness,
            profile=profile,
        )

        # 1. NI round trip
        ni_flits = pkt.to_ni_flits()
        assert len(ni_flits) == spec["ni_length"]
        # Check head/body/tail framing
        if len(ni_flits) == 1:
            assert ni_flits[0].flit_type == FlitType.FLIT_HEAD_TAIL
        else:
            assert ni_flits[0].flit_type == FlitType.FLIT_HEAD
            for f in ni_flits[1:-1]:
                assert f.flit_type == FlitType.FLIT_BODY
            assert ni_flits[-1].flit_type == FlitType.FLIT_TAIL

        pkt_ni_rt = P7Packet.from_ni_flits(ni_flits, profile=profile)
        assert pkt_ni_rt.short_name == pkt.short_name
        assert pkt_ni_rt.payload == pkt.payload
        assert pkt_ni_rt.mac_flits == pkt.mac_flits
        assert pkt_ni_rt.control_field == pkt.control_field
        assert pkt_ni_rt.src_coord == pkt.src_coord
        assert pkt_ni_rt.dest_coord == pkt.dest_coord

        # 2. Wire round trip
        wire_flits = pkt.to_wire_flits()
        assert len(wire_flits) == spec["wire_length"]
        if len(wire_flits) == 1:
            assert wire_flits[0].flit_type == FlitType.FLIT_HEAD_TAIL
        else:
            assert wire_flits[0].flit_type == FlitType.FLIT_HEAD
            for f in wire_flits[1:-1]:
                assert f.flit_type == FlitType.FLIT_BODY
            assert wire_flits[-1].flit_type == FlitType.FLIT_TAIL

        pkt_wire_rt = P7Packet.from_wire_flits(wire_flits, profile=profile)
        assert pkt_wire_rt.short_name == pkt.short_name
        assert pkt_wire_rt.payload == pkt.payload
        assert pkt_wire_rt.mac_flits == pkt.mac_flits
        assert pkt_wire_rt.control_field == pkt.control_field
        if spec["is_control"]:
            assert pkt_wire_rt.freshness is not None
            assert pkt_wire_rt.freshness.seq == freshness.seq
            assert pkt_wire_rt.freshness.epoch == freshness.epoch


# ------------------------------------------------------------------------------
# 4. Negative and Mutation Tests: Payload Length Violations
# ------------------------------------------------------------------------------

def test_reject_incorrect_payload_length(profile: ProtocolProfile) -> None:
    """Verifies rejection when payload flits count does not match profile."""
    # ATTEST_CHALLENGE expects 7 flits; give 6 flits
    with pytest.raises(PacketValidationError, match="Payload length 6 does not match expected 7"):
        pkt = P7Packet(
            src_coord=Coord(x=0, y=1),
            dest_coord=Coord(x=1, y=1),
            msg_type="ATTEST_CHALLENGE",
            payload=[1, 2, 3, 4, 5, 6],
            mac_flits=[0, 1, 2, 3],
            profile=profile,
        )
        pkt.validate()

    # MEM_RD_REQ expects 1 flit; give 2 flits
    with pytest.raises(PacketValidationError, match="Payload length 2 does not match expected 1"):
        pkt = P7Packet(
            src_coord=Coord(x=0, y=0),
            dest_coord=Coord(x=2, y=0),
            msg_type="MEM_RD_REQ",
            payload=[0x1234, 0x5678],
            profile=profile,
        )
        pkt.validate()


# ------------------------------------------------------------------------------
# 5. Negative and Mutation Tests: MAC Framing Violations
# ------------------------------------------------------------------------------

def test_reject_incorrect_mac_length_control_packets(profile: ProtocolProfile) -> None:
    """Verifies that control messages with missing or wrong MAC length are rejected."""
    # Control packet with 0 MAC flits (missing MAC)
    with pytest.raises(PacketValidationError, match="Control message .* must carry exactly 4 MAC flits, got 0"):
        pkt = P7Packet(
            src_coord=Coord(x=0, y=1),
            dest_coord=Coord(x=1, y=1),
            msg_type="ATTEST_CHALLENGE",
            payload=[i for i in range(7)],
            mac_flits=[],
            profile=profile,
        )
        pkt.validate()

    # Control packet with 3 MAC flits (truncated MAC)
    with pytest.raises(PacketValidationError, match="Control message .* must carry exactly 4 MAC flits, got 3"):
        pkt = P7Packet(
            src_coord=Coord(x=0, y=1),
            dest_coord=Coord(x=1, y=1),
            msg_type="ATTEST_RESPONSE",
            payload=[i for i in range(16)],
            mac_flits=[1, 2, 3],
            profile=profile,
        )
        pkt.validate()

    # Control packet with 5 MAC flits (extra MAC)
    with pytest.raises(PacketValidationError, match="Control message .* must carry exactly 4 MAC flits, got 5"):
        pkt = P7Packet(
            src_coord=Coord(x=0, y=1),
            dest_coord=Coord(x=1, y=1),
            msg_type="ATTEST_GRANT",
            payload=[],
            mac_flits=[1, 2, 3, 4, 5],
            profile=profile,
        )
        pkt.validate()


def test_reject_unexpected_mac_on_data_packets(profile: ProtocolProfile) -> None:
    """Verifies that data-plane packets carrying any MAC flits are rejected."""
    with pytest.raises(PacketValidationError, match="Data message .* must have 0 MAC flits, got 4"):
        pkt = P7Packet(
            src_coord=Coord(x=0, y=0),
            dest_coord=Coord(x=2, y=0),
            msg_type="MEM_WR_REQ",
            payload=[0x1111, 0x2222],
            mac_flits=[1, 2, 3, 4],
            profile=profile,
        )
        pkt.validate()


# ------------------------------------------------------------------------------
# 6. Negative and Mutation Tests: Wire and NI Length Violations
# ------------------------------------------------------------------------------

def test_reject_corrupted_wire_length_field(profile: ProtocolProfile) -> None:
    """Mutates the length field in wire flits; verifies deserializer rejects it."""
    pkt = P7Packet(
        src_coord=Coord(x=0, y=1),
        dest_coord=Coord(x=1, y=1),
        msg_type="ATTEST_CHALLENGE",
        payload=[i for i in range(7)],
        mac_flits=[1, 2, 3, 4],
        freshness=FreshnessMetadata(seq=1, epoch=1),
        profile=profile,
    )
    flits = pkt.to_wire_flits()
    # Mutate length field in HEAD flit (set length field to 15 instead of 17)
    corrupted_data = (flits[0].data & ~(0x1F << 11)) | (15 << 11)
    corrupted_flits = [Flit(data=corrupted_data, flit_type=flits[0].flit_type, vc_id=flits[0].vc_id)] + flits[1:]

    with pytest.raises(PacketValidationError, match="HEAD length field 15 != expected wire length 17"):
        P7Packet.from_wire_flits(corrupted_flits, profile=profile)


def test_reject_truncated_wire_packet(profile: ProtocolProfile) -> None:
    """Truncates one flit from wire packet; verifies deserializer rejects it."""
    pkt = P7Packet(
        src_coord=Coord(x=0, y=1),
        dest_coord=Coord(x=1, y=1),
        msg_type="ATTEST_CHALLENGE",
        payload=[i for i in range(7)],
        mac_flits=[1, 2, 3, 4],
        freshness=FreshnessMetadata(seq=1, epoch=1),
        profile=profile,
    )
    flits = pkt.to_wire_flits()
    truncated_flits = flits[:-1]

    with pytest.raises(PacketValidationError, match="Flit count 16 != expected wire length 17"):
        P7Packet.from_wire_flits(truncated_flits, profile=profile)


# ------------------------------------------------------------------------------
# 7. Negative Tests: Invalid Message Types and Out-of-Mesh Coordinates
# ------------------------------------------------------------------------------

def test_reject_invalid_message_type(profile: ProtocolProfile) -> None:
    """Verifies that non-existent message types are rejected."""
    with pytest.raises(PacketValidationError, match="Unknown message type 'INVALID_TYPE'"):
        P7Packet(
            src_coord=Coord(0, 0),
            dest_coord=Coord(1, 0),
            msg_type="INVALID_TYPE",
            profile=profile,
        )

    with pytest.raises(PacketValidationError, match="Unknown message encoding 15"):
        profile.get_msg_spec(15)


def test_reject_out_of_mesh_coordinates(profile: ProtocolProfile) -> None:
    """Verifies coordinate boundary checks (3x2 mesh)."""
    # X out of bounds (>= 3)
    with pytest.raises(PacketValidationError, match="Source coord \\(3,0\\) out of mesh bounds"):
        pkt = P7Packet(
            src_coord=Coord(3, 0),
            dest_coord=Coord(1, 0),
            msg_type="MEM_RD_REQ",
            payload=[1],
            profile=profile,
        )
        pkt.validate()

    # Y out of bounds (>= 2)
    with pytest.raises(PacketValidationError, match="Dest coord \\(0,2\\) out of mesh bounds"):
        pkt = P7Packet(
            src_coord=Coord(0, 0),
            dest_coord=Coord(0, 2),
            msg_type="MEM_RD_REQ",
            payload=[1],
            profile=profile,
        )
        pkt.validate()


# ------------------------------------------------------------------------------
# 8. KMAC Framing Interface and Cryptographic Status
# ------------------------------------------------------------------------------

def test_kmac_framing_interface_and_status(profile: ProtocolProfile) -> None:
    """
    Tests KMAC transcript generation and framing interface.
    Asserts equivalence status is explicitly marked NOT VERIFIED.
    """
    key = bytes(range(32))  # 256-bit dummy key
    pkt = P7Packet(
        src_coord=Coord(x=0, y=1),
        dest_coord=Coord(x=1, y=1),
        msg_type="ATTEST_CHALLENGE",
        payload=[i for i in range(7)],
        control_field=0x15,
        freshness=FreshnessMetadata(seq=1, epoch=0xABC),
        profile=profile,
    )

    transcript = compute_p7_l2_transcript(pkt)
    # 24 header bytes (6 words) + 4 * 7 payload bytes = 52 bytes
    assert len(transcript) == 24 + 4 * 7

    tag_128, mac_flits, status = compute_p7_kmac128_tag(key, pkt)
    assert len(mac_flits) == 4
    assert 0 <= tag_128 < (1 << 128)
    assert status == CRYPTO_EQUIVALENCE_STATUS
    assert status == "NOT VERIFIED"

    # Set tag into packet and validate
    pkt.set_mac_tag_128(tag_128)
    assert pkt.mac_flits == mac_flits
    pkt.validate(wire_mode=True)

