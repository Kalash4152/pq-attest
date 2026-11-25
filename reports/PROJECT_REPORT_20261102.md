# NOC_PQATTEST project report, 2026-11-02: counts, area, cost, power, timing

- **Branch:** noc/credit-integration (not merged). Design: M-F1 rev 7 / P7 (control-plane MAC, L2 on tiles 3 and 4, shared L2
  KMAC, guarded ingress, non-attested tiles refused).
- **Stage:** I-5 PASS (NOC 3 / 5, PQ 3 / 5), then STOPPED per Kalash (2026-10-29). Since then: Vivado project merged
  (all 99 benches + P7 runs) and the D5 board wrapper built to a bitstream (2026-11-02).
- **Validation:** HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.
- **Evidence classes:** section 1 rows are registered (scripts/dual_lane.py). Sections 4-6 board figures are a GUI build of
  NOC_PQATTEST.xpr run impl_p7_board: implemented, not registered, not run on hardware.
- **Sources:** reports/FINAL_PROGRESS_20261029.md, reports/I5_GATE_20261029.md,
  docs/reviews/IPD_III_Baseline_Area_Comparison_20261030.md (registered routed P7 vs baseline),
  NOC_PQATTEST.runs/impl_p7_board/*.rpt and its routed checkpoint (hierarchical utilization regenerated 2026-11-02),
  NOC_PQATTEST.runs/impl_1/*power_routed.rpt (baseline mesh).

## 1. Verification counts (registered)

| Increment | Date | Jobs accepted | Milestone |
|---|---|---|---|
| I-1 / I-1.5 | 2026-10-09 / 10-19 | PASS (baseline, hygiene) | |
| I-2 | 2026-10-19 | 36 / 36 | NOC-1, PQ-1 |
| I-3 | 2026-10-20 | 22 / 22 PASS_FRESH | NOC-2, PQ-2 |
| I-4 | 2026-10-20 | 33 / 33 | PQ-3 |
| B-4 / S1 (P7 area rework) | 2026-10-23 | 39 / 39 PASS_FRESH, 21 mutants killed | area decision |
| I-5 / S2 | 2026-10-29 | 30 / 30 (11 fresh, 19 identity-matched reuse) | NOC-3 |
| **Total I-2 .. I-5** | | **160 / 160** | |

**Registry** (scripts/dual_lane_jobs.json): 231 jobs:
- 99 simulation benches;
- 82 mutants;
- 17 Python reference checks;
- 15 OOC syntheses, 2 implementations;
- 6 gates, 10 reuse records.

**Security and behaviour results:**
- L2 attack matrix 30 / 0; 10 / 10 negative controls killed.
- C4 REVOKE latency max 486 cycles (bound 1,500); engine bounds P <= 269, Q <= 792, J <= 128.
- Latency:
  - L2 verdict 107 cycles;
  - attestation round trip 1,204 cycles idle (24.1 us at 50 MHz), 1,205-1,206 under load;
  - L2 overhead on a GRANT +113 to +115 cycles.

**Vivado project check (2026-11-02, not evidence):** all 99 benches compile and elaborate; 19 sampled benches give their
registered CHECKS with ERRORS 0; the board smoke bench passes 6 / 6.

## 2. Area: registered full design vs unsecured baseline (routed, xc7a100t, 20 ns)

| Metric | Baseline mesh (no security) | Secured P7 subsystem (OOC) | Delta | Ratio |
|---|---|---|---|---|
| Slice LUTs | 10,114 (16.0 %) | **43,935 (69.3 %)** | +33,821 | 4.34x |
| - LUT as logic | 8,398 | 41,921 | +33,523 | 4.99x |
| - LUT as distributed RAM | 1,716 | 2,014 | +298 | 1.17x |
| Flip-flops | 2,178 (1.7 %) | 36,102 (28.5 %) | +33,924 | 16.6x |
| Block RAM | 0 | 0.5 tile (1 RAMB18) | +0.5 | |
| DSP | 0 | 0 | 0 | |
| Timing endpoints | 18,237 | 125,491 | | 6.9x |

- **Budget:** 47,550 LUT. The registered P7 uses 43,935 routed (44,412 post-synthesis): 3,615 LUT of headroom (7.6 %).
- **Before D-AREA-1:** the I-4 full-chip estimate was 105-112k LUT. D-SYN-1/2 cut the measurement block from 120,581 to
  8,763 LUT.

**Where the area goes** (registered P7, routed):

| Function | LUT | FF | % of LUT |
|---|---|---|---|
| Mesh (3x2, 6 routers) | 10,263 | 1,934 | 23.4 % |
| Plain NIs (tiles 0, 1, 2, 5) | 647 | 324 | 1.5 % |
| Attestation endpoint (tile 3) | 16,345 | 15,629 | 37.2 % |
| RoT verifier (tile 4) | 7,871 | 8,129 | 17.9 % |
| L2 packet authentication (2 wrappers + shared engine) | 8,231 | 9,046 | 18.7 % |
| Ingress security (parsers, quarantine, merge, gates) | 438 | 754 | 1.0 % |
| Top glue / reset bridge | 147 | 286 | 0.3 % |
| **Security total** (endpoint, verifier, L2, ingress) | **32,885** | **33,558** | **74.8 %** |

**Cost of security:** +33.8k LUT and +33.9k FF over the bare mesh; three quarters of the secured design is security logic.

## 3. Timing

| Build | Clock | WNS | TNS | WHS | Status |
|---|---|---|---|---|---|
| Baseline mesh (impl_1, board pins) | 20 ns | +0.202 ns | 0 | +0.047 ns | met |
| Registered P7 OOC (S1-PNR-DIR, I/O budgets 5 ns) | 20 ns | **+0.165 ns** | 0 | +0.013 ns | met; flagged: below the +0.3 merge target |
| P7 board bitstream (impl_p7_board) | 100 MHz in -> MMCM -> 20 ns | **+0.592 ns** | 0 | +0.016 ns | met, 0 failing of 97,194 endpoints |

- **Why the board WNS is better:** the board build has fewer live paths and no 5 ns OOC I/O budgets (section 4).
- **Merge target:** the registered OOC figure (+0.165 ns) is the one that counts for the +0.3 ns target.
- **Hold:** on all three builds it is thin but met.

## 4. P7 board bitstream (D5, 2026-11-02)

- **Run:** `NOC_PQATTEST.runs/impl_p7_board/pq_p7_board_top.bit`.
- **Flow:** synth -> opt Explore -> place ExtraTimingOpt -> phys_opt / route / post-route phys_opt AggressiveExplore -> bitgen.
- **Checks:**
  - DRC 0 errors, 3 warnings (REQP-1840: memory stand-in RAMB18 controls driven by the reset-bridge register);
  - 0 critical warnings in synthesis and implementation.

| Resource | Used | Available | % |
|---|---|---|---|
| Slice LUTs | 33,970 | 63,400 | 53.6 |
| - logic / distributed RAM | 32,274 / 1,696 | | |
| Flip-flops | 28,276 | 126,800 | 22.3 |
| RAMB18 | 1 (0.5 tile) | 135 tiles | 0.4 |
| DSP | 0 | 240 | 0 |
| Bonded IOB | 11 | 210 | 5.2 |
| MMCM | 1 | 6 | 16.7 |

**By hierarchy (board build, routed):**
- mesh 9,959 LUT;
- endpoint 11,083;
- L2 pair 7,020 (shared engine 5,418);
- verifier 5,571 (shared KMAC 4,817);
- NIs + gates + ingress about 300;
- wrapper 34.

**Read this before quoting 33,970 as the design area.** The board build is about 10k LUT smaller than the registered 43,935
because synthesis removes logic the demo cannot exercise:
- **Ingress path for tiles 1, 2, 4, 5 and the tile-5 raw injector:** no traffic source drives them (`spoof_raw_valid` = 0, no
  apps on those tiles), so the quarantine and parsers drop to about 5 LUT, against about 438 in the registered build.
- **Fixed demo secrets:** keys, nonce, config and imem are constants, so part of the endpoint and measurement logic folds
  (endpoint 11,083 vs 16,345).
- **Status counters** (rejected, accepted and fault counts) that no LED reads are removed.

So the bitstream contains the attestation flow (RoT -> CHALLENGE -> RESPONSE -> GRANT / REVOKE), L2 MAC, the mesh, the gate
on tiles 0 and 3, and the memory stand-in. It does not contain the full ingress / quarantine hardware. **The full-design
area is the registered 43,935 LUT.**

## 5. Power (Vivado vectorless estimate, 25 C ambient, typical process)

| | Baseline mesh (impl_1) | P7 board (impl_p7_board) |
|---|---|---|
| Total on-chip | 0.160 W | **0.400 W** |
| Dynamic | 0.063 W | 0.302 W |
| - clocks | 0.011 | 0.032 |
| - logic | 0.023 | 0.069 |
| - signals | 0.028 | 0.095 |
| - MMCM | none | 0.106 |
| Static | 0.097 W | 0.098 W |
| Junction temperature | | 26.8 C |
| Confidence | Medium | **Low** |

- **Low confidence:** these are default toggle-rate estimates, not simulation-annotated (no SAIF).
- **The two builds see different activity:**
  - the baseline mesh is driven by free-running LFSR traffic;
  - the P7 board design is idle most of the time (one attestation, then switch-driven writes).
- **Use them as an upper-level order of magnitude, not a measurement.**
- **Without the MMCM** (0.106 W), P7 dynamic power is about 0.20 W, against 0.063 W for the bare mesh.

## 6. Cost summary

| Item | Value |
|---|---|
| Area cost of security (registered, routed) | +33.8k LUT (4.3x), +33.9k FF (16.6x); 74.8 % of the secured design |
| Budget headroom | 3,615 LUT under 47,550 (7.6 %) |
| Timing cost | WNS +0.202 -> +0.165 ns (registered OOC); still met at 50 MHz, below the +0.3 merge target |
| Latency cost | attestation round trip 1,204 cycles (24.1 us); L2 adds +113-115 cycles per GRANT; data plane unchanged (MAC on control only) |
| Power cost (estimate) | about 0.16 -> 0.40 W on-chip (0.10 W of it is the MMCM); low confidence |
| Device | xc7a100tcsg324-1: 53.6 % LUT used by the board build, 69.3 % by the registered full subsystem |

## 7. Open items

- **I-6 .. I-8:** C-1/C-2 retry, fault status, 0x2 map, K-3 binding; the SEC-1..4 matrix (6 attestation rows OPEN);
  regression; the N-13 full-top timing; the merge. All waiting for Kalash (plan: docs/proposals/PLAN_NEXT10_ALL_LANES_20261030.md).
- **Timing:** the registered WNS of +0.165 ns is below the +0.3 ns merge target.
- **Board bitstream:**
  - demo secrets (fixed keys and nonce); no TRNG;
  - full ingress logic trimmed (section 4);
  - not run on hardware;
  - to keep the full design in a bitstream, the wrapper needs traffic sources on all tiles and the raw injector.
- **Handoff lanes:**
  - RISC-V adapter not accepted (double-capture bug);
  - Engineer 4 tooling valid for rev 5 only;
  - briefs: docs/handoff/BRIEF_*_20261031.pdf.
