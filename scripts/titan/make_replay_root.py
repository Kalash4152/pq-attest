"""Materialize a TITAN evidence root at a real branch commit and verify its overlays."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BRANCH = "kalash/titan-rtl"
PAYLOAD = Path("automation/dual_lane_payload")
LEDGER = PAYLOAD / "baseline_before.json"


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])


def sha(data):
    return hashlib.sha256(data).hexdigest()


def matched_bytes(raw, expected):
    lf = raw.replace(b"\r\n", b"\n")
    for candidate in (raw, lf, lf.replace(b"\n", b"\r\n")):
        if sha(candidate) in expected:
            return candidate
    return None


def local(root, rel):
    path = (root / rel).resolve()
    if path == root or not path.is_relative_to(root):
        raise ValueError(f"Path escapes replay input root: {rel}")
    return path


def prepare(dest, live):
    if dest.exists() or dest.is_relative_to(live) or dest.is_relative_to(ROOT):
        raise ValueError("Replay destination must be new and outside both project trees")
    commit = git(ROOT, "rev-parse", BRANCH).decode().strip()
    ledger_raw = git(ROOT, "show", f"{commit}:{LEDGER.as_posix()}")
    protected = {
        p: h for p, h in json.loads(ledger_raw)["files"].items()
        if ("/sources_1/new/" in p and not Path(p).name.startswith("tb"))
        or Path(p).name in ("tb_ni_n81.sv", "tb_noc_n81.sv")
    }
    if len(protected) != 48:
        raise ValueError(f"Unexpected protected ledger scope: {len(protected)}")
    original = {p: local(live, p).read_bytes() for p in protected}
    for p, data in original.items():
        if sha(data) != protected[p]:
            raise ValueError(f"Protected digest mismatch: {p}")

    subprocess.run(["git", "-C", str(ROOT), "worktree", "add", "--detach", "--quiet", str(dest), commit],
                   check=True)
    for rel, raw in original.items():
        target = local(dest, rel)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        if sha(target.read_bytes()) != protected[rel]:
            raise ValueError(f"Protected replay digest mismatch: {rel}")

    # Git normalizes text blobs. Reconstruct only exact ledger-matching bytes
    # for the existing scheduler payload, never accepting a normalized hash.
    changed = {}
    manifest = json.loads((dest / PAYLOAD / "update_manifest.json").read_bytes())
    for row in manifest["files"]:
        rel = row["path"]
        source = local(dest, PAYLOAD / row["payload"])
        raw = source.read_bytes()
        verified = matched_bytes(raw, {row["after"]})
        if verified is None:
            raise ValueError(f"Cannot reconstruct pinned payload bytes: {rel}")
        if raw != verified:
            source.write_bytes(verified)
        target = local(dest, rel)
        if not target.is_file():
            if row["before"] is not None:
                raise ValueError(f"Missing guarded baseline input: {rel}")
            continue
        raw = target.read_bytes()
        verified = matched_bytes(raw, {row["before"], row["after"]})
        if verified is None:
            # Mixed CRLF/LF cannot be inferred from an LF Git blob. The
            # exact verified payload can recover it when content matches.
            candidate = source.read_bytes()
            if candidate.replace(b"\r\n", b"\n") == raw.replace(b"\r\n", b"\n"):
                verified = candidate
        if verified is None:
            raise ValueError(f"Cannot reconstruct pinned destination bytes: {rel}")
        if raw != verified:
            if rel in protected:
                raise ValueError(f"Payload conflicts with protected replay input: {rel}")
            target.write_bytes(verified)
            changed[rel] = sha(verified)
    if git(dest, "rev-parse", "HEAD").decode().strip() != commit:
        raise ValueError("Replay HEAD drift")
    identity = dict(branch=BRANCH, commit=commit, ledger_sha256=sha(ledger_raw),
                    protected_overlays=protected, restored_guarded_text_bytes=changed)
    (dest / "REPLAY_IDENTITY.json").write_text(json.dumps(identity, indent=2) + "\n", encoding="utf-8")
    print(f"TITAN_REPLAY: PASS commit={commit} protected={len(protected)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=Path)
    parser.add_argument("--live", type=Path, default=Path("C:/vivado_verilog_proj/NOC_PQATTEST"))
    args = parser.parse_args()
    prepare(args.destination.resolve(), args.live.resolve())
