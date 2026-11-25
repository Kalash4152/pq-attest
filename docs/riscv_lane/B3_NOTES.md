# B3 notes: `meas_window_reader` (IMEM measurement window)

**Files:** `rtl/riscv/meas_window_reader.sv`, `sim_riscv/tb_meas_window_reader.sv`,
`riscv_a1/run_tb_meas_window_reader.tcl` (Vivado Tcl-console runner).

**Status:** scratch-level (XSim 2024.1), **not registered**. The main session registers the bench (CHECKS = 10, frozen in
its header before the first run), wires the reader in B2 (`cpu_tile_noc`), and owns the IMEM read port (A7,
`tile_mem_wrapper` `meas_rd_*`).

**Spec:** docs/handoff/BRIEF_RISCV_LANE_v2_20261101.md sec. B3; the main session's B3 task message (2026-11-06).

## Behaviour (as built)

| Item | Implementation |
|---|---|
| Ports | `clk`, `rst` (sync, active high), `start_i`; IMEM port `meas_rd_en_o`, `meas_rd_addr_o[31:0]` (byte address), `meas_rd_data_i[31:0]` (registered, 1-cycle latency); `meas_imem_o[511:0]`, `meas_imem_len_o[6:0]`, `meas_valid_o`, `busy_o`. Parameter `MEAS_BASE` (byte address, word-aligned, default 0). |
| Reads | 16 back-to-back reads at `MEAS_BASE + 4k`, k = 0..15, on the dedicated port. The CPU's IMEM port is not used, so the CPU is never stalled. |
| Byte order | `meas_imem_o[i*8 +: 8]` = IMEM byte `MEAS_BASE + i` (pq_measurement convention); little-endian word k sits at `[32k +: 32]`. |
| Length | `meas_imem_len_o` = 64 (constant). |
| Valid | Low from `start_i` until the 16th word is captured, then high; the window is frozen until the next `start_i`. It rises 17 cycles after the start edge. |
| Restart | `start_i` while busy restarts from word 0; the in-flight read's data is ignored. Exactly one valid rise per completed load. |

## Scratch results (XSim 2024.1)

**Unmutated: `RESULT : PASS`, 10 / 10 checks, 0 `Error:` lines.**
- IMEM model loaded from `vectors/d2_k3_64.svh` (read-only `include): row 0 at bytes 0x00..0x3F, row 1 at 0x40..0x7F.
- `B3_WINDOW_ROW0`: the window equals the row 0 `imem` vector, byte for byte. `B3_BYTES_JSON_ROW0`: byte 0 = 0x10, byte 63 =
  0x4F (the JSON row 0 IMEM bytes 0x10..0x4F).
- Reads: 16, addresses 0x00..0x3C, back to back. Valid rises once, 17 cycles after the start edge.
- Frozen: IMEM rewritten while idle, 50 cycles: window unchanged, 0 reads.
- Restart (valid drops, new window loaded), restart 5 cycles into a load (one valid rise, final window = current IMEM),
  `MEAS_BASE` 0x40 (row 1 window): all PASS.

**Mutants (scratch, one RTL edit each, generated outside the repo): 3 / 3 killed, each `RESULT : FAIL`, no timeouts.**

| Mutant | Edit | Killed by |
|---|---|---|
| `word_order_reversed` | word k stored at `[32(15-k) +: 32]` | `B3_WINDOW_ROW0` (byte 0 = 0x4C), `B3_BYTES_JSON_ROW0`, `B3_BASE_0x40` + 3 more (6 errors) |
| `off_by_one_start` | read address `+ 4` | `B3_READ_SEQUENCE` (first 0x04, last 0x40), `B3_WINDOW_ROW0` (byte 0 = 0x14) + 5 more (7 errors) |
| `bytes_swapped` | bytes reversed within each word | `B3_WINDOW_ROW0` (byte 0 = 0x13), `B3_BYTES_JSON_ROW0` + 4 more (6 errors) |

`bytes_swapped` is an extra mutant beyond the two requested.

## Bench notes

1. The first run passed 10 / 10 with three block-local initialized variables that XSim warned were implicitly static
   (`VRFC 10-3824`). They were made explicitly `automatic`, so they are evaluated when the block runs, and the base was
   re-run (10 / 10 PASS, warnings gone) before the mutant runs. No check or count changed.
2. Every scratch sim hit the known XSim start stall once and passed on the single retry; no result came from a stalled run.

## Open points

1. The brief's "done" also asks for a match against Engineer 4's step 14 expected vector. Our row 0 `imem` vector is
   byte-identical to his copy of `vectors/d2_k3_64.*` (E4 intake 2026-11-06), so this bench covers the byte pattern; the
   measurement digest itself is computed by the endpoint, not here.
2. Wiring in `cpu_tile_noc` (B2): `start_i` from `attest_req`; `meas_imem_o` / `meas_imem_len_o` to the endpoint's `imem` /
   `imem_len`. Whether the endpoint should wait for `meas_valid_o` before measuring is a B2 integration point.
