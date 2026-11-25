# PQ-Attest SoC: team package, 2026-11-07

**What this is.** The merged system-on-chip:
- a 3×2 network-on-chip (NoC);
- post-quantum attestation (SHA-3 / KMAC, KDF, measurement, RoT verifier, authenticated L2 link);
- two RISC-V CPU tiles (PicoRV32), on a Xilinx Artix-7 (xc7a100tcsg324-1, Arty A7-100T) at 50 MHz.

The package contains the RTL, the board build's reports, the verification gate reports, the firmware and the scripts to rebuild everything.

Status:
- HARDWARE_VALIDATED = YES: demo PASS on the board, Kalash's report; itemised observations pending.
- SOC_INTEGRATION_COMPLETE = NO: final sign-off pending.
- FORMAL_PROOF = NO.

## 1. Results (latest build, 2026-11-07 20:13)

| Metric | Value | Limit |
|---|---|---|
| LUT | 34,987 (55 % of the device) | D4 hard stop 47,550 |
| FF / BRAM36 / DSP | 25,276 / 20 / 0 | |
| WNS / WHS (post-route, setup / hold) | +0.237 ns / +0.035 ns | ≥ 0: **met** |
| Timing | "All user specified timing constraints are met" | |
| Errors / critical warnings | 0 / 0 | |
| Bitstream | `build/pq_merged_board_top.bit`, sha256 fa0b3361…cd51 (full hash in `SHA256SUMS.txt`) | |

**Where the area goes (post-route):**

| Block | LUT |
|---|---|
| NoC mesh | 10,311 |
| L2 authenticated link | 6,591 |
| PQ-Attest endpoint | 6,586 |
| RoT verifier | 5,804 |
| RISC-V tile 3 | 2,696 |
| RISC-V tile 0 | 2,560 |
| NIs and gates | about 370 |

## 2. What the demo does

| Step | What happens |
|---|---|
| Measure | Both CPUs boot `firmware/demo_fw.S`. Tile 3's first 64 instruction bytes (a fixed boot stub) are measured and sent to the RoT. |
| Attest | The RoT attests tile 3 with KMAC tags and grants it. Tile 0 is never authorized. |
| Tile 3 | Writes 0xC0DE5A5A to the tile-2 memory through the NoC, reads it back, prints **"T3 PASS"** on UART, LED 0001. |
| Tile 0 | Tries the same; its bridge refuses locally (no packet enters the NoC). The CPU receives a poison value and prints **"T0 REFUSED"**, LED 0010. |
| Revoke | Button 2 revokes tile 3; button 1 re-attests. |

**Board:**
- UART 115,200 8N1. sw[0] selects which CPU's UART you see.
- btn[0] = reset (the lines print once per reset).

## 3. What was built and how it was verified

All verification runs in Vivado XSim 2024.1 through the project's harness (`scripts/dual_lane.py`):
- every bench's check count is frozen before its first run;
- mutant controls prove that the benches catch real faults;
- failed runs stay on record, and none was relabelled.

| Part | Built | Registered evidence |
|---|---|---|
| NoC: router, NI, mesh, credits, XY routing, virtual channels | Lane 1 | Increments I-1 … I-12 |
| PQ-Attest: SHA-3, KMAC, KDF, measurement, endpoint, verifier, L2 auth, gates | Lane 1 | I-1 … I-12; Engineer 4 suite 389 / 15 |
| RISC-V tile: PicoRV32 + adapter, decoder, STATUS, UART, GPIO, memories | RISC-V lane; fixed and completed by Lane 1 | I-13, I-14, I-16 |
| NoC bridge, CPU tile wrapper, measurement reader, protocol checker | Lane 1 | I-13, I-14 |
| Merged SoC co-simulation (both tiles + NoC + attestation) | Lane 1 | I-15, I-16 (10 / 10) |
| Merged board implementation gate (timing, route, DRC, MMCM clock proof, firmware-in-netlist proof) | Lane 1 | I-17 |
| Board run | Kalash | demo PASS |

The gate reports, one per increment, are in `reports/`. `reports/RISCV_STATUS_20261107.md` is the item-by-item status.

## 4. Package contents

| Folder | Contents |
|---|---|
| `rtl/` | The exact 70-file source list of the merged board build (`scripts/merged_bitstream_sources.tcl` order), with the original repository paths |
| `constraints/` | Board XDC (pins, clock, I/O) |
| `firmware/` | `demo_fw.S` / `.hex`, `memtest.S` / `.hex`, `status_regs.h`, the RV32I assembler `rv32_asm.py`, `hex_to_svh.py` |
| `sim/` | Merged co-simulation bench and the RISC-V unit and tile benches |
| `build/` | Bitstream, utilization (flat + hierarchical), timing summary, result |
| `reports/` | Gate reports I-13 … I-17, merged build record, hardware run record, status and completion checklists, tile OOC synthesis / implementation reports (B7, A9) |
| `scripts/` | Project-update Tcl, merged bitstream flow, source-list builder, provisioning helper, merged gate scripts |
| `docs/` | Contract M-F1 rev 8 draft, takeover plan, RISC-V lane questionnaire and A1 response, CPU tile README |

## 5. How to rebuild or re-check (Vivado 2024.1)

In the Vivado Tcl console, with the full repository's `NOC_PQATTEST.xpr` open:

```tcl
source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/merged_project_update.tcl
merged_sim      ;# merged co-simulation: expect RESULT : PASS (10/10), stops at ~1.13 ms
merged_build    ;# bitstream in its own window (~1 h); then: merged_result -> BUILT, TIMING MET
```

## 6. What is left

| Item | Type | Owner |
|---|---|---|
| Contract sec. 8: may the CPU request attestation? Today only the RoT / button starts it, and CPU `attest_req_o` is unconnected. Proposal: "CPU may request, RoT decides". About 10 lines of RTL + re-run. | RTL, policy decision | Kalash |
| Merged-level checks still missing from plan R4.3: error response, revoke while a request is in flight, port busy during attestation, CPU A refused after revoke (needs firmware v2) | Verification | Lane 1 |
| Firmware v2: polling limit, "REFUSED OK", revoke-trap demo, cycle counter | Software | Lane 1 (held until a new board image is wanted) |
| C firmware: needs the GCC download (decision R-D2) | Software | Kalash approval + RISC-V lane answer |
| Contract note: final values for sec. 7 / 8 / 9 `[OPEN: from package]` items | Documentation | Lane 1 |
| Itemised board observations (LEDs, UART text, revoke / re-attest) for the hardware record | Evidence | Kalash |
| Paper measurements: insecure baseline with the same flow; latency on the final design | Measurement | Lane 1 |
| ASIC / GDSII on the college Cadence flow (step A0: tools, PDK, memory compiler) | Next phase | Team |

**Out of scope by decision:**
- TRNG (the demo uses a fixed nonce, DEMO secrets only);
- formal proof;
- side-channel evaluation;
- asymmetric PQC.
