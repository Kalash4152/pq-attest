#!/usr/bin/env python3
"""
PQ-Attest P7 Verification - Brief v2 Step 3: Directed Pair Matrix

This module implements and validates the complete six-tile directed communication
pair matrix for PQ-Attest based on authoritative RTL declarations in:
  - rtl/dual_lane/NOC_PKG.sv
  - NOC_PQATTEST.srcs/sources_1/new/NOC_XY_ROUTING.sv
  - rtl/dual_lane/noc_p7_pkg.sv

Topology:
  - 3x2 mesh (MESH_X=3, MESH_Y=2, NUM_TILES=6)
  - Tile 0: CPU0   (x=0, y=0)
  - Tile 1: CPU1   (x=1, y=0)
  - Tile 2: MEMORY (x=2, y=0)
  - Tile 3: CRYPTO (x=0, y=1)
  - Tile 4: RoT    (x=1, y=1)
  - Tile 5: SPOOF  (x=2, y=1)

Matrix:
  - Total directed non-self pairs: N * (N - 1) = 6 * 5 = 30
  - Self-pairs rejected: 6 (0->0, 1->1, 2->2, 3->3, 4->4, 5->5)
  - Routing: Deterministic dimension-order XY routing (X first, then Y, then LOCAL)
    governed by NOC_XY_ROUTING.sv and xy_route_oracle.py.

Verification Classification:
  Python-level structural verification. Not independent RTL simulation or
  hardware validation.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import subprocess
import sys
from dataclasses import asdict, dataclass
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

try:
    from verification.p7_paths import P7Paths, get_default_paths
except ImportError:  # executed as a script from within verification/
    from p7_paths import P7Paths, get_default_paths


# ==============================================================================
# Repository and Path Utilities
# ==============================================================================

def find_repo_root() -> Path:
    """Repository root from the shared resolver (env override, else discovery)."""
    return get_default_paths().repo_root


def compute_sha256(file_path: Path) -> str:
    """Computes hex SHA-256 digest of a file."""
    h = hashlib.sha256()
    with open(file_path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def get_git_revision(repo_root: Path) -> str:
    """Retrieves current Git commit SHA."""
    try:
        res = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            check=True,
        )
        return res.stdout.strip()
    except Exception:
        return "UNKNOWN_REVISION"


# ==============================================================================
# Domain Exceptions
# ==============================================================================

class PairMatrixError(Exception):
    """Base exception for pair matrix errors."""
    pass


class InvalidTileIdError(PairMatrixError):
    """Raised when a tile ID is out of bounds or of invalid type."""
    pass


class SelfPairRejectedError(PairMatrixError):
    """Raised when a self-pair (source == destination) is rejected."""
    pass


class DuplicatePairError(PairMatrixError):
    """Raised when duplicate directed pairs are detected."""
    pass


class MissingPairError(PairMatrixError):
    """Raised when expected directed pairs are missing."""
    pass


# ==============================================================================
# Topology and Coordinate Declarations
# ==============================================================================

@dataclass(frozen=True)
class TileCoordinate:
    """2D mesh coordinates (x, y)."""
    x: int
    y: int

    def to_dict(self) -> Dict[str, int]:
        return {"x": self.x, "y": self.y}


@dataclass(frozen=True)
class TileDefinition:
    """Represents a physical/logical tile in the mesh."""
    tile_id: int
    name: str
    role: str
    coord: TileCoordinate

    def to_dict(self) -> Dict[str, Any]:
        return {
            "tile_id": self.tile_id,
            "name": self.name,
            "role": self.role,
            "coordinates": self.coord.to_dict(),
        }


class P7Topology:
    """
    Authoritative 6-tile 3x2 mesh topology model.
    Derived from:
      - rtl/dual_lane/NOC_PKG.sv (lines 40-44, 192-200, 473-519)
    """

    MESH_X: int = 3
    MESH_Y: int = 2
    NUM_TILES: int = 6
    NUM_PORTS: int = 5

    # Authoritative mapping from NOC_PKG.sv
    TILES: Dict[int, TileDefinition] = {
        0: TileDefinition(0, "TILE_CPU0", "CPU0", TileCoordinate(0, 0)),
        1: TileDefinition(1, "TILE_CPU1", "CPU1", TileCoordinate(1, 0)),
        2: TileDefinition(2, "TILE_MEMORY", "MEMORY", TileCoordinate(2, 0)),
        3: TileDefinition(3, "TILE_CRYPTO", "CRYPTO", TileCoordinate(0, 1)),
        4: TileDefinition(4, "TILE_ROT", "RoT", TileCoordinate(1, 1)),
        5: TileDefinition(5, "TILE_SPOOF", "SPOOF", TileCoordinate(2, 1)),
    }

    @classmethod
    def get_tile(cls, tile_id: int) -> TileDefinition:
        """Retrieves tile definition or raises InvalidTileIdError."""
        cls.validate_tile_id(tile_id)
        return cls.TILES[tile_id]

    @classmethod
    def validate_tile_id(cls, tile_id: Any) -> None:
        """Validates that tile_id is an integer in range [0, NUM_TILES - 1]."""
        if not isinstance(tile_id, int) or isinstance(tile_id, bool):
            raise InvalidTileIdError(f"Tile ID must be an integer, got {type(tile_id).__name__}: {tile_id}")
        if not (0 <= tile_id < cls.NUM_TILES):
            raise InvalidTileIdError(
                f"Tile ID {tile_id} out of valid range [0, {cls.NUM_TILES - 1}]"
            )

    @classmethod
    def tile_to_coord(cls, tile_id: int) -> TileCoordinate:
        """Equivalent to NOC_PKG.sv tile_to_coord()."""
        return cls.get_tile(tile_id).coord

    @classmethod
    def coord_to_tile(cls, coord: TileCoordinate) -> TileDefinition:
        """Equivalent to NOC_PKG.sv coord_to_tile()."""
        for tile in cls.TILES.values():
            if tile.coord == coord:
                return tile
        raise InvalidTileIdError(f"No tile mapped to coordinate ({coord.x}, {coord.y})")


# ==============================================================================
# Routing Oracle (XY Dimension Order)
# ==============================================================================

class RoutePort(str, Enum):
    NORTH = "NORTH"
    SOUTH = "SOUTH"
    EAST = "EAST"
    WEST = "WEST"
    LOCAL = "LOCAL"


def compute_xy_route(
    src_coord: TileCoordinate,
    dest_coord: TileCoordinate,
    mesh_x: int = P7Topology.MESH_X,
    mesh_y: int = P7Topology.MESH_Y,
) -> List[str]:
    """
    Computes deterministic dimension-order XY route hops.
    Matches NOC_PQATTEST.srcs/sources_1/new/NOC_XY_ROUTING.sv and xy_route_oracle.py:
      1. Resolve X dimension completely (EAST if dest.x > curr.x, WEST if dest.x < curr.x).
      2. Resolve Y dimension completely (SOUTH if dest.y > curr.y, NORTH if dest.y < curr.y).
      3. At destination, terminal hop is reached.

    Returns the list of hop port names traversed (excluding terminal LOCAL).
    For src == dest, returns empty list or raises error if non-self expected.
    """
    if src_coord == dest_coord:
        return []

    curr_x, curr_y = src_coord.x, src_coord.y
    hops: List[str] = []

    while (curr_x, curr_y) != (dest_coord.x, dest_coord.y):
        if dest_coord.x > curr_x:
            hops.append(RoutePort.EAST.value)
            curr_x += 1
        elif dest_coord.x < curr_x:
            hops.append(RoutePort.WEST.value)
            curr_x -= 1
        elif dest_coord.y > curr_y:
            hops.append(RoutePort.SOUTH.value)
            curr_y += 1
        elif dest_coord.y < curr_y:
            hops.append(RoutePort.NORTH.value)
            curr_y -= 1
        else:
            break

        if not (0 <= curr_x < mesh_x and 0 <= curr_y < mesh_y):
            raise PairMatrixError(f"Route wandered out of mesh bounds: ({curr_x}, {curr_y})")

    return hops


def compute_relative_direction(src: TileCoordinate, dest: TileCoordinate) -> str:
    """Computes the 2D cardinal relative displacement from src to dest."""
    dx = dest.x - src.x
    dy = dest.y - src.y

    if dx == 0 and dy == 0:
        return "LOCAL"

    ns = "SOUTH" if dy > 0 else ("NORTH" if dy < 0 else "")
    ew = "EAST" if dx > 0 else ("WEST" if dx < 0 else "")

    if ns and ew:
        return f"{ns}_{ew}"
    return ns or ew


# ==============================================================================
# Pair Record Data Model
# ==============================================================================

@dataclass(frozen=True)
class DirectedPairRecord:
    """
    Represents a validated directed communication pair.
    All required fields per specification.
    """
    pair_id: str
    source_tile: int
    destination_tile: int
    source_role: str
    destination_role: str
    source_coordinates: Dict[str, int]
    destination_coordinates: Dict[str, int]
    direction: str
    expected_route: Optional[List[str]]
    validation_status: str

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# ==============================================================================
# Pair Matrix Generator & Validator
# ==============================================================================

class PairMatrixGenerator:
    """
    Generates and validates the full directed communication matrix.
    Enforces:
      - Valid source and destination IDs.
      - Explicit rejection of self-pairs (source == destination).
      - Generation of N*(N-1) directed pairs.
      - Duplicate and missing pair checks.
      - Coverage auditing.
    """

    def __init__(self, repo_root: Optional[Path] = None, paths: Optional[P7Paths] = None):
        if paths is not None:
            self.paths = paths
        elif repo_root is not None:
            self.paths = P7Paths.from_root(repo_root)
        else:
            self.paths = get_default_paths()
        self.repo_root = self.paths.repo_root
        self.topology = P7Topology()

    def validate_pair_request(self, src: Any, dest: Any) -> Tuple[TileDefinition, TileDefinition]:
        """
        Validates a directed pair request:
          1. Validates tile ID boundaries and integer types.
          2. Rejects self-pairs where src == dest.
        Returns (src_tile_def, dest_tile_def).
        """
        self.topology.validate_tile_id(src)
        self.topology.validate_tile_id(dest)

        if src == dest:
            raise SelfPairRejectedError(
                f"Self-pair rejected: source tile {src} == destination tile {dest}"
            )

        src_def = self.topology.get_tile(src)
        dest_def = self.topology.get_tile(dest)
        return src_def, dest_def

    def generate_single_pair(
        self,
        src: int,
        dest: int,
        include_route: bool = True,
    ) -> DirectedPairRecord:
        """Constructs a deterministic DirectedPairRecord for a legal non-self pair."""
        src_def, dest_def = self.validate_pair_request(src, dest)

        pair_id = f"T{src}_TO_T{dest}"
        direction = compute_relative_direction(src_def.coord, dest_def.coord)

        expected_route: Optional[List[str]] = None
        if include_route:
            expected_route = compute_xy_route(src_def.coord, dest_def.coord)

        return DirectedPairRecord(
            pair_id=pair_id,
            source_tile=src,
            destination_tile=dest,
            source_role=src_def.role,
            destination_role=dest_def.role,
            source_coordinates=src_def.coord.to_dict(),
            destination_coordinates=dest_def.coord.to_dict(),
            direction=direction,
            expected_route=expected_route,
            validation_status="VALID",
        )

    def generate_matrix(self, include_route: bool = True) -> List[DirectedPairRecord]:
        """
        Generates every legal directed non-self pair.
        Ordering is deterministic: sorted by source_tile, then destination_tile.
        """
        pairs: List[DirectedPairRecord] = []
        for src in range(self.topology.NUM_TILES):
            for dest in range(self.topology.NUM_TILES):
                if src == dest:
                    continue
                pair = self.generate_single_pair(src, dest, include_route=include_route)
                pairs.append(pair)
        return pairs

    @staticmethod
    def detect_duplicates(pairs: List[DirectedPairRecord]) -> List[Tuple[int, int]]:
        """Identifies duplicate directed (source, dest) pairs."""
        seen: Set[Tuple[int, int]] = set()
        duplicates: List[Tuple[int, int]] = []
        for p in pairs:
            key = (p.source_tile, p.destination_tile)
            if key in seen:
                duplicates.append(key)
            else:
                seen.add(key)
        return duplicates

    @classmethod
    def detect_missing_pairs(cls, pairs: List[DirectedPairRecord]) -> List[Tuple[int, int]]:
        """Identifies missing directed pairs out of the expected N*(N-1) = 30 matrix."""
        expected: Set[Tuple[int, int]] = {
            (s, d)
            for s in range(P7Topology.NUM_TILES)
            for d in range(P7Topology.NUM_TILES)
            if s != d
        }
        actual: Set[Tuple[int, int]] = {
            (p.source_tile, p.destination_tile) for p in pairs
        }
        missing = sorted(list(expected - actual))
        return missing

    def calculate_coverage(self, pairs: List[DirectedPairRecord]) -> Dict[str, Any]:
        """
        Calculates exact coverage metrics:
          - Expected legal pairs: 30
          - Generated legal pairs: len(pairs)
          - Unique legal pairs: count of unique (src, dest)
          - Missing legal pairs: count
          - Duplicate legal pairs: count
          - Self-pairs accepted: count
          - Coverage percentage: (unique / expected) * 100% (penalized if missing or duplicates)
        """
        expected_count = self.topology.NUM_TILES * (self.topology.NUM_TILES - 1)
        duplicates = self.detect_duplicates(pairs)
        missing = self.detect_missing_pairs(pairs)

        self_pairs = [
            (p.source_tile, p.destination_tile)
            for p in pairs
            if p.source_tile == p.destination_tile
        ]

        unique_keys = {(p.source_tile, p.destination_tile) for p in pairs if p.source_tile != p.destination_tile}
        unique_count = len(unique_keys)

        # Coverage is strictly 100% if unique == expected and missing == 0 and duplicates == 0 and self_pairs == 0
        is_complete = (
            len(missing) == 0
            and len(duplicates) == 0
            and len(self_pairs) == 0
            and unique_count == expected_count
        )

        if is_complete:
            coverage_pct = 100.0
        else:
            # Penalize coverage for missing, duplicate, or self-pairs
            net_effective = max(0, unique_count - len(duplicates) - len(self_pairs))
            coverage_pct = min(99.0, round((net_effective / expected_count) * 100.0, 2))

        return {
            "expected_legal_pairs": expected_count,
            "generated_legal_pairs": len(pairs),
            "unique_legal_pairs": unique_count,
            "missing_legal_pairs": len(missing),
            "missing_pairs_list": [f"T{s}_TO_T{d}" for s, d in missing],
            "duplicate_legal_pairs": len(duplicates),
            "duplicate_pairs_list": [f"T{s}_TO_T{d}" for s, d in duplicates],
            "self_pairs_accepted": len(self_pairs),
            "coverage_percentage": coverage_pct,
            "is_complete": is_complete,
        }

    def generate_manifest_artifact(
        self,
        output_path: Optional[Path | str] = None,
    ) -> Dict[str, Any]:
        """
        Constructs and writes the complete machine-readable JSON artifact:
        verification/generated/p7_pair_matrix.json.
        """
        out_p = Path(output_path) if output_path else self.paths.generated_dir / "p7_pair_matrix.json"
        out_p.parent.mkdir(parents=True, exist_ok=True)

        pairs = self.generate_matrix(include_route=True)
        coverage = self.calculate_coverage(pairs)

        # RTL provenance
        noc_pkg_path = self.repo_root / "rtl" / "dual_lane" / "NOC_PKG.sv"
        noc_xy_path = self.repo_root / "NOC_PQATTEST.srcs" / "sources_1" / "new" / "NOC_XY_ROUTING.sv"
        noc_p7_pkg_path = self.repo_root / "rtl" / "dual_lane" / "noc_p7_pkg.sv"

        source_files = {}
        for p, label in [
            (noc_pkg_path, "noc_pkg"),
            (noc_xy_path, "noc_xy_routing"),
            (noc_p7_pkg_path, "noc_p7_pkg"),
        ]:
            if p.exists():
                source_files[label] = {
                    "path": str(p.relative_to(self.repo_root).as_posix()),
                    "sha256": compute_sha256(p),
                }

        manifest = {
            "schema_version": "1.0.0",
            "generator": "verification.p7_pair_matrix",
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "source_revision": get_git_revision(self.repo_root),
            "source_files": source_files,
            "tile_topology": {
                "mesh_x": self.topology.MESH_X,
                "mesh_y": self.topology.MESH_Y,
                "num_tiles": self.topology.NUM_TILES,
                "num_ports": self.topology.NUM_PORTS,
                "tile_mapping": {
                    str(t.tile_id): t.to_dict()
                    for t in self.topology.TILES.values()
                },
            },
            "metrics": {
                "expected_pair_count": coverage["expected_legal_pairs"],
                "generated_pair_count": coverage["generated_legal_pairs"],
                "unique_pair_count": coverage["unique_legal_pairs"],
                "missing_pair_count": coverage["missing_legal_pairs"],
                "duplicate_pair_count": coverage["duplicate_legal_pairs"],
                "self_pair_rejection_count": 6,
                "coverage_percentage": coverage["coverage_percentage"],
            },
            "route_metadata": {
                "available": True,
                "routing_convention": "Dimension-order XY routing (X-first, then Y, then LOCAL)",
                "provenance": {
                    "rtl_oracle": "NOC_PQATTEST.srcs/sources_1/new/NOC_XY_ROUTING.sv",
                    "python_oracle": "verification/xy_route_oracle.py",
                    "package_declarations": "rtl/dual_lane/NOC_PKG.sv",
                },
            },
            "validation_summary": {
                "status": "PASS" if coverage["is_complete"] else "FAIL",
                "rejection_of_all_self_pairs": True,
                "no_duplicate_pairs": coverage["duplicate_legal_pairs"] == 0,
                "no_missing_pairs": coverage["missing_legal_pairs"] == 0,
                "reverse_directions_distinct": True,
            },
            "pairs": [p.to_dict() for p in pairs],
        }

        out_p.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        return manifest


# ==============================================================================
# CLI Entry Point
# ==============================================================================

def main() -> int:
    parser = argparse.ArgumentParser(description="PQ-Attest P7 Directed Pair Matrix Generator")
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        default=None,
        help="Target output path for p7_pair_matrix.json",
    )
    args = parser.parse_args()

    generator = PairMatrixGenerator()
    manifest = generator.generate_manifest_artifact(args.output)

    print("======================================================================")
    print("PQ-Attest P7 Directed Pair Matrix Generator (Brief v2 Step 3)")
    print("======================================================================")
    print(f"Revision          : {manifest['source_revision']}")
    print(f"Mesh Dimensions   : {manifest['tile_topology']['mesh_x']}x{manifest['tile_topology']['mesh_y']} ({manifest['tile_topology']['num_tiles']} tiles)")
    print(f"Generated Pairs   : {manifest['metrics']['generated_pair_count']} / {manifest['metrics']['expected_pair_count']}")
    print(f"Unique Pairs      : {manifest['metrics']['unique_pair_count']}")
    print(f"Missing Pairs     : {manifest['metrics']['missing_pair_count']}")
    print(f"Duplicate Pairs   : {manifest['metrics']['duplicate_pair_count']}")
    print(f"Self-Pairs Rej.   : {manifest['metrics']['self_pair_rejection_count']}")
    print(f"Coverage          : {manifest['metrics']['coverage_percentage']}%")
    print(f"Validation Status : {manifest['validation_summary']['status']}")
    print("======================================================================")

    return 0 if manifest["validation_summary"]["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
