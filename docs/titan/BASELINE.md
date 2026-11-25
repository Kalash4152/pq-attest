# TITAN baseline

Pinned B0: b9e41c383473802267c8c3d604e329770d708ab5, tag titan-base-20261119. Clean checkout on kalash/titan-rtl on 20 November 2026 IST.

Measured revision-10 historical FPGA baseline from reports/R10_OWNER_GUI_BUILD_20261115.md: 39,962 LUT, 29,187 FF, 20 BRAM36, WNS +0.182 ns, WHS +0.007 ns, Vivado 2024.1, post-route, xc7a100tcsg324-1, 20 ns. I-27-R2 reported matched secure read/write at 32/32 cycles. These are B0 results, not measurements for TITAN.

The Claude outputs ZIP and repo-aligned copy share the stage plan and HDL skeletons. The repo-aligned copy adds 07_REPO_RULES_ALIGNMENT.md and clarifies the bench evidence format. Use the existing dual_lane.py scheduler and expected-count rules. No interface change in Stage 0.

HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.
