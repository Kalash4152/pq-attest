# C-1 / C-2 decision: endpoint BUSY is a bounded retry in the RoT policy layer

**Decided:** Kalash, 2026-10-20, **Option A**. **Implementation:** I-6 (NOC-4), not I-3.
**PQ-2** may be accepted with C-1/C-2 recorded as "decided, implementation in I-6".

## Problem (rev-6 conflicts C-1, C-2)

The K-2 endpoint (`rtl/dual_lane/pq_attest_endpoint.sv`, merged `913de93`) answers a second RoT challenge that
arrives while it is busy with one queued `MSG_ATTEST_RESPONSE`: status 3, 16 zero words. The prepared verifier
`rtl/dual_lane/pq_rot_verifier.sv` accepts only status 1:
- `:70` sets `bad_header` when `rx_control[10:7] != 1` (also on wrong source or msg type);
- `:77` then sets `failed` and enters `V_REVOKE` at the last payload word.

Any non-success status, busy included, therefore revokes a healthy tile.

## Decision

The RoT verifier, i.e. the system policy layer (`rtl/dual_lane/pq_rot_verifier.sv`), handles the response status
in `control[10:7]` of `MSG_ATTEST_RESPONSE` before any measurement or tag check:

| Status | Verifier action |
|---|---|
| 1 success | as today: measurement check (`V_CHECK`), tag check (`V_TSTART`/`V_TWAIT`), then GRANT or REVOKE |
| 3 busy | **retry**: discard the 16 words and re-issue the *same* outstanding challenge (same epoch and nonce; the endpoint drained the busy one without starting crypto, R6.10). Increment `busy_retries` |
| 3 busy when `busy_retries` = 3 | **fail closed**: `failed`, REVOKE (record reason 4 stale/timeout, or 10, per the C-2 reason output when added) |
| any other value (0, 2, 4–15) | fail closed: `failed`, REVOKE |

- **Retry limit:** at most **3** retries per attestation (`MAX_BUSY_RETRIES = 3`). A 4th busy reply revokes.
  `busy_retries` resets on GRANT, REVOKE, reset and a new `start`.
- **Timeout:** the existing `TIMEOUT_CYCLES` watchdog (`:103`) restarts for each retry and keeps failing closed.
- **Unchanged:** the teammate verifier (`verifier_check` in the ZIP) and the ZIP itself. The teammate verifier is
  stateless and only judges a success response (R6.2 / V10 policy split). The RoT retry is policy, like the
  duplicate and whitelist rules in `scripts/policy_layer.py`. The Python policy model gains the same rule in I-6
  so the oracle and RTL agree.

## Wire / status-code format

**No wire or status-code format change.**
- Status 3 (busy, endpoint-detected, 16 × 0) is already frozen in M-F1 rev 6 R6.3.
- A retry is an ordinary Q-C challenge (R6.1) with unchanged fields.
- No new message type, length, field or code is introduced.

So no M-F1 revision is required. If the I-6 implementation needs any wire change (for example a retry counter on
the wire), an M-F1 revision must be written and signed first.

## Implementation and acceptance (I-6, NOC-4)

1. RTL: `rtl/dual_lane/pq_rot_verifier.sv` only. It reads `rx_control[10:7]`, adds `busy_retries` and
   `MAX_BUSY_RETRIES = 3`, and implements the fail-closed default.
2. Tests (counts frozen from source before the first run):
   - **busy → retry → grant:** the endpoint is busy for the first challenge, the retry succeeds, GRANT is issued,
     and exactly one extra challenge appears on the wire;
   - **busy × 4 → revoke:** four consecutive busy replies give exactly 3 retries, then REVOKE, `failed`, and no GRANT.
3. Mutant **no retry limit** (retry-count compare removed) must be killed by the busy × 4 test's targeted check,
   not by a timeout.
4. Re-run the full-chain test (PQ-5 bench) with an endpoint-busy case.

Remaining open items unaffected by this decision: the C-2 reason output (codes 4 and 6–9) and C-10.
