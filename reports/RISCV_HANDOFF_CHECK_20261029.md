# RISC-V lane handoff check, 2026-10-29: NOT ACCEPTED

- **Package:** `PQ_ATTEST.zip` (Downloads), 12,634,534 bytes, SHA-256
  `273e3057196026331c3da0c4f6abebffda2b4618d809648cd1ec29a5653a2cd7`, 358 files. It is a Git working tree
  (origin github.com/arnav1609/PQ_ATTEST, branch main, 1 commit "Set up project structure"). Only 4 files are tracked
  (DESIGN_LOG.md, MEMORY_MAP.h, README.md, RESOURCES.md); every RTL, software and testbench file is untracked.
- **Checked against:** the lane brief `BRIEF_RISCV_Lane_Complete.md.docx` (Part 5 interface contract, Part 8 constraints,
  Part 10 deliverables and acceptance criteria 1-28), and this repository's NoC side (noc_pkg, noc_addr_decoder,
  pq_noc_subsystem_p7).
- **Method:** extracted read-only into an isolated scratch folder. The team's own testbenches were compiled and run in
  XSim 2024.1 with hard-coded `C:/Users/HP/...` paths rewritten to the copy. One added probe bench (scratch, not evidence)
  counted core transfers against adapter requests. Nothing from the package was executed except HDL simulation; nothing
  was copied into this repository.
- Evidence class: XSim-simulated (scratch, not registered) and source-inspected. Hardware, timing and formal: NO.

## Verdict

Not accepted for Integration 1. A blocking adapter bug: `picorv32_adapter.sv` issues duplicate transactions, including
writes. The conformance test fails, the random-latency test hangs, and several required deliverables are missing.

## Blocking findings

1. **Duplicate transactions in `picorv32_adapter.sv` (design bug).**
   - In RESPONSE the adapter sets `mem_ready_q` and returns to IDLE on the same edge.
   - PicoRV32 drops `mem_valid` only on the next edge, after it samples `mem_ready` (`mem_xfer`, picorv32.v:373).
   - So IDLE sees `mem_valid` still high and captures the same request again.
   - Probe on `tb_tile_top`: 24 core transfers (3 writes) against 31 adapter requests (5 writes).
   - Effect: spurious duplicate writes. On the TMEM side these are double remote side effects. The CPU stops progressing
     at PC 0x12C, in both `tb_tile_top` and `tb_two_tiles`.
   - Fix direction (the team's call): do not accept a new request in the cycle `mem_ready` is high, e.g. a one-cycle
     post-response state or gating capture with `!mem_ready_q`.
2. **TMEM conformance fails** (the team's `tb_conformance`, 1,000 transactions):
   - stability errors 3,996, fetch-flag errors 999, protocol errors 1,999, response errors 0;
   - result FAIL;
   - the counts match the duplicate capture above (about 4 field mismatches plus 2 protocol errors per transaction).
3. **Random-latency stress test does not run to completion** (`tb_random_latency`):
   - no output for 900 s, after which my bounded wait stopped it;
   - it never prints its first transaction and has no internal timeout;
   - as written it covers 20 transactions on one seed, while the brief (7.1, criterion 13) requires 1,000 seeds.
4. **Bus errors complete silently.**
   - On `tmem_err` or a local error the adapter returns read data 0 and a normal `mem_ready`.
   - `dbg_trap_o` is tied to 0.
   - The brief (4.2, 4.3, criterion 6) requires a bus error back to the core, never a silent zero.

## Other findings

| # | Item | Status |
|---|---|---|
| 1 | PicoRV32 unmodified, RV32IMC | configured RV32IMC (COMPRESSED_ISA = 1, ENABLE_MUL = 1). Byte-identity to upstream not verified here (SHA-256 of the shipped file `0836050971b3c6cd...0622`; compare with the upstream tag used) |
| 3 | Two instances, different IDs and programs | `tb_two_tiles` passes, but both tiles load the same `hello_words.hex`, and its pass rule is only PC != 0 |
| 4, 7 | Local memory all sizes and alignments; status registers from software | no memtest.c; no test |
| 8 | Attest-request pulse exactly one cycle | logic present in tile_status.sv; no test (`tb_tile_status` has no checks) |
| 9 | Memory tile with no processor | memory_tile.sv absent |
| 10 | Exactly the ten TMEM signals | present on tile_top. TILE_ID / BUILD_ID are parameters, not the `tile_id_i` / `build_id_i` ports of 5.5; `last_fault_timeout_i` added (fine, but agree it) |
| 11, 12 | Address-stable and one-response assertions | no assertions in the RTL (7.3) |
| 15 | No combinational grant-to-request path | holds by inspection (`tmem_req_o` is a function of the registered state only) |
| 16-18 | No latches, loops, multi-driven nets | tile_top synthesis log: 0 errors, 0 critical warnings, 97 warnings (unconnected PicoRV32 ports); not confirmed per criterion |
| 20 | Timing at 50 MHz | no tile_top implementation or timing report; the impl_1 run in the package is an LED-blink project |
| 21 | Resources measured | tile_top synthesis (2026-09-29): LUT 1,674 (48 LUTRAM), FF 1,102, DSP 0, **Block RAM 4**. RESOURCES.md records standalone PicoRV32 only (RV32IMC 1,478 LUT, 902 FF, about 130 MHz synthesis estimate at a 10 ns constraint) |
| 22 | Zero BRAM inside tile_top | violated in that synthesis report (4 BRAM tiles); confirm whether the report predates moving memories out |
| 23 | Reset per 8.1 | reset_sync.sv is correct in shape (async assert, sync deassert, gated on `locked_i`) but is not instantiated in tile_top; tile_status uses an asynchronous reset while the other blocks use synchronous ones |
| 24 | Debug taps | `dbg_pc_o` is the memory address, not the retiring PC; `dbg_inst_o` is the memory read data; `dbg_trap_o` is constant 0 |
| - | mem_bram second read port (4.7) | absent (one port only) |
| - | UART | 115200 baud from 50 MHz, 16-entry FIFO; `tb_uart_tx` and `tb_uart_mmio` PASS |
| - | Benches that never end | `tb_tile_status` and `tb_gpio` ran 900 s without `$finish` (stopped by my bounded wait); neither contains a check |
| - | Unit test drift | `tb/tb_addr_decode.sv` no longer elaborates: it connects `local_req_i`, which the shipped addr_decode.sv does not have |
| - | Memory map | RTL is 16 KB IMEM + 16 KB DMEM; MEMORY_MAP.h and link.ld still say 8 KB (marked placeholders). The local map matches noc_pkg, except that noc_pkg's NI window 0x1000_3000 is unmapped in their decoder |
| 25-28 | Software (one-command hex, different programs, cycle counter, traffic generator) | convert_hex.py, start.S, print library and hello.c present; no cycle-counter code, memtest or traffic generator |
| - | Docs | README.md and DESIGN_LOG.md are empty; stray build products (a.out, xsimk.exe, .wdb, .dcp) are inside the tree |

## Our side (Lane 1): integration issues found by this check

These are for Kalash, not for the RISC-V team.

1. **Who may send data in P7.**
   - Under M-F1 rev 7 / P7 only tiles 3 and 4 are attested.
   - The CPU tiles 0 and 1 and the memory tile 2 are built ATTESTABLE = 0, so their gates refuse application data
     (noc_attest_gate.sv:21, and registered I-5 job p7_gate_data).
   - The brief's demo (CPU tiles attest, then their traffic flows) therefore cannot run on the P7 subsystem as built.
   - This needs a decision before Integration 2: attest CPU tiles, or change the demo.
2. **Remote address mismatch inside our design.**
   - noc_pkg REMOTE_BASE is 0x2000_0000 with the tile in bits [27:24]; the team's MEMORY_MAP.h and their adapter agree.
   - The P7 memory stand-in accepts only `address[31:28] == 4'h8 && address[27:24] == 2` (pq_noc_subsystem_p7.sv:248).
   - A CPU access to the memory tile at 0x2200_xxxx would be answered as illegal.
3. **No TMEM <-> NI bridge exists yet.** The team's tile ends at the ten TMEM signals. Our NI takes tx_valid / dest /
   msg_type / control / payload. Converting TMEM to MEM_WR_REQ / MEM_RD_REQ and their responses (and `tmem_err`) is Lane 1
   work, not started.
4. **N-8.1 watchdog (OPEN-T1).** TMEM has no response backpressure (`tmem_rvalid` must always be accepted), so the
   tile-side RX stall S_tile can be 0 once the bridge exists.

## Area against the B3 rule

44,412 (P7 subsystem, OOC synthesis) + 2 x 1,674 (two CPU tiles, tile_top synthesis, memories excluded) = 47,760 LUT, below
54,000. B3 would not trigger. This excludes the memory tile, the bridges and BRAM wrappers, and the tile figure comes from a
report that may predate the current RTL. Phase B is cancelled anyway (Kalash 2026-10-29).

## Requested from the RISC-V team before re-submission

1. Fix the adapter double capture; rerun `tb_conformance` to PASS.
2. Make `tb_random_latency` terminate (internal timeout) and run 1,000 seeds over the full memory test.
3. Raise a real bus error on `tmem_err` / unmapped access; drive `dbg_trap_o`.
4. Add the 7.3 assertions; fix `tb_addr_decode`; give `tb_two_tiles` two different programs and a real pass rule.
5. Deliver memory_tile.sv, the mem_bram second read port, memtest.c, cycle-counter access and the traffic generator.
6. Re-synthesize tile_top (confirm 0 BRAM, 0 DSP), add an implementation run at 50 MHz, update RESOURCES.md, fill README.md
   and DESIGN_LOG.md, set the memory sizes in MEMORY_MAP.h and link.ld, commit the sources, and drop the build products.
