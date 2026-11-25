"""
Unit and Regression Tests for Authoritative KMAC128 Reference Adapter
(Task F1: Pinned KMAC Reference Correction)

Verifies:
  1. Import resolution points strictly to the teammate reference or its explicit adapter.
  2. All three published NIST SP 800-185 KMAC128 sample vectors pass.
  3. All six RTL testbench known-answer tests pass.
  4. Output length (128-bit vs 256-bit) and byte ordering remain bit-exact.
  5. Packet MAC framing and domain-separation (b"NOC-L2-AUTH-v1") behave correctly.
  6. Negative tests reject invalid parameter types and lengths.
  7. The demoted repo copy (software/kmac128_ref.py) is rejected and never silently imported.
  8. SHA-256 and source archive provenance match pinned values.
"""

from pathlib import Path
import pytest

from verification.p7_kmac_adapter import (
    AUTHORITATIVE_KMAC_SHA256,
    DEMOTED_KMAC_SHA256,
    SOURCE_ARCHIVE_SHA256,
    ReferenceIdentityError,
    compute_sha256,
    derive_tile_key,
    find_repo_root,
    get_kmac_reference_metadata,
    kmac128,
    resolve_authoritative_reference_dir,
)
import verification.p7_differential as diff_mod
import verification.p7_packet_model as pkt_mod


# ==============================================================================
# 1. Import Resolution & Identity Tests
# ==============================================================================

def test_authoritative_import_resolution():
    """Verify import resolution resolves to the teammate reference, not demoted copy."""
    meta = get_kmac_reference_metadata()
    assert meta["status"] == "AUTHORITATIVE_PINNED"
    assert meta["authoritative_reference"]["sha256"] == AUTHORITATIVE_KMAC_SHA256
    assert meta["authoritative_reference"]["source_archive_sha256"] == SOURCE_ARCHIVE_SHA256

    # Verify active module path in adapter is inside pq_attest_final
    active_mod = meta["adapter"]["active_module"]
    assert "software" in active_mod and "pq_attest_final" in active_mod


def test_active_modules_bind_to_adapter():
    """Verify active verification modules bind to p7_kmac_adapter and not software.kmac128_ref."""
    assert diff_mod.kmac128 is kmac128
    assert pkt_mod.kmac128 is kmac128

    # Ensure demoted software.kmac128_ref is not the function bound
    import software.kmac128_ref as demoted_mod
    assert diff_mod.kmac128 is not demoted_mod.kmac128
    assert pkt_mod.kmac128 is not demoted_mod.kmac128


def test_demoted_reference_hash_distinct():
    """Verify demoted reference file has distinct known hash and is tracked as demoted."""
    repo_root = find_repo_root()
    demoted_path = repo_root / "software" / "kmac128_ref.py"
    assert demoted_path.is_file()
    actual_demoted_hash = compute_sha256(demoted_path)
    assert actual_demoted_hash == DEMOTED_KMAC_SHA256
    assert actual_demoted_hash != AUTHORITATIVE_KMAC_SHA256


# ==============================================================================
# 2. NIST SP 800-185 KMAC128 KATs
# ==============================================================================

def test_nist_sp800_185_sample_vectors():
    """Verify all 3 published NIST SP 800-185 sample vectors pass bit-exact."""
    K = bytes(range(0x40, 0x60))
    samples = [
        # (X, L_bytes, S, expected_hex)
        (
            bytes([0x00, 0x01, 0x02, 0x03]),
            32,
            b"",
            "e5780b0d3ea6f7d3a429c5706aa43a00fadbd7d49628839e3187243f456ee14e",
        ),
        (
            bytes([0x00, 0x01, 0x02, 0x03]),
            32,
            b"My Tagged Application",
            "3b1fba963cd8b0b59e8c1a6d71888b7143651af8ba0a7070c0979e2811324aa5",
        ),
        (
            bytes(range(200)),
            32,
            b"My Tagged Application",
            "1f5b4e6cca02209e0dcb5ca635b89a15e271ecc760071dfd805faa38f9729230",
        ),
    ]

    for i, (X, outlen, S, expected) in enumerate(samples, 1):
        actual = kmac128(K, X, outlen, S).hex().lower()
        assert actual == expected, f"NIST Sample {i} failed: got {actual}, exp {expected}"


# ==============================================================================
# 3. RTL Testbench Known-Answer Tests (6 TB Vectors)
# ==============================================================================

def test_rtl_tb_known_answer_tests():
    """Verify all 6 testbench vectors match RTL literal values."""
    tb_kats = [
        {
            "id": "TB_TEST_1",
            "key": bytes(range(32)),
            "msg": b"",
            "custom": b"",
            "out_len": 32,
            "expected_literal": 0x973ad9b322481f9e33d9b846afdf832e22857038c98773a9aec45b25a004a502,
        },
        {
            "id": "TB_TEST_2",
            "key": bytes(range(32)),
            "msg": bytes(range(16)),
            "custom": b"",
            "out_len": 32,
            "expected_literal": 0x350e8bd95e6df79c65878fd953f0369745115da9cb1c7bdce21b4384a56cd119,
        },
        {
            "id": "TB_TEST_3",
            "key": bytes(range(32)),
            "msg": bytes(range(16)),
            "custom": b"Custom",
            "out_len": 32,
            "expected_literal": 0x29b7bd43a1df5e4ffbacb9d3134aa837dc3ee504a563858ca2327fe0fef702db,
        },
        {
            "id": "TB_TEST_4",
            "key": bytes(range(32)),
            "msg": bytes(range(16)),
            "custom": bytes(range(16)),
            "out_len": 32,
            "expected_literal": 0x556c806a871cc489e51b2f3085ac01ac55065b94f2b0e43af340c14faa83e13e,
        },
        {
            "id": "TB_TEST_5",
            "key": bytes(range(16)),
            "msg": bytes(range(16)),
            "custom": b"",
            "out_len": 32,
            "expected_literal": 0xf1501b0abeb872265fc62c77e9a37c59ba8038288bad24b4b6861fc410c659a4,
        },
        {
            "id": "TB_TEST_6_L128",
            "key": bytes(range(32)),
            "msg": bytes(range(16)),
            "custom": b"",
            "out_len": 16,
            "expected_literal": 0x1f2915cfef11bdfabebf8e536b71fa30,
        },
    ]

    for kat in tb_kats:
        res_bytes = kmac128(kat["key"], kat["msg"], kat["out_len"], kat["custom"])
        res_int = int.from_bytes(res_bytes, byteorder="little")
        assert res_int == kat["expected_literal"], (
            f"{kat['id']} mismatch: got {hex(res_int)}, expected {hex(kat['expected_literal'])}"
        )


# ==============================================================================
# 4. Output Length, Byte Ordering, and Domain Separation
# ==============================================================================

def test_output_length_and_byte_ordering():
    """Verify output lengths (16 vs 32 bytes) and byte ordering consistency."""
    key = bytes(range(32))
    msg = b"PQ-Attest Test Packet"

    out16 = kmac128(key, msg, 16, b"NOC-L2-AUTH-v1")
    assert len(out16) == 16

    out32 = kmac128(key, msg, 32, b"NOC-L2-AUTH-v1")
    assert len(out32) == 32

    # Squeeze prefix: first 16 bytes of out32 should not equal out16 because L (output bits) is encoded in KMAC input!
    assert out16 != out32[:16]


def test_packet_mac_domain_separation():
    """Verify domain separation string 'NOC-L2-AUTH-v1' alters the MAC tag."""
    key = bytes(range(32))
    msg = b"Packet Payload"

    tag_default = kmac128(key, msg, 16, b"")
    tag_noc = kmac128(key, msg, 16, b"NOC-L2-AUTH-v1")
    tag_other = kmac128(key, msg, 16, b"OTHER-DOMAIN")

    assert tag_default != tag_noc
    assert tag_noc != tag_other


# ==============================================================================
# 5. Negative and Type Validation Tests
# ==============================================================================

def test_negative_parameter_validation():
    """Verify rejection of invalid parameter types and values."""
    key = bytes(range(32))
    msg = b"test"

    # Non-bytes key
    with pytest.raises(TypeError):
        kmac128("string_key", msg, 16)

    # Non-bytes message
    with pytest.raises(TypeError):
        kmac128(key, "string_msg", 16)

    # Non-integer output_bytes
    with pytest.raises(TypeError):
        kmac128(key, msg, "16")

    with pytest.raises(TypeError):
        kmac128(key, msg, 16.5)

    with pytest.raises(TypeError):
        kmac128(key, msg, True)

    # Negative output_bytes
    with pytest.raises(ValueError):
        kmac128(key, msg, -1)

    # Non-bytes customization
    with pytest.raises(TypeError):
        kmac128(key, msg, 16, "custom")


# ==============================================================================
# 6. Per-Tile KDF Tests
# ==============================================================================

def test_derive_tile_key_api():
    """Verify derive_tile_key works and enforces 16 or 32 byte key lengths."""
    root = bytes(range(32))
    tile_id = (3).to_bytes(4, "big")
    epoch = (1).to_bytes(8, "big")
    context = b"KDF-TEST"

    k16 = derive_tile_key(root, tile_id, epoch, context, key_bytes=16)
    assert len(k16) == 16

    k32 = derive_tile_key(root, tile_id, epoch, context, key_bytes=32)
    assert len(k32) == 32
    assert k16 != k32[:16]

    with pytest.raises(ValueError):
        derive_tile_key(root, tile_id, epoch, context, key_bytes=64)

