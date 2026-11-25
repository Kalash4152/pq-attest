# Engineer 4 Step 8 handoff check, 2026-11-05: report CONSISTENT with our evidence; NOT ACCEPTED as evidence (code not delivered)

- **Input:** `E4_P7_STEP8_FINAL_HANDOFF.md` (Downloads, dated 2026-11-04), filed as
  `docs/handoff/E4_P7_STEP8_FINAL_HANDOFF_20261104.md` (SHA-256 `3ace7ed4fe71e11aafdb27d81164e645ad46d05575a573e50a77d23371324615`).
- **Not received:** the `verification/` tree it describes (p7_rtl_parser.py ... p7_regression.py, 224 tests, generated JSON).
  Its links point to `C:/Users/Arnav Bhandari/PQ_Attest/`; no zip of it is in Downloads. Nothing was run.
- **Evidence class:** document review only. The 224 tests, 16 mutants, 57 requirements and 15 stages are **claimed, not
  re-run here**. Same rule as the 2026-10-29 check (`reports/E4_HANDOFF_CHECK_20261029.md`): accepted only after a re-run of
  the delivered code.

## 1. Facts checked against the repository (all MATCH)

| E4 claim | Ours | Source |
|---|---|---|
| tb_pq_full_chain_p7 21 checks; tb_i7_sec 30 | 21; 30 | scripts/release_expected.tcl (dl_s4_i7_full_chain, dl_s4_i7_sec) |
| tb_l2p7_equiv 2,425; engine 8,020 | 2,425; 8,020 | dl_s4_s3_l2p7_equiv, dl_s4_s3_l2e_engine |
| refuse_grant 12; ingress 39; i6_retry 24 | 12; 39; 24 | dl_s4_i6_p7_refuse_grant, _ingress, dl_s4_i6_retry |
| 4th BUSY fails closed, reason 9 | reason 9 = status != 1 incl. BUSY after 3 retries | docs/decisions/I6_CONTRACT.md sec. 3 |
| 0x8200_0100 rejected, fault 13 | 13 = address outside the 0x2 window | I6_CONTRACT.md sec. 3 |
| control lengths, 3 VCs, 5 freshness flits, 4 MAC flits | as brief v2 sec. 2.3 | docs/handoff/BRIEF_E4_VERIFICATION_LANE_v2_20261101.md |

The contract staleness found on 2026-10-29 (MAC_FLITS = 0, CHALLENGE = 5, self-pairs) is fixed in what the report describes.

## 2. Corrections to the report

1. **CDC claim is wrong.** Sec. 7B.2 speaks of "asynchronous crypto accelerator" handshakes and CDC. The design is single
   clock (20 ns, no CDC by rule); there is nothing asynchronous to validate. Drop the item.
2. **"Fully verified / hardware-ready" overstates.** The RTL evidence is Lane 1's XSim runs; E4's part is an independent
   Python reference that agrees with those logs (reference-checked). Wording should be "Python model agrees with the
   registered XSim results".
3. **The 16 mutants are Python-model mutants.** They show the Python suite is sensitive; they say nothing about RTL. Brief
   step 18 asks for RTL mutant proposals with expected kill signatures (not patches); that is still open.
4. **Identity is the I-8 release, not S4.** E4 reconciled `E4_P7_XSIM_20261103`. S4 (2026-11-05) adds
   `rtl/dual_lane/kmac_128_a5.sv` / `kmac_128_xp_a5.sv` in the source lists; all 54 benches re-ran on S4 with the same counts,
   so the reconciliation carries over by count, but E4's 38-file SHA-256 baseline is release-identity and needs refreshing
   if it is meant to track the current build.

## 3. Brief v2 steps (18) against the report

| Step | Status per report |
|---|---|
| 1 parse lengths / types, 2 framing, 4 authorization model, 5 artifacts, 6 evidence reader, 10 packaging | described as done |
| 7 security-matrix verdict vectors, 9 integration-demo oracle, 16 coverage model | partly (scenarios + coverage, no per-vector JSON in the form step 7 asks) |
| 3 pair matrix (30 legal pairs, self-pair negative test) | not mentioned |
| 8 bridge oracle, 15 bridge golden vectors | blocked: needs the Lane 1 integration contract (not written) |
| 11 link monitor, 12 latency / timeout model, 13 NI slot-leak, 14 measurement-window vectors, 17 report figures, 18 RTL mutant proposals | not mentioned |

## 4. What closes it

E4 sends the `verification/` tree as a zip (with its SHA-256). Lane 1 extracts it into scratch, inspects the scripts, runs
`python verification/p7_regression.py` and `python -m pytest -q`, and records PASS / FAIL against the 224 / 15 / 16 claims.

HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.
