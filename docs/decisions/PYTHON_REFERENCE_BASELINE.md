# Teammate Python reference baseline — Revision 4, I-1

## 1. Pinned authority and immutable extraction

PQ behavior is governed by `Pq_Attest_final.zip`, SHA-256 `047bb5a981050f11a572a60e850f7c7511ff5d636f7903c6a8d239891003c6a0`; the live hash matched. Historical inputs only: `PQ_Attest (2).zip` = `62abec084e61a9900a829f1d0d1be1f3c71558c972ce1358477795e2e3fb67`; `(3).zip` = `538cc7764d5119ac63f81f160d9815b212c3c0998d80b7a36f535ca71dac48ea`.

Exactly 15 Python files were extracted with their original bytes and internal `PQ_Attest/` root into `software/pq_attest_final/`. RTL and cached bytecode were excluded. Each extracted file has the Windows read-only attribute. The member SHA-256 table is recorded in `dual_lane_config.json` under `python_reference.members`. Every audit rechecks the ZIP, extraction and manifest before and after execution.

## 2. Executable verification and repo-copy reconciliation

`scripts/python_reference_audit.py` runs the eight suites declared by the immutable `run_all_tests.py` in separate disposable copies, with a 120-second timeout per suite. It parses per-test output and the positive terminal marker; printed FAIL is rejected even when the process exits zero. The original unbounded aggregate runner is inspected, not used as the verdict oracle.

The audit also checks the ZIP's KMAC128 using [NIST samples 1–3](https://csrc.nist.gov/csrc/media/projects/cryptographic-standards-and-guidelines/documents/examples/kmac_samples.pdf) and compares reference SHA3 against `hashlib` for lengths 0, 3, 135, 136, 137, 271, 272, 273 and 512. `python_kats.json` records exact expected/actual bytes. Any mismatch blocks PQ-1; extracted sources are never patched.

The repo KMAC copy is supplementary. `kmac_source.diff` records its complete textual difference from the ZIP copy. `kmac_comparison.json` compares the same external KATs and 24 cases (outputs 16/32 bytes, messages 0/4/167/168/169/400, empty/`PQ-ATTEST-AUTH` customization). Source differences alone are not semantic failures; differing bytes must be reported with the ZIP governing.

Actual results live in the new scheduler run's `python_ref/` directory: `suite.json`, eight raw stdout/stderr/process records, `python_kats.json`, `kmac_comparison.json`, `reference_manifest.json` and `audit.json`. This document does not predeclare PASS. The runner's positive marker is emitted only after all required Python checks succeed.

## 3. Contract and qualification boundary

V6 is documented in `docs/verification/PYTHON_RTL_CONTRACT_MATRIX.md`. The system uses a 32-byte tile key; unchanged teammate examples retain their 16-byte profile. Separate V8 jobs, ZIP-backed V7 adapters, all 776-bit RTL comparisons and V10 reference/policy verdicts belong to I-2. `PYTHON_RTL_COMPATIBILITY=NOT_RUN` at I-1.

Existing `s8_golden.py`, `full_chain_golden.py`, `l2_golden.py` and their vectors are preserved as the previous supplementary identity. They cannot accept PQ-1 under Revision 4. No existing demo PASS is relabeled as a ZIP-reference PASS. Limitations L-1 through L-4 are defined in the contract matrix and must accompany later reports.

## 4. Executed I-1 Python result

Scheduler evidence: `reports/dual_lane_10_20261008_191722_1819097c/python_ref/`. V1/V2 PASS; eight of eight parsed suites PASS; three KMAC external samples and nine SHA3 boundary lengths PASS; all 24 repo/ZIP cross cases match. V6 matrix is documented, with source-level MATCH/ADAPTER rows. V7–V10 and Python-to-RTL requalification remain NOT_RUN. The audit job is PASS_FRESH; package acceptance remains 0/10. A later run must match the complete input identity before reuse.
