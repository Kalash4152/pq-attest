#!/usr/bin/env python3
"""
PQ-Attest P7 Verification - Step 2: MAC Framing and Packet Reference Model

This module provides the authoritative reference model for P7 packet construction,
wire/NI framing, serialization/deserialization, and validation.

Protocol parameters (lengths, VCs, encodings, freshness overhead) are dynamically
loaded from the Step 1 protocol manifest (verification/generated/p7_protocol_manifest.json)
rather than being hardcoded.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from enum import Enum, IntEnum
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Union

# Bind to authoritative teammate KMAC128 reference via adapter
try:
    from verification.p7_kmac_adapter import kmac128
except ImportError:
    kmac128 = None


# Status of cryptographic equivalence against live RTL
CRYPTO_EQUIVALENCE_STATUS = "NOT VERIFIED"
CRYPTO_EQUIVALENCE_REASON = (
    "L2 KMAC engine transcript word assembly in noc_l2_auth_p7.sv / l2_kmac_engine.sv "
    "requires dynamic simulation vector verification; equivalence marked NOT VERIFIED "
    "per Step 2 instructions until hardware-in-the-loop oracle validation in Step 4/5."
)

from verification.p7_paths import get_default_paths

# Historical in-repository location (kept for reference). Active lookups go
# through default_manifest_path() so --out / P7_OUT_DIR are honoured.
DEFAULT_MANIFEST_PATH = (
    Path(__file__).resolve().parent / "generated" / "p7_protocol_manifest.json"
)


def default_manifest_path() -> Path:
    """Protocol manifest in the configured generated-artifact directory."""
    return get_default_paths().generated_dir / "p7_protocol_manifest.json"


# ==============================================================================
# Exceptions
# ==============================================================================

class PacketValidationError(ValueError):
    """Raised when packet validation, framing, or decoding fails."""
    pass


# ==============================================================================
# Flit and Header Definitions
# ==============================================================================

class FlitType(IntEnum):
    FLIT_HEAD = 0
    FLIT_BODY = 1
    FLIT_TAIL = 2
    FLIT_HEAD_TAIL = 3


@dataclass(frozen=True)
class Flit:
    """Represents an atomic physical flit on the NoC link."""
    data: int
    flit_type: FlitType
    vc_id: int

    def __post_init__(self) -> None:
        if not (0 <= self.data <= 0xFFFFFFFF):
            raise PacketValidationError(f"Flit data 0x{self.data:X} exceeds 32 bits")
        if not (0 <= self.vc_id <= 3):
            raise PacketValidationError(f"VC ID {self.vc_id} out of bounds")


@dataclass
class Coord:
    x: int
    y: int

    def to_tile_id(self, mesh_x: int = 3) -> int:
        return self.y * mesh_x + self.x

    @classmethod
    def from_tile_id(cls, tile_id: int, mesh_x: int = 3) -> Coord:
        return cls(x=tile_id % mesh_x, y=tile_id // mesh_x)


# ==============================================================================
# Freshness Metadata Model
# ==============================================================================

@dataclass
class FreshnessMetadata:
    """
    Represents the 160-bit freshness overhead injected at the L2 boundary:
      - 64-bit sequence number (seq_q)
      - 80-bit boot epoch (epoch_q)
      - 16-bit padding (must be 0)
    """
    seq: int
    epoch: int
    padding: int = 0

    def validate(self) -> None:
        if not (0 <= self.seq <= 0xFFFFFFFFFFFFFFFF):
            raise PacketValidationError(f"Sequence number {self.seq} out of 64-bit range")
        if not (0 <= self.epoch <= 0xFFFFFFFFFFFFFFFFFFFF):
            raise PacketValidationError(f"Boot epoch {self.epoch} out of 80-bit range")
        if self.padding != 0:
            raise PacketValidationError(f"Freshness padding must be 0, got 0x{self.padding:X}")

    def to_flits(self) -> List[int]:
        """
        Serializes 160-bit freshness into 5 32-bit words (F0 to F4) per RTL:
          F0: seq[31:0]
          F1: seq[63:32]
          F2: epoch[31:0]
          F3: epoch[63:32]
          F4: {padding[15:0], epoch[79:64]}
        """
        self.validate()
        f0 = self.seq & 0xFFFFFFFF
        f1 = (self.seq >> 32) & 0xFFFFFFFF
        f2 = self.epoch & 0xFFFFFFFF
        f3 = (self.epoch >> 32) & 0xFFFFFFFF
        f4 = ((self.padding & 0xFFFF) << 16) | ((self.epoch >> 64) & 0xFFFF)
        return [f0, f1, f2, f3, f4]

    @classmethod
    def from_flits(cls, flits: List[int]) -> FreshnessMetadata:
        """Deserializes 5 32-bit flits into FreshnessMetadata."""
        if len(flits) != 5:
            raise PacketValidationError(f"Expected 5 freshness flits, got {len(flits)}")
        f0, f1, f2, f3, f4 = [f & 0xFFFFFFFF for f in flits]
        seq = (f1 << 32) | f0
        epoch_low = (f3 << 32) | f2
        epoch_high = f4 & 0xFFFF
        epoch = (epoch_high << 64) | epoch_low
        padding = (f4 >> 16) & 0xFFFF
        meta = cls(seq=seq, epoch=epoch, padding=padding)
        meta.validate()
        return meta


# ==============================================================================
# Protocol Profile Loader
# ==============================================================================

class ProtocolProfile:
    """Loads and encapsulates protocol rules from the Step 1 manifest."""

    def __init__(self, manifest_data: Dict[str, Any]) -> None:
        self.manifest = manifest_data
        self.messages: Dict[str, Dict[str, Any]] = manifest_data["messages"]
        self.constants: Dict[str, int] = {
            k: v["value"] for k, v in manifest_data["protocol_constants"].items()
        }
        self.vcs: Dict[str, int] = {
            k: v["id"] for k, v in manifest_data["virtual_channels"].items()
        }
        self.freshness_overhead_flits: int = manifest_data["freshness_overhead"]["value"]

        # Reverse lookup by encoding
        self.enc_to_name: Dict[int, str] = {
            v["encoding"]: k for k, v in self.messages.items()
        }

    @classmethod
    def load(cls, manifest_path: Optional[Path | str] = None) -> ProtocolProfile:
        p = Path(manifest_path) if manifest_path else default_manifest_path()
        if not p.exists():
            raise FileNotFoundError(
                f"Protocol manifest not found at {p.resolve()}. "
                f"Please run Step 1 (verification.p7_rtl_parser) first."
            )
        data = json.loads(p.read_text(encoding="utf-8"))
        return cls(data)

    def get_msg_spec(self, msg_type: Union[str, int]) -> Dict[str, Any]:
        if isinstance(msg_type, int):
            if msg_type not in self.enc_to_name:
                raise PacketValidationError(f"Unknown message encoding {msg_type}")
            return self.messages[self.enc_to_name[msg_type]]
        # String lookup: handle MSG_ prefix or bare name
        clean = msg_type.replace("MSG_", "")
        if clean not in self.messages:
            raise PacketValidationError(f"Unknown message type '{msg_type}'")
        return self.messages[clean]


# ==============================================================================
# P7 Packet Reference Model
# ==============================================================================

@dataclass
class P7Packet:
    """
    Authoritative reference model for a P7 NoC packet.
    """
    src_coord: Coord
    dest_coord: Coord
    msg_type: str
    payload: List[int] = field(default_factory=list)
    control_field: int = 0
    mac_flits: List[int] = field(default_factory=list)
    freshness: Optional[FreshnessMetadata] = None
    profile: ProtocolProfile = field(default_factory=ProtocolProfile.load)

    def __post_init__(self) -> None:
        self.spec = self.profile.get_msg_spec(self.msg_type)
        self.short_name = self.spec["short_name"]
        self.encoding = self.spec["encoding"]
        self.is_control = self.spec["is_control"]
        self.expected_payload_len = self.spec["payload_flits"]
        self.expected_mac_len = self.spec["mac_flits"]
        self.expected_ni_len = self.spec["ni_length"]
        self.expected_wire_len = self.spec["wire_length"]
        self.vc_id = self.spec["vc_id"]
        self.vc_name = self.spec["vc_name"]

    @property
    def ni_length(self) -> int:
        """Computed NI packet length = 1 (HEAD) + payload + mac."""
        return 1 + len(self.payload) + len(self.mac_flits)

    @property
    def wire_length(self) -> int:
        """Computed mesh wire length = NI length + (freshness if control else 0)."""
        f_len = self.profile.freshness_overhead_flits if self.is_control and self.freshness else 0
        return self.ni_length + f_len

    @property
    def mac_tag_128(self) -> Optional[int]:
        """Returns 128-bit MAC tag if present."""
        if len(self.mac_flits) != 4:
            return None
        return (
            (self.mac_flits[0] & 0xFFFFFFFF)
            | ((self.mac_flits[1] & 0xFFFFFFFF) << 32)
            | ((self.mac_flits[2] & 0xFFFFFFFF) << 64)
            | ((self.mac_flits[3] & 0xFFFFFFFF) << 96)
        )

    def set_mac_tag_128(self, tag: int) -> None:
        """Sets 4 MAC flits from a 128-bit integer tag."""
        if not self.is_control:
            raise PacketValidationError(f"Cannot set MAC on data-plane message '{self.short_name}'")
        if not (0 <= tag < (1 << 128)):
            raise PacketValidationError(f"MAC tag 0x{tag:X} exceeds 128 bits")
        self.mac_flits = [
            (tag >> (32 * i)) & 0xFFFFFFFF for i in range(4)
        ]

    # --------------------------------------------------------------------------
    # Validation Rules
    # --------------------------------------------------------------------------

    def validate(self, wire_mode: bool = False) -> None:
        """
        Validates packet according to P7 specification:
          - Topology coordinate checks
          - Payload length matching specification
          - MAC framing: exactly 4 words for control, exactly 0 for data
          - Length field conformance (NI length vs Wire length)
          - Freshness presence on control wire packets
        """
        mesh_x = self.profile.constants.get("MESH_X", 3)
        mesh_y = self.profile.constants.get("MESH_Y", 2)

        if not (0 <= self.src_coord.x < mesh_x and 0 <= self.src_coord.y < mesh_y):
            raise PacketValidationError(f"Source coord ({self.src_coord.x},{self.src_coord.y}) out of mesh bounds")
        if not (0 <= self.dest_coord.x < mesh_x and 0 <= self.dest_coord.y < mesh_y):
            raise PacketValidationError(f"Dest coord ({self.dest_coord.x},{self.dest_coord.y}) out of mesh bounds")

        # Payload checks
        if len(self.payload) != self.expected_payload_len:
            raise PacketValidationError(
                f"Payload length {len(self.payload)} does not match expected {self.expected_payload_len} "
                f"for '{self.short_name}'"
            )
        for i, word in enumerate(self.payload):
            if not (0 <= word <= 0xFFFFFFFF):
                raise PacketValidationError(f"Payload word {i} (0x{word:X}) exceeds 32 bits")

        # Control field
        if not (0 <= self.control_field <= 0x7FF):
            raise PacketValidationError(f"Control field 0x{self.control_field:X} exceeds 11 bits")

        # MAC framing checks
        if self.is_control:
            if len(self.mac_flits) != 4:
                raise PacketValidationError(
                    f"Control message '{self.short_name}' must carry exactly 4 MAC flits, got {len(self.mac_flits)}"
                )
            for i, word in enumerate(self.mac_flits):
                if not (0 <= word <= 0xFFFFFFFF):
                    raise PacketValidationError(f"MAC word {i} (0x{word:X}) exceeds 32 bits")
        else:
            if len(self.mac_flits) != 0:
                raise PacketValidationError(
                    f"Data message '{self.short_name}' must have 0 MAC flits, got {len(self.mac_flits)}"
                )

        # Length checks
        if self.ni_length != self.expected_ni_len:
            raise PacketValidationError(
                f"NI length {self.ni_length} does not match expected {self.expected_ni_len} for '{self.short_name}'"
            )

        if wire_mode:
            if self.is_control:
                if self.freshness is None:
                    raise PacketValidationError(f"Freshness metadata required for control wire packet '{self.short_name}'")
                self.freshness.validate()
            else:
                if self.freshness is not None:
                    raise PacketValidationError(f"Freshness metadata not permitted on data wire packet '{self.short_name}'")

            if self.wire_length != self.expected_wire_len:
                raise PacketValidationError(
                    f"Wire length {self.wire_length} does not match expected {self.expected_wire_len} for '{self.short_name}'"
                )

    # --------------------------------------------------------------------------
    # Serialization (Packet -> Flits)
    # --------------------------------------------------------------------------

    def build_header_word(self, length: int) -> int:
        """
        Builds packed 32-bit HEAD flit data per NOC_PKG.sv:
          [31:29] dest_x
          [28:26] dest_y
          [25:23] src_x
          [22:20] src_y
          [19:16] msg_type
          [15:11] length
          [10:0]  control
        """
        return (
            ((self.dest_coord.x & 0x7) << 29)
            | ((self.dest_coord.y & 0x7) << 26)
            | ((self.src_coord.x & 0x7) << 23)
            | ((self.src_coord.y & 0x7) << 20)
            | ((self.encoding & 0xF) << 16)
            | ((length & 0x1F) << 11)
            | (self.control_field & 0x7FF)
        )

    def to_ni_flits(self) -> List[Flit]:
        """
        Generates flit sequence presented at / produced by the Network Interface:
          HEAD (length = NI length) -> Payload flits -> MAC flits
        """
        self.validate(wire_mode=False)
        flits: List[Flit] = []
        tot_flits = self.ni_length

        # Head flit
        head_data = self.build_header_word(tot_flits)
        head_type = FlitType.FLIT_HEAD_TAIL if tot_flits == 1 else FlitType.FLIT_HEAD
        flits.append(Flit(data=head_data, flit_type=head_type, vc_id=self.vc_id))

        if tot_flits == 1:
            return flits

        # Payload flits
        for i, word in enumerate(self.payload):
            is_last = (i == len(self.payload) - 1) and (len(self.mac_flits) == 0)
            ft = FlitType.FLIT_TAIL if is_last else FlitType.FLIT_BODY
            flits.append(Flit(data=word & 0xFFFFFFFF, flit_type=ft, vc_id=self.vc_id))

        # MAC flits
        for i, word in enumerate(self.mac_flits):
            is_last = (i == len(self.mac_flits) - 1)
            ft = FlitType.FLIT_TAIL if is_last else FlitType.FLIT_BODY
            flits.append(Flit(data=word & 0xFFFFFFFF, flit_type=ft, vc_id=self.vc_id))

        return flits

    def to_wire_flits(self) -> List[Flit]:
        """
        Generates flit sequence on the mesh wire after L2 auth processing:
          - Data packets: pass-through plain (same as NI flits)
          - Control packets: HEAD (length = wire length) -> F0-F4 -> Payload -> MAC
        """
        self.validate(wire_mode=True)
        flits: List[Flit] = []
        tot_flits = self.wire_length

        head_data = self.build_header_word(tot_flits)
        head_type = FlitType.FLIT_HEAD_TAIL if tot_flits == 1 else FlitType.FLIT_HEAD
        flits.append(Flit(data=head_data, flit_type=head_type, vc_id=self.vc_id))

        if tot_flits == 1:
            return flits

        # Control packet freshness flits F0..F4
        if self.is_control:
            assert self.freshness is not None
            fresh_words = self.freshness.to_flits()
            for word in fresh_words:
                flits.append(Flit(data=word, flit_type=FlitType.FLIT_BODY, vc_id=self.vc_id))

        # Payload flits
        for i, word in enumerate(self.payload):
            is_last = (i == len(self.payload) - 1) and (len(self.mac_flits) == 0) and not self.is_control
            ft = FlitType.FLIT_TAIL if is_last else FlitType.FLIT_BODY
            flits.append(Flit(data=word & 0xFFFFFFFF, flit_type=ft, vc_id=self.vc_id))

        # MAC flits (control packets)
        for i, word in enumerate(self.mac_flits):
            is_last = (i == len(self.mac_flits) - 1)
            ft = FlitType.FLIT_TAIL if is_last else FlitType.FLIT_BODY
            flits.append(Flit(data=word & 0xFFFFFFFF, flit_type=ft, vc_id=self.vc_id))

        return flits

    # --------------------------------------------------------------------------
    # Deserialization (Flits -> Packet)
    # --------------------------------------------------------------------------

    @classmethod
    def from_ni_flits(
        cls,
        flits: List[Flit],
        profile: Optional[ProtocolProfile] = None,
    ) -> P7Packet:
        """Parses an NI flit sequence into a P7Packet."""
        prof = profile or ProtocolProfile.load()
        if not flits:
            raise PacketValidationError("Cannot decode empty flit list")

        head = flits[0]
        if head.flit_type not in (FlitType.FLIT_HEAD, FlitType.FLIT_HEAD_TAIL):
            raise PacketValidationError(f"Expected HEAD flit at position 0, got {head.flit_type.name}")

        d = head.data
        dest_x = (d >> 29) & 0x7
        dest_y = (d >> 26) & 0x7
        src_x = (d >> 23) & 0x7
        src_y = (d >> 22) & 0x7 if False else (d >> 20) & 0x7
        msg_enc = (d >> 16) & 0xF
        length_field = (d >> 11) & 0x1F
        control_field = d & 0x7FF

        spec = prof.get_msg_spec(msg_enc)
        msg_name = spec["short_name"]
        exp_payload = spec["payload_flits"]
        exp_mac = spec["mac_flits"]
        exp_ni_len = spec["ni_length"]

        if length_field != exp_ni_len:
            raise PacketValidationError(
                f"HEAD length field {length_field} != expected NI length {exp_ni_len} for '{msg_name}'"
            )
        if len(flits) != exp_ni_len:
            raise PacketValidationError(
                f"Flit count {len(flits)} != expected NI length {exp_ni_len} for '{msg_name}'"
            )

        payload_words = [f.data for f in flits[1 : 1 + exp_payload]]
        mac_words = [f.data for f in flits[1 + exp_payload : 1 + exp_payload + exp_mac]]

        pkt = cls(
            src_coord=Coord(x=src_x, y=src_y),
            dest_coord=Coord(x=dest_x, y=dest_y),
            msg_type=msg_name,
            payload=payload_words,
            control_field=control_field,
            mac_flits=mac_words,
            freshness=None,
            profile=prof,
        )
        pkt.validate(wire_mode=False)
        return pkt

    @classmethod
    def from_wire_flits(
        cls,
        flits: List[Flit],
        profile: Optional[ProtocolProfile] = None,
    ) -> P7Packet:
        """Parses a wire flit sequence into a P7Packet."""
        prof = profile or ProtocolProfile.load()
        if not flits:
            raise PacketValidationError("Cannot decode empty flit list")

        head = flits[0]
        if head.flit_type not in (FlitType.FLIT_HEAD, FlitType.FLIT_HEAD_TAIL):
            raise PacketValidationError(f"Expected HEAD flit at position 0, got {head.flit_type.name}")

        d = head.data
        dest_x = (d >> 29) & 0x7
        dest_y = (d >> 26) & 0x7
        src_x = (d >> 23) & 0x7
        src_y = (d >> 20) & 0x7
        msg_enc = (d >> 16) & 0xF
        length_field = (d >> 11) & 0x1F
        control_field = d & 0x7FF

        spec = prof.get_msg_spec(msg_enc)
        msg_name = spec["short_name"]
        is_control = spec["is_control"]
        exp_payload = spec["payload_flits"]
        exp_mac = spec["mac_flits"]
        exp_wire_len = spec["wire_length"]

        if length_field != exp_wire_len:
            raise PacketValidationError(
                f"HEAD length field {length_field} != expected wire length {exp_wire_len} for '{msg_name}'"
            )
        if len(flits) != exp_wire_len:
            raise PacketValidationError(
                f"Flit count {len(flits)} != expected wire length {exp_wire_len} for '{msg_name}'"
            )

        freshness_meta: Optional[FreshnessMetadata] = None
        curr = 1

        if is_control:
            freshness_words = [f.data for f in flits[curr : curr + 5]]
            freshness_meta = FreshnessMetadata.from_flits(freshness_words)
            curr += 5

        payload_words = [f.data for f in flits[curr : curr + exp_payload]]
        curr += exp_payload

        mac_words = [f.data for f in flits[curr : curr + exp_mac]]
        curr += exp_mac

        pkt = cls(
            src_coord=Coord(x=src_x, y=src_y),
            dest_coord=Coord(x=dest_x, y=dest_y),
            msg_type=msg_name,
            payload=payload_words,
            control_field=control_field,
            mac_flits=mac_words,
            freshness=freshness_meta,
            profile=prof,
        )
        pkt.validate(wire_mode=True)
        return pkt


# ==============================================================================
# KMAC128 Reference Interface (with explicit verification status)
# ==============================================================================

def compute_p7_l2_transcript(pkt: P7Packet) -> bytes:
    """
    Constructs the 24 + 4*pn byte transcript according to R6.6 / noc_l2_auth_p7.sv:
      Word 0: wire HEAD
      Word 1: {epoch[15:0], 8'd1 (ver), 8'(VC)}
      Word 2: epoch[47:16]
      Word 3: epoch[79:48]
      Word 4: seq[31:0]
      Word 5: seq[63:32]
      Words 6..: payload words tp[0..pn-1]
    All words are packed in little-endian byte order matching the RTL bit-slices.
    """
    if not pkt.is_control or not pkt.freshness:
        raise PacketValidationError("Transcript only defined for control packets with freshness")

    wire_head = pkt.build_header_word(pkt.wire_length)
    epoch = pkt.freshness.epoch
    seq = pkt.freshness.seq
    vc = pkt.vc_id

    w0 = wire_head
    w1 = ((epoch & 0xFFFF) << 16) | (1 << 8) | (vc & 0xFF)
    w2 = (epoch >> 16) & 0xFFFFFFFF
    w3 = (epoch >> 48) & 0xFFFFFFFF
    w4 = seq & 0xFFFFFFFF
    w5 = (seq >> 32) & 0xFFFFFFFF

    words = [w0, w1, w2, w3, w4, w5] + pkt.payload
    raw_bytes = bytearray()
    for w in words:
        raw_bytes.extend((w & 0xFFFFFFFF).to_bytes(4, byteorder="little"))
    return bytes(raw_bytes)


def compute_p7_kmac128_tag(
    key: bytes,
    pkt: P7Packet,
) -> Tuple[int, List[int], str]:
    """
    Calculates 128-bit KMAC128 tag over the P7 packet transcript.
    Returns:
      (tag_128, [mac_flit_0, mac_flit_1, mac_flit_2, mac_flit_3], equivalence_status)
    """
    if kmac128 is None:
        raise RuntimeError("kmac128 reference implementation unavailable via verification.p7_kmac_adapter")

    if len(key) != 32:
        raise PacketValidationError(f"Expected 32-byte (256-bit) key, got {len(key)} bytes")

    transcript = compute_p7_l2_transcript(pkt)
    # RTL DOMAIN = 112'h31762d485455412d324c2d434f4e -> b"NOC-L2-AUTH-v1"
    customization = b"NOC-L2-AUTH-v1"

    tag_bytes = kmac128(
        key=key,
        message=transcript,
        output_bytes=16,
        customization=customization,
    )

    tag_128 = int.from_bytes(tag_bytes, byteorder="little")
    mac_flits = [(tag_128 >> (32 * i)) & 0xFFFFFFFF for i in range(4)]

    # Returns NOT VERIFIED per Step 2 instruction
    return tag_128, mac_flits, CRYPTO_EQUIVALENCE_STATUS

