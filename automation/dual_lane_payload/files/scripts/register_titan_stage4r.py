"""Register D10 epoch requalification, preserving every historical selection."""
from copy import deepcopy


def append_jobs(jobs):
    old = [job for job in jobs if job.get("selection") == "I-T4"]
    remap = {job["id"]: job["id"].replace("it4_", "it4r_", 1) for job in old}
    base = "rtl/dual_lane/titan"
    changes = {f"{base}/s4/pq_noc_subsystem_p7_t1.sv": f"{base}/s4r/pq_noc_subsystem_p7_t1.sv",
               f"{base}/titan_epoch_tracker.sv": f"{base}/titan_epoch_tracker_r1.sv",
               f"{base}/tb_titan_epoch.sv": f"{base}/tb_titan_epoch_r1.sv",
               f"{base}/tb_titan_epoch_subsystem.sv": f"{base}/tb_titan_epoch_subsystem_r1.sv"}
    controls = {
        "it4_kill_bad_grant": ("revoke", "EDGE_REVOKE", 1),
        "it4_kill_drop_revoke": ("held_high", "EDGE_HELD", 2),
        "it4_kill_early_wrap": ("trusted_fail", "EDGE_TRUSTED", 3),
    }
    for jid, (name, _, _) in controls.items():
        remap[jid] = f"it4r_kill_{name}"
    added = []
    for previous in old:
        source_id = previous["id"]
        job = deepcopy(previous)
        job.update(id=remap[source_id], selection="I-T4R",
                   dependencies=[remap[d] for d in previous["dependencies"]])
        job["sources"] = [changes.get(source, source) for source in job["sources"]]
        if source_id == "it4_epoch_unit":
            job.update(top="tb_titan_epoch_r1", checks=11, config=dict(TOP="tb_titan_epoch_r1", CHECKS=11, CASE=0),
                       checks_basis="Eleven rising-edge D10, priority, reset and wrap checks")
        elif source_id in controls:
            name, check, case_id = controls[source_id]
            job.update(top=f"tb_titan_epoch_r1_{name}",
                       config=dict(TOP="tb_titan_epoch_r1", CHECKS=1, CASE=case_id),
                       checks_basis=f"Single isolated D10 check {check}")
            pattern = rf"^\[FAIL\] {check}\b"
            job["tb_control"] = dict(errors=1, oracle=[pattern], allowed_fail=[pattern])
            job["sources"] = [f"{base}/s4r/titan_epoch_mut_{name}.sv" if "/titan_epoch_mut_" in s else s
                              for s in job["sources"]]
        elif source_id == "it4_mode4_smoke":
            job.update(top="tb_titan_epoch_subsystem_r1", config=dict(TOP="tb_titan_epoch_subsystem_r1", CHECKS=4))
        job["oracle_files"] = sorted(set(job.get("oracle_files", []) + ["scripts/titan/prepare_stage4r.py",
                                     "mutants/s4_mutants.json"]))
        jobs.append(job)
        added.append(job["id"])
    assert len(added) == 19
    return added
