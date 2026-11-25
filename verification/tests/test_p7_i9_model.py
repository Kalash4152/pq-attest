#!/usr/bin/env python3
"""
Unit tests for the PQ-Attest I-9 Reference Model Extension (M-F1 revision 8).
Validates NI slot allocation, timeout, late/stale response rejection,
app_rx CPU tile restrictions, Tile-2 BRAM 16 KB window, and byte-lane enables.
"""

from __future__ import annotations

import pytest

from verification.p7_i9_model import (
    AUTHORIZED_APP_RX_CPU_TILES,
    DEFAULT_NI_SLOT_TIMEOUT,
    DeliveryDecision,
    I9DropReason,
    MSG_ATTEST_RESPONSE,
    MSG_MEM_RD_REQ,
    MSG_MEM_RD_RESP,
    MSG_MEM_WR_REQ,
    MSG_MEM_WR_RESP,
    NITransactionTable,
    P7I9IntegratedModel,
    ResponseClassification,
    SlotState,
    TILE_2_BRAM_BASE,
    TILE_2_BRAM_LAST_ALIGNED,
    TILE_2_BRAM_LIMIT,
    Tile2BRAMModel,
)


# ==============================================================================
# A. NI Slot Allocation & Timeout Tests
# ==============================================================================

def test_ni_slot_allocation_success() -> None:
    """Verifies allocation of both outstanding transaction slots in order."""
    table = NITransactionTable(slot_timeout=600)
    assert table.slots_occupied == 0
    assert table.has_available_slot is True

    # Allocate first slot (slot 0, tag 0)
    t0 = table.allocate(dest_x=2, dest_y=0, dest_tile=2, req_type=MSG_MEM_RD_REQ)
    assert t0 is not None
    assert t0.slot_id == 0
    assert t0.tag == 0
    assert table.slots_occupied == 1
    assert table.has_available_slot is True

    # Allocate second slot (slot 1, tag 1)
    t1 = table.allocate(dest_x=0, dest_y=1, dest_tile=3, req_type=MSG_MEM_WR_REQ)
    assert t1 is not None
    assert t1.slot_id == 1
    assert t1.tag == 1
    assert table.slots_occupied == 2
    assert table.has_available_slot is False


def test_ni_slot_allocation_blocked_when_full() -> None:
    """Verifies that attempting allocation when both slots are full returns None."""
    table = NITransactionTable(slot_timeout=600)
    assert table.allocate(dest_x=2, dest_y=0, dest_tile=2) is not None
    assert table.allocate(dest_x=0, dest_y=1, dest_tile=3) is not None

    # Third allocation must fail
    t_blocked = table.allocate(dest_x=1, dest_y=1, dest_tile=4)
    assert t_blocked is None
    assert table.slots_occupied == 2


def test_ni_slot_timeout_release() -> None:
    """Verifies slot timeout after exact contract duration (600 cycles) and slot release."""
    table = NITransactionTable(slot_timeout=600)
    t0 = table.allocate(dest_x=2, dest_y=0, dest_tile=2, cycle=100)
    assert t0 is not None
    assert t0.timeout_cycle == 700

    # Advance 599 cycles -> slot still occupied
    timed_out = table.advance_time(599)
    assert len(timed_out) == 0
    assert table.slots_occupied == 1
    assert table.slots[0] is not None

    # Advance 1 cycle -> hit 600 cycles timeout -> slot freed
    timed_out = table.advance_time(1)
    assert len(timed_out) == 1
    assert timed_out[0].txn_id == t0.txn_id
    assert table.slots_occupied == 0
    assert table.slots[0] is None
    assert table.has_available_slot is True


def test_slot_reuse_after_timeout() -> None:
    """Verifies another transaction can allocate the slot released by timeout."""
    table = NITransactionTable(slot_timeout=600)
    t0 = table.allocate(dest_x=2, dest_y=0, dest_tile=2, cycle=0)
    assert t0 is not None

    # Timeout slot 0
    table.advance_time(600)
    assert table.slots_occupied == 0

    # Allocate new transaction into freed slot 0
    t_new = table.allocate(dest_x=0, dest_y=0, dest_tile=0)
    assert t_new is not None
    assert t_new.slot_id == 0
    assert t_new.tag == 0
    assert t_new.txn_id != t0.txn_id
    assert table.slots_occupied == 1


def test_independent_slot_timeouts() -> None:
    """Verifies that timeout of slot 0 does not affect active slot 1."""
    table = NITransactionTable(slot_timeout=600)
    t0 = table.allocate(dest_x=2, dest_y=0, dest_tile=2, cycle=0)
    table.advance_time(200)
    t1 = table.allocate(dest_x=0, dest_y=1, dest_tile=3)
    assert t0 is not None and t1 is not None

    # Advance to cycle 600: t0 expires, t1 still has 200 cycles remaining
    timed_out = table.advance_time(400)
    assert len(timed_out) == 1
    assert timed_out[0].txn_id == t0.txn_id
    assert table.slots[0] is None
    assert table.slots[1] is not None
    assert table.slots[1].txn_id == t1.txn_id
    assert table.slots_occupied == 1


# ==============================================================================
# B. Valid Responses & Completion Tests
# ==============================================================================

def test_valid_response_matching_and_completion() -> None:
    """Verifies matching response completes transaction and releases slot."""
    table = NITransactionTable(slot_timeout=600)
    t0 = table.allocate(dest_x=2, dest_y=0, dest_tile=2, req_type=MSG_MEM_RD_REQ)
    assert t0 is not None

    verdict = table.process_response(
        tag=0,
        src_x=2,
        src_y=0,
        msg_type=MSG_MEM_RD_RESP,
        dest_tile=0,  # CPU tile 0
    )

    assert verdict.classification == ResponseClassification.VALID_MATCH
    assert verdict.delivery == DeliveryDecision.DELIVER
    assert verdict.drop_reason == I9DropReason.NONE
    assert verdict.slot_state_after == SlotState.FREE
    assert verdict.exported_to_app_rx is True
    assert table.slots_occupied == 0
    assert t0.completed is True


def test_mismatched_source_rejected() -> None:
    """Verifies response from unexpected source tile coordinates is dropped."""
    table = NITransactionTable(slot_timeout=600)
    t0 = table.allocate(dest_x=2, dest_y=0, dest_tile=2, req_type=MSG_MEM_RD_REQ)
    assert t0 is not None

    # Arriving from wrong coordinates (0, 1) instead of (2, 0)
    verdict = table.process_response(
        tag=0,
        src_x=0,
        src_y=1,
        msg_type=MSG_MEM_RD_RESP,
        dest_tile=0,
    )

    assert verdict.classification == ResponseClassification.MISMATCHED_SRC
    assert verdict.delivery == DeliveryDecision.DROP
    assert verdict.drop_reason == I9DropReason.SRC_DEST_MISMATCH
    assert table.slots_occupied == 1  # Slot remains pending
    assert t0.completed is False


def test_mismatched_response_type_rejected() -> None:
    """Verifies response with unexpected message type is dropped."""
    table = NITransactionTable(slot_timeout=600)
    t0 = table.allocate(dest_x=2, dest_y=0, dest_tile=2, req_type=MSG_MEM_RD_REQ)
    assert t0 is not None

    # Arriving with WR_RESP instead of expected RD_RESP
    verdict = table.process_response(
        tag=0,
        src_x=2,
        src_y=0,
        msg_type=MSG_MEM_WR_RESP,
        dest_tile=0,
    )

    assert verdict.classification == ResponseClassification.MISMATCHED_TYPE
    assert verdict.delivery == DeliveryDecision.DROP
    assert verdict.drop_reason == I9DropReason.MSG_TYPE_MISMATCH
    assert table.slots_occupied == 1


# ==============================================================================
# C. Late & Stale Response Handling Tests
# ==============================================================================

def test_late_response_after_timeout_dropped() -> None:
    """Verifies response arriving after slot timeout is dropped and never delivered."""
    table = NITransactionTable(slot_timeout=600)
    t0 = table.allocate(dest_x=2, dest_y=0, dest_tile=2, req_type=MSG_MEM_RD_REQ, cycle=0)
    assert t0 is not None

    # Advance past timeout
    table.advance_time(601)
    assert table.slots[0] is None

    # Late response arrives
    verdict = table.process_response(
        tag=0,
        src_x=2,
        src_y=0,
        msg_type=MSG_MEM_RD_RESP,
        dest_tile=0,
    )

    assert verdict.classification == ResponseClassification.LATE_TIMED_OUT
    assert verdict.delivery == DeliveryDecision.DROP
    assert verdict.drop_reason == I9DropReason.SLOT_TIMED_OUT
    assert verdict.exported_to_app_rx is False


def test_stale_response_for_reused_tag_dropped() -> None:
    """Verifies response from old transaction arriving after tag reuse is dropped."""
    table = NITransactionTable(slot_timeout=600)
    t0 = table.allocate(dest_x=2, dest_y=0, dest_tile=2, req_type=MSG_MEM_RD_REQ, cycle=0)
    assert t0 is not None

    # Slot 0 times out
    table.advance_time(600)

    # New transaction reuses slot 0 / tag 0
    t1 = table.allocate(dest_x=2, dest_y=0, dest_tile=2, req_type=MSG_MEM_RD_REQ)
    assert t1 is not None
    assert t1.tag == 0
    assert t1.txn_id != t0.txn_id

    # Arriving response belongs to old t0 (identified by specific_txn_id)
    verdict = table.process_response(
        tag=0,
        src_x=2,
        src_y=0,
        msg_type=MSG_MEM_RD_RESP,
        dest_tile=0,
        specific_txn_id=t0.txn_id,
    )

    assert verdict.classification == ResponseClassification.STALE_REUSED
    assert verdict.delivery == DeliveryDecision.DROP
    assert verdict.drop_reason == I9DropReason.STALE_TAG_REUSED
    assert verdict.exported_to_app_rx is False
    assert table.slots_occupied == 1  # Active t1 slot is NOT completed
    assert t1.completed is False


def test_duplicate_response_after_completion_dropped() -> None:
    """Verifies second response for already-completed transaction is dropped."""
    table = NITransactionTable(slot_timeout=600)
    t0 = table.allocate(dest_x=2, dest_y=0, dest_tile=2, req_type=MSG_MEM_RD_REQ)
    assert t0 is not None

    # First response completes it
    v1 = table.process_response(tag=0, src_x=2, src_y=0, msg_type=MSG_MEM_RD_RESP, dest_tile=0)
    assert v1.delivery == DeliveryDecision.DELIVER

    # Second response arrives for same tag while slot is free
    v2 = table.process_response(tag=0, src_x=2, src_y=0, msg_type=MSG_MEM_RD_RESP, dest_tile=0)
    assert v2.classification == ResponseClassification.UNMATCHED_ALREADY_COMPLETED
    assert v2.delivery == DeliveryDecision.DROP
    assert v2.drop_reason == I9DropReason.ALREADY_COMPLETED
    assert v2.exported_to_app_rx is False


def test_invalid_tag_value_dropped() -> None:
    """Verifies response carrying invalid tag (>= N_OUTSTANDING) is dropped."""
    table = NITransactionTable(slot_timeout=600)
    verdict = table.process_response(
        tag=2,  # Invalid tag (only 0 and 1 valid)
        src_x=2,
        src_y=0,
        msg_type=MSG_MEM_RD_RESP,
        dest_tile=0,
    )
    assert verdict.classification == ResponseClassification.INVALID_TAG
    assert verdict.delivery == DeliveryDecision.DROP
    assert verdict.drop_reason == I9DropReason.INVALID_TAG_VALUE


# ==============================================================================
# D. app_rx CPU Tile Restriction Tests
# ==============================================================================

def test_app_rx_export_permitted_for_cpu_tiles() -> None:
    """Verifies memory responses are exported to CPU tiles 0 and 3."""
    model = P7I9IntegratedModel(slot_timeout=600)

    # To CPU tile 0
    t0 = model.send_memory_request(dest_x=2, dest_y=0, dest_tile=2)
    v0 = model.receive_memory_response(tag=0, src_x=2, src_y=0, msg_type=MSG_MEM_RD_RESP, dest_tile=0)
    assert v0.delivery == DeliveryDecision.DELIVER
    assert v0.exported_to_app_rx is True

    # To CPU tile 3
    t1 = model.send_memory_request(dest_x=2, dest_y=0, dest_tile=2)
    v1 = model.receive_memory_response(tag=0, src_x=2, src_y=0, msg_type=MSG_MEM_RD_RESP, dest_tile=3)
    assert v1.delivery == DeliveryDecision.DELIVER
    assert v1.exported_to_app_rx is True


@pytest.mark.parametrize("unauthorized_tile", [1, 2, 4, 5])
def test_app_rx_export_rejected_for_non_cpu_tiles(unauthorized_tile: int) -> None:
    """Verifies memory responses addressed to non-CPU tiles (1, 2, 4, 5) are not exported."""
    model = P7I9IntegratedModel(slot_timeout=600)
    t = model.send_memory_request(dest_x=2, dest_y=0, dest_tile=2)

    verdict = model.receive_memory_response(
        tag=0,
        src_x=2,
        src_y=0,
        msg_type=MSG_MEM_RD_RESP,
        dest_tile=unauthorized_tile,
    )

    assert verdict.delivery == DeliveryDecision.DROP
    assert verdict.drop_reason == I9DropReason.UNAUTHORIZED_APP_RX_DESTINATION
    assert verdict.exported_to_app_rx is False


def test_non_memory_responses_excluded_from_app_rx() -> None:
    """Verifies non-memory responses (e.g. ATTEST_RESPONSE) cannot use app_rx export."""
    model = P7I9IntegratedModel(slot_timeout=600)
    verdict = model.receive_memory_response(
        tag=0,
        src_x=1,
        src_y=1,
        msg_type=MSG_ATTEST_RESPONSE,
        dest_tile=0,
    )
    assert verdict.classification == ResponseClassification.NON_MEMORY_TYPE
    assert verdict.delivery == DeliveryDecision.DROP
    assert verdict.drop_reason == I9DropReason.NON_MEMORY_RESPONSE
    assert verdict.exported_to_app_rx is False


# ==============================================================================
# E. Tile-2 BRAM 16 KB Window Tests
# ==============================================================================

def test_bram_exact_boundaries() -> None:
    """Verifies 0x2200_3FFC is accepted and 0x2200_4000 is rejected."""
    bram = Tile2BRAMModel()

    # 0x2200_3FFC: Last valid aligned word inside the 16 KB window
    r_last = bram.read_word(TILE_2_BRAM_LAST_ALIGNED)
    assert r_last.accepted is True
    assert r_last.drop_reason == I9DropReason.NONE

    # 0x2200_4000: First address beyond 16 KB window -> must be REJECTED
    r_beyond = bram.read_word(TILE_2_BRAM_LIMIT)
    assert r_beyond.accepted is False
    assert r_beyond.drop_reason == I9DropReason.BRAM_OUT_OF_BOUNDS


def test_bram_first_valid_address() -> None:
    """Verifies base address 0x2200_0000 is accepted."""
    bram = Tile2BRAMModel()
    res = bram.read_word(TILE_2_BRAM_BASE)
    assert res.accepted is True
    assert res.drop_reason == I9DropReason.NONE


def test_bram_misaligned_access_rejected() -> None:
    """Verifies non-word-aligned accesses are rejected."""
    bram = Tile2BRAMModel()
    for offset in [1, 2, 3]:
        bad_addr = TILE_2_BRAM_BASE + offset
        res = bram.read_word(bad_addr)
        assert res.accepted is False
        assert res.drop_reason == I9DropReason.BRAM_MISALIGNED


def test_bram_below_base_rejected() -> None:
    """Verifies accesses below 0x2200_0000 are rejected."""
    bram = Tile2BRAMModel()
    res = bram.read_word(TILE_2_BRAM_BASE - 4)
    assert res.accepted is False
    assert res.drop_reason == I9DropReason.BRAM_OUT_OF_BOUNDS


# ==============================================================================
# F. Byte-Lane Write-Enable Tests
# ==============================================================================

def test_bram_full_word_write() -> None:
    """Verifies all byte lanes write when wstrb == 0xF."""
    bram = Tile2BRAMModel()
    addr = TILE_2_BRAM_BASE + 0x100
    res = bram.write_word(addr, wdata=0xDEADBEEF, wstrb=0xF)
    assert res.accepted is True
    assert res.rdata_after == 0xDEADBEEF
    assert res.modified_bytes == [0, 1, 2, 3]


def test_bram_zero_write_strobe_preserves_content() -> None:
    """Verifies wstrb == 0x0 modifies zero bytes."""
    bram = Tile2BRAMModel()
    addr = TILE_2_BRAM_BASE + 0x200
    bram.write_word(addr, wdata=0x12345678, wstrb=0xF)

    # Write with wstrb = 0x0
    res = bram.write_word(addr, wdata=0xAAAAAAAA, wstrb=0x0)
    assert res.accepted is True
    assert res.rdata_after == 0x12345678
    assert res.modified_bytes == []


@pytest.mark.parametrize("lane,wstrb,expected_byte", [
    (0, 0x1, 0xAA),
    (1, 0x2, 0xBB),
    (2, 0x4, 0xCC),
    (3, 0x8, 0xDD),
])
def test_bram_individual_byte_lanes(lane: int, wstrb: int, expected_byte: int) -> None:
    """Verifies single-byte write enables modify only targeted lane."""
    bram = Tile2BRAMModel()
    addr = TILE_2_BRAM_BASE + 0x300

    # Initial zero word
    bram.write_word(addr, wdata=0x00000000, wstrb=0xF)

    # Write single lane
    wdata = 0xDDCCBBAA
    res = bram.write_word(addr, wdata=wdata, wstrb=wstrb)
    assert res.accepted is True
    assert res.modified_bytes == [lane]

    actual_byte = (res.rdata_after >> (lane * 8)) & 0xFF
    assert actual_byte == expected_byte

    # Verify other lanes remain 0
    for other in range(4):
        if other != lane:
            assert ((res.rdata_after >> (other * 8)) & 0xFF) == 0


def test_bram_partial_write_preserves_unselected_lanes() -> None:
    """Verifies unselected lanes in partial write strictly retain prior values."""
    bram = Tile2BRAMModel()
    addr = TILE_2_BRAM_BASE + 0x400

    # Initialize with recognizable pattern
    bram.write_word(addr, wdata=0x11223344, wstrb=0xF)

    # Overwrite only lanes 0 and 2 (wstrb = 0x5)
    res = bram.write_word(addr, wdata=0xAA00BB00, wstrb=0x5)
    assert res.accepted is True
    assert res.modified_bytes == [0, 2]

    # Lane 0 should be 0x00
    assert (res.rdata_after & 0xFF) == 0x00
    # Lane 1 should preserve 0x33
    assert ((res.rdata_after >> 8) & 0xFF) == 0x33
    # Lane 2 should be 0x00
    assert ((res.rdata_after >> 16) & 0xFF) == 0x00
    # Lane 3 should preserve 0x11
    assert ((res.rdata_after >> 24) & 0xFF) == 0x11


# ==============================================================================
# G. State Consistency & Invariant Tests
# ==============================================================================

def test_full_interleaved_transaction_sequence() -> None:
    """Verifies complex interleaved sequence of allocations, timeouts and completions."""
    model = P7I9IntegratedModel(slot_timeout=600)

    # 1. Allocate slot 0 and slot 1
    t0 = model.send_memory_request(dest_x=2, dest_y=0, dest_tile=2, cycle=0)
    t1 = model.send_memory_request(dest_x=2, dest_y=0, dest_tile=2, cycle=100)
    assert model.ni.slots_occupied == 2

    # 2. Complete slot 0 at cycle 300
    v0 = model.receive_memory_response(tag=0, src_x=2, src_y=0, msg_type=MSG_MEM_RD_RESP, dest_tile=0, cycle=300)
    assert v0.delivery == DeliveryDecision.DELIVER
    assert model.ni.slots_occupied == 1

    # 3. Slot 0 is now free -> allocate new t2 into slot 0
    t2 = model.send_memory_request(dest_x=2, dest_y=0, dest_tile=2, cycle=400)
    assert t2 is not None
    assert t2.slot_id == 0

    # 4. Advance to cycle 750 -> t1 (allocated at cycle 100, timeout 700) times out!
    timed_out = model.advance_time(350)
    assert len(timed_out) == 1
    assert timed_out[0].txn_id == t1.txn_id
    assert model.ni.slots[1] is None

    # 5. Late response for t1 arrives at cycle 800 -> must be dropped
    v1_late = model.receive_memory_response(tag=1, src_x=2, src_y=0, msg_type=MSG_MEM_RD_RESP, dest_tile=0, cycle=800)
    assert v1_late.delivery == DeliveryDecision.DROP
    assert v1_late.classification == ResponseClassification.LATE_TIMED_OUT

    # 6. Valid response for t2 arrives at cycle 850 -> must complete cleanly
    v2 = model.receive_memory_response(tag=0, src_x=2, src_y=0, msg_type=MSG_MEM_RD_RESP, dest_tile=0, cycle=850)
    assert v2.delivery == DeliveryDecision.DELIVER
    assert model.ni.slots_occupied == 0


# ==============================================================================
# H. Python-Model Mutant Kill Tests (8 Targeted Mutants)
# ==============================================================================

def test_kill_mut_no_timeout() -> None:
    """MUT-01: Verifies detection when timeout does not release the slot."""
    # Normal model frees slot
    normal = NITransactionTable(slot_timeout=600)
    normal.allocate(dest_x=2, dest_y=0, dest_tile=2, cycle=0)
    normal.advance_time(600)
    assert normal.slots[0] is None
    assert normal.slots_occupied == 0

    # Mutant model fails to free slot
    mut = NITransactionTable(slot_timeout=600, mut_no_timeout=True)
    mut.allocate(dest_x=2, dest_y=0, dest_tile=2, cycle=0)
    mut.advance_time(600)
    # Detection: slot remains occupied
    assert mut.slots[0] is not None
    assert mut.slots_occupied == 1


def test_kill_mut_late_deliver() -> None:
    """MUT-02: Verifies detection when late response is delivered instead of dropped."""
    # Normal model drops late response
    normal = NITransactionTable(slot_timeout=600)
    normal.allocate(dest_x=2, dest_y=0, dest_tile=2, cycle=0)
    normal.advance_time(601)
    v_norm = normal.process_response(tag=0, src_x=2, src_y=0, msg_type=MSG_MEM_RD_RESP, dest_tile=0)
    assert v_norm.delivery == DeliveryDecision.DROP

    # Mutant model delivers it
    mut = NITransactionTable(slot_timeout=600, mut_late_deliver=True)
    mut.allocate(dest_x=2, dest_y=0, dest_tile=2, cycle=0)
    mut.advance_time(601)
    v_mut = mut.process_response(tag=0, src_x=2, src_y=0, msg_type=MSG_MEM_RD_RESP, dest_tile=0)
    assert v_mut.delivery == DeliveryDecision.DELIVER


def test_kill_mut_stale_deliver() -> None:
    """MUT-03: Verifies detection when stale response completes newer transaction on reused tag."""
    # Mutant setup
    mut = NITransactionTable(slot_timeout=600, mut_stale_deliver=True)
    t0 = mut.allocate(dest_x=2, dest_y=0, dest_tile=2, cycle=0)
    mut.advance_time(600)
    t1 = mut.allocate(dest_x=2, dest_y=0, dest_tile=2, cycle=600)
    assert t0 is not None and t1 is not None

    # Stale response from t0 arrives
    v_mut = mut.process_response(tag=0, src_x=2, src_y=0, msg_type=MSG_MEM_RD_RESP, dest_tile=0, specific_txn_id=t0.txn_id)
    assert v_mut.delivery == DeliveryDecision.DELIVER
    assert t1.completed is True


def test_kill_mut_rx_all() -> None:
    """MUT-04: Verifies detection when app_rx exports to unauthorized tiles."""
    from verification.p7_i9_model import AppRxExportPolicy
    normal = AppRxExportPolicy(mut_rx_all=False)
    ok_norm, r_norm = normal.is_export_eligible(dest_tile=1, msg_type=MSG_MEM_RD_RESP)
    assert ok_norm is False
    assert r_norm == I9DropReason.UNAUTHORIZED_APP_RX_DESTINATION

    mut = AppRxExportPolicy(mut_rx_all=True)
    ok_mut, _ = mut.is_export_eligible(dest_tile=1, msg_type=MSG_MEM_RD_RESP)
    assert ok_mut is True


def test_kill_mut_window_inclusive() -> None:
    """MUT-05: Verifies detection when 0x2200_4000 is incorrectly accepted."""
    normal = Tile2BRAMModel(mut_window_inclusive=False)
    assert normal.read_word(TILE_2_BRAM_LIMIT).accepted is False

    mut = Tile2BRAMModel(mut_window_inclusive=True)
    assert mut.read_word(TILE_2_BRAM_LIMIT).accepted is True


def test_kill_mut_window_1k() -> None:
    """MUT-06: Verifies detection when 0x2200_3FFC is incorrectly rejected by 1KB limit."""
    normal = Tile2BRAMModel(mut_window_1k=False)
    assert normal.read_word(TILE_2_BRAM_LAST_ALIGNED).accepted is True

    mut = Tile2BRAMModel(mut_window_1k=True)
    res_mut = mut.read_word(TILE_2_BRAM_LAST_ALIGNED)
    assert res_mut.accepted is False
    assert res_mut.drop_reason == I9DropReason.BRAM_OUT_OF_BOUNDS


def test_kill_mut_bram_lanes() -> None:
    """MUT-07: Verifies detection when byte-lane enables are ignored."""
    addr = TILE_2_BRAM_BASE + 0x500
    mut = Tile2BRAMModel(mut_bram_lanes=True)
    mut.write_word(addr, wdata=0x00000000, wstrb=0xF)
    res = mut.write_word(addr, wdata=0x11223344, wstrb=0x1)  # Strobe lane 0 only
    # In mutant, all 4 lanes are overwritten
    assert res.rdata_after == 0x11223344


def test_kill_mut_disabled_lanes_overwrite() -> None:
    """MUT-08: Verifies detection when disabled byte lanes are wiped."""
    addr = TILE_2_BRAM_BASE + 0x600
    mut = Tile2BRAMModel(mut_disabled_lanes_overwrite=True)
    mut.write_word(addr, wdata=0x11223344, wstrb=0xF)
    res = mut.write_word(addr, wdata=0x000000AA, wstrb=0x1)  # Only lane 0 targeted
    # In mutant, lanes 1..3 were wiped to 0
    assert res.rdata_after == 0x000000AA
    assert res.rdata_after != 0x112233AA


def test_mutation_analysis_runner_all_killed() -> None:
    """Verifies all 8 mutants are killed by the mutation analysis suite."""
    from verification.p7_i9_model import execute_i9_mutation_analysis
    res = execute_i9_mutation_analysis()
    assert res["metadata"]["status"] == "PASS"
    assert res["metadata"]["killed_mutants"] == 8
    assert res["metadata"]["total_mutants"] == 8
    assert res["metadata"]["mutation_score_percent"] == 100.0


def test_vector_generation_all_passed() -> None:
    """Verifies all reference vectors pass verification against the model."""
    from verification.p7_i9_model import generate_i9_vectors
    vecs = generate_i9_vectors()
    assert vecs["metadata"]["status"] == "PASS"
    assert vecs["metadata"]["passed_vectors"] == 9
    assert vecs["metadata"]["total_vectors"] == 9

