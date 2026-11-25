# A1 patch notes — PQ_ATTEST

## Scope

This patch addresses only A1 duplicate-request capture and its immediate testbench evidence.

## Files changed

- `rtl/picorv32_adapter.sv`
  - Retains the existing `mem_valid_i && !mem_ready_q` behavior through an explicit `capture` signal.
  - Adds `capture_attempt` and a simulation-time assertion that no capture attempt occurs while `mem_ready_q` is high.
  - Does not modify PicoRV32 or the ten TMEM interface signals.

- `rtl/tb_tile_top.sv`
  - Replaces the unbounded `$monitor` trace with 500-cycle heartbeat messages.
  - Counts CPU accepted transfers, adapter captures, and adapter responses.
  - Checks that the architectural PicoRV32 `reg_pc` advances beyond `0x12C`.
  - Adds bounded settling and a simulation-time watchdog.
  - Replaces the machine-specific IMEM path with `sw/hello_words.hex`.

- `rtl/tb_two_tiles.sv`
  - Replaces machine-specific IMEM paths with `sw/hello_words.hex`.
  - Reports/checks the actual PicoRV32 `reg_pc` in both instances, rather than the tile debug bus address.
  - Requires both CPUs to advance beyond `0x12C`.
  - Adds a simulation-time watchdog.

## Verification status

**NOT RUN in this environment.** This environment does not have Icarus Verilog or Vivado installed. No compile or simulation PASS is claimed.

The previous `build/tb_tile_top_A1.log` included in the source ZIP is historical evidence only and ends at approximately 4.43 us. It is not a completed regression.

Run the following from the repository root in Windows PowerShell:

```powershell
New-Item -ItemType Directory -Force -Path build | Out-Null

& "C:\iverilog\bin\iverilog.exe" -g2012 -s tb_tile_top `
  -o build/tb_tile_top_A1.vvp `
  rtl/picorv32.v rtl/picorv32_adapter.sv rtl/addr_decode.sv `
  rtl/tile_status.sv rtl/uart_tx.sv rtl/uart_mmio.sv `
  rtl/tile_top.sv rtl/mem_bram.sv rtl/gpio.sv `
  rtl/tile_mem_wrapper.sv rtl/tb_tile_top.sv

if ($LASTEXITCODE -ne 0) { throw "tb_tile_top compile failed" }

& "C:\iverilog\bin\vvp.exe" build/tb_tile_top_A1.vvp `
  > build/tb_tile_top_A1.log 2>&1
if ($LASTEXITCODE -ne 0) { throw "tb_tile_top simulation failed" }

Get-Content build/tb_tile_top_A1.log -Tail 40
```

Compile `tb_two_tiles` with the same RTL dependencies plus `rtl/memory_tile.sv` and `rtl/tb_two_tiles.sv`, using `-s tb_two_tiles`.

The conformance and random-latency tests must also be rerun with their original checks unchanged. Do not mark A1 complete until both integration simulations finish normally and their logs show the required PC progress and count reconciliation.

## Important limitation

The uploaded project ZIP did not include `BRIEF_RISCV_LANE_AREA_ADDENDUM_20261103.md`. This A1 patch does not attempt any area optimization or later A-series/B-series work.
