# Detached build worker: end-to-end test, 2026-11-11 (not a harness increment; tool acceptance)

Route tested = the owner's route: a Vivado session (batch, on a short-path copy of NOC_PQATTEST.xpr, MG_ROOT set) sources
`scripts/merged_project_update.tcl`, calls `merged_build`, later `merged_result`.

| Step | Observed |
|---|---|
| Session 1 environment | Vivado's PYTHONHOME present (the condition that broke I-25 run 132805) |
| Project update | `merged sets ready ... files added/removed now: 1 1` (v1 firmware image replaced by demo_fw_v2.hex) |
| `merged_build` | `MERGED BUILD STARTED worker=21988`; session returned at once |
| `merged_result` while building | `MERGED BUILD RUNNING` |
| Worker | both profile checkers PASS; release flow ran alone; gate PASS before the image was written; `done.txt` = exit 0; lock removed |
| Result | `release_result.json`: gate PASS, LUT 34,952, WNS +0.12, WHS +0.009, source manifest re-validated (no drift), 0 critical warnings |
| Session 2 | re-source: `files added/removed now: 0 0`; `MERGED RELEASE PASS: LUT 34952, WNS 0.12, WHS 0.009; SHA256 7b83a07f03cd18d7ed440659f626b4774ad52a732d2a1449f77f33c0832935cd` |

The image hash differs from the I-25 harness build (c2a3ef62...) because a bitstream embeds its build time; sources, LUT and timing are identical.
Previous `merged_board` folder was moved to `merged_board_prev_<time>`, not deleted. HARDWARE_VALIDATED=NO.
