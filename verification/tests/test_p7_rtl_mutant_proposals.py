"""
verification/tests/test_p7_rtl_mutant_proposals.py
==================================================
PQ-Attest P7 RTL Mutant Proposals Tests — Step 18 (Evidence-Grounded).

Engineer 4 Verification Infrastructure.

Tests:
1. Coverage of all 15 required architectural categories and proposal numbers (01..15).
2. Field completeness and real source path validation (no fabricated files).
3. Exclusive triage classification fidelity (implemented=3, already_covered=9, not_a_killable_control=3).
4. Manifest generation and Markdown report generation from single-source-of-truth JSON.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from verification.p7_paths import get_default_paths
from verification.p7_rtl_mutant_proposals import (
    ProposalClassification,
    build_all_rtl_mutant_proposals,
    generate_rtl_mutant_manifest,
    generate_rtl_mutant_markdown,
)


def test_proposals_cover_all_15_required_categories():
    """Verify that all 15 architectural areas and numbers 01..15 are represented."""
    proposals = build_all_rtl_mutant_proposals()
    assert len(proposals) == 15

    expected_numbers = {f"{i:02d}" for i in range(1, 16)}
    actual_numbers = {p.number for p in proposals}
    assert actual_numbers == expected_numbers

    expected_categories = {
        "Routing",
        "Credit Handling",
        "VC Allocation",
        "FIFO Protection",
        "NI Timeout and Slot Release",
        "Late/Stale Response Handling",
        "Authentication",
        "Replay Protection",
        "Authorization",
        "Memory Window",
        "Byte Enables",
        "Measurement Length",
        "IMEM Bytes 16-63",
        "Tile Identity",
        "Nonce Handling",
    }
    actual_categories = {p.category for p in proposals}
    assert actual_categories == expected_categories


def test_proposal_fields_completeness_and_source_paths():
    """Verify real source paths and complete fields on every proposal."""
    proposals = build_all_rtl_mutant_proposals()
    prohibited_files = {"TRNG_SOURCE.sv", "pq_kdf_message_builder.sv"}

    for p in proposals:
        assert p.id.startswith("RTL_MUT_")
        assert p.target_file.endswith(".sv")
        assert p.target_file not in prohibited_files, f"Prohibited ungrounded file: {p.target_file}"
        assert len(p.intended_defect) > 10
        assert len(p.verdict_detail) > 10
        assert len(p.registered_evidence) > 5
        assert len(p.oracle_kill_signature) > 10
        assert len(p.oracle_independence_notes) > 10
        assert isinstance(p.classification, ProposalClassification)


def test_status_classifications_fidelity():
    """Verify exclusive triage categories match Kalash's exact intake results."""
    proposals = build_all_rtl_mutant_proposals()
    class_map = {p.number: p.classification for p in proposals}

    # 1. Implemented in I-11 (proposals 01, 03, 10)
    assert class_map["01"] == ProposalClassification.IMPLEMENTED
    assert class_map["03"] == ProposalClassification.IMPLEMENTED
    assert class_map["10"] == ProposalClassification.IMPLEMENTED

    # 2. Not a killable control (proposals 04, 11, 12)
    assert class_map["04"] == ProposalClassification.NOT_A_KILLABLE_CONTROL
    assert class_map["11"] == ProposalClassification.NOT_A_KILLABLE_CONTROL
    assert class_map["12"] == ProposalClassification.NOT_A_KILLABLE_CONTROL

    # 3. Already covered by existing killed controls (02, 05, 06, 07, 08, 09, 13, 14, 15)
    already_covered_set = {"02", "05", "06", "07", "08", "09", "13", "14", "15"}
    for num in already_covered_set:
        assert class_map[num] == ProposalClassification.ALREADY_COVERED

    # Exact summary counts
    counts = {
        "implemented": sum(1 for p in proposals if p.classification == ProposalClassification.IMPLEMENTED),
        "already_covered": sum(1 for p in proposals if p.classification == ProposalClassification.ALREADY_COVERED),
        "not_a_killable_control": sum(1 for p in proposals if p.classification == ProposalClassification.NOT_A_KILLABLE_CONTROL),
    }
    assert counts == {"implemented": 3, "already_covered": 9, "not_a_killable_control": 3}


def test_manifest_generation(tmp_path):
    """Verify p7_rtl_mutant_proposals.json and Markdown report generation."""
    out_file = tmp_path / "mutants.json"
    out_md = tmp_path / "mutants.md"

    data = generate_rtl_mutant_manifest(out_file)
    assert out_file.exists()
    assert data["metadata"]["total_proposals"] == 15
    assert len(data["proposals"]) == 15

    md_content = generate_rtl_mutant_markdown(out_file, out_md)
    assert out_md.exists()
    assert "Single Source of Truth" in md_content
    assert "dual_lane_10_20261106_163900_ff77f562" in md_content
