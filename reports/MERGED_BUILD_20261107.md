# Merged SoC build, 2026-11-07: bitstream BUILT, TIMING MET

This build uses the real RISC-V CPU tiles running the demo firmware. It is not harness-registered: it is the release S4 flow (`scripts/merged_bitstream_flow.tcl merged_board`) run in Vivado batch mode, alone. HARDWARE_VALIDATED=NO, because the board run is Kalash's.

- **Sources:** `scripts/merged_bitstream_sources.tcl` (from `make_merged_sources.py`, commit c7d8c7aa). Preflight PASS, 70 files.
- **Defines:** `PQ_MAC_ON`, `CPU_TILE_MODULE=cpu_tile_noc`, `REAL_CPU_TILE`.
- **Firmware:** `sw/riscv/demo_fw.hex` in both CPU tiles. Synthesis log: "$readmem data file 'demo_fw.hex' is read successfully".
- **Provisioning:** APPROVED_MEAS = the firmware's 64-byte boot stub (`merged_provision.py --words`). DEMO secrets only.

| Metric | Value | Bound |
|---|---|---|
| LUT | 34,987 (55.2 % of xc7a100t) | D4 hard stop 47,550: **within** |
| FF | 25,276 | |
| BRAM36 | 20 / 135 | |
| DSP | 0 | |
| WNS (post-route, setup) | **+0.237 ns** | ≥ 0: met |
| WHS (post-route, hold) | **+0.035 ns** | ≥ 0: met |
| Timing report | "All user specified timing constraints are met." | |
| Critical warnings | 0 | |

- **Per CPU tile (hierarchical, post-route):** u_cpu_a 2,696 LUT, u_cpu_b 2,560 LUT.
- **Bitstream:** `NOC_PQATTEST.runs_merged/merged_board/pq_merged_board_top.bit`, sha256 `d738b12b994776d6ab183a9691d77113e2c5f15b4e7105a394a69378e14867e3`. The binary is not committed.
- **Reports:** `docs/riscv_lane/merged_build_20261107/`.

## Verification behind this build

| Level | What passed | Notes |
|---|---|---|
| Harness I-13 / I-14 | 18 RISC-V benches, 6 mutant kills | `cpu_tile_noc`, `tb_demo_fw`, B1, B3, B5 |
| Scratch B6 co-simulation (`tb_merged_real`) | 10/10 | Same 70-file list. Measured boot stub → GRANT → "T3 PASS" over UART → BRAM 0xC0DE5A5A, 1 commit → "T0 REFUSED" with no gate fault → revoke |

## What Kalash should see on the board (Arty A7-100T)

| Indicator | Expected after power-up / reset |
|---|---|
| led[0] | on: tile 3 authorized, after the automatic attestation start |
| led[1] | off: no attestation failure |
| led[2] | on: CPU A printed "T3 PASS" |
| led[3] | blinking heartbeat |
| led0_r | on: CPU B refused, printed "T0 REFUSED" |
| led0_g | off: no CPU printed FAIL |
| UART | 115,200 8N1. sw[0] = 0 shows "T3 PASS"; sw[0] = 1 shows "T0 REFUSED". Each line is printed once after reset; press btn[0] to reset and print again. |
| btn[2] | revoke: led[0] goes off |
| btn[1] | re-attest: led[0] comes back |

**UART caveat:** the text is printed once, right after reset. Open the terminal before you press reset.

## Rebuild 2026-11-07 20:13 (fixed merged_build, detached)

- Result: LUT 34,987, FF 25,276, WNS +0.237 ns, WHS +0.035 ns. "All user specified timing constraints are met." 0 errors and 0 critical warnings.
- Bitstream: `NOC_PQATTEST.runs_merged/merged_board/pq_merged_board_top.bit`, sha256 `fa0b33619535b9eff83ec6420a39b1176cc76fba45a3e6ce9a2b61835193cd51`.
- The XDC now carries explicit 0 ns I/O delays (I-17) and the adapter carries the A5 assertions (simulation only), so the hash differs from d738b12b…. Timing is identical.
- The d738b12b… image (board-tested) was deleted by the old `merged_build`. It can be rebuilt from 16f2d63c.
