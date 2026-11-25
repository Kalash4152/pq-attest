# I-5 / NOC-3 Track P3: exact CHECKS for `tb_noc_l2_auth` (derived from source, NOT run)

Status: implemented, oracle-checked (`l2_golden.py` check mode PASS). **Not compiled and not
XSim-simulated** (Vivado/XSim was not allowed during P3). Not registered in `dual_lane_jobs.json`.
Formal and hardware: NO.

## Rule from the TB source (`NOC_PQATTEST.srcs/sim_1/new/tb_noc_l2_auth.sv`)

`check()` is the only place that increments `checks`. Calls per step op (the main loop calls exactly
one task per step):

| Op (code) | Task | `check()` calls | Names |
|---|---|---|---|
| RESET (0) | `step_reset` | 1 | `:RESET_STATE` |
| RX (1) | `step_rx(...,0)` | 4 | `:COUNTERS`, `:REASON`, `:NI_DELIVERY`, `:SLOTS` |
| BURST (2) | `step_rx(...,1)` | 4 | same |
| TX (3) | `step_tx` | 2 | `:TX_WIRE_BIT_EXACT`, `:SLOTS` |
| PROBE (4) | `step_probe` | 1 | `:TX_READY_IS_n` |
| INJECT (5) | `step_inject` | 0 | (INFO line only) |
| after loop | | 1 | `NI_NO_ABORT` |

All calls are unconditional (no check sits inside an `if`), so CHECKS depends only on the step table.
The `WAIT_IDLE_BOUND` and unknown-op paths increment `errors` only (RESULT FAIL, CHECKS unchanged).
The config `$fatal` (more than one NEG define) and `TB_TIMEOUT` `$fatal` are not checks.

## Step tables (from `vectors/l2_golden.svh` `l2_step_op`, MODE = `l2_golden.MODES` index)

| Mode | Define | RESET | RX | BURST | TX | PROBE | INJECT | Steps |
|---|---|---|---|---|---|---|---|---|
| 0 ENFORCE | (none) | 2 | 32 | 1 | 4 | 2 | 1 | 42 |
| 1 NEG_MAC | `L2_NEG_MAC` | 1 | 3 | 0 | 1 | 0 | 0 | 5 |
| 2 NEG_SEQUENCE | `L2_NEG_SEQUENCE` | 1 | 5 | 0 | 2 | 0 | 0 | 8 |
| 3 NEG_EPOCH | `L2_NEG_EPOCH` | 1 | 2 | 0 | 0 | 0 | 0 | 3 |

## Derived CHECKS

- ENFORCE: 2x1 + (32+1)x4 + 4x2 + 2x1 + 1x0 + 1 = 2 + 132 + 8 + 2 + 0 + 1 = **145**
- NEG_MAC: 1 + 3x4 + 1x2 + 1 = **16**
- NEG_SEQUENCE: 1 + 5x4 + 2x2 + 1 = **26**
- NEG_EPOCH: 1 + 2x4 + 1 = **10**

These equal `tb_checks` in `vectors/l2_golden.json`, which the generator computes independently
from the step table. Expected for a passing run: `CHECKS : <n>`, `ERRORS : 0`, `RESULT : PASS`; the
three NEG modes must also print `NEGATIVE_CONTROL_EFFECTIVE` (set only when an oracle-marked attack
step delivered exactly the oracle's expected head/payload words).

Counts must be frozen in `scripts/dual_lane_jobs.json` **before** the first run (CLAUDE.md); P3 did
not touch the registry. The BURST `:COUNTERS` check uses `rejected delta >= 2` (lower bound) because
C-6 says per-packet overload counts must not be frozen yet; acceptance/delivery in the burst is exact.
