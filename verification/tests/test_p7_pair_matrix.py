"""
Unit and Regression Tests for PQ-Attest P7 Directed Pair Matrix
(Brief v2 Step 3)

Tests:
  A. Exact pair count (30 directed pairs, no self-pairs)
  B. Six independent self-pair rejections (0->0, 1->1, 2->2, 3->3, 4->4, 5->5)
  C. Invalid tile IDs (negative, out-of-range, non-integer types)
  D. Duplicate detection (injected duplicate fails validation, generator produces 0)
  E. Missing-pair detection (removed pair detected and reported in diagnostics)
  F. Reverse-direction distinction (e.g. 0->1 vs 1->0 are distinct and preserved)
  G. Coverage metrics and calculations (100% on complete matrix, penalized if flawed)
  H. Route oracle and topology consistency with RTL (NOC_PKG.sv, NOC_XY_ROUTING.sv)
  I. Generated JSON artifact validation
"""

import json
from pathlib import Path
import pytest

from verification.p7_pair_matrix import (
    P7Topology,
    PairMatrixGenerator,
    DirectedPairRecord,
    InvalidTileIdError,
    SelfPairRejectedError,
    compute_xy_route,
    compute_relative_direction,
    find_repo_root,
)


@pytest.fixture
def generator() -> PairMatrixGenerator:
    return PairMatrixGenerator()


# ==============================================================================
# Requirement A: Exact Pair Count
# ==============================================================================

def test_exact_pair_count(generator: PairMatrixGenerator):
    """Test that exactly 30 legal directed pairs are generated."""
    pairs = generator.generate_matrix(include_route=True)
    assert len(pairs) == 30, f"Expected 30 pairs, got {len(pairs)}"

    # Check non-self invariant on every pair
    for p in pairs:
        assert p.source_tile != p.destination_tile, (
            f"Self-pair leaked into generated matrix: {p.pair_id}"
        )
        assert p.validation_status == "VALID"
        assert p.pair_id == f"T{p.source_tile}_TO_T{p.destination_tile}"


# ==============================================================================
# Requirement B: Six Independent Self-Pair Rejections
# ==============================================================================

@pytest.mark.parametrize("tile_id", [0, 1, 2, 3, 4, 5])
def test_explicit_self_pair_rejection(generator: PairMatrixGenerator, tile_id: int):
    """Independently assert that self-pair (i -> i) is rejected with SelfPairRejectedError."""
    with pytest.raises(SelfPairRejectedError) as exc_info:
        generator.validate_pair_request(tile_id, tile_id)

    assert f"source tile {tile_id} == destination tile {tile_id}" in str(exc_info.value)

    # Also test via generate_single_pair
    with pytest.raises(SelfPairRejectedError):
        generator.generate_single_pair(tile_id, tile_id)


def test_all_six_self_pairs_rejected_count(generator: PairMatrixGenerator):
    """Confirm all 6 self-pairs fail validation."""
    rejected_count = 0
    for t in range(6):
        try:
            generator.validate_pair_request(t, t)
        except SelfPairRejectedError:
            rejected_count += 1

    assert rejected_count == 6


# ==============================================================================
# Requirement C: Invalid Tile IDs
# ==============================================================================

def test_negative_source_tile(generator: PairMatrixGenerator):
    """Test that negative source tile is rejected."""
    with pytest.raises(InvalidTileIdError) as exc:
        generator.validate_pair_request(-1, 2)
    assert "out of valid range" in str(exc.value)


def test_source_tile_greater_than_max(generator: PairMatrixGenerator):
    """Test that source tile >= 6 is rejected."""
    with pytest.raises(InvalidTileIdError) as exc:
        generator.validate_pair_request(6, 2)
    assert "out of valid range" in str(exc.value)

    with pytest.raises(InvalidTileIdError):
        generator.validate_pair_request(99, 2)


def test_negative_destination_tile(generator: PairMatrixGenerator):
    """Test that negative destination tile is rejected."""
    with pytest.raises(InvalidTileIdError) as exc:
        generator.validate_pair_request(0, -1)
    assert "out of valid range" in str(exc.value)


def test_destination_tile_greater_than_max(generator: PairMatrixGenerator):
    """Test that destination tile >= 6 is rejected."""
    with pytest.raises(InvalidTileIdError) as exc:
        generator.validate_pair_request(0, 6)
    assert "out of valid range" in str(exc.value)

    with pytest.raises(InvalidTileIdError):
        generator.validate_pair_request(0, 100)


@pytest.mark.parametrize("invalid_val", ["0", "1", None, 1.5, True, False, [0]])
def test_invalid_tile_types(generator: PairMatrixGenerator, invalid_val):
    """Confirm that non-integer types are rejected and not silently coerced."""
    with pytest.raises(InvalidTileIdError):
        generator.validate_pair_request(invalid_val, 1)

    with pytest.raises(InvalidTileIdError):
        generator.validate_pair_request(0, invalid_val)


# ==============================================================================
# Requirement D: Duplicate Detection
# ==============================================================================

def test_generator_produces_no_duplicates(generator: PairMatrixGenerator):
    """Ensure the generator produces zero duplicate ordered pairs."""
    pairs = generator.generate_matrix()
    duplicates = generator.detect_duplicates(pairs)
    assert len(duplicates) == 0, f"Found unexpected duplicates: {duplicates}"


def test_injected_duplicate_detected(generator: PairMatrixGenerator):
    """Inject a duplicate ordered pair and confirm detection."""
    pairs = generator.generate_matrix()
    # Inject a duplicate of T0_TO_T1
    dup_pair = generator.generate_single_pair(0, 1)
    corrupted_pairs = list(pairs) + [dup_pair]

    duplicates = generator.detect_duplicates(corrupted_pairs)
    assert len(duplicates) == 1
    assert duplicates[0] == (0, 1)

    cov = generator.calculate_coverage(corrupted_pairs)
    assert cov["duplicate_legal_pairs"] == 1
    assert "T0_TO_T1" in cov["duplicate_pairs_list"]
    assert not cov["is_complete"]


# ==============================================================================
# Requirement E: Missing-Pair Detection
# ==============================================================================

def test_missing_pair_detection(generator: PairMatrixGenerator):
    """Remove legal pairs and verify detection in diagnostics."""
    pairs = generator.generate_matrix()

    # Drop T2_TO_T5 and T4_TO_T1
    incomplete = [p for p in pairs if p.pair_id not in ("T2_TO_T5", "T4_TO_T1")]
    assert len(incomplete) == 28

    missing = generator.detect_missing_pairs(incomplete)
    assert len(missing) == 2
    assert (2, 5) in missing
    assert (4, 1) in missing

    cov = generator.calculate_coverage(incomplete)
    assert cov["missing_legal_pairs"] == 2
    assert "T2_TO_T5" in cov["missing_pairs_list"]
    assert "T4_TO_T1" in cov["missing_pairs_list"]
    assert cov["unique_legal_pairs"] == 28
    assert cov["coverage_percentage"] == round((28 / 30) * 100.0, 2)
    assert not cov["is_complete"]


# ==============================================================================
# Requirement F: Reverse-Direction Distinction
# ==============================================================================

def test_reverse_direction_distinction(generator: PairMatrixGenerator):
    """
    Verify that reverse-direction pairs (e.g. 0->1 and 1->0) are distinct:
      - Different pair IDs
      - Both present in generated matrix
      - Opposite or distinct routing hops
      - Never conflated into an unordered combination
    """
    pairs = generator.generate_matrix(include_route=True)
    pair_map = {p.pair_id: p for p in pairs}

    # Test T0_TO_T1 vs T1_TO_T0
    assert "T0_TO_T1" in pair_map
    assert "T1_TO_T0" in pair_map
    p01 = pair_map["T0_TO_T1"]
    p10 = pair_map["T1_TO_T0"]

    assert p01.pair_id != p10.pair_id
    assert p01.source_tile == 0 and p01.destination_tile == 1
    assert p10.source_tile == 1 and p10.destination_tile == 0
    assert p01.expected_route == ["EAST"]
    assert p10.expected_route == ["WEST"]

    # Verify for all 15 unordered combinations that both directed pairs exist
    for src in range(6):
        for dest in range(src + 1, 6):
            fwd_id = f"T{src}_TO_T{dest}"
            rev_id = f"T{dest}_TO_T{src}"

            assert fwd_id in pair_map, f"Missing forward pair {fwd_id}"
            assert rev_id in pair_map, f"Missing reverse pair {rev_id}"

            fwd = pair_map[fwd_id]
            rev = pair_map[rev_id]

            assert fwd.pair_id != rev.pair_id
            assert fwd.direction != rev.direction


# ==============================================================================
# Requirement G: Coverage Calculations
# ==============================================================================

def test_complete_coverage_metrics(generator: PairMatrixGenerator):
    """Verify that complete matrix achieves exact 100% coverage with 0 defects."""
    pairs = generator.generate_matrix()
    cov = generator.calculate_coverage(pairs)

    assert cov["expected_legal_pairs"] == 30
    assert cov["generated_legal_pairs"] == 30
    assert cov["unique_legal_pairs"] == 30
    assert cov["missing_legal_pairs"] == 0
    assert cov["duplicate_legal_pairs"] == 0
    assert cov["self_pairs_accepted"] == 0
    assert cov["coverage_percentage"] == 100.0
    assert cov["is_complete"] is True


def test_coverage_penalization_on_self_pair(generator: PairMatrixGenerator):
    """Verify coverage calculation is not 100% if a self-pair is improperly included."""
    pairs = generator.generate_matrix()
    # Maliciously craft a self pair record
    bad_self = DirectedPairRecord(
        pair_id="T0_TO_T0",
        source_tile=0,
        destination_tile=0,
        source_role="CPU0",
        destination_role="CPU0",
        source_coordinates={"x": 0, "y": 0},
        destination_coordinates={"x": 0, "y": 0},
        direction="LOCAL",
        expected_route=[],
        validation_status="INVALID",
    )
    corrupted = pairs + [bad_self]
    cov = generator.calculate_coverage(corrupted)
    assert cov["self_pairs_accepted"] == 1
    assert cov["is_complete"] is False


# ==============================================================================
# Requirement H: Topology and Routing Oracle Consistency
# ==============================================================================

def test_topology_matches_noc_pkg_declarations():
    """Verify topology coordinates and roles match NOC_PKG.sv."""
    expected_mapping = {
        0: ("TILE_CPU0", "CPU0", 0, 0),
        1: ("TILE_CPU1", "CPU1", 1, 0),
        2: ("TILE_MEMORY", "MEMORY", 2, 0),
        3: ("TILE_CRYPTO", "CRYPTO", 0, 1),
        4: ("TILE_ROT", "RoT", 1, 1),
        5: ("TILE_SPOOF", "SPOOF", 2, 1),
    }

    assert P7Topology.MESH_X == 3
    assert P7Topology.MESH_Y == 2
    assert P7Topology.NUM_TILES == 6

    for tid, (name, role, x, y) in expected_mapping.items():
        tile = P7Topology.get_tile(tid)
        assert tile.name == name
        assert tile.role == role
        assert tile.coord.x == x
        assert tile.coord.y == y
        assert P7Topology.tile_to_coord(tid) == tile.coord


def test_dimension_order_xy_route_properties():
    """
    Verify dimension-order routing invariants:
      - X dimension resolved first
      - Once Y resolution starts, X hops never re-occur
    """
    for src in range(6):
        src_coord = P7Topology.tile_to_coord(src)
        for dest in range(6):
            if src == dest:
                continue
            dest_coord = P7Topology.tile_to_coord(dest)
            hops = compute_xy_route(src_coord, dest_coord)

            assert len(hops) > 0

            # Verify no X hop after a Y hop
            seen_y_hop = False
            for hop in hops:
                if hop in ("NORTH", "SOUTH"):
                    seen_y_hop = True
                elif hop in ("EAST", "WEST"):
                    assert not seen_y_hop, (
                        f"Route {src_coord} -> {dest_coord} violated XY dimension ordering: {hops}"
                    )


# ==============================================================================
# Requirement I: Generated JSON Artifact Verification
# ==============================================================================

def test_generated_manifest_artifact(generator: PairMatrixGenerator):
    """Verify the generated JSON artifact exists and matches all specifications."""
    repo_root = find_repo_root()
    manifest_path = repo_root / "verification" / "generated" / "p7_pair_matrix.json"

    # Generate freshly to test generator method
    manifest = generator.generate_manifest_artifact(manifest_path)

    assert manifest_path.exists()
    with open(manifest_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    assert data["schema_version"] == "1.0.0"
    assert data["generator"] == "verification.p7_pair_matrix"
    assert "source_revision" in data
    assert "source_files" in data
    assert "noc_pkg" in data["source_files"]
    assert "noc_xy_routing" in data["source_files"]

    assert data["metrics"]["expected_pair_count"] == 30
    assert data["metrics"]["generated_pair_count"] == 30
    assert data["metrics"]["unique_pair_count"] == 30
    assert data["metrics"]["missing_pair_count"] == 0
    assert data["metrics"]["duplicate_pair_count"] == 0
    assert data["metrics"]["self_pair_rejection_count"] == 6
    assert data["metrics"]["coverage_percentage"] == 100.0

    assert data["validation_summary"]["status"] == "PASS"
    assert len(data["pairs"]) == 30

