"""Compare observations only after the registered Stage 0 XSim jobs passed."""
import argparse
import json
import re
from decimal import Decimal
from pathlib import Path

PAIRS = {"inflight": 6, "attack": 6, "contention": 8, "phase": 56}
NS_PER_UNIT = {"ps": Decimal("0.001"), "ns": Decimal(1), "us": Decimal(1000), "ms": Decimal(1000000)}


def observe(run, status, job, count):
    record = status["jobs"][job]
    if record["state"] != "PASS_FRESH" or record["fresh_run"] != run.name:
        raise ValueError(f"{job}: {record['state']} is not fresh evidence for this run")
    if record["expected"]["checks"] != count:
        raise ValueError(f"{job}: frozen check count differs from S0 plan")
    logs = list((run / job / "workspace").rglob("simulate.log"))
    if len(logs) != 1:
        raise ValueError(f"{job}: expected exactly one raw simulation log")
    lines = logs[0].read_text(encoding="utf-8", errors="replace").splitlines()
    finish = [m.groups() for line in lines if (m := re.match(r'^\$finish called at time\s*:\s*([\d.]+)\s*(ps|ns|us|ms)\b', line))]
    verdicts = [line for line in lines if line.startswith("RESULT :")]
    checks = [line for line in lines if line.startswith("[PASS] ")]
    if len(finish) != 1 or verdicts != ["RESULT : PASS"] or len(checks) != count:
        raise ValueError(f"{job}: missing completion or check evidence")
    value, unit = finish[0]
    cycles = Decimal(value) * NS_PER_UNIT[unit] / 20
    timing = [line for line in lines if line.startswith(("ATTEST_LATENCY ", "REVOKE_LATENCY ", "AT_CONTROL_TIMING "))]
    return {"checks": checks, "finish_clock_periods": str(cycles), "timing_lines": timing}


def compare(run):
    status = json.loads((run / "status.json").read_bytes())
    expected = {f"it0_{bench}_{variant}_r1" for bench in PAIRS for variant in ("b0", "t1")}
    if status.get("active_increment") != "I-T0" or status.get("increment_status") != "PASS":
        raise ValueError("I-T0 is not accepted")
    if set(job for job in status["jobs"] if job.startswith("it0_") and job.endswith("_r1")) != expected:
        raise ValueError("Unexpected Stage 0 job set")
    details = {}
    for bench, count in PAIRS.items():
        b0, t1 = (observe(run, status, f"it0_{bench}_{variant}_r1", count) for variant in ("b0", "t1"))
        if b0 != t1:
            raise ValueError(f"{bench}: B0 and TITAN observations differ")
        details[bench] = {"checks_per_job": count, "verdict": "RESULT : PASS", **b0}
    return details


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("run", type=Path)
    args = parser.parse_args()
    print(json.dumps(compare(args.run), indent=2))
