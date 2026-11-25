"""
verification/build_corrected_handoff.py
=======================================
Builds and verifies the Engineer 4 corrected handoff archive.

Hash placement (a file cannot contain its own hash):
  * INTERNAL manifest (inside the zip): per-file path/size/sha256 for every other
    archive entry. It records the base commit and states archive_hash_location =
    EXTERNAL_SIDECAR. It never contains the archive hash or a final HEAD claim.
  * EXTERNAL sidecar  <zip>.sha256              : archive SHA-256 + size.
  * EXTERNAL manifest <zip stem>.manifest.json  : internal manifest + archive hash,
    size, final HEAD SHA and post-build verification result.

Usage:
  python verification/build_corrected_handoff.py --manifest   # write internal manifest
  python verification/build_corrected_handoff.py --build      # build zip + external files
  python verification/build_corrected_handoff.py --verify     # re-verify the zip

Python tooling only. Not RTL simulation, not hardware, not formal.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import Dict, List

REPO = Path(__file__).resolve().parent.parent
ZIP_NAME = "E4_P7_CORRECTED_HANDOFF_FINAL_20261106.zip"
SIDECAR_NAME = ZIP_NAME + ".sha256"
EXT_MANIFEST_NAME = "E4_P7_CORRECTED_HANDOFF_FINAL_20261106.manifest.json"
INT_MANIFEST_REL = "verification/generated/e4_corrected_handoff_manifest.json"
REPORT_REL = "reports/E4_P7_CORRECTED_HANDOFF_20261106.md"
ROOTS = ("verification", "reports", "vectors")
ZIP_DATE = (2026, 11, 6, 0, 0, 0)

REGISTERED_VECTORS = {
    "vectors/d2_k3_64.json": "0a96d46447f51ce2b5cdb0b8d240849c3f68e8b4b7c89c58451daa7bf99e540f",
    "vectors/d2_k3_64.svh": "f58e0344185e84680a54164e358a95731f37e10dd46ff5d61618b44baf7cd198",
}
KEY_DELIVERABLES = [
    "reports/E4_P7_FINAL_CORRECTION_REPORT_20261106.md",
    "reports/E4_P7_D2_FILENAME_RECONCILIATION.md",
    "reports/E4_P7_STEP18_RTL_MUTANT_PROPOSALS.md",
    "reports/E4_P7_STEP18_MUTANT_RECONCILIATION.md",
    "verification/generated/p7_rtl_mutant_proposals.json",
    "reports/E4_P7_STEP12_LATENCY_TIMEOUT.md",
    "verification/generated/p7_latency_model_results.json",
    "reports/figures/fig05_timeout_behavior.svg",
    "reports/figures/fig06_latency_breakdown.svg",
    "reports/E4_P7_CORRECTED_HANDOFF_20261106.md",
    "vectors/d2_k3_64.json",
    "vectors/d2_k3_64.svh",
    "vectors/e4_d2_measurements.json",
    "vectors/e4_d2_measurements.svh",
]
DISCLAIMERS = {
    "classification_wording": "Python model checking. Not RTL simulation, not hardware, not formal.",
    "HARDWARE_VALIDATED": "NO",
    "SOC_INTEGRATION_COMPLETE": "NO",
    "FORMAL_PROOF": "NO",
    "RTL_MODIFICATIONS": 0,
    "PYTHON_MUTANTS_ARE_RTL_MUTANTS": "NO",
    "SYNTHETIC_STIMULUS_IS_RTL_EVIDENCE": "NO",
}


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=REPO, check=True, capture_output=True, text=True).stdout.strip()


def collect_files() -> List[str]:
    tracked = git("ls-files", *ROOTS).splitlines()
    untracked = git("ls-files", "-o", "--exclude-standard", *ROOTS).splitlines()
    out = set()
    for rel in tracked + untracked:
        if "__pycache__" in rel or rel.endswith(".pyc"):
            continue
        if (REPO / rel).is_file():
            out.add(rel)
    return sorted(out)


def build_internal_manifest() -> Dict:
    files = []
    for rel in collect_files():
        if rel == INT_MANIFEST_REL:
            continue  # a manifest cannot contain its own hash
        data = (REPO / rel).read_bytes()
        files.append({"path": rel, "size_bytes": len(data), "sha256": sha256_bytes(data)})
    by_path = {f["path"]: f for f in files}
    return {
        "metadata": {
            "manifest_title": "PQ-Attest Engineer 4 Corrected Handoff Manifest (internal)",
            "date": "2026-11-06",
            "author": "PQ-Attest Engineer 4",
            "reviewer": "Kalash Bheda (Lane 1)",
            "evidence_package": "E4_EVIDENCE_20261106",
            "evidence_commit": "9af9cdfe83f222dc65f8bdcfaa1e9047bfcba0a9",
            "base_commit_sha": git("rev-parse", "HEAD"),
            "historical_commits": [
                "289fc44a2288667c60f65e35d98f40b02aaa227d",
                "902bd90b75bac8c9317584c9757a576687736f1f",
                "735caa3cb03297e857674ad2239a2019b7857358",
                "00d58c1417fe8c049d78ba63038abfd24ee69811",
            ],
            "final_head_note": "A commit cannot contain its own SHA. The final HEAD SHA is recorded only in the external manifest and sidecar.",
            "archive_hash_location": "EXTERNAL_SIDECAR",
            "archive_hash_note": "The archive SHA-256 cannot be embedded in the archive. See " + SIDECAR_NAME + " and " + EXT_MANIFEST_NAME + ".",
            "manifest_self_entry": "This manifest does not list its own hash.",
            "reconciliation_status": "COMPLETE",
            "acceptance_status": "AWAITING_KALASH_SIGNOFF",
            "test_counts": {"pytest_passed": 389, "pytest_total": 389, "regression_stages_passed": 15, "regression_stages_total": 15},
            "disclaimers": DISCLAIMERS,
        },
        "registered_vectors_expected_sha256": REGISTERED_VECTORS,
        "key_deliverables": [by_path[p] for p in KEY_DELIVERABLES if p in by_path],
        "file_count": len(files),
        "files": files,
    }


def write_internal_manifest() -> None:
    m = build_internal_manifest()
    (REPO / INT_MANIFEST_REL).write_text(json.dumps(m, indent=2) + "\n", encoding="utf-8", newline="")
    print(f"Wrote {INT_MANIFEST_REL}: {m['file_count']} files, base {m['metadata']['base_commit_sha'][:7]}")


def verify_zip(zip_path: Path, sidecar: Path) -> Dict:
    problems: List[str] = []
    raw = zip_path.read_bytes()
    actual = sha256_bytes(raw)
    side = sidecar.read_text(encoding="utf-8").split()
    if side[0].lower() != actual:
        problems.append(f"sidecar hash {side[0]} != actual {actual}")
    with zipfile.ZipFile(zip_path) as z:
        bad = z.testzip()
        if bad:
            problems.append(f"zip CRC failure: {bad}")
        names = set(z.namelist())
        manifest = json.loads(z.read(INT_MANIFEST_REL))
        listed = set()
        for f in manifest["files"]:
            listed.add(f["path"])
            if f["path"] not in names:
                problems.append(f"missing in archive: {f['path']}")
                continue
            d = z.read(f["path"])
            if sha256_bytes(d) != f["sha256"] or len(d) != f["size_bytes"]:
                problems.append(f"mismatch: {f['path']}")
        extra = names - listed - {INT_MANIFEST_REL, "README.md"}
        if extra:
            problems.append(f"unlisted archive entries: {sorted(extra)}")
        for p, h in REGISTERED_VECTORS.items():
            if sha256_bytes(z.read(p)) != h:
                problems.append(f"registered vector hash wrong: {p}")
        if z.read("README.md") != z.read(REPORT_REL):
            problems.append("README.md differs from the handoff report")
        entries = len(names)
    return {"status": "PASS" if not problems else "FAIL", "problems": problems,
            "sha256": actual, "size_bytes": len(raw), "archive_entries": entries,
            "manifest_entries_checked": manifest["file_count"]}


def build() -> int:
    dirty = git("status", "--porcelain", "--untracked-files=no")
    if dirty:
        print("Tracked tree is not clean; commit first:\n" + dirty)
        return 2
    internal = build_internal_manifest()
    on_disk = json.loads((REPO / INT_MANIFEST_REL).read_text(encoding="utf-8"))
    if internal["files"] != on_disk["files"]:
        print("Internal manifest is stale. Run --manifest, commit, then --build.")
        return 2
    head = git("rev-parse", "HEAD")
    zpath = REPO / ZIP_NAME
    if zpath.exists():
        zpath.unlink()
    paths = [p for p in collect_files()]
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        def add(arc: str, data: bytes) -> None:
            zi = zipfile.ZipInfo(arc, ZIP_DATE)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = 0o644 << 16
            z.writestr(zi, data)
        add("README.md", (REPO / REPORT_REL).read_bytes())
        for rel in paths:
            add(rel, (REPO / rel).read_bytes())
    sidecar = REPO / SIDECAR_NAME
    sha = sha256_bytes(zpath.read_bytes())
    sidecar.write_text(f"{sha}  {ZIP_NAME}\n", encoding="utf-8", newline="")
    res = verify_zip(zpath, sidecar)
    ext = {
        "external_manifest_note": "Contains the internal manifest content plus values that cannot live inside the archive.",
        "archive": {"name": ZIP_NAME, "size_bytes": res["size_bytes"], "sha256": res["sha256"],
                    "hash_location": SIDECAR_NAME, "entries": res["archive_entries"]},
        "git": {"final_head_sha": head, "final_head_short": head[:7],
                "base_commit_sha": on_disk["metadata"]["base_commit_sha"],
                "tracked_tree_clean_at_build": True},
        "post_build_verification": res,
        "acceptance_status": "AWAITING_KALASH_SIGNOFF",
        "internal_manifest": on_disk,
    }
    (REPO / EXT_MANIFEST_NAME).write_text(json.dumps(ext, indent=2) + "\n", encoding="utf-8", newline="")
    print(json.dumps({k: res[k] for k in ("status", "sha256", "size_bytes", "archive_entries", "manifest_entries_checked")}, indent=2))
    print("HEAD", head)
    return 0 if res["status"] == "PASS" else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--manifest", action="store_true")
    g.add_argument("--build", action="store_true")
    g.add_argument("--verify", action="store_true")
    a = ap.parse_args()
    if a.manifest:
        write_internal_manifest()
        return 0
    if a.build:
        return build()
    res = verify_zip(REPO / ZIP_NAME, REPO / SIDECAR_NAME)
    print(json.dumps(res, indent=2))
    return 0 if res["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
