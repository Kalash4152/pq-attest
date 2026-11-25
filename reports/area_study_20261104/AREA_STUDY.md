# Area study for S4 (measurement only, no RTL / registry change), 2026-11-04

Scratch synthesis / P&R on the release sources (DUAL_LANE_10_20261103), Vivado 2024.1, xc7a100tcsg324-1, 20 ns, OOC unless
stated; release P&R directives. Not registered evidence. Raw numbers: area_results.txt.

## Synthesis (post opt_design), LUT / FF

| Run | Flow / change | LUT | FF |
|---|---|---|---|
| S0 | release flow (-flatten_hierarchy none) | 38,020 | 33,038 |
| S1 | -flatten_hierarchy rebuilt | 35,802 | 32,951 |
| S2 | none + -directive AreaOptimized_high | 37,732 | 32,943 |
| S3 | rebuilt + AreaOptimized_high | 33,399 | 32,872 |
| S4 | rebuilt + SoC top (debug / statistics exports unconnected) | 33,097 | 31,170 |
| S5 | rebuilt + AreaOptimized_high + A5 (KMAC wrapper state copy removed) | 31,749 | 28,021 |
| S6 | S4 + AreaOptimized_high | 33,097 | 31,170 |
| S7 | S6 + A5 | 32,517 | 26,332 |

## Routed

| Run | LUT | FF | WNS (ns) | WHS (ns) | paths < 0.5 ns |
|---|---|---|---|---|---|
| release rel_p7_pnr (registered) | 37,666 | 33,038 | +0.358 | +0.014 | 9 |
| S5 routed (full exports kept) | 31,476 | 28,021 | **-0.018** | +0.020 | 634 |
| **S7 routed (SoC top: exports pruned)** | **32,014** | **26,332** | **+0.505** | +0.014 | 0 |
| SoC proxy, release recipe + 2 CPU placeholders (Phase 0) | 41,012 total | | +0.128 | +0.023 | 14 |
| **SoC proxy, S7 recipe + 2 CPU placeholders** | **34,184 total** (subsystem 30,795) | 30,953 | +0.007 | +0.040 | 393 |

## Findings

- A5 (withdrawn in S3 because it ADDED +790 LUT per engine under -flatten_hierarchy none) saves area once the hierarchy
  is flattened: the select logic merges with the absorb XOR across the old boundary.
- AreaOptimized_high helps only together with flattening.
- Leaving the observation-only exports unconnected at the SoC top removes their counters and registers; with flattening
  that logic disappears across blocks (no subsystem RTL change; the benches keep the ports).
- Area falls 15-17 % (subsystem about 30.8-32.0k LUT routed); timing stays router-limited: in the SoC proxy WNS is
  +0.007 ns (vs +0.128 with the release recipe, both inside the 0.1-0.2 ns placement variation). Area work does not fix
  the router paths; the lookahead router variant remains the timing lever.
- Not measured: residual A3 / B2 (est. a few hundred LUT), per-block synthesis strategies (area on crypto, performance on
  the mesh).
