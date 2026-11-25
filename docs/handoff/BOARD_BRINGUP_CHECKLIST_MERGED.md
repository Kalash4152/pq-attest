# Board bring-up checklist: merged SoC on the Arty A7-100T

For Kalash's first hardware run, after the RISC-V and Engineer 4 final packages are merged. Until you record a result
here, the project stays `HARDWARE_VALIDATED=NO`.

## A. Do not go to the board until all of these are true

| # | Gate | Where it shows |
|---|---|---|
| A1 | Merged design registered and its gate report says PASS (contract sec. 11: `i9_bridge_cosim`, `i9_demo`) | `reports/I*_GATE_*.md` |
| A2 | Merged bitstream built with the S4 flow: **WNS >= 0, WHS >= 0**, 0 route / DRC errors | `merged_build` prints `BUILT, TIMING MET` |
| A3 | LUT within the D4 merged ceiling (52,000); the subsystem alone stays <= 47,550 | `NOC_PQATTEST.runs_merged/merged_board/utilization.rpt` |
| A4 | `APPROVED_MEAS` recomputed from the **real** first 64 IMEM bytes (`scripts/merged_provision.py --words <fw hex>`) | header of `synth/merged/pq_merged_board_top.sv` |
| A5 | LED / UART map re-checked against the real `cpu_tile_noc` `gpio_o` bits (the table in C assumes the stub's bits) | `pq_merged_board_top.sv`, "outputs" block |

A timing FAIL is a hard stop: do not load that bitstream.

## B. What you need

- B1. Arty A7-100T (xc7a100tcsg324-1) and its micro-USB cable (JTAG and USB-UART on one cable).
- B2. Pins used. All of them match the Digilent `Arty-A7-100-Master.xdc`; led0_g and uart_rxd_out were checked on
  2026-11-06.

  | Function | Port | Pin |
  |---|---|---|
  | 100 MHz clock | CLK100MHZ | E3 |
  | Reset | btn[0] | D9 |
  | Re-attest | btn[1] | C9 |
  | Revoke | btn[2] | B9 |
  | UART source | sw[0] | A8 |
  | Status LEDs | led[3:0] | T10, T9, J5, H5 |
  | CPU B refused | led0_r | G6 |
  | CPU A error | led0_g | F6 |
  | UART to host | uart_rxd_out | D10 |

- B3. A serial terminal on the board's COM port. **Baud rate and frame format come from the RISC-V package** (fill in
  here: ______). The stub UART is idle, so there is no text until the real CPU is in.
- B4. Vivado Hardware Manager: Open Target -> Auto Connect -> Program Device with
  `NOC_PQATTEST.runs_merged/merged_board/pq_merged_board_top.bit`.

## C. Expected behaviour (50 MHz; one attestation starts automatically about 20 us after reset)

| Step | Action | Expected | If not |
|---|---|---|---|
| C1 | Program the bitstream | **led[3]** blinks about 1.5 Hz (heartbeat: the clock and MMCM run) | no blink: check that the bitstream loaded (DONE LED) and the 100 MHz clock pin |
| C2 | Wait < 1 s | **led[0] on**: tile 3 authorized (GRANT after about 1.25k cycles = 25 us) | led[1] on instead: attestation failed. Check A4 (approved measurement vs the real IMEM bytes), the K-3 lengths (config 16 / IMEM 64), and the demo keys |
| C3 | Wait < 1 s | **led[2] on**: CPU A wrote to the tile-2 BRAM through the NoC and read the same data back | led0_g on: CPU A saw an error (err response, abort or timeout) |
| C4 | Look at led0_r | **led0_r on**: CPU B (tile 0, never attested) refused its memory access locally | off: CPU B never tried, or the refusal path is broken. Record it |
| C5 | Press **btn[2]** (revoke) | **led[0] off**; CPU A stops (no new commits). led[2] keeps its last value | led[0] stays on: revoke not taking effect. Record it and stop |
| C6 | Press **btn[1]** (re-attest) | **led[0] on** again, and CPU A resumes | led[1] on: re-attestation failed |
| C7 | Press **btn[0]** (reset) | everything off, then C2 to C4 repeat | |
| C8 | UART, sw[0] = 0 then 1 | CPU A, then CPU B, prints its PASS / FAIL lines (real CPU only) | no text: check the baud rate (B3), the COM port, and sw[0] |

## D. Known limits (say them when you show the demo)

- **Demo secrets:** the root secret, keys and nonce are fixed constants and readable from the bitstream. There is no TRNG
  nonce and no protected key storage. This shows the protocol on hardware; it is not a secure deployment.
- **Approved measurement:** valid only for the exact firmware image used in A4. Any firmware change means a new
  `APPROVED_MEAS`; otherwise C2 fails, which is the intended behaviour.
- **Area:** a board top with constant secrets trims logic. Quote area from the accurate-area build (p7_soc / N-13 style),
  not from this bitstream.

## E. Record the result (this is what changes HARDWARE_VALIDATED)

Copy this block into `reports/BOARD_RUN_<date>.md` and fill it in:

```
Board run, date:          Board serial / revision:
Bitstream: NOC_PQATTEST.runs_merged/merged_board/pq_merged_board_top.bit  SHA-256:
Commit:                   Firmware image + SHA-256:
C1 heartbeat     PASS / FAIL      C5 revoke        PASS / FAIL
C2 grant         PASS / FAIL      C6 re-attest     PASS / FAIL
C3 CPU A R/W     PASS / FAIL      C7 reset         PASS / FAIL
C4 CPU B refused PASS / FAIL      C8 UART text     PASS / FAIL (paste lines)
Photos / video of the LEDs:
Notes:
```

Only when every row is PASS can the report say `HARDWARE_VALIDATED=YES (demo board run, demo secrets)`, with exactly that
qualifier. Formal proof stays NO.
