# Reproducing results

1. **Tools.** Vivado/XSim 2024.1 on Windows (part `xc7a100tcsg324-1`) and Python 3.13. Set the Python path in
   `docs/decisions/dual_lane_config.json` if yours differs.
2. **Generated sources.** Never edit `*_i9.sv` (or any file marked "GENERATED") by hand. Regenerate and check them:
   `python scripts/prepare_i9.py && python scripts/check_i9.py`. The other generators (`prepare_s3.py`, `prepare_s4.py`, …)
   work the same way.
3. **Evidence harness.**
   - Run `python scripts/test_dual_lane.py` (the harness self-tests).
   - Run `python scripts/dual_lane.py preflight`.
   - Run `python scripts/dual_lane.py run --select <increment>`.
   - Results land in `reports/dual_lane_10_<timestamp>_<id>/`. Accepted states are PASS_FRESH and identity-matched
     PASS_REUSED.
   - Run at most 2 XSim processes at a time; run synthesis and implementation alone.
4. **FPGA build.** `scripts/make_merged_sources.py` writes `scripts/merged_bitstream_sources.tcl`.
   `scripts/merged_bitstream_flow.tcl` runs the release flow in batch: S4 synthesis settings, mesh split, S1-PNR-DIR
   directives. Compare your result with `reports/R10_OWNER_GUI_BUILD_20261115.md`.
5. **Raw evidence.** Per-job raw logs (more than 50,000 files, more than 1 GB) are not in this repository. Gate reports
   cite each run by its ID.
