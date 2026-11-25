# Open threads (prune ruthlessly)

- **Timing:** N-13 real-pin top WNS +0.260 ns (secure), router-limited (protected mesh); OOC P&R +0.358. Closed at 20 ns.
- **Area:** S4 32,708 LUT. B1 closed; A3 parked (about -0.4k; reopen if merged LUT > 46,000 or an encoder path is near-critical);
  A2 only if the merged build runs out of headroom. Timing slack (p7_board +0.017 ns) is the tighter merge risk.
- **Vivado project updated 2026-11-03 to the release sources** (synth_p7 / impl_p7, demo board runs, new accurate-area runs
  synth_p7_area / impl_p7_area, 33 release simsets + 2 board smoke sets). Bitstreams: Kalash builds with
  scripts/build_release_bitstreams.tcl (not yet built on the release sources).
- **I-6, I-7, I-8 PASS (2026-11-03); release DUAL_LANE_10_20261103.** Next Lane-1 steps (integration contract, TMEM <-> NI
  bridge, CPU integration, merge) need Kalash's go.
- **RISC-V lane:** adapter double-capture bug open; integrate after the brief's steps pass. **Engineer 4:** P7 re-baseline.
- **Board bitstream:**
  - demo secrets, no TRNG, ingress trimmed, not run on hardware;
  - to keep the full design, the wrapper needs traffic on all tiles plus the raw injector.
