"""Freeze TITAN S2 unit, negative-control, and passive bound observations."""
from copy import deepcopy

BASE = "rtl/dual_lane/titan"
UNIT = f"{BASE}/tb_titan_mon_unit.sv"
MONITOR = f"{BASE}/titan_finality_monitor.sv"
MUTATION_BUILDER = "scripts/titan/prepare_monitor_controls.py"

UNIT_CASES = (
    "MON_CLEAN_WRITE", "MON_CLEAN_READ", "MON_P1_STALE_COMMIT", "MON_P2_REVOKED_READ",
    "MON_P4_DUPLICATE", "MON_SD_SLOT_EXPIRY", "MON_M3_LATE_COMMIT", "MON_RESET_DISCARDS_OPEN",
    "MON_BOTH_TAGS", "MON_TAG_REUSE", "MON_P3_UNKNOWN",
)


def append_jobs(jobs):
    by_id = {job["id"]: job for job in jobs}
    controls = ("p1", "tag", "reset")
    positive = dict(
        id="it2_mon_unit", kind="simulation", top="tb_titan_mon_unit",
        sources=[UNIT, MONITOR], oracle_files=[MUTATION_BUILDER], checks=11, defines=[],
        dependencies=[], independent=True, build_timeout=1200, sim_timeout=600,
        selection="I-T2", include_dirs=[], tb_time_limit="100us",
        config=dict(TOP="tb_titan_mon_unit", CHECKS=11, CASE=0),
        checks_basis="Seven monitor sequences and four edge cases, one exact six-counter comparison per case",
        required_lines=[[rf"^\[PASS\] {case}$", 1] for case in UNIT_CASES],
    )
    added = [positive]
    for name, case_id in zip(controls, (3, 9, 8)):
        target = UNIT_CASES[case_id - 1]
        case = deepcopy(positive)
        case.update(
            id=f"it2_kill_{name}", top=f"tb_titan_mon_case_{name}", sources=[UNIT, f"{BASE}/titan_mon_mut_{name}.sv"],
            dependencies=[positive["id"]], independent=False,
            checks=1, checks_basis=f"One isolated exact counter vector for {target}",
            config=dict(TOP="tb_titan_mon_unit", CHECKS=1, CASE=case_id),
            required_lines=[[r"^\$finish called at time\s*:", 1]],
            tb_control=dict(errors=1, oracle=[rf"^\[FAIL\] {target}\b"],
                            allowed_fail=[rf"^\[FAIL\] {target}\b"]),
        )
        added.append(case)
    for workload in ("matched_secure", "matched_secure_contended"):
        case = deepcopy(by_id[f"it1_{workload}"])
        case.update(id=f"it2_{workload}_bound", top="tb_titan_mon_b0", selection="I-T2",
                    dependencies=[entry["id"] for entry in added[:4]], independent=False)
        case["sources"].extend([MONITOR, f"{BASE}/titan_mon_bind.sv"])
        case.setdefault("required_lines", []).append([
            r"^TITAN_SUMMARY P1=0 P2=0 P3=0 P4=0 P6=X M3=0 SD=0 maxlat=[1-9]\d*\s*$", 1
        ])
        added.append(case)
    jobs.extend(added)
    return [job["id"] for job in added]
