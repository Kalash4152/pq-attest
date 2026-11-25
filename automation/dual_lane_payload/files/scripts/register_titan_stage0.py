"""Freeze Stage 0 B0/Stage-0 TITAN pairs from the existing I-27-R2 definitions."""
from copy import deepcopy

from prepare_titan import variant_map, PROVENANCE

BENCHES = {
    "inflight": "i27r2_inflight",
    "attack": "i27r2_attack_approve_changed",
    "contention": "i27r2_contention",
    "phase": "i27r2_phase_sweep",
}


def append_jobs(jobs, *, revision=0):
    by_id = {job["id"]: job for job in jobs}
    mapping = variant_map()
    added = []
    for name, source_id in BENCHES.items():
        for variant in ("b0", "t1"):
            job = deepcopy(by_id[source_id])
            suffix = "_r1" if revision == 1 else ""
            job.update(id=f"it0_{name}_{variant}{suffix}", selection="I-T0", dependencies=[], independent=True)
            if variant == "t1":
                if not set(mapping) <= set(job["sources"]):
                    raise ValueError(f"{source_id}: missing pinned I-9 closure")
                job["sources"] = [mapping.get(path, path) for path in job["sources"]]
                if revision == 0:
                    job["defines"] = [*job["defines"], "TITAN_T1"]
                job["oracle_files"] = sorted(set(job["oracle_files"] + [
                    "scripts/prepare_titan.py", PROVENANCE.as_posix(), *mapping,
                ]))
            jobs.append(job)
            added.append(job["id"])
    return added
