# RTL finalization: open decisions, questions and design options (2026-11-07)

**Purpose.** Everything Kalash needs to decide to finalize the whole RTL side of the merged PQ-Attest SoC (NoC + PQ-Attest + two RISC-V tiles) and hand it to the GDS2 phase.

**How to answer.** Fill in **Answer** under each item:
- with an option letter, "rec" (accept the recommendation), or free text;
- send the file back;
- Lane 1 then implements, re-verifies in the harness, and signs off.

**Where we are:**
- The merged design is built with timing met: 34,987 LUT, WNS +0.237 ns.
- It passes I-13 … I-17, and the board demo passed.
- One RTL item is open (D1). The rest are scope choices, polish, and the ASIC hand-over.

Legend:
- **[RTL]** changes RTL;
- **[FW]** firmware;
- **[VER]** verification;
- **[DOC]** documentation;
- **[ASIC]** affects the GDS2 phase;
- **Hard stop** = a contract, security-scope or budget decision that only Kalash can take.

---

## A. Must decide (blocks RTL sign-off)

### D1. May the CPU request attestation? (contract M-F1 rev 8 sec. 8, decision R-D5) [RTL] Hard stop

**Today:**
- Only the RoT side starts attestation: board auto-start after reset, or btn[1].
- The CPU's STATUS ATTEST_REQ bit raises `attest_req_o`, but it is **not connected** in `pq_soc_merged_core`.

| Option | Meaning | Work |
|---|---|---|
| a | **CPU may request, RoT decides**: `attest_req_o` of tile 3 is ORed into the verifier start; a request while the verifier is busy is ignored (rate limit = verifier busy). Firmware can re-attest after a revoke. | About 10 lines of RTL + 2 merged checks (request starts attestation; request while busy ignored) |
| b | **RoT only**: keep it unconnected; close sec. 8 as "the CPU cannot start attestation" (smaller attack surface; the CPU is the attested party). | Comment + contract note only |
| c | CPU may request only for itself and only after a revoke (stricter variant of a) | About 20 lines + 3 checks |

**Recommendation:** **b** for this release (the simplest trust story: the verifier, not the attested software, decides when to measure). Option a stays a documented extension.

**Answer:**

### D2. When is "SOC_INTEGRATION_COMPLETE = YES"? [DOC] Hard stop

**Proposed criteria (all must hold):**
1. D1 implemented and verified.
2. The I-18 merged checks PASS (item V1).
3. The final bitstream passes the I-17 gate.
4. Kalash's itemised board observations are recorded (item B1).
5. Tag `rtl-signoff-fpga-v1` pushed.

**Answer:** (accept / change)

### D3. Final demo firmware: v1 as is, or v2? [FW]

v1 (on the board now) prints "T3 PASS" / "T0 REFUSED" once.

v2 adds:
- a polling limit (no infinite wait);
- PASS / FAIL-first lines;
- "REFUSED OK";
- a cycle counter print;
- after a revoke, tile 3 retries and must be refused (proves revoke on the board).

The 64-byte boot stub, and therefore APPROVED_MEAS, does not change.

| Option | |
|---|---|
| a | v2 (recommended: it shows revoke enforcement on the board, which the paper needs) |
| b | keep v1 |

**Answer:**

### D4. C firmware / GCC download (decision R-D2) [FW]

The demo is assembled with our in-repo RV32I assembler, so no GCC is needed today. C firmware needs the xPack RISC-V GCC (Windows zip from GitHub, about 200 MB).

| Option | |
|---|---|
| a | approve the download now (wait for the RISC-V lane's answer Q3.1 on their exact version) |
| b | stay assembler-only for this release (recommended unless the paper needs C benchmarks) |

**Answer:**

---

## B. Verification scope before sign-off

### V1. Remaining merged-level checks from plan R4.3 (new increment I-18) [VER]

| # | Check | Needs | Include? |
|---|---|---|---|
| 1 | Error response from the memory tile reaches CPU A as poison + STATUS code 3 | bench-forced error | |
| 2 | Revoke while CPU A's request is in flight: refused or timed out, never committed | firmware v2 or bench | |
| 3 | App port busy during attestation: CPU traffic waits, nothing is lost | bench | |
| 4 | CPU A refused after revoke (poison 0xBADBE002) | firmware v2 | |
| 5 | D1 checks (if D1 = a or c) | D1 | |

**Recommendation:** all of 1–4. The plan required them, and each comes with a mutant control.

**Answer:**

### V2. Benches that stay outside the harness

These are scratch PASS only: `tb_tile_top` (covered by `tb_two_tiles`), and the legacy print-only benches (conformance 1,000; random latency 1,000 / 1,000; CPU ALU / branch / mem).

| Option | |
|---|---|
| a | accept as scratch evidence |
| b | add CHECKS / RESULT lines and register them (about 0.5 day) |

**Answer:**

### V3. Formal / extra assurance

FORMAL = NO by scope. Optional: SymbiYosys-style bounded proofs of the adapter A1 guard and the bridge authorization gate. This needs an open-source toolchain on Windows / WSL.

**Answer:** (out of scope / do it)

---

## C. Design tweaks you may want (optional)

| # | Idea | Effect | Area / risk | Recommendation | Answer |
|---|---|---|---|---|---|
| T1 | Tile 0 can be attested too (today it is never authorized by design D1, to show refusal) | Two attested CPUs; refusal shown by revoke instead | +~0 LUT RTL; provisioning + checks change | Keep as is (the refusal demo is the point) | |
| T2 | Bus-fault IRQ handler in firmware (IRQ 3 is wired, masked at reset) | Faults are reported asynchronously | Firmware only | Optional with v2 | |
| T3 | UART RX on the CPU tiles (commands from the PC) | Interactive demo | +~200 LUT | Not needed | |
| T4 | Measurement window larger than 64 bytes (full 16 KB IMEM) | Measures the whole program | New reference profile, M-F1 revision, re-qualification (decision D2 of the contract chose 64 bytes) | Not this release | |
| T5 | More timing margin (WNS +0.237 ns today) | Robustness across temperature / boards | Effort; critical path in the subsystem | Accept (timing is signed off at 20 ns) | |
| T6 | Fresh nonce per attestation (TRNG; today a fixed DEMO nonce) | Real replay protection on hardware | TRNG RTL exists but not integrated; scope decision S-4 says "replay only" | Out of scope (state in the paper) | |
| T7 | Auto-attest delay, LED map, UART text changes | Demo polish | Trivial | Tell us what you want | |
| T8 | Area budget use: 34,987 / 47,550 LUT used | Room for about 12k LUT (e.g. a third CPU tile ≈ 2.7k, or a second attested tile path) | — | Only if the paper needs it | |

---

## D. Documentation to close

| # | Item | Answer |
|---|---|---|
| C1 | Contract numbered note: sec. 7 config_data words (TILE_ID / BUILD_ID), sec. 8 final wiring (after D1), sec. 9 BRAM read latency = 1 cycle, window 16 KB. OK for Lane 1 to write it? | |
| C2 | Error-read semantics: we return poison 0xBADB_E00x on a bus error; the RISC-V lane's old contract said "read error returns 0". Confirm poison is final. Waiting on questionnaire Q1.2. | |
| C3 | Credit line for the paper: RISC-V tile base (RISC-V lane), A1 guard (RISC-V lane), fixes / bridge / reader / checker / firmware / merge (Lane 1). OK? | |

---

## E. Board record

| # | Question | Answer |
|---|---|---|
| B1 | After programming the final bitstream: led[0] (tile 3 authorized), led[2] (T3 PASS), led0_r (T0 refused), led[1] / led0_g off, led[3] blinking? | |
| B2 | UART text with sw[0] = 0 and with sw[0] = 1 (copy it) | |
| B3 | btn[2] revoke → led[0] off? btn[1] re-attest → led[0] on? | |

---

## F. ASIC hand-over (decide now, used right after RTL sign-off)

| # | Question | Options | Recommendation | Answer |
|---|---|---|---|---|
| G1 | College tools and PDK (step A0) | gpdk045 / foundry PDK; Genus + Innovus versions; server access | Ask the college this week; it blocks everything else | |
| G2 | SRAM memory compiler available? | yes → SRAM macros at full 16 KB; no → flip-flop memories, reduced to 1–4 KB each | Full size if a compiler exists | |
| G3 | Firmware in the ASIC | a) ROM (hard-wired image); b) loaded after reset over a debug port; c) keep `$readmemh` for simulation only | a) ROM for the boot stub + app (simplest, keeps the measurement fixed) | |
| G4 | Clock / reset for the ASIC top | pad clock at 50 MHz (no MMCM), synchronous reset kept | As recommended | |
| G5 | ASIC target frequency | 50 MHz (same as FPGA) or higher | 50 MHz for comparability, then report fmax | |
| G6 | Pad ring | only if the college flow requires it | Ask in A0 | |

---

## G. After your answers, Lane 1 will

1. Implement D1 / D3 / T-items as answered, in RTL variants with explicit source lists.
2. Register I-18: counts frozen before the first run, mutant controls, then run and gate.
3. Rebuild the bitstream through the I-17 gate. You run the board (E).
4. Write the contract note (C1) and the sign-off report, and tag `rtl-signoff-fpga-v1`.
5. Start A1: ASIC-ready RTL in `rtl/asic/`, per F.
