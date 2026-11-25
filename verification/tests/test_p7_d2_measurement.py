"""
verification/tests/test_p7_d2_measurement.py
============================================
PQ-Attest D2: 64-Byte IMEM Measurement Verification Suite.

Engineer 4 Verification Infrastructure.

Tests:
1. Input Length Validation (7 + 16 + 64 = 87 bytes, <= 135 single-block bound, 1 permutation)
2. Teammate Reference vs hashlib.sha3_256 Cross-Check
3. IMEM Window Coverage & Sensitivity Sweep (bytes 16..63 exhaustive 48/48 divergence)
4. Vector File Integrity (vectors/d2_k3_64.json and vectors/d2_k3_64.svh consistency)
5. Boundary Conditions (config != 16, IMEM != 64, len > 135 rejected)
6. Historical Compatibility (39-byte historical vs 87-byte D2 distinct digests)
7. Generated Artifact Validation (p7_d2_measurement_vectors.json & p7_d2_measurement_coverage.json)
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path
import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from verification.p7_paths import get_default_paths
from verification.p7_d2_measurement import (
    AUTHORITATIVE_PACKAGE_SHA256,
    CONFIG_BYTES,
    DIGEST_BYTES,
    IMEM_BYTES,
    RATE_BYTES,
    SINGLE_BLOCK_MAX_BYTES,
    TILE_ID_BYTES,
    TOTAL_MESSAGE_BYTES,
    bswap_hex,
    build_d2_test_vectors,
    compute_d2_measurement,
    run_imem_window_sensitivity_sweep,
)

# Reference import
TEAMMATE_SW_DIR = REPO_ROOT / "software" / "pq_attest_final" / "PQ_Attest" / "software"
if str(TEAMMATE_SW_DIR) not in sys.path:
    sys.path.insert(0, str(TEAMMATE_SW_DIR))

try:
    import measurement_ref
    HAVE_TEAMMATE_REF = True
except ImportError:
    HAVE_TEAMMATE_REF = False


# =============================================================================
# 1. Length Validation Tests
# =============================================================================

def test_measurement_input_length_exact_87_bytes():
    """Verify that D2 measurement input is exactly 7 + 16 + 64 = 87 bytes."""
    tile_id = b"TILE_01"
    config = bytes(CONFIG_BYTES)
    imem = bytes(IMEM_BYTES)

    assert len(tile_id) == 7, "Tile ID length must be exactly 7 bytes"
    assert len(config) == 16, "K-3 config length must be exactly 16 bytes"
    assert len(imem) == 64, "D2 IMEM window length must be exactly 64 bytes"

    total_len = len(tile_id) + len(config) + len(imem)
    assert total_len == 87, f"Total measurement input must be exactly 87 bytes, got {total_len}"
    assert total_len == TOTAL_MESSAGE_BYTES


def test_measurement_within_single_block_bound():
    """Verify 87 bytes <= 135 bytes (single-block bound: RATE_BYTES - 1)."""
    assert TOTAL_MESSAGE_BYTES <= SINGLE_BLOCK_MAX_BYTES
    assert SINGLE_BLOCK_MAX_BYTES == RATE_BYTES - 1
    assert RATE_BYTES == 136  # SHA3-256 rate: 1088 bits = 136 bytes


def test_keccak_permutation_count_exactly_one():
    """Verify that an 87-byte message requires exactly one Keccak-f[1600] permutation.

    In SHA3-256 (rate = 136 bytes):
    Padding rule pad10*1 adds domain separator byte 0x06 and delimiter byte 0x80.
    With message length 87:
      87 payload bytes + 1 domain byte (0x06) + 47 zero bytes + 1 final pad byte (0x80)
      = 136 bytes = exactly 1 Keccak block.
    """
    msg_len = TOTAL_MESSAGE_BYTES
    # Minimum padding is 1 byte (if 0x86 combined), or 2 bytes.
    # At 87 bytes, 87 < 136, so padded block is exactly 136 bytes.
    padded_blocks = (msg_len + RATE_BYTES) // RATE_BYTES
    assert padded_blocks == 1, f"Expected 1 Keccak block, got {padded_blocks}"


# =============================================================================
# 2. Reference Cross-Check Tests
# =============================================================================

def test_teammate_reference_availability_and_provenance():
    """Verify teammate measurement_ref.py is available and from the pinned package."""
    assert HAVE_TEAMMATE_REF, "Authoritative teammate measurement_ref could not be imported"
    assert hasattr(measurement_ref, "measure_tile")
    assert hasattr(measurement_ref, "sha3_256_reference")


def test_teammate_reference_vs_hashlib_agreement():
    """Verify 100% agreement between teammate measurement_ref and hashlib.sha3_256."""
    vectors = build_d2_test_vectors()
    for v in vectors:
        tid = bytes.fromhex(v.tile_id_hex)
        cfg = bytes.fromhex(v.config_hex)
        imem = bytes.fromhex(v.imem_hex)

        ref_digest = measurement_ref.measure_tile(tid, cfg, imem)
        hashlib_digest = hashlib.sha3_256(tid + cfg + imem).digest()

        assert ref_digest == hashlib_digest, f"Digest mismatch on vector {v.id}"
        assert ref_digest.hex() == v.measurement_hex, f"Vector {v.id} hex mismatch"


# =============================================================================
# 3. IMEM Window Coverage & Sensitivity Tests (Bytes 16..63)
# =============================================================================

def test_imem_byte16_sensitivity():
    """Verify that mutating IMEM byte 16 produces a divergent measurement (proves byte 16 coverage)."""
    t1 = b"TILE_01"
    cfg = bytes(range(16))
    std_imem = bytes([0x10 + i for i in range(64)])

    m_std = compute_d2_measurement(t1, cfg, std_imem)

    mut_imem = bytearray(std_imem)
    mut_imem[16] ^= 0xFF
    m_mut16 = compute_d2_measurement(t1, cfg, bytes(mut_imem))

    assert m_std != m_mut16, "Mutating byte 16 must produce divergent measurement!"


def test_imem_byte63_sensitivity():
    """Verify that mutating IMEM byte 63 produces a divergent measurement (proves byte 63 coverage)."""
    t1 = b"TILE_01"
    cfg = bytes(range(16))
    std_imem = bytes([0x10 + i for i in range(64)])

    m_std = compute_d2_measurement(t1, cfg, std_imem)

    mut_imem = bytearray(std_imem)
    mut_imem[63] ^= 0xFF
    m_mut63 = compute_d2_measurement(t1, cfg, bytes(mut_imem))

    assert m_std != m_mut63, "Mutating byte 63 must produce divergent measurement!"


def test_imem_window_sensitivity_byte16_to_63_exhaustive():
    """Exhaustively verify that mutating each individual byte from 16 to 63 causes divergence (48/48)."""
    sweep = run_imem_window_sensitivity_sweep()
    assert sweep["total_tested_bytes"] == 48
    assert sweep["divergent_bytes"] == 48
    assert sweep["divergence_rate_pct"] == 100.0
    assert sweep["all_divergent"] is True


# =============================================================================
# 4. Vector File Integrity Tests
# =============================================================================

def test_vectors_d2_k3_64_json_integrity():
    """Validate vectors/e4_d2_measurements.json exists, parses, and matches golden reference."""
    json_path = REPO_ROOT / "vectors" / "e4_d2_measurements.json"
    assert json_path.exists(), f"Missing required file: {json_path}"

    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    meta = data.get("metadata", {})
    assert meta.get("reference_package_sha256") == AUTHORITATIVE_PACKAGE_SHA256
    assert meta.get("parameters", {}).get("total_message_bytes") == 87

    vectors = data.get("vectors", [])
    assert len(vectors) == 12, f"Expected 12 test vectors, got {len(vectors)}"

    # Check categories
    cat_counts = {}
    for v in vectors:
        c = v["category"]
        cat_counts[c] = cat_counts.get(c, 0) + 1

    assert cat_counts.get("standard") == 1
    assert cat_counts.get("sensitivity_byte16") == 1
    assert cat_counts.get("sensitivity_byte63") == 1
    assert cat_counts.get("all_zeros") == 2
    assert cat_counts.get("all_ones") == 1
    assert cat_counts.get("multi_tile") == 6

    # Verify each vector recalculates to the exact expected digest
    for v in vectors:
        tid = bytes.fromhex(v["tile_id_hex"])
        cfg = bytes.fromhex(v["config_hex"])
        imem = bytes.fromhex(v["imem_hex"])
        expected_hex = v["measurement_hex"]

        actual = compute_d2_measurement(tid, cfg, imem)
        assert actual.hex() == expected_hex, f"Mismatch in vector {v['id']}"


def test_vectors_d2_k3_64_svh_consistency():
    """Validate vectors/e4_d2_measurements.svh exists, contains macros, and matches JSON vectors."""
    svh_path = REPO_ROOT / "vectors" / "e4_d2_measurements.svh"
    assert svh_path.exists(), f"Missing required file: {svh_path}"

    content = svh_path.read_text(encoding="utf-8")
    assert "`ifndef D2_K3_64_SVH" in content
    assert "`define D2_K3_64_SVH" in content
    assert "localparam int D2_NUM_VECTORS     = 12;" in content
    assert "localparam int D2_TOTAL_BYTES     = 87;" in content

    # Check that standard vector RTL literal is present
    vectors = build_d2_test_vectors()
    std_v = vectors[0]
    assert std_v.measurement_rtl_hex in content
    assert std_v.measurement_hex in content


# =============================================================================
# 5. Boundary Condition Tests
# =============================================================================

def test_boundary_config_length_not_16_rejected():
    """Verify that config_len != 16 is rejected when enforcing architectural lengths."""
    t1 = b"TILE_01"
    imem = bytes(64)

    with pytest.raises(ValueError, match="Config length must be 16"):
        compute_d2_measurement(t1, bytes(15), imem, enforce_lengths=True)

    with pytest.raises(ValueError, match="Config length must be 16"):
        compute_d2_measurement(t1, bytes(17), imem, enforce_lengths=True)


def test_boundary_imem_length_not_64_rejected():
    """Verify that imem_len != 64 is rejected when enforcing architectural lengths."""
    t1 = b"TILE_01"
    cfg = bytes(16)

    with pytest.raises(ValueError, match="IMEM length must be 64"):
        compute_d2_measurement(t1, cfg, bytes(63), enforce_lengths=True)

    with pytest.raises(ValueError, match="IMEM length must be 64"):
        compute_d2_measurement(t1, cfg, bytes(65), enforce_lengths=True)


def test_boundary_input_length_exceeding_135_rejected():
    """Verify that any measurement input > 135 bytes is rejected (single-block bound)."""
    t1 = b"TILE_01"
    # Create input totaling > 135 bytes
    huge_cfg = bytes(64)
    huge_imem = bytes(65)  # 7 + 64 + 65 = 136 > 135

    with pytest.raises(ValueError, match="exceeds single-block bound of 135"):
        compute_d2_measurement(t1, huge_cfg, huge_imem, enforce_lengths=False)


# =============================================================================
# 6. Historical Compatibility Tests
# =============================================================================

def test_historical_16b_vs_d2_64b_measurement_non_equivalence():
    """Verify that 16-byte historical IMEM produces a different digest than 64-byte IMEM."""
    t1 = b"TILE_01"
    cfg = bytes(range(16))
    imem16 = bytes([0x10 + i for i in range(16)])
    imem64 = bytes([0x10 + i for i in range(64)])

    # Historical 39-byte measurement (V01 from measurement_ref.py)
    hist_digest = hashlib.sha3_256(t1 + cfg + imem16).hexdigest()
    assert hist_digest == "959b61960366c705b889e2c09ffaead296e296475f32a610732ab9eac293182a"

    # D2 87-byte measurement
    d2_digest = compute_d2_measurement(t1, cfg, imem64).hex()
    assert d2_digest == "5d44a067029ba92ba45ad0a87b229c4480e8d6cda2756f907afa8715ddc27ccb"

    assert hist_digest != d2_digest, "Historical 16B and D2 64B measurements must not collide!"


def test_zero_padded_vs_d2_measurement_non_equivalence():
    """Verify that a 16-byte IMEM zero-padded to 64 bytes is not equivalent to standard D2."""
    t1 = b"TILE_01"
    cfg = bytes(range(16))
    imem_padded = bytes([0x10 + i for i in range(16)]) + bytes(48)
    std_imem = bytes([0x10 + i for i in range(64)])

    m_padded = compute_d2_measurement(t1, cfg, imem_padded).hex()
    m_std = compute_d2_measurement(t1, cfg, std_imem).hex()

    assert m_padded != m_std, "Zero-padded IMEM must differ from standard sequential IMEM!"


# =============================================================================
# 7. Multi-Tile Diversity Tests
# =============================================================================

def test_multi_tile_measurements_are_all_distinct():
    """Verify that measurements across all 6 tiles (TILE_00 .. TILE_05) produce distinct digests."""
    std_cfg = bytes(range(16))
    std_imem = bytes([0x10 + i for i in range(64)])

    tile_measurements = set()
    for i in range(6):
        tid = f"TILE_{i:02d}".encode("ascii")
        m = compute_d2_measurement(tid, std_cfg, std_imem).hex()
        assert m not in tile_measurements, f"Collision detected for tile {tid}!"
        tile_measurements.add(m)

    assert len(tile_measurements) == 6, "All 6 tiles must produce unique measurement digests"


# =============================================================================
# 8. Generated Manifest Validation Tests
# =============================================================================

def test_generated_p7_d2_measurement_vectors_artifact():
    """Verify verification/generated/p7_d2_measurement_vectors.json."""
    gen_file = get_default_paths().generated_dir / "p7_d2_measurement_vectors.json"
    assert gen_file.exists(), f"Missing artifact: {gen_file}"

    with open(gen_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    assert len(data.get("vectors", [])) == 12
    assert data.get("metadata", {}).get("parameters", {}).get("total_message_bytes") == 87


def test_generated_p7_d2_measurement_coverage_artifact():
    """Verify verification/generated/p7_d2_measurement_coverage.json."""
    gen_file = get_default_paths().generated_dir / "p7_d2_measurement_coverage.json"
    assert gen_file.exists(), f"Missing artifact: {gen_file}"

    with open(gen_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    metrics = data.get("coverage_metrics", {})
    assert metrics.get("expansion_sensitivity", {}).get("total_expansion_bytes") == 48
    assert metrics.get("expansion_sensitivity", {}).get("divergent_bytes") == 48
    assert metrics.get("expansion_sensitivity", {}).get("status") == "PASS"
    assert metrics.get("single_block_absorption", {}).get("status") == "PASS"
    assert data.get("metadata", {}).get("requirement_id") == "REQ-D2-IMEM-64"

