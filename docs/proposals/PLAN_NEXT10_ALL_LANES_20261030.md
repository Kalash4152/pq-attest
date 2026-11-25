# Next 10 steps per lane: Lane 1 (NoC + PQ), RISC-V lane, Engineer 4 (verification), 2026-10-30

**Status: PROPOSAL, not started.** Lane 1 is STOPPED after I-5 PASS (`reports/NEXT_STEP.md`). Nothing below starts without
Kalash's go. Every LUT figure marked ESTIMATE is a calculation, not a measured result.

Scope of the evidence:
- **Read live:** HEAD b73ff3b; `reports/I5_GATE_20261029.md`; R4 plan sec. 3-5 (NOC-4/5, PQ-4/5, increments);
  `docs/DECISION_REGISTER.md`; `rtl/dual_lane/pq_noc_subsystem_p7.sv`; `noc_attest_gate.sv`; the P7 OOC `util_hier.rpt`
  (run 20261023_115722_49c54548); both handoff reports; `docs/reviews/Lane1_NoC_PQ_Spec_and_Progress_20261030.docx`
  sec. 6; `docs/reviews/P4_OPTIMIZATION_STUDY_20261023.md`.
- **Validation status:** HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

## 0. Decisions only Kalash can make

I-6 needs none of D1 to D5, so Lane 1 steps 1-3 can start on "I-6 go" alone.

| # | Decision | Needed before | Recommendation (proposal) |
|---|---|---|---|
| D0 | Restart: "I-6 go" | L1 step 1 | - |
| D1 | Demo topology: which tiles hold CPUs | L1 step 4; RV steps 7-8 | **CPUs at tile 3 (attested) and tile 0 (refused); tile 1 stays plain.** Both demo behaviours (admission, isolation) and the brief's "two instances" are kept. CPUs at 0, 1 and 3 add 1,674 LUT plus one bridge (ESTIMATE). |
| D2 | What tile 3's measurement covers (new security-scope question, a HARD STOP item) | L1 step 4 | See below. |
| D3 | Ownership: bridge and memory front end | L1 step 4; RV step 7 | See below. |
| D4 | Merged-chip LUT ceiling (47,550 governs the subsystem only) | L1 step 10 | About 52,000 LUT (82 %), with routed timing at 20 ns as the real gate. See below. |
| D5 | Board clock and top-level I/O (a clock / pin change) | L1 steps 9-10 | See below. |

**D2: what tile 3's measurement covers.**
- Today `config_data` and `imem` are 512-bit trusted inputs (at most 64 bytes each, V7 profile). A CPU's 16 KB IMEM cannot
  be measured under this profile.
- Recommendation for this release: measure a fixed 64-byte IMEM window, read from the real IMEM through the second read
  port, and state the claim exactly. A fetch window that lets the tile-3 CPU execute only measured code is optional.
- Full-IMEM measurement needs:
  - an M-F1 revision;
  - a new reference profile (L-4: the 135-byte cap);
  - new vectors;
  - re-qualification of the endpoint and measurement jobs.

**D3: ownership of the bridge and the memory front end.**
- Lane 1 builds the TMEM <-> NI bridge and keeps the tile-2 memory front end, which holds the F4 / Q2 checks. The RISC-V
  team supplies a plain BRAM memory macro.
- R4 sec. 3 places N-14 SoC integration outside Lane 1, so this decision moves it in.

**D4: merged-chip LUT ceiling.**
- Two CPUs: 44,412 + 2 x 1,674 = 47,760 before the bridges and the memory front end; about 49-51k with them (ESTIMATE).
- Three CPUs: about 51-53k (ESTIMATE), which can exceed 52k.

**D5: board clock and top-level I/O.**
- The board oscillator is 100 MHz, so 50 MHz needs an MMCM or a divider.
- The subsystem has far more ports than the package's 210 user I/O. N-13 and the merged top need a wrapper: provisioning
  from a ROM or registers so no logic constant-folds, plus status pins.

## 1. Lane 1: NoC + PQ attestation (Kalash; RTL and runs by Claude Code through the registered harness)

Rules: CLAUDE.md, the P7 contract, counts frozen before runs, one Vivado/XSim at a time, no protected-file edits. A gate
report is written and committed at every increment boundary.

| # | Step | Content | Done when | Depends on |
|---|---|---|---|---|
| 1 | I-6 spec and registration | See (a) below | Counts frozen in `dual_lane_jobs.json`; one regeneration; `test_dual_lane.py` passes first | D0 |
| 2 | I-6 RTL | See (b) below | Scratch compile and elaboration are clean; the policy model tests pass | 1 |
| 3 | I-6 run and gate | See (c) below | Every I-6 job PASS (fresh or identity-matched); LUT <= 47,550; WNS >= 0; gate report written -> **NOC 4/5** | 2 |
| 4 | Integration contract (an M-F1 revision, written before any bridge RTL) | See (d) below | Signed by Kalash and sent to both teams | D1-D3 |
| 5 | TMEM <-> NI bridge (`rtl/dual_lane/`) | See (e) below | Registered PASS; mutants killed; the bridge's OOC timing is clean | 4 |
| 6 | I-7, PQ-4 | See (f) below | Every attack rejected for its stated reason; 0 unauthorized commits; every control effective -> **PQ 4/5** | 3; E4 step 7 helps |
| 7 | I-7, PQ-5 | See (g) below | Fresh PASS against independent expected values -> **PQ 5/5** | 6 |
| 8 | I-8, N-11 / N-12 | Consume the PQ-4 evidence on the matching identity; a clean regression of every gate on one release identity; release manifest `releases/DUAL_LANE_10_<id>/` | All PASS on one identity | 7 |
| 9 | I-8, N-13 | See (h) below | WNS / WHS / WPWS >= 0, TNS / THS = 0, 0 route / DRC errors -> **NOC 5/5**. A FAIL is a HARD STOP. | 8, D5 |
| 10 | Integration and merge | See (i) below | The demo scenario passes in XSim; merged LUT <= the D4 ceiling; merged timing met | 5, 9, RV 10, E4 9, D4 |

**(a) I-6 spec and registration.** One adaptation doc maps the NOC-4 items onto P7:
- C-1 / C-2: BUSY is retried at most 3 times, then the verifier fails closed;
- `noc_fault_status` connected; it is not instantiated anywhere today;
- trusted fail / timeout / clear (tied to 0 at `pq_noc_subsystem_p7.sv:121` today);
- C-5: the 0x2 window;
- K-3 length binding.

**(b) I-6 RTL.**
- Verifier retry FSM.
- `noc_fault_status`: source, operation, reason and epoch observable.
- Trusted fail / timeout / clear wired into the gates.
- The stand-in accepts `A[31:28] == 4'h2`; `pq_noc_subsystem_p7.sv:248` still checks `4'h8`. The benches that drive
  `0x8200_0100` get new versions; reference vectors are never edited.
- K-3 lengths fixed per tile, beside the whitelist.
- The retry rule added to `scripts/policy_layer.py`.
- An M-F1 note first if any port changes.

**(c) I-6 run and gate.**
- Run `python scripts/dual_lane.py run --select i6`.
- Integrated gate cases:
  - blocked after reset;
  - grant only from the RoT, with status 1 and a whitelist match;
  - revoke, failure, timeout and reset-during-challenge all block;
  - trusted clear and retry work;
  - memory responses are gated;
  - 4 BUSY -> exactly 3 retries, then fail.
- Mutants: gate bypass, issuer check removed, revocation ignored, retry unbounded.
- Re-measure the P7 OOC area and timing.

**(d) Integration contract.**
- Signal mapping: the ten TMEM signals to `app_*`.
- Packets are atomic, with one outstanding request per CPU.
- Address and data: `0x2T00_0000` -> destination tile T; byte enables -> `control[10:7]`.
- Error mapping:
  - an illegal address (control 0x400) -> `tmem_err`;
  - refused before send (`authorized[g] == 0`) -> an immediate bus error. Today the gate holds `app_ready` low forever,
    so a CPU would hang;
  - revoked in flight -> the response is suppressed (F4 / Q2), the NI request times out, and the bridge returns a bus error.
- Tile 3 shares its TX port with the endpoint, so a CPU request waits up to one attestation (about 1.2k cycles).
- Tile 2's front end keeps F4 / Q2, with the BRAM macro behind it. A memory tile plugged into tile 2's application port
  would be refused by the ATTESTABLE = 0 gate and would skip F4 / Q2.
- The measurement read path follows D2.
- TMEM has no response backpressure, so S_tile = 0 for OPEN-T1.

**(e) TMEM <-> NI bridge.**
- Bench with a TMEM model that uses PicoRV32 timing.
- Checks:
  - exactly one NoC request per TMEM request;
  - read and write data;
  - byte enables;
  - illegal address, refusal and timeout each -> `tmem_err`.
- Mutants: double capture restored, byte-lane swap, error dropped.

**(f) I-7, PQ-4.** The SEC-1..4 matrix on the real NOC-3 / NOC-4 modules.
- It includes the 6 OPEN rows:
  - wrong tag at the verifier;
  - wrong measurement;
  - attestation replay;
  - nonce substitution;
  - config / imem substitution at re-attestation;
  - error response.
- It also covers wrong issuer, timeout, status-clear misuse, truncated challenge and concurrent SPOOF traffic.
- Each row has its targeted control.

**(g) I-7, PQ-5.** `tb_pq_full_chain` in non-demo mode on P7.
- Chain: challenge -> L2 -> endpoint -> response -> verifier and policy layer -> GRANT -> authorized write ->
  revoke / substitution -> blocked.
- Also: repeats, backpressure, reset at each boundary, SPOOF traffic, retry and timeout.
- The nonce source is reported as a "deterministic demo issuer".

**(h) I-8, N-13.**
- Isolated batch synthesis and implementation of the full top at 20 ns with the S1-PNR-DIR flow, using the D5 wrapper
  (reused later for the merged top).
- Both profiles, secure and insecure.
- If timing fails, the first candidate is fanout / reset replication (`docs/reviews/P4_OPTIMIZATION_STUDY_20261023.md`;
  the reset net has 7,988 sinks). It is a study item and is not built.

**(i) Integration and merge.**
- XSim of the integrated system: tile-3 CPU attests -> GRANT -> reads and writes tile-2 memory; tile-0 CPU gets bus
  errors; REVOKE blocks tile 3 within 1,500 cycles (486 measured today).
- Merged synthesis and P&R at 20 ns, with LUT measured against D4.
- Then the merge PR for noc/credit-integration.

## 2. RISC-V lane (team's work; the handoff re-check is done here)

Basis: `reports/RISCV_HANDOFF_CHECK_20261029.md` and brief criteria 1-28.

| # | Step | Done when |
|---|---|---|
| 1 | See (a) below | The probe on `tb_tile_top` shows core transfers = adapter requests (24 = 24; writes 3 = 3); the CPU runs past PC 0x12C in `tb_tile_top` and `tb_two_tiles` |
| 2 | Re-run `tb_conformance` | 1,000 transactions, 0 stability / fetch / protocol / response errors |
| 3 | Real bus errors and debug taps | See (b) below |
| 4 | `tb_random_latency`: add an internal timeout and `$finish`, then run 1,000 seeds over the full memory test | 1,000 / 1,000 PASS, no hang |
| 5 | Bench hygiene | See (c) below |
| 6 | Reset and IDs | See (d) below |
| 7 | Memory, per D3 | See (e) below |
| 8 | Software | See (f) below |
| 9 | `tile_top` synthesis and implementation at 20 ns | See (g) below |
| 10 | Re-submission | See (h) below |

**(a) Adapter double capture.** Fix it: never accept a request in the cycle `mem_ready` is high. A `pending` flag that clears
on the edge where `mem_ready` is seen also works. Add an assertion of one accept per `mem_ready`.
- The mechanism is already proven by source and probe: in RESPONSE the adapter sets `mem_ready_q` and returns to IDLE on the
  same edge, and IDLE re-captures the still-high `mem_valid`.

**(b) Bus errors and debug taps.**
- Done when:
  - `tmem_err` or an unmapped access traps the core, never returning a silent zero;
  - `dbg_trap_o` is driven;
  - `dbg_pc_o` is the retiring PC;
  - each of these has a test.
- Refusal behaviour follows the Lane 1 contract (step 4).

**(c) Bench hygiene.**
- Add the 7.3 assertions: address stable while pending, and one response per request.
- Fix `tb_addr_decode`.
- `tb_two_tiles` gets two different programs and a real pass rule.
- `tb_tile_status` and `tb_gpio` get checks and `$finish`, including the one-cycle attest-request pulse.
- Done when: every bench self-checks and terminates.

**(d) Reset and IDs.**
- `reset_sync` instantiated in `tile_top`, with one reset style throughout.
- TILE_ID / BUILD_ID agreed in writing.
- The decoder matches noc_pkg (remote `0x2T00_0000`, the NI window `0x1000_3000`).
- Done when: reviewed, and `tb_addr_decode` passes.

**(e) Memory, per D3.**
- A plain BRAM macro for tile 2, which sits behind the Lane 1 front end.
- The `mem_bram` second read port, which serves the D2 measurement read path.
- 16 KB in `MEMORY_MAP.h` and `link.ld`.
- `memtest.c`.
- Done when: memtest passes for every size and alignment.

**(f) Software.**
- A one-command hex build.
- A tile-3 program for attested access and a tile-0 program that expects bus errors.
- A cycle counter, a traffic generator at `0x2T00_0000`, and UART result lines.
- Done when: both programs pass in `tb_two_tiles`.

**(g) `tile_top` synthesis and implementation at 20 ns.** Done when:
- WNS >= 0;
- 0 latches, loops or multi-driven nets (criteria 16-18);
- BRAM / DSP as agreed;
- RESOURCES.md updated.

**(h) Re-submission.**
- Sources committed (not untracked), with build products removed.
- README and DESIGN_LOG filled in.
- The PicoRV32 upstream tag and hash recorded.
- A zip with its SHA-256 and commit ID.
- Done when: the re-check here answers all 28 criteria.

## 3. Engineer 4 lane: verification (team's work; re-baseline to P7)

Basis: `reports/E4_HANDOFF_CHECK_20261029.md` (pqattest1.zip, commit b62b78d).

| # | Step | Done when |
|---|---|---|
| 1 | Read message types and lengths from the P7 packages (`rtl/dual_lane/NOC_PKG.sv`, `noc_p7_pkg.sv`) instead of hard-coding them (`sv_vector_bridge.py` has CHALLENGE = 5) | A negative test: a package with CHALLENGE 5 makes the cross-module check FAIL. Today it passes against both. |
| 2 | Per-type framing: data types 0-3 plain; control types 4-7 carry 4 MAC words | CHALLENGE 12, RESPONSE 21, GRANT / REVOKE 5 flits; V1 / V2 regenerated as new files |
| 3 | Pair matrix | 30 legal ordered pairs; LOCAL -> LOCAL rejected by a negative test |
| 4 | P7 authorization model | See (a) below |
| 5 | Regenerate the JSON / SV artifacts for P7 | New files with a SHA-256 manifest; the rev-5 set kept as history, not edited |
| 6 | Independent reader for our evidence | See (b) below |
| 7 | I-7 oracles | See (c) below |
| 8 | Bridge oracle (TMEM <-> NoC), from the Lane 1 contract | See (d) below |
| 9 | Integration-demo oracle | See (e) below |
| 10 | Packaging | See (f) below |

**(a) P7 authorization model.** It covers R7.4, F4 commit-time authorization and Q2 read disclosure. Done when:
- control flows only 4 -> 3 (CHALLENGE, GRANT, REVOKE) and 3 -> 4 (RESPONSE);
- tiles 0 / 1 / 2 / 5 refuse control (reason 8);
- data commits only from an authorized source;
- each illegal scenario carries its expected reason.

**(b) Independent evidence reader.** The parser reads CHECKS / RESULT and `status.json`.
- Done when: it re-adjudicates I-5 into a new record and gets 30 / 30.
- Negative tests: an `Error:` line, a timeout, a missing RESULT and a count mismatch must never PASS.

**(c) I-7 oracles.** Expected outcomes for SEC-1..4, including the 6 OPEN rows, from the frozen teammate reference plus the
policy layer. Done when: they are delivered as new vector files, with the reference untouched.

**(d) Bridge oracle.** Done when it checks:
- one NoC request per TMEM request;
- address -> tile;
- byte enables;
- illegal address, refusal and timeout -> `tmem_err`.

**(e) Integration-demo oracle.** Done when: the expected trace (tile-3 GRANT -> reads and writes; tile 0 refused; REVOKE
blocks within 1,500 cycles) and the commit / fault accounting are written down.

**(f) Packaging.** One-command `p7_regression`, pytest pinned, and the two 0-byte SHA3 RTL files filled or deleted. Then a
zip with its SHA-256 and commit ID. Done when: a re-run here reproduces the counts.

## 4. Sync points and proposed calendar (ESTIMATE; Lane 1 weeks follow the Lane 1 document's sec. 6.2)

| Week | Lane 1 | RISC-V | Engineer 4 | Sync point |
|---|---|---|---|---|
| 2-8 Nov | D0-D5 answered; steps 1-4 (I-6 -> NOC 4/5; contract signed) | 1-3 | 1-3 | Contract signed -> both teams build against it |
| 9-15 Nov | 5-7 (bridge; I-7 -> PQ 5/5) | 4-7 | 4-7 | E4 step 7 vectors feed L1 step 6 |
| 16-22 Nov | 8-9 (I-8 -> NOC 5/5) | 8-9 | 8-9 | RV step 9 numbers feed the D4 area check |
| 23-30 Nov | 10 (integration, merged P&R, merge) | 10 | 10 | RV re-acceptance + E4 step 9 -> integrated sim |

Critical path:
1. RISC-V steps 1-2 (no co-simulation is meaningful before them).
2. D2: full-IMEM measurement would add a contract revision and re-qualification.
3. N-13 timing: the routed WNS today is only an OOC proxy at +0.165 ns.
4. The one-Vivado/XSim rule serializes every Lane 1 run.

## 5. Corrections to the recommendations received on 2026-10-30

1. **0x2 window.** It was decided (C-5, 7d90d70) but not implemented. Both stand-ins still check `4'h8`
   (`pq_noc_subsystem.sv:173`, `pq_noc_subsystem_p7.sv:248`), and 6 benches drive `0x8200_0100`. It is an I-6 item.
2. **Three CPUs (0, 1, 3) and a 52k ceiling conflict:** about 51-53k (ESTIMATE). Two CPUs (3 and 0) keep both demo
   behaviours.
3. **The measurement covers at most 64 bytes of IMEM** (D2). This was not covered in the recommendations.
4. **The memory tile cannot sit on tile 2's application port** (refused by the gate, and F4 / Q2 would be bypassed). D3
   keeps the front end in Lane 1.
5. **A refused CPU hangs today** (`app_ready` held low) instead of getting a bus error. The bridge contract fixes this.
6. **The "prepared" fixes are not built.**
   - Endpoint Keccak sharing: 3,741 LUT is the gross upper bound, the net saving is unknown, and the P4 study rates it high
     risk and defers it.
   - Fanout / reset replication: a study recommendation. Phase B, which held it, was cancelled.
7. **Confirmed:**
   - An extra attestable tile costs the endpoint (16,568 LUT measured) plus an L2 wrapper (about 1.1k).
   - The double-capture mechanism was already proven in our handoff check.
