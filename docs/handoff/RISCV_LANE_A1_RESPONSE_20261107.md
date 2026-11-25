# A1 response to the RISC-V lane, from Lane 1 (Kalash Bheda), 2026-11-07

Your A1 analysis describes the working copy as it was before Lane 1 took it over. A1 is now **closed in Lane 1's tree**, and the evidence is in git.

Our simulator is Vivado XSim 2024.1. Icarus is not used and its results are not accepted as evidence here.

## Your questions, answered

| # | Your question | Answer | Evidence |
|---|---|---|---|
| 1 | Why `tb_tile_top` did not reach its completion checks | It was a **bench issue, not an RTL deadlock**. In XSim, `$fatal` and some exit paths of the old bench did not end an `xsim -R` run. The bench was fixed so every exit path prints `RESULT` and calls `$finish`, and the check waits for the program's end loop. It now ends with PASS: PC passes 0x12C and reaches the end loop, with 6,229 core transfers = 6,229 captures = 6,229 responses. | 71178d5a, `riscv_a1/run_tb_tile_top.tcl` |
| 2 | Counters 40 / 39 / 38 at cycle 250 | Not a duplicate. That snapshot catches one request accepted but not yet answered, plus the registered ready pulse (non-blocking update order). The counts are equal at the end of every run. | as above; `tb_two_tiles` T2_TILE*_COUNTS |
| 3 | Guard on the registered-ready cycle, including compressed fetches | Correct. PicoRV32 keeps `mem_valid` high, or presents a new address for the second half of a compressed fetch (`picorv32.v` 600-608), while `mem_ready_q` is presented. `capture = (IDLE && mem_valid) && !mem_ready_q` suppresses exactly that cycle, and the new request is captured on the next one. Checked with COMPRESSED_ISA = 1 on real programs, the conformance bench (1,000 transactions) and random latency (1,000 / 1,000 seeds). | `tb_two_tiles`, `R1_BATCH_SCRATCH_20261106.txt` |
| 4 | A meaningful `a_no_capture_during_ready` | It is checked on **registered state**, so it is independent of the `capture` wire. `idle_ready_q <= (state_q == IDLE) && mem_ready_q`; if `idle_ready_q && state_q != IDLE`, the adapter left IDLE in a cycle where the previous ready pulse was being presented. A live `mem_valid` in that cycle stays legal. | `rtl/riscv/picorv32_adapter.sv` |
| 4b | Does it fire when the guard is broken? | Yes. Mutant `rva_no_guard` (guard removed) is killed in the harness: `[FAIL] A1_NO_CAPTURE_DURING_READY` plus count mismatches. | I-14 job `i14_mut_no_guard` (bf497843) |
| 5 | Counters measure equivalent events | Core transfer = `mem_valid && mem_ready` at the core. Capture = the adapter's IDLE→REQUEST transition. Response = `local_rvalid` or `tmem_rvalid` delivered to the adapter. All three are counted on the same clock edge. | `tb_two_tiles` |
| 6 | `tb_two_tiles` against the A1 criteria | Both CPUs reach their end loops beyond 0x12C, bounded at 2.5 M cycles with a 60 ms watchdog. Counts match per tile, no trap, plus a remote write and a remote read. 8 checks, registered in the harness (`i14_two_tiles`). **Still open (brief A5):** both tiles run the *same* program. A second program is being added. | `sim_riscv/tb_two_tiles.sv` |
| 7 | Protected files | `picorv32.v` is untouched, the 10 TMEM signals are unchanged, and CATCH_MISALIGN / CATCH_ILLINSN are preserved. A3 adds a *sideband* `tmem_err_code_i`, not a TMEM signal. | — |

## Verified vs not verified (A1)

**Verified (harness):**
- the guard;
- the registered-state assertion, with a mutant kill;
- `tb_tile_top` / `tb_two_tiles` bounded PASS;
- conformance and random latency (scratch).

**Verified on hardware:**
- the merged SoC with both tiles: Kalash reported "Board shows PASS".

**Not verified:**
- formal proof of the guard: FORMAL = NO;
- a second, different program in `tb_two_tiles` (A5, in progress).

## What we need from you

Please answer the questionnaire (`RISCV_LANE_QUESTIONNAIRE_20261107.md`), especially:
- **Q3.1:** exact GCC package and version. Your `-march=rv32imc -mabi=ilp32` is noted as inferred, not confirmed.
- **Q1.2:** does anything rely on error reads returning 0?
- **Q2.x:** the purpose of the files we did not use.
