# I-6 contract: NOC-4 trusted authorization (written before the RTL, 2026-11-02)

Source plan: docs/handoff/LANE1_I6_I7_I8_HANDOFF_20261103.md sec. 4. Base: the S3 source list (`s3_list()` in
scripts/prepare_dual_lane.py). Kalash's I-6 decisions (2026-11-02): K-3 enforced in hardware; new subsystem ports
approved (trusted clear in, fault status out); B1 counter widths deferred (32-bit kept); unprotected `rtl/dual_lane`
files edited in place (older jobs' identities change; their records stay as history).

## 1. What changes

| ID | File (in place) | Change |
|---|---|---|
| C-1 / C-2 | `rtl/dual_lane/pq_rot_verifier.sv` | Bounded busy retry: a complete 16-word RESPONSE from tile 3 with status 3 (BUSY) re-issues the SAME outstanding challenge (same epoch / nonce / derived key; no new KDF), `busy_retries++`, timer restarted. A BUSY when `busy_retries == MAX_BUSY_RETRIES (3)` fails closed (failed, REVOKE). Any other status != 1 fails closed immediately. `busy_retries` is cleared on reset, on start, at the GRANT handshake and at the REVOKE handshake. A revoke / abort / timeout during a retry wins as before (F2, Q5). New output `fail_reason[3:0]` (sec. 3 codes 8..12), valid with the `failed` pulse. New status capture `hdr_status` at the RESPONSE HEAD; the source / type check stays separate (reason 10). |
| K-3 | `rtl/dual_lane/pq_attest_endpoint.sv` | Parameters `K3_ENFORCE` (default 0), `K3_CONFIG_LEN`, `K3_IMEM_LEN` (default 16 / 16). When enforced, a valid challenge whose runtime `config_len` / `imem_len` differ from the provisioned constants is answered with status 5 (MALFORMED) before the controller starts, counted in `rejected_count`, and pulses the new output `k3_fault`. No wire change: the verifier fails closed on status 5. |
| Gate events | `rtl/dual_lane/noc_attest_gate.sv` | New parameter `TILE` (default 0) and outputs `fault_event` (one-cycle pulse, registered with `fault_reason`), `fault_source[2:0]` (tile index: the packet's source for GRANT / REVOKE faults, else `TILE`), `fault_operation[3:0]` (message type). Authorization behaviour unchanged. |
| N-10 / trusted inputs / C-5 / K-3 | `rtl/dual_lane/pq_noc_subsystem_p7.sv` | (a) tile 3's gate: `trusted_fail = attestation_failed && fail_reason != 8`, `trusted_timeout = attestation_failed && fail_reason == 8` (verifier drives the gate directly); (b) `trusted_clear` input to every gate and to the fault status; (c) one `noc_fault_status` (sec. 3) with new outputs; (d) memory window `A[31:28] == 4'h2` (C-5; was `4'h8`); (e) endpoint built `K3_ENFORCE = 1`, 16 / 16; (f) parameter `VERIFIER_TIMEOUT` (default 100,000, unchanged for synthesis) passed to the verifier; (g) bench-only `TB_INJECT` hooks extended: `TBI.gv/gsrc/gmsg/gctl[g]` present an authenticated HEAD at gate g's inputs, `TBI.drop4` hides tile 4's RX from the verifier (a lost response). `TB_INJECT = 0` everywhere except benches: wires only. |
| C-1 model | `scripts/policy_layer.py` | `busy_retry_outcome(n_busy)` (same rule, MAX 3) plus selftest cases; vectors for the RTL bench generated from it (sec. 4). |

Not changed: the NoC wire format, message lengths, M-F1 codes, the router / NI / mesh (protected), the L2 pair, the
ingress, the clock, the device, signed bounds. B1 (counter widths) deferred by Kalash.

## 2. Ports (M-F1 rev 7, R7.11 port note)

`pq_noc_subsystem_p7` gains:
- input `trusted_clear` (trusted, RoT side; clears every gate's fault counter / reason and the fault status; no
  application port can reach it);
- outputs `fault_sticky`, `fault_count[31:0]` (saturating), `fault_source[2:0]`, `fault_operation[3:0]`,
  `fault_reason[3:0]`, `fault_epoch[79:0]`.
No timestamp output (not approved; the `noc_fault_status` timestamp input is tied 0 and its output left open).

## 3. Fault status map (one `noc_fault_status`, epoch = `attest_epoch` in the event cycle)

| reason | event | source | operation |
|---|---|---|---|
| 1 | data refused at a gate (not authorized) | that tile | the app message type |
| 2 | GRANT / REVOKE from a non-RoT issuer | packet source | GRANT / REVOKE |
| 3 | GRANT with status != 1 | packet source | GRANT |
| 4 | trusted fail / timeout blocked tile 3 (gate) | 3 | RESPONSE |
| 5 | GRANT / REVOKE at a non-attestable gate (unreachable in P7) | packet source | GRANT / REVOKE |
| 6 | memory request without authorization (dropped at HEAD, write not committed, read suppressed) | requester | MEM_WR_REQ / MEM_RD_REQ |
| 7 | K-3 length binding mismatch at the endpoint | 3 | CHALLENGE |
| 8 | verifier timeout | 3 | CHALLENGE |
| 9 | verifier: RESPONSE status != 1 (including BUSY after 3 retries) | 3 | RESPONSE |
| 10 | verifier: malformed RESPONSE (source, type, length, rx_abort) | 3 | RESPONSE |
| 11 | verifier: measurement not the approved one | 3 | RESPONSE |
| 12 | verifier: tag mismatch (or tag error) | 3 | RESPONSE |
| 13 | memory address outside the 0x2 window (error reply 0x400 as before) | requester | MEM_WR_REQ / MEM_RD_REQ |

One record per cycle; simultaneous events: verifier > K-3 > memory > gates (lowest tile index first). `fault_count`
counts cycles with at least one event. `trusted_clear` and reset clear all fields.

## 4. Jobs (counts frozen here, before the first run)

Selection `i6`:

| Job | Kind / top | Checks | Notes |
|---|---|---|---|
| `i6_benches` | python `scripts/prepare_i6.py --check` | marker `I6_BENCHES: PASS` | the `*_i6` bench copies equal their generation from the originals (address 0x8200_0100 -> 0x2200_0100, `.trusted_clear(1'b0)` connected); provenance `sim/dual_lane/i6/i6_provenance.json` |
| `i6_policy_layer` | python `scripts/policy_layer.py` | marker `POLICY_LAYER: PASS` | adds the busy-retry rule cases |
| `i6_retry_vectors` | python `scripts/gen_i6_vectors.py --check` | marker `I6_VECTORS: PASS` | `vectors/i6_retry.svh` from `policy_layer.busy_retry_outcome` |
| `i6_retry` | `tb_i6_retry` | **24** | verifier unit (real RTL, BYPASS_MEASUREMENT / TAG = 1, TIMEOUT 3,000): 6 Python rows x 2 (n_busy 0..5: challenges + identical words; outcome) + statuses 2 / 5 / 10 x 2 (no retry; fail reason 9) + 2 counter-reset + 2 timeout-in-retry + 1 per-attempt timer + 1 revoke-in-retry |
| `i6_gate` | `tb_i6_gate` | **25** | integrated S3/I-6 subsystem, PQ_MAC_ON, TB_INJECT = 1, VERIFIER_TIMEOUT = 3,000 (list below) |
| `i6_verifier_revoke` | `tb_verifier_revoke` | 48 | unchanged bench on the I-6 verifier |
| `i6_pq_endpoint_unit` | `tb_pq_endpoint_unit` (`_i6`) | 275 | copy that only declares `k3_fault` (the bench uses an implicit `.*` connection); endpoint K3_ENFORCE = 0 default |
| `i6_s2_attacks` | `tb_s2_attacks` | 30 | unchanged bench, gate changed |
| `i6_n2p7_rtt` | `tb_n2p7_rtt` (file `tb_n2p7_rtt_i6.sv`) | 11 | 0x2 copy |
| `i6_p7_c4` | `tb_p7_c4` (`tb_p7_c4_i6.sv`) | 18 | 0x2 copy |
| `i6_f234_p7` | `tb_sys_f234` (`tb_sys_f234_p7_i6.sv` + `tb_sys_f234_body_i6.svh`) | 26 | 0x2 copy |
| `i6_p7_gate_data` | `tb_p7_gate_data` (`_i6`) | 4 | 0x2 copy |
| `i6_p7_ingress` | `tb_p7_ingress` (`_i6`) | 39 | 0x2 copy |
| `i6_p7_refuse_grant` | `tb_p7_refuse_grant` (`_i6`) | 12 | trusted_clear tie only |

Module names in the copies are unchanged (only the file names differ); a source list never holds a copy and its
original. Selection `i6_pnr`: `i6_p7_pnr` (copy of `s3_p7_pnr`, I-6 list, S1-PNR-DIR, run alone).

`tb_i6_gate` checks (25): I6G_RESET_BLOCKED, I6G_RESET_RECORD, I6G_GRANT_AUTHORIZED, I6G_GRANT_WRITE_COMMITS,
I6G_MEM_READ_AUTHORIZED, I6G_WINDOW_OLD_REFUSED, I6G_WINDOW_RECORD, I6G_MEM_UNAUTH_NO_COMMIT, I6G_MEM_UNAUTH_RECORD,
I6G_ISSUER_REJECTED, I6G_ISSUER_RECORD, I6G_GRANT_STATUS_REJECTED, I6G_GRANT_STATUS_RECORD, I6G_REVOKE_BLOCKS,
I6G_K3_FAIL_BLOCKS_LOCAL, I6G_K3_RECORD, I6G_FAIL_RECORD, I6G_WRONG_MEAS_NO_GRANT, I6G_WRONG_MEAS_RECORD,
I6G_TIMEOUT_BLOCKS_LOCAL, I6G_TIMEOUT_RECORD, I6G_TRUSTED_CLEAR, I6G_RETRY_AFTER_FAIL_GRANT,
I6G_RESET_DURING_CHALLENGE, I6G_NO_UNAUTH_COMMIT. `*_BLOCKS_LOCAL`: authorized[3] falls at most 2 cycles after the
verifier's failed pulse (the trusted path, not the later REVOKE packet). A `*_RECORD` check finds the stated
(source, operation, reason, epoch) among the fault-status records logged since the case began.

Handoff case 7 (4 BUSY -> 3 retries -> fail) is checked at the verifier unit (`tb_i6_retry`): in the integrated P7
the endpoint queues at most one BUSY reply and always behind its in-flight RESPONSE, so a run of BUSY replies
cannot be produced through the RoT's single outstanding challenge. Stated, not hidden.

## 5. Mutants (each KILLED by its targeted check; no timeout or fatal)

| Job | Mutant (file) | Oracle | Kill scope |
|---|---|---|---|
| `i6_mut_retry_unbounded` | limit compare never true (verifier) | `^\[FAIL\] RETRY_PY_N[45]_` | `^\[FAIL\] RETRY_` |
| `i6_mut_no_retry` | BUSY fails at once (verifier) | `^\[FAIL\] RETRY_PY_N[123]_` | `^\[FAIL\] RETRY_` |
| `i6_mut_gate_bypass` | `.BYPASS_GATE(1'b1)` (subsystem) | `^\[FAIL\] I6G_RESET_BLOCKED` | `^\[FAIL\] I6G_` |
| `i6_mut_issuer_off` | `.BYPASS_ISSUER(1'b1)` | `^\[FAIL\] I6G_ISSUER_` | `^\[FAIL\] I6G_` |
| `i6_mut_revoke_ignored` | `.BYPASS_REVOKE(1'b1)` | `^\[FAIL\] I6G_REVOKE_BLOCKS` | `^\[FAIL\] I6G_` |
| `i6_mut_trusted_off` | gate trusted inputs tied 0 | `^\[FAIL\] I6G_(K3_FAIL\|TIMEOUT)_BLOCKS_LOCAL` | `^\[FAIL\] I6G_` |
| `i6_mut_fs_off` | fault-status `event_valid` tied 0 | `^\[FAIL\] I6G_\w+_RECORD` | `^\[FAIL\] I6G_` |
| `i6_mut_k3_off` | `.K3_ENFORCE(1'b0)` | `^\[FAIL\] I6G_K3_RECORD` | `^\[FAIL\] I6G_` |
| `i6_mut_window_old` | window back to `4'h8` | `^\[FAIL\] I6G_(GRANT_WRITE_COMMITS\|WINDOW_)` | `^\[FAIL\] I6G_` |

The integrated kill scope is the whole bench prefix: every I6G check reads the state the mutated control feeds.

## 6. Invariants

- No memory commit while the writer is not authorized in the decision cycle (I6G_NO_UNAUTH_COMMIT; F4 / Q2 unchanged).
- Only an authenticated GRANT from the RoT (tile 4) with status 1 sets authorized[3]; revoke, failure, timeout and
  reset clear it; a new trusted attestation can grant again.
- The verifier never sends more than 1 + 3 challenges per start; it never grants after a non-1 status other than a
  BUSY that was retried.
- Fault records for every class above; trusted_clear only from the trusted input.

## 7. Acceptance

Every `i6` job PASS_FRESH or identity-matched PASS_REUSED; every mutant KILLED within its scope; `i6_p7_pnr` LUT <=
47,550 with WNS >= 0 (reported against +0.3 ns and against S3 37,398 LUT / +0.126 ns). Gate report
reports/I6_GATE_<date>.md. HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

## 8. Amendment before the first run (2026-11-02)

Scratch compile (not evidence) showed that `tb_pq_endpoint_unit` connects the endpoint with `.*`, so the new `k3_fault`
output needs a bench signal. `scripts/prepare_i6.py` now also generates `tb_pq_endpoint_unit_i6.sv` (one declaration
added); `i6_pq_endpoint_unit` uses it. Count unchanged (275). No other job, count or check changed.
Lint waivers (scripts/rtl_lint_waivers.json): the two pinned waivers for the unchanged capture lines
`pq_attest_endpoint.sv` (`challenge[32*wcount +: 32]`) and `pq_rot_verifier.sv` (`incoming[count*32+:32]`) moved from
lines 202 / 106 to 212 / 111 with the in-place edits; line numbers re-pinned, source text and line SHA-256 unchanged.
Registry fix after run `i6` attempt 1 (stopped by me after its first job): `i6_benches` listed the bench files as
`sources`, so the harness preflight compiled-scanned them without include directories (FAIL "missing include"); they
are now `oracle_files` (still hashed into the identity). No count, check or bench changed. The stopped run stays as
history; every identity changed with the registry, so nothing from it is reused.
Registry fix after run `dual_lane_10_20261102_233828_e26d042a` (15 PASS_FRESH; `i6_gate` INVALID "wrong configuration
TOP=tb_n2p7_rtt": the copy inherited the n2p7 job's CONFIG fields; its 7 mutants BLOCKED): `i6_gate` and `i6_retry` now
carry their own CONFIG fields (TOP, CHECKS, timeout). Benches, counts and checks unchanged. The run stays as history; the
whole `i6` selection is re-run because every identity includes the registry.
Registry fix after run `dual_lane_10_20261102_235623_5a0e5b57` (15 PASS_FRESH; `i6_gate` INVALID: it inherited the n2p7
job's `required_lines`; its mutants BLOCKED): the two new-bench jobs drop every bench-specific field of their copied base
(`required_lines`, `variant_of`). Before re-running, the judge (`dual_lane_verify.judge`) was replayed offline on the
scratch logs of all 20 I-6 simulation jobs: all accepted (11 PASS, 9 KILLED). Scratch replay is not evidence.
