#!/usr/bin/env python3
"""
PQ-Attest P7 Verification - I-9 Reference Model Extension
=========================================================

This module implements the reference model for the signed I-9 integration
contract (M-F1 revision 8), covering:
  1. NI Slot Lifecycle and Timeout:
     - Two outstanding transaction slots (N_OUTSTANDING = 2) with 1-bit tags.
     - Lowest-numbered slot allocation policy.
     - Slot timeout duration: NI_SLOT_TIMEOUT = 600 cycles.
     - Slot release on timeout permitting immediate re-allocation.
     - Late response rejection: expired tag responses are dropped and never delivered.
     - Stale response rejection: responses for superseded/reused transactions are dropped.
  2. app_rx Memory-Response Export:
     - Memory responses (MEM_RD_RESP, MEM_WR_RESP) are exported strictly to CPU tiles 0 and 3.
     - Tiles 1, 2, 4, 5 are unauthorized for app_rx memory-response export.
     - Non-memory response packets are excluded from the memory-response export path.
  3. Tile-2 BRAM 16 KB Window:
     - Base address: 0x2200_0000.
     - Window size: 16 KB (16,384 bytes, 4,096 32-bit words).
     - Valid aligned range: 0x2200_0000 to 0x2200_3FFC.
     - Strictly exclusive upper boundary: 0x2200_3FFC accepted, 0x2200_4000 rejected.
     - 4-byte alignment check (addr[1:0] == 2'b00).
  4. BRAM Byte-Lane Write-Enables:
     - 32-bit data width, 4 byte lanes controlled by wstrb[3:0].
     - Byte lane i corresponds to bits [8*i+7 : 8*i].
     - Disabled byte lanes strictly preserve prior memory contents.
  5. Python-Model Mutation Analysis:
     - Explicit mutation flags reflecting the 5 negative controls from tb_i9_integ
       and Section 9 requirements.

Classification:
  Python reference-model extension and Python-model mutation analysis for the
  signed I-9 integration contract. Existing Kalash I-9 XSim evidence is used as
  behavioral reference where applicable. This work does not constitute new RTL
  simulation, formal proof or hardware validation.
"""

from __future__ import annotations

import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from dataclasses import dataclass, field
from enum import Enum, IntEnum
from typing import Any, Dict, List, Optional, Set, Tuple


# ==============================================================================
# Protocol & Hardware Constants
# ==============================================================================

N_OUTSTANDING: int = 2
TXN_TAG_WIDTH: int = 1
DEFAULT_NI_SLOT_TIMEOUT: int = 600
DEFAULT_VERIFIER_TIMEOUT: int = 3000

TILE_2_BRAM_BASE: int = 0x2200_0000
TILE_2_BRAM_SIZE_BYTES: int = 16 * 1024  # 16 KB = 16384 bytes
TILE_2_BRAM_LIMIT: int = TILE_2_BRAM_BASE + TILE_2_BRAM_SIZE_BYTES  # 0x2200_4000 (exclusive)
TILE_2_BRAM_LAST_ALIGNED: int = TILE_2_BRAM_LIMIT - 4              # 0x2200_3FFC (inclusive)

# Authorized destination CPU tiles for app_rx memory-response export
AUTHORIZED_APP_RX_CPU_TILES: Set[int] = {0, 3}

# Protocol Message Types
MSG_MEM_RD_REQ: int = 0
MSG_MEM_RD_RESP: int = 1
MSG_MEM_WR_REQ: int = 2
MSG_MEM_WR_RESP: int = 3
MSG_ATTEST_CHALLENGE: int = 4
MSG_ATTEST_RESPONSE: int = 5
MSG_ATTEST_GRANT: int = 6
MSG_ATTEST_REVOKE: int = 7

MEMORY_RESPONSE_TYPES: Set[int] = {MSG_MEM_RD_RESP, MSG_MEM_WR_RESP}


# ==============================================================================
# Enums for States, Classifications and Decisions
# ==============================================================================

class SlotState(str, Enum):
    """Lifecycle state of an NI transaction slot."""
    FREE = "FREE"
    OCCUPIED = "OCCUPIED"
    TIMED_OUT = "TIMED_OUT"
    RELEASED = "RELEASED"


class ResponseClassification(str, Enum):
    """Deterministic classification of incoming response flits."""
    VALID_MATCH = "VALID_MATCH"
    LATE_TIMED_OUT = "LATE_TIMED_OUT"
    STALE_REUSED = "STALE_REUSED"
    UNMATCHED_ALREADY_COMPLETED = "UNMATCHED_ALREADY_COMPLETED"
    INVALID_TAG = "INVALID_TAG"
    MISMATCHED_SRC = "MISMATCHED_SRC"
    MISMATCHED_TYPE = "MISMATCHED_TYPE"
    NON_MEMORY_TYPE = "NON_MEMORY_TYPE"


class DeliveryDecision(str, Enum):
    """Final delivery verdict for the application interface."""
    DELIVER = "DELIVER"
    DROP = "DROP"


class I9DropReason(str, Enum):
    """Exhaustive diagnostic reason codes for dropped responses or rejected accesses."""
    NONE = "NONE"
    SLOT_TIMED_OUT = "SLOT_TIMED_OUT"
    STALE_TAG_REUSED = "STALE_TAG_REUSED"
    ALREADY_COMPLETED = "ALREADY_COMPLETED"
    INVALID_TAG_VALUE = "INVALID_TAG_VALUE"
    SRC_DEST_MISMATCH = "SRC_DEST_MISMATCH"
    MSG_TYPE_MISMATCH = "MSG_TYPE_MISMATCH"
    NON_MEMORY_RESPONSE = "NON_MEMORY_RESPONSE"
    UNAUTHORIZED_APP_RX_DESTINATION = "UNAUTHORIZED_APP_RX_DESTINATION"
    BRAM_OUT_OF_BOUNDS = "BRAM_OUT_OF_BOUNDS"
    BRAM_MISALIGNED = "BRAM_MISALIGNED"
    BRAM_NO_BYTE_ENABLES = "BRAM_NO_BYTE_ENABLES"


# ==============================================================================
# Data Structures
# ==============================================================================

@dataclass
class TransactionRecord:
    """Represents a single initiated memory transaction."""
    txn_id: int
    slot_id: int
    tag: int
    dest_x: int
    dest_y: int
    dest_tile: int
    req_type: int
    expected_resp_type: int
    alloc_cycle: int
    timeout_cycle: int
    completed: bool = False
    timed_out: bool = False
    completed_cycle: Optional[int] = None


@dataclass
class ResponseVerdict:
    """Detailed verdict produced for every received response."""
    tag: int
    slot_id: Optional[int]
    matching_txn_id: Optional[int]
    classification: ResponseClassification
    delivery: DeliveryDecision
    drop_reason: I9DropReason
    slot_state_after: SlotState
    exported_to_app_rx: bool
    source_tile: Optional[int] = None
    dest_tile: Optional[int] = None
    msg_type: Optional[int] = None


@dataclass
class BRAMAccessResult:
    """Outcome of a Tile-2 BRAM read or write access."""
    accepted: bool
    addr: int
    is_write: bool
    wstrb: int
    wdata: int
    rdata_before: int
    rdata_after: int
    drop_reason: I9DropReason
    modified_bytes: List[int] = field(default_factory=list)


# ==============================================================================
# 1. NI Slot Lifecycle and Timeout Engine
# ==============================================================================

class NITransactionTable:
    """
    Reference model for the NI transaction slot table, matching
    noc_network_interface_p7.sv and the I-9 timeout extension.
    """

    def __init__(
        self,
        num_slots: int = N_OUTSTANDING,
        slot_timeout: int = DEFAULT_NI_SLOT_TIMEOUT,
        # Mutation injection switches:
        mut_no_timeout: bool = False,
        mut_late_deliver: bool = False,
        mut_stale_deliver: bool = False,
    ) -> None:
        self.num_slots = num_slots
        self.slot_timeout = slot_timeout
        self.mut_no_timeout = mut_no_timeout
        self.mut_late_deliver = mut_late_deliver
        self.mut_stale_deliver = mut_stale_deliver

        self.current_cycle: int = 0
        self._next_txn_id: int = 1

        # Current active transactions indexed by slot_id
        self.slots: List[Optional[TransactionRecord]] = [None] * self.num_slots
        # History of all initiated transactions for audit and stale response detection
        self.txn_history: Dict[int, TransactionRecord] = {}
        # Most recent transaction allocated for each tag (used for stale-tag disambiguation)
        self.last_tag_txn: Dict[int, int] = {}
        # Set of transaction IDs that timed out
        self.timed_out_txns: Set[int] = set()

    @property
    def slots_occupied(self) -> int:
        """Count of currently occupied active slots."""
        return sum(1 for s in self.slots if s is not None)

    @property
    def has_available_slot(self) -> bool:
        """Whether a slot can currently be allocated."""
        return self.slots_occupied < self.num_slots

    def get_lowest_free_slot(self) -> Optional[int]:
        """Finds lowest-numbered free slot (RTL priority encoder)."""
        for i in range(self.num_slots):
            if self.slots[i] is None:
                return i
        return None

    def allocate(
        self,
        dest_x: int,
        dest_y: int,
        dest_tile: int,
        req_type: int = MSG_MEM_RD_REQ,
        cycle: Optional[int] = None,
    ) -> Optional[TransactionRecord]:
        """
        Allocates the lowest available slot for a new request.
        Returns None if all slots are occupied.
        """
        if cycle is not None:
            self.advance_time(cycle - self.current_cycle)

        slot_id = self.get_lowest_free_slot()
        if slot_id is None:
            return None

        expected_resp = MSG_MEM_RD_RESP if req_type == MSG_MEM_RD_REQ else MSG_MEM_WR_RESP
        txn = TransactionRecord(
            txn_id=self._next_txn_id,
            slot_id=slot_id,
            tag=slot_id,  # 1-bit tag matches slot_id in RTL (0 or 1)
            dest_x=dest_x,
            dest_y=dest_y,
            dest_tile=dest_tile,
            req_type=req_type,
            expected_resp_type=expected_resp,
            alloc_cycle=self.current_cycle,
            timeout_cycle=self.current_cycle + self.slot_timeout,
        )

        self._next_txn_id += 1
        self.slots[slot_id] = txn
        self.txn_history[txn.txn_id] = txn
        self.last_tag_txn[txn.tag] = txn.txn_id
        return txn

    def advance_time(self, cycles: int = 1) -> List[TransactionRecord]:
        """
        Advances internal time and evaluates slot timeouts.
        Returns list of newly timed-out transactions.
        """
        if cycles <= 0:
            return []

        timed_out: List[TransactionRecord] = []
        target_cycle = self.current_cycle + cycles

        # Step cycle-by-cycle or jump to earliest expiration
        for slot_id in range(self.num_slots):
            txn = self.slots[slot_id]
            if txn is not None and not txn.timed_out:
                if target_cycle >= txn.timeout_cycle:
                    if not self.mut_no_timeout:
                        # Normal behavior: timeout releases the slot
                        txn.timed_out = True
                        self.timed_out_txns.add(txn.txn_id)
                        timed_out.append(txn)
                        self.slots[slot_id] = None
                    else:
                        # Mutant: timeout does not release the slot!
                        pass

        self.current_cycle = target_cycle
        return timed_out

    def process_response(
        self,
        tag: int,
        src_x: int,
        src_y: int,
        msg_type: int,
        dest_tile: int,
        specific_txn_id: Optional[int] = None,
        cycle: Optional[int] = None,
    ) -> ResponseVerdict:
        """
        Processes an arriving response flit and produces a deterministic verdict.
        """
        if cycle is not None:
            self.advance_time(cycle - self.current_cycle)

        # 1. Validate tag width
        if tag < 0 or tag >= self.num_slots:
            return ResponseVerdict(
                tag=tag,
                slot_id=None,
                matching_txn_id=None,
                classification=ResponseClassification.INVALID_TAG,
                delivery=DeliveryDecision.DROP,
                drop_reason=I9DropReason.INVALID_TAG_VALUE,
                slot_state_after=SlotState.FREE,
                exported_to_app_rx=False,
                dest_tile=dest_tile,
                msg_type=msg_type,
            )

        # 2. Check message type qualification
        if msg_type not in MEMORY_RESPONSE_TYPES:
            active_slot = self.slots[tag]
            return ResponseVerdict(
                tag=tag,
                slot_id=tag,
                matching_txn_id=active_slot.txn_id if active_slot else None,
                classification=ResponseClassification.NON_MEMORY_TYPE,
                delivery=DeliveryDecision.DROP,
                drop_reason=I9DropReason.NON_MEMORY_RESPONSE,
                slot_state_after=SlotState.OCCUPIED if active_slot else SlotState.FREE,
                exported_to_app_rx=False,
                dest_tile=dest_tile,
                msg_type=msg_type,
            )

        active_slot = self.slots[tag]

        # 3. Handle case where active slot exists
        if active_slot is not None:
            # Check source coordinates and expected response type
            src_match = (src_x == active_slot.dest_x) and (src_y == active_slot.dest_y)
            type_match = (msg_type == active_slot.expected_resp_type)

            if not src_match:
                return ResponseVerdict(
                    tag=tag,
                    slot_id=tag,
                    matching_txn_id=active_slot.txn_id,
                    classification=ResponseClassification.MISMATCHED_SRC,
                    delivery=DeliveryDecision.DROP,
                    drop_reason=I9DropReason.SRC_DEST_MISMATCH,
                    slot_state_after=SlotState.OCCUPIED,
                    exported_to_app_rx=False,
                    dest_tile=dest_tile,
                    msg_type=msg_type,
                )

            if not type_match:
                return ResponseVerdict(
                    tag=tag,
                    slot_id=tag,
                    matching_txn_id=active_slot.txn_id,
                    classification=ResponseClassification.MISMATCHED_TYPE,
                    delivery=DeliveryDecision.DROP,
                    drop_reason=I9DropReason.MSG_TYPE_MISMATCH,
                    slot_state_after=SlotState.OCCUPIED,
                    exported_to_app_rx=False,
                    dest_tile=dest_tile,
                    msg_type=msg_type,
                )

            # Check if this response belongs to an OLD superseded transaction on the same tag
            if specific_txn_id is not None and specific_txn_id != active_slot.txn_id:
                # Arriving response is from an old transaction whose tag was reused!
                if not self.mut_stale_deliver:
                    # Normal: stale response is dropped, active transaction NOT completed
                    return ResponseVerdict(
                        tag=tag,
                        slot_id=tag,
                        matching_txn_id=specific_txn_id,
                        classification=ResponseClassification.STALE_REUSED,
                        delivery=DeliveryDecision.DROP,
                        drop_reason=I9DropReason.STALE_TAG_REUSED,
                        slot_state_after=SlotState.OCCUPIED,
                        exported_to_app_rx=False,
                        dest_tile=dest_tile,
                        msg_type=msg_type,
                    )
                else:
                    # Mutant: stale response completes active transaction incorrectly!
                    active_slot.completed = True
                    active_slot.completed_cycle = self.current_cycle
                    self.slots[tag] = None
                    return ResponseVerdict(
                        tag=tag,
                        slot_id=tag,
                        matching_txn_id=active_slot.txn_id,
                        classification=ResponseClassification.VALID_MATCH,
                        delivery=DeliveryDecision.DELIVER,
                        drop_reason=I9DropReason.NONE,
                        slot_state_after=SlotState.FREE,
                        exported_to_app_rx=True,
                        dest_tile=dest_tile,
                        msg_type=msg_type,
                    )

            # Normal active matching response
            active_slot.completed = True
            active_slot.completed_cycle = self.current_cycle
            self.slots[tag] = None  # Release slot

            # Check app_rx destination permission
            export_ok = dest_tile in AUTHORIZED_APP_RX_CPU_TILES
            if not export_ok:
                return ResponseVerdict(
                    tag=tag,
                    slot_id=tag,
                    matching_txn_id=active_slot.txn_id,
                    classification=ResponseClassification.VALID_MATCH,
                    delivery=DeliveryDecision.DROP,
                    drop_reason=I9DropReason.UNAUTHORIZED_APP_RX_DESTINATION,
                    slot_state_after=SlotState.FREE,
                    exported_to_app_rx=False,
                    dest_tile=dest_tile,
                    msg_type=msg_type,
                )

            return ResponseVerdict(
                tag=tag,
                slot_id=tag,
                matching_txn_id=active_slot.txn_id,
                classification=ResponseClassification.VALID_MATCH,
                delivery=DeliveryDecision.DELIVER,
                drop_reason=I9DropReason.NONE,
                slot_state_after=SlotState.FREE,
                exported_to_app_rx=True,
                dest_tile=dest_tile,
                msg_type=msg_type,
            )

        # 4. Active slot is None: response arrived for an empty slot (late or completed)
        # Check historical transactions for this tag
        last_id = self.last_tag_txn.get(tag)
        is_timed_out = last_id in self.timed_out_txns if last_id else False

        if is_timed_out:
            classification = ResponseClassification.LATE_TIMED_OUT
            drop_reason = I9DropReason.SLOT_TIMED_OUT
        else:
            classification = ResponseClassification.UNMATCHED_ALREADY_COMPLETED
            drop_reason = I9DropReason.ALREADY_COMPLETED

        if self.mut_late_deliver:
            # Mutant: delivered to application even though timed out!
            return ResponseVerdict(
                tag=tag,
                slot_id=tag,
                matching_txn_id=last_id,
                classification=classification,
                delivery=DeliveryDecision.DELIVER,
                drop_reason=I9DropReason.NONE,
                slot_state_after=SlotState.FREE,
                exported_to_app_rx=True,
                dest_tile=dest_tile,
                msg_type=msg_type,
            )

        return ResponseVerdict(
            tag=tag,
            slot_id=tag,
            matching_txn_id=last_id,
            classification=classification,
            delivery=DeliveryDecision.DROP,
            drop_reason=drop_reason,
            slot_state_after=SlotState.FREE,
            exported_to_app_rx=False,
            dest_tile=dest_tile,
            msg_type=msg_type,
        )


# ==============================================================================
# 2. app_rx Export Policy Model
# ==============================================================================

class AppRxExportPolicy:
    """
    Validates export eligibility through app_rx.
    Memory responses are strictly exported to CPU tiles 0 and 3 only.
    """

    def __init__(self, mut_rx_all: bool = False) -> None:
        self.mut_rx_all = mut_rx_all

    def is_export_eligible(self, dest_tile: int, msg_type: int) -> Tuple[bool, I9DropReason]:
        """
        Determines if a packet is eligible for app_rx delivery.
        """
        if msg_type not in MEMORY_RESPONSE_TYPES:
            return False, I9DropReason.NON_MEMORY_RESPONSE

        if self.mut_rx_all:
            # Mutant: all tiles are permitted!
            return True, I9DropReason.NONE

        if dest_tile in AUTHORIZED_APP_RX_CPU_TILES:
            return True, I9DropReason.NONE

        return False, I9DropReason.UNAUTHORIZED_APP_RX_DESTINATION


# ==============================================================================
# 3. Tile-2 BRAM 16 KB Window & Byte-Lane Model
# ==============================================================================

class Tile2BRAMModel:
    """
    Reference model for Tile-2 BRAM interface, enforcing the 16 KB window
    (0x2200_0000 to 0x2200_3FFF) and 4 byte-lane write strobes.
    """

    def __init__(
        self,
        base_addr: int = TILE_2_BRAM_BASE,
        size_bytes: int = TILE_2_BRAM_SIZE_BYTES,
        # Mutation injection switches:
        mut_window_inclusive: bool = False,
        mut_window_1k: bool = False,
        mut_bram_lanes: bool = False,
        mut_disabled_lanes_overwrite: bool = False,
    ) -> None:
        self.base_addr = base_addr
        self.size_bytes = size_bytes
        self.mut_window_inclusive = mut_window_inclusive
        self.mut_window_1k = mut_window_1k
        self.mut_bram_lanes = mut_bram_lanes
        self.mut_disabled_lanes_overwrite = mut_disabled_lanes_overwrite

        # 32-bit word store indexed by word offset (0 to 4095)
        self.num_words = self.size_bytes // 4
        self.words: Dict[int, int] = {}

    @property
    def upper_limit(self) -> int:
        """Effective upper boundary."""
        if self.mut_window_1k:
            return self.base_addr + 1024  # 1 KB mutant
        return self.base_addr + self.size_bytes

    def is_address_in_window(self, addr: int) -> bool:
        """Evaluates whether address is within valid window."""
        if addr < self.base_addr:
            return False

        if self.mut_window_inclusive:
            # Mutant: boundary check uses <= instead of <
            return addr <= self.upper_limit

        # Normal: strictly exclusive of upper boundary
        return addr < self.upper_limit

    def read_word(self, addr: int) -> BRAMAccessResult:
        """Executes a 32-bit word read."""
        if (addr & 0x3) != 0:
            return BRAMAccessResult(
                accepted=False,
                addr=addr,
                is_write=False,
                wstrb=0,
                wdata=0,
                rdata_before=0,
                rdata_after=0,
                drop_reason=I9DropReason.BRAM_MISALIGNED,
            )

        if not self.is_address_in_window(addr):
            return BRAMAccessResult(
                accepted=False,
                addr=addr,
                is_write=False,
                wstrb=0,
                wdata=0,
                rdata_before=0,
                rdata_after=0,
                drop_reason=I9DropReason.BRAM_OUT_OF_BOUNDS,
            )

        word_idx = (addr - self.base_addr) >> 2
        val = self.words.get(word_idx, 0)
        return BRAMAccessResult(
            accepted=True,
            addr=addr,
            is_write=False,
            wstrb=0,
            wdata=0,
            rdata_before=val,
            rdata_after=val,
            drop_reason=I9DropReason.NONE,
        )

    def write_word(self, addr: int, wdata: int, wstrb: int) -> BRAMAccessResult:
        """Executes a word write with byte-lane enables."""
        if (addr & 0x3) != 0:
            return BRAMAccessResult(
                accepted=False,
                addr=addr,
                is_write=True,
                wstrb=wstrb,
                wdata=wdata,
                rdata_before=0,
                rdata_after=0,
                drop_reason=I9DropReason.BRAM_MISALIGNED,
            )

        if not self.is_address_in_window(addr):
            return BRAMAccessResult(
                accepted=False,
                addr=addr,
                is_write=True,
                wstrb=wstrb,
                wdata=wdata,
                rdata_before=0,
                rdata_after=0,
                drop_reason=I9DropReason.BRAM_OUT_OF_BOUNDS,
            )

        wstrb_effective = wstrb & 0xF
        word_idx = (addr - self.base_addr) >> 2
        old_val = self.words.get(word_idx, 0)

        if self.mut_bram_lanes:
            # Mutant: ignores wstrb and overwrites entire 32-bit word
            new_val = wdata & 0xFFFF_FFFF
            modified = [0, 1, 2, 3]
        else:
            new_val = old_val
            modified = []
            for lane in range(4):
                mask = 0xFF << (lane * 8)
                if (wstrb_effective & (1 << lane)) != 0:
                    byte_val = (wdata >> (lane * 8)) & 0xFF
                    new_val = (new_val & ~mask) | (byte_val << (lane * 8))
                    modified.append(lane)
                elif self.mut_disabled_lanes_overwrite:
                    # Mutant: disabled lanes zeroed out!
                    new_val = new_val & ~mask

        self.words[word_idx] = new_val
        return BRAMAccessResult(
            accepted=True,
            addr=addr,
            is_write=True,
            wstrb=wstrb_effective,
            wdata=wdata,
            rdata_before=old_val,
            rdata_after=new_val,
            drop_reason=I9DropReason.NONE,
            modified_bytes=modified,
        )


# ==============================================================================
# 4. Integrated I-9 Reference Model
# ==============================================================================

class P7I9IntegratedModel:
    """
    Unified high-level integration model binding transaction slots,
    timeout handling, app_rx export policy, and BRAM window verification.
    """

    def __init__(
        self,
        slot_timeout: int = DEFAULT_NI_SLOT_TIMEOUT,
        # Mutants:
        mut_no_timeout: bool = False,
        mut_late_deliver: bool = False,
        mut_stale_deliver: bool = False,
        mut_rx_all: bool = False,
        mut_window_inclusive: bool = False,
        mut_window_1k: bool = False,
        mut_bram_lanes: bool = False,
        mut_disabled_lanes_overwrite: bool = False,
    ) -> None:
        self.ni = NITransactionTable(
            slot_timeout=slot_timeout,
            mut_no_timeout=mut_no_timeout,
            mut_late_deliver=mut_late_deliver,
            mut_stale_deliver=mut_stale_deliver,
        )
        self.app_rx = AppRxExportPolicy(mut_rx_all=mut_rx_all)
        self.bram = Tile2BRAMModel(
            mut_window_inclusive=mut_window_inclusive,
            mut_window_1k=mut_window_1k,
            mut_bram_lanes=mut_bram_lanes,
            mut_disabled_lanes_overwrite=mut_disabled_lanes_overwrite,
        )

    def advance_time(self, cycles: int = 1) -> List[TransactionRecord]:
        return self.ni.advance_time(cycles)

    def send_memory_request(
        self,
        dest_x: int,
        dest_y: int,
        dest_tile: int,
        req_type: int = MSG_MEM_RD_REQ,
        cycle: Optional[int] = None,
    ) -> Optional[TransactionRecord]:
        return self.ni.allocate(dest_x, dest_y, dest_tile, req_type, cycle)

    def receive_memory_response(
        self,
        tag: int,
        src_x: int,
        src_y: int,
        msg_type: int,
        dest_tile: int,
        specific_txn_id: Optional[int] = None,
        cycle: Optional[int] = None,
    ) -> ResponseVerdict:
        verdict = self.ni.process_response(
            tag=tag,
            src_x=src_x,
            src_y=src_y,
            msg_type=msg_type,
            dest_tile=dest_tile,
            specific_txn_id=specific_txn_id,
            cycle=cycle,
        )
        # Verify app_rx export policy
        if verdict.delivery == DeliveryDecision.DELIVER:
            eligible, reason = self.app_rx.is_export_eligible(dest_tile, msg_type)
            if not eligible:
                verdict.delivery = DeliveryDecision.DROP
                verdict.drop_reason = reason
                verdict.exported_to_app_rx = False

        return verdict

    def access_tile2_bram(
        self,
        addr: int,
        is_write: bool = False,
        wdata: int = 0,
        wstrb: int = 0,
    ) -> BRAMAccessResult:
        if is_write:
            return self.bram.write_word(addr, wdata, wstrb)
        return self.bram.read_word(addr)


# ==============================================================================
# 5. Mutation Analysis Runner
# ==============================================================================

@dataclass
class I9MutantDefinition:
    mutant_id: str
    negative_control_job: Optional[str]
    mutant_symbol: str
    requirement: str
    description: str
    expected_oracle: str
    kill_test_name: str


I9_MUTANT_DEFINITIONS: List[I9MutantDefinition] = [
    I9MutantDefinition(
        mutant_id="I9-MUT-01",
        negative_control_job="i9_mut_no_timeout",
        mutant_symbol="i9n_no_timeout",
        requirement="NI Slot Timeout Release (M-F1 rev 8 §11)",
        description="Slot is not freed when NI_SLOT_TIMEOUT expires",
        expected_oracle="^[FAIL] I9_SLOT_RECOVER",
        kill_test_name="test_kill_mut_no_timeout",
    ),
    I9MutantDefinition(
        mutant_id="I9-MUT-02",
        negative_control_job=None,
        mutant_symbol="i9m_late_deliver",
        requirement="Late Response Rejection (M-F1 rev 8 §11)",
        description="Late response arriving after timeout is delivered to application",
        expected_oracle="^[FAIL] I9_LATE_DROPPED",
        kill_test_name="test_kill_mut_late_deliver",
    ),
    I9MutantDefinition(
        mutant_id="I9-MUT-03",
        negative_control_job="i9_mut_stale_deliver",
        mutant_symbol="i9n_stale_deliver",
        requirement="Stale Tag Response Rejection (M-F1 rev 8 §11)",
        description="Response for superseded transaction completes newer transaction on reused tag",
        expected_oracle="^[FAIL] I9_STALE_DROPPED",
        kill_test_name="test_kill_mut_stale_deliver",
    ),
    I9MutantDefinition(
        mutant_id="I9-MUT-04",
        negative_control_job="i9_mut_rx_all",
        mutant_symbol="i9s_rx_all",
        requirement="app_rx Restricted to CPU Tiles 0 and 3 (M-F1 rev 8 §11)",
        description="app_rx exports memory responses to all tiles (including tile 1, 2, 4, 5)",
        expected_oracle="^[FAIL] I9_RX_ACCOUNTED",
        kill_test_name="test_kill_mut_rx_all",
    ),
    I9MutantDefinition(
        mutant_id="I9-MUT-05",
        negative_control_job=None,
        mutant_symbol="i9m_window_inclusive",
        requirement="16 KB Window Upper Limit Strict Exclusion (0x2200_4000 rejected)",
        description="BRAM upper boundary is incorrectly inclusive (accepts 0x2200_4000)",
        expected_oracle="^[FAIL] I9_WINDOW_LIMIT_STRICT",
        kill_test_name="test_kill_mut_window_inclusive",
    ),
    I9MutantDefinition(
        mutant_id="I9-MUT-06",
        negative_control_job="i9_mut_window_1k",
        mutant_symbol="i9s_window_1k",
        requirement="16 KB BRAM Window Capacity (0x2200_3FFC accepted)",
        description="BRAM window is incorrectly restricted to 1 KB (rejects 0x2200_3FFC)",
        expected_oracle="^[FAIL] I9_WINDOW_TOP_OK",
        kill_test_name="test_kill_mut_window_1k",
    ),
    I9MutantDefinition(
        mutant_id="I9-MUT-07",
        negative_control_job="i9_mut_bram_lanes",
        mutant_symbol="i9s_bram_lanes",
        requirement="BRAM Byte-Lane Write Enable Fidelity",
        description="Byte-lane enables ignored; all 4 bytes written on any write",
        expected_oracle="^[FAIL] I9_BYTE_LANES",
        kill_test_name="test_kill_mut_bram_lanes",
    ),
    I9MutantDefinition(
        mutant_id="I9-MUT-08",
        negative_control_job=None,
        mutant_symbol="i9m_disabled_lanes_overwrite",
        requirement="Unselected Byte-Lane Preservation",
        description="Disabled byte lanes overwrite pre-existing memory with zero",
        expected_oracle="^[FAIL] I9_LANE_PRESERVE",
        kill_test_name="test_kill_mut_disabled_lanes_overwrite",
    ),
]


def execute_i9_mutation_analysis() -> Dict[str, Any]:
    """
    Executes all 8 Python-model mutants and records kill results and assertions.
    """
    results: List[Dict[str, Any]] = []

    # 1. MUT-01: No timeout release
    m1 = NITransactionTable(slot_timeout=600, mut_no_timeout=True)
    m1.allocate(dest_x=2, dest_y=0, dest_tile=2, cycle=0)
    m1.advance_time(600)
    # Detection: in normal model slot 0 is None. Mutant keeps slot 0 occupied.
    mut1_killed = (m1.slots[0] is not None)
    results.append({
        "mutant_id": "I9-MUT-01",
        "name": "No Timeout Release",
        "negative_control_job": "i9_mut_no_timeout",
        "oracle": "^[FAIL] I9_SLOT_RECOVER",
        "status": "KILLED" if mut1_killed else "SURVIVED",
        "kill_diagnostic": "Assertion failed: slot 0 remained occupied after 600 cycles (slots[0] is not None).",
    })

    # 2. MUT-02: Late deliver
    m2 = NITransactionTable(slot_timeout=600, mut_late_deliver=True)
    m2.allocate(dest_x=2, dest_y=0, dest_tile=2, cycle=0)
    m2.advance_time(601)
    v2 = m2.process_response(tag=0, src_x=2, src_y=0, msg_type=MSG_MEM_RD_RESP, dest_tile=0)
    mut2_killed = (v2.delivery == DeliveryDecision.DELIVER)
    results.append({
        "mutant_id": "I9-MUT-02",
        "name": "Late Response Delivered",
        "negative_control_job": None,
        "oracle": "^[FAIL] I9_LATE_DROPPED",
        "status": "KILLED" if mut2_killed else "SURVIVED",
        "kill_diagnostic": "Assertion failed: response after timeout returned delivery=DELIVER instead of DROP.",
    })

    # 3. MUT-03: Stale deliver
    m3 = NITransactionTable(slot_timeout=600, mut_stale_deliver=True)
    t0 = m3.allocate(dest_x=2, dest_y=0, dest_tile=2, cycle=0)
    m3.advance_time(600)
    t1 = m3.allocate(dest_x=2, dest_y=0, dest_tile=2, cycle=600)
    v3 = m3.process_response(tag=0, src_x=2, src_y=0, msg_type=MSG_MEM_RD_RESP, dest_tile=0, specific_txn_id=t0.txn_id)
    mut3_killed = (v3.delivery == DeliveryDecision.DELIVER) and (t1.completed is True)
    results.append({
        "mutant_id": "I9-MUT-03",
        "name": "Stale Reused Tag Delivered",
        "negative_control_job": "i9_mut_stale_deliver",
        "oracle": "^[FAIL] I9_STALE_DROPPED",
        "status": "KILLED" if mut3_killed else "SURVIVED",
        "kill_diagnostic": "Assertion failed: stale response completed newer transaction t1 on reused tag 0.",
    })

    # 4. MUT-04: RX all
    m4 = AppRxExportPolicy(mut_rx_all=True)
    ok_t1, _ = m4.is_export_eligible(dest_tile=1, msg_type=MSG_MEM_RD_RESP)
    mut4_killed = (ok_t1 is True)
    results.append({
        "mutant_id": "I9-MUT-04",
        "name": "app_rx Export to All Tiles",
        "negative_control_job": "i9_mut_rx_all",
        "oracle": "^[FAIL] I9_RX_ACCOUNTED",
        "status": "KILLED" if mut4_killed else "SURVIVED",
        "kill_diagnostic": "Assertion failed: app_rx permitted memory response export to unauthorized tile 1.",
    })

    # 5. MUT-05: Window inclusive
    m5 = Tile2BRAMModel(mut_window_inclusive=True)
    res5 = m5.read_word(TILE_2_BRAM_LIMIT)  # 0x2200_4000
    mut5_killed = (res5.accepted is True)
    results.append({
        "mutant_id": "I9-MUT-05",
        "name": "BRAM Upper Boundary Inclusive",
        "negative_control_job": None,
        "oracle": "^[FAIL] I9_WINDOW_LIMIT_STRICT",
        "status": "KILLED" if mut5_killed else "SURVIVED",
        "kill_diagnostic": "Assertion failed: BRAM accepted out-of-window address 0x2200_4000.",
    })

    # 6. MUT-06: Window 1K
    m6 = Tile2BRAMModel(mut_window_1k=True)
    res6 = m6.read_word(TILE_2_BRAM_LAST_ALIGNED)  # 0x2200_3FFC
    mut6_killed = (res6.accepted is False)
    results.append({
        "mutant_id": "I9-MUT-06",
        "name": "BRAM Window Restricted to 1K",
        "negative_control_job": "i9_mut_window_1k",
        "oracle": "^[FAIL] I9_WINDOW_TOP_OK",
        "status": "KILLED" if mut6_killed else "SURVIVED",
        "kill_diagnostic": "Assertion failed: BRAM rejected valid address 0x2200_3FFC due to 1KB artificial bound.",
    })

    # 7. MUT-07: BRAM lanes ignored
    m7 = Tile2BRAMModel(mut_bram_lanes=True)
    addr7 = TILE_2_BRAM_BASE + 0x100
    m7.write_word(addr7, wdata=0x00000000, wstrb=0xF)
    res7 = m7.write_word(addr7, wdata=0xFFFFFFFF, wstrb=0x1)  # Write lane 0 only
    mut7_killed = (res7.rdata_after == 0xFFFFFFFF)  # Overwrote all 4 lanes
    results.append({
        "mutant_id": "I9-MUT-07",
        "name": "Byte-Lane Enables Ignored",
        "negative_control_job": "i9_mut_bram_lanes",
        "oracle": "^[FAIL] I9_BYTE_LANES",
        "status": "KILLED" if mut7_killed else "SURVIVED",
        "kill_diagnostic": "Assertion failed: write with wstrb=0x1 overwrote all 4 byte lanes.",
    })

    # 8. MUT-08: Disabled lanes overwrite
    m8 = Tile2BRAMModel(mut_disabled_lanes_overwrite=True)
    addr8 = TILE_2_BRAM_BASE + 0x200
    m8.write_word(addr8, wdata=0x11223344, wstrb=0xF)
    res8 = m8.write_word(addr8, wdata=0x000000AA, wstrb=0x1)  # Only lane 0 should be updated
    # In mutant, lanes 1, 2, 3 were zeroed out
    mut8_killed = (res8.rdata_after == 0x000000AA) and (res8.rdata_after != 0x112233AA)
    results.append({
        "mutant_id": "I9-MUT-08",
        "name": "Disabled Lanes Zeroed Out",
        "negative_control_job": None,
        "oracle": "^[FAIL] I9_LANE_PRESERVE",
        "status": "KILLED" if mut8_killed else "SURVIVED",
        "kill_diagnostic": "Assertion failed: unselected byte lanes 1..3 were wiped instead of preserved.",
    })

    killed_count = sum(1 for r in results if r["status"] == "KILLED")
    return {
        "metadata": {
            "title": "I-9 Python-Model Mutation Analysis Results",
            "generator": "verification.p7_i9_model",
            "contract": "M-F1 revision 8",
            "total_mutants": len(results),
            "killed_mutants": killed_count,
            "mutation_score_percent": (killed_count / len(results)) * 100.0,
            "status": "PASS" if killed_count == len(results) else "FAIL",
        },
        "mutants": results,
    }


# ==============================================================================
# 6. Differential / Integration Vector Generator
# ==============================================================================

def generate_i9_vectors() -> Dict[str, Any]:
    """
    Generates contract-derived reference vectors for I-9 features and checks.
    """
    model = P7I9IntegratedModel(slot_timeout=600)
    vectors: List[Dict[str, Any]] = []

    # VEC 01: Slot allocation sequence
    t0 = model.send_memory_request(dest_x=2, dest_y=0, dest_tile=2, req_type=MSG_MEM_RD_REQ, cycle=0)
    t1 = model.send_memory_request(dest_x=2, dest_y=0, dest_tile=2, req_type=MSG_MEM_WR_REQ, cycle=10)
    t_full = model.send_memory_request(dest_x=2, dest_y=0, dest_tile=2, req_type=MSG_MEM_RD_REQ, cycle=20)
    vectors.append({
        "vector_id": "VEC-I9-01-ALLOC-FULL",
        "description": "Two transaction slots allocated; third allocation blocked",
        "provenance": "contract-derived (M-F1 rev 8 §11)",
        "inputs": {"alloc_0": "MEM_RD_REQ", "alloc_1": "MEM_WR_REQ", "alloc_2": "MEM_RD_REQ"},
        "expected": {"slot_0_tag": 0, "slot_1_tag": 1, "alloc_2_result": None},
        "python_result": {"slot_0_tag": t0.tag, "slot_1_tag": t1.tag, "alloc_2_result": None if t_full is None else t_full.tag},
        "status": "PASS" if (t0.tag == 0 and t1.tag == 1 and t_full is None) else "FAIL",
    })

    # VEC 02: Timeout release (advance from cycle 20 to cycle 605: t0 expires at 600; t1 expires at 610)
    timed_out = model.advance_time(585)
    vectors.append({
        "vector_id": "VEC-I9-02-TIMEOUT-RELEASE",
        "description": "Slot 0 expires at 600 cycles and is freed while slot 1 remains pending",
        "provenance": "contract-derived (M-F1 rev 8 §11 / dual_lane_jobs.json: i9_integ)",
        "inputs": {"elapsed_cycles": 585, "current_cycle": 605, "slot_0_timeout": 600, "slot_1_timeout": 610},
        "expected": {"timed_out_count": 1, "timed_out_slot": 0, "slots_occupied": 1},
        "python_result": {"timed_out_count": len(timed_out), "timed_out_slot": timed_out[0].slot_id, "slots_occupied": model.ni.slots_occupied},
        "status": "PASS" if len(timed_out) == 1 and timed_out[0].slot_id == 0 and model.ni.slots_occupied == 1 else "FAIL",
    })

    # VEC 03: Late response drop
    v_late = model.receive_memory_response(tag=0, src_x=2, src_y=0, msg_type=MSG_MEM_RD_RESP, dest_tile=0, cycle=650)
    vectors.append({
        "vector_id": "VEC-I9-03-LATE-DROP",
        "description": "Late response for timed-out slot 0 dropped and not delivered",
        "provenance": "contract-derived (M-F1 rev 8 §11 / dual_lane_jobs.json: i9_integ)",
        "inputs": {"tag": 0, "msg_type": "MEM_RD_RESP", "dest_tile": 0},
        "expected": {"delivery": "DROP", "classification": "LATE_TIMED_OUT", "exported_to_app_rx": False},
        "python_result": {"delivery": v_late.delivery.value, "classification": v_late.classification.value, "exported_to_app_rx": v_late.exported_to_app_rx},
        "status": "PASS" if v_late.delivery == DeliveryDecision.DROP and not v_late.exported_to_app_rx else "FAIL",
    })

    # VEC 04: app_rx CPU tile 0 export OK
    t_cpu0 = model.send_memory_request(dest_x=2, dest_y=0, dest_tile=2, req_type=MSG_MEM_RD_REQ, cycle=700)
    v_cpu0 = model.receive_memory_response(tag=0, src_x=2, src_y=0, msg_type=MSG_MEM_RD_RESP, dest_tile=0, cycle=750)
    vectors.append({
        "vector_id": "VEC-I9-04-APP-RX-CPU0",
        "description": "Memory response exported to CPU tile 0",
        "provenance": "contract-derived (M-F1 rev 8 §11)",
        "inputs": {"dest_tile": 0, "msg_type": "MEM_RD_RESP"},
        "expected": {"delivery": "DELIVER", "exported_to_app_rx": True},
        "python_result": {"delivery": v_cpu0.delivery.value, "exported_to_app_rx": v_cpu0.exported_to_app_rx},
        "status": "PASS" if v_cpu0.exported_to_app_rx else "FAIL",
    })

    # VEC 05: app_rx CPU tile 3 export OK
    t_cpu3 = model.send_memory_request(dest_x=2, dest_y=0, dest_tile=2, req_type=MSG_MEM_RD_REQ, cycle=800)
    v_cpu3 = model.receive_memory_response(tag=0, src_x=2, src_y=0, msg_type=MSG_MEM_RD_RESP, dest_tile=3, cycle=850)
    vectors.append({
        "vector_id": "VEC-I9-05-APP-RX-CPU3",
        "description": "Memory response exported to CPU tile 3",
        "provenance": "contract-derived (M-F1 rev 8 §11)",
        "inputs": {"dest_tile": 3, "msg_type": "MEM_RD_RESP"},
        "expected": {"delivery": "DELIVER", "exported_to_app_rx": True},
        "python_result": {"delivery": v_cpu3.delivery.value, "exported_to_app_rx": v_cpu3.exported_to_app_rx},
        "status": "PASS" if v_cpu3.exported_to_app_rx else "FAIL",
    })

    # VEC 06: app_rx unauthorized tile 1 drop
    t_t1 = model.send_memory_request(dest_x=2, dest_y=0, dest_tile=2, req_type=MSG_MEM_RD_REQ, cycle=900)
    v_t1 = model.receive_memory_response(tag=0, src_x=2, src_y=0, msg_type=MSG_MEM_RD_RESP, dest_tile=1, cycle=950)
    vectors.append({
        "vector_id": "VEC-I9-06-APP-RX-TILE1-DROP",
        "description": "Memory response to non-CPU tile 1 rejected from app_rx",
        "provenance": "contract-derived (M-F1 rev 8 §11)",
        "inputs": {"dest_tile": 1, "msg_type": "MEM_RD_RESP"},
        "expected": {"delivery": "DROP", "drop_reason": "UNAUTHORIZED_APP_RX_DESTINATION", "exported_to_app_rx": False},
        "python_result": {"delivery": v_t1.delivery.value, "drop_reason": v_t1.drop_reason.value, "exported_to_app_rx": v_t1.exported_to_app_rx},
        "status": "PASS" if v_t1.delivery == DeliveryDecision.DROP and not v_t1.exported_to_app_rx else "FAIL",
    })

    # VEC 07: BRAM 16 KB last valid aligned address (0x2200_3FFC)
    bram = Tile2BRAMModel()
    res_last = bram.read_word(TILE_2_BRAM_LAST_ALIGNED)
    vectors.append({
        "vector_id": "VEC-I9-07-BRAM-BOUNDARY-3FFC",
        "description": "Tile-2 BRAM word read at 0x2200_3FFC accepted",
        "provenance": "contract-derived (M-F1 rev 8 §11 / E4_RESPONSE_20261106 §5)",
        "inputs": {"addr": "0x22003FFC", "access_type": "READ"},
        "expected": {"accepted": True, "drop_reason": "NONE"},
        "python_result": {"accepted": res_last.accepted, "drop_reason": res_last.drop_reason.value},
        "status": "PASS" if res_last.accepted else "FAIL",
    })

    # VEC 08: BRAM 16 KB first out-of-window address (0x2200_4000)
    res_beyond = bram.read_word(TILE_2_BRAM_LIMIT)
    vectors.append({
        "vector_id": "VEC-I9-08-BRAM-BOUNDARY-4000",
        "description": "Tile-2 BRAM word read at 0x2200_4000 rejected",
        "provenance": "contract-derived (M-F1 rev 8 §11 / E4_RESPONSE_20261106 §5)",
        "inputs": {"addr": "0x22004000", "access_type": "READ"},
        "expected": {"accepted": False, "drop_reason": "BRAM_OUT_OF_BOUNDS"},
        "python_result": {"accepted": res_beyond.accepted, "drop_reason": res_beyond.drop_reason.value},
        "status": "PASS" if not res_beyond.accepted else "FAIL",
    })

    # VEC 09: Byte-lane partial write preservation
    addr_byte = TILE_2_BRAM_BASE + 0x100
    bram.write_word(addr_byte, wdata=0x11223344, wstrb=0xF)
    res_byte = bram.write_word(addr_byte, wdata=0xAA00BB00, wstrb=0x5)  # Write lanes 0 and 2
    vectors.append({
        "vector_id": "VEC-I9-09-BRAM-BYTE-LANES-PARTIAL",
        "description": "Partial write with wstrb=0x5 updates lanes 0 and 2; preserves 1 and 3",
        "provenance": "contract-derived (mem_bram.sv / M-F1 rev 8 §11)",
        "inputs": {"addr": hex(addr_byte), "wdata": "0xAA00BB00", "wstrb": "0x5", "initial_val": "0x11223344"},
        "expected": {"accepted": True, "rdata_after": "0x11003300", "modified_bytes": [0, 2]},
        "python_result": {"accepted": res_byte.accepted, "rdata_after": hex(res_byte.rdata_after), "modified_bytes": res_byte.modified_bytes},
        "status": "PASS" if res_byte.rdata_after == 0x11003300 else "FAIL",
    })

    all_pass = all(v["status"] == "PASS" for v in vectors)
    return {
        "metadata": {
            "title": "I-9 Differential and Integration Reference Vectors",
            "generator": "verification.p7_i9_model",
            "contract": "M-F1 revision 8",
            "total_vectors": len(vectors),
            "passed_vectors": sum(1 for v in vectors if v["status"] == "PASS"),
            "status": "PASS" if all_pass else "FAIL",
        },
        "vectors": vectors,
    }


def main() -> int:
    """CLI generator for I-9 artifacts."""
    import argparse
    import json
    from verification.p7_paths import get_default_paths

    parser = argparse.ArgumentParser(description="Generate I-9 verification artifacts")
    parser.add_argument("--out", metavar="DIR", default=None, help="Output directory for generated JSON files")
    args = parser.parse_args()

    paths = get_default_paths()
    out_dir = Path(args.out).resolve() if args.out else paths.generated_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    # 1. Run mutation analysis
    mut_results = execute_i9_mutation_analysis()
    mut_file = out_dir / "p7_i9_mutation_results.json"
    with open(mut_file, "w", encoding="utf-8") as f:
        json.dump(mut_results, f, indent=2)
    print(f"Generated: {mut_file} ({mut_results['metadata']['killed_mutants']}/{mut_results['metadata']['total_mutants']} mutants killed)")

    # 2. Run vector generation
    vec_results = generate_i9_vectors()
    vec_file = out_dir / "p7_i9_vectors.json"
    with open(vec_file, "w", encoding="utf-8") as f:
        json.dump(vec_results, f, indent=2)
    print(f"Generated: {vec_file} ({vec_results['metadata']['passed_vectors']}/{vec_results['metadata']['total_vectors']} vectors passed)")

    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())

