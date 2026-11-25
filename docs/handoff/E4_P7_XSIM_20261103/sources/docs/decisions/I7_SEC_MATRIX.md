# I-7 contract: PQ-4 SEC-1..4 matrix and PQ-5 offline full chain on P7 (written before the I-7 RTL hooks and runs, 2026-11-03)

Source plan: docs/handoff/LANE1_I6_I7_I8_HANDOFF_20261103.md sec. 5. Base: the I-6 subsystem (S3 / I-6 source list), the
real NOC-3 / NOC-4 modules, never bench stand-ins. Starts after the I-6 gate PASS (reports/I6_GATE_20261103.md, 3d72f16).

## 1. What changes

| Item | File | Change |
|---|---|---|
| Bench hooks | `rtl/dual_lane/pq_noc_subsystem_p7.sv` (in place, I6-INPLACE) | Under `TB_INJECT` only (wires when 0): (a) `TBI.ep_sub / ep_ctl / ep_words`: tile 3's RESPONSE status and 16 words replaced by bench values before tile 3's L2 (a compromised tile 3 that holds its L2 key); (b) the L2 pair (tiles 3, 4) receives through the existing `TBI.v / f` injector (L2 replay). No behaviour change with `TB_INJECT = 0`; the P&R netlist is unchanged in function. |
| Vectors | `scripts/gen_i7_vectors.py` -> `vectors/i7_sec.svh` | Attacker RESPONSE words and expected verdicts from the teammate reference (s8_golden adapter) and `scripts/policy_layer.py`; L2 reasons from `scripts/l2_golden.py` `rx_verdict` and M-F1 R7.2. SHA-256 printed by the check job. Never hand-edited. |
| Benches | `tb_i7_sec.sv` (PQ-4), `tb_pq_full_chain_p7.sv` (PQ-5) | sec. 3, 4 |

No RTL behaviour, wire format, bound, clock or device change.

## 2. Wire verdict rule (stated)

The P7 RESPONSE carries only the measurement (W0..W7) and the tag (W8..W15). The RTL verifier recomputes the tag over its
own outstanding tile / epoch / nonce. Each attacker row is judged by the reference as the wire allows: `verifier_check`
with the outstanding request and a response holding that request's fields plus the attacker's measurement and tag; then
the policy layer whitelist. Map to the I-6 fault reasons: reference "KMAC128 tag verification failed" -> 12; policy
"measurement not on whitelist" -> 11; status != 1 -> 9 (C-1/C-2). The attacker's own field values (old nonce, other
epoch / identity / key) are kept in the vector comments.

## 3. PQ-4 matrix (`tb_i7_sec`, 30 checks)

| Row | ID | Attack | Stimulus | Expected (oracle source) | Targeted control (mutant) |
|---|---|---|---|---|---|
| SEC1 | SEC-1 | genuine tile | row 0 | grant, endpoint_response == teammate expected_response, write commits (full_chain.svh) | `i7_mut_corrupt_response` (endpoint tag words swapped) |
| GENUINE_SUB | SEC-1 | genuine words through the hook | row 1 words | grant (reference ACCEPT, policy ACCEPT) | (hook self-check) |
| WRONG_TAG | OPEN-1 | wrong tag at the verifier | tag bit flipped | 12 | `i7_mut_tag_off` |
| WRONG_MEAS | OPEN-2 | wrong measurement | genuine key, unapproved image | 11 | `i7_mut_meas_off` |
| ATTEST_REPLAY | OPEN-3 | attestation replay | row-0 response to the row-1 challenge | 12 | `i7_mut_nonce_stale` |
| NONCE_SUBST | OPEN-4 | nonce substitution | tag over an attacker nonce | 12 | `i7_mut_tag_off` |
| ERROR_RESPONSE | OPEN-6 | error response | status 2, zero words | 9 | `i7_mut_error_accepted` |
| WRONG_KEY | SEC-2 | wrong key | other root secret | 12 | `i7_mut_tag_off` |
| WRONG_IDENTITY | SEC-2 | wrong identity | key / tag of TILE_04 | 12 | `i7_mut_tag_off` |
| STALE_EPOCH | SEC-3 | stale epoch | key / tag of EPOCH_0000 | 12 | `i7_mut_tag_off` |
| SEC4_SUBST | OPEN-5, SEC-4 | runtime imem substitution at re-attestation | imem input changed, genuine endpoint | 11, revoked and isolated; restored image grants | `i7_mut_meas_off` |
| SEC3_L2_REPLAY | SEC-3 | L2 replay | captured GRANT replayed after revoke | tile-3 L2 reason 4 (l2_golden) | `i7_mut_l2_seq_off` |
| SEC3_RESET_REPLAY | SEC-3 | reset replay | same GRANT after reboot with a new boot epoch | reason 3 (l2_golden) | `i7_mut_l2_epoch_off` |
| SEC2_SPOOF_RESPONSE | SEC-2 | forged RESPONSE from SPOOF | raw port, well-formed header | tile-4 L2 reason 5 (M-F1 R7.2), verifier never sees it | `i7_mut_peer_src_off` (reason becomes 2) |
| TRUNC_CHALLENGE | plus | truncated challenge | raw 3-flit CHALLENGE to tile 3 | tile-5 quarantine reason 11 (M-F1 R7.5b), nothing reaches tile 3's L2, endpoint silent | - |
| STATUS_CLEAR_MISUSE | plus | status-clear misuse | app traffic + GRANT after faults | sticky / count kept; only trusted_clear clears | - |
| CONCURRENT_SPOOF | plus | concurrent SPOOF traffic | raw flood during an attestation | grant, response matches, flood forwarded | - |
| NO_UNAUTH_COMMIT | all | - | whole run | 0 commits with authorized[3] = 0 | - |

Wrong grant issuer and timeout: covered by I-6 (`i6_gate` ISSUER / TIMEOUT, killed controls), consumed here by reference.

Counts: 2 + 9 x 2 + 3 + 1 + 1 + 1 + 1 + 1 + 1 + 1 = 30.

Mutants (kill scope `^\[FAIL\] SEC`): `i7_mut_corrupt_response` (oracle `SEC1_GENUINE_GRANT`), `i7_mut_tag_off`
(`SEC_(WRONG_TAG|WRONG_KEY|WRONG_IDENTITY|STALE_EPOCH|ATTEST_REPLAY|NONCE_SUBST)_`), `i7_mut_meas_off`
(`SEC(_WRONG_MEAS|4_SUBST)_`), `i7_mut_nonce_stale` (`SEC_ATTEST_REPLAY_`), `i7_mut_error_accepted`
(`SEC_ERROR_RESPONSE_`), `i7_mut_l2_seq_off` (`SEC3_L2_REPLAY`), `i7_mut_l2_epoch_off` (`SEC3_RESET_REPLAY`),
`i7_mut_peer_src_off` (`SEC2_SPOOF_RESPONSE`).

## 4. PQ-5 offline full chain (`tb_pq_full_chain_p7`, 21 checks)

Chain: challenge -> L2-authenticated transport -> endpoint (KDF, measure, tag) -> response -> RoT verifies (RTL verifier;
expected response from the teammate adapter = V7 oracle; policy layer whitelist via approved_measurement) -> GRANT ->
authorized write / read -> revoke / substitution -> blocked. Nonce source: deterministic demo issuer (chain rows); no
TRNG claim. Checks: FC_TXN<r>_RESPONSE / _GRANT / _DATA / _REVOKE_BLOCKS for rows 0, 1, 2 (12), FC_SUBST_BLOCKED (1),
FC_RESET_<S>_CLEAN for a reset in V_KWAIT, V_FILL, V_WAIT, V_TWAIT, V_GRANT (5), FC_TIMEOUT_THEN_RETRY (1),
FC_SPOOF_COEXIST (1), FC_NO_UNAUTH_COMMIT (1) = 21. The whole run has the raw-port flood on and tile 3's application
payload under backpressure (payload offered with gaps). Busy retry: unit level (I-6 `i6_retry`), stated.
Control: `i7_fc_mut_tag_swap` (endpoint tag words swapped on the wire; oracle `FC_TXN\d_GRANT`, scope `^\[FAIL\] FC_`).

## 5. Jobs (selection `i7`)

`i7_vectors` (python, marker `I7_VECTORS: PASS`), `i7_sec` (30), `i7_full_chain` (21), the 8 SEC mutants, `i7_fc_mut_tag_swap`,
plus `i7_gate_regress` (`tb_i6_gate`, 25, on the I-7 subsystem with its hooks; shows the hooks change nothing).

## 6. Acceptance

Every attack rejected for its stated reason with 0 unauthorized commits; every targeted control KILLED within scope;
PQ-5 fresh PASS. Gate report reports/I7_GATE_<date>.md. HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

## 7. Amendment before the first run (2026-11-03)

Scratch XSim (not evidence) showed the truncated raw CHALLENGE rejected by the tile-5 quarantine (reason 11) before any
L2. That is the specified first layer (M-F1 R7.5b: HEAD length must equal the P7 message length). The row's expected
value was mis-derived from the L2 model alone; it is now the quarantine verdict (q_rejected +1, q_reason 11), with the
added conditions that tile 3's L2 sees nothing and the endpoint sends nothing. Count unchanged (30); the check is not
weaker (expecting the L2 reason would have required the quarantine to fail). The generator still asserts the L2 model
would refuse it too (framing, 1).
Also before the first run: the row names come from a generated `case` function `i7_name()` and the SEC-4 row from
`I7_SUBST_ROW`, not from a localparam string array (XSim 2024.1 printed and compared those elements wrongly: scratch
showed garbled names and 32 checks). No count or check changed. The harness labels an implementation job's scope and
gate failure from the job (`scope`, `gate_label`) instead of the fixed mesh text (label only; acceptance unchanged).
Scratch (not evidence): i7_sec 30/30, i7_full_chain 21/21, i7_gate_regress 25/25; the 8 SEC controls KILLED; judge
replayed offline on the scratch logs.
Oracle correction for `i7_fc_mut_tag_swap` (scratch showed it, before its first registered run): the mutant swaps the
tag words the endpoint SENDS, not its internal response, so `endpoint_response` still equals the reference and
FC_TXN*_RESPONSE passes; the causal check is FC_TXN*_GRANT (the verifier refuses the corrupted RESPONSE). Oracle changed
from `FC_TXN\d_RESPONSE` to `FC_TXN\d_GRANT`; scope unchanged. Registered run `dual_lane_10_20261103_121815_8a007e1c` was
stopped by me after 5 jobs (i7_vectors, i7_sec, i7_full_chain, i7_gate_regress, i7_mut_corrupt_response, all
PASS_FRESH) to apply this before the job ran; it stays as history.

