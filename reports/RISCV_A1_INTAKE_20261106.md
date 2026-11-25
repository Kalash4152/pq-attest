# RISC-V lane package intake, 2026-11-06: only A1 attempted, not complete; Lane 1 takes over the remaining work

- **Received:** `PQ_ATTEST_A1_working_copy.zip` (17,488,885 bytes, SHA-256
  `ee36ae70aece4af77138426eb5a6c3ecb7b36c48c7f1935622b6e779c7cc9b49`, 553 entries) and `PQ_ATTEST_A1_HANDOFF_KALASH.docx`
  (44,533 bytes, SHA-256 `25bc644b7c749070be809c052538128e8665e9d4a01647d30558a5e4585132e1`).
- **Their git:** still the single commit `0acc9e1` "Set up project structure"; all work is uncommitted. Their handoff says the
  local folder may be newer than the zip.
- **Handling:** extracted read-only into the session scratch; HDL simulation only (XSim), nothing executed from the package
  otherwise; nothing copied into this repository.
- **Checked against:** docs/handoff/BRIEF_RISCV_LANE_v2_20261101.md (A1-A10, B1-B7) and M-F1 rev 8 sec. 12.
- **Status:** HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO. Evidence below is scratch XSim (not registered).

## 1. What they say (their handoff, honestly written)

A1 is NOT complete: an IDLE capture guard (`capture = (state_q == IDLE) && mem_valid_i && !mem_ready_q`) was added; their
assertion first flagged suppressed attempts, then was edited into a tautology; `tb_tile_top` in Icarus stopped printing after
cycle 250; `tb_two_tiles`, conformance and random-latency were not re-run. They also report the area addendum as missing (we
have it: docs/handoff/BRIEF_RISCV_LANE_AREA_ADDENDUM_20261103.md).

## 2. What we re-checked (XSim 2024.1, scratch)

| Check | Result |
|---|---|
| `tb_tile_top` (zip version) compiles / elaborates in XSim | clean |
| Does the A1 guard remove the duplicate transactions? | **Yes.** At quiescent points captures = core transfers = responses exactly (e.g. 119,234 / 119,234 / 119,234 at cycle 718,500); on 29 Oct the same probe showed 31 captures vs 24 transfers |
| Does the CPU progress beyond 0x12C? | **Yes.** It runs the whole program and parks at 0x148 = `0xA001` (`c.j .`, the end-of-program spin loop) |
| Their "stall at cycle 250" | **Icarus-specific.** XSim ran past 718,000 cycles |
| Their assertion (zip version) | **Wrong (bench defect):** fires on every suppressed capture *attempt* (317,112 messages); the edited local version is tautological |
| Does their bench finish? | **No.** It never reached its own PASS / FAIL or its 150 us watchdog in 900 s wall time (sim at 14.4 ms); root cause not yet diagnosed (bench completion / watchdog), first item when we take over |

## 3. Brief v2 status, item by item

| Item | Brief requirement | Status in their package |
|---|---|---|
| A1 | adapter double capture fixed, accounting, assertion, PC > 0x12C in tb_tile_top and tb_two_tiles | 🟡 **RTL fix works** (our XSim check); assertion wrong; bench does not finish; tb_two_tiles not run |
| A2 | re-run tb_conformance (1,000 transactions, 0 errors) | ⬜ not re-run |
| A3 | real bus errors (tmem_err -> trap, dbg_trap_o) | ⬜ not done (`dbg_trap_o` tied 0; errors still complete silently) |
| A4 | random-latency stress that terminates | ⬜ not done (no internal timeout / `$finish`) |
| A5 | bench and assertion hygiene (tb_addr_decode `local_req_i`, ...) | ⬜ not done |
| A6 | reset_sync instantiated, TILE_ID / BUILD_ID, synchronous status reset | 🟡 TILE_ID / BUILD_ID parameters exist; reset_sync not instantiated |
| A7 | 16 KB IMEM / DMEM, second read port (for B3), tile-2 `mem_bram` with `we[3:0]` | ⬜ still 8 KB, no second port |
| A8 | demo software (write / read the memory tile, UART PASS / FAIL lines) | 🟡 hello program only; no demo flow |
| A9 | tile_top synthesis + implementation at 20 ns | 🟡 an old fpga_top implementation (6 Oct, 1,988 LUT, 12 BRAM); not re-run on the fixed RTL |
| A10 | re-submission package | ⬜ |
| B1 | `tmem_app_bridge.sv` (TMEM -> app port, app_rx, BRIDGE_TIMEOUT, refusal rules) | ⬜ not started |
| B2 | `cpu_tile_noc.sv` (the module Lane 1 instantiates) | ⬜ not started |
| B3 | measurement window reader (64 bytes at MEAS_BASE) | ⬜ not started |
| B4 | STATUS block bit map (0x1000_2000) | 🟡 `tile_status.sv` exists; the B4 bit map is not confirmed |
| B5 | bind-able app-port protocol checker | ⬜ not started |
| B6 | co-simulation against the real Lane 1 RTL | ⬜ not started (Lane 1 has the merged skeleton ready) |
| B7 | area / timing of the CPU tile package | ⬜ not started |

**Summary:** of 17 items, 0 are complete; A1's RTL fix is effective; everything Lane 1 needs for the merge (B1-B4, B6, A3,
A7, A8) is still to do.

## 4. Files to request from the RISC-V lane (send them this list)

1. **Their current local working tree** (the handoff says it may be newer than the zip): at least `rtl/picorv32_adapter.sv`,
   `rtl/tb_tile_top.sv`, `rtl/tb_two_tiles.sv`, plus the output of `git status --short` and `git diff`.
2. **Firmware build:** the exact compiler they used (name, version, `-march` / `-mabi`), the build command for
   `sw/hello.elf` -> `hello_words.hex`, and which hex is current (`rtl/program.hex`, `sw/hello_words.hex`, `sw/tile1_words.hex`).
   We have no RISC-V GCC on this machine.
3. **Their historical logs** for `tb_conformance` (1,000 / 0 errors) and `tb_random_latency` (1,000 seeds), if kept.
4. Anything they started for B1-B7 that is not in the zip.

## 5. Proposed plan (Lane 1 takes over; needs Kalash's go)

Order chosen so the merge is unblocked first; every step registered in the harness with counts frozen first.

1. **R-1 tile fix-up (A1 close, A3, A6, A7):** correct assertion (on the registered capture event), bench completion that ends
   on its own, tb_two_tiles accounting; real bus errors; reset_sync; 16 KB memories + second read port. Re-run A2 / A4 unchanged.
2. **R-2 interface package (B1-B4):** `tmem_app_bridge` (contract sec. 3-5, D7 4,096), `cpu_tile_noc` matching the port list
   our skeleton already uses, measurement reader (64 bytes, D2), STATUS map. Unit benches + mutants (brief B1 list).
3. **R-3 firmware (A8):** demo program (CPU A: write / read memory tile after GRANT, print PASS / FAIL; CPU B: refused). Needs
   a RISC-V toolchain (file request 2, or install one with Kalash's permission).
4. **R-4 merge (B6, B7, A9):** replace the stub in the merged skeleton, register the bridge co-sim and demo jobs (contract sec. 11),
   merged bitstream, timing / area gates, then the board run.
