# M-F1 rev 8 (DRAFT): CPU tile integration contract

**Status: SIGNED by Kalash 2026-11-05 ("Sign rev 8", with D1 tiles 3 + 0, D2 64 bytes, D4 52k LUT, D6 NI slot timeout,
D7 BRIDGE_TIMEOUT 4,096). Drafted the same day (commit 02aa1424) before any dependent RTL. Binds the I-9 (integration) builds.**
Decisions taken (sec. 1): D1 = tiles 3 + 0; D2 = option (ii), K3_IMEM_LEN = 64 in the merged build, new vectors from the
teammate reference and re-qualification; D4 = 52,000 LUT merged; D6 = option (a); D7 = 4,096 (until E4 step 12 is accepted).
The remaining [OPEN: from package] items are filled from the RISC-V delivery by a numbered note, not a new revision,
unless they change a port or a wire format.
Items marked **[PROPOSED, needs Kalash]** are decisions; items marked **[OPEN: from package]** are filled in from the
RISC-V lane's delivery (expected 2026-11-06). Rev 7 and its amendments (`docs/decisions/M-F1-interface-freeze.md`) stay
binding; this revision is additive and is merged into that document only when signed.

**Scope:** connecting the RISC-V CPU tile package (`cpu_tile_noc`, brief v2 Part B) to the P7 subsystem
(`rtl/dual_lane/pq_noc_subsystem_p7.sv`) and building the merged top. This is Lane-1 step 4 of
`docs/proposals/PLAN_NEXT10_ALL_LANES_20261030.md`; it must be signed before the bridge co-simulation, the `app_rx` export
and the tile-2 memory front-end changes (steps 5 and 10).

**Basis:** the interface already sent to the RISC-V lane in `docs/handoff/BRIEF_RISCV_LANE_v2_20261101.md` sec. 1.3-1.5 and
B1-B3. This contract freezes that interface and adds Lane 1's own obligations. Where the brief and this draft differ, the
difference is listed in sec. 12.

---

## 1. Decisions needed before signing

| # | Decision | Proposal | Why it matters |
|---|---|---|---|
| D1 | CPU placement | **[PROPOSED, needs Kalash]** CPU A at tile 3 (attested), CPU B at tile 0 (never authorized). Tile 1 stays plain, no CPU. | Shows both admission (A writes memory after GRANT) and isolation (B is refused). A third CPU costs about +1.7k LUT plus a bridge (ESTIMATE). |
| D2 | What tile 3's measurement covers (security scope: HARD STOP item) | **[PROPOSED, needs Kalash]** a fixed IMEM window read at `MEAS_BASE` through the IMEM second read port, length = the provisioned K-3 value, frozen until the next attestation. The claim is stated exactly as "the first N bytes of IMEM at MEAS_BASE", not "the program". | See the K-3 conflict in sec. 7: today the endpoint is built `K3_IMEM_LEN = 16`, but brief B3 delivers 64 bytes. One of the two must change. |
| D4 | Merged-chip LUT ceiling | **[PROPOSED, needs Kalash]** 52,000 LUT for the merged top, routed timing at 20 ns as the real gate. 47,550 stays the subsystem bound. | Estimate after S4: subsystem 32.7k (N-13) + 2 CPU tiles about 3.4k + bridges and front end about 1-2k = about 37-38k (ESTIMATE, not measured). |
| D6 | NI slot leak on a suppressed response | **[PROPOSED, needs Kalash]** option (a) of sec. 6. | Without a fix, two revoked-in-flight requests leave the CPU's NI permanently out of slots. |
| D7 | `BRIDGE_TIMEOUT` | **[PROPOSED, needs Kalash]** 4,096 cycles until Engineer 4's step 12 worst-case model is accepted, then that value rounded up to a power of 2. | Must exceed the worst legitimate wait (sec. 5). |

## 2. Topology and ownership (frozen by this revision)

| Tile | Role | Owner of the logic |
|---|---|---|
| 0 | CPU B (plain, never authorized) | RISC-V lane (`cpu_tile_noc`, TILE_ID = 0) |
| 1 | plain, no CPU (app port tied off: `app_valid = 0`) | Lane 1 |
| 2 | memory: Lane 1 front end + RISC-V lane's plain BRAM macro | front end Lane 1; BRAM macro RISC-V lane |
| 3 | CPU A, shares its port with the attestation endpoint | RISC-V lane (`cpu_tile_noc`, TILE_ID = 3) |
| 4 | Root of Trust (verifier) | Lane 1 (unchanged) |
| 5 | untrusted injection port (attack tests; tied off in the demo top) | Lane 1 |

The bridge `tmem_app_bridge` is the RISC-V lane's (D3 revised 2026-11-01). Lane 1 owns everything inside
`pq_noc_subsystem_p7` and the merged top.

## 3. TX: CPU -> subsystem application port (frozen as brief sec. 1.3)

Per tile g: `app_valid/app_ready`, `app_destination` (`coord_t`), `app_message` (`msg_type_e`), `app_control[10:0]`,
`app_payload[31:0]`, `app_payload_valid/app_payload_ready`, `app_tx_error`, `authorized`. No change to these ports.

Rules (from the RTL, binding on the bridge):
1. `app_message` is only `MSG_MEM_RD_REQ` (0) or `MSG_MEM_WR_REQ` (2). Types 4-7 never come from a CPU.
2. `app_control[0]` (tag) is driven 0; the NI owns it. Writes put `wstrb` in `[10:7]`; reads drive `'0`.
3. Payload: write = address, data (2 words); read = address (1 word). Address `A[31:28] = 4'h2`, `A[27:24] = 2`,
   `A[1:0] = 2'b00` (M-F1 sec. 5a.2-5a.3).
4. **Never raise `app_valid` while `authorized[g] = 0`.** The gate holds `app_ready` low and counts a fault every cycle
   `app_valid && !allowed`. The bridge refuses locally; the gate stays the enforcement point.
5. One request at a time per CPU (the NI allows 2; the bridge uses 1).
6. Tile 3: `app_ready[3] = 0` while the endpoint owns the port (about 1.2k cycles per attestation). This is a normal wait,
   covered by `BRIDGE_TIMEOUT`.

## 4. RX: new `app_rx` bundle (wire change; Lane 1 obligation)

Today `rready` is tied to 1 and NI RX data is not exported, so a CPU cannot receive read data. Lane 1 adds, per tile g,
as new **outputs** of a new subsystem variant (`rtl/dual_lane/pq_noc_subsystem_p7_i9.sv`, the production-style
`pq_noc_subsystem_p7.sv` is not edited):

| Signal | Width | Meaning |
|---|---|---|
| `app_rx_head_valid[g]` | 1 | HEAD of a response to tile g |
| `app_rx_src[g]` | `coord_t` | source tile |
| `app_rx_msg[g]` | `msg_type_e` | `MSG_MEM_RD_RESP` (1) or `MSG_MEM_WR_RESP` (3) only |
| `app_rx_control[g]` | 11 | `[10]` = err; `[0]` = tag (informational) |
| `app_rx_data[g]`, `app_rx_data_valid[g]` | 32, 1 | RDATA (reads) |
| `app_rx_last[g]` | 1 | terminator accepted |
| `app_rx_abort[g]` | 1 | packet aborted: the bridge treats it as an error |

- The bridge is always ready (no RX backpressure); the subsystem keeps `rready = 1` for CPU tiles.
- Only memory responses are exported. Control types (4-7) and anything at tiles without a CPU stay internal.
- Tile 3: responses are routed to the CPU only for types 1/3; the endpoint keeps types 4-7 as today.
- All existing outputs and their values are unchanged; the 36 project benches and the registered P7 jobs must still pass
  with their frozen counts on the new variant (re-run, not re-frozen).

## 5. Error mapping and timeouts

| Situation | Subsystem behaviour | Bridge returns |
|---|---|---|
| Authorized, legal address, response arrives | commit / read | success (with RDATA for reads) |
| Not authorized when the request is issued | nothing sent | `tmem_err` within 2 cycles |
| T != 2, T >= 6, self-address, `A[31:28] != 2` | nothing sent | `tmem_err` within 2 cycles |
| Address outside the memory window (fault 13) | response with err (`control = 0x400`) | `tmem_err` |
| Revoked between issue and side effect (F4 / Q2) | write: no commit; read: response suppressed, never zero-filled | `tmem_err` on timeout |
| `app_ready` never comes | gate refusal or busy port | `tmem_err` on timeout |
| `app_rx_abort` | aborted response | `tmem_err` |

**One timeout owner:** only the bridge times out (`BRIDGE_TIMEOUT`, D7). The adapter/core has none. After a timeout the
bridge drops any late response to that request and takes no new request until idle.

**Worst legitimate wait** (to be computed by Engineer 4 step 12, then frozen here): tile-3 port held by an attestation
(about 1.2k cycles) + NI store-and-forward + mesh round trip + front-end service. `BRIDGE_TIMEOUT` must exceed it with
margin and must stay below `VERIFIER_TIMEOUT` (100,000) so a CPU fault never looks like an attestation timeout.

## 6. NI slot leak (Lane 1 obligation, D6)

Today an NI slot is freed only by the matching response (`noc_network_interface_p7.sv:719-760`). A suppressed response
(revoked in flight) holds the slot forever; after two, the CPU's NI accepts nothing.

- **(a) PROPOSED:** an NI request timeout `NI_SLOT_TIMEOUT` (> `BRIDGE_TIMEOUT`) frees the slot and arms a per-slot
  "stale" flag; a late response carrying that slot's tag is dropped by the NI and counted. No wire change; security
  semantics of F4 / Q2 unchanged (the response is still suppressed at the memory).
- (b) alternative: the memory front end answers a revoked request with an err response instead of suppressing it. This
  changes the Q2 rule ("suppressed, never zero-filled") and is a security-semantics change: not proposed.

Verification: a bench with two revoked-in-flight requests followed by an authorized one that must succeed; a mutant with
the timeout disabled must hang (killed by the bench's completion check, not by the global timeout).

## 7. Measurement path (D2) and the K-3 conflict

- Endpoint today: `imem[511:0]`, `imem_len[6:0]` runtime inputs; built `K3_ENFORCE = 1`, `K3_CONFIG_LEN = 16`,
  `K3_IMEM_LEN = 16`. A challenge with a different `imem_len` is answered status 5 (MALFORMED) and the verifier fails
  closed (I-6 K-3).
- Brief B3 asks the RISC-V lane for a 16-word (64-byte) reader with `meas_imem_len_o = 64`. **Connected as is, every
  attestation of tile 3 would fail with status 5.**
- Options **[needs Kalash]**:
  - (i) keep the signed K-3 profile: the reader delivers 64 bytes, the merged top connects `imem_len = 16`, and the claim
    is "the first 16 bytes of IMEM at MEAS_BASE". No RTL or bound change. Weak claim (16 bytes is 4 instructions).
  - (ii) re-provision K-3 to 64 / 16 (`K3_IMEM_LEN = 64`) in the merged build: a change to a provisioned constant, needs new
    expected vectors from the teammate reference (TILE_KEY_BYTES = 32 profile, 64-byte IMEM) and re-qualification of the
    endpoint, full-chain and SEC-matrix jobs. Claim "the first 64 bytes".
  - (iii) full-IMEM (16 KB): new reference profile, M-F1 revision, new vectors, re-qualification; out of scope for this
    release.
- Recommendation: (ii) if the demo's measured code fits in 64 bytes at MEAS_BASE (a boot stub that jumps to the
  application); otherwise (i) with the claim stated exactly.
- `config_data` source **[OPEN: from package]**: the CPU tile's TILE_ID / BUILD_ID words (brief A6), 16 bytes.

## 8. Attestation signals between the CPU tile and the subsystem

**[OPEN: from package]**, confirmed against `cpu_tile_noc`'s port table:
- `authorized_i` <- `authorized[g]`;
- `grant_done_i` <- tile 3's GRANT accepted (subsystem output to be named; proposal: rising edge of `authorized[3]`);
- `attest_failed_i` <- verifier `failed` for tile 3;
- `attest_req_o` -> verifier start (today the verifier starts from the RoT side; whether the CPU may request attestation
  is a policy question: **[needs Kalash]**, proposal: the CPU may request, the RoT decides; repeated requests rate-limited
  by the verifier being busy);
- `meas_imem_o`, `meas_valid_o` -> endpoint `imem`; `imem_len` per sec. 7.

## 9. Tile-2 memory front end (Lane 1) and BRAM macro (RISC-V lane)

- The front end keeps every rule it has today: F4 (write decided at the final data acceptance), Q2 (read rechecked when the
  response HEAD is first offered), fault 6 / 13 records, `mem_faults`, `memory_commits`, the 0x2 window and M-F1 sec. 5a.
- Change: today the subsystem holds the memory state itself (`memory_last_data`, commit counter). The merged variant puts
  the RISC-V lane's BRAM behind the front end: one read/write port, word-addressed, `wstrb` byte enables, read latency
  **[OPEN: from package]** (1 cycle expected for BRAM). Window size = the macro's size (16 KB proposed, `OFF < 0x4000`).
- Nothing reaches the BRAM except through the front end.

## 10. Merged top, clock and budget

- One clock, 20 ns, synchronous active-high reset (no CDC; no clock or pin change beyond D5-BOARD's MMCM 100 -> 50 MHz).
- Two tops, as for P7: an accurate-area top (exports kept through the N-13 shift-chain/MISR method) and a board demo top
  (Arty A7-100T, D5-BOARD pins plus UART TX for the CPUs).
- Synthesis flow: the S4 flow (mesh split S4-F3, F1/F2 elsewhere). The CPU tiles synthesize with the same F1/F2 settings
  unless their OOC numbers show a loss.
- Gates: LUT <= D4 ceiling, WNS / WHS >= 0, TNS / THS = 0, check_timing clean, 0 route / DRC errors. A timing FAIL is a
  HARD STOP.

## 11. Evidence (jobs frozen in `scripts/dual_lane_jobs.json` before their first run)

| Job (proposed) | What it shows | Counts |
|---|---|---|
| `i9_rx_export` | new subsystem variant: all 54 S4 benches pass unchanged on it | as frozen today |
| `i9_slot_leak` + mutant | sec. 6 | frozen at registration |
| `i9_bridge_cosim` | `cpu_tile_noc` x 2 on the real subsystem: write, read, refusal at tile 0, err response, revoke in flight, port busy during attestation | frozen at registration |
| `i9_demo` | merged top in XSim: boot, attest tile 3, CPU A writes and reads memory, CPU B refused, REVOKE, CPU A refused after REVOKE | frozen at registration |
| `i9_merged_pnr`, `i9_n13` | merged area / timing | gates above |

Engineer 4: bridge oracle (step 8) and bridge golden vectors (step 15) are built from sec. 3-5 of this contract.

## 12. Differences from brief v2 that the RISC-V lane must apply

1. `REMOTE_PREFIX_OUT` default is `4'h2` (I-6 is done; the `4'h8` stand-in is gone).
2. `meas_imem_len_o` per sec. 7 (16 or 64, after D2).
3. `BRIDGE_TIMEOUT` per D7.
4. `app_rx_abort` and `app_rx_control[10]` both map to `tmem_err`.

## 13. What does not change

Wire formats, message types and lengths, freshness, MAC, VC mapping, the authorization rules (R7.4, F4, Q2), the I-6
fault codes, the signed arbiter and REVOKE bounds, the protected router / mesh RTL, the device, the clock.

HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.
