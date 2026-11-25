# Merge prep, 2026-11-06: skeleton ready for the RISC-V package (NOT evidence, NOT registered)

- **Commit base:** 7bc80b25 (merge-prep files), I-10 PASS 59fc673f.
- **Status:** HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO (stub CPUs), FORMAL_PROOF=NO.

## What exists

| File | Role |
|---|---|
| `rtl/dual_lane/merged/cpu_tile_noc_stub.sv` | stand-in for the RISC-V lane's `cpu_tile_noc` (brief B2 ports; bridge rules of M-F1 rev 8 sec. 3 / 5; scripted write / read-back; 64-byte measurement image) |
| `rtl/dual_lane/merged/pq_soc_merged_core.sv` | I-9 subsystem (MEM_EXT = 1, 16 KB BRAM, K3_IMEM_LEN = 64, NI_SLOT_TIMEOUT 8192 > BRIDGE_TIMEOUT 4096, CPU_TILES 3 + 0); CPU tiles through `CPU_TILE_MODULE`; attestation start held until tile 3's measurement is valid |
| `rtl/dual_lane/merged/tb_merged_skeleton.sv` | smoke bench, 7 checks |
| `synth/merged/pq_merged_board_top.sv`, `pq_merged_board_arty.xdc` | Arty board top (D5 front end + UART TX, led0_g); pins checked against the Digilent master XDC |
| `scripts/make_merged_sources.py` | merged source list with a FILL IN block for the RISC-V files; preflight: files exist, no variant + original, no duplicate modules |
| `scripts/merged_bitstream_flow.tcl` | the registered S4 bitstream flow, merged source table |
| `scripts/merged_project_update.tcl` | `.xpr` backup + `dl_merged_src` / `dl_merged_xdc` / `dl_merged_smoke` sets; `merged_sim`, `merged_build` |
| `scripts/merged_provision.py` | approved measurement from the real first 64 IMEM bytes (self-check reproduces vectors/d2_k3_64 row 0) |
| `docs/handoff/BOARD_BRINGUP_CHECKLIST_MERGED.md` | board run gates, steps, expected LEDs, result template |

## What was run (scratch / prep, not registered)

| Check | Result |
|---|---|
| Smoke bench (XSim, stub CPUs) | **7 / 7 PASS**, no `Error:` line: expected response with the 64-byte IMEM, GRANT at 1,252 cycles, CPU A 3 BRAM write / read-back rounds through the NoC, CPU B refused locally (no gate fault, never authorized), REVOKE stops commits. Re-run after the enum-cast cleanup: 7 / 7 |
| Board top elaboration (unisims) | clean |
| Skeleton bitstream, S4 flow (`merged_bitstream_flow.tcl`, run alone) | **LUT 29,420, FF 20,793, BRAM 4 tiles, WNS +0.337 ns, WHS +0.020 ns**, TNS / THS 0, 0 unrouted nets, 0 errors. Bitstream built |
| `merged_project_update.tcl` on a project copy (`vivado_sim/_mtest`) | backup made; 58-file source set, XDC set and smoke simset added; `sources_1` untouched; project-mode compile + elaborate + simulate PASS (7 / 7) once `dl_merged_smoke` is the active simset (what `merged_sim` does) |

## Reading the numbers

- The stub CPUs are a few hundred LUT. The real `cpu_tile_noc` x 2 (RV32 core, IMEM / DMEM BRAM, bridge, status) will
  add to the 29,420. The D4 merged ceiling is 52,000, so there is about 22.5k LUT for the two CPU tiles before the
  ceiling (not a measurement of the CPU tiles).
- WNS +0.337 ns on this board top is better than p7_board's +0.017 ns, but placement changes once the real CPUs are
  in: re-measure. A timing FAIL is a hard stop.
- The board top trims logic (constant secrets). Quote area from an accurate-area merged top (contract sec. 10), not
  from this build.

## Tomorrow, when the RISC-V package arrives

1. Check the package (isolated copy, read scripts first, re-run its claims).
2. Fill the FILL IN block in `scripts/make_merged_sources.py`; run it (preflight PASS).
3. Re-map the two CPU instances in `pq_soc_merged_core.sv` to the real port names (README port table).
4. `scripts/merged_provision.py --words <firmware>` -> paste APPROVED_MEAS / image into the board top.
5. Register the merged jobs (contract sec. 11: bridge co-sim, demo), freeze their counts, run, gate.
6. Give Kalash `merged_project_update.tcl` -> `merged_build`; timing / area gates; then the board checklist.
