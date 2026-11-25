"""Register the seven-check S5R wire bench and all existing S5 checks."""
from copy import deepcopy

from register_titan_stage5 import SUBSYSTEM as OLD_S5
from register_titan_stage4 import TRACKER as OLD_TRACKER


def append_jobs(jobs):
    old = [job for job in jobs if job.get("selection") == "I-T5"]
    remap = {job["id"]: job["id"].replace("it5_", "it5r_", 1) for job in old}
    base = "rtl/dual_lane/titan"
    replace = {
        OLD_S5: f"{base}/s5r/pq_noc_subsystem_p7_t1.sv",
        OLD_TRACKER: f"{base}/titan_epoch_tracker_r1.sv",
        f"{base}/tb_titan_stamp_subsystem.sv": f"{base}/tb_titan_stamp_subsystem_r1.sv",
    }
    added = []
    for previous in old:
        job = deepcopy(previous)
        job.update(id=remap[previous["id"]], selection="I-T5R",
                   dependencies=[remap[d] for d in previous["dependencies"]])
        job["sources"] = [replace.get(source, source) for source in job["sources"]]
        if previous["id"] == "it5_stamp_wire":
            top = "tb_titan_stamp_subsystem_r1"
            job.update(top=top, config=dict(TOP=top, CHECKS=7), tb_time_limit="3ms", sim_timeout=600,
                       checks_basis="Same seven wire checks, actual two-slot overlap and bounded waits")
            job["required_lines"] += [[r"^STAMP_SYS_TAG_DIAG both_live=1 first=0 second=1$", 1]]
        elif previous["id"].startswith("it5_b0_"):
            pass
        job["oracle_files"] = sorted(set(job.get("oracle_files", []) + ["scripts/titan/prepare_stage5r.py"]))
        jobs.append(job)
        added.append(job["id"])
    assert len(added) == 20
    return added
