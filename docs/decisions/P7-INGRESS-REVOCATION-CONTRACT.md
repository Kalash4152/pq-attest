# P7 ingress, revocation and integration contract (S1 + S2)

**Source:** Kalash Bheda, 2026-10-21, `docs/reviews/CC_INSTRUCTION_S1_S2_FINAL_20261021.md` (signed contract; it decides Codex
review items A1-I2 and findings B3/C3/B1/B4/D1). Sections 1-11 are copied verbatim below. The hard stops (sec. 12 of the source)
are in CLAUDE.md and the source file. M-F1 amendments: R7.5b (ingress) and R7.7b (D2 wait graph); DECISION_REGISTER Q1-Q6.

---

## 1. Ingress (R7.5b): replaces the D1 implementation (Q1)

**Delete the zero-TAIL injection (`G_TAIL`, `noc_ingress_guard.sv`) entirely.** Nothing incomplete or fabricated
may ever enter the mesh.

### 1a. Untrusted port: the raw injector at tile 5 → `noc_ingress_quarantine` (store-and-forward)

- **Storage:**
  - a FIFO of **depth 32** (≥ 26 maximum packet) in LUTRAM;
  - **reset only the pointers and valid bits, never the array**;
  - commit pointer ≠ write pointer, so an uncommitted partial packet is discarded by rolling back the write pointer.
- **HEAD validation** (the first flit of a packet must be HEAD or HEAD_TAIL; anything else is a stray, consumed and counted as
  reason 11):
  - src == this port's coordinate (else reason 9);
  - msg_type legal in P7;
  - dest inside the mesh;
  - header length field == P7 `message_length(type)` (R7.1);
  - `vc_id == message_to_vc(type)`;
  - HEAD_TAIL only for length-1 types.
- **Continuation checks** (any failure → discard the whole buffered packet, reason 11, then resync: consume until the next
  HEAD):
  - flit type BODY/TAIL only (a **nested HEAD/HEAD_TAIL → discard**);
  - `vc_id` equal to the HEAD's;
  - TAIL exactly at flit `length` (early TAIL → discard; no TAIL by `length` → overlong → discard).
- **Gap discard (internal watchdog):**
  - counter `gap` increments **only** while a packet is partially buffered **and** `in_valid == 0` **and** the quarantine
    can accept (`in_ready == 1`);
  - it **resets on every accepted flit**;
  - at `gap == W_Q` (= 64, parameter, counter width `$clog2(W_Q+1)`) → discard the partial packet, reason 10.
  - The sum of gaps doesn't matter, because length is capped, so no wall-clock limit is needed: nothing enters the mesh
    before the packet is complete.
- **Forwarding:** only **complete, validated** packets, from the FIFO head, back to back as the mesh accepts.
- **Counters:** `q_rejected[reason]`, `q_forwarded`, `q_discarded`.

### 1b. Trusted ports (NI-driven, every local port including tile 5's NI) → a non-buffering `noc_ingress_parser`

- **On every HEAD:**
  - source check (reason 9) and the type/length/VC checks above (reason 11);
  - on failure, consume the whole packet (count flits to its header length) and forward nothing.
  - Return a credit/ready for every consumed flit; if the local interface uses credits, emit the credit returns so the
    NI's balance stays exact.
- **Mid-packet (a trusted NI is qualified by N-8.1 and re-earned in §9):**
  - SVA + fault counter for nested HEAD, VC change, overlong or early TAIL;
  - **no recovery and no fabricated flit.** A violation here is an NI fault, outside the threat model, and it's flagged.
- **No watchdog on trusted ports.** The NI's own W (N-8.1) bounds its packets.

### 1c. Tile-5 merge

The quarantine output and the tile-5 NI parser output share the local router input through a **packet-atomic
round-robin mux**: the owner is locked from HEAD handshake to TAIL handshake. The quarantine only offers complete packets,
so it can never hold the input.

### 1d. Tests (counts frozen from source; each with a mutant)

| Test | Expected |
|---|---|
| forged src on raw / on NI | reason 9, zero delivery, credits balanced |
| nested HEAD (same VC and cross-VC, incl. a forged src = 4 HEAD inside a legal VC0 packet) | reason 11, zero delivery |
| mid-packet HEAD_TAIL, VC change, early TAIL, overlong, endless BODY, stray BODY/TAIL | reason 11, discarded, resync to the next legal packet |
| withheld TAIL (raw) for 10k cycles while RoT sends REVOKE | reason 10, mesh never holds the route, REVOKE delivered |
| missing final write-data flit (raw) | discarded, **no memory commit**, no zero write |
| gap counting: all 4 valid/ready combinations | the counter advances only for (`valid=0`, `ready=1`) mid-packet |
| legal traffic on every port | delivered unchanged |

Mutants: no nested-HEAD check (the src = 4 spoof reaches tile 3 → killed); gap counts `!valid` regardless of ready
(a legal congested packet gets discarded → killed); no length cap (endless BODY never discarded → killed);
partial forwarding (forwards before complete → the route-hold test fails → killed).

---

## 2. Verifier revocation (Q3, Q5): `pq_rot_verifier.sv` (rtl/dual_lane)

- **Pending revoke latch:**
  - `pending <= pending | (revoke & !revoke_q)`, one per rising edge (Q3);
  - **cleared when the REVOKE packet's request handshake occurs** (`vs == V_REVOKE && tx_ready`);
  - an edge arriving while in V_REVOKE before acceptance merges into it.
- **Interface rule:** once `tx_valid` is asserted, valid **and** msg_type stay stable until `tx_ready` (no withdrawal).
  An accepted request always gets its complete payload.

| State | Rule |
|---|---|
| V_IDLE | `pending` → V_REVOKE (wins over a new `start`) |
| V_KSTART | child start issued this edge → go to V_KWAIT (no suppression) |
| V_KWAIT | wait for `kd` (drain); then `pending` → V_REVOKE (discard the result), else V_REQ |
| V_REQ | **never leave without a handshake.** `tx_ready` → V_FILL even if pending |
| V_FILL | send all 7 words; after word 6: `pending` → V_REVOKE, else V_WAIT |
| V_WAIT | `pending` → V_REVOKE; `collecting <= 0`; later response flits are consumed and discarded by RX |
| V_CHECK | `pending` → V_REVOKE (wins over success) |
| V_TSTART | → V_TWAIT (child start issued) |
| V_TWAIT | wait for `td` (drain); `pending` → V_REVOKE (wins over tag success) |
| V_GRANT | hold valid; on `tx_ready`: `grant_done`, then `pending` → V_REVOKE else V_IDLE. GRANT→REVOKE stay ordered (same VC and path). Check `pending` before **entering** V_GRANT. |
| V_REVOKE | hold until `tx_ready`; clear `pending`; → V_IDLE |

- **Timeout and `rx_abort`** set `failed` and `pending`, and obey the same drain rules: never cut V_FILL, V_REQ or
  V_GRANT mid-transfer.
- **Tests:** a revoke edge in **every** state; same-edge combinations (revoke + `tx_ready` in V_REQ/V_GRANT, revoke + `kd`,
  revoke + `td`); held revoke for 10k cycles produces exactly 1 REVOKE; a timeout during V_FILL; `rx_abort` during V_WAIT.
- **Mutants:** cancel in V_REQ without handshake (truncated challenge detected → killed); level-triggered revoke
  (more than 1 REVOKE → killed); success wins over pending in V_CHECK (GRANT after revoke → killed).

---

## 3. Ownership and memory boundaries (F3/F4, Q2)

- **TX owner register at tiles 2 and 3:**
  - set at the HEAD handshake, held until the last payload handshake (the count comes from `message_payload_flits`);
  - the mux selects only the owner;
  - when idle: endpoint (tile 3) or memory-response (tile 2) has priority over the application at **packet boundaries
    only**.
- **RX destination latch at tile 3:** the L2 replay goes to endpoint or app, latched from HEAD to end.
- **Write commit:** authorization is evaluated in the **same cycle as the final write-data acceptance**, using
  `authorized[src]` of that cycle. If `authorized = 0` that cycle → no commit, a fault is counted, and the write response
  is suppressed. The revocation boundary is the first cycle with `authorized[src] = 0`.
- **Read disclosure (Q2):**
  - authorization is rechecked in the cycle the MEM_RD_RESP HEAD is first offered;
  - revoked → the response is **suppressed** (never zero-filled) and the requester's slot retires through its existing
    N-8.1 timeout;
  - once the HEAD is accepted, the response completes.
- **Tests (Codex D4 stimuli):**
  - application request accepted, payload paused, then a challenge arrives and the endpoint wants TX → the application
    packet finishes first;
  - revoke swept from −5 to +5 cycles around the write commit, including the same edge;
  - read revoked before enqueue, between enqueue and HEAD offer, and after HEAD acceptance;
  - tile-2 application vs memory response.
- **Mutants:** an owner switch mid-packet (deadlock/timeout detected → killed); authorization sampled at HEAD (write after
  revoke → killed); response not suppressed (read data after revoke → killed).
- The P7 refusal of old tile-2 paths: adapt those cases and document why; never fake the old path.

---

## 4. Peer slot / D2 (R7.7b): corrected argument and accounting

- **Wait graph to write down, with every edge bounded separately:**
  1. peer collection from the mesh: bounded by trusted senders, the quarantine (§1) and NI W;
  2. preceding pass-through data in the wrapper: bounded by length ≤ 26 plus an always-ready consumer;
  3. engine service: P ≤ 269 + J;
  4. replay into the NI/endpoint/gate: always-ready consumer.
  The engine is released before TX waits on the mesh. Write this down; there is no claim of "no mesh dependency".
- **SVA:** the tile-3 control consumers (endpoint, gate, app RX) have `ready == 1` always. If any becomes conditional,
  that's a HARD STOP.
- **Accounting:** `peer_accepted`, `peer_replayed`, `peer_rejected`, `peer_hold_max`. Invariant at quiescence:
  accepted == replayed + rejected. SVA: hold ≤ **H_MAX = 512** cycles (report the measured maximum).
- **Mutant:** busy-peer drop restored → **the tile stays authorized after REVOKE** (observable security failure) → killed.

---

## 5. Shared L2 engine (Q4) and reset

- **Key:** latch the directed key **atomically with the owner/length at grant**; the transcript is read from the
  wrapper's buffer, which must stay stable until `done` (SVA, A1).
- **Vectors:** from `l2_golden.py` (ZIP `kmac128`, guard 31fb455) for every P7 transcript: CHALLENGE 52 B, RESPONSE 88 B,
  GRANT/REVOKE 24 B, both directions (TX MAC and RX verify). Expected tags come only from Python.
- **Tests:**
  - four distinct transcripts and keys, simultaneous and back-to-back;
  - each requester receives exactly its tag, exactly once;
  - per job, measure grant → consumed completion; assert **J ≤ 128** and **OVH ≤ 4** under four-requester contention;
    report the measured P/Q maxima (≤ 269 / ≤ 792).
- **Mutants:** owner select, completion routing, a transcript read one cycle off, key read live instead of latched
  (provisioning changed mid-job), all killed.
- **Reset:** one top-level reset bridge (asynchronous assert, 2-FF synchronous deassert) feeds every block, including the
  async-reset generated `pq_kdf_xk`. Arbiter grants are masked during reset.
  Tests: reset at grant, at load indices 0/11/21, at each permutation boundary and at completion → no stale
  `done`/tag/authorization afterwards.

---

## 6. Area and timing

- **RAM inference:** every slot/FIFO/transcript array is coded without content reset. Verify in `util_hier` that they map
  to RAM32M/RAM64M (LUTRAM); otherwise fix the coding before going further.
- **First full-subsystem OOC with all real logic retained** (engine, wrappers, quarantine, parsers, gates, consumers;
  **no stubs**):
  - LUT ≤ 47,550, 0 latches, DRC 0, hierarchy check, RAM inference check (the judge enforces the ceiling);
  - a stub result may only appear labelled "diagnostic lower bound".
- **Over budget → fallbacks in this order, measured each time:** fix RAM inference → remove duplicated transcript/storage
  logic → trim unused plain-NI features. **Credit no saving for already-shared crypto.** Any serialized-crypto redesign
  needs Kalash.
- **Timing:**
  - parsers start combinational;
  - if the integrated mesh/ingress path has WNS < +0.1 ns, insert an elastic skid buffer (ready/valid stable, credits and
    ownership preserved) and rerun the hop/latency tests.
- **Integrated place & route checkpoint** (the full P7 subsystem, 20 ns, I/O budgets as in the OOC flow):
  WNS/WHS/WPWS ≥ 0, TNS/THS = 0, route errors 0, blocking DRC 0, `check_timing` with 0 unconstrained endpoints.
  Report LUTRAM and control sets.

---

## 7. C4 REVOKE latency (Q6)

- **Measure from:** the first sampled `revoke` rising edge with `authorized[3] = 1`. **To:** the first sampled
  `authorized[3] = 0`.
- **Scenarios (max over all):** idle; a revoke edge in every verifier state (including V_REQ blocked by backpressure,
  mid-V_FILL, V_GRANT pending, crypto active); saturated VC0/VC1 data from every NI; raw-port withheld TAIL / endless
  BODY / nested HEAD; peer slot occupied; tile-3 RESPONSE in the engine (Q contention); held revoke.
- **Pass:** max ≤ **1,500** cycles (target). Report the full component breakdown from the trace. Measured above 1,500
  → HARD STOP (never re-derive the bound to fit).

---

## 8. S2 / I-5 matrix (registry IDs, frozen counts, expected reason, one effective negative control each)

| Attack | Mechanism | Negative control (must make the attack succeed observably) |
|---|---|---|
| payload/tag corruption, wrong key | MAC | MAC compare disabled |
| header-field mutation | transcript binding | the field omitted from the transcript |
| wrong peer/source (valid MAC recomputed) | identity (reason 5) | identity check disabled |
| wrong dest/VC/type | structural checks | that one check disabled |
| duplicate/old sequence | replay state | sequence compare/update disabled |
| old epoch, reset replay | epoch | epoch compare disabled |
| sequence zero/wrap/exhaustion | sequence lifecycle | the forbidden transition allowed |
| short/overlong control packet | framing | that length boundary disabled |
| flood / occupancy | peer hold, rate limit (reason 6) | drop restored / rate limit disabled |
| data-source spoof | ingress source (reason 9) | source check disabled |
| nested-HEAD spoof, incomplete raw packet | quarantine (reasons 10/11) | framing / length / gap disabled |

- **Rejected control packets:** zero trusted delivery and zero slot retirement (assertion + counter).
- **Plain-data aborts:** N-8.1 retirement allowed.
- Make sure each identity mutant fails through the identity check, not through MAC; the expected reason is asserted.
- Also measure: authentication latency per message type, and engine contention (P/Q maxima).

---

## 9. Re-earn versus reuse (A4, G5)

- **Re-run on P7** (new evidence):
  - N-8.1 containment adapted to P7;
  - framing;
  - F2–F4;
  - authorization;
  - N-7.5 finite liveness;
  - a NOC-2 subset (uniform and hotspot at 1/64, 1/8, 1, in both MAC modes; plus the hop probes);
  - all synthesis.
- **Re-adjudicate only** (identical source closure, parameters, vectors and tool): the KMAC/SHA3 KATs, s8_golden and
  mutants, the arbiter jobs, endpoint unit, the exclusivity jobs.
- Old results stay as history and are never relabelled as P7 qualification.

---

## 10. Claims (H1/H2): use these words in STATUS, the reports and the paper

> P7 authenticates the supported control traffic between its provisioned peers and rejects the tested replay, identity,
> epoch and integrity violations before trusted control delivery. This assumes trusted keys, NIs, routers and links, with
> untrusted injection confined to guarded local ports. Plain data packets do not receive cryptographic integrity
> protection. Guarded raw-port containment and bounded control progress apply only under the tested framing, reset and
> resource assumptions. Physical attacks, compromised trusted routing logic, key extraction and arbitrary malicious
> behavior by an authorized endpoint are outside this claim. S2 alone does not establish final end-to-end authorization
> closure or routed FPGA timing.

The raw port is "an untrusted protocol-level local injector". Remove any "all packets authenticated", "deadlock-free
under arbitrary traffic" or "FPGA closed" wording before the matching gate passes.

---

## 11. Execution order (continue automatically through every PASS)

1. §0 (baseline, contract, hang fix).
2. §5 engine qualification + §2 verifier + §3 boundaries + §1 ingress RTL, each with its tests and mutants.
3. Compile-check every bench → **one** registry regeneration → `test_dual_lane.py` + preflight → commit.
4. Run the S1 jobs one at a time → §4 accounting → §7 C4 → §6 OOC → §6 P&R checkpoint.
5. Write the S1 gate report. On PASS → §8 S2 matrix + §9 re-earn → I-5 gate report → continue to I-6 per the earlier
   plan (C-1/C-2 retry, `noc_fault_status`, trusted fail/timeout/clear, the 0x2 map, K-3 binding).
6. Every gate report gives: commit and source identity; accepted/fresh/reused/failed/invalid/not-run jobs with run IDs;
   measured LUT/LUTRAM/WNS/WHS; the C4 maximum; P/Q/J maxima; blockers; the next dependency.

---
