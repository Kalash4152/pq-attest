"""Check pinned inputs, deterministic output and the exact-anchor failure cases."""
import json
import shutil
import tempfile
from pathlib import Path

from dual_lane_preflight import PreflightFailure, source_names
from prepare_titan import PROVENANCE, ROOT, build, replace_once, variant_map


def must_fail(action, reason):
    try:
        action()
    except ValueError as error:
        if reason not in str(error):
            raise
    else:
        raise ValueError(f"Expected rejection: {reason}")


def main():
    generated = build()
    with tempfile.TemporaryDirectory(prefix="titan_check_") as tmp:
        isolated = Path(tmp)
        for rel in [PROVENANCE, *variant_map()]:
            target = isolated / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / rel, target)
        replay = build(isolated)
        if generated != replay:
            raise ValueError("TITAN regeneration is nondeterministic")
        for rel, raw in replay.items():
            (isolated / rel).write_bytes(raw)
            if (ROOT / rel).read_bytes() != (isolated / rel).read_bytes():
                raise ValueError(f"TITAN generated file drift: {rel}")
        pins = json.loads((isolated / PROVENANCE).read_text(encoding="utf-8"))
        pins["input_sha256"][next(iter(variant_map()))] = "0" * 64
        (isolated / PROVENANCE).write_text(json.dumps(pins), encoding="utf-8")
        must_fail(lambda: build(isolated), "input hash mismatch")

    fixture = "head\nanchor\nfoot\n"
    if replace_once(fixture, "anchor", "new", "fixture") != "head\nnew\nfoot\n":
        raise ValueError("Exact-anchor replacement produced unexpected output")
    must_fail(lambda: replace_once(fixture, "missing", "new", "fixture"), "matched 0 times")
    must_fail(lambda: replace_once(fixture + "anchor\n", "anchor", "new", "fixture"), "matched 2 times")
    for src, dst in variant_map().items():
        duplicate = {"kind": "simulation", "sources": [src, dst]}
        try:
            source_names(ROOT, duplicate)
        except PreflightFailure as error:
            if "duplicate module:" not in str(error):
                raise
        else:
            raise ValueError(f"Mixed I-9/TITAN source list was accepted: {src}")
    print("TITAN_VARIANT: PASS files=4 negative_controls=4")


if __name__ == "__main__":
    main()
