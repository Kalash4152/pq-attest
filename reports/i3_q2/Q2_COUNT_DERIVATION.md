# Q2 count derivation (I-3 / PQ-2): frozen BEFORE any run

Derived on 2026-10-19 by Track Q2 by reading the bench source. No compile or simulation of any kind was run. The figures are
the values `prepare_dual_lane.i3_q2.patch` freezes (`EP_UNIT_CHECKS=275`, `EP_SYS_CHECKS=37`). Each `check()` call prints exactly one
`[PASS] name` or `[FAIL] name` line and adds 1 to CHECKS. No check sits behind a data-dependent branch. A bounded wait that expires
prints `TB_TIMEOUT …` and adds to ERRORS without a check, so the run is INVALID rather than a pass or a kill.

## Unit bench `tb_pq_endpoint_unit.sv` (MAC_FLITS=0, CHALLENGE_LEN=8): CHECKS = 275

Helper task sizes (bench source):

| Task | Checks | Lines |
|---|---:|---|
| `expect_success` | 6 | STATUS, DEST, MEAS_WORDS, TAG_WORDS, EPOCH_NONCE_FIELDS, INTERNAL_776 (:145–151) |
| `expect_error` | 3 | STATUS, DEST, ZERO_PAYLOAD (:157–159) |
| `expect_quiet` | 1 | NO_REPLY (:165) |
| `valid_case` | 6 + 1 = 7 | expect_success + NO_REJECT (:172–173) |
| `malformed_case` | 3 + 2 = 5 | expect_error + COUNTED + NO_START (:181–184) |
| `drop_case` | 1 + 2 = 3 | expect_quiet + COUNTED/NOT_COUNTED + NO_START (:192–194) |
| `ctrl_error_case` | 3 + 2 = 5 | expect_error + STARTED + NOT_COUNTED (:211–213) |
| `reset_checks` | 2 | CLEARED, NO_STALE_TX (:225, :230) |

| Section | Arithmetic | Checks |
|---|---|---:|
| T1 valid V00–V05 (:243–244) | 6 × 7 | 42 |
| T1 DISTINCT_CONSECUTIVE (:247) | 1 | 1 |
| T1 V00DUP + DUPLICATE_SERVED_STATELESS (:249–250) | 7 + 1 | 8 |
| T2 malformed: SHORT6, LONG8, LEN_PLUS1, LEN_MINUS1, ZERO_WORDS, PAD_BIT223, PAD_BIT208 (:253–259) | 7 × 5 | 35 |
| T2 abort after k = 0..6 (:260–261) | 7 × 5 | 35 |
| T2 drop and ignore: 4 issuer, 2 type, 4 ignored (:262–275) | 10 × 3 | 30 |
| T3 R_STALE_INTERNAL_PRESENT (:279) | 1 | 1 |
| T3 R_CTX15, R_CFG65, R_IMEM65, X_FORCED_ERR (:280–283) | 4 × 5 | 20 |
| T4 B1: success + busy + COUNTED + ONE_START (:292–296) | 6 + 3 + 2 | 11 |
| T4 B2: success + busy + quiet + COUNTED_TWO + ONE_START (:307–312) | 6 + 3 + 1 + 2 | 12 |
| T4 B3: success + REPLY_TO_LATCHED + quiet + COUNTED (:319–322) | 6 + 1 + 1 + 1 | 9 |
| T4 B4: success + quiet + COUNTED (:329–331) | 6 + 1 + 1 | 8 |
| T4 B5: success + busy + COUNTED (:339–342) | 6 + 3 + 1 | 10 |
| T5 P1 valid under LFSR stalls (:347) | 7 | 7 |
| T5 P2 malformed under stalls (:348) | 5 | 5 |
| T5 P3 HELD_REQUEST + success (:358, :360) | 1 + 6 | 7 |
| T6 RST_PRE_ABORT (:367) | 3 | 3 |
| T6 reset phases RX, VALIDATE, START, WAIT, REQ, FILL, BUSY_PENDING, ERROR_FILL (:374–397) | 8 × 2 | 16 |
| T6 RST_RECOVERY (:398) | 7 | 7 |
| Global monitors (:402–409) | 8 | 8 |
| **Total** | 42+1+8+35+35+30+1+20+11+12+9+8+10+7+5+7+3+16+7+8 | **275** |

Sum by section: T1 51, T2 100, T3 21, T4 50, T5 19, T6 26, global 8 = 275.

Derived side tallies (they are checked by START_COUNT and RESPONSE_COUNT):

- Expected `controller_start` = 23. That is 9 valid_case (T1 6 + DUP + P1 + RST_RECOVERY), 4 ctrl_error_case, B1–B5 5, P3 1,
  and the 4 reset phases WAIT, REQ, FILL and BUSY_PENDING. RX, VALIDATE and START reset before the start is sampled outside reset,
  and ERROR_FILL is malformed.
- Expected complete responses = **38**: 15 `expect_success` (9 via valid_case + B1–B5 + P3) plus 23 `expect_error`
  (14 T2 malformed + P2 + 4 T3 + 3 busy (B1, B2, B5) + RST_PRE_ABORT = 14 + 1 + 4 + 3 + 1). The RESPONSE_COUNT check compares against the bench's own tally (`exp_responses`), so
  this figure is informative only. The RST_FILL and RST_ERROR_FILL partial responses are discarded at reset and never complete.

## System bench `tb_pq_endpoint_sys.sv` (PQ_MAC_ON, MAC_FLITS=4, wire challenge 17 flits): CHECKS = 37

`attest()` = 5 checks (STATUS, DEST, MEAS_WORDS, TAG_WORDS, GRANT). `untouched()` = 1.

| Section | Arithmetic | Checks |
|---|---|---:|
| S0_RESET_IDLE | 1 | 1 |
| S1 attest + INTERNAL_776 + EPOCH_NONCE_FIELDS + ONE_CHALLENGE_NO_REJECT | 5 + 3 | 8 |
| S2 forged challenge (bad MAC): L2_MAC_REJECTED + untouched + NO_REVOKE | 1 + 1 + 1 | 3 |
| S3 replay of recorded RoT challenge: L2_REPLAY_REJECTED + untouched + NO_REVOKE | 1 + 1 + 1 | 3 |
| S4 wrong VC: L2_VC_REJECTED + untouched | 1 + 1 | 2 |
| S5 SPOOF mid-packet stall 400 cycles: L2_REJECTED_AFTER_STALL + untouched + attest | 1 + 1 + 5 | 7 |
| S6 stall concurrent with challenge: EVENTUALLY_GRANTED, RESPONSE_WORDS, NO_SPOOF_IN_ENDPOINT | 3 | 3 |
| S7 reset in E_WAIT: RESET_CLEARS + NO_STALE_RESPONSE + attest S7R | 2 + 5 | 7 |
| Global: SYS_ENDPOINT_RX_READY_ALWAYS, SYS_ONLY_SUCCESS_REPLIES, SYS_NO_MEMORY_COMMIT | 3 | 3 |
| **Total** | 1+8+3+3+2+7+3+7+3 | **37** |

S6 allows at most one trusted retry inside the bench. The SPOOF stall can delay the RoT challenge, or the L2 overload policy
(R6.7 item 6) can drop it, and the timing decides which; the check count is the same either way. One verifier timeout is
100 000 cycles, so the job sets `sim_timeout=1800` s.

## Mutants: expected targeted error lines (all run on the unit bench; CHECKS stay 275)

| Job | Mutant | Targeted oracle | Expected targeted `[FAIL]` lines | Expected ERRORS | Derivation |
|---|---|---|---:|---:|---|
| `pq_endpoint_mut_tag_swap` | `ep_tag_swap` | `^\[FAIL\] \S+_TAG_WORDS$` | 15 | 15 | 15 `expect_success` calls. Each tag W8..W15 is sent reversed. No vector's tag word list is a palindrome (asserted in `endpoint_golden.py`). MEAS, INTERNAL and EPOCH_NONCE are unaffected |
| `pq_endpoint_mut_nonce_offset` | `ep_nonce_offset` | `^\[FAIL\] \S+_EPOCH_NONCE_FIELDS$` | 15 | 45 | Each of the 15 successes fails EPOCH_NONCE_FIELDS, TAG_WORDS and INTERNAL_776 (3 × 15). `C[215:88] != nonce` for all 6 vectors (asserted). The measurement does not depend on the nonce, so MEAS passes. DISTINCT and DUPLICATE are expected to pass (the mutated tags still differ by nonce and are equal for the duplicate) |
| `pq_endpoint_mut_wrong_reply` | `ep_wrong_reply` | `^\[FAIL\] REPLY_TO_LATCHED$` | 1 | 2 | B3 is the only reply sent while the last RX HEAD came from a non-RoT source (SPOOF). It fails B3_FIRST_DEST and REPLY_TO_LATCHED. Every other reply follows a RoT HEAD |
| `pq_endpoint_mut_rx_stall` | `ep_rx_stall` | `^\[FAIL\] RX_READY_ALWAYS$` | 1 | 1 | The endpoint logic never reads rx_ready, so behaviour is unchanged. The monitor sees rx_ready = 0 while busy. The RTL SVA also prints `[FAIL] SVA_RX_READY_ALWAYS …` lines. These are not counted in ERRORS and the judge allows them for mutants |
| `pq_endpoint_control_after` | none | — | 0 | 0 | 275/0 PASS |

The judge requires ERRORS > 0, RESULT FAIL, and at least one match of the oracle for a kill. The "Expected ERRORS" column is a
prediction for review. It is not frozen in the registry.
