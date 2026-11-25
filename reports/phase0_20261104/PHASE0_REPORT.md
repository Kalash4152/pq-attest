# Phase 0 report (S4 measurement only, no RTL change), 2026-11-04

Scratch P&R measurements, Vivado 2024.1, xc7a100tcsg324-1, 20 ns. Not registered evidence. Plan:
docs/proposals/S4_AREA_TIMING_PLAN_20261104.md.

## 1. Flow-only timing settings (release netlist, OOC, HD.CLK_SRC model)

| Variant | Change vs the release flow (S1-PNR-DIR) | WNS (ns) | WHS (ns) | paths < 0.5 ns | paths < 1.0 ns |
|---|---|---|---|---|---|
| V0 | none | **+0.358** | +0.014 | 9 | 209 |
| V1 | forced replication of the 288 router FIFO rd_ptr nets | +0.247 | **-0.030** | 17 | 218 |
| V2 | place ExtraNetDelay_high | +0.295 | +0.015 | 8 | 206 |
| V3 | place AltSpreadLogic_high | +0.358 | +0.014 | 9 | 209 |
| V4 | place Explore | +0.087 | +0.016 | 51 | 313 |

**Finding:** no placer or replication setting beats the release flow; replication even breaks hold. Flow-only tuning (T3)
is dropped from S4.

## 2. Integration stress (the SoC timing the CPUs will see)

Real-pin N-13 secure top with two CPU-tile placeholders driving tiles 0 and 1 (cpu_placeholder.sv; 32 x 32 LUT-RAM
register file, ALU, pipelined datapath, real NoC application traffic), release directives:

| Run | Placeholder size (each) | Total LUT | WNS (ns) | WHS (ns) | paths < 0.5 ns | Worst path |
|---|---|---|---|---|---|---|
| reference: N-13 secure, no CPUs (registered) | - | 38,054 | +0.260 | +0.016 | - | router 4 |
| stress, small placeholders | 1,126 LUT / 616 FF | 39,765 | +0.045 | +0.024 | 58 | router 4 |
| stress, **full-size placeholders** | **1,702 LUT** (real tile: 1,674) | 41,012 | **+0.128** | +0.023 | 14 | router 1 |

**Findings:**
- With two real-size CPU tiles beside the NoC, the SoC still closes at 20 ns, but only by **+0.05 to +0.13 ns**
  (placement run-to-run variation is about 0.1-0.2 ns here). The +0.3 ns merge target is not met.
- Every one of the worst 20 paths stays inside the mesh routers (routers 1 and 4, next to the CPU tiles): FIFO read
  pointer -> LUT-RAM head read -> route compute -> input / output arbitration -> crossbar -> link register; 20-22 logic
  levels, 74-78 % routing. The CPU placeholders are never critical.
- Not yet included: the TMEM <-> NI bridge (~1.5k LUT est.), which adds more congestion near the routers.

## 3. What this means for S4

- **Area (A3 + B2, about -1.1 to -1.6k LUT est.)** is still worth doing (more room for the CPUs and the bridge, less
  congestion), but it does not touch the limiting paths, which are inside the routers.
- **The timing lever is the router itself.** A cycle-identical lookahead-routing variant (route computed when the flit is
  written into the input FIFO, stored with it) takes the LUT-RAM read and the route compute off the critical path with no
  latency or signed-bound change. It is a variant of protected RTL (rtl/dual_lane copy; the original stays untouched) and
  needs the NoC evidence (NOC-1..3, credits, N-6, N-7.5, N-8, hop probes) re-earned on it: **Kalash's decision**.
- Not proposed: an extra router pipeline stage (+1 cycle per hop: signed latency bounds, hard stop); flow-only tuning.
