#!/usr/bin/env python3
"""
PQ-Attest P7 Verification - Step 3: Authorization and Replay Reference Model

This module implements an authoritative, independent, stateful reference model
for the P7 security enforcement rules directly established by the SystemVerilog RTL:
  - rtl/dual_lane/noc_attest_gate.sv (tile authorization, fault accounting)
  - rtl/dual_lane/noc_l2_auth_p7.sv (replay protection, freshness checks, L2 verdicts)
  - rtl/dual_lane/noc_ingress_parser.sv (source spoofing, header checks)
  - rtl/dual_lane/noc_network_interface_p7.sv (transaction matching, 2 slots, control refusal)
  - rtl/dual_lane/pq_noc_subsystem_p7.sv (memory authorization at side-effect, response suppression)
  - rtl/dual_lane/pq_rot_verifier.sv (verifier failure/timeout reasons)

The model strictly separates:
  1. Structural validity (flit/length formatting)
  2. Cryptographic verification (explicit MAC tag checking)
  3. Freshness / replay status (epoch and sequence monotonicity)
  4. Authorization (tile grant/gate permissions)
  5. Operation acceptance (memory commit / delivery)
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum, IntEnum
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple, Union

from verification.p7_packet_model import (
    Coord,
    Flit,
    FreshnessMetadata,
    P7Packet,
    PacketValidationError,
    ProtocolProfile,
)


# ==============================================================================
# Layer-Specific Rejection Reasons (Byte-identical to RTL constants)
# ==============================================================================

class GateFaultReason(IntEnum):
    """noc_attest_gate.sv lines 37-48."""
    NONE = 0
    UNAUTHORIZED_ACCESS = 1       # line 37: app_valid && !allowed
    INVALID_ISSUER = 2            # line 44: source != RoT
    INVALID_GRANT_STATUS = 3      # line 48: control[10:7] != 1
    TRUSTED_FAIL_OR_TIMEOUT = 4   # line 39: trusted_fail || trusted_timeout
    NON_ATTESTABLE_TILE = 5       # line 42: !ATTESTABLE (tiles 0, 1, 2, 5)


class L2RejectReason(IntEnum):
    """noc_l2_auth_p7.sv lines 208-283."""
    NONE = 0
    HEADER_OR_FRAMING_BAD = 1     # lines 234, 277: hdr_bad, length bounds, padding != 0
    MAC_MISMATCH = 2              # line 281: e_tag != tag_q
    EPOCH_MISMATCH = 3            # line 282: epoch != boot_epoch
    SEQUENCE_VIOLATION = 4        # line 283: seq == 0 || seq <= rx_seq
    NON_PEER_CONTROL = 5          # line 265: in_src != PEER
    RATE_LIMIT_EXCEEDED = 6       # line 237: rl[in_src] != 0
    OCCUPANCY_DROP = 7            # line 271: ps != P_FREE
    PLAIN_TILE_CONTROL_DROP = 8   # pq_noc_subsystem_p7.sv:205: control HEAD at plain tile


class IngressRejectReason(IntEnum):
    """noc_ingress_parser.sv lines 50-52."""
    NONE = 0
    SOURCE_SPOOFING = 9           # line 50: src_x != ME.x || src_y != ME.y
    INVALID_HEADER = 11           # line 50: !head_ok (type/dest/len/vc)


class MemoryFaultReason(IntEnum):
    """pq_noc_subsystem_p7.sv lines 283, 295, 296, 304."""
    NONE = 0
    UNAUTHORIZED_ACCESS = 6       # lines 283, 295, 304: requester not authorized at side-effect
    OUT_OF_WINDOW_ADDRESS = 13    # line 296: address not in 0x2T00_0000 window or unaligned


class VerifierFailReason(IntEnum):
    """pq_rot_verifier.sv lines 104-146."""
    NONE = 0
    TIMEOUT = 8                   # line 146: timeout_now
    BAD_HEADER_STATUS = 9         # line 117: hdr_status != 1
    FORMAT_OR_ABORT = 10          # line 104, 115: bad_header || count != 15 || rx_abort
    MEASUREMENT_MISMATCH = 11     # line 134: incoming measurement != approved
    TAG_MISMATCH = 12             # line 139: expected_tag != incoming tag


class NIProtocolErrorReason(str, Enum):
    """noc_network_interface_p7.sv lines 1017-1088."""
    NONE = "NONE"
    ORPHAN_BODY_OR_TAIL = "ORPHAN_BODY_OR_TAIL"
    MID_PACKET_FRAMING_VIOLATION = "MID_PACKET_FRAMING_VIOLATION"
    RESPONSE_UNMATCHED = "RESPONSE_UNMATCHED"
    CONTROL_NOT_ALLOWED = "CONTROL_NOT_ALLOWED"
    LENGTH_ERROR = "LENGTH_ERROR"


# ==============================================================================
# Security Operation Result
# ==============================================================================

@dataclass
class SecurityOperationResult:
    """
    Detailed audit outcome distinguishing structural, cryptographic, freshness,
    authorization, and execution statuses.
    """
    structurally_valid: bool = False
    cryptographically_verified: bool = False
    fresh: bool = False
    authorized: bool = False
    accepted: bool = False

    rejection_layer: Optional[str] = None     # "ingress", "l2", "gate", "ni", "memory", "verifier"
    rejection_reason_code: int = 0
    rejection_reason_name: str = "NONE"
    rejection_details: str = ""

    response_packet: Optional[P7Packet] = None


# ==============================================================================
# Replay Protection State Model
# ==============================================================================

@dataclass
class ReplayState:
    """
    Per-peer freshness and replay tracker per noc_l2_auth_p7.sv lines 281-284:
      - Checks boot epoch equality.
      - Checks sequence strictly monotonic (seq > last_accepted_seq).
      - Strictly rejects sequence 0.
      - Never advances last_accepted_seq unless all checks and MAC succeed.
    """
    expected_boot_epoch: int
    last_accepted_seq: int = 0

    def check_and_update(
        self,
        epoch: int,
        seq: int,
        mac_verified: bool,
    ) -> Tuple[bool, Optional[L2RejectReason], str]:
        """
        Executes the exact sequence of checks from noc_l2_auth_p7.sv lines 281-284:
          1. MAC check (reason 2)
          2. Epoch check (reason 3)
          3. Sequence check (reason 4)
        """
        if not mac_verified:
            return False, L2RejectReason.MAC_MISMATCH, "MAC signature mismatch"

        if epoch != self.expected_boot_epoch:
            return (
                False,
                L2RejectReason.EPOCH_MISMATCH,
                f"Boot epoch mismatch: got 0x{epoch:X}, expected 0x{self.expected_boot_epoch:X}",
            )

        if seq == 0:
            return False, L2RejectReason.SEQUENCE_VIOLATION, "Sequence number 0 is illegal"

        if seq <= self.last_accepted_seq:
            return (
                False,
                L2RejectReason.SEQUENCE_VIOLATION,
                f"Stale sequence {seq} <= last accepted {self.last_accepted_seq}",
            )

        # All passed: advance sequence number
        self.last_accepted_seq = seq
        return True, None, "Fresh and authenticated"


# ==============================================================================
# Tile Authorization State Machine
# ==============================================================================

class TileAuthorizationState:
    """
    Authoritative model for noc_attest_gate.sv:
      - RoT (Tile 4) is always authorized.
      - Tile 3 (CRYPTO) authorized ONLY after valid GRANT with status=1 from RoT.
      - Tile 3 loses authorization on REVOKE, trusted fail, or trusted timeout.
      - Tiles 0, 1, 2, and 5 are NEVER attestable and NEVER authorized (ATTESTABLE=0).
    """

    ROT_TILE_ID = 4
    CRYPTO_TILE_ID = 3

    def __init__(self) -> None:
        self.authorized: Dict[int, bool] = {
            0: False,
            1: False,
            2: False,
            3: False,
            4: True,   # RoT is always authorized (pq_noc_subsystem_p7.sv:259)
            5: False,
        }
        self.fault_count: Dict[int, int] = {i: 0 for i in range(6)}
        self.fault_reason: Dict[int, GateFaultReason] = {i: GateFaultReason.NONE for i in range(6)}

    def is_tile_authorized(self, tile_id: int) -> bool:
        if tile_id == self.ROT_TILE_ID:
            return True
        return self.authorized.get(tile_id, False)

    def process_grant(
        self,
        target_tile: int,
        issuer_tile: int,
        grant_status: int,
        authenticated: bool,
    ) -> Tuple[bool, Optional[GateFaultReason], str]:
        """
        Handles GRANT packet delivery per noc_attest_gate.sv lines 41-50.
        """
        if not authenticated:
            return False, None, "GRANT unauthenticated at L2"

        # Check ATTESTABLE
        if target_tile not in (3, 4):
            self.fault_count[target_tile] += 1
            self.fault_reason[target_tile] = GateFaultReason.NON_ATTESTABLE_TILE
            return False, GateFaultReason.NON_ATTESTABLE_TILE, f"Tile {target_tile} is not attestable"

        # Check issuer == RoT (Tile 4)
        if issuer_tile != self.ROT_TILE_ID:
            self.fault_count[target_tile] += 1
            self.fault_reason[target_tile] = GateFaultReason.INVALID_ISSUER
            return False, GateFaultReason.INVALID_ISSUER, f"GRANT issuer {issuer_tile} != RoT ({self.ROT_TILE_ID})"

        # Check grant status (control[10:7] == 1)
        if grant_status == 1:
            self.authorized[target_tile] = True
            return True, None, f"Tile {target_tile} authorized"
        else:
            self.authorized[target_tile] = False
            self.fault_count[target_tile] += 1
            self.fault_reason[target_tile] = GateFaultReason.INVALID_GRANT_STATUS
            return False, GateFaultReason.INVALID_GRANT_STATUS, f"GRANT status {grant_status} != 1"

    def process_revoke(
        self,
        target_tile: int,
        issuer_tile: int,
        authenticated: bool,
    ) -> Tuple[bool, Optional[GateFaultReason], str]:
        """
        Handles REVOKE packet delivery per noc_attest_gate.sv lines 41-50.
        """
        if not authenticated:
            return False, None, "REVOKE unauthenticated at L2"

        if target_tile not in (3, 4):
            self.fault_count[target_tile] += 1
            self.fault_reason[target_tile] = GateFaultReason.NON_ATTESTABLE_TILE
            return False, GateFaultReason.NON_ATTESTABLE_TILE, f"Tile {target_tile} is not attestable"

        if issuer_tile != self.ROT_TILE_ID:
            self.fault_count[target_tile] += 1
            self.fault_reason[target_tile] = GateFaultReason.INVALID_ISSUER
            return False, GateFaultReason.INVALID_ISSUER, f"REVOKE issuer {issuer_tile} != RoT ({self.ROT_TILE_ID})"

        if target_tile != self.ROT_TILE_ID:
            self.authorized[target_tile] = False

        return True, None, f"Tile {target_tile} authorization revoked"

    def signal_trusted_fail_or_timeout(
        self,
        tile_id: int = 3,
        is_timeout: bool = False,
    ) -> None:
        """
        Handles RoT verifier failure or timeout pulse per noc_attest_gate.sv line 39.
        """
        if tile_id != self.ROT_TILE_ID:
            self.authorized[tile_id] = False
        self.fault_count[tile_id] += 1
        self.fault_reason[tile_id] = GateFaultReason.TRUSTED_FAIL_OR_TIMEOUT


# ==============================================================================
# Transaction Identity & Slot Tracker (NI Level)
# ==============================================================================

@dataclass
class TransactionSlot:
    valid: bool = False
    dest_coord: Optional[Coord] = None
    expected_resp_type: Optional[str] = None


class TransactionTracker:
    """
    Enforces 2-slot outstanding transaction identity per noc_network_interface_p7.sv lines 845-880:
      - 1-bit transaction tag (0 or 1).
      - Matching response source and type required for slot retirement.
    """
    NUM_SLOTS = 2

    def __init__(self) -> None:
        self.slots: List[TransactionSlot] = [TransactionSlot(), TransactionSlot()]

    def allocate_slot(self, dest_coord: Coord, req_msg_type: str) -> Optional[int]:
        """Allocates free slot and records expected response."""
        resp_type_map = {
            "MEM_RD_REQ": "MEM_RD_RESP",
            "MEM_WR_REQ": "MEM_WR_RESP",
        }
        exp_resp = resp_type_map.get(req_msg_type.replace("MSG_", ""))
        if not exp_resp:
            return None

        for tag in range(self.NUM_SLOTS):
            if not self.slots[tag].valid:
                self.slots[tag].valid = True
                self.slots[tag].dest_coord = dest_coord
                self.slots[tag].expected_resp_type = exp_resp
                return tag
        return None  # Slot exhaustion

    def match_and_release(
        self,
        tag: int,
        src_coord: Coord,
        resp_msg_type: str,
    ) -> Tuple[bool, Optional[NIProtocolErrorReason], str]:
        """
        Validates response tag, destination match, and response type match.
        Releases slot on match.
        """
        if not (0 <= tag < self.NUM_SLOTS):
            return False, NIProtocolErrorReason.RESPONSE_UNMATCHED, f"Tag {tag} exceeds 2 slots"

        slot = self.slots[tag]
        if not slot.valid:
            return False, NIProtocolErrorReason.RESPONSE_UNMATCHED, f"Slot {tag} is not active"

        clean_resp = resp_msg_type.replace("MSG_", "")
        if slot.dest_coord != src_coord:
            return (
                False,
                NIProtocolErrorReason.RESPONSE_UNMATCHED,
                f"Response src {src_coord} does not match request dest {slot.dest_coord}",
            )

        if slot.expected_resp_type != clean_resp:
            return (
                False,
                NIProtocolErrorReason.RESPONSE_UNMATCHED,
                f"Response type {clean_resp} != expected {slot.expected_resp_type}",
            )

        # Matched: release slot
        slot.valid = False
        slot.dest_coord = None
        slot.expected_resp_type = None
        return True, None, f"Transaction slot {tag} retired"


# ==============================================================================
# Memory Endpoint Reference Model
# ==============================================================================

class MemoryEndpoint:
    """
    Offline 1 KiB memory stand-in modeled directly after pq_noc_subsystem_p7.sv lines 245-312:
      - Memory base address: 0x2200_0000 (Region 0x2, Tile 2, offset 0x0000..0x03FF).
      - Authorization check at Read Request HEAD.
      - Authorization recheck at Read Response HEAD offer (suppressed if revoked).
      - Authorization check at Final Write Data Word acceptance.
      - Write rejection without memory modification on revocation.
      - Response suppression on unauthorized operations.
    """

    MEMORY_BASE = 0x22000000
    MEMORY_SIZE_BYTES = 1024

    def __init__(self, auth_state: TileAuthorizationState) -> None:
        self.auth_state = auth_state
        self.memory: bytearray = bytearray(self.MEMORY_SIZE_BYTES)
        self.memory_commits: int = 0
        self.memory_last_data: int = 0
        self.mem_faults: int = 0
        self.last_fault_reason: MemoryFaultReason = MemoryFaultReason.NONE

    def check_address_legal(self, address: int) -> bool:
        """pq_noc_subsystem_p7.sv line 291."""
        return (
            (address & 0xF0000000) == 0x20000000
            and ((address >> 24) & 0x0F) == 2
            and ((address >> 10) & 0x3FFF) == 0
            and (address & 0x3) == 0
            and (0 <= (address - self.MEMORY_BASE) < self.MEMORY_SIZE_BYTES)
        )

    def handle_read_request(
        self,
        src_tile: int,
        address: int,
        tag: int,
        simulate_revocation_before_response: bool = False,
    ) -> Tuple[bool, Optional[MemoryFaultReason], Optional[int], str]:
        """
        Executes memory read with two-phase authorization check:
          Phase 1: Checked at read request HEAD (line 277).
          Phase 2: Rechecked when offering response HEAD (lines 255, 303).
        """
        # Phase 1: Check authorization at request HEAD
        if not self.auth_state.is_tile_authorized(src_tile):
            self.mem_faults += 1
            self.last_fault_reason = MemoryFaultReason.UNAUTHORIZED_ACCESS
            return False, MemoryFaultReason.UNAUTHORIZED_ACCESS, None, "Dropped at request HEAD: requester unauthorized"

        if not self.check_address_legal(address):
            self.mem_faults += 1
            self.last_fault_reason = MemoryFaultReason.OUT_OF_WINDOW_ADDRESS
            return False, MemoryFaultReason.OUT_OF_WINDOW_ADDRESS, None, "Illegal memory address window"

        # Phase 2: Check authorization when offering response HEAD
        if simulate_revocation_before_response:
            self.auth_state.authorized[src_tile] = False

        if not self.auth_state.is_tile_authorized(src_tile):
            self.mem_faults += 1
            self.last_fault_reason = MemoryFaultReason.UNAUTHORIZED_ACCESS
            return False, MemoryFaultReason.UNAUTHORIZED_ACCESS, None, "Response suppressed: revoked before response offer"

        offset = (address & 0x3FC)
        read_val = int.from_bytes(self.memory[offset : offset + 4], byteorder="little")
        return True, None, read_val, "Read successful"

    def handle_write_request(
        self,
        src_tile: int,
        address: int,
        wdata: int,
        wstrb: int,
        tag: int,
        simulate_revocation_before_final_data: bool = False,
    ) -> Tuple[bool, Optional[MemoryFaultReason], str]:
        """
        Executes memory write with authorization check at HEAD and recheck
        at final write data acceptance (lines 289-295).
        """
        # Check authorization at write request HEAD
        if not self.auth_state.is_tile_authorized(src_tile):
            self.mem_faults += 1
            self.last_fault_reason = MemoryFaultReason.UNAUTHORIZED_ACCESS
            return False, MemoryFaultReason.UNAUTHORIZED_ACCESS, "Dropped at write HEAD: requester unauthorized"

        # Authorization at side-effect point (final write data acceptance)
        if simulate_revocation_before_final_data:
            self.auth_state.authorized[src_tile] = False

        if not self.auth_state.is_tile_authorized(src_tile):
            self.mem_faults += 1
            self.last_fault_reason = MemoryFaultReason.UNAUTHORIZED_ACCESS
            return (
                False,
                MemoryFaultReason.UNAUTHORIZED_ACCESS,
                "No commit: requester revoked before final data acceptance; response suppressed",
            )

        if not self.check_address_legal(address):
            self.mem_faults += 1
            self.last_fault_reason = MemoryFaultReason.OUT_OF_WINDOW_ADDRESS
            return False, MemoryFaultReason.OUT_OF_WINDOW_ADDRESS, "Illegal memory address window"

        offset = (address & 0x3FC)
        data_bytes = bytearray(wdata.to_bytes(4, byteorder="little"))
        for b in range(4):
            if (wstrb >> b) & 1:
                self.memory[offset + b] = data_bytes[b]

        self.memory_commits += 1
        self.memory_last_data = wdata
        return True, None, "Write committed"


# ==============================================================================
# Master P7 Security Enforcement Subsystem Reference Model
# ==============================================================================

class P7SecuritySubsystem:
    """
    Comprehensive reference model executing end-to-end P7 security rules across
    Ingress, L2 Auth, Gates, NIs, Memory, and Replay Protection.
    """

    def __init__(self, boot_epoch: int = 0x1A2B3C4D5E6F708192A3) -> None:
        self.boot_epoch = boot_epoch
        self.auth_state = TileAuthorizationState()
        self.profile = ProtocolProfile.load()

        # Peer replay trackers for Tile 3 (Crypto) and Tile 4 (RoT)
        self.replay_trackers: Dict[int, ReplayState] = {
            3: ReplayState(expected_boot_epoch=boot_epoch),
            4: ReplayState(expected_boot_epoch=boot_epoch),
        }

        # NI Transaction Trackers for Tiles
        self.ni_trackers: Dict[int, TransactionTracker] = {
            i: TransactionTracker() for i in range(6)
        }

        # Memory Endpoint at Tile 2
        self.memory_endpoint = MemoryEndpoint(self.auth_state)

    def validate_control_direction(self, msg_type: str, src_tile: int, dest_tile: int) -> bool:
        """
        Enforces valid control message paths per P7 specification:
          ATTEST_CHALLENGE: 4 -> 3
          ATTEST_RESPONSE:  3 -> 4
          ATTEST_GRANT:     4 -> 3
          ATTEST_REVOKE:    4 -> 3
        """
        clean = msg_type.replace("MSG_", "")
        allowed = {
            "ATTEST_CHALLENGE": (4, 3),
            "ATTEST_RESPONSE": (3, 4),
            "ATTEST_GRANT": (4, 3),
            "ATTEST_REVOKE": (4, 3),
        }
        if clean not in allowed:
            return False
        return (src_tile, dest_tile) == allowed[clean]

    def process_ingress(self, pkt: P7Packet, injecting_port: int) -> Tuple[bool, Optional[IngressRejectReason], str]:
        """
        Checks packet at ingress parser (noc_ingress_parser.sv lines 36-39).
        """
        src_tile = pkt.src_coord.to_tile_id()
        if src_tile != injecting_port:
            return (
                False,
                IngressRejectReason.SOURCE_SPOOFING,
                f"Source spoofing: claimed tile {src_tile} != port {injecting_port}",
            )

        mesh_x = self.profile.constants.get("MESH_X", 3)
        mesh_y = self.profile.constants.get("MESH_Y", 2)
        if not (0 <= pkt.dest_coord.x < mesh_x and 0 <= pkt.dest_coord.y < mesh_y):
            return (
                False,
                IngressRejectReason.INVALID_HEADER,
                f"Destination coord ({pkt.dest_coord.x},{pkt.dest_coord.y}) out of mesh bounds",
            )

        return True, None, "Ingress passed"

    def process_wire_packet(
        self,
        pkt: P7Packet,
        injecting_port: int,
        mac_cryptographically_verified: bool = False,
    ) -> SecurityOperationResult:
        """
        End-to-end evaluation of packet arriving over the link.
        """
        res = SecurityOperationResult()

        # 1. Ingress Parser
        in_ok, in_reason, in_msg = self.process_ingress(pkt, injecting_port)
        if not in_ok:
            res.rejection_layer = "ingress"
            res.rejection_reason_code = int(in_reason)
            res.rejection_reason_name = in_reason.name
            res.rejection_details = in_msg
            return res

        src_tile = pkt.src_coord.to_tile_id()
        dest_tile = pkt.dest_coord.to_tile_id()

        # 2. Control Traffic Direction & Plain Tile Refusal
        if pkt.is_control:
            # Rejection on plain tiles (reasons 8 / CONTROL_NOT_ALLOWED)
            if dest_tile not in (3, 4):
                res.rejection_layer = "ni"
                res.rejection_reason_code = int(L2RejectReason.PLAIN_TILE_CONTROL_DROP)
                res.rejection_reason_name = "PLAIN_TILE_CONTROL_DROP"
                res.rejection_details = f"Control message '{pkt.short_name}' refused at non-attested tile {dest_tile}"
                return res

            if not self.validate_control_direction(pkt.short_name, src_tile, dest_tile):
                res.rejection_layer = "l2"
                res.rejection_reason_code = int(L2RejectReason.NON_PEER_CONTROL)
                res.rejection_reason_name = "NON_PEER_CONTROL"
                res.rejection_details = f"Illegal control direction from tile {src_tile} to {dest_tile}"
                return res

            # 3. L2 Auth Replay & Freshness (at receiver dest_tile)
            if pkt.freshness is None:
                res.rejection_layer = "l2"
                res.rejection_reason_code = int(L2RejectReason.HEADER_OR_FRAMING_BAD)
                res.rejection_reason_name = "HEADER_OR_FRAMING_BAD"
                res.rejection_details = "Missing freshness metadata on control packet"
                return res

            tracker = self.replay_trackers[dest_tile]
            fresh_ok, l2_reason, l2_msg = tracker.check_and_update(
                epoch=pkt.freshness.epoch,
                seq=pkt.freshness.seq,
                mac_verified=mac_cryptographically_verified,
            )
            res.cryptographically_verified = mac_cryptographically_verified
            res.fresh = fresh_ok

            if not fresh_ok:
                res.rejection_layer = "l2"
                assert l2_reason is not None
                res.rejection_reason_code = int(l2_reason)
                res.rejection_reason_name = l2_reason.name
                res.rejection_details = l2_msg
                return res

            # 4. Attestation Gate (for GRANT / REVOKE at tile 3)
            if pkt.short_name in ("ATTEST_GRANT", "ATTEST_REVOKE"):
                status_nibble = (pkt.control_field >> 7) & 0xF
                if pkt.short_name == "ATTEST_GRANT":
                    g_ok, g_reason, g_msg = self.auth_state.process_grant(
                        target_tile=dest_tile,
                        issuer_tile=src_tile,
                        grant_status=status_nibble,
                        authenticated=mac_cryptographically_verified and fresh_ok,
                    )
                else:
                    g_ok, g_reason, g_msg = self.auth_state.process_revoke(
                        target_tile=dest_tile,
                        issuer_tile=src_tile,
                        authenticated=mac_cryptographically_verified and fresh_ok,
                    )

                if not g_ok:
                    res.rejection_layer = "gate"
                    assert g_reason is not None
                    res.rejection_reason_code = int(g_reason)
                    res.rejection_reason_name = g_reason.name
                    res.rejection_details = g_msg
                    return res

        else:
            # Data-plane message: Check authorization of source
            src_auth = self.auth_state.is_tile_authorized(src_tile)
            res.authorized = src_auth
            if not src_auth:
                res.rejection_layer = "gate"
                res.rejection_reason_code = int(GateFaultReason.UNAUTHORIZED_ACCESS)
                res.rejection_reason_name = "UNAUTHORIZED_ACCESS"
                res.rejection_details = f"Data request from unauthorized tile {src_tile}"
                return res

        # All checks passed
        res.structurally_valid = True
        res.authorized = self.auth_state.is_tile_authorized(src_tile)
        res.accepted = True
        return res

