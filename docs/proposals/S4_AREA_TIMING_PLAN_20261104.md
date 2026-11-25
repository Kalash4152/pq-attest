# S4 proposal: area and timing together (2026-11-04, proposal only, nothing started)

Base: release DUAL_LANE_10_20261103. Inputs: routed release P&R (run 20261103_134238_44759502, rel_p7_pnr), the release
bitstreams (impl_p7_area 38,168 LUT / WNS +0.368 ns), reports/STEP_A_FULL_SCOUT_20261102.md. Estimates are labelled.

## 1. Where the time goes (measured, rel_p7_pnr)

- WNS +0.358 ns at 20 ns. **All 20 worst setup paths are inside the mesh routers** (protected RTL), router 1 / 4 / 5.
- Path: input FIFO `rd_ptr` (fanout 38) -> LUT-RAM read (RAMD32) -> XY route compute -> input arbiter -> output arbiter ->
  crossbar select -> crossbar valid -> next link register (`G_LINK_REG`). **21 logic levels; 80 % of the delay is routing**
  (logic 3.9 ns, nets 15.7 ns). The whole router pipeline (route compute + switch allocation + traversal) is one cycle.
- The crypto (endpoint / verifier / L2) is not in the top 20 since S3 (T1 removed the Keccak fan-out paths).

## 2. Where the area goes (measured, same run, LUT)

| Block | LUT | Note |
|---|---|---|
| mesh (6 routers, protected) | 10,201 | 1.5-2.0k per router |
| endpoint (KDF / tag KMAC + measurement SHA3, shared Keccak) | 9,956 | S3 applied |
| L2 pair (shared L2 KMAC engine + 2 wrappers) | 8,236 | |
| verifier (its own KMAC) | 7,894 | A2 would merge it into the L2 engine |
| NIs, gates, ingress, fault status, memory stand-in | about 1.4k | |

## 3. Options (area A*, B*; timing T*)

| ID | Change | Area (est.) | Timing (est.) | Signed bounds / protected RTL | Re-earn | Risk |
|---|---|---|---|---|---|---|
| A3 | kmac_encode specialised to each engine's fixed key / customization lengths | -1.0 to -1.5k LUT | small + (less routing pressure) | none / none | KMAC KATs, s8, l2e, endpoint, verifier, rel regression, N-13 | low-medium |
| B2 | L2 `int` extension counter -> 3 bits; verifier timer -> 17 bits | -0.1k | none | none / none | L2, verifier benches | low |
| T3 | **Flow only:** replicate `rd_ptr` (MAX_FANOUT), per-router pblocks, placer directive sweep (ExtraNetDelay_high, AltSpreadLogic_high) | 0 (+replicas) | unknown; route-dominated paths usually respond (hypothesis, to measure) | none / none (constraints only) | P&R only (netlist function unchanged) | low; a flow change is Kalash's decision (as S1-PNR-DIR) |
| T4 | **Router variant, cycle-identical lookahead routing:** compute the output port when the flit is written into the FIFO and store it with the flit; the read side skips route compute | about 0 | removes RAMD32 -> route-compute levels from the critical path (est. 2-3 of 21 levels) | none (same cycles) / **variant of protected router** in rtl/dual_lane | NOC-1..3 re-earn on the variant (transport, credits, N-6, N-7.5, N-8, hop probes) + rel + N-13 | medium-high |
| B1 | status counters 32 -> 16 bit | -0.4 to -0.6k | none | none (fault-status widths = SoC register map) | benches reading counts | low; held for the register map |
| A2 | verifier KMAC merged into the L2 engine at tile 4 | -4.5 to -6k | none | **changes signed bounds** (P / Q, C4, RTT) | broad | high; reserve |
| T5 | extra pipeline stage in the router (registered FIFO output / split allocation) | ~0 | large | **+1 cycle per hop: latency bounds change** | everything NoC | hard stop; not proposed |

## 4. Proposed sequence

1. **Phase 0, measure (no RTL, about half a day):** on the release netlist, (a) T3 flow variants, (b) an integration
   stress P&R with two CPU-tile placeholders (the RISC-V lane's tile netlist if available, otherwise 2 x 1.7k LUT of
   register-bounded filler placed at tiles 0 / 1) to measure the WNS the SoC will actually see. Report only.
2. **Phase 1 = S4 (one increment, no bound change):** A3 + B2 + the T3 flow settings that Phase 0 proves. Contract with
   frozen counts first; KMAC known-answer and equivalence benches + mutants; rel regression + N-13 + both bitstreams.
   Expected: about 36.6-37.1k LUT; timing per Phase 0.
3. **Phase 2 only if Phase 0 shows the integrated WNS below about +0.3 ns:** T4 lookahead router variant (Kalash decision:
   variant of protected RTL plus NOC-1..3 re-earn).
4. Held: B1 (register map), A2 (only if the CPUs overrun the budget). Not proposed: T5.
