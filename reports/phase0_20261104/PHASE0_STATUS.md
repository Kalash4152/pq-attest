# Phase 0 (S4 measurement, no RTL change): status at stop, 2026-11-04 ~03:45

Scratch measurements on the release netlist (rel_p7_pnr synth.dcp of run 20261103_134238_44759502), OOC flow with the
HD.CLK_SRC model, Vivado 2024.1. Not evidence. Results (results.txt):

| Variant | Change vs release flow | WNS | WHS | paths < 0.5 ns | paths < 1.0 ns | Note |
|---|---|---|---|---|---|---|
| V0 | none (release S1-PNR-DIR) | +0.358 | +0.014 | 9 | 209 | reproduces the release exactly |
| V1 | + forced replication of the 288 router FIFO rd_ptr nets | +0.247 | **-0.030** | 17 | 218 | worse; hold violation: reject |
| V2 | place ExtraNetDelay_high | +0.295 | +0.015 | 8 | 206 | worse WNS, slightly fewer near-critical paths |
| V3 | place AltSpreadLogic_high | +0.358 | +0.014 | 9 | 209 | identical to V0 (no effect) |
| V4 | place Explore | not finished | | | | stopped at Kalash's request |

Reading so far: the placer / replication knobs do not improve the router paths; the release flow is already the best
of those tried. This supports the lookahead-router variant (T4) as the real timing lever, still to be confirmed by the
integration stress run.

Not run yet: V4; the integration stress P&R (stress.tcl: N-13 secure top with two CPU-sized placeholders on tiles 0/1,
cpu_placeholder.sv, pq_phase0_stress_top.sv; compiled and elaborated cleanly). Resume:
  cd vivado_sim/_phase0 && vivado -mode batch -source stress.tcl -tclargs ExtraTimingOpt   (alone)
Then write the Phase 0 report and the S4 contract (A3 + B2 + any proven flow setting).
