# RISC-V lane: status report (memory for Kalash), 2026-11-07

**Overall: about 97 % done** (update 18:40: I-17 merged board implementation gate PASS; A5, A6, A7, A9 closed; I-16 PASS).

**Board run: PASS.** You reported "Board shows PASS". The bitstream is `NOC_PQATTEST.runs_merged/merged_board/pq_merged_board_top.bit`, sha256 d738b12b…67e3. The record is `reports/HARDWARE_RUN_20261107.md`.

**What is on the board:**
- the merged NoC + PQ-Attest SoC;
- two real PicoRV32 tiles: tile 3 is attested, tile 0 is never authorized;
- demo firmware that prints "T3 PASS" and "T0 REFUSED".

## Done ✅

| Area | What | Evidence |
|---|---|---|
| Intake | RISC-V zip imported, every claim re-tested, review plan | aae60b47, `docs/proposals/RISCV_TAKEOVER_PLAN_20261106.md` |
| A1 | Adapter double capture fixed | 71178d5a; mutant killed (I-14) |
| A2 / A4 | Conformance 1,000 transactions; random latency 1,000 / 1,000 seeds | scratch (legacy benches) |
| A3 | Bus errors: poison 0xBADB_E00x, IRQ 3, STATUS latch | I-13 / I-14 + mutants |
| AD-1 / AD-4 / R-D8 | Decoder: one access per transaction; unmapped access no longer hangs; IMEM read-only | 2222fc86 |
| R-D9 | `ENABLE_DIV` (`remu` trap found) | a8978f3a |
| A6 | Synchronous reset; TILE_ID; decode table T = 0..15 (18/18, scratch) | 6755b70a |
| A7 | IMEM port B; 16 KB in MEMORY_MAP.h / link.ld; memtest: all 17 memory tests passed (scratch) | a59c6b2d + the memtest note below |
| B1 – B5 | Bridge, `cpu_tile_noc`, measurement reader, STATUS map + `status_regs.h`, protocol checker | I-13 / I-14 PASS |
| B6 | Merged co-simulation with the real tiles, 10/10 plus a word-order control | **I-15 PASS** (3e860bd4) |
| B7 | Tile OOC synthesis: 2,938 LUT, WNS +7.903; DRC reset issue fixed | 6ff0d713 |
| Firmware | `scripts/rv32_asm.py` (RV32I assembler, no GCC); `demo_fw.S`; `memtest.S` | I-14 `tb_demo_fw` 9/9 |
| R-4 merge | Merged list (70 files); bitstream with 34,987 LUT (≤ 47,550), WNS +0.237, WHS +0.035 | 16f2d63c |
| Project | `merged_project_update.tcl`, tested on a project copy: GUI-path simulation 10/10 | ef9ab31d |
| Harness | Increments I-13, I-14, I-15 all PASS; 6 RISC-V mutant kinds with negative tests (142 OK) | gate reports in `reports/` |
| Questionnaire | For the RISC-V lane: 33 questions | `docs/handoff/RISCV_LANE_QUESTIONNAIRE_20261107.md` |

**Memtest note:**
- The first scratch run passed all 17 memory tests (0x600D0011), but MT_LED failed: the bench sampled the LEDs too early.
- The bench is fixed (count unchanged). Re-run: **4/4 PASS**.

## Closed after the first version of this report

- **I-16 PASS** (`reports/I16_GATE_20261107.md`, 9/9):
  - A6 decode table, 18 checks;
  - A7 memtest, 4 checks;
  - A5 `tb_two_programs`, 9 checks;
  - A5 adapter assertions, with every adapter bench re-run.
- **A9:** OOC post-route 2,881 LUT, WNS +4.909, WHS +0.038, 0 latches / loops / multi-driven (f91b88f6).
- **I-17 PASS:** the merged board top now has registered harness evidence (`reports/I17_GATE_20261107.md`):
  - 34,987 LUT, WNS +0.237, WHS +0.035;
  - MMCM and firmware proofs;
  - gate negative tests 4/4.
- **RISC-V lane A1 reply:** `docs/handoff/RISCV_LANE_A1_RESPONSE_20261107.md`.

## Left ⬜ (about 3 %)

| Item | What is left | Blocked by |
|---|---|---|
| Board details | Itemised LED, UART and revoke / re-attest observations for the hardware record | your report |
| A8 firmware v2 | Polling limit, "REFUSED OK", PASS-first lines, revoke → trap demo, `rdcycle`. Then rebuild the bitstream (the boot stub stays fixed, so APPROVED_MEAS is unchanged). | held until you want a new board image |
| C firmware | Needs the GCC download (decision R-D2) | your approval + the RISC-V lane's answer to Q3.1 |
| Questionnaire answers | Fold the RISC-V lane's answers into the docs | their reply |
| Later | Research paper, GDSII (college Cadence) | your call |

**Status:**
- HARDWARE_VALIDATED = YES (demo PASS, your report; details pending).
- SOC_INTEGRATION_COMPLETE = NO (your decision).
- FORMAL_PROOF = NO.

**Resume:** read this file, then `reports/RISCV_LANE_COMPLETION_20261107.md`, then `reports/OVERNIGHT_20261107.md`.
