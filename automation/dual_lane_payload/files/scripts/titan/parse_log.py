"""Extract golden metrics from logs accepted by the registered scheduler."""
import csv
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re
import statistics
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from dual_lane_verify import diagnostic_scan
from matched_latency import parse as parse_matched
from register_titan_stage1 import GOLDEN

PASS = re.compile(r"^RESULT\s*:\s*PASS[^\S\n]*$", re.M)
FINISH = re.compile(r"^\$finish called at time\s*:\s*([\d.]+)\s*(ps|ns|us|ms)\b", re.M)
NS = dict(ps=Decimal("0.001"), ns=Decimal(1), us=Decimal(1000), ms=Decimal(1000000))


def parse(text, expected_checks):
    diagnostic_scan(text, {})
    if re.search(r"\$error\b|\btimeout\b", text, re.I):
        raise ValueError("unexpected error or timeout")
    checks = re.findall(r"^CHECKS\s*:\s*(\d+)\s*$", text, re.M)
    errors = re.findall(r"^ERRORS\s*:\s*(\d+)\s*$", text, re.M)
    finishes = list(FINISH.finditer(text))
    results = re.findall(r"^RESULT\s*:", text, re.M)
    passes = list(PASS.finditer(text))
    if checks != [str(expected_checks)] or errors != ["0"] or len(results) != 1 or len(passes) != 1:
        raise ValueError("missing, duplicate, or inconsistent pass/check/error lines")
    if len(finishes) != 1 or finishes[0].start() <= passes[0].start():
        raise ValueError("missing completion after pass marker")
    value, unit = finishes[0].groups()
    return format(Decimal(value) * NS[unit] / 20, "f")


def read_golden(run):
    status = json.loads((run / "status.json").read_bytes())
    if (status["active_increment"], status["increment_status"]) != ("I-T1", "PASS"):
        raise ValueError("I-T1 increment must pass before collecting golden data")
    rows = []
    for name in GOLDEN:
        jid = f"it1_{name}"
        job = status["jobs"][jid]
        if job["state"] not in ("PASS_FRESH", "PASS_REUSED"):
            raise ValueError(f"{jid}: not accepted")
        accepted_run = run if job["state"] == "PASS_FRESH" else run.parent / job["original_run"]
        if job["state"] == "PASS_FRESH" and job["fresh_run"] != run.name:
            raise ValueError(f"{jid}: unexpected fresh-run identity")
        logs = list((accepted_run / jid / "workspace").rglob("simulate.log"))
        if len(logs) != 1:
            raise ValueError(f"{jid}: expected exactly one raw simulation log")
        raw = logs[0].read_bytes()
        if job["artifacts"].get(str(logs[0])) != hashlib.sha256(raw).hexdigest():
            raise ValueError(f"{jid}: log differs from accepted artifact hash")
        text = raw.decode("utf-8", errors="replace")
        expected = job["expected"]
        finish = parse(text, expected["checks"])
        rows.append((jid, expected["top"], job["state"], expected["checks"],
                     "completion_in_20ns_periods", finish, accepted_run.name))
        if name.startswith("matched_secure"):
            transfers = parse_matched(text)
            for write in (0, 1):
                median = statistics.median(row["latency"] for row in transfers if row["write"] == write)
                metric = "write_latency_median_cycles" if write else "read_latency_median_cycles"
                rows.append((jid, expected["top"], job["state"], expected["checks"], metric, f"{median:g}",
                             accepted_run.name))
                if name == "matched_secure" and median != 32:
                    raise ValueError(f"{jid}: {metric} changed from 32 to {median:g}")
    return rows


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    parser.add_argument("csv", type=Path)
    args = parser.parse_args()
    data = read_golden(args.run.resolve())
    with args.csv.open("x", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(("job", "bench", "state", "checks", "metric", "value", "run"))
        writer.writerows(data)
