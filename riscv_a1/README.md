# RISC-V A1: tb_tile_top that ends by itself (fix, 2026-11-06)

> **2026-11-06 update:** these fixes now live in the single imported tree: `rtl/riscv/picorv32_adapter.sv` and
> `sim_riscv/tb_tile_top.sv` (import manifest: docs/riscv_lane/IMPORT_MANIFEST.json). The duplicate copies that were here
> (`riscv_a1/rtl`, `riscv_a1/sw`) were removed; `run_tb_tile_top.tcl` builds from the single tree and runs in `riscv_a1/run/`.
> Re-run from the single tree: `RESULT : PASS`, 6,229 = 6,229 = 6,229, `$finish` at 809,571 ns. Negative test (guard
> removed): 24 x `[FAIL] A1_NO_CAPTURE_DURING_READY`, CPU stuck at 0x12C, 24 transfers / 31 captures / 30 responses, `RESULT : FAIL`.


**Status:** scratch-level check, NOT registered evidence. Not part of the RISC-V takeover plan (docs/proposals/RISCV_TAKEOVER_PLAN_20261106.md), which still awaits Kalash's go.

**Source:** the RISC-V lane's `PQ_ATTEST_A1_working_copy.zip` (SHA-256 `ee36ae70...9b49`). All files are copied unchanged except two.

## The problem

Their `tb_tile_top` never ended in XSim. It ran past 14 ms of simulated time without reaching its PASS / FAIL or its 150 µs watchdog.

## Causes

1. **False assertion flood.** The assertion in `picorv32_adapter.sv` fired `$error` + `$fatal(1)` on every *suppressed* capture attempt: about 317,000 false messages. A live `mem_valid` while the ready pulse is presented is legal, because PicoRV32 keeps it high for a compressed second-word fetch (`picorv32.v` lines 600-603).
2. **`$fatal` does not end the run.** In an `xsim -R` run, `$fatal` does not terminate the simulation, so neither the FAIL path nor the watchdog ended it.
3. **Pass check too early.** It sampled the PC after a fixed 5,000 cycles, while the CPU is still in its UART print loop. That gave a false FAIL "PC not beyond 0x12C", even though the CPU was not stuck.

## Changes (bench and simulation-only code; no synthesizable logic changed)

| File | Change |
|---|---|
| `rtl/picorv32_adapter.sv` | The simulation-only check is now `a_no_capture_during_ready` on the **registered** state: after a cycle with `state_q == IDLE && mem_ready_q`, the adapter must still be IDLE. On violation it prints `[FAIL] A1_NO_CAPTURE_DURING_READY`. The check is no longer true by definition, and it no longer fires on legal attempts. |
| `rtl/tb_tile_top.sv` | Runs until the CPU sits in its end loop (PC unchanged for 1,000 cycles; at most 2.5 M cycles), then drains and checks: max PC > 0x12C, end loop reached, captures = core transfers = responses, adapter idle. Every exit path prints `RESULT : PASS/FAIL` and calls `$finish`. The watchdog is at 60 ms. The heartbeat prints every 50,000 cycles. |

The CPU core (`picorv32.v`), the adapter's capture guard (`capture = IDLE && mem_valid && !mem_ready_q`) and all other RTL are unchanged.

## Result (XSim 2024.1)

The bench now passes and ends by itself:

`A1 FINAL: pc=00000148 max_pc=00000148 end_loop=1 run_cycles=40469 core_transfers=6229 adapter_captures=6229 adapter_responses=6229 settle_cycles=0`

`RESULT : PASS`, `$finish` at 809,571 ns.

## Run it

```tcl
source C:/vivado_verilog_proj/NOC_PQATTEST/riscv_a1/run_tb_tile_top.tcl
```

## Still open (A1 and beyond, per the takeover plan)

- `tb_two_tiles` with per-tile accounting.
- A mutant without the guard that this bench must kill.
- A conformance re-run.
- Registration in the harness.
