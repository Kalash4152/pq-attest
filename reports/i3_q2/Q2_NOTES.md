# Track Q2 notes: I-3 / PQ-2 endpoint preparation (2026-10-19)

**Evidence state.** The endpoint, both benches and the vectors are **implemented**. Nothing has been compiled or XSim-simulated,
and nothing is reference-checked in RTL or mutation-tested: no Vivado, XSim, xvlog or xelab process was run, by rule, because a
synthesis job was running. Python only: `endpoint_golden.py` in check mode, `test_q2_mutants.py` and `test_dual_lane.py`. Formal
proof: NO. Hardware: NO. Base: `noc/credit-integration` at `cf29ec3`. The brief's base was `57b7031`; the only differences are
in STATUS and DECISION_REGISTER, which Q2 does not read for these semantics.

## Files

| File | Role |
|---|---|
| `rtl/dual_lane/pq_attest_endpoint.sv` | K-2 endpoint (the only RTL change). Same port list as before, so `pq_noc_subsystem.sv` is unchanged. The `MUT_*` parameters are removed; mutants are now text anchors |
| `scripts/endpoint_golden.py` | Thin adapter over `s8_golden.compose` (teammate reference, TILE_KEY_BYTES=32). It also proves that `vectors/full_chain.*` is fresh and that V00–V02 equal full-chain rows 0–2 |
| `vectors/endpoint_golden.json/.svh` | 6 R-B vectors and a 17-row K-2 error-case table |
| `NOC_PQATTEST.srcs/sim_1/new/tb_pq_endpoint_unit.sv` | Unit bench, 275 checks |
| `NOC_PQATTEST.srcs/sim_1/new/tb_pq_endpoint_sys.sv` | System bench (`pq_noc_subsystem`, PQ_MAC_ON), 37 checks |
| `reports/i3_q2/mutation.i3_q2.patch` | **Not applied.** Adds the `ep_*` anchors to `mutation()` and makes `execute()` mutate `pq_attest_endpoint.sv` for `ep_*` kinds |
| `reports/i3_q2/prepare_dual_lane.i3_q2.patch` | **Not applied.** Adds 8 jobs with selection `I-3` and an `I-3` increment, replaces the `pq_endpoint` blocker in stage PQ-2, and leaves `active_increment` at `I-2` |
| `reports/i3_q2/test_q2_mutants.py` | Checks anchor uniqueness and oracle targeting. It also applies both patches to a temp copy and builds the patched registry, with preflight |
| `reports/i3_q2/Q2_COUNT_DERIVATION.md` | Frozen counts and the predicted mutant failure lines |

## Status-code behaviour (implemented; see the RTL header)

| Stimulus at the endpoint RX | rejected_count | Reply (tx_control[10:7]) | Crypto |
|---|---|---|---|
| MEM_* , ATTEST_GRANT, ATTEST_REVOKE (any source) | unchanged | none | no |
| ATTEST_RESPONSE or reserved type 8–15 | +1 | none | no |
| CHALLENGE from a source other than RoT (1,1), any content | +1 | none (no reflection toward SPOOF) | no |
| RoT CHALLENGE while busy (transaction or queued busy reply) | +1 | **3**, queued behind the in-flight reply; one deep | no |
| … a second busy challenge while a busy reply is already queued | +1 | none | no |
| … a busy challenge that is aborted | +1 | none | no |
| RoT CHALLENGE (idle) with HEAD length ≠ message_length | +1 | **5** | no |
| … payload words ≠ 7 (6, 8, HEAD_TAIL 0) | +1 | **5** | no |
| … rx_abort after k = 0..6 words | +1 | **5** | no |
| … padding C[223:208] ≠ 0 | +1 | **5** | no |
| Valid challenge, controller err with error_code 1 (context_len > 14) or 2 (config/imem length) | unchanged | **2** | started |
| Valid challenge, controller err with any other code | unchanged | **10** | started |
| Valid challenge, controller done without err | unchanged | **1**, R-B words | started |

Every status other than 1 carries 16 zero words. Under the controller error path `response` keeps its previous value
(`pq_attest_protocol.sv`:686–735), so zeroing at the endpoint is what prevents stale bytes from leaking. T3 checks this after a
success. Busy takes priority over malformed.

## Busy reply (3) vs `pq_rot_verifier` (rev-6 C-1 note). C-2 stays OPEN; the verifier is unchanged

`pq_rot_verifier.sv` holds one outstanding challenge and records no per-cause reason.

1. **Busy reply during V_WAIT.** If a busy reply reaches the RoT while it waits for a response, the verifier takes it as *the*
   response: `bad_header` is set because status ≠ 1 (:70), and at the terminator (:77) it goes to REVOKE.
2. **Busy reply during V_CHECK / V_TSTART / V_TWAIT.** Any HEAD clears `incoming` (:69). The tag compare at :96 then uses zeroed
   data (the measurement compare at :92 may also be hit), so the verifier REVOKEs. A busy reply arriving after a healthy success
   response can therefore **revoke a healthy attestation**.
3. **What the endpoint does.** It queues the busy reply *behind* the in-flight response and never sends it first. That removes
   case 1 for the challenge being served, but **not** case 2.
4. **When it can happen.** In the P6-S secure profile only the RoT can deliver a challenge (N-9 MAC and sequence). The RoT issues
   a second challenge only after its own timeout or revoke. So the hazard needs a RoT retry racing a slow endpoint, or the
   unauthenticated P6 profile (where SPOOF can forge the RoT source). The system bench does not provoke it, and the unit bench has
   no verifier.
5. **Fix options (Kalash, C-1 / C-2 / Q-7), not implemented.**
   - (a) The verifier ignores any response HEAD outside V_WAIT and does not clear `incoming` (C-2 work, NOC-4/PQ-4).
   - (b) The endpoint sends busy only when no response is pending toward that issuer.
   - (c) Return to drain-only busy (S8-2 text / OD-5), which contradicts the K-2 restatement used here.

## Open items

| ID | Item |
|---|---|
| C-1 / Q-7 | Implemented as Kalash restated K-2: the endpoint sends 2/3/5/10. Still to be recorded in the register; the hazard is above. `S8-2-tile-attest-endpoint.md` and R6.10 still say "busy challenges receive no queued response". Those docs are outside the Q2 allowlist and need a doc update |
| Q2-a | Mapping of controller `error_code` 1/2 to **2 (reject)** and every other `err` to **10** is a Q2 design choice. The teammate reference defines no status codes. Kalash to confirm |
| C-2 | Verifier per-cause reason and the busy-reply revoke hazard: OPEN, verifier unchanged |
| C-10 / Q-8 | `config_len` / `imem_len` are still runtime ports. They were not changed, because fixing them needs subsystem and whitelist changes outside this file. The unit bench varies them (V04, V05) only to exercise wiring |
| Q2-b | `pq_noc_subsystem` switches the tile-3 TX mux on `endpoint_busy` without waiting for an application packet boundary (pre-existing, `pq_noc_subsystem.sv`:87). Q2 keeps `busy` high across the queued busy reply to avoid a one-cycle gap. Belongs to NOC-4 |
| Q2-c | Wrong VC cannot be seen at the endpoint ports (the NI and L2 filter it). It is covered only in the system bench (S4) |
| Q2-d | Unit case X_FORCED_ERR uses `force dut.err` (a bench-only force on the endpoint-side net) because the controller has no reachable internal-error stimulus. If XSim rejects that force, the case needs another stimulus |
| Q2-e | R4 PQ-2 asks to delete the zero-byte `pq_attest_request.sv`/`pq_attest_response.sv` and mark `pq_attest_protocol_pkg.sv` orphaned, with a register entry. That is not done here (register and protected-area edits are out of scope). Neither is in any Q2 source list |
| Q2-f | Mutant `ep_wrong_reply` models "reply to the live RX source instead of the latched HEAD source". The old `MUT_REPLY` (reply to CRYPTO itself) is retired |
| Q2-g | The patch adds only the PQ-2 half of `increments['I-3']`. The NOC-2 track must append its jobs, and the integrator switches `active_increment`/config to `I-3` |
| Q2-h | **Untracked empty file left in the main checkout** by a failed .NET write during this session: `C:\vivado_verilog_proj\NOC_PQATTEST\NOC_PQATTEST.srcs\sim_1\new\tb_pq_endpoint_unit.sv` (0 bytes expected). Deletion was refused by the permission classifier. Kalash should delete it, or the merge of this branch will conflict with it |
