# I-3 merge proof for the hand-resolved generator — 2026-10-20

**Result: PASS. No N2 or Q2 job differs from its single-patch build.**

## Method (no simulator)

The proof ran in a detached worktree outside the repo folder (`C:\npqc_mergeproof`, base `5f46799` = `8893c11^`,
removed afterwards). Script: scratchpad `merge_proof.py`.
1. `build_registry(check_files=False)` produced three registries from the base `prepare_dual_lane.py`: unpatched,
   with `reports/i3_n2/prepare_dual_lane.i3_n2.patch` alone, and with `reports/i3_q2/prepare_dual_lane.i3_q2.patch` alone.
2. "Touched" means jobs that differ from the unpatched build. Every touched job was compared field by field (every
   key: sources, defines, checks, judge/oracle fields, config, dependencies, timeouts, selection, ...) against the
   same job in the committed `8893c11:scripts/dual_lane_jobs.json`.
3. Any job that changed in `8893c11` without being touched by either patch was listed and explained.

## Results

| Check | Result |
|---|---|
| N2-touched jobs (15): perf_m0/m1, perf_ctrl_corrupt/drop/stall, n75_* ×6, perf_matrix, perf_hop_probes, pfc_perf_m0/m1 | 0 field differences |
| Q2-touched jobs (8): endpoint_python, pq_endpoint_unit/sys, 4 mutants, pq_endpoint_control_after | 0 field differences |
| Jobs removed | `pq_endpoint` (blocker) by Q2 only; same set removed in final |
| `increments['I-3']` | equals N2's I-3 list followed by Q2's (21 jobs) |
| Stage NOC-2 / PQ-2 | identical to the N2-only / Q2-only builds |
| All other stages | identical to base |
| Changed in final, not by either patch | `pfc_ni_ooc`, `pfc_mesh_gate`: only `min_free_ram_gb` 5 → 2.0, plus new `min_pagefile_gb=8` and `ram_gate_basis` (the intended I-2 open-item fix) |

## Identity inputs other than the registry

Every job's identity also hashes `scripts/dual_lane.py`, `scripts/dual_lane_verify.py`, `controlled_diagnostics.py`,
`dual_lane_preflight.py`, the support scripts and `dual_lane_config.json`. In `8893c11` two of these changed for
*all* jobs, as the separate N2 judge patch and Q2 mutation patch require:
- `dual_lane_verify.py` (`reports/i3_n2/dual_lane_verify.i3_n2.patch`);
- `dual_lane.py` (`reports/i3_q2/mutation.i3_q2.patch`).

Both applied cleanly (`git apply --check`) on top of each other. They are not part of the generator merge.
Source and oracle file lists are covered by the field comparison above.
