# Overnight 2026-11-07: main Lane 1 session. Morning summary for Kalash

**Bottom line:**
- The RISC-V lane is integrated: two real PicoRV32 tiles with firmware, inside the merged NoC + PQ-Attest SoC.
- The merged bitstream is **built with timing met**: 34,987 LUT, WNS +0.237 ns, WHS +0.035 ns.
- It is **ready for your board run**.

Status: HARDWARE_VALIDATED=NO (the board run is yours), SOC_INTEGRATION_COMPLETE=NO (until your board run and its registration), FORMAL_PROOF=NO.

| # | Task | State | Result / commit |
|---|---|---|---|
| 1 | B7: `cpu_tile_noc` OOC synthesis at 20 ns | ✅ | 2,938 LUT, 2,230 FF, 8 BRAM36, WNS +7.903 (6ff0d713). DRC REQP-1839 fixed: synchronous reset. |
| 2 | B5 intake (fork handoff aced7452) | ✅ | Re-run here: 10/10, and the bound-checker mutant is killed |
| 3 | Hex-path fix (`tb_two_tiles`) | ✅ | IMEM preloaded from an include, so the harness can run it |
| 4 | Harness mutant kinds + negative tests | ✅ | `rva_` / `rvc_` / `rvb_` / `rvm_`; `test_dual_lane` 142 OK |
| 5 | **I-14 gate** | ✅ **PASS** | 10/10: 4 benches + 6 mutant kills (bf497843) |
| 6 | Demo firmware without GCC (R-3a) | ✅ | `scripts/rv32_asm.py` + `sw/riscv/demo_fw.S`. Two tiles print "T3 PASS" and "T0 REFUSED". |
| 7 | R-4 step 1: merged source list + B6 co-simulation | ✅ | 70 files, preflight PASS. `tb_merged_real` 10/10 (c7d8c7aa). |
| 8 | **R-4 step 2: merged bitstream** | ✅ **TIMING MET** | 34,987 LUT (≤ 47,550), WNS +0.237 / WHS +0.035, 0 critical warnings (16f2d63c). `reports/MERGED_BUILD_20261107.md`. |
| 9 | Project-update Tcl, tested on a project copy | ✅ | Sets created; the GUI-path simulation `dl_merged_real` gives 10/10 PASS (ef9ab31d) |

## What you do (board run)

You can program the bitstream that is already built. Open the Hardware Manager and program:
`C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.runs_merged/merged_board/pq_merged_board_top.bit`
(sha256 d738b12b…67e3).

Before that, open a serial terminal: 115,200 baud, 8N1.

What to check:
1. **After reset:**
   - led[0] on: tile 3 authorized.
   - led[2] on: CPU A printed "T3 PASS".
   - led0_r on: CPU B printed "T0 REFUSED".
   - led[1] and led0_g off.
   - led[3] blinking.
2. **UART:** sw[0] = 0 → "T3 PASS"; sw[0] = 1 → "T0 REFUSED". The lines print once per reset, so press btn[0] with the terminal open.
3. **btn[2] (revoke):** led[0] goes off. **btn[1] (re-attest):** led[0] comes back.

**Optional: add everything to the project.** In the Vivado Tcl console with `NOC_PQATTEST.xpr` open:
```
source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/merged_project_update.tcl
merged_sim          ;# dl_merged_real: expect RESULT : PASS, 10/10
merged_build        ;# only if you want to rebuild the bitstream (~1 h)
```
It backs up the `.xpr` first and only touches the `dl_merged_*` sets.

Tell me what the board shows. The result goes into a hardware record, and only then does HARDWARE_VALIDATED change.

## Decisions taken tonight (VLSI review, under your delegation)

- **Measurement trigger:** ATTEST_REQ, plus one pulse after reset.
- **A3 sideband:** `{0, last_err_kind}`.
- **Reset:** synchronous 2-flop reset in `cpu_tile_noc`. This fixes the B7 DRC.
- **Firmware:** an in-repo RV32I assembler, so no GCC download was needed. R-D2 stays open, only for future C firmware.
- **B5 checker:** keeps the M-F1 rev 8 rule-6 withdrawal, so no contract question arises.
- **B5 bench fix:** `REPORT = 0` on the negative-injection checker. The judge is unchanged.
- **Not registered:** `tb_tile_top`, which is covered by `tb_two_tiles`.

## Next plan (ready; I continue with it unless you redirect)

1. **I-15:** register the merged co-simulation (`tb_merged_real`, 10 checks) and the merged implementation gate in the harness. This makes the merged result registered evidence, not scratch.
2. **After your board run:** a hardware record with your observations. HARDWARE_VALIDATED changes only from your report.
3. **Final completion report:** an updated Lane 1 + RISC-V checklist, every item ticked with its commit and evidence.
4. **Later, on your call:**
   - C firmware (R-D2 GCC download);
   - research paper;
   - GDSII flow on the college Cadence setup.
