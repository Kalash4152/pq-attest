"""Register S4 epoch tests and a fresh mode-zero replay of the S1 selection."""
from copy import deepcopy

from register_titan_stage1 import GOLDEN

BASE = "rtl/dual_lane/titan"
PACKAGE = "rtl/dual_lane/NOC_PKG.sv"
GATE = "rtl/dual_lane/noc_attest_gate.sv"
UNIT = f"{BASE}/tb_titan_epoch.sv"
TRACKER = f"{BASE}/titan_epoch_tracker.sv"
SUBSYSTEM = f"{BASE}/s4/pq_noc_subsystem_p7_t1.sv"
B0_SUBSYSTEM = "rtl/dual_lane/pq_noc_subsystem_p7_i9.sv"
UPDATE_PROOF = "scripts/titan/prepare_stage4.py"


def mode_zero_sources(job, subsystem):
    sources = job["sources"]
    if B0_SUBSYSTEM in sources:
        job["sources"] = [subsystem if source == B0_SUBSYSTEM else source for source in sources]
        job["sources"].append(TRACKER)


def append_jobs(jobs):
    by_id = {job["id"]: job for job in jobs}
    unit = dict(
        id="it4_epoch_unit", kind="simulation", top="tb_titan_epoch", selection="I-T4",
        sources=[PACKAGE, GATE, TRACKER, UNIT], oracle_files=[UPDATE_PROOF],
        checks=13, defines=[], dependencies=[], independent=True, include_dirs=[],
        build_timeout=1200, sim_timeout=600, tb_time_limit="100us",
        config=dict(TOP="tb_titan_epoch", CHECKS=13, CASE=0),
        required_lines=[[r"^\$finish called at time\s*:", 1]],
        checks_basis="Thirteen defined gate, tracker, wrap and reset observations",
    )
    added = [unit]
    for case_id, (name, oracle) in enumerate(
        (("bad_grant", "EPOCH_BAD_GRANT"), ("drop_revoke", "EPOCH_REVOKE"), ("early_wrap", "EPOCH_MODULO_WRAP")), 1
    ):
        variant = deepcopy(unit)
        fail_line = rf"^\[FAIL\] {oracle}\b"
        variant.update(
            id=f"it4_kill_{name}", top=f"tb_titan_epoch_{name}", checks=1,
            sources=[PACKAGE, GATE, f"{BASE}/s4/titan_epoch_mut_{name}.sv", UNIT],
            dependencies=[unit["id"]], independent=False,
            config=dict(TOP="tb_titan_epoch", CHECKS=1, CASE=case_id),
            checks_basis=f"One targeted observation, {oracle}",
            tb_control=dict(errors=1, oracle=[fail_line], allowed_fail=[fail_line]),
        )
        added.append(variant)

    smoke = deepcopy(by_id["it1_matched_secure"])
    smoke_top = "tb_titan_epoch_subsystem"
    smoke.update(
        id="it4_mode4_smoke", top=smoke_top, selection="I-T4", checks=4,
        sources=[s for s in smoke["sources"] if not s.endswith("/tb_matched_memory_v10.sv")],
        dependencies=[j["id"] for j in added], independent=False,
        config=dict(TOP=smoke_top, CHECKS=4),
        checks_basis="Mode 4 subsystem reset, grant, revoke and per-tile locality",
    )
    mode_zero_sources(smoke, SUBSYSTEM)
    smoke["sources"].append(f"{BASE}/{smoke_top}.sv")
    added.append(smoke)

    for name in GOLDEN:
        job = deepcopy(by_id[f"it1_{name}"])
        job.update(id=f"it4_b0_{name}", selection="I-T4",
                   dependencies=[smoke["id"]], independent=False)
        mode_zero_sources(job, SUBSYSTEM)
        added.append(job)
    jobs.extend(added)
    return [job["id"] for job in added]
