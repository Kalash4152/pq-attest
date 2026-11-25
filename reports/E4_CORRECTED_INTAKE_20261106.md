# Engineer 4 corrected final package intake, 2026-11-06: ACCEPTED and integrated (I-12 PASS)

- **Package:** `E4_P7_CORRECTED_HANDOFF_FINAL_20261106.zip`: 850,269 bytes, 226 entries, SHA-256
  `cf9d925688905ad77017973a723512451695c40f1b72959e6e9234cb447fdd1c`. It matches his `.sha256` sidecar and external manifest.
- **His git:** HEAD `78ba9dc`, base `b2511f5`, tree clean at build. Our evidence package `E4_EVIDENCE_20261106` / commit `9af9cdfe`.
- **Handling:** extracted read-only in the session scratch; new / changed scripts read first (only Python, pytest and `git`
  calls; the builder deletes only its own previous zip). Nothing from the package is executed except his test suite.
- **Status:** Python model checking, not RTL simulation, not hardware, not formal.

## What he fixed (checked)

| Request (our response + evidence cover) | Result |
|---|---|
| Step 12 rebuilt from registered evidence | **Accepted.** Round trip 1,204 cycles (NONE) and 1,206 (LOADED max) from the I-5 table (our gate notes 1,205-1,206 under load); C4 486 (bound 1,500); P 269, Q 792, J 128 with an applicability table (J not double-counted); 28-cycle service path labelled. Worst legitimate wait 1,234 cycles (1,720 with C4 max); recommends **keeping BRIDGE_TIMEOUT = 4,096** (margin 1.5x even on the 2,734-cycle contract worst case) |
| Step 13: 2 slots, I-9 semantics | **Accepted.** 2 slots; bench timeout 600 vs merged NI_SLOT_TIMEOUT 8,192 kept distinct and labelled |
| Step 18: JSON only, real files, implemented / covered / not killable | **Accepted** (reconciliation report + regenerated JSON) |
| D2 file names | **Fixed.** His file is now `vectors/e4_d2_measurements.*`; his copy of our `vectors/d2_k3_64.*` is byte-identical to the registered one (`0a96d464...`, `f58e0344...`) |
| Commit his work | Done (`78ba9dc`) |
| Counts | 389 / 15: changed from 387, announced in his report; registered as a new job (v3), not edited |

## Re-run here

- **Our live sources, staged** (`scripts/e4_verification_v3.py`): **389 / 389 pytest, 15 / 15 regression stages**.
- **Registered:** I-12 `e4_verification_v3` PASS_FRESH (reports/I12_GATE_20261106.md).

## Minor findings (no effect on acceptance)

1. **Stale package identifiers.** `E4_P7_FINAL_CORRECTION_REPORT_20261106.md` states the archive as 850,025 bytes /
   `f7e52a23...` and the final commit as `b2511f5`. The real archive is 850,269 bytes / `cf9d9256...` and HEAD `78ba9dc`
   (per his sidecar and manifest). The report was written before the last rebuild.
2. **Stale README count.** His package `README.md` still says the frozen counts are 387 / 15.
3. **Missing test inputs.** The zip omits the six `verification/tests/sample_*.log` test inputs (his packer appears to skip
   `.log`). We kept them from his previous package (unchanged files).

## What was integrated

- `verification/` replaced with his tree, plus the six kept sample logs.
- `verification/e4_data/vectors/e4_d2_measurements.*` and his updated step reports in `verification/e4_data/reports/`.
- `scripts/e4_verification_v3.py`, its negative tests, and the I-12 registration. Commit 9b676f84.
