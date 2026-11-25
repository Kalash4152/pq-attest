# RISC-V lane takeover plan (for Kalash's review; nothing started)

**Date:** 2026-11-06 · **Prepared by:** Lane 1 (Claude Code) for Kalash · **Status:** DRAFT, awaiting go-ahead

**Inputs**
- Their package: `PQ_ATTEST_A1_working_copy.zip` (SHA-256 `ee36ae70...9b49`) and `PQ_ATTEST_A1_HANDOFF_KALASH.docx`.
- Our intake: reports/RISCV_A1_INTAKE_20261106.md.
- Specs: brief v2 (docs/handoff/BRIEF_RISCV_LANE_v2_20261101.md), area addendum (docs/handoff/BRIEF_RISCV_LANE_AREA_ADDENDUM_20261103.md),
  contract M-F1 rev 8, and the merge prep (reports/MERGE_PREP_20261106.md).

---

## 1. What the RISC-V lane delivered

| Area | Delivered | State |
|---|---|---|
| CPU tile RTL | `picorv32.v` (stock YosysHQ core, ISC licence, SHA-256 `0836...0622`), `picorv32_adapter.sv`, `addr_decode.sv`, `tile_top.sv`, `tile_mem_wrapper.sv`, `mem_bram.sv`, `tile_status.sv`, `uart_tx.sv`, `uart_mmio.sv`, `gpio.sv`, `reset_sync.sv`, `memory_tile.sv`, `fpga_top.sv`, `tmem_traffic_gen.sv` | complete set; compiles in XSim |
| Benches | 18 (`tb_conformance`, `tb_random_latency`, `tb_tile_top`, `tb_two_tiles`, `tb_cpu_*`, `tb_memory_*`, `tb_tile_status`, `tb_addr_decode`, `tb_uart_*`, `tb_gpio`, `tb_mutation_checks`, `tb_traffic_gen`) | present; several defects (below) |
| Firmware | `start.S`, `hello.c`, `print.c/h`, `link.ld`, `convert_hex.py`, built `hello.elf`, `hello_words.hex` (96 words) | hello program only |
| Docs | `CPU_MEMORY_CONTRACT.md` (frozen TMEM protocol), `NOC_HANDOFF.md`, `MEMORY_MAP.h`, `LANE2_HANDOFF.md` | useful; status-map and memory-size placeholders |
| Vivado | `pq_attest_lane2` (fpga_top, 6 Oct 2026: 1,988 LUT, 12 BRAM), `picorv32_synth` | old; not on the fixed RTL |
| A1 | adapter IDLE guard `capture = IDLE && mem_valid && !mem_ready_q` | **RTL fix works** (our XSim check: counts reconcile, CPU runs to its end loop). Assertion wrong, bench never finishes, tb_two_tiles not run |

**Of the 17 brief items, none is complete.** A1 is half done (RTL yes, evidence no); A6 / A8 / A9 / B4 are partial; the rest are
not started (table in sec. 3 of the intake report).

## 2. Do we have everything we need to take over? **Yes.**

| Needed | In the zip? | Note |
|---|---|---|
| Every RTL source of the tile, unmodified CPU core | yes | `picorv32.v` hash recorded; treated as read-only third-party code |
| The A1 fix | yes | verified in XSim |
| Benches to re-qualify (conformance, random latency, tile_top, two_tiles, unit benches) | yes | run in XSim under our harness |
| Firmware sources + linker script + hex converter | yes | rebuild needs a RISC-V GCC (decision R-D2) |
| TMEM protocol definition | yes | `CPU_MEMORY_CONTRACT.md` sec. 4-8 (grant any time, exactly one response per accepted request, read error returns 0) |
| UART settings for the board checklist | yes | 115,200 baud at 50 MHz (`uart_tx` defaults) |
| Bridge, cpu_tile_noc, reader, checker (B1-B5) | no, never started | we write them (nothing to request) |

**Nice to have from them (not blocking; ask in your message):**
1. their current local `picorv32_adapter.sv`, `tb_tile_top.sv`, `tb_two_tiles.sv` + `git status` / `git diff` (their handoff
   says the local copy may be newer than the zip);
2. the exact GCC name / version / flags they used (we expect `-march=rv32imc -mabi=ilp32` from `COMPRESSED_ISA=1`, `ENABLE_MUL=1`);
3. their old `tb_conformance` / `tb_random_latency` logs.

## 3. Technical findings that shape the plan

1. **A1 is correct by construction.** PicoRV32 (`picorv32.v` lines 600-608) either drops `mem_valid` on the transfer, or for a
   compressed instruction split across two words keeps it high with the next address. Blocking capture while `mem_ready_q` is
   high gives exactly one capture per transfer. The missing piece is evidence: a non-tautological assertion on observable
   state (`state_q == IDLE && mem_ready_q |=> state_q == IDLE`) plus exact transaction accounting.
2. **Their bench completion is broken.** XSim ran 718k cycles without reaching its own PASS / FAIL or its 150 us watchdog. Their
   "cycle-250 stall" was Icarus-only.
3. **Bus errors are silent (A3).** The adapter returns data 0 with a normal ready on `local_err` / `tmem_err`; `dbg_trap_o` is tied
   to 0. The brief requires the CPU to trap (contract sec. 5 maps every NoC failure to `tmem_err`).
4. **Memory sizes (A7)** are already 16 KB in the RTL (`tile_mem_wrapper` 4,096 words). Only `MEMORY_MAP.h` / `link.ld` say
   8 KB. The block is single-port, so B3's 64-byte reader needs a second read port (brief A7) or must share the bus while the
   CPU is held.
5. **STATUS map (B4) differs from the brief.**

   | Offset | Theirs | Brief B4 |
   |---|---|---|
   | +0x0 | BUILD_ID | control bits |
   | +0x4 | status | FAULT_ADDR |
   | +0x8 | ATTEST_REQ | FAULT_CODE |
   | +0xC | — | BUILD_ID |

   Changing it means firmware changes.
6. **Shape of `cpu_tile_noc` (B2):** `tile_top` already exposes the 10 TMEM signals and `attested_i` / `attest_req_o` with
   IMEM / DMEM outside, so B2 = `tile_top` + `tile_mem_wrapper` + `tmem_app_bridge` (B1) + measurement reader (B3), wired to
   the port list our merged skeleton already uses (`rtl/dual_lane/merged/cpu_tile_noc_stub.sv`).
7. **Area:** their old fpga_top used 1,988 LUT. Two tiles plus bridges is likely a few thousand LUT (estimate, to be
   measured), well inside the ~22.5k LUT left under the 52k ceiling (skeleton 29,420).

## 4. Task list (Lane 1 executes; every step registered in the harness, counts frozen before the first run)

Phases run in order; each ends with a gate report and a commit, as for I-1 to I-11.

### R-0 Import and baseline (start of the takeover)

| ID | Task | Done when |
|---|---|---|
| R0.1 | Import their tile RTL, benches, firmware sources and docs into `rtl/riscv/`, `sim_riscv/`, `sw/riscv/` with a SHA-256 manifest; `picorv32.v` read-only (third-party) | manifest committed; no Lane 1 file touched |
| R0.2 | Duplicate-module preflight vs our source lists (no clash with Lane 1 module names) | preflight PASS |
| R0.3 | Register their benches **as they are** (baseline, expected to show today's defects), run in XSim | baseline gate report: what passes / fails today |

### R-1 Fix the tile (brief A1-A7, A10)

| ID | Brief | Task | Done when |
|---|---|---|---|
| R1.1 | A1 | Real assertion on observable state + exact transaction accounting (one outstanding, pending flag); bench ends on its own (find why the watchdog did not fire) | tb_tile_top PASS, captures = transfers = responses at drain; a mutant without the guard is killed |
| R1.2 | A1 | tb_two_tiles with per-tile accounting, both CPUs past 0x12C; replace the forced TMEM poke with real CPU traffic | PASS + killed mutant |
| R1.3 | A2 | tb_conformance re-run, checks unchanged | 1,000 transactions, 0 errors |
| R1.4 | A3 | bus errors trap (`dbg_trap_o`, error to the CPU via `CATCH_MISALIGN` / `CATCH_ILLINSN`-compatible path) | remote-read and remote-write error tests trap; mutant "silent error" killed |
| R1.5 | A4 | random-latency stress with an internal timeout and `$finish` | 1,000 / 1,000 seeds, terminates |
| R1.6 | A5 | bench / assertion hygiene (tb_addr_decode elaborates, no tautologies) | all unit benches elaborate and PASS |
| R1.7 | A6 | `reset_sync` instantiated; TILE_ID / BUILD_ID per tile; synchronous status reset | tb_tile_status PASS |
| R1.8 | A7 | 16 KB in `MEMORY_MAP.h` / `link.ld`; second read port for B3; tile-2 BRAM `we[3:0]` (we already have `tile2_bram_infer`) | memtest-style bench PASS, port-B bench PASS |

### R-2 Interface package (brief B1-B5)

| ID | Brief | Task | Done when |
|---|---|---|---|
| R2.1 | B1 | `tmem_app_bridge.sv`: decode (T = 2 only, not self, < 6), refuse when not authorized (no `app_valid`), build HEAD + payload (`REMOTE_PREFIX_OUT = 4'h2`), wait on `app_rx`, err / abort -> `tmem_err`, `BRIDGE_TIMEOUT` 4,096, drop late responses, one request at a time | unit bench (brief list: write, read, refusal, decode errors, err response, timeout, late response, 1,000 random) + 4 mutants killed |
| R2.2 | B3 | measurement reader: 16 words at `MEAS_BASE` via the second port, `meas_valid`, `meas_imem_len = 64` | bench vs `vectors/d2_k3_64` row image byte for byte |
| R2.3 | B4 | STATUS block with the agreed map (decision R-D4) | tb_tile_status PASS with the new bits |
| R2.4 | B2 | `cpu_tile_noc.sv` = tile_top + memories + bridge + reader + status, port list = our skeleton's | elaborates against our packages; port table in the README |
| R2.5 | B5 | bind-able app-port protocol checker (optional, decision R-D6) | binds in the merged bench, catches an injected violation |

### R-3 Firmware (brief A8)

| ID | Task | Done when |
|---|---|---|
| R3.1 | Toolchain (decision R-D2) | `riscv-none-elf-gcc --version` recorded with its hash |
| R3.2 | Demo program. CPU A: wait for GRANT (STATUS), write / read the tile-2 memory through the NoC, print PASS / FAIL on UART, LEDs. CPU B: try the same, expect the error trap, print "REFUSED". The first 64 IMEM bytes are a fixed boot stub (so the measured window does not change with the app) | hex built reproducibly; `merged_provision.py` gives `APPROVED_MEAS` |

### R-4 Merge into our Vivado project (brief B6, B7, A9)

| ID | Task | Done when |
|---|---|---|
| R4.1 | Replace the stub: fill `scripts/make_merged_sources.py` (RISC-V files, `CPU_TILE_MODULE = cpu_tile_noc`), re-map the two instances in `pq_soc_merged_core.sv` | preflight PASS (no variant + original, no duplicate modules) |
| R4.2 | Contract sec. 8 wiring (attest request policy, decision R-D5) | M-F1 rev 8 sec. 8 closed in the contract before the RTL |
| R4.3 | Register the merged jobs (contract sec. 11): `bridge_cosim` (write, read, refusal at tile 0, err response, revoke in flight, port busy during attestation) and `demo` (boot, attest, CPU A R/W, CPU B refused, REVOKE, CPU A refused after) | gate PASS, controls killed |
| R4.4 | OOC area / timing of `cpu_tile_noc`; merged bitstream with the S4 flow | timing met, LUT <= 52,000 (hard stops as always) |
| R4.5 | Project update Tcl (already written; re-run after R4.1) + board checklist filled with the real LED / UART meaning | Kalash runs `merged_build`, then the board run |

### Estimate (rough, for planning only)

| Phase | Effort |
|---|---|
| R-0 | 0.5 day |
| R-1 | 1.5-2 days |
| R-2 | 2-3 days |
| R-3 | 0.5-1 day (after the toolchain) |
| R-4 | 1-2 days |
| **Total** | **about 6-9 working days**, longer if a hard stop or a design question comes up |

## 5. Decisions needed from Kalash before R-0

| ID | Decision | Recommendation |
|---|---|---|
| R-D1 | Import location and status of their code | `rtl/riscv/` etc. inside this repository; `picorv32.v` read-only; their Vivado projects not imported (we use ours) |
| R-D2 | RISC-V toolchain | install the xPack GNU RISC-V Embedded GCC (Windows x64 zip from GitHub Releases, e.g. v14.2.0-1; needs your permission to download), record its version and hash. Alternative: ask the RISC-V lane to build the hex from our source (slower loop) |
| R-D3 | Memory sizes | 16 KB IMEM + 16 KB DMEM per CPU, 16 KB tile-2: about 20 BRAM36 of 135 (fine) |
| R-D4 | STATUS map | adopt brief B4's map (the contract said Lane 1 approves it); firmware follows |
| R-D5 | Attestation request policy (contract sec. 8) | the CPU may request, the RoT decides, repeated requests limited by "verifier busy" (as proposed in rev 8) |
| R-D6 | B5 protocol checker | include a light version (it is cheap and strengthens the co-sim) |
| R-D7 | Credit / authorship | the record states which parts are theirs (tile RTL, A1 guard) and which are Lane 1's (fixes, B1-B5, firmware demo, merge) |

## 6. Risks

- **Hidden CPU-side defects** beyond A1/A3 (their unit benches have not run in a while). Mitigation: R0.3 baseline first.
- **Bridge corner cases** (port held during attestation, revoke in flight, late responses). Mitigation: contract sec. 3-6 rules
  become bench checks and mutants.
- **Toolchain download** blocked or slow. Mitigation: R-D2 alternative.
- **Timing:** two CPUs plus bridges may move the critical path. A timing FAIL is a hard stop, as always.
- **XSim start stalls:** the harness already retries once; scratch runs use the per-snapshot watchdog.

Sources for the toolchain and PicoRV32 interface facts:
- [xPack GNU RISC-V Embedded GCC v14.2.0-1 release](https://xpack-dev-tools.github.io/riscv-none-elf-gcc-xpack/blog/2024/08/07/riscv-none-elf-gcc-v14-2-0-1-released)
- [PicoRV32 memory interface (KU Leuven course notes)](https://kuleuven-diepenbeek.github.io/course_hwswcodesign/100_processor/103_picorv)
- [YosysHQ picorv32.v](https://github.com/YosysHQ/picorv32/blob/main/picorv32.v)
- The local `rtl/picorv32.v`, lines 361-381 and 575-640

---

## 7. Pre-import RTL review (VLSI review rules; Kalash 2026-11-06: "test what they have done, do not believe 100%")

| ID | File | Finding | Severity | Tested | Plan item |
|---|---|---|---|---|---|
| A1 | picorv32_adapter.sv | IDLE guard `!mem_ready_q` is correct by construction (picorv32.v 600-608: on transfer the core drops `mem_valid` or, for a compressed split fetch, keeps it high with the next address) | fix OK | XSim: captures = transfers = responses at drain (119,234 each) | R1.1 adds the evidence |
| A1-b | picorv32_adapter.sv | assertion fires on the suppressed *attempt* (zip) or is tautological (their local edit) | bench defect | XSim: 317,112 false messages | R1.1 |
| AD-1 | addr_decode.sv | IMEM / DMEM `valid` held in IDLE **and** the WAIT cycle; `mem_bram` answers each, so **every access is performed twice** (writes repeated) and a stale ready reaches the idle decoder | **real defect** (latent hazard: safe only because the adapter cannot re-request within 2 cycles) | XSim probe, 3,000 cycles: IMEM 760 valid cycles / 380 transactions; DMEM 68 / 34; writes 42 / 21; 414 stale readies | R1.6 (new): assert `valid` only in the accept cycle; probe becomes a check + mutant |
| AD-2 | addr_decode, tile_status, uart_mmio, ... | asynchronous resets (brief: synchronous) | medium | source | R1.7 |
| AD-3 | addr_decode.sv | CPU can **write its own IMEM**, including the measured 64-byte window: after a GRANT, code can change what was attested (TOCTOU) | **security** | source | **R-D8 (Kalash)** |
| TT-1 | tile_top.sv | `trap` unconnected, `dbg_trap_o = 0`, `irq = 0`: no bus-error path (A3 needs `ENABLE_IRQ = 1` + IRQ line + poison 0xBADB_E000) | high | source | R1.4 |
| TT-2 | tile_top.sv | `reset_sync` exists but is not instantiated | medium | source | R1.7 |
| TT-3 | tile_top.sv | `dbg_pc_o = mem_addr` (bus address, not PC) | low | source | R1.4 (brief A3 debug taps) |
| TS-1 | tile_status.sv | map differs from brief B4; no FAULT_ADDR / FAULT_CODE | medium | source | R2.3 |
| UM-1 | uart_mmio.sv, gpio.sv | handshake clean (`always_comb` defaults, no latches; read-only writes -> err) | OK | source | — |
| RS-1 | reset_sync.sv | correct async-assert / sync-release, 2 flops | OK | source | R1.7 instantiates it |

## 8. Decisions (VLSI review recommendation; Kalash to confirm in review)

- **R-D1:** `rtl/riscv/`, `sim_riscv/`, `sw/riscv/`, `docs/riscv_lane/`; `picorv32.v` read-only, pinned by hash; their Vivado projects not imported.
- **R-D2:** xPack riscv-none-elf-gcc 14.2.0-1, `-march=rv32imc -mabi=ilp32`; download at R-3 with Kalash's permission.
- **R-D3:** 16 KB IMEM + 16 KB DMEM per CPU, 16 KB tile 2 (about 20 BRAM36 of 135); IMEM gets a second read port for B3.
- **R-D4:** brief B4 map (fault address and code are needed by A3).
- **R-D5:** CPU may request attestation, RoT decides, ignored while the verifier is busy; written into contract sec. 8 before RTL.
- **R-D6:** light B5 checker (valid / ready stability, no `app_valid` while unauthorized, one outstanding).
- **R-D7:** their headers kept; every Lane 1 change logged in the import manifest and design log.
- **R-D8 (NEW, security, Kalash decides):** make IMEM read-only from the CPU data bus (loaded only at reset / in the bitstream).
  Recommended: the demo needs no self-modifying code, and this closes the measured-window TOCTOU.
- **R0.3 changed:** their benches are baselined in **scratch** (they do not print our CHECKS / RESULT format and several are
  known defective); they are registered only after R-1 fixes them, with counts frozen before their first registered run.
