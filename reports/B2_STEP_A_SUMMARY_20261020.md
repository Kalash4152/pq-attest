# B-2 step a (M-F1 rev 7 R7.8.1): L2 trims T1 + T2. PASS, 7/7 jobs, one registry identity

Runs:
- `dual_lane_10_20261020_212836_fe37bf25`: 6 simulation/python jobs;
- `dual_lane_10_20261020_213342_6177f773`: the OOC job, run alone.

The registry was not regenerated between the two runs. All results are PASS_FRESH.

History, kept and not cited by the gate:
- `204125` INVALID: bench TB_TIMEOUT, a stimulus bug fixed in `4a336ff`;
- `211736` and `212015` PASS, but in an older identity, before the memory-coverage job was added.

| Job | Expected | Observed |
|---|---|---|
| l2trim_variant | pinned pre-trim blob, TB copy, provenance | PASS |
| l2trim_equiv | 300,008 / 0 (per-cycle compare of every output + 8 coverage checks) | 300,008 / 0 (1,087 accepted; reasons 1/2/3/4/7 seen) |
| l2trim_mut_tag_off_by_one | targeted kill | KILLED: 299,624 `L2TRIM_EQUIV_CYCLE` failures, run completed normally |
| l2trim_equiv_mem | 100,004 / 0 (MEM_RD_REQ / MEM_WR_REQ only) | 100,004 / 0 (141 RD_REQ and 30 WR_REQ heads delivered, 196 resets) |
| b2_endpoint_python | PASS | PASS |
| b2_pq_endpoint_sys | 37 / 0 (count unchanged) | 37 / 0 on the trimmed wrapper |
| b2_ooc_noc_l2_auth | latches 0, WNS/WHS ≥ 0, child check | **14,446 LUT / 13,973 FF**, WNS +3.743, WHS +0.256, 0 latches, child check PASS |

**Coverage per message type.** All 8 types are covered.

| Bench | Types | Wire lengths | Payload words |
|---|---|---|---|
| `l2trim_equiv` | 1, 3, 4, 5, 6, 7 | 10, 11, 17, 26 | 0, 1, 7, 16 |
| `l2trim_equiv_mem` | 0, 2 | 11, 12 | 1, 2 |

**Measured saving per `noc_l2_auth`.**

| | Before | After | Change |
|---|---|---|---|
| LUT | 16,235 | 14,446 | **−1,789** (estimate T1 + T2 ≈ −1,930) |
| FF | 15,249 | 13,973 | −1,276 (estimate −1,280) |
| top-level glue LUT | 4,156 | 2,367 | |

**Updated full-chip arithmetic (ESTIMATE, D-AREA-1 configuration).**
- The area matrix assumed trimmed glue of 1,127 LUT per L2 tile, which needs T1–T4. T1 + T2 measured give 2,367.
- T3 (key RAM) and T4 (LUTRAM quarantine) are planned inside steps c and d. On their attribution (≈ 940 + ≈ 210) the glue would come to ≈ 1,220, close to the 1,127 assumed.
- The 44,000 LUT (69 %) estimate stands, within ≈ +200 LUT (2 L2 tiles × ≈ 100).
- It is still an ESTIMATE. The measured gate is the step-d full-subsystem OOC (≤ 47,550 LUT).
