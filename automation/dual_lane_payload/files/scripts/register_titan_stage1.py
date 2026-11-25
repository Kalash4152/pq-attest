"""Select the secure revision-10 regression for the TITAN Stage 1 golden."""
from copy import deepcopy

GOLDEN = (
    "closure", "lifecycle", "error", "inflight", "contention", "phase_sweep",
    "attack_approve_changed", "attack_reject_changed", "hasher", "decoder",
    "mmio_guard", "i9_integ", "matched_secure", "matched_secure_contended",
)


def append_jobs(jobs):
    by_id = {job["id"]: job for job in jobs}
    added = ["it1_parse_log_controls"]
    jobs.append(dict(
        id=added[0], kind="python", script="scripts/titan/test_parse_log.py",
        sources=[], oracle_files=["scripts/titan/parse_log.py", "scripts/matched_latency.py",
                                "scripts/titan/test_parse_log.py"],
        dependencies=[], independent=True, selection="I-T1", sim_timeout=60,
        positive_marker=r"^TITAN_PARSE_LOG: PASS cases=4 rejected=3$",
    ))
    for name in GOLDEN:
        source = by_id[f"i27r2_{name}"]
        if source["kind"] != "simulation" or source.get("mutant") or source.get("tb_control"):
            raise ValueError(f"{source['id']} is not a golden simulation")
        job = deepcopy(source)
        job.update(id=f"it1_{name}", selection="I-T1", dependencies=[added[0]], independent=False)
        jobs.append(job)
        added.append(job["id"])
    return added
