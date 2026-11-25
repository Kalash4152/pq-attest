# Engineer 4 package intake, 2026-11-05: verification/ tree delivered and re-run, 224/224 and 15/15 reproduced

- **Package:** `pqattestfinal.zip` (Downloads, 2026-11-05 23:35), 42,043,856 bytes,
  SHA-256 `4bd4cb4f122fa8adf291b7bf49cc3b95a9e5d0d1007892a70a401c0e21b36218`. 1,372 entries; a full working-copy snapshot
  (E4 git HEAD b62b78d) plus `verification/` (70 files; tree digest
  `8d57d3a4c279b633652a384e0251c82c348c4c20b7c93f662e708f2edae5952d`, sorted path + SHA-256 list, `__pycache__` excluded).
- **Handling:** extracted read-only into the session scratch (no unsafe paths); nothing from the package written into this
  repository. Python scripts read before running: they start only Python, pytest and `git rev-parse` inside the package copy;
  no network or delete calls. pytest 9.2.0 installed for the user Python (Kalash approved 2026-11-05).
- **Step 8 handoff:** `reports/E4_P7_STEP8_FINAL_HANDOFF.md` in the package is byte-identical to the one already checked
  (reports/E4_STEP8_HANDOFF_CHECK_20261105.md, commit 842484b0), SHA-256 `3ace7ed4...4615`.

## Re-run here (Python 3.13.17, win32, package copy as working directory)

| Claim in the handoff | Re-run result |
|---|---|
| Full pytest suite 224 / 224 | `python -m pytest verification`: **224 passed** (19.3 s), exit 0 |
| Step 7 regression runner 15 / 15 stages | `python verification/p7_regression.py --full`: **15 / 15 PASS**, exit 0 (incl. 57 / 57 traced requirements, 16 / 16 Python mutants, 20 integration flows, artifact validation) |

## RTL snapshot against this repository (content compare, no code run)

- `NOC_PQATTEST.srcs/sources_1/new`: 49 / 49 identical. `NOC_PQATTEST.srcs/sim_1/new`: 29 / 29 identical.
- `rtl/dual_lane`: 30 / 31 identical. **`pq_noc_subsystem_p7.sv` differs:** the package has the I-6 version, without the I-7
  bench hooks (TBI ep_sub / ep_ctl / ep_words, `ertctl_x` / `ertdata_x`, `ni_rx_*` substitution; commit 38ea97a9). Those
  hooks are inert with TB_INJECT = 0, so the release logic is the same, but the file is not byte-identical: the E4
  "38 / 38 identical" claim is against E4's own baseline, not against the release identity of this file.
- No package file is newer than the I-9 variants; E4 did not see I-9 (`*_i9.sv`) or I-10.

## Classification

- What E4 delivers is **Python model checking**: packet / security models, differential vectors, Python mutants, traceability,
  and reconciliation against XSim logs that **we** produced (E4_P7_XSIM_20261103). It is reference-checked and
  mutation-tested **in Python**; it adds no new RTL simulation, synthesis or hardware result.
- Reproduced: YES (both claims). Formal: NO. Hardware: NO. Not yet a harness job (no `scripts/dual_lane.py` record).

## Open

- Import `verification/` into this repository (text only) and register a Python job (`p7_regression.py --full`, marker
  `REGRESSION RESULT: PASS`): needs Kalash's go.
- Point the E4 RTL parser at the release / I-9 sources (the package parsed the I-6 subsystem file).
