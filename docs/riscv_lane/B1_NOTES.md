# B1 / R2.1 notes: `tmem_app_bridge` (TMEM -> Lane 1 application port)

**Files:** `rtl/riscv/tmem_app_bridge.sv`, `sim_riscv/tb_tmem_app_bridge.sv`.

**Status:** scratch-level (XSim 2024.1), **not registered**. The main session registers the bench, with its count frozen,
before its first harness run.

**Specs:**
- docs/handoff/BRIEF_RISCV_LANE_v2_20261101.md sec. B1
- docs/decisions/M-F1-rev8-INTEGRATION-DRAFT.md sec. 3-6
- docs/riscv_lane/CPU_MEMORY_CONTRACT.md sec. 4-8
- types from `rtl/dual_lane/NOC_PKG.sv` (read-only)

## Behaviour (as built)

| Item | Implementation |
|---|---|
| TMEM grant | Same cycle as the request when idle (`gnt = IDLE && req`). Fields are latched at grant; one request at a time. |
| Exactly one response per grant | Every path ends in a one-cycle `rvalid`: LOCAL_ERR, RESP. The bench counts 1,017 grants = 1,017 responses. |
| Decode refusal | Error on the next cycle (bench: 1 cycle after the grant), with no network traffic, when any of these holds: `addr[31:28] != 2`, `addr[1:0] != 0`, `T = addr[27:24]` with `T != MEM_TILE`, `T >= 6`, or `T == TILE_ID`. |
| Remote instruction fetch | `tmem_is_fetch_i = 1` is refused on the same path as a decode refusal (error in 1 cycle, data 0, no network traffic, `last_err_kind` 1). Code fetched over the NoC would bypass the measured / attested IMEM. |
| Authorization | `authorized_i = 0` at grant gives a local error (1 cycle). `app_valid = (st == HEAD) && authorized_i`, so it is **never** high while unauthorized; there is also a simulation-only monitor. If authorization drops while the HEAD is still being offered: local error, no packet. |
| Request format | `app_destination = tile_to_coord(MEM_TILE)`. `app_message` is `MSG_MEM_WR_REQ` or `MSG_MEM_RD_REQ`. `app_control = {wstrb, 6'b0, 1'b0}` for writes, `'0` for reads. Payload word 0 = `{REMOTE_PREFIX_OUT, addr[27:2], 2'b00}`; word 1 = `wdata` (writes only). |
| Response | From `app_rx`: HEAD (`src` must be MEM_TILE, `msg` must be the matching RESP type, else error), optional data word, terminator (`app_rx_last`). An error comes from `control[10]` or from `app_rx_abort`. Read errors return 0. |
| Timeout | Counted from the moment the HEAD is offered. After `BRIDGE_TIMEOUT` cycles: error response. If the HEAD had been accepted, the bridge **drains**: no new grant, and `app_rx` traffic is discarded, until the late response's terminator / abort or `LATE_DRAIN_CYCLES`. A late response is never delivered and never matched to a later request. If the HEAD was never accepted (`app_ready` held low), there is nothing to drain. |
| Drain bound | Parameter `NI_SLOT_TIMEOUT` (default 8,192). Elaboration fails (`$fatal` in a generate block) if `LATE_DRAIN_CYCLES < NI_SLOT_TIMEOUT`: the NI can still deliver the late response until its slot timeout frees the slot. |
| `app_tx_error` | During HEAD: local error, no packet. During payload: error response. |
| Status outputs | `last_err_kind` (1 decode, 2 refused, 3 remote err, 4 timeout), `timeout_count`, `refused_count`: for the brief's NI-window status (B4 / B2 wiring). |

## Scratch results (XSim 2024.1, bench parameters `BRIDGE_TIMEOUT` 64, `LATE_DRAIN` 400)

**Unmutated (after the 2026-11-06 decisions): `RESULT : PASS`, 19 / 19 checks, 0 `Error:` lines.** (The earlier 18-check
version, commit 306d68ee, also passed 18 / 18.)
- **Write / read / byte lanes:** OK (`ca220044` after `wstrb` 0101).
- **Packet format:** HEAD `ctl` 0x780, `w0 = 0x2200_0100`.
- **Refusals:** unauthorized, T = 0 / 6 / 15 / self, and a remote fetch (`B1_FETCH_REFUSED`) each give an error in 1 cycle
  with 0 HEADs.
- **Remote error and abort:** both give `tmem_err`.
- **Timeout and ready held low:** error after 66 / 65 cycles.
- **Late response:** dropped while draining; the next read returned its own data.
- **Random requests:** 1,000, 0 mismatches.
- **Counts:** network HEADs 836 = expected 836; responses = grants = 1,017.
- **Unauthorized `app_valid`:** never high (0 cycles).

**Mutants (scratch, one RTL edit each, generated outside the repo, rerun against the 19-check bench): 5 / 5 killed. Each
run ended with `RESULT : FAIL` (no timeouts).**

| Mutant | Edit | Killed by (first `[FAIL]` lines) |
|---|---|---|
| `double_issue` | after a write response, go back to HEAD (the write is sent twice) | `B1_LATE_RESPONSE_IGNORED` (responses +3), `B1_RANDOM_1000` (43 mismatches), `B1_COUNTS` (HEADs 2,276 vs 836 expected) |
| `auth_removed` | `app_valid` no longer gated by `authorized_i`; both refusal branches disabled | `B1_REFUSED_UNAUTH` (err=0, HEADs +1), plus `B1_SVA_VALID_WHILE_UNAUTH` monitor lines |
| `late_accepted` | no DRAIN after a timeout (S_RESP always returns to IDLE) | `B1_LATE_RESPONSE_IGNORED` (second read err=0, data `aaaa0005` = the late response, responses +2): 19 checks, 1 error |
| `fetch_allowed` | fetch term removed from the decode refusal | `B1_FETCH_REFUSED` (err=0, HEADs +1, data `ca220044`), `B1_COUNTS` (HEADs 837 vs 836) |
| `lanes_swapped` | `wstrb` bit order reversed in `app_control` | `B1_BYTE_LANES` (data `11fe3301`), `B1_RANDOM_1000` (11 mismatches) |

**Drain-bound guard (negative test, elaboration only):** the bench with `NI_SLOT_TIMEOUT` = 401 > `LATE_DRAIN_CYCLES` = 400
fails `xelab` with the `$fatal` message (`VRFC 10-8279`).

Each scratch sim first hit the known XSim start stall and passed on the one retry; no result came from a stalled run.

## Bench design notes

1. **Two bench timing fixes before the first PASS.** The bridge RTL was never changed.
   - The late-response test first used a 60-cycle response latency for the follow-up read. With random backpressure that can
     exceed the 64-cycle timeout, so it is now 20.
   - The response-count baseline was sampled on the same edge as the previous response's counter update; it is now sampled at
     the next negedge.
2. `B1_LATE_RESPONSE_IGNORED` is built so that a bridge **without** the drain receives the late response while the second read
   is waiting. That is how the `late_accepted` mutant is caught.

## Decisions on the open questions (main session, VLSI review, 2026-11-06)

1. **Drain bound:** kept `LATE_DRAIN_CYCLES >= NI_SLOT_TIMEOUT`, now enforced at elaboration (new parameter `NI_SLOT_TIMEOUT`).
2. **Remote instruction fetch:** refused. Added check `B1_FETCH_REFUSED`; the frozen count went from 18 to 19 **before** the
   first run with it. Added mutant `fetch_allowed`.
3. **Status outputs:** left unconnected here; the main session wires them in B2 / B4.
