"""Build and verify a hash-pinned, text-only export for the separate verification repo."""
import argparse
from hashlib import sha256
import io
import json
from pathlib import Path
import subprocess
import zipfile


def git(*args):
    return subprocess.check_output(["git", *args])


def build_export(ref, stage, dest):
    commit = git("rev-parse", ref).decode().strip()
    branch = git("branch", "--show-current").decode().strip()
    base = git("rev-list", "-n", "1", "titan-base-20261119").decode().strip()
    if not base.startswith("b9e41c38") or branch != "kalash/titan-rtl":
        raise ValueError("Export requires the TITAN branch and pinned baseline")

    def blob(path, revision=commit):
        raw = git("show", f"{revision}:{path}")
        raw.decode("utf-8-sig")
        return raw

    paths = {
        "docs/titan/ARNAV_PATH_MAP.md", "docs/titan/MONITOR_EVENTS.md", "docs/titan/ARNAV_GATE_PROOF_TARGET.md",
        "docs/titan/S1_GOLDEN.csv", "docs/decisions/M-F1-rev11-TITAN-EPOCH-STATUS.md",
    }
    files = {p: blob(p, base) for p in ("rtl/dual_lane/NOC_PKG.sv", "rtl/dual_lane/noc_attest_gate.sv")}
    if stage == "S0-S3":
        paths.update(f"docs/titan/stage_reports/S{n}.md" for n in range(4))
        paths.update(("docs/titan/S3_CONSUMERS.md", "rtl/dual_lane/titan_provenance.json",
                      "rtl/dual_lane/titan_pkg.sv", "scripts/prepare_titan.py", "scripts/titan/benches.txt",
                      "scripts/titan/prepare_monitor_controls.py", "sw/riscv/status_regs.h"))
        for name in ("noc_network_interface_p7","noc_l2_auth_p7","noc_l2_p7_pair","pq_noc_subsystem_p7"):
            paths.add(f"rtl/dual_lane/{name}_t1.sv")
        registry = json.loads(blob("scripts/dual_lane_jobs.json"))
        selected = {j for n in range(4) for j in registry["increments"][f"I-T{n}"]}
        for job in registry["jobs"]:
            if job["id"] not in selected or job["kind"] != "simulation":
                continue
            for path in job["sources"]:
                if Path(path).name == f"{job['top']}.sv" or "/titan/" in path:
                    paths.add(path)
        run = "docs/titan/stage_reports/S2_evidence/dual_lane_10_20261121_023545_a4737134"
        unit = blob(f"{run}/it2_mon_unit/titan_events.csv")
        bound = blob(f"{run}/it2_matched_secure_bound/simulate.log").decode()
        bound_rows = [line.removeprefix("TITAN_EVENT ") for line in bound.splitlines()
                      if line.startswith("TITAN_EVENT ")]
        if bound_rows or "P1=0 P2=0 P3=0 P4=0 P6=X M3=0 SD=0" not in bound:
            raise ValueError("The selected S2 bound log does not establish the expected quiet sample")
        files.update({"samples/s2_unit_events.csv": unit,
                      "samples/s2_bound_events.csv": b"cycle,event,src,tag,epoch\n"})
    else:
        n = stage[1]
        revised = stage.endswith("R")
        suffix = "r" if revised else ""
        paths.update((f"docs/titan/stage_reports/{stage}.md", f"mutants/s{n}_mutants.json",
                      f"scripts/titan/prepare_stage{n}{suffix}.py",
                      f"scripts/register_titan_stage{n}{suffix}.py"))
        listing = git("ls-tree","-r","--name-only",commit,"rtl/dual_lane/titan").decode().splitlines()
        names = ("tb_titan_epoch", "titan_epoch_tracker") if n == "4" else ("tb_titan_stamp", "titan_epoch_stamp")
        paths.update(p for p in listing if f"/s{n}{suffix}/" in p or Path(p).name.startswith(names))
        if n == "5":
            tracker_name = "titan_epoch_tracker_r1.sv" if revised else "titan_epoch_tracker.sv"
            paths.update(("rtl/dual_lane/titan_pkg.sv","rtl/dual_lane/titan/tb_titan_pkg.sv",
                          f"rtl/dual_lane/titan/{tracker_name}",
                          f"scripts/titan/prepare_stage4{suffix}.py",
                          f"rtl/dual_lane/titan/s4{suffix}/pq_noc_subsystem_p7_t1.sv"))
    timing = "docs/titan/ATTEST_TIMING_FACTS.md"
    if stage != "S0-S3":
        paths.add(timing)
    files.update({path: blob(path) for path in sorted(paths)})
    manifest = [
        f"Stage: {stage}", f"Branch: {branch}", f"Commit: {commit}", f"titan-base-20261119: {base}",
        "", "SHA-256  archive path",
        *(f"{sha256(raw).hexdigest()}  {path}" for path, raw in sorted(files.items())),
    ]
    files["MANIFEST.txt"] = ("\n".join(manifest) + "\n").encode()
    name = f"TITAN_RTL_{stage}_{commit[:8]}.zip"
    dest.mkdir(parents=True, exist_ok=True)
    target = dest / name
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path, raw in sorted(files.items()):
            info = zipfile.ZipInfo(path)
            archive.writestr(info, raw, compress_type=zipfile.ZIP_DEFLATED)
    with zipfile.ZipFile(buffer) as archive:
        if archive.testzip() is not None or set(archive.namelist()) != set(files):
            raise ValueError("Export integrity check failed")
        if any(archive.read(path) != raw for path, raw in files.items()):
            raise ValueError("Export bytes did not match the verified source bytes")
    raw_zip = buffer.getvalue()
    if target.exists() and target.read_bytes() != raw_zip:
        raise ValueError(f"Existing archive differs: {target}")
    target.write_bytes(raw_zip)
    print(f"{target} | {len(files)} files | SHA-256 {sha256(raw_zip).hexdigest()}")


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("stage", choices=("S0-S3","S4","S5","S4R","S5R"))
    cli.add_argument("ref")
    cli.add_argument("dest", type=Path)
    args = cli.parse_args()
    build_export(args.ref, args.stage, args.dest.resolve())
