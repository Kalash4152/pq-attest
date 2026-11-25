# RISC-V CPU tile resources (brief v2 B7)

`cpu_tile_noc` was synthesized out of context with Vivado 2024.1. Lane 1, 2026-11-07.

**Setup:**
- Part xc7a100tcsg324-1, 20 ns clock.
- 5 ns input and output delays assumed.
- Synthesis only, no place-and-route.
- Script: `synth/riscv/b7_cpu_tile_noc_ooc.tcl`.
- Reports: `docs/riscv_lane/b7_20261107/`.

This is a **scratch measurement** run outside the harness: synthesized, not implemented, not hardware-validated.

**BRAM is inside the module:** IMEM 16 KB + DMEM 16 KB, inferred block RAM.

| Metric | Value |
|---|---|
| LUT | 2,938 (2,842 logic + 96 LUTRAM) |
| FF | 2,230 |
| BRAM36 tiles | 8 |
| DSP | 0 (PicoRV32 MUL / DIV in LUTs) |
| WNS setup, post-synthesis | +7.903 ns |
| WHS hold, post-synthesis | +0.256 ns |
| DRC | 1 warning: CFGBVS-1, a board-level XDC property that does not apply to an OOC module |

## Per-instance utilization (first run, same RTL apart from the reset)

| Instance | LUT | FF | BRAM |
|---|---|---|---|
| u_tile (tile_top) | 2,777 | 1,533 | 0 |
| of which picorv32 | 1,332 | 708 | 0 |
| u_bridge (tmem_app_bridge) | 115 | 135 | 0 |
| u_meas (meas_window_reader) | 24 | 524 | 0 |
| u_mem (IMEM + DMEM) | 18 | 2 | 8 |

## First run: DRC REQP-1839, fixed

The first run used `reset_sync`. Its asynchronous set drove the BRAM enable pins (22 × REQP-1839). That is an untimed asynchronous control on RAMB36.

Lane 1's `rst` is already synchronous to `clk`. So `cpu_tile_noc` now uses a synchronous 2-flop reset pipeline that powers up asserted:
- assertion takes 1 edge;
- release is still 2 edges after `rst` falls.

**Re-run after the fix:**
- REQP-1839: 0.
- Timing: unchanged.
- LUT: +1.
- Benches still pass in scratch: `tb_cpu_tile_noc` 12/12, `tb_demo_fw` 9/9, and the sideband mutant is still killed.

The first-run DRC is kept in `b7_20261107/first_run_reset_sync/`.

## Merged-area outlook

This is an INFERENCE, not a measured result:

| Item | LUT |
|---|---|
| Released p7_board | 29,319 |
| Two CPU tiles (≈ 2 × 2,938) | ≈ 5,900 |
| Estimate, minus the stubs they replace | ≈ 35,200 |

That is below the D4 hard stop of 47,550. The merged synthesis will measure it.

---

## Earlier numbers from the RISC-V lane (imported in aae60b47, unchanged)

### PicoRV32 Synthesis Resources

Standalone synthesis results for PicoRV32 on the Digilent Arty A7-100
(Xilinx Artix-7 `xc7a100tcsg324-1`) using Vivado 2024.1.

| Configuration | ENABLE_MUL | COMPRESSED_ISA | LUTs | FFs | Fmax |
|---|---:|---:|---:|---:|---:|
| RV32I | 0 | 0 | 928 | 575 | ~206.27 MHz |
| RV32IMC | 1 | 1 | 1478 | 902 | ~130.34 MHz |

#### Notes

- `picorv32.v` was used unmodified.
- LUT and FF values are from Vivado post-synthesis utilization reports.
- Fmax values are synthesis-estimated from a 10 ns clock constraint.
- Timing paths were unplaced at this stage, so these are not final post-route Fmax values.
- Both configurations use 0 BRAMs and 0 DSPs.
## A9: OOC implementation (post-route), 2026-11-07

Script: `synth/riscv/a9_cpu_tile_noc_impl.tcl`. Reports: `docs/riscv_lane/a9_20261107/`. This is a scratch measurement, outside the harness.

| Metric | Value | Brief A9 criterion |
|---|---|---|
| LUT / FF / LUTRAM / BRAM36 / DSP | 2,881 / 2,230 / 94 / 8 / 0 | |
| WNS / WHS / TNS | +4.909 / +0.038 / 0.000 ns | WNS ≥ 0 and WHS ≥ 0: **met** |
| Latches / combinational loops (LUTLP-1) / multi-driven (MDRV-1) | 0 / 0 / 0 | **met** |
| Critical warnings | 0 | |
| DRC | CFGBVS-1 (board property, n/a OOC), RTSTAT-10 (OOC dangling nets) | |
| Methodology | 649 × XDCH-2 (identical min/max I/O delay from the assumed 5 ns budgets) | |

**IMEM:** inside the module.

**Earlier attempts:** four attempts failed inside Vivado's startup scripts (tool environment). This run passed with 1.2 GB of free RAM.
