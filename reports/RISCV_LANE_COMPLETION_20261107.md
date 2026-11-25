# RISC-V lane completion checklist (brief v2), 2026-11-07

Lane 1 took over the RISC-V lane on 2026-11-06. This checklist ticks each brief item against its evidence.

Legend:
- ✅ done, with the evidence named;
- ◐ partly done: the open part is named;
- ⬜ open.

Harness = registered evidence (`scripts/dual_lane.py`). Scratch = run here outside the harness.

Status: HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

## Part A (the tile)

| Item | State | Evidence / what is open |
|---|---|---|
| A1 adapter double capture | ✅ | Registered-state assertion. No-guard mutant killed in the harness (`i14_mut_no_guard`). 71178d5a. |
| A2 `tb_conformance` re-run | ✅ scratch | 1,000 transactions PASS (`R1_BATCH_SCRATCH`). Legacy bench without CHECKS lines, so not registered. |
| A3 real bus errors | ✅ | Poison 0xBADB_E00x, IRQ 3, STATUS fault latch. Harness: `r1_adapter_a3`, `r2_cpu_tile_noc`, `i14_mut_no_poison`, `i14_mut_sideband`. |
| A4 random-latency stress that terminates | ✅ scratch | 1,000 / 1,000 seeds after the seeding fix (2222fc86). Legacy bench, not registered. |
| A5 bench hygiene | ◐ | Done: `tb_addr_decode_v2`, `tb_tile_status`, `tb_gpio`, `tb_two_tiles` self-check (harness). App-port assertions: B5 checker. **Open:** TMEM-side "stable while pending / one response per request" assertions in the adapter; `tb_two_tiles` still runs the *same* program on both tiles. |
| A6 reset, tile identity, decode | ✅ scratch | Done: synchronous reset (A6, plus the B7 DRC fix); TILE_ID parameter and STATUS +0x10; decode refusal for T ≥ 6 / T ≠ 2 / self in the bridge (`r2_tmem_app_bridge`). Decode table bench `tb_bridge_decode_table` (T = 0..15 + prefix + misaligned): 18/18 in scratch (`A6_A9_SCRATCH`). |
| A7 memories | ◐ | Done: IMEM read port B (`r1_mem_bram_dp`). Tile-2 memory is Lane 1's `tile2_bram_infer`. MEMORY_MAP.h / link.ld set to 16 KB (a59c6b2d). **Open:** `memtest` at every alignment. |
| A8 demo software | ◐ | Done: one-command build (`scripts/rv32_asm.py`); Program A (wait AUTHORIZED → write / read 0x2200_0100 → UART); Program B (refused → UART); on two tiles (`i14_demo_fw`) and in the merged SoC (`i15_merged_real`). **Open:** polling limit; REVOKE → trap demo; IRQ handler path; "REFUSED OK" / PASS-first line format; `rdcycle` and traffic generator. ATTEST_REQ is not written, because the RoT starts attestation under the sec. 8 policy. |
| A9 tile synthesis at 20 ns | ◐ | `cpu_tile_noc` (contains `tile_top`) OOC synthesis: WNS +7.903, IMEM inside (B7). Merged post-route WNS +0.237. **Open:** OOC implementation and the latch / loop / multi-driven report for the tile alone. Script `synth/riscv/a9_cpu_tile_noc_impl.tcl` is ready, but the run is NOT_RUN: two Vivado tool-environment failures (scripts that exist on disk could not be read), one relaunch used. |
| A10 re-submission package | n/a | Lane 1 owns the code now: everything is committed, and the reports and READMEs are in the repo. |

## Part B (the interface package)

| Item | State | Evidence |
|---|---|---|
| B1 `tmem_app_bridge` | ✅ | `r2_tmem_app_bridge` 19 checks; `i14_mut_auth_removed` (fork 8305fe81) |
| B2 `cpu_tile_noc` | ✅ | `i14_cpu_tile_noc` 12; README port table; stub-identical ports |
| B3 measurement window reader | ✅ | `r2_meas_window_reader` 10 (`d2_k3_64` rows 0 / 1); `i14_mut_word_order`, `i15_mut_word_order` |
| B4 STATUS block + `status_regs.h` | ✅ | `r1_tile_status` 14; `sw/riscv/status_regs.h` |
| B5 protocol checker | ✅ | `i14_app_port_checker` 10; `i14_mut_b5_auth_removed`; bind into `tb_pq_full_chain` compiles (fork) |
| B6 co-simulation with the real Lane 1 RTL | ✅ | `i15_merged_real` 10 (measurement → GRANT → write / read through the NoC → refusal → revoke) |
| B7 area / timing of the tile | ✅ scratch | 2,938 LUT / 2,230 FF / 8 BRAM36, WNS +7.903 (synthesis); `docs/riscv_lane/RESOURCES.md` |

## R-4 merge (Lane 1)

| Step | State | Evidence |
|---|---|---|
| Merged source list | ✅ | `make_merged_sources.py`: preflight PASS, 70 files |
| Merged co-simulation | ✅ harness | I-15 (3e860bd4) |
| Merged bitstream | ✅ batch flow | 34,987 LUT, WNS +0.237, WHS +0.035, 0 critical warnings (16f2d63c) |
| Project-update Tcl | ✅ | Tested on a project copy: GUI-path simulation 10/10 (ef9ab31d) |
| Board run | ⬜ **Kalash** | Checklist in `reports/OVERNIGHT_20261107.md` |

## Next plan

Work order. The first five run here without you.

1. ~~A7 docs~~: done (a59c6b2d). ~~A6 decode table~~: done in scratch; register it in the next increment.
2. **A8 firmware completion in `demo_fw.S`:**
   - polling limit;
   - PASS / FAIL-first lines;
   - "REFUSED OK";
   - `rdcycle` print.

   Re-run `tb_demo_fw` and the merged co-sim as new frozen counts in a new increment, then rebuild the bitstream and re-provision APPROVED_MEAS if the boot stub changes. The boot stub is designed to stay fixed.
3. **A5:** a second program for `tb_two_tiles`, and TMEM-side assertions in the adapter.
4. **A9:** re-run `synth/riscv/a9_cpu_tile_noc_impl.tcl` after a Vivado restart / tool check (NOT_RUN tonight).
5. **Hold:** firmware v2 (item 2) waits for your board run on v1, so the ready bitstream does not change underneath you.
6. **Kalash:** board run → hardware record.
7. **Later, on Kalash's call:**
   - C firmware (R-D2);
   - harness board-top implementation gate;
   - research paper;
   - GDSII flow on the college Cadence setup.
