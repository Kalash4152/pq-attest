# S4 follow-up (measurement only, not evidence): keeping NoC hierarchy under the S4 flow, 2026-11-05

Question: after the S4 gate FAIL (s4_p7_pnr WNS -0.018 ns, reports/S4_GATE_20261104.md), can the S4 area be kept with
timing margin by stopping `-flatten_hierarchy rebuilt` from restructuring the protected NoC? Kalash delegated the decision.
Same sources as s4_p7_pnr (S4 list), top pq_noc_subsystem_p7 (all ports), OOC, 20 ns, S4-F1 + F2 synthesis, S1-PNR-DIR
implementation; a synthesis-only XDC adds KEEP_HIERARCHY. Scripts and reports in this folder.

| Run | Kept | LUT | Mesh LUT | LUTRAM (all) | WNS ns | WHS ns | Worst path |
|---|---|---|---|---|---|---|---|
| release (rel_p7_pnr) | flatten none | 37,666 | ~10.2k | 2,014 | +0.358 | +0.014 | router 4 west VC1 FIFO -> link reg |
| s4_p7_pnr (registered FAIL) | nothing | 31,476 | ~10.1k | 2,014 | -0.018 | +0.020 | router 3 local VC2 FIFO -> east link reg, 27 levels |
| H1 | mesh + all 277 cells under it | 35,324 | 13,316 | 2,794 | **-0.365** | +0.015 | router 1 -> west link reg, 24 levels |
| H2 | the 6 router instances | 33,796 | 12,024 | 2,496 | **-0.477** | **-0.049** | router 1 -> south link reg, 25 levels |

Findings:
- Hard KEEP_HIERARCHY is stricter than `-flatten_hierarchy none`: it also blocks constant propagation and LUTRAM / logic
  merging across the kept boundaries, so the mesh grows by 1.8k-3.1k LUT and timing gets worse, not better.
- Under S4 the router -> link-register paths sit around 0 ns and move by about +-0.5 ns between netlists (+0.505 area study,
  +0.002 s4_soc_pnr, -0.018 s4_p7_pnr, -0.365 H1, -0.477 H2). No flow setting tried gives a margin that survives a different
  placement (the project bitstream run is one).
- Conclusion: the -16 % S4 area cannot be made timing-safe by flow settings. The limiter is the protected router's path
  depth (21+ levels at 20 ns). Timing-safe ways: (C) the lookahead router variant (registered RTL variant, needs Kalash), or
  give up flatten (about -1 % area only, area study S2).

HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.
