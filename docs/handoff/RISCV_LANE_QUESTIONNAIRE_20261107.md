# Questionnaire for the RISC-V lane, from Lane 1 (Kalash Bheda), 2026-11-07

Lane 1 took over your package (`PQ_ATTEST_A1_working_copy.zip`, ee36ae70…9b49) on 2026-11-06 and integrated it into the merged NoC + PQ-Attest SoC. The merged bitstream with two of your PicoRV32 tiles has run on the board and printed PASS.

We changed some things and wrote some missing parts. Please answer briefly, by question number. "Don't know" is a fine answer.

## 1. Changes we made: please confirm nothing of yours depends on the old behaviour

| # | What we changed | Question |
|---|---|---|
| 1.1 | **A1:** the adapter no longer captures while `mem_ready` is being presented (registered-state guard). | Did any of your code or benches rely on the old capture timing? |
| 1.2 | **A3:** a bus error now returns `0xBADB_E000 | code` (codes 1-5), raises IRQ 3 and latches STATUS. Your contract said a read error returns 0. | Does any of your software check for 0 on error? |
| 1.3 | **AD-1:** `addr_decode` now makes one memory access per transaction. Before, IMEM/DMEM saw two accesses per load. | Was the double access intentional, for example as a wait-state trick? |
| 1.4 | **AD-4:** an unmapped address now gets its error answered *after* the grant. Before, the CPU hung. | Known issue on your side? |
| 1.5 | **R-D8:** IMEM is read-only from the CPU data bus; a store is a bus error. | Did any program write IMEM (self-modifying code, a loader)? |
| 1.6 | **R-D9:** `ENABLE_DIV = 1`. CPU 1 trapped on `remu`, because only MUL was enabled while the declared ISA is rv32im. | Which `-march` / `-mabi` did you build with? Was DIV left out on purpose for area? |
| 1.7 | **A6:** all resets are synchronous. `cpu_tile_noc` uses a synchronous 2-flop pipeline, not your `reset_sync`: its async set drove the BRAM enables (DRC REQP-1839). | Where else did you use `reset_sync` (`fpga_top`?) and why asynchronous? |
| 1.8 | **B4:** the STATUS map was replaced. CTRL (+0x0), FAULT_ADDR (+0x4), FAULT_CODE (+0x8), BUILD_ID (+0xC), TILE_ID (+0x10). | Was any of the old map (BUILD_ID +0, STATUS +4 with tile_id[7:4], ATTEST_REQ +8) needed by something other than `hello.c`? |
| 1.9 | **A7:** MEMORY_MAP.h / link.ld changed from 8 KB to 16 KB, to match RTL `IMEM_WORDS` / `DMEM_WORDS` = 4096. | Was 8 KB a placeholder, or a planned size? |
| 1.10 | `tb_two_tiles` loads IMEM from an include, not from `$readmemh("sw/hello_words.hex")`. | Fine? |

## 2. Files we did not use: what are they for?

| # | File | Question |
|---|---|---|
| 2.1 | `rtl/riscv/fpga_top.sv` | Standalone board top for one tile? Was it tested on hardware? Which XDC? |
| 2.2 | `rtl/riscv/memory_tile.sv` | Is it only a bench model of tile 2, or meant for synthesis? |
| 2.3 | `rtl/riscv/tmem_traffic_gen.sv` | Bench only? |
| 2.4 | `rtl/riscv/program.hex`, `sw/riscv/tile1_words.hex` | Which programs are these, and with which sources and toolchain were they built? |
| 2.5 | `sw/riscv/convert_hex.py` | The exact command line from ELF to `*_words.hex`? |
| 2.6 | `riscv_a1/` (scripts, logs) | Anything there we should keep or re-run? |

## 3. Toolchain and software

| # | Question |
|---|---|
| 3.1 | GCC: exact package, version and download URL (we need it for C firmware; decision R-D2). |
| 3.2 | Did you use compressed (C) instructions? `COMPRESSED_ISA = 1` in `tile_top`: is that required? |
| 3.3 | `print.c` includes `../MEMORY_MAP.h`, but that file is not at `sw/`. How did your build find it? |
| 3.4 | Did you ever run `hello.c` on a board? Any UART output captured? |
| 3.5 | Did you plan an IRQ handler (`PROGADDR_IRQ` = 0x10, maskirq)? Any code for it? |

## 4. Verification

| # | Question |
|---|---|
| 4.1 | `tb_conformance` and `tb_random_latency` never drive an error. Did you test the error path anywhere else? |
| 4.2 | The original `tb_addr_decode` targeted an older interface and did not elaborate. Which interface version was it for? |
| 4.3 | `tb_mutation_checks`: how were its "representative mutations" chosen? |
| 4.4 | Did you run any bench with `-d RISCV_FORMAL` on purpose? Did RVFI ever drive a checker? |
| 4.5 | Any known failing or flaky bench, or seed, that you did not report? |

## 5. Synthesis and timing

| # | Question |
|---|---|
| 5.1 | Your RESOURCES.md lists PicoRV32 RV32IMC at 1,478 LUT / ~130 MHz. Was that with MUL only, and with or without the adapter? |
| 5.2 | Did you ever implement (place and route) `tile_top` at 20 ns? Our OOC synthesis of `cpu_tile_noc` gives WNS +7.903 ns, and the merged design gives +0.237 ns post-route. |
| 5.3 | Any timing exceptions or constraints you expected us to keep? |

## 6. Anything else

| # | Question |
|---|---|
| 6.1 | Design decisions not written down: anything we should know before the paper / GDSII step? |
| 6.2 | Who should be credited, and how, for the RISC-V tile in the paper? |

Thank you.
