# Changelog

High-level milestones. Every gate has a report in `reports/` or `docs/titan/stage_reports/` (titan branch).

| Date (2026) | Milestone |
|---|---|
| Sep | Crypto lane stages 1–7 (SHA-3, KMAC-128, KDF, measurement, attestation tag); NoC router/NI baseline |
| Oct 8–23 | Dual-lane evidence harness (`dual_lane.py`); M-F1 rev 6/7 interface freeze; P7 control-plane-only MAC with a shared L2 engine; ingress, revocation and P&R checkpoint (S1) |
| Nov 2 | S3 area package: shared tile-3 Keccak, select replication, one-block SHA-3 (−6.5k LUT) |
| Nov 5 | S4 area package with mesh-split synthesis: N-13 secure 32,708 LUT (−14 %), WNS +0.275 ns |
| Nov 7 | Merged SoC with two PicoRV32 tiles and firmware: 34,987 LUT, timing met |
| Nov 12 | RC1 tag `rtl-rc1-20261112` |
| Nov 14–15 | Revision 10 (whole-IMEM measurement, firmware v3): 39,962 LUT, WNS +0.182 ns; owner GUI build; release image hash recorded |
| Nov 19–21 | TITAN research extension started (`titan` branch): S0–S3, S4R epoch tracker, S5R request stamp (see the titan branch) |
