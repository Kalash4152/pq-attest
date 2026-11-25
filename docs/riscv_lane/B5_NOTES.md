# B5 notes: `app_port_checker` (bind-able app-port protocol checker)

**Files:** `sim_riscv/app_port_checker.sv`, `sim_riscv/tb_app_port_checker.sv`, `riscv_a1/run_tb_app_port_checker.tcl`
(Vivado Tcl-console runner).

**Status:** scratch-level (XSim 2024.1), **not registered**. CHECKS = 10, frozen in the bench header before the first run.
Simulation-only module; never part of a synthesis source list. Formal: NO. Hardware: NO.

**Specs:** docs/handoff/BRIEF_RISCV_LANE_v2_20261101.md sec. B5; docs/decisions/M-F1-rev8-INTEGRATION-DRAFT.md sec. 3-6; the
main session's B5 task message (2026-11-06).

## Properties

Each violation prints `[FAIL] B5_<PROPERTY> t=... <detail>` (never an `Error:` line) and increments a per-property counter
(`n_head_stable`, `n_payload_stable`, `n_valid_unauth`, `n_one_outstanding`, `n_payload_count`, `n_msg_legal`,
`n_dest_legal`; `total()` sums them), so a bench can read the counters hierarchically.

| Property | Fires when | Allowed exceptions (from the contract / bridge behaviour) |
|---|---|---|
| `B5_HEAD_STABLE` | `app_valid` held without `app_ready`, and next cycle `app_valid` drops or destination / message / control change | Drop allowed when `authorized = 0` (rule 4 revocation), after `TIMEOUT_CYCLES` held (rule 6: a held-off HEAD is a wait covered by `BRIDGE_TIMEOUT`), or the cycle after `app_tx_error`. Field changes always fire. |
| `B5_PAYLOAD_STABLE` | `app_payload_valid` held without ready, and next cycle it drops or `app_payload` changes | Drop allowed the cycle after `app_tx_error`, or once `TIMEOUT_CYCLES` have passed since the HEAD was raised. |
| `B5_VALID_UNAUTH` | `app_valid && !authorized` | none |
| `B5_ONE_OUTSTANDING` | a new HEAD while a request is open | Open from the HEAD handshake until `app_rx_last`, `app_rx_abort`, `app_tx_error`, or `RELEASE_CYCLES` (= the sender's late-response drain). |
| `B5_PAYLOAD_COUNT` | not exactly 2 payload words (write) / 1 (read) per request | A cycle with `app_tx_error` is a rejection, not a transfer. |
| `B5_MSG_LEGAL` | `app_valid` with a message other than `MSG_MEM_RD_REQ` / `MSG_MEM_WR_REQ` | none |
| `B5_DEST_LEGAL` | `app_valid` with a destination outside the 3 x 2 mesh or equal to the tile's own coordinate | none |

Parameters: `SELF_TILE` (3), `TIMEOUT_CYCLES` (sender's `BRIDGE_TIMEOUT`, 4,096), `RELEASE_CYCLES` (sender's
`LATE_DRAIN_CYCLES`, 8,192). Bind example: header of `app_port_checker.sv`.

**Not covered by the checker:** "every request ends in exactly one of response / error / timeout" needs the sender's TMEM
side; `tb_tmem_app_bridge` checks it (`B1_COUNTS`: responses == grants), and so does this bench's `B5_CLEAN_COVERAGE`.

## Scratch results (XSim 2024.1)

**Unmutated: `RESULT : PASS`, 10 / 10 checks, 0 `Error:` lines.** Also passed once through the Tcl in Vivado batch mode.
- **Clean (checker bound into `tmem_app_bridge`, 400 random requests):** 0 violations. Every mode was exercised: normal 283,
  no response 14, HEAD ready held low 13, payload ready held low 18, late response 16, `app_tx_error` 15, unauthorized 24,
  bad tile 17. Bridge timeouts 61, refusals 24, grants = responses = 400.
- **Negative (stand-alone checker, one injected violation per case):** each of the 8 cases (HEAD fields changed, HEAD
  withdrawn early, payload changed, valid while unauthorized, second HEAD while open, write with 1 payload word, message 4,
  destination = self) raised exactly its own counter by 1 and left the other 6 at 0. The 8 `[FAIL] B5_...` lines in the log
  are these expected checker reports; the bench verdict is the `[PASS] B5_NEG_...` line after each.

**Bridge mutants under the bound checker (B1 mutant files, scratch): 3 / 3 caught, each `RESULT : FAIL`, no timeouts.**

| Mutant | Checker counters on the clean traffic |
|---|---|
| `auth_removed` | `B5_VALID_UNAUTH` 33 |
| `late_accepted` (no drain after a timeout) | `B5_ONE_OUTSTANDING` 47, `B5_PAYLOAD_COUNT` 42 |
| `double_issue` | `B5_HEAD_STABLE` 3, `B5_PAYLOAD_STABLE` 10 (plus `B5_CLEAN_COVERAGE`: responses 939 vs 400 grants) |

The brief's "each property fails at least once on a mutant" is met for `VALID_UNAUTH`, `ONE_OUTSTANDING`, `PAYLOAD_COUNT`,
`HEAD_STABLE`, `PAYLOAD_STABLE` by these bridge mutants. `MSG_LEGAL` and `DEST_LEGAL` cannot be reached by a one-line bridge
mutant without also failing B1 (the bridge drives constants there); they are covered by the directed negative cases only.

**Bind check (brief "binds cleanly into a copy of tb_pq_full_chain"; compile only, not simulated):** the registered
`full_chain` source list (`PQ_MAC_ON`, include `vectors/`) + `app_port_checker.sv` + a scratch module holding
`bind tb_pq_full_chain app_port_checker #(.SELF_TILE(3)) u_b5 (...)` on tile 3's app port: xvlog 0 errors, xelab 0 errors,
snapshot built. The protected bench was not edited. That bench has no `app_tx_error` / `app_rx` bundle, so those inputs were
tied to 0. If it were simulated, the checker would report `B5_VALID_UNAUTH` on the bench's two intentional
"valid while blocked" probes (`RESET_DATA_BLOCKED`, `REVOKED_DATA_BLOCKED`): those are deliberate violations, by design.

## History (scratch, before the commit)

1. **First run (bench and checker as frozen):** the 8 negative cases passed, but the clean run reported 10
   `B5_PAYLOAD_COUNT` "extra word" violations. **Checker bug:** a payload handshake in the same cycle as `app_tx_error` was
   counted, although the bridge treats that cycle as a rejection. Fixed in the checker. Re-run: 10 / 10 PASS.
2. **The `late_accepted` mutant survived the first mutant pass.** **Bench weakness:** the clean traffic waited DRAIN + 20 cycles
   after every timeout, which hid a sender without the drain. That idle wait was removed (stronger stimulus; no check or count
   changed). Re-run: base 10 / 10 PASS; all three mutants re-run against the final bench (results above).
3. The checker's HEAD / payload withdrawal exceptions (timeout, `app_tx_error`) were added before the first run, after
   reading M-F1 rev 8 sec. 3 rule 6 and the bridge RTL (the bridge withdraws a held-off HEAD on its timeout).
4. Every scratch sim hit the known XSim start stall once and passed on the single retry; no result came from a stalled run.

## Open points for the main session

1. Registration (count 10; compile list `rtl/dual_lane/NOC_PKG.sv`, `rtl/riscv/tmem_app_bridge.sv`,
   `sim_riscv/app_port_checker.sv`, `sim_riscv/tb_app_port_checker.sv`; top `tb_app_port_checker`).
2. Binding into `cpu_tile_noc` / merged benches: the `TIMEOUT_CYCLES` / `RELEASE_CYCLES` parameters must match that
   build's `BRIDGE_TIMEOUT` / `LATE_DRAIN_CYCLES`.
3. The withdrawal exceptions (timeout, `app_tx_error`) are an interpretation of M-F1 rev 8 sec. 3 rule 6; if Lane 1 wants
   `app_valid` held strictly until `app_ready`, the bridge (not the checker) would have to change: a contract question.
