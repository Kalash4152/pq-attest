#!/usr/bin/env python3
"""
PQ-Attest P7 Verification - F1: Authoritative KMAC Reference Adapter

This adapter binds Engineer 4's verification infrastructure to the pinned
authoritative teammate reference:
  software/pq_attest_final/PQ_Attest/software/kmac128_ref.py
  (Source archive: Pq_Attest_final.zip, SHA-256: 047bb5a981050f11a572a60e850f7c7511ff5d636f7903c6a8d239891003c6a0)

The older repo copy `software/kmac128_ref.py` is demoted to a supplementary
standalone KAT script and MUST NOT be imported by the active verification path.

Verification Classification:
  Python cryptographic reference correction and test validation.
  This does not constitute new RTL simulation, formal proof or hardware validation.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import importlib
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    from verification.p7_paths import P7Paths, get_default_paths
except ImportError:  # executed as a script from within verification/
    from p7_paths import P7Paths, get_default_paths


# ==============================================================================
# Constants and Hashes
# ==============================================================================

AUTHORITATIVE_KMAC_SHA256 = (
    "ac8076e665b6b838c58b9b3458b6e3cd16101fbab4dc0d90fbc78f90497ce394"
)
AUTHORITATIVE_KECCAK_SHA256 = (
    "80cbd3a8c2cc73065ab153be7ba21c204c5d529f3951c1f7187ea9580baa1824"
)
DEMOTED_KMAC_SHA256 = (
    "73d9b064b6b546fede85ed182259d7ed33f8e0d9ec512abee57db6827b5bde62"
)
SOURCE_ARCHIVE_NAME = "Pq_Attest_final.zip"
SOURCE_ARCHIVE_SHA256 = (
    "047bb5a981050f11a572a60e850f7c7511ff5d636f7903c6a8d239891003c6a0"
)


class ReferenceIdentityError(RuntimeError):
    """Raised when an invalid, demoted, or corrupt cryptographic reference is loaded."""
    pass


# ==============================================================================
# Path Resolution and Integrity Check
# ==============================================================================

def find_repo_root() -> Path:
    """Repository root from the shared resolver (env override, else discovery)."""
    return get_default_paths().repo_root


def _paths_for(repo_root: Optional[Path]) -> P7Paths:
    """``repo_root`` keeps its historical meaning (data layout beneath it)."""
    return P7Paths.from_root(repo_root) if repo_root is not None else get_default_paths()


def compute_sha256(file_path: Path) -> str:
    """Computes SHA-256 digest of a file."""
    h = hashlib.sha256()
    with open(file_path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def resolve_authoritative_reference_dir(repo_root: Optional[Path] = None) -> Tuple[Path, Path]:
    """
    Resolves the directory containing the authoritative teammate KMAC reference.
    Candidates come from the configured data dir (see verification/p7_paths.py):
      1. <data>/software/pq_attest_final/PQ_Attest/software
      2. <data>/PQ_Attest_S4_Evidence/02_sources/software/pq_attest_final/PQ_Attest/software
    Returns (ref_dir, kmac_file_path).  Never searches anywhere else.
    """
    paths = _paths_for(repo_root)
    candidates = paths.reference_dir_candidates

    for cand in candidates:
        kmac_p = cand / "kmac128_ref.py"
        if kmac_p.is_file():
            # Validate hash immediately
            file_hash = compute_sha256(kmac_p)
            if file_hash == DEMOTED_KMAC_SHA256:
                raise ReferenceIdentityError(
                    f"Forbidden: Attempted to load demoted software/kmac128_ref at {kmac_p}"
                )
            if file_hash != AUTHORITATIVE_KMAC_SHA256:
                raise ReferenceIdentityError(
                    f"Authoritative KMAC reference hash mismatch at {kmac_p}: "
                    f"got {file_hash}, expected {AUTHORITATIVE_KMAC_SHA256}"
                )
            return cand, kmac_p

    raise ReferenceIdentityError(
        "Authoritative teammate KMAC reference not found. Expected kmac128_ref.py at: "
        + " or ".join(str(c) for c in candidates)
        + f" (data directory: {paths.data_dir}; set --data-dir / P7_DATA_DIR)"
    )


# ==============================================================================
# Module Loader
# ==============================================================================

def _load_authoritative_module():
    """
    Loads the authoritative teammate kmac128_ref module in isolation.
    Guarantees no contamination from demoted root software/kmac128_ref.py.
    """
    ref_dir, kmac_path = resolve_authoritative_reference_dir()

    # Verify keccak_ref companion file exists and has pinned hash
    keccak_path = ref_dir / "keccak_ref.py"
    if not keccak_path.is_file():
        raise ReferenceIdentityError(f"Missing authoritative keccak_ref at {keccak_path}")
    keccak_hash = compute_sha256(keccak_path)
    if keccak_hash != AUTHORITATIVE_KECCAK_SHA256:
        raise ReferenceIdentityError(
            f"Authoritative keccak_ref hash mismatch at {keccak_path}: "
            f"got {keccak_hash}, expected {AUTHORITATIVE_KECCAK_SHA256}"
        )

    # Clean existing kmac128_ref or keccak_ref from sys.modules if pointing to demoted repo copy
    for mod_name in ("kmac128_ref", "keccak_ref"):
        if mod_name in sys.modules:
            existing_f = getattr(sys.modules[mod_name], "__file__", "")
            if existing_f and Path(existing_f).resolve().parent != ref_dir.resolve():
                del sys.modules[mod_name]

    sys.dont_write_bytecode = True
    ref_dir_str = str(ref_dir.resolve())
    orig_path = list(sys.path)

    try:
        # Prepend authoritative reference dir
        if ref_dir_str in sys.path:
            sys.path.remove(ref_dir_str)
        sys.path.insert(0, ref_dir_str)

        mod = importlib.import_module("kmac128_ref")

        # Double check loaded module file
        loaded_f = getattr(mod, "__file__", "")
        if not loaded_f or Path(loaded_f).resolve() != kmac_path.resolve():
            raise ReferenceIdentityError(
                f"kmac128_ref resolved to {loaded_f}, expected {kmac_path}"
            )

        return mod
    finally:
        # Restore sys.path
        sys.path = orig_path


_AUTHORITATIVE_MOD = _load_authoritative_module()


# ==============================================================================
# Public Cryptographic API
# ==============================================================================

def kmac128(
    key: bytes,
    message: bytes,
    output_bytes: int,
    customization: bytes = b"",
) -> bytes:
    """
    SP 800-185 KMAC128 via the authoritative teammate reference.

    Parameters:
      key: bytes (16 or 32 bytes)
      message: bytes (input transcript/payload)
      output_bytes: int (number of requested output bytes)
      customization: bytes (domain-separation string, e.g. b"NOC-L2-AUTH-v1")
    """
    if not isinstance(key, (bytes, bytearray)):
        raise TypeError(f"KMAC key must be bytes or bytearray, got {type(key).__name__}")
    if not isinstance(message, (bytes, bytearray)):
        raise TypeError(f"KMAC message must be bytes or bytearray, got {type(message).__name__}")
    if not isinstance(output_bytes, int) or isinstance(output_bytes, bool):
        raise TypeError(f"output_bytes must be integer, got {type(output_bytes).__name__}")
    if output_bytes < 0:
        raise ValueError(f"output_bytes must be non-negative, got {output_bytes}")
    if not isinstance(customization, (bytes, bytearray)):
        raise TypeError(f"customization must be bytes, got {type(customization).__name__}")

    return _AUTHORITATIVE_MOD.kmac128(
        key=bytes(key),
        message=bytes(message),
        output_bytes=output_bytes,
        customization=bytes(customization),
    )


def derive_tile_key(
    root_secret: bytes,
    tile_id: bytes,
    epoch: bytes,
    context: bytes,
    key_bytes: int = 16,
) -> bytes:
    """
    PQ-Attest per-tile KDF via the authoritative teammate reference.
    """
    return _AUTHORITATIVE_MOD.derive_tile_key(
        root_secret=root_secret,
        tile_id=tile_id,
        epoch=epoch,
        context=context,
        key_bytes=key_bytes,
    )


# ==============================================================================
# Provenance Metadata
# ==============================================================================

def get_kmac_reference_metadata(repo_root: Optional[Path] = None) -> Dict[str, Any]:
    """Exposes comprehensive cryptographic provenance and integrity metadata.

    Paths are rendered portably (repo-relative or ``$DATA/...``), never as
    machine-specific absolute paths.
    """
    paths = _paths_for(repo_root)
    ref_dir, kmac_path = resolve_authoritative_reference_dir(repo_root)
    demoted_path = paths.demoted_kmac_reference
    keccak_path = ref_dir / "keccak_ref.py"

    metadata = {
        "status": "AUTHORITATIVE_PINNED",
        "authoritative_reference": {
            "path": paths.portable(kmac_path),
            "sha256": compute_sha256(kmac_path),
            "size_bytes": kmac_path.stat().st_size,
            "source_archive": SOURCE_ARCHIVE_NAME,
            "source_archive_sha256": SOURCE_ARCHIVE_SHA256,
        },
        "companion_keccak_reference": {
            "path": paths.portable(keccak_path),
            "sha256": compute_sha256(keccak_path),
            "size_bytes": keccak_path.stat().st_size,
        },
        "demoted_reference": {
            "path": paths.portable(demoted_path) if demoted_path.exists() else None,
            "sha256": compute_sha256(demoted_path) if demoted_path.exists() else None,
            "status": "DEMOTED_SUPPLEMENTARY_KAT_ONLY",
        },
        "adapter": {
            "path": "verification/p7_kmac_adapter.py",
            "active_module": paths.portable(Path(getattr(_AUTHORITATIVE_MOD, "__file__", ""))),
        },
        "updated_import_locations": [
            "verification/p7_packet_model.py",
            "verification/p7_differential.py",
            "verification/crypto_compare.py",
            "verification/tests/test_p7_differential.py",
        ],
    }
    return metadata


def generate_provenance_artifact(output_path: Optional[Path | str] = None) -> Dict[str, Any]:
    """Generates verification/generated/p7_kmac_reference_provenance.json."""
    paths = get_default_paths()
    out_p = (
        Path(output_path)
        if output_path
        else paths.generated_dir / "p7_kmac_reference_provenance.json"
    )
    out_p.parent.mkdir(parents=True, exist_ok=True)

    meta = get_kmac_reference_metadata()

    # Run selftest samples
    K = bytes(range(0x40, 0x60))
    sample1 = kmac128(K, bytes([0, 1, 2, 3]), 32, b"").hex().lower()
    exp1 = "e5780b0d3ea6f7d3a429c5706aa43a00fadbd7d49628839e3187243f456ee14e"

    manifest = {
        "schema_version": "1.0.0",
        "generator": "verification.p7_kmac_adapter",
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "provenance": meta,
        "self_test_verification": {
            "nist_sp800_185_sample1_match": (sample1 == exp1),
            "sample1_hex": sample1,
            "expected_hex": exp1,
            "status": "PASS" if sample1 == exp1 else "FAIL",
        },
    }

    out_p.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description="PQ-Attest P7 Authoritative KMAC Reference Provenance")
    parser.add_argument("--output", "-o", type=Path, default=None, help="Target provenance JSON file")
    args = parser.parse_args()

    manifest = generate_provenance_artifact(args.output)
    print("======================================================================")
    print("PQ-Attest P7 Authoritative KMAC Reference Provenance (Task F1)")
    print("======================================================================")
    print(f"Authoritative File : {manifest['provenance']['authoritative_reference']['path']}")
    print(f"SHA-256            : {manifest['provenance']['authoritative_reference']['sha256']}")
    print(f"Source Archive     : {manifest['provenance']['authoritative_reference']['source_archive']}")
    print(f"Archive SHA-256    : {manifest['provenance']['authoritative_reference']['source_archive_sha256']}")
    print(f"Demoted File       : {manifest['provenance']['demoted_reference']['path']}")
    print(f"Self-Test Status   : {manifest['self_test_verification']['status']}")
    print("======================================================================")
    return 0 if manifest["self_test_verification"]["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())

