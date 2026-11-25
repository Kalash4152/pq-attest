---
title: "Area and Timing Optimization Playbook"
subtitle: "Every LUT/FF reduction and slack decision made on PQ-Attest, with numbers, provenance, costs and the reusable rule behind each. 20 Nov 2026"
---

# 0. How to read this

**Sources** (all read from the live repo `C:\vivado_verilog_proj\NOC_PQATTEST` on 20 Nov 2026):

- `docs/DECISION_REGISTER.md`;
- `docs/decisions/S3_T1_A1_CONTRACT.md` and `S4_AREA_CONTRACT.md`;
- studies: `reports/STEP_A_AREA_TIMING_20261102.md`, `reports/b1_trims/B1_AREA_TRIMS_20261020.md`, `reports/area_study_20261104/AREA_STUDY.md`, `reports/s4_hier_study_20261105/HIER_STUDY.md`, `reports/B1_A3_AREA_PROBE_20261105.md`;
- gate and build reports: `reports/S1_GATE_20261023.md`, `S3_GATE_20261102.md`, `S4_GATE_20261105_REV1.md`, `MERGED_BUILD_20261107.md`.

**Provenance labels.** Unless stated otherwise, every number is Vivado 2024.1, xc7a100tcsg324-1, 20 ns (50 MHz), post-route. Each number also carries one of these labels:

| Label | Meaning |
|---|---|
| **M** | measured in a registered run |
| **S** | scratch measurement (real tool run, not registered evidence) |
| **E** | estimate |

All of this is FPGA utilisation and is not ASIC area.

**The one-line lesson:** the biggest wins came from **architecture** (what exists at all), then **sharing hardware that is never busy at the same time**, then **removing fan-out and runtime indexing**, and only last from **tool settings**. Tool settings gave real area, but they also caused the only timing failure, and fixing that took a flow-level split.

# 1. The trajectory (what actually happened)

| Point (date) | Design | LUT | FF | WNS (ns) | Label | What changed |
|---|---|---|---|---|---|---|
| Option matrix (20 Oct) | full chip, every tile wrapped, 9 Keccak cores | 75,556 | – | – | E | starting configuration: 119 % of the device |
| Rejected option (20 Oct) | all 6 tiles L2 + shared KMAC + trims | ≈ 47,952 (≈ 49.5–50k with a 12-requester mux) | – | – | E | over the 75 % budget |
| D-AREA-1 chosen (20 Oct) | L2 on tiles 3/4 + one shared L2 KMAC + time-multiplexed KDF/tag + trims T1–T4 | ≈ 44,000 | – | – | E | architecture decision |
| S1 default directives (22 Oct, run 234618) | P7 subsystem, OOC | – | – | **−0.417** | M (FAIL) | default implementation directives |
| S1 directive flow (23 Oct, run 121951) | same netlist | 43,935 (synth 44,412) | 36,102 | **+0.165** | M | implementation directives only |
| S3 (2 Nov) | + Keccak select replication, shared tile-3 Keccak, 1-block SHA3 | **37,398** | 32,810 | +0.126 | M | −6.5k LUT; timing now router-limited |
| Release rel_p7_pnr (3 Nov) | S3 + I-6/I-7 features | 37,666 | 33,038 | +0.358 | M | feature growth |
| S4 rev 0 (4 Nov) | + flatten rebuilt + AreaOptimized_high + state-copy removal | 31,476 | 28,021 | **−0.018** | M (FAIL) | area −16 %, timing broke |
| S4 rev 1 (5 Nov) | + mesh synthesized separately with release settings | **32,457** | 28,021 | **+0.334** | M | area kept, timing restored |
| N-13 secure top (5 Nov) | real pins, all outputs | **32,708** (release 38,054, **−14.0 %**) | 30,841 | +0.275 | M | gate PASS |
| Merged SoC (7 Nov) | + 2 PicoRV32 tiles + firmware | 34,987 | 25,276 | +0.237 | M | CPUs ≈ 2.6–2.7k LUT each |
| RC1 board (I-25) | release board | 34,952 | – | +0.120 | M | – |
| Rev-10 (14 Nov) | + whole-IMEM measurement and later features | 39,962 | 29,187 | +0.182 | M | feature growth, not an optimization step |

Budgets held throughout: subsystem **LUT ≤ 47,550** (75 % of device, a HARD STOP) and merged-chip ceiling 52,000. **LUT was the budget, FF was not**: FF sat around 28 % of the device. That one fact decided several trade-offs below.

# 2. The method we used every time

1. **Measure where the area and the timing actually are** before proposing anything (Step A, 2 Nov):
   - `report_utilization -hierarchical -hierarchical_depth 8` on the routed checkpoint, to get LUT/FF per block;
   - `report_timing -slack_lesser_than 0.5 -nworst 1 -unique_pins`, to see every near-critical endpoint, not just the worst one;
   - `report_high_fanout_nets -timing`;
   - for flat blocks, Tcl fan-in-cone attribution on `synth.dcp` (`reports/b1_trims/l2_lut_attribution.tcl`), so every LUT is owned by an RTL line.
2. **Rank candidates in one table:** expected effect (labelled E), whether it touches a signed bound or contract, how much must be re-verified, risk.
3. **The owner chooses.** Candidates that change a signed latency or arbitration bound are a hard stop (see A2 below).
4. **Write the contract before the RTL:** what changes, the invariants (usually **cycle identity**), the jobs, and their check counts frozen before the first run.
5. **Implement as generated variants** from pinned sources. Protected originals are never edited, so the baseline stays rebuildable.
6. **Re-run every affected bench with unchanged counts**, add a killed mutant for the new structure, then a registered P&R gate.
7. **Record withdrawals and failures as history**, with their numbers. Two of our best decisions (A5 under S4, the mesh split) came out of a recorded failure.

# 3. Decision notes

## 3.1 D-AREA-1: architecture first (20 Oct)
- **Chose:**
  - link-layer authentication (L2) only on tiles 3 and 4;
  - **one** L2 KMAC shared by all L2 users, with RoT priority;
  - KDF and tag time-multiplexed on one KMAC in the endpoint and the verifier ("D");
  - L2 trims T1–T4 (§3.2);
  - control-plane-only MAC (M-F1 rev 7).
- **Over:**
  - every tile wrapped (75,556 E);
  - all 6 tiles with a shared KMAC (≈ 47,952 E, ≈ 49.5–50k with a 12-requester mux);
  - a single shared Keccak for every user.
- **Because:** only the configurations with L2 on tiles 3/4 plus a shared KMAC plus at least two of {D, trims, shared Keccak} fit under 75 %, and this was the smallest one that kept the threat-model core. Estimate ≈ 44,000 E; measured 43,935 M at S1.
- **Costs:**
  - **data-plane link authentication removed** (forged-source, replayed or tampered data packets are no longer caught at L2; compensated by the ingress source check and the gates);
  - attestation latency now depends on L2 load (a shared engine needs priority and signed bounds: P ≤ 269, Q ≤ 792).
- **Revisit if:** a larger device, or the data plane must be authenticated.
- **Reusable rule:** build a **configuration × area × security-loss matrix** (`reports/b1_trims/area_matrix.py`). Write the threat-model loss in the same row as the LUT number, so nobody buys area without seeing what it costs.

## 3.2 B-1 trims inside the L2 wrapper (20 Oct): runtime indexing and redundant copies
The 4,156 non-KMAC LUTs of `noc_l2_auth` were attributed cone by cone. The big items were runtime-indexed **reads** and redundant wide copies, not logic:

| Trim | Problem (RTL) | Fix | Saving (E, per L2 tile) | Cost |
|---|---|---|---|---|
| T1 | `supplied_tag = rb[rn-4+i]`: runtime-indexed read, 4×32 bits × 26 positions (1,156 LUT cells) | capture the 4 MAC words into a 128-bit register while collecting (counter-indexed, 4 positions) | ≈ 990 LUT | +40 LUT, +128 FF |
| T2 | two 704-bit transcripts with per-bit `i<pn ? word : 0` zero-fill, duplicating masking that `kmac_encode` already does and a register the KMAC re-takes | drop the transcripts; wire `msg_in` at constant positions | ≈ 940 LUT, −1,408 FF | 0 |
| T3 | 6:1 × 256-bit key muxes per direction on a 1,536-bit port | per-tile key RAM (RAMB18) | ≈ 940 LUT | +1 RAMB18, +30 LUT |
| T4 | quarantine `rb[]` in flip-flops | LUTRAM; HEAD and freshness captured at collect; replay by pointer | ≈ 210 LUT, −≈ 700 FF | +60 LUT |

The per-trim savings were not measured separately in the reports read for this document. The package was measured as part of the S1 total.

**Reusable rules:**
- A **runtime-indexed read or write** of a wide array becomes a large mux. Capture into fixed registers while the data streams in, or use RAM.
- Look for **the same wide value stored 2–3 times** (here: transcript → KMAC input register → encoder register).
- Big key or constant tables belong in **BRAM/LUTRAM**, not in muxes on a wide port.

## 3.3 D-SYN-2: byte-serial message assembly (20 Oct)
- **Chose:** assemble the measurement message one byte per cycle (a `rtl/dual_lane` variant).
- **Over:** a parallel builder with runtime-offset part-select writes in loops (`block[(len+k)*8 +: 8]`), which synthesise to huge shifters/muxes.
- **Because:** byte-serial assembly avoids the runtime-offset write pattern, and it needed no vector or count change (7 length layouts in the frozen vectors meant the alternative would have re-frozen counts). A **preflight lint rule against runtime-offset writes in loops** was added so the pattern cannot come back. The measured area/synthesis effect is not in the reports read here (see §5).
- **Costs:** +`req_len`+1 cycles of latency.
- **Reusable rule:** trade a few cycles for a serial datapath wherever the latency is off the critical protocol path, and turn the lesson into a lint check.

## 3.4 S1-PNR-DIR: implementation directives (22–23 Oct)
- **Chose:**
  - `opt_design -directive Explore`;
  - `place_design -directive ExtraTimingOpt`;
  - `phys_opt_design -directive AggressiveExplore`;
  - `route_design -directive AggressiveExplore`;
  - a post-route `phys_opt_design -directive AggressiveExplore`;
  - plus `report_design_analysis -congestion -complexity -timing` and `report_qor_suggestions`.
- **Over:** default directives, which gave run 234618 **WNS −0.417, TNS −3.741**, route-dominated router paths.
- **Because:** the same netlist reached **WNS +0.165 M**. It is a flow change only, with no RTL or constraint change.
- **Costs:** longer runs. The +0.3 ns merge-headroom target was still not met (PASS, flagged).
- **Out-of-context (OOC) proxy:** the block is implemented alone, with `set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]` modelling the driving clock buffer. The **real-pin N-13 top** stayed the final timing gate.
- **Reusable rule:** try directives before touching RTL. If directives fail, **stop and report congestion before any retiming or pblock**.

## 3.5 S3-T1: replicate a high-fanout select (2 Nov)
- **Problem (measured):** 121 of 123 near-critical endpoints came from one RTL pattern. In each `keccak_f1600`, one one-hot `fsm_state` bit selected the next value of all 1,600 `state_reg` bits: **fanout 1,618, path 19.67 ns, 97 % routing, 1 logic level**.
- **Chose:** 25 registered copies of the 2-bit FSM state, one per 64-bit lane, marked `(* keep = "true" *)`. Each copy is updated identically, including reset and default, and each lane's `case` uses its local copy. A procedural `$error` (translate_off) checks replica == original every cycle.
- **Over:** `max_fanout` attributes or `phys_opt -force_replication_on_nets` (flow-level). The RTL replica is explicit, survives every flow and is checkable.
- **Costs:** +50 FF, ≈ 0 LUT. **Cycle-identical**, so every digest and count is unchanged.
- **Measured outcome:** the Keccak cluster left the critical list. WNS at S3 was +0.126: the limiter became the protected **router** path, which has real logic depth (21 levels).
- **Reusable rule:** when the worst paths have **1 logic level and >90 % routing**, the problem is fan-out, not logic. Replicate the driver per consumer group and mark the copies `keep`.

## 3.6 S3-A1: share hardware that is never busy at the same time (2 Nov)
- **Basis:** at tile 3 the endpoint runs KDF → measurement → tag **strictly in sequence**, but the measurement SHA3 had its own full Keccak core (3,741 LUT + 1,621 FF) that was never busy alongside the KMAC's.
- **Chose:** one `keccak_f1600` shared through a permutation port. The rules:
  - **Request:** the start signals are OR-ed, and the input state is selected by the requester.
  - **Owner:** an owner register is set at start, and only while the core is idle.
  - **Isolation:** `done` goes to the owner only, and each wrapper captures `state_out` only on its own `done`. This also isolates the key-derived state the KDF leaves in the core.
  - **Exclusivity:** two starts in one cycle, or a start into a busy core, are checked by RTL `$error` and by a new bench.
- **Costs:** a 1,600-bit input mux (≈ 800–1,600 LUT E); one more invariant to verify.
- **Rejected sibling, A2:** merging the verifier and L2 engines at tile 4 (−5 to −6k LUT E) **changes signed bounds** (engine Q ≤ 792 / P ≤ 269, REVOKE 486 of 1,500, round trip 1,204). That made it a separate bound proposal and a hard stop, and it was not built.
- **Reusable rule:** find engines whose **phases are already sequential** in the controller FSM. Sharing them costs no cycles if the request mux is combinational and the owner register only routes `done`.

## 3.7 S3-A6: specialise to the parameter range actually used (2 Nov)
- **Basis:** the maximum measurement message is 135 bytes, below the SHA3 rate of 136, and longer requests are rejected. So every measurement is exactly **one block**.
- **Chose:** the message builder writes the SHA3 padding itself (domain byte 0x06, or 0x86 when it shares the last byte); the SHA3 drops pad, absorb and its 1,600-bit state copy. Same digest and latency, checked by an **exhaustive equivalence bench**.
- **Reusable rule:** read the constants. A general multi-block engine sized for a case that the system rejects is pure area.

S3 total (measured): **43,935 → 37,398 LUT (−6.5k), 36,102 → 32,810 FF**, 18/18 jobs PASS_FRESH.

## 3.8 S3-A5 → S4-A5: the same change was bad, then good (2 Nov → 4 Nov)
- **Change:** delete the KMAC wrapper's 1,600-bit state copy; absorb from the core's held `state_out` instead. Cycle-identical.
- **Under `-flatten_hierarchy none` (S3):** **saved 1,600 FF but added ≈ 790 LUT per engine**. The zero/hold function moved from FF reset/enable pins into LUTs across a hierarchy boundary. LUT is the budget, so it was **WITHDRAWN on measured data**.
- **Under `-flatten_hierarchy rebuilt` (S4):** re-measured at **−1.65k LUT / −4.85k FF**, because the select logic merges with the absorb XOR across the old boundary. Re-approved as S4-A5.
- **Reusable rule:** an optimisation's value **depends on the synthesis flow**. FF reset/enable pins are free logic; moving that function into LUTs is not. Re-measure withdrawn ideas whenever the flow changes.

## 3.9 S4-F1/F2 and S4-SOC: tool settings and pruning observation-only outputs (4 Nov)
Scratch synthesis on the release sources (post `opt_design`), labelled S:

| Run | Flow | LUT | FF |
|---|---|---|---|
| S0 | release (`-flatten_hierarchy none`) | 38,020 | 33,038 |
| S1 | `-flatten_hierarchy rebuilt` | 35,802 | 32,951 |
| S2 | none + `-directive AreaOptimized_high` | 37,732 | 32,943 |
| S3 | rebuilt + AreaOptimized_high | 33,399 | 32,872 |
| S5 | rebuilt + AreaOptimized_high + A5 | 31,749 | 28,021 |
| S7 | + SoC top (observation-only exports unconnected) + A5 | 32,517 | 26,332 |

- **AreaOptimized_high only helps together with flattening** (S2 vs S3).
- **S4-SOC:** debug and statistics outputs were left unconnected at the SoC top, with no subsystem RTL change; benches keep every port. Synthesis then removes their counters and registers.
- **Reusable rule:** separate **observation outputs** from functional outputs at the top. Keep them in the bench top and drop them in the implementation top.

## 3.10 S4-F3: when area settings broke timing, split the flow (4–5 Nov)
- **Failure (registered):** S4 rev 0 `s4_p7_pnr` **WNS −0.018 ns**. Flattening had deepened the protected router path from **21 to 27 logic levels**.
- **Measured alternatives, all scratch:**

| Option | LUT | WNS | Verdict |
|---|---|---|---|
| H1: KEEP_HIERARCHY on the mesh and all cells under it | 35,324 | −0.365 | worse: hard KEEP also blocks constant propagation and LUTRAM merging (+1.8–3.1k mesh LUT) |
| H2: KEEP_HIERARCHY on the 6 routers | 33,796 | −0.477 (WHS −0.049) | worse |
| T4: lookahead router (route computed at FIFO write, stored with the flit), cycle-identical RTL variant | – | +0.016 ns gain only | parked |
| **M1: protected mesh synthesized alone with the release settings (flatten none), the rest with S4 settings, linked with `link_design`** | **32,457** | **+0.334** | **chosen** |

- **Chose M1 as S4-F3.** The decision rule was fixed **before** the M1 result came in. The flow fails closed:
  - exactly one mesh instance;
  - every instance built with `LINK_PIPE=1`;
  - no black box left after `link_design`;
  - mesh cell count > 0.
- **Costs:**
  - a more complex flow, with a black-box declaration (`synth/s4/noc_mesh_3x2_bb.sv`) that must never sit in the same synthesis as the real mesh;
  - the first N-13 attempt failed because the mesh checkpoint re-defined `clk` (no_clock 29,507). That was fixed with a fail-closed post-link clock check and a negative test.
- **Result (registered):** N-13 secure **32,708 LUT (−14.0 %), WNS +0.275**; OOC 32,457 / +0.334; 66/66 jobs PASS_FRESH.
- **Reusable rules:**
  - **Per-block synthesis strategies:** area settings on the crypto, release/performance settings on the timing-critical fabric.
  - Do not use hard `KEEP_HIERARCHY` to protect timing; it blocks good optimisations.
  - Margins near 0 ns move by ±0.5 ns between netlists or placements (+0.505 to −0.477 here). **A single positive run is not a margin.**

## 3.11 Probes that said "don't" (5 Nov)
- **I9-B1 CLOSED: narrower counters.** 16 counters at 32-bit wrap become 16-bit saturating: **+64 LUT**, −256 FF (S). A 32-bit incrementer is almost free on the CARRY4 chain (≈ 1 LUT per counter), and saturation needs a compare. FF was not the budget.
- **I9-A3 PARKED: specialise `kmac_encode` to fixed key and custom lengths.** −199 LUT per shared encoder, **+4** for the L2 encoder (S): about −0.4k total, against an estimate of 1.0–1.5k. Not worth a re-qualification. **Reopen trigger written down:** merged LUT > 46,000, or a `kmac_encode` path in the top 100 timing endpoints.
- **Reusable rules:**
  - Probe in scratch before registering. Estimates were 2–3× optimistic here.
  - Narrowing counters on FPGA rarely saves LUT.
  - Always write a **reopen trigger** for parked ideas.

## 3.12 Standing timing rules that came out of this
- **Timing watch (19 Oct):** any increment that adds logic to the NI or mesh runs an OOC or mesh timing check before its gate. A failing timing check blocks the gate. The basis was a mesh WNS of only +0.202 ns.
- **Margin policy:** WNS ≥ 0 is the gate; **+0.3 ns is the merge-headroom target**, and below it the gate is "PASS, flagged".
- **`LINK_PIPE=1` is frozen** in the interface (one register per router-to-router data link, +1 cycle per hop; credits are not piped).
- **`check_timing` must be clean** (I-17): the board XDC false-pathed asynchronous I/O but left `no_input_delay` / `no_output_delay` warnings. Explicit 0 ns I/O delays were added on the MMCM clock for bookkeeping, false paths kept, and gate negative tests (extra clock, tightened period, zeroed firmware) must FAIL.
- **The full real-pin top is the final timing gate.** The N-13 top uses a serial shift chain for the inputs and a 64-bit MISR on 5 pins for the outputs, so nothing is pruned and the I/O is real. OOC is only a proxy.

# 4. Reusable checklist for the next project

**Area**

1. Draw the per-block LUT table from `util_hier` at full depth before guessing.
2. Ask in order:
   - Does this block need to exist? (architecture matrix with the security or function loss in the same row)
   - Is it busy at the same time as a twin? (share it)
   - Is it sized for inputs the system rejects? (specialise)
   - Is a wide array indexed at runtime? (capture registers, RAM, serialise)
   - Is the same wide value stored more than once?
   - Is a constant table built from muxes? (RAM)
3. Remove observation-only logic at the implementation top, not in the RTL.
4. Then try the synthesis flow (`-flatten_hierarchy rebuilt` + `-directive AreaOptimized_high`) and **re-measure earlier withdrawn ideas under it**.
5. Know which resource is the budget. Do not trade LUT for FF when LUT is the limit.

**Timing**

1. List **every** endpoint under 0.5 ns, not just the worst one, and group them by cause.
2. Logic levels ≈ 1 and routing > 90 % means fan-out: replicate the driver in RTL with `keep`.
3. Many logic levels means real depth: pipeline or look ahead, with a contract, because it changes cycles.
4. Try implementation directives before RTL changes.
5. When area settings hurt a timing-critical block, synthesize that block separately with its own settings and link. Avoid hard KEEP_HIERARCHY.
6. Gate on the real-pin top with `check_timing` clean. Treat margins under about +0.3 ns as placement noise.

**Process**

- Contract before RTL.
- Cycle-identical invariants wherever possible, so all benches are re-earned with unchanged counts.
- Generated variants from pinned sources.
- Scratch probes labelled "not evidence".
- The decision rule written before the result.
- Every withdrawal kept with its numbers.

# 5. Gaps in this record

- Per-trim measured savings for L2 trims T1–T4 and for D-SYN-2 are not in the reports read for this document; only package totals are measured.
- The reasons behind `LINK_PIPE=1` are in `docs/decisions/M-F1-interface-freeze.md`; only the frozen setting is quoted here.
- No ASIC numbers appear here. The IHP SG13G2 mapping (65.42 mm², dominated by memories built from flip-flops) is a separate problem, with its own plan in `PQ_Attest_ASIC_Debug_Plan_for_Arnav_20261120.docx`.
