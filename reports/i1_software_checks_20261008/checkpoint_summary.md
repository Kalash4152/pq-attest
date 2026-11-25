# I-1 checkpoint

State: PREPARED; 13 fresh Vivado gates NOT_RUN.

Commits:
- 2fd1138 Kalash Bheda <kkalash.bheda@gmail.com> I-1: enforce source guards and prepare bounded increment launcher
- 858c95d Kalash Bheda <kkalash.bheda@gmail.com> I-1: pin teammate Python reference and document RTL contract
- 8a82ab8 Kalash Bheda <kkalash.bheda@gmail.com> I-1: restore baseline contracts and preserve recovery copies

```text
NOC_PACKAGES_ACCEPTED=0/5
PQ_PACKAGES_ACCEPTED=0/5
DUAL_LANE_STATUS=BLOCKED
SOURCE_IDENTITY=dee22ceec8dc09e421f6a43e93890ffb21a391cb244022a314d179742a9d25c8
PYTHON_REFERENCE_ZIP=Pq_Attest_final.zip
PYTHON_REFERENCE_SHA256=047bb5a981050f11a572a60e850f7c7511ff5d636f7903c6a8d239891003c6a0
TILE_KEY_BYTES=32
PYTHON_RTL_COMPATIBILITY=NOT_RUN
EVIDENCE_DIR=C:\vivado_verilog_proj\NOC_PQATTEST\reports\dual_lane_10_20261008_192951_74c52288
HARDWARE_VALIDATED=NO
SOC_INTEGRATION_COMPLETE=NO
```

45 automation tests PASS; 8/8 teammate suites PASS; 3 KMAC + 9 SHA3 KATs PASS; 24 repo/ZIP comparisons MATCH. 48 protected files unchanged; all 64 payload Git blobs retain their pinned bytes. Existing local edits remain preserved and are recorded in automation/I1_CHECKPOINT_2026-10-08.json.

Stop after I-1 as required by Revision 4. Kalash runs scripts/run_dual_lane_10.tcl in Vivado 2024.1; I-2 requires accepted I-1 gates.
