# Kalash's release run in the project, 2026-11-05: ALL VERIFIED (36/36) + three bitstreams built, timing met

- Command: `source scripts/run_release_all.tcl` in the Vivado GUI (NOC_PQATTEST.xpr, S4 update installed). Run by Kalash; benches 10:54, bitstreams 12:13 / 13:22 / 14:10 IST.
- STEP 3: 36 OK, 0 BAD of 36 (release_project_sims.txt).
- STEP 4 (registered S4 flow, scripts/p7_bitstream_flow.tcl): 0 CRITICAL WARNING / ERROR lines in each vivado.log; 0 register pins without a clock.

| Bitstream | LUT | FF | WNS ns | WHS ns |
|---|---|---|---|---|
| p7_soc (pq_p7_soc_area_top) | 32,118 | 29,168 | +0.184 | +0.048 |
| p7_area (pq_p7_area_top) | 32,830 | 30,847 | +0.091 | +0.021 |
| p7_board (pq_p7_board_top) | 29,319 | 20,425 | +0.017 | +0.012 |

- Identical to the session builds of 2026-11-05 night (reports/s4_bitstreams_20261105): the flow is reproducible.
- .bit files stay on disk (NOC_PQATTEST.runs_s4/, gitignored); hashes in bitstreams_sha256.txt.
- Project run, not registered harness evidence (the registered S4 evidence is reports/S4_GATE_20261105_REV1.md).
- HARDWARE_VALIDATED=NO (no board run), SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.
