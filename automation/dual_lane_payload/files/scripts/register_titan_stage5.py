"""Freeze S5 unit controls, wire-observation evidence and mode-zero regressions."""
from copy import deepcopy
import json
from pathlib import Path

from register_titan_stage1 import GOLDEN
from register_titan_stage4 import BASE, PACKAGE, mode_zero_sources

STAMP = f"{BASE}/titan_epoch_stamp.sv"
PKG = "rtl/dual_lane/titan_pkg.sv"
UNIT = f"{BASE}/tb_titan_stamp.sv"
INTEGRATION = f"{BASE}/tb_titan_stamp_subsystem.sv"
CATALOG = "mutants/s5_mutants.json"
SUBSYSTEM = f"{BASE}/s5/pq_noc_subsystem_p7_t1.sv"
GENERATOR = "scripts/titan/prepare_stage5.py"


def add_stamp_sources(job):
    mode_zero_sources(job, SUBSYSTEM)
    if SUBSYSTEM in job["sources"]:
        job["sources"].extend([PKG, STAMP])


def append_jobs(jobs):
    by_id = {job["id"]: job for job in jobs}
    recheck_pkg = deepcopy(by_id["it3_pkg"])
    recheck_pkg.update(id="it5_pkg_portable", selection="I-T5")
    unit = dict(
        id="it5_stamp_unit", kind="simulation", top="tb_titan_stamp", selection="I-T5",
        sources=[PACKAGE, PKG, STAMP, UNIT], oracle_files=[GENERATOR, CATALOG],
        checks=5, defines=[], dependencies=[recheck_pkg["id"]], independent=False,
        include_dirs=[], build_timeout=1200, sim_timeout=600, tb_time_limit="100us",
        config=dict(TOP="tb_titan_stamp", CHECKS=5, CASE=0),
        required_lines=[[r"^\$finish called at time\s*:", 1]],
        checks_basis="Stamp holds for 50 cycles, non-memory pass, overwrite, reset, and valid withdrawal",
    )
    added = [recheck_pkg, unit]
    mutations = json.loads((Path(__file__).resolve().parents[1]/CATALOG).read_bytes())
    for case_id, mutant in enumerate(mutations, 1):
        name, target = mutant["id"], mutant["targeted_check"]
        control = deepcopy(unit)
        fail = rf"^\[FAIL\] {target}\b"
        control.update(
            id=f"it5_kill_{name}", top=f"tb_titan_stamp_{name}", checks=1,
            sources=[PACKAGE, PKG, f"{BASE}/s5/titan_stamp_mut_{name}.sv", UNIT],
            dependencies=[unit["id"]], config=dict(TOP="tb_titan_stamp", CHECKS=1, CASE=case_id),
            checks_basis=f"One targeted observation, {target}",
            tb_control=dict(errors=1, oracle=[fail], allowed_fail=[fail]),
        )
        added.append(control)

    real = deepcopy(by_id["it1_matched_secure"])
    top = "tb_titan_stamp_subsystem"
    real.update(
        id="it5_stamp_wire", top=top, selection="I-T5", checks=7,
        sources=[s for s in real["sources"] if not s.endswith("/tb_matched_memory_v10.sv")],
        dependencies=[job["id"] for job in added], independent=False,
        config=dict(TOP=top, CHECKS=7),
        checks_basis="Seven checks including 1,000 wire HEADs, both live tags, responses and stalls",
    )
    add_stamp_sources(real)
    real["sources"].append(INTEGRATION)
    real.setdefault("required_lines", []).append(
        [r"^TITAN_STAMP_RANDOM requests=1000 writes=\d+ reads=\d+ wire=1000$",1])
    added.append(real)
    for name in GOLDEN:
        job = deepcopy(by_id[f"it1_{name}"])
        job.update(id=f"it5_b0_{name}", selection="I-T5", dependencies=[real["id"]], independent=False)
        add_stamp_sources(job)
        added.append(job)
    jobs.extend(added)
    return [job["id"] for job in added]
