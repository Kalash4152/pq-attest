"""Register the standalone S3 package check without touching the datapath."""


def append_jobs(jobs):
    job_id = "it3_pkg"
    jobs.append(dict(
        id=job_id, kind="simulation", top="tb_titan_pkg", selection="I-T3",
        sources=["rtl/dual_lane/NOC_PKG.sv", "rtl/dual_lane/titan_pkg.sv",
                 "rtl/dual_lane/titan/tb_titan_pkg.sv"],
        defines=[], checks=2067, dependencies=[], independent=True,
        build_timeout=1200, sim_timeout=600, tb_time_limit="10us", include_dirs=[],
        config=dict(TOP="tb_titan_pkg", CHECKS=2067),
        required_lines=[
            [r"^TITAN_PKG_CONTROL_VECTORS=2048 EPOCH_REPLACEMENTS=131072 LEGACY_TAGS=2 MESSAGE_CODES=16$", 1],
            [r"^\$finish called at time\s*:", 1],
        ],
        checks_basis="Profile width, 2048 raw controls, 2 legacy tags, 16 message codes",
    ))
    return [job_id]
