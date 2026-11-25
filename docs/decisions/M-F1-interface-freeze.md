# M-F1 — NoC Interface Freeze

**Status:** rev 8 (integration: CPU tiles, app_rx, NI slot timeout, memory front end) SIGNED by Kalash 2026-11-05 in `docs/decisions/M-F1-rev8-INTEGRATION-DRAFT.md`; it adds to rev 7 and changes no existing value. rev 6, 2026-10-19 (rev 7 SIGNED by Kalash 2026-10-20 with conditions C1–C4, section "Rev 7 amendments"; binds P7 builds). **SIGNED by Kalash 2026-10-19 ("rev 6 approved") as the DECISION freeze.** Rev 6 is additive and is
confined to the "Rev 6 amendments" section at the end of this document; it binds P6 (rtl/dual_lane) builds, rev 5 binds production builds.
Rev 5 status line, preserved verbatim: "rev 5, 2026-09-30. **SIGNED by delegation** (see §14). Binding for all NoC-lane work from this revision."
**Rev 5** adds §5a (remote memory access semantics: payload words, byte lanes, target window, err rules, target obligations)
for Lane 2 (processor tile). Additive: no existing transport value changes. The S-8 attestation width decision (HANDOFF
2026-09-26 C1.1) is NOT part of rev 5.
Rev 4 (2026-09-25) applied AM-1..AM-6 from N-8.1 architecture rev 1.
**Scope:** the NoC lane interfaces other work builds on: N-8 traffic, N-9/N-10 MAC and enforcement, S-8 attestation protocol, N-14 SoC.
**Source of truth (RTL baseline): commit `acd1f73`** on branch `noc/credit-integration`. That is the RTL the N-2.5 MF1 gate (reports/n25_mf1_2026-09-25, gate HEAD `acd1f73`) and the XSim mf1 regression ran on. Commit chain: `9251bab` (values first read) → `111f0a5` (+ I-3 check, the only RTL change) → `acd1f73` (docs) → later commits are docs/logs only (`git diff --stat acd1f73 HEAD -- NOC_PQATTEST.srcs synth` is empty). Any RTL change after `acd1f73` voids this freeze until the mf1 regression and the N-2.5 gate are re-run.

---

## 1. Topology (frozen)

| Item | Value | Source |
|---|---|---|
| Mesh | 3 × 2, 6 tiles, 5 ports/router (N,S,E,W,LOCAL) | `noc_pkg` MESH_X/Y, NUM_PORTS |
| Port encoding | N=0, S=1, E=2, W=3, LOCAL=4, PORT_NONE=7 | `port_e` |
| Tile map (id → x,y) | CPU0 0→(0,0) · CPU1 1→(1,0) · MEMORY 2→(2,0) · CRYPTO 3→(0,1) · RoT 4→(1,1) · SPOOF 5→(2,1) | `tile_to_coord` |
| Tile index | i = y·MESH_X + x | `noc_mesh_3x2` GEN_R |
| Routing | XY, deterministic | M5 `noc_xy_routing` |
| Switching | wormhole (HEAD acquires, TAIL releases, HEAD_TAIL single-flit) | M7 `allocator.sv` |

## 2. Flit format (frozen)

`flit_t` = 36 stored bits, and there is **no valid bit in the flit**. Validity belongs to the transfer (L-05).

| Field | Bits | Encoding |
|---|---|---|
| `flit_data` | 32 | payload, or the head word below |
| `flit_type` | 2 | HEAD=0, BODY=1, TAIL=2, HEAD_TAIL=3 |
| `vc_id` | 2 | 0=REQUEST, 1=RESPONSE, 2=ATTESTATION, **3 = illegal** |

**Head word** (`head_flit_t`, packed, MSB first):

| Bits | Field | Width |
|---|---|---|
| [31:29] | dest_x | 3 |
| [28:26] | dest_y | 3 |
| [25:23] | src_x | 3 |
| [22:20] | src_y | 3 |
| [19:16] | msg_type | 4 |
| [15:11] | length (total flits incl. head, incl. MAC) | 5 |
| [10:0] | control (overlay by message class) | 11 |

The `control` field has four overlays. They share bits, so which one applies depends on the message:

| Message class | Fields |
|---|---|
| mem write request | wstrb [10:7] |
| mem response | err [10] |
| attestation | status [10:7] |
| transaction tag (memory messages) | tag [0] |

## 3. Virtual channels (frozen)

- **3 VCs per port, 4 flits each** (VC0/1/2_DEPTH = 4).
- **VC class is fixed by message type** (`message_to_vc`):

  | Message type | VC |
  |---|---|
  | MEM_*_REQ | REQUEST (0) |
  | MEM_*_RESP | RESPONSE (1) |
  | ATTEST_* | ATTESTATION (2) |

- **A flit keeps its VC on every hop.** There is no VC reallocation: M9 uses `selected_vc = xbar_sel % NUM_VC`.
- ⚠ **VCs isolate buffers, not output links.** See FD-1 in §10.

## 4. Message types (frozen for ids and lengths)

`MAC_FLITS` = 0 today because `MAC_ENABLE` = 0.

| id | msg_type | VC | payload flits | total length (MAC off) |
|---|---|---|---|---|
| 0 | MEM_RD_REQ | REQ | 1 | 2 |
| 1 | MEM_RD_RESP | RESP | 1 | 2 |
| 2 | MEM_WR_REQ | REQ | 2 | 3 |
| 3 | MEM_WR_RESP | RESP | 0 | 1 (HEAD_TAIL) |
| 4 | ATTEST_CHALLENGE | ATT | 5 (160 bits) | 6 |
| 5 | ATTEST_RESPONSE | ATT | 16 (512 bits) | 17 |
| 6 | ATTEST_GRANT | ATT | 0 | 1 |
| 7 | ATTEST_REVOKE | ATT | 0 | 1 |

- 8–15 are reserved. **(rev 4, AM-5)** A reserved msg_type is rejected: NI TX raises `tx_error` and sends nothing; NI RX
  consumes it as a framing error (HEAD → discard to terminator, HEAD_TAIL → back to idle). Until N-8.1 RTL lands, the RTL still
  maps them to VC0 / length 1 (known gap, N-8.1 Gap C).
- **(rev 4, AM-6)** A HEAD whose length field ≠ `message_length(msg_type)` is rejected and consumed to its terminator, never delivered.
- With MAC on, every packet grows by 4 flits (128-bit tag). MAX_PACKET_FLITS = 21, which fits the 5-bit length field.

## 5. Transaction tags (frozen)

- **Up to 2 outstanding remote memory transactions per NI** (`N_OUTSTANDING` = 2).
- **The tag is 1 bit, carried in `control[0]`.**
- **The NI (M10) allocates the tag; the CPU does not.** A response must echo its request's tag.

## 5a. Remote memory access semantics (frozen, rev 5)

Evidence base: payload order was already exercised by `tb6_1.sv` (N-6, 126/0). Everything else in this section was
unspecified before rev 5 and is decided here. Tiers in the Lane-2 contract: [F] = frozen before rev 5, [R5] = frozen by rev 5.

**5a.1 Initiator decode** (M11 `noc_addr_decoder`, unchanged [F]). `addr[31:28]==4'h2` is remote, tile = `addr[27:24]`.
Tile >= 6, self-addressed remote, and any address outside §6 give `bus_error`: **no packet is ever sent** for them.

**5a.2 Payload words** ([R5], matches tb6_1):

| Message | word 0 | word 1 | control |
|---|---|---|---|
| MEM_RD_REQ | A = full 32-bit address as issued by the CPU (incl. `0x2`, tile bits) | - | `wstrb` = 0 |
| MEM_WR_REQ | A = full 32-bit address | WDATA | `control[10:7]` = wstrb |
| MEM_RD_RESP | RDATA | - | `control[10]` = err |
| MEM_WR_RESP | (HEAD_TAIL, no payload) | - | `control[10]` = err |

`control[0]` = tag, allocated by the requester's NI and echoed by the responder ([F] §5).

**5a.3 Byte lanes** ([R5]). Little-endian, project convention: byte i = bits `[8i+7:8i]` of WDATA/RDATA, and `wstrb[i]`
enables byte i. Data travels in its natural lane (no shifting on the wire). `A[1:0]` must be `2'b00`: accesses are
word-addressed, as PicoRV32's native memory interface issues them. Reads always return the full 32-bit word.

**5a.4 Target interpretation** ([R5]). The remote window of every tile is its **data memory only**:
- `OFF = A[23:0]` is a **byte offset from the start of the target's data memory**. For a processor tile, `OFF` = the local
  address `LOCAL_DMEM_BASE + OFF` (so remote `0x2T00_0100` = tile T's local `0x0000_4100`).
- Window size = the target's data-memory size: **16 KB (`OFF < 0x4000`) for processor tiles**; for the MEMORY tile, its
  memory size parameter (<= 16 MB, declared by the memory-tile owner).
- **IMEM, UART, GPIO, STATUS and NI registers are NOT reachable remotely.** Reason: attestation measures IMEM, so a
  remote write path to IMEM would let one tile change another tile's code after it was measured.
- A tile with no data memory (window size 0) answers every remote request with err=1.

**5a.5 err rules** ([R5]). The responder sets `err=1` **if and only if** at least one of these holds:
1. `OFF >= window size` (outside the window; this includes every IMEM/peripheral offset);
2. `A[1:0] != 2'b00` (misaligned);
3. `A[31:28] != 4'h2` or `A[27:24] !=` the responder's own tile ID (misrouted; defensive, M11 prevents it).

On err: a read returns RDATA = 0; a write changes nothing. `wstrb = 4'b0000` on a write is a legal no-op (err = 0).

**5a.6 Responder obligations** ([R5]):
- Exactly **one** response per accepted MEM_*_REQ, **including error cases**: to `rx_src_coord`, type RD_RESP / WR_RESP
  matching the request, tag echoed with `set_txn_tag('0, get_txn_tag(rx_control))`.
- A request the responder never answers leaks one of the requester's two transaction slots permanently.
- The responder must not hold `rx_ready` low on a request longer than the N-8.1 watchdog budget W per packet: a request
  discarded by containment is never answered.

**5a.7 Requester on error** (not a transport rule; Lane-2 internal, recorded for completeness): a `bus_error` or an
`err=1` response must still complete the CPU access (never hang); reads return 0; the adapter records the error in its
tile-local STATUS region.

## 6. Address map (frozen)

| Region | Base | Size |
|---|---|---|
| Local IMEM | 0x0000_0000 | 16 KB |
| Local DMEM | 0x0000_4000 | 16 KB |
| UART / GPIO / STATUS / NI regs | 0x1000_0000 / _1000 / _2000 / _3000 | 4 KB each |
| Remote | addr[31:28] = 0x2, tile = addr[27:24] | tile ≥ 6 → invalid (decoder `valid`=0) |

The only decoder is `address_to_coord_safe` (L-08).

## 7. Router ↔ router flow control (frozen, 7c)

- **Credit-based, one counter per output port × VC.** Each counter resets to 4.
- **The upstream counter decrements when the flit is granted**, not when it arrives.
- **`credit_out` is a registered 1-cycle pulse**, raised one clock after the downstream FIFO pops. It drives the neighbour's `credit_return`.
- **Link stage (`LINK_PIPE=1`, frozen ON):** each router-to-router data link has one register. Credits are not piped.
- **Credit round trip = 4 cycles = VC depth 4 (invariant I-1).** One VC can sustain 1 flit/cycle, with zero slack.

## 8. NI ↔ router (LOCAL) flow control (frozen, 7c)

- **Ready/valid in both directions, one ready bit per direction.**
  - LOCAL in: a transfer happens when `in_valid_local && in_ready_local`.
  - LOCAL out: a transfer happens when `out_valid_local && out_ready_local`.
- **`out_valid_local` = `!eject_empty`.** It comes from a register and never depends on `out_ready_local`. This is required because the NI's `noc_rx_ready` is combinational on `noc_rx_valid`/`noc_rx_flit`.
- **The flit is held stable until accepted** (SVA `a_local_out_flit_hold`).
- **`in_ready_local` is per the incoming flit's VC.** A LOCAL flit with an illegal VC gets `in_ready_local` = 1 (existing behaviour; decided in N-8.1, see §11).

## 9. LOCAL credit behaviour (frozen)

- **LOCAL output credits = 4 + 4 + 4 = 12. The eject FIFO holds 12** (it maps to a 16-deep LUTRAM).
- **Eject stage (`EJECT_PIPE=1`, frozen ON):** the flit and its write strobe are registered before the eject FIFO.
- **Safety:** the credit is consumed at grant, so a flit sitting in the stage already owns a slot.
- **LOCAL credits return when the eject FIFO pops**, internal to the router. `credit_return[LOCAL]` is ignored at the mesh boundary and tied to 0.

## 10. FD-1 — endpoint containment (DECIDED: B′, property frozen, mechanism = N-8.1)

**What the RTL does (unchanged, frozen):** the allocator reserves a whole **output port** per packet
(`output_locked[p]`, `output_owner[p]` in `allocator.sv`), not an (output port, VC) pair. VCs isolate
buffers, not links. The router is **not** modified for FD-1 (option A rejected: it rewrites the
allocator, which is the +0.202 ns critical path).

**Why a rule on tiles is not enough:** the NI couples the network to the tile. In
`noc_network_interface.sv` a valid packet for the local tile gets `noc_rx_ready = rx_ready`
(RX_IDLE / RX_PAYLOAD, ~L827, ~L877). A tile holding `rx_ready = 0` therefore stalls the eject FIFO
and, through wormhole reservation, shared router ports. SPOOF is an adversarial tile by design, so
"tiles always consume" cannot be assumed. (Malformed / misaddressed / unmatched traffic is already
consumed with `noc_rx_ready = 1` + `rx_protocol_error`; the gap is valid traffic only.)

**FROZEN REQUIREMENT FD-1 (B′):**
1. Tile-side backpressure must not propagate into the NoC indefinitely. The trusted NI bounds it.
2. Once the NI accepts a packet HEAD it **owns** that packet until the accepted flit that terminates it
   (TAIL; for a single-flit packet the HEAD_TAIL itself), and consumes it without depending on the tile.
   Ownership ends on the actual terminator flit, not on a length/payload counter: a length mismatch may
   raise an error but must never create a router/NI disagreement about packet boundaries. Router and NI must never disagree about whether a packet is
   in flight: "drop" means *keep accepting and discard to the terminator*, never "stop accepting".
   **Terminator** = the accepted TAIL flit, or HEAD_TAIL for a single-flit packet. It is NOT "the last
   payload flit": with MAC_ENABLE = 1 the last payload flit is BODY and the last MAC flit is TAIL
   (`noc_network_interface.sv` TX: `(tx_last_payload && MAC_FLITS==0) ? TAIL : BODY`, `tx_last_mac ? TAIL : BODY`).
   **(rev 4, AM-3)** Precisely: terminator(k, type) = (k = 0 ∧ HEAD_TAIL) ∨ (k ≥ 1 ∧ TAIL), k = flit position in the packet.
   A mid-packet HEAD or HEAD_TAIL is **not** a terminator, mirroring the allocator (only the owner's TAIL releases a locked
   output, `allocator.sv` ~L470; A4 flags the malformed case).
3. Credits, packet accounting and wormhole release in the router stay exactly as in §7-9. No router
   RTL change.
4. Every containment event is reported by **at least one persistent observable**: a sticky containment
   flag (cleared only by reset or an explicit clear) or a monotonic containment-event counter. A one-cycle
   pulse alone is insufficient. (N-8.1 plan: implement both; the sticky flag is the acceptance criterion.)
5. A malicious endpoint may hold a network resource temporarily, but cannot retain it indefinitely solely by
   withholding tile-side consumption **or supply** (rev 4, AM-2). Traffic that needed that resource completes after containment.
   **(rev 4, AM-2 — architectural transport amendment)** The NI acquires the complete packet payload from its tile **before**
   injecting the HEAD (TX store-and-forward); from HEAD to terminator it supplies every flit without depending on the tile.
   Cost: HEAD latency + T_fill; measured in N-8.
6. The endpoint watchdog counts **tile-induced** stall only: cycles with packet owned AND `noc_rx_valid = 1`
   AND tile not accepting. It must not advance when the upstream NoC simply has no next flit
   (`noc_rx_valid = 0`).
   **(rev 4, AM-1)** The count also includes the **HEAD-pending** interval: cycles in which a deliverable HEAD/HEAD_TAIL is
   valid at the NI and the tile has not accepted it (RX_IDLE forwards `rx_ready` for it today). Responsibility starts at
   presentation; ownership (rule 2) starts at acceptance. The count is per packet and cumulative (not reset per flit).

**Mechanism: NOT frozen — N-8.1 deliverable.** Candidate to evaluate first, because it matches the
NI's existing error path: a per-packet watchdog in the NI (rule 6); on expiry the NI enters a
*discard-to-terminator* state with `noc_rx_ready = 1` and raises an error. It needs no packet buffer, so
the 17-flit (21 with MAC) packet vs 12-flit eject depth is not an issue. Alternatives (bounded
receive buffer, buffer + watchdog) are compared in N-8.1 before any RTL.

**Acceptance evidence (N-8.1, required before N-8 proper) — finite and deterministic:**
- **Topology fixed in the N-8.1 test plan before RTL:** the source of the 17-flit ATTEST_RESPONSE to SPOOF
  (tile 5), the exact router output ports its wormhole reservation holds, and a finite set of competing
  packets from other tiles that must cross those same ports (packet counts stated).
- **Completion bound:** every competing packet completes within a cycle bound derived in the plan from
  watchdog limit + path length + packet length (not guessed).
- **Drain condition** after the finite workload: all router input FIFOs and eject FIFOs empty, all link
  and eject stage valids 0, every credit counter back to its reset value.
- **Containment observed:** sticky containment flag set (acceptance criterion) and event counter incremented, both still readable after the discard.
- **Negative control:** same workload with the watchdog disabled must hit a fixed timeout of the same
  cycle bound (deterministic FAIL, not an open-ended hang).
- **Separate tests** (different failure classes, not merged with the above): premature TAIL, BODY at the
  expected end, HEAD_TAIL on a multi-flit message type, length field ≠ message length, illegal VC 3 at
  LOCAL input, and **missing TAIL / truncated packet** (sender stops mid-packet).
- **Truncated packet is a protocol-boundary test, not a containment case:** under this freeze only the
  terminator releases a router reservation; neither the NI nor the router may release it on length
  expiry or idleness, and no router timeout is added. The test documents the resulting stall and hands
  sender-side detection to S-8/N-10.
- **Framing tests run in both framing modes:** MAC_ENABLE = 0 (last payload = TAIL) and MAC_ENABLE = 1
  (last MAC flit = TAIL), so terminator handling is not hard-coded to one mode.

**Known NI framing gap to fix in N-8.1 (verified in RTL):** `RX_PAYLOAD` leaves on the payload
*counter* (`rx_payload_cnt_q + 1 >= rx_payload_n_q`, `noc_network_interface.sv` ~L885/L968), not on
the TAIL flit. A premature TAIL lets the router release the path while the NI stays in `RX_PAYLOAD`;
the next packet's HEAD is then consumed as a protocol error and its BODY flits are misattributed. Rule 2
above requires ownership to end on the terminator flit.

**Initiators:** the transport layer imposes **no initiator authorization restriction**: every tile NI has
transport TX capability and the decoder accepts remote tiles 0-5. Which initiator/message pairs are *authorized* is N-10
policy, not M-F1. No endpoint buffer size (e.g. "36 flits") is frozen here; any bound is derived in
N-8.1 from outstanding transactions and packet lengths.

## 11. Out of scope for M-F1 (owned by S-8, NOT frozen here)

M-F1 is the **NoC transport** freeze. These are attestation-protocol semantics and are frozen in S-8:

| # | Item | What exists today | Missing |
|---|---|---|---|
| S8-1 | Attestation request/response field layout | widths only: challenge 160 bits (5 flits), response 512 bits (16 flits) | field map (nonce, measurement, tag, epoch) |
| S8-2 | MAC format | MAC_TAG_BITS 128 = 4 trailing flits (L-09); MAC_ENABLE = 0 | key, KMAC customization, coverage, enable point |
| S8-3 | Nonce semantics | TRNG nonce 128 bits; challenge field 160 bits | 128->160 mapping, freshness window |
| S8-4 | Attestation status codes | 4-bit `control.attest.status` | value table |
| S8-5 | Error behaviour at the tile | NI `tx_error`, `rx_protocol_error`, `rx_length_error` | tile reaction per error |

Transport-level item kept here: the router accepts a LOCAL flit with illegal VC 3 (`in_ready_local = 1`).
**(rev 4, AM-4) Decided:** the NI TX cannot emit VC 3 (`message_to_vc` maps every msg_type onto 0..2; SVA `a_tx_vc_legal`
in N-8.1). Router LOCAL-in behaviour for VC 3 is unchanged (accept + drop, unreachable from a trusted NI). NI RX flags any VC
mismatch, VC 3 included, as a framing error.

## 12. Timing and latency contract

- **Clock:** 50 MHz (20 ns), closed **under Vivado 2024.1, xc7a100tcsg324-1, strategy Performance_ExplorePostRoutePhysOpt**: WNS +0.202 ns, all gate checks PASS (N-2.5 run 3 `impl_pe`, and again on the final RTL: `impl_1`, reports/n25_mf1_2026-09-25). Default strategy: WNS +0.048 ns, 0 failing (timing report only, full gate not run). This is an implementation result, not an intrinsic property of the RTL.
- **Implementation strategy is pinned on `impl_1`:** `Performance_ExplorePostRoutePhysOpt`. Default strategy also met timing once, at +0.048 ns (0.24%); it is a fallback, not the reference.
- **Latency added by the timing fixes:**
  - +1 cycle per router-to-router hop (`LINK_PIPE`)
  - +1 cycle per LOCAL delivery (`EJECT_PIPE`)
- **NI timing is not measured:** the N-2.5 gate synthesizes `noc_mesh_synth_top` (6 routers, no NI).
  NI timing is checked separately when N-8.1 changes the NI.
- **Absolute per-hop latency is not measured yet.** That is an N-8 deliverable, in cycles first.
- **Rule:** any NoC RTL change requires the XSim regression and the N-2.5 gate to run again before merge. The margin is 1%.

## 13. Invariants (checked where stated)

| id | Invariant | Checked by |
|---|---|---|
| I-1 | credit round trip ≤ VC depth (4 ≤ 4) | analysis §7; N-7/N-6 pass. A throughput test is due in N-8 |
| I-2 | a flit never enters a full FIFO | FIFO SVA "FLIT DROPPED": 0 firings in N-7/N-6/M8, fires on mutant M-c. TB1 fires it only in its deliberate-violation phases |
| I-3 | EJECT_DEPTH ≥ total LOCAL credit | elaboration `$fatal` in `noc_router.sv`; negative test: EJECT_DEPTH=11 → `$fatal` at t=0 (logs/i3_negative_verilator_2026-09-25.log); XSim mf1 regression PASS with it |
| I-4 | `out_valid_local` independent of `out_ready_local` | M8 T9, 7c rule |
| I-5 | VC id never changes in flight | N-7 per-link legal-VC checks; RTL `xbar_sel % NUM_VC` |

## 14. Sign-off

Evidence in the repo at signature:
- [x] RTL baseline `acd1f73`; `git diff acd1f73 HEAD -- NOC_PQATTEST.srcs synth` empty
- [x] XSim mf1 with I-3, all RECOMPILED: N-7 1756/0, M8 47/0, N-6 126/0, TB1 PASS (logs/*_mf1_2026-09-25.log)
- [x] I-3 negative test fires: EJECT_DEPTH=11 → `$fatal` at t=0 (logs/i3_negative_verilator_2026-09-25.log)
- [x] N-2.5 gate on `impl_1`, pinned PhysOpt: PASS, WNS +0.202 ns, 0/18,237 (reports/n25_mf1_2026-09-25)
- [x] FD-1 decided: B′ requirement §10 (mechanism = N-8.1)
- [x] Two independent external reviews (25-Sep): rev 2 "ready to sign"; rev 3 applies their three
      non-blocking wording/test-plan items (terminator definition, persistent observable, truncated packet)

Signing freezes §1-§10 and §12-§13. It does **not** claim FD-1 is implemented. N-8.1 must meet the §10
acceptance evidence before any other N-8 work. M-F1 is re-opened if FD-1 cannot be met without a router
change, or if any RTL after `acd1f73` changes a frozen value.

**Rev 4 (2026-09-25), signed by delegation** on Kalash's instruction to apply the 10b review ("review with all skills nd apply").
The N-8.1 NI RTL is the sanctioned mechanism for §10 and does not void this freeze by itself; it still requires the full
XSim regression and (because `NOC_PKG.sv` gains a default-preserving MAC define) the N-2.5 gate before merge.

**Signed by delegation:** Claude, on Kalash's explicit instruction of 2026-09-25 ("all questions u asked
me finalize them urself"), after a council review (below). Same delegation model as the 7c freeze.
Kalash may countersign or re-open at any time.

Council summary (why signing now is right):
- Contrarian: the only real risks (FD-1 unimplemented, NI framing bug, thin +0.202 ns) are all written
  in as conditions or re-open triggers, not hidden.
- First principles: M-F1 freezes *how packets move*. Nothing in the three edits or the open NI work changes
  a transport value, so waiting buys no information.
- Expansionist: signing unblocks N-8.1 and S-8 in parallel; delay blocks both.
- Outsider: provenance is now a single commit with evidence files in the repo.
- Executor: next action is the N-8.1 architecture document, no RTL.

Countersigned: ____________ (Kalash) Date: ________

**Rev 5 (2026-09-30), signed by delegation** on Kalash's instruction ("use the council and VLSI expert, decide what is best").
Adds §5a only.

---

# Rev 6 amendments (SIGNED 2026-10-19 by Kalash as the decision freeze)

**State:** SIGNED by Kalash on 2026-10-19 (reply "rev 6 approved"), as the decision freeze; not signed by delegation. Open conflicts and questions (R6.12) remain work items. §1–§14 above are rev 5 text, kept
verbatim, and they stay binding for every build that compiles the production sources.
**Authority:** R4 (`docs/CODEX_INSTRUCTIONS_R4_FINAL_2026-10-08.md`) §1 K-2, §3 NOC-3 and §4 PQ-1/PQ-2. OD-1 to OD-6 are
ACCEPTED in `docs/decisions/dual_lane_config.json` (2026-10-08). Supporting texts: `DUAL_LANE_10_CONTRACT.md`,
`N-9-l2-authentication.md`, `S8-1-attestation-field-map.md`, `S8-2-tile-attest-endpoint.md` and `N-10-attestation-enforcement.md`.
**Evidence base:** the prepared variants were read live at HEAD `0b5c0d6`. Every value below cites the file:line it was read
from. This is a documentation freeze, so it rests on reading, not on running anything: no simulation, synthesis or Python run
was performed for rev 6. The variants are **implemented, unqualified**: none is XSim-simulated, reference-checked or
mutation-tested under this revision.
**Where the RTL and the decisions disagree,** rev 6 picks neither. Each such case is listed under "Rev 6 open conflicts" (R6.12)
and in `docs/decisions/M-F1-rev6-conflicts.md`. Rev 6 does not edit RTL.

## R6.0 Profiles and scope (no production change)

| Profile | Sources | Governs |
|---|---|---|
| **P5 baseline** (rev 5) | production `NOC_PQATTEST.srcs/sources_1/new/NOC_PKG.sv` (SHA-256 `e741a32d…`) and `noc_network_interface.sv` (`83f3b884…`), unchanged | §1–§14 exactly as written, including §4 ATTEST_CHALLENGE = 5 payload words / length 6, and §11 "challenge 160 bits" |
| **P6 Q-C/R-B** (rev 6) | `rtl/dual_lane/NOC_PKG.sv` (`e428af10…`), `rtl/dual_lane/noc_network_interface.sv` (`341c46d2…`), plus the new `rtl/dual_lane/*` modules, all in explicit source lists | R6.1–R6.10 below. Everything in §1–§14 not named here is inherited unchanged |
| **P6-S secure** | P6 with `PQ_MAC_ON` defined, wrapped by `noc_l2_auth` at every tile (`pq_noc_subsystem.sv`:101) | P6 plus the N-9 secure wire, R6.5–R6.8 |

- The only package delta between P5 and P6 is `ATTEST_CHALLENGE_WIDTH` 160→224 (production `NOC_PKG.sv`:289 → variant :290)
  and `message_payload_flits(MSG_ATTEST_CHALLENGE)` 5→7 (production :614 → variant :615), plus a comment line. This was diffed
  live on 2026-10-19. `MAX_PACKET_FLITS` stays `1+16+MAC_FLITS_FULL` = 21 (variant :643–644), and it is unused by any RTL.
- The only NI delta is the added output `tx_auth_preview` (variant :90, :262–276) and a comment line. Its state machine is
  byte-identical to production apart from the shifted line numbers.
- **Production impact: none.** Rev 6 needs no write to any protected file. No P6 value may be back-ported into the
  protected production `NOC_PKG.sv` or `noc_network_interface.sv` under this revision. Doing that would need Kalash to lift
  the CLAUDE.md protection explicitly, and then a separate revision. The rule against duplicate names (R4 §2 rule 2) still
  applies: P5 and P6 package/NI files never appear together in one source list.
- The router, allocator, mesh, credits, VCs and FD-1 (§1–§3, §7–§10) are untouched. The router has no length dependency:
  `grep -i length` over `noc_router.sv`, `allocator.sv`, `noc_mesh_3x2.sv` and `NOC_DATAPTAH.sv` finds nothing. So the 26-flit
  secure wire packets (R6.5) need no router change.

Conventions for all of rev 6: a multi-byte field F has **byte i at `F[i*8 +: 8]`**. Payload word k of a packet is the
k-th payload flit after HEAD (and after the freshness words on the P6-S wire). A word built from a byte string B takes
bytes `B[4k..4k+3]` with `B[4k]` in bits [7:0] (little-endian). SV hexadecimal literals print the highest byte first,
so they read reversed. That is a display artefact, not a wire difference (S8-1).

## R6.1 Q-C challenge (OD-1): 7 words, 224 bits

| Item | Frozen value | Evidence |
|---|---|---|
| msg_type | 4 = `MSG_ATTEST_CHALLENGE`, VC 2 (ATTESTATION) | variant `NOC_PKG.sv`:181, :586–590 |
| Payload | 7 words = 224 bits, vector `C[223:0]`, word k = `C[32k +: 32]` | variant `NOC_PKG.sv`:290, :615; endpoint `pq_attest_endpoint.sv`:75; verifier `pq_rot_verifier.sv`:52 |
| Epoch (80 bits, 10 bytes) | `C[79:0]`; epoch byte e at `C[8e +: 8]`, e = 0..9 | `pq_attest_endpoint.sv`:85; `pq_rot_verifier.sv`:46; OD-1 |
| Nonce (128 bits, 16 bytes) | `C[207:80]`; nonce byte n at `C[80+8n +: 8]`, n = 0..15 | same lines; OD-1 |
| Padding | `C[223:208]` = 0. The sender drives 0 (`pq_rot_verifier.sv`:46). The receiver rejects a nonzero value (`pq_attest_endpoint.sv`:84) | OD-1; R4 NOC-3 |
| HEAD control | `control[10:0]` = 0 (status field 0) | `pq_rot_verifier.sv`:50 |
| Issuer / target | Issuer: RoT, tile index 4, coordinate (1,1). Target: CRYPTO, index 3, coordinate (0,1). The endpoint drops a challenge from any other source | `pq_attest_endpoint.sv`:72; `pq_rot_verifier.sv`:48 (tx_dest) |
| Tile ID | **Not carried.** Tile 3 = ASCII `TILE_03` (56 bits, `56'h33305f454c4954`) is a constant on both sides | `pq_attest_endpoint.sv`:43; `pq_rot_verifier.sv`:43; OD-3 |

Word map (`E` = epoch, `N` = nonce, bit ranges of the logical field):

| Word | [31:16] | [15:0] |
|---|---|---|
| W0 | E[31:16] | E[15:0] |
| W1 | E[63:48] | E[47:32] |
| W2 | N[15:0] | E[79:64] |
| W3 | N[47:32] | N[31:16] |
| W4 | N[79:64] | N[63:48] |
| W5 | N[111:96] | N[95:80] |
| W6 | **0 (padding)** | N[127:112] |

**Lengths (HEAD field, total flits including HEAD and MAC).** Only `msg_type` 4 changes. Length 8 applies when `MAC_ENABLE`=0
(no `PQ_MAC_ON`). Length 12 applies when `MAC_ENABLE`=1 (`PQ_MAC_ON`; 1 + 7 + 4). That gives `message_length`
= 1 + `message_payload_flits` + `MAC_FLITS` (variant `NOC_PKG.sv`:631–639, :81–92). On the P6-S secure wire the same message is
17 flits (R6.5). The endpoint requires `rx_length == message_length(MSG_ATTEST_CHALLENGE)`, exactly 7 payload words, and the
final word, before it starts any crypto (`pq_attest_endpoint.sv`:72, :79–80).

## R6.2 R-B response (OD-1): 16 words, 512 bits

| Item | Frozen value | Evidence |
|---|---|---|
| msg_type | 5 = `MSG_ATTEST_RESPONSE`, VC 2. Lengths 17 (MAC off), 21 (MAC on), 26 on the P6-S wire. These are unchanged from rev 5 §4 apart from the secure wire | variant `NOC_PKG.sv`:616; §4 |
| Payload vector | `R[511:0]`, word k = `R[32k +: 32]` | `pq_rot_verifier.sv`:73 |
| Measurement (32 bytes) | `R[255:0]` = words W0–W7. Measurement byte m at `R[8m +: 8]` | `pq_rot_verifier.sv`:92; OD-1 |
| Tag (32 bytes) | `R[511:256]` = words W8–W15. Tag byte t at `R[256+8t +: 8]` | `pq_rot_verifier.sv`:96; OD-1 |
| Source of the words (endpoint) | W k (k<8) = `internal_response[264+32k +: 32]`, that is, internal bytes 33+4k … 36+4k. W k (k≥8) = `internal_response[520+32(k-8) +: 32]`, that is, internal bytes 65+4(k-8) … | `pq_attest_endpoint.sv`:55, :57 |
| HEAD control | `control[10:7]` = OD-2 status (R6.3), `control[6:0]` = 0 | `pq_attest_endpoint.sv`:50 |
| Error payload | Status ≠ 1 ⇒ all 16 words = 0 | `pq_attest_endpoint.sv`:53–54; OD-2 |
| Destination | The reply-to coordinate latched at the challenge HEAD | `pq_attest_endpoint.sv`:48, :73 |

**Tile, epoch and nonce are NOT on the wire in R-B.** The internal controller response stays 97 bytes / 776 bits, with byte i
at `[i*8 +: 8]`: tile 0–6, epoch 7–16, nonce 17–32, measurement 33–64, tag 65–96 (S8-1; `PYTHON_RTL_CONTRACT_MATRIX.md` §"Exact
internal packing"). R-B transmits only bytes 33–96. The verifier rebuilds the other fields from its own state: tile from
the constant `TILE_03` gated by authenticated source = CRYPTO (`pq_rot_verifier.sv`:43, :70), and epoch and nonce from the
outstanding record (`epoch_q`, `outstanding_nonce`, tagger inputs at `pq_rot_verifier.sv`:56–58). It recomputes the tag over
`tile‖epoch‖nonce‖measurement` (S8-1). R-A (25 words) is not adopted.

## R6.3 OD-2 status table, `control[10:7]` of `MSG_ATTEST_RESPONSE`

| Code | Meaning | Detected by (K-2) | Wire payload |
|---:|---|---|---|
| 0 | reserved, never valid in a response | — | — |
| 1 | success | endpoint | R-B fields (R6.2) |
| 2 | reject | **endpoint** | 16 × 0 |
| 3 | busy | **endpoint** | 16 × 0 |
| 4 | stale | verifier | n/a (verifier verdict) |
| 5 | malformed | **endpoint** | 16 × 0 |
| 6 | tag failure | verifier | n/a |
| 7 | measurement failure | verifier | n/a |
| 8 | identity failure | verifier | n/a |
| 9 | epoch failure | verifier | n/a |
| 10 | internal failure | **endpoint** (controller `err`) | 16 × 0 |
| 11–15 | reserved | — | — |

- Frozen: 4 bits in `control[10:7]` (rev 5 §2 attest overlay; `ATTEST_STATUS_WIDTH`=4, variant `NOC_PKG.sv`:292). The payload
  length stays a fixed 16 words even on error.
- Frozen: the endpoint emits **only codes from {1, 2, 3, 5, 10}**. Codes 4 and 6–9 are verifier verdict reasons and never
  appear in an endpoint response.
- Frozen: no status other than 1 may lead to a grant. The verifier treats `control[10:7] ≠ 1` as a failure
  (`pq_rot_verifier.sv`:70, :77).
- **Not yet matched by RTL:** the prepared endpoint emits only 1 and 10 (`pq_attest_endpoint.sv`:87), and the prepared
  verifier records no per-cause reason. See conflicts C-1 and C-2. The table above is the decision. The RTL has to come into
  line with it in PQ-2 / NOC-4, or Kalash amends K-2.

Status field of the other attestation messages, **proposed from the RTL** (OD-2 does not cover these; open question Q-6):
CHALLENGE `control` = 0 (`pq_rot_verifier.sv`:50), GRANT `control[10:7]` = 1 (`pq_rot_verifier.sv`:50, `11'h080`;
the gate grants only on 1, `noc_attest_gate.sv`:32), REVOKE `control` = 0 (`pq_rot_verifier.sv`:50).

## R6.4 Message lengths per profile (HEAD length field)

| id | msg_type | payload words | P5 MAC off / on | P6 MAC off / on | P6-S secure wire |
|---:|---|---:|---|---|---:|
| 0 | MEM_RD_REQ | 1 | 2 / 6 | 2 / 6 | 11 |
| 1 | MEM_RD_RESP | 1 | 2 / 6 | 2 / 6 | 11 |
| 2 | MEM_WR_REQ | 2 | 3 / 7 | 3 / 7 | 12 |
| 3 | MEM_WR_RESP | 0 | 1 / 5 | 1 / 5 | 10 |
| 4 | ATTEST_CHALLENGE | 5 → **7** | 6 / 10 | **8 / 12** | **17** |
| 5 | ATTEST_RESPONSE | 16 | 17 / 21 | 17 / 21 | **26** |
| 6 | ATTEST_GRANT | 0 | 1 / 5 | 1 / 5 | 10 |
| 7 | ATTEST_REVOKE | 0 | 1 / 5 | 1 / 5 | 10 |

P6-S requires `MAC_ENABLE`=1 (elaboration `$fatal`, `noc_l2_auth.sv`:258). So inside the secure boundary the NI always uses the
MAC-on column, and the wire length is that value + 5. No secure wire packet is a single flit: every one is at least 10 flits
(HEAD … TAIL).

## R6.5 N-9 secure packet (P6-S wire, OD-4)

Flit order (all on VC `message_to_vc(msg_type)`; n = `message_payload_flits(msg_type)`):

| Flit position | Content | flit_type |
|---|---|---|
| 0 | HEAD, with `length` = NI length + 5 = n + 10 | HEAD |
| 1–5 | freshness words F0–F4 | BODY |
| 6 … 5+n | application payload P0 … P(n-1) | BODY |
| 6+n … 9+n | MAC words M0–M3 | BODY, BODY, BODY, **TAIL** |

- **Maximum length 26** (ATTEST_RESPONSE). Quarantine depth `MAX_WIRE`=26 (`noc_l2_auth.sv`:39, :145). The minimum is 10. A
  receiver drains any HEAD with length < 10 or > 26 (`noc_l2_auth.sv`:191). 26 fits the 5-bit length field (rev 5 §2). Nothing
  is placed in unused HEAD/control bits, and the 1-bit transaction tag is not reused (OD-4).
- **Freshness vector** `Fr[159:0]` = `{16'b0, boot_epoch[79:0], seq[63:0]}`, word Fk = `Fr[32k +: 32]` (`noc_l2_auth.sv`:59, :84):
  F0 = seq[31:0], F1 = seq[63:32], F2 = epoch[31:0], F3 = epoch[63:32], F4[15:0] = epoch[79:64], **F4[31:16] = 0**.
  So bits 0–63 are the sequence, 64–143 the boot epoch and 144–159 zero (N-9 doc).
  The receiver rejects nonzero `Fr[159:144]` (`noc_l2_auth.sv`:212). Those 16 bits are not in the MAC transcript.
  Golden: `l2_golden.py`:12–13.
- **MAC words** Mk = `tag[32k +: 32]`. KMAC output byte t is at `tag[8t +: 8]` (`kmac_128.sv`:544). The NI emits MAC word k from
  `tx_mac_tag_q[{k,5'd0} +: 32]` (variant NI :490). The receiver reads them from the last 4 flits (`noc_l2_auth.sv`:163).
  Golden: `l2_golden.py`:13.
- **TX insertion:** the trusted wrapper adds 5 to the NI's HEAD length and inserts F0–F4 directly after the HEAD.
  The NI itself sees and emits the unextended packet (`noc_l2_auth.sv`:80–94, :102–104).

## R6.6 MAC primitive and transcript

- **Primitive:** KMAC128, key K = the 32-byte directed key K[src→dst] (`noc_l2_auth.sv`:69–72, :110, :170–173, :215),
  output **L = 128 bits / 16 bytes**, customization **S = `NOC-L2-AUTH-v1`** (14 bytes, `DOMAIN` =
  `112'h31762d485455412d324c2d434f4e`, `noc_l2_auth.sv`:40). `out_len_sel = 0 = KMAC_L_128` (`kmac_pkg.sv`:109) absorbs
  `right_encode(128)`. That makes it a true 16-byte KMAC, not a truncated 256-bit KMAC (`kmac_128.sv`:30–34; N-9 doc).
- **Transcript** T, byte offsets (vector form `T[8i +: 8]` = byte i):

| Bytes | Field | Vector bits | Evidence |
|---|---|---|---|
| 0–3 | **wire** HEAD word, little-endian (T[0] = HEAD[7:0]); its length field is the extended value n+10 | `[31:0]` | `noc_l2_auth.sv`:66, :119 (TX), :217 (RX); `l2_golden.py`:8, :10 |
| 4 | VC (0..2, zero-extended) | `[39:32]` | :120, :218 |
| 5 | version = `0x01` | `[47:40]` | :121, :218 |
| 6–15 | boot epoch, epoch byte e at T[6+e] | `[127:48]` | :122, :219 |
| 16–23 | sequence, little-endian | `[191:128]` | :123, :219 |
| 24 … 23+4n | payload P0 … P(n-1), each little-endian | `[192+32i +: 32]` | :124, :220 |

  Total length = 24 + 4n bytes, **maximum 88** (`MSG_BYTES`=88; :125, :221). That is R4's HEAD(4)‖VC(1)‖ver(1)‖epoch(10)‖seq(8)‖payload.
  Note the order: on the wire the freshness words are sequence then epoch, but in the transcript the epoch comes before the sequence.
- **Key provisioning** is an input (`tx_keys`/`rx_keys`, `noc_l2_auth.sv`:9; `pq_noc_subsystem.sv`:12, :74–75). TX to peer p
  uses `directed_keys[(g*6+p)]` and RX from peer p uses `directed_keys[(p*6+g)]`. Rev 6 does **not** freeze how the keys are
  derived (open question Q-4, conflict C-8).

## R6.7 Receive quarantine (before NI delivery and slot retirement)

1. The wrapper always consumes the network: `noc_rx_ready = 1` (`noc_l2_auth.sv`:157). That keeps FD-1 (§10) at the network
   boundary. No router lock is held during KMAC.
2. The whole wire packet is collected into the 26-flit quarantine. The framing rules: same VC on every flit, BODY until
   position length-1, then TAIL. An early terminator or one that does not match the length is rejected. Over-length packets
   are drained (`noc_l2_auth.sv`:187–206).
3. Validation before KMAC: msg_type ≤ 7; src/dest inside the 3×2 mesh; dest = own tile; VC = `message_to_vc`;
   length = `message_length`+5; freshness padding zero (`noc_l2_auth.sv`:208–213).
4. KMAC, then in this order: MAC (`:226`), epoch (`:228`), sequence (`:230`). A failure on any one discards the packet.
   The NI sees nothing of it, so there is **zero NI delivery and zero transaction-slot retirement**.
5. Only an authenticated packet is replayed to the NI (`:233–240`, `:164–168`). The replay is the HEAD with length − 5,
   then the payload, then the 4 MAC words, with F0–F4 removed. So the NI's application delivery and memory-slot retirement
   (§5) both happen after authentication (OD-4).
6. A packet that arrives while the quarantine is in PREP/START/WAIT/PLAY/DRAIN is consumed, dropped and counted at its
   terminator (`:182–185`). This is a bounded overload policy, not reliable buffering (N-9 doc). Per-packet accounting:
   see conflict C-6.
7. `reject_reason` is the wrapper's **local** diagnostic namespace and has nothing to do with OD-2: 1 framing/header/drain,
   2 MAC, 3 epoch, 4 sequence, 7 busy-drop (`:184`, `:192`, `:199`, `:205`, `:213`, `:227`, `:229`, `:231`). See C-7.

## R6.8 Counter and boot-epoch rules

- There is one 64-bit sequence per directed peer: `tx_seq[dest]` and `rx_seq[src]`, 6 each (`noc_l2_auth.sv`:45). Both
  are 0 after reset (`:100`, `:179`).
- TX uses seq = `tx_seq[dest]` + 1, so the **first value is 1** (`:109`). `tx_seq` commits when the NI accepts the
  request (`:131`).
- **No wrap:** `tx_ready` = 0 while `tx_seq[dest]` = 2^64−1 (`:73–74`). The largest value ever sent is 2^64−1. Transmission
  to that peer stays refused until a reset with renewed provisioning.
- RX accepts only when seq ≠ 0 and seq > `rx_seq[src]`. Gaps are allowed, for accounted drops (`:230`). `rx_seq` commits
  **only after** MAC and epoch pass (`:233`).
- **Boot epoch:** one 80-bit system-wide input shared by all six wrappers (`pq_noc_subsystem.sv`:9, :102). TX samples it per
  packet (`noc_l2_auth.sv`:109). RX requires an exact match with its own input (`:228`).
- **Reset** clears the counters and authorization. The secure profile requires a NEW externally provisioned boot epoch after
  every reset. RTL cannot enforce this, so it is a provisioning precondition. Reset with unchanged provisioning is outside the
  secure profile (OD-3; N-9 doc). The attestation epoch in Q-C (R6.1) is a separate value from the L2 boot epoch.

## R6.9 `tx_auth_preview` (variant NI output, P6 only)

`output head_flit_t tx_auth_preview` (variant `noc_network_interface.sv`:90) is driven purely combinationally (:262–276):

| HEAD field | Preview value |
|---|---|
| src_x / src_y | `LOCAL_COORD` |
| dest_x / dest_y | `tx_dest_coord` |
| msg_type | `tx_msg_type` |
| length | `message_length(tx_msg_type)`, the NI length including `MAC_FLITS`, **not** the wire length + 5 |
| control | `tx_control`, except that for MEM_RD_REQ / MEM_WR_REQ `control[0]` is replaced by `tx_alloc_tag`, the lowest free slot (:214–229) |

Frozen semantics:
- Every cycle it equals the HEAD that the NI would emit if it accepted the present request inputs in that cycle. At acceptance
  it matches `tx_head` field for field (variant :389–402, with the `tx_control_q` tag override at :664–668).
- It is **not** qualified by `tx_valid`, `tx_ready` or slot availability. It is a pure preview: it accepts no request, changes
  no state and has no handshake. For a reserved msg_type it shows `message_length` of that type, but the NI still rejects the
  request (rev 5 AM-5).
- Consumer obligation: the trusted adapter asserts NI `tx_valid` only while the preview equals the HEAD it MACed
  (`noc_l2_auth.sv`:78). It recomputes the MAC if the preview changes before acceptance (`:129`), which covers a slot being
  freed by a concurrent response.
- Under P5, no such port exists. Existing benches connect the NI by named ports (no `.*` in any bench that instantiates the
  NI), so the extra output may stay unconnected.

## R6.10 Endpoint and verifier obligations carried from S8-2 / OD-5 (unchanged by rev 6)

The reply-to is latched at HEAD. Crypto starts only after a complete, valid 7-word challenge. `rx_ready` = 1 always. One
challenge is outstanding per target. A second challenge is drained while the endpoint is busy. TX words stay stable under
backpressure. Reset cancels everything. Rev 6 adds no rule here beyond R6.1–R6.3.

## R6.10a Tile-key profile (K-1): `TILE_KEY_BYTES = 32`

**System profile, frozen:** tile key = teammate `derive_tile_key(root_secret, tile_id, epoch, context, key_bytes=32)`
(`software/pq_attest_final/PQ_Attest/software/kmac128_ref.py`:414–440). Its steps:
- KDF message `encode_string(tile) ‖ encode_string(epoch) ‖ encode_string(context)`.
- KMAC128 keyed by the root, with empty customization and 32-byte output.

Field constraints:
- root: exactly 32 bytes.
- tile: 7 bytes (`TILE_03` for the single CRYPTO endpoint).
- epoch: 10 bytes, the attestation epoch from Q-C (R6.1).
- context: 0–14 bytes.

The context is a provisioned trusted input, not a wire field. The demo value is `PQ-ATTEST-KDF`, 13 bytes
(`scripts/full_chain_golden.py`:7, :17 at HEAD `0b5c0d6`).

Where the RTL selects 32 bytes:

| Point | Source |
|---|---|
| Controller KDF length select fixed to `2'b01` | `NOC_PQATTEST.srcs/sources_1/new/pq_attest_protocol.sv`:251 (`.key_len_sel(2'b01)`) |
| `2'b01` = `KDF_LEN_256` (32 bytes) | `pq_kdf_pkg.sv`:116–117 |
| KDF KMAC output length follows the select (L = 256) | `pq_kdf.sv`:87, :217, :259 |
| Controller tag length select fixed to `2'b01` = `TAG_LEN_256` (32-byte tag; R-B carries 32 tag bytes) | `pq_attest_protocol.sv`:321; `pqattest_stg7_pkg.sv`:169–170; `pqattest_stg7.sv`:312 |
| Controller rejects context_len > 14 | `pq_attest_protocol.sv`:362–363 |
| Endpoint instantiates that controller; it has no length-select port, so the endpoint cannot select 16 | `rtl/dual_lane/pq_attest_endpoint.sv`:60–63; root port 256 bits at :6, context :7–8 |
| Verifier independently uses `key_len_sel(2'b01)` and `tag_len_sel(2'b01)`, and accepts start only if context_len ≤ 14 | `rtl/dual_lane/pq_rot_verifier.sv`:54, :57, :83 |

**16-byte profile: reference-only, never on the wire.** The teammate's own 16-byte examples are reproduced unchanged by the
separate R4 V8 job `py_teammate_examples`, for example root `bytes(range(32))`, `TILE_01`, `EPOCH_0001`, `PQ-ATTEST-KDF`,
key16 `9c699e78…27c`. That job validates the reference and nothing else:
- No P5/P6 RTL instance, vector, packet or job on the system profile uses a 16-byte tile key or a 16-byte attestation tag.
- The two profiles are never mixed in one job (R4 K-1, V8).

The protected `pq_kdf`/`pqattest_stg7` blocks still accept 16 as a unit-level option (their own S-5/S-7 tests). That is not a
system path.

## R6.10b Measurement boundary and L-1 mitigation (K-3)

**Frozen:** measurement = `SHA3-256(tile ‖ config[:config_len] ‖ imem[:imem_len])`. The input is unencoded: no length prefix
and no separator, exactly as the teammate `measure_tile` computes it (`software/pq_attest_final/PQ_Attest/software/measurement_ref.py`:83–100).
- RTL `pq_measurement.sv`:108–130 lays out the tile at bytes 0–6, config immediately after, then imem immediately after config.
- The 135-byte cap stays (L-4).

**L-1 mitigation (provisioning rule):** `config_len` and `imem_len` are **fixed provisioned constants per tile**, recorded
next to that tile's whitelist digest (`approved_measurement`). With a fixed split, the same concatenated bytes cannot be
read as a different (config, imem) pair.

The verifier never sees the lengths. R-B carries only measurement and tag (R6.2), and the verifier only compares the digest
(`pq_rot_verifier.sv`:92). So this is a **provisioning guarantee, not a cryptographic one**. Changing either length means
reprovisioning the whitelist and requalifying.

Constants for TILE_03 in the prepared oracle (offline demo):

| Item | Value | Source |
|---|---|---|
| config | `bytes(range(16))`, so **config_len = 16** | `scripts/full_chain_golden.py`:7, :17 (`config_len=16`) |
| imem | `bytes(range(16,32))`, so **imem_len = 16** | `scripts/full_chain_golden.py`:7, :17 (`imem_len=16`) |
| context_len | 13 (`PQ-ATTEST-KDF`) | `scripts/full_chain_golden.py`:7, :17 |
| Whitelist digest | `approved_measurement` = the oracle measurement of the row above | `scripts/full_chain_golden.py`:15; `pq_noc_subsystem.sv`:11 |

**The RTL does not hold these as constants.** `config_len` and `imem_len` are runtime input ports of the endpoint
(`pq_attest_endpoint.sv`:10, forwarded at :62) and of the subsystem (`pq_noc_subsystem.sv`:16, :114). The controller latches
them per request (`pq_attest_protocol.sv`:530, :533). Nothing records them beside `approved_measurement`. The testbench
loads them per vector (`tb_pq_full_chain.sv`:13, `load_chain`). This is open conflict **C-10**.

## R6.11 Jobs requiring requalification (`post_format_compat`)

Rule: any job whose source list compiles a NOC_PKG must be rerun on P6 identity before any P6-dependent gate may be accepted.
This follows R4 PQ-1 ("rerunning every job that compiles NOC_PKG") and NOC-3 ("rerun the N-8.1 framing jobs on the variant
identity"). Proposed mechanics (Kalash/integrator decides; `dual_lane_jobs.json` is **not** edited by rev 6): each rerun is
a **new job id** on the P6 source list, with its expected counts frozen before its first run. The I-1 P5 jobs stay valid
as rev-5 baseline evidence and are not overwritten.

| Group | Job ids (current registry) | Compiles today | Why affected |
|---|---|---|---|
| N-8.1 NI | `n81_ni_m0w16`, `n81_ni_m0w1`, `n81_ni_m1w16`, `n81_ni_m1w1`, `n81_nitb` | P5 PKG + P5 NI | challenge length 6/10 → 8/12; NI variant |
| N-8.1 system | `n81_n6`, `n81_sys_m0w16`, `n81_sys_m0w64`, `n81_sys_m0n0`, `n81_sys_m1w16`, `n81_sys_m1n0` | P5 PKG + P5 NI | same |
| WP-0 N-6 mutation | `wp0_n6_control_before`, `wp0_n6_mut_a`, `wp0_n6_mut_b_t5`, `wp0_n6_mut_c`, `wp0_n6_control_after` | P5 PKG + P5 NI | package identity |
| D7 | `d7_n7_pipe1`, `d7_n7_pipe0`, `d7_m8`, `d7_n6`, `d7_tb1` | P5 PKG + P5 NI | package identity; TB1 checks attestation VC mapping |
| OOC / gate | `ni_ooc` (P5 PKG+NI), `mesh_gate` (P5 PKG, implementation; runs alone) | P5 | package/NI identity (the router does not use the changed constants; identity is still a rerun trigger) |
| Performance | `perf_m0`, `perf_m1` (and the consuming gate `perf_matrix`) | P5 PKG + P5 NI | challenge length in the traffic mix |
| Already P6 | `full_chain` (P6 PKG + NI, `PQ_MAC_ON`), `endpoint_ooc` (P6 PKG) | P6 | first qualification under rev 6 (their earlier runs predate rev 6) |
| Oracles | `chain_python` (`full_chain_golden.py`), plus the **unregistered** L2 oracle `l2_golden.py` and the unregistered `tb_noc_l2_auth.sv` | — | they produce the P6-S wire vectors; the ZIP-adapter switch (C-4) also changes their identity |
| Dependent gates | `pq_endpoint`, `l2_auth`, `l3_enforce`, `security_sec_1_4`, `N-11`, `N-12`, `N-13`, `post_format_compat` itself | — | consume the above |
| Not affected by the wire | `s8_python`, `s8_golden`, the 7 `s8_mut_*`, `s8_control_after`, `python_ref`, `ooc_pq_*` (4) | no NOC_PKG | internal 97-byte format unchanged. They are still subject to Track A (V7) for oracle identity |

Open for Kalash (Q-5): whether the compat reruns use P6 PKG + P6 NI together (proposed, since that is the secure identity),
or also a P6-PKG-with-P5-NI axis. `tb_ni_n81.sv` derives challenge lengths from `message_payload_flits`/`message_length`
(e.g. :356, :450, :636, :731), and its T06 test lengths `{3, 20}` (:487) are still ≠ 8/12. So no expected-count change is
*predicted*, but cycle-dependent checks were not analysed. Counts are frozen per job before the first run and never edited
to pass.

## R6.12 Rev 6 open conflicts (summary; full table in `M-F1-rev6-conflicts.md`)

| ID | Severity | Short form |
|---|---|---|
| C-1 | High | Endpoint emits only status 1/10. K-2 says the endpoint emits 2/3/5/10 |
| C-2 | High | Verifier has no OD-2 reason output. Codes 4, 6–9 are produced nowhere |
| C-3 | Medium | No identity bypass control in `noc_l2_auth` (R4 NOC-3 and N-9 require four bypasses) |
| C-4 | Resolved (merged `99b2746`) | The oracles are now thin adapters over the pinned ZIP; vector payloads are byte-identical |
| C-5 | High | Memory stand-in and L2/full-chain vectors use remote prefix `0x8`. Rev 5 §5a freezes `0x2` |
| C-6 | Low | L2 overload drops are counted per flit, with reason 1, when a dropped packet's tail outlives the busy window |
| C-7 | Low | L2 `reject_reason` values overlap OD-2 numbers (7 = busy-drop vs OD-2 7 = measurement) |
| C-8 | Medium | L2 directed-key derivation (`NOC-L2-KEY-v1`, same demo root) is undocumented in every decision |
| C-9 | Resolved by R6.0 (on signature) | Rev 5 §4/§11 (5 words / 160 bits) vs the P6 package (7 / 224): profile split |
| C-10 | Medium | K-3 needs fixed per-tile config_len/imem_len next to the whitelist digest. The prepared RTL takes both as runtime ports |

Rev 6 cannot be signed as "consistent with RTL" while C-1 to C-3, C-5 to C-8 and C-10 are open, and while C-4 waits for the
merge of `912ee39`. It can be signed as the **decision** freeze, with those items carried as RTL/oracle work items. Kalash
chooses.

## R6.13 Rev 6 sign-off

Evidence at writing: the variant diffs and file hashes were read live on 2026-10-19 at HEAD `0b5c0d6`. Production
`NOC_PKG.sv` is `e741a32d…` and production `noc_network_interface.sv` is `83f3b884…`, both equal to R4 §0. No run of any kind
was performed for rev 6.

- [x] Kalash accepts R6.1–R6.11, including R6.10a (K-1, 32-byte key) and R6.10b (K-3, L-1 mitigation), as the P6 freeze
- [ ] Kalash rules on C-1 to C-3, C-5 to C-8, C-10 and Q-1 to Q-8 (`M-F1-rev6-conflicts.md`): OPEN; each blocks only the increment that implements it
- [~] `post_format_compat` job set registered (I-2, `pfc_*`); 13 count-carried jobs frozen, 10 FREEZE_REQUIRED still blocked

Signed: Kalash Bheda, 2026-10-19, in chat: "rev 6 approved". Decision freeze only; not a claim that the RTL matches (see R6.12).

# Rev 7 amendments (SIGNED by Kalash 2026-10-20 with conditions C1–C4, R7.9; drafted by Claude Code)

Rev 7 is additive. It defines a new profile **P7** for the area-reduced secure subsystem Kalash chose on 2026-10-20:
- the configuration is the `reports/b1_trims/area_matrix.md` row "3,4 / 1 shared / D / trim / no shared Keccak", 44,000 LUT (69 %, ESTIMATE);
- the record is DECISION_REGISTER D-AREA-1.

P5, P6 and P6-S (rev 5/6) are unchanged and stay valid for their builds. No RTL for P7 exists when this section is written.

## R7.0 Profile P7 and scope

| Item | P6-S (rev 6) | **P7 (rev 7)** |
|---|---|---|
| L2 wrapper (`noc_l2_auth`) | every tile (`pq_noc_subsystem.sv`:101) | **tiles 3 (CRYPTO) and 4 (RoT) only** |
| Other tiles 0, 1, 2, 5 | wrapped | **plain NI**, `CONTROL_ALLOWED = 0` (R7.4) |
| MAC'd message types | all 8 | **CHALLENGE (4), RESPONSE (5), GRANT (6), REVOKE (7) only** |
| Data-plane types 0–3 | MAC + freshness | **no MAC, no freshness, no sequence** |
| L2 KMAC | 2 per wrapper (tx, rx) | **one shared KMAC128 engine** for both wrappers (R7.6) |
| Endpoint / verifier KMAC | separate KDF and tag KMACs | KDF and tag **time-multiplexed on one KMAC** each (D); digests unchanged |
| Mesh ingress | none | **ingress source check** on every local port (R7.5) |

P7 is selected by a new define `PQ_P7` together with `PQ_MAC_ON`. The router, allocator, mesh, credits, VCs and FD-1 (§1–§3, §7–§10)
are untouched.

## R7.1 Message lengths (HEAD length field) and wire format

P7 defines `message_mac_flits(t)` in the variant `NOC_PKG.sv`: 4 if `MAC_ENABLE` and t ∈ {4, 5, 6, 7}, else 0. Then
`message_length(t)` = 1 + `message_payload_flits(t)` + `message_mac_flits(t)`. In P7, `MAC_FLITS` is no longer a per-build constant.

| id | msg_type | payload words | P7 NI length | P7 wire length | wire format |
|---:|---|---:|---:|---:|---|
| 0 | MEM_RD_REQ | 1 | 2 | **2** | plain: HEAD, payload; last flit TAIL |
| 1 | MEM_RD_RESP | 1 | 2 | **2** | plain |
| 2 | MEM_WR_REQ | 2 | 3 | **3** | plain |
| 3 | MEM_WR_RESP | 0 | 1 | **1** (HEAD_TAIL) | plain |
| 4 | ATTEST_CHALLENGE | 7 | 12 | **17** | R6.5 secure packet (unchanged) |
| 5 | ATTEST_RESPONSE | 16 | 21 | **26** | R6.5 secure packet (unchanged) |
| 6 | ATTEST_GRANT | 0 | 5 | **10** | R6.5 secure packet (unchanged) |
| 7 | ATTEST_REVOKE | 0 | 5 | **10** | R6.5 secure packet (unchanged) |

- **Control-plane packets** keep the rev 6 secure wire exactly: R6.5 framing (F0–F4 freshness, 4 MAC words), the R6.6 transcript and primitive, and the R6.8 counters. They exist only between tiles 3 and 4.
- **Data-plane packets** use the plain NI framing (MAC-off column of R6.4) everywhere, including through the tile-3/4 wrappers. The wrapper passes them through unchanged in both directions: no quarantine, no KMAC, no length +5.
- **Sequence counters:** P7 keeps them only for the single control peer, tile 3 ↔ tile 4. That is 1 `tx_seq`/`rx_seq` entry, not 6.
- **Maximum wire length** stays 26 (RESPONSE), so the 5-bit length field still holds.

## R7.2 Status and reason codes

| Where | Code | Meaning | New? |
|---|---|---|---|
| L2 `reject_reason` (R6.7.7 namespace) | 1, 2, 3, 4, 7 | unchanged (framing/header, MAC, epoch, sequence, busy-drop) | — |
| L2 `reject_reason` | **5** | control-type packet from a source other than the wrapper's single control peer (tile 3 accepts only src 4, tile 4 only src 3). Rejected in the header pre-check, **before** any KMAC request | new |
| L2 `reject_reason` | **6** | general-slot packet refused by the per-source rate limit (SF-1 design, R7.7) | new |
| plain-NI tile counter (`l2_rejected[g]` / `l2_reason[g]` for g ∈ {0,1,2,5}) | **8** | control-type HEAD (types 4–7) received at a non-attested tile: consumed to its terminator, never delivered | new |
| plain NI TX | `tx_error` | the application at a non-attested tile requests a control type: refused, nothing sent (same mechanism as reserved types, rev 4 AM-5) | new use |
| ingress check (R7.5) | **9** | HEAD entering the mesh at local port g with `src ≠ g`: dropped to its terminator, counted at port g | new |
| gate `fault_reason` (`noc_attest_gate.sv`) | **5** | GRANT/REVOKE head delivered at a gate built `ATTESTABLE = 0`. Unreachable by construction (code 8 drops first); asserted, and kept as defence in depth | new |
| OD-2 `control[10:7]` of RESPONSE | unchanged (R6.3) | | — |

## R7.3 L2 instances

`noc_l2_auth` is instantiated on tiles 3 and 4 only, with `PEER` = 4 and 3 respectively.
- **Keys:** only K[4→3] and K[3→4] are needed, 2 × 256 bits, held in a key RAM (trim T3). `directed_keys` shrinks from 9,216 to 512 bits in P7.
- **Freshness:** the epoch and sequence rules (R6.8) apply unchanged to the single peer.

## R7.4 Non-attested tiles (0, 1, 2, 5) refuse GRANT/REVOKE

- **NI:** built with `CONTROL_ALLOWED = 0`.
  - TX of types 4–7 is refused with `tx_error`.
  - RX of a type 4–7 HEAD is consumed to its terminator and counted with reason 8. It is never delivered: zero NI delivery and zero slot retirement.
- **Gate:** built with `ATTESTABLE = 0`.
  - `authorized` is tied to 0, so the tile's own data-plane TX is never authorized. Rev 6 already behaves this way: the verifier only grants `TILE_CRYPTO` (`pq_rot_verifier.sv`:48).
  - A delivered GRANT/REVOKE head raises fault 5.
- **Required test (I-5):** a GRANT and a REVOKE claiming `TILE_ROT`, presented at the network input of each non-attested tile.
  - Expected: reason 8 counted, no delivery, `authorized[g]` stays 0, no fault 5 (unreachable).
  - A mutant with `CONTROL_ALLOWED = 1` and `ATTESTABLE = 1` must be killed by the `authorized[g]` check.

## R7.5 Threat model (P7), stated explicitly

**Trusted:**
- the NIs, the routers and links, and the L2 wrappers;
- the shared KMAC engine and the RoT verifier;
- key provisioning and the boot-epoch input.

**Source IDs are hardware-stamped by the sending tile's NI.** The attestation gate enforces authorization (`noc_attest_gate.sv`). Memory acceptance (`pq_noc_subsystem.sv`:141–142) trusts the stamped source of an authorized tile.

**Enforcing "stamped source" at the raw port.** The subsystem keeps a raw injection port at tile 5 (`pq_noc_subsystem.sv`:66, the SPOOF test hook). It models an agent attached to a mesh port without an NI.
- **The check:** P7 adds an **ingress source check** on every local port. A HEAD with `src ≠ g` entering at port g is dropped (reason 9).
- **Where it lives:** an `rtl/dual_lane` subsystem wrapper. It does not touch the router.
- **Why it is needed:** without it the stated assumption is false at the raw port, and neither the data plane nor SF-1 can be defended (R7.7).

**This is a design point for Kalash's sign-off.**

**Untrusted:** application software on every tile (including the attested tile before GRANT), and any agent at the raw port.

**Security goals kept:**
1. **G1:** authenticity, integrity and freshness of CHALLENGE/RESPONSE/GRANT/REVOKE between tiles 3 and 4 (MAC, epoch, sequence).
2. **G2:** only an attested, granted tile may issue data-plane memory requests (gate + stamped source + ingress check).
3. **G3:** a REVOKE from the RoT is never suppressed by other traffic (SF-1, R7.7).
4. **G4:** non-attested tiles can never become authorized (R7.4).

**Given up (residual risk, accepted by D-AREA-1):**
1. Integrity, freshness and replay protection of data-plane packets against an attacker *inside* the trusted mesh (a faulty or compromised router or link).
2. Data-plane confidentiality, which was never provided.

### NOC-3 attack cases under P7 (`scripts/l2_golden.py`:210–241; `tb_pq_endpoint_sys` S1–S7)

| Case(s) | P7 status | Why |
|---|---|---|
| `ch1_genuine`, `ch2_genuine`, `resp1/resp2_genuine`, the boot-B cases, seq max / max−1, `ch_seq_zero` | **retained** | control-plane RX at the L2 tiles; same R6.5–R6.8 rules |
| tamper of head control / payload / tag / fresh seq / fresh epoch / fresh padding; `resp1_bad_tag` | **retained** | MAC/epoch/sequence/padding checks unchanged |
| `ch2_wrong_key_reverse_direction` | **retained** (reason 2) | K[3→4] used for a 4→3 packet |
| `ch2_wrong_key_spoof_signed` (signed by tile 5) and `ch2_wrong_src_claim` (src = tile 2,1) | **retained, expected reason 2 → 5** | a non-peer source is now refused in the header pre-check, before KMAC |
| `ch2_wrong_dest_tile5`, `ch2_wrong_vc_body`, `ch2_len_field_tamper`, `ch2_truncated_8`, `ch2_overlong_30_flits`, `ch2_len_over_max_27`, `grant_undersize_unextended` | **retained** (reason 1) | framing/header rules unchanged |
| `BURST grant3+ch4+grant5` | **retained, re-specified** | busy-drop semantics change with the reserved peer slot (R7.7); new expected counts are frozen in I-5 |
| NEG_MAC / NEG_SEQUENCE / NEG_EPOCH negative controls | **retained** | bypass controls unchanged |
| `(T, (2, 2, 0x780, W))` TX of a MAC'd memory write to tile 2; `INJECT tx_seq[2]` + `PROBE` refuse to tile 2 | **retired** | data-plane packets carry no MAC or sequence in P7. Replaced by a data-plane TX pass-through check (bit-exact plain framing) and by a sequence-exhaustion refuse on the control peer (tile 4) |
| `tb_pq_endpoint_sys` S2 forged challenge from SPOOF claiming RoT, S3 replay, S4 wrong VC | **retained, observation moves** | the raw-port packet with `src = 4` is dropped at ingress (reason 9). An L2-level copy of each case stays in the unit bench (MAC/sequence/VC) |
| S5/S6 SPOOF stall mid-packet, S7 reset | **retained** | FD-1 / containment unchanged |
| New (I-5) | — | SF-1 SPOOF-flood-during-REVOKE + mutant; shared-engine starvation; refuse-GRANT at non-L2 tiles (R7.4); ingress forged-source drop |

## R7.6 Shared L2 KMAC engine and arbitration

- **Requesters.** RoT-priority class **P = {r0, r1}** (RoT-sourced packets); non-RoT class **Q = {r2, r3}**.

  | Requester | Job | Class |
  |---|---|---|
  | r0 | tile-4 TX (RoT → 3: CHALLENGE, GRANT, REVOKE) | P |
  | r1 | tile-3 RX from the reserved peer slot (stamped src = 4) | P |
  | r2 | tile-3 TX (RESPONSE) | Q |
  | r3 | tile-4 RX (RESPONSE from 3) | Q |

- **One job:** one KMAC128 over ≤ 88 transcript bytes (R6.6) with the requester's directed key.
  - **J_MAX = 128 cycles** is the frozen upper bound per job, including handoff.
  - Estimate: 3 permutations × 24 rounds plus encode/absorb ≈ 80–100 cycles.
  - The I-5 bench measures every job and fails on any job > J_MAX.
- **Arbitration rule:** strict priority P over Q, round-robin within each class.
  - **Aging guard:** at most **2 consecutive P grants** while a Q request is pending, then one Q grant. This bounds Q even if P is requested continuously, e.g. a held `revoke` input re-entering V_REVOKE (`pq_rot_verifier.sv`:82).
  - No grant is pre-empted.
- **Bounds** (cycles at 20 ns, conditional on J_MAX; arbitration overhead 4 cycles):

  | Requester | Worst-case wait | Calculation |
  |---|---|---|
  | P requester | **≤ 2·J_MAX + 4 = 260 cycles** (5.2 µs) | the job in flight + at most one forced Q grant |
  | Q requester (starvation bound) | **≤ 4·J_MAX + 4 = 516 cycles** (10.3 µs) | the job in flight + 2 P grants + the other Q requester |

  The I-5 starvation test drives continuous P load and checks that every Q wait is ≤ 516.

## R7.6a Amendment: arbiter bounds re-frozen (Kalash 2026-10-20, Option 1)

The R7.6 text above is left as signed. Its two bounds were wrong, and this amendment supersedes them.

| Item | Value |
|---|---|
| Old bounds (R7.6) | P ≤ 2·J_MAX + 4 = 260, Q ≤ 4·J_MAX + 4 = 516 cycles |
| Why they were wrong | Under the signed rule, after the guard forces a grant to the *other* Q requester, the consecutive-P counter resets, so P gets 2 more grants before the waiting Q. The Q worst case is therefore 6 job slots, not 4 |
| Found by | the exhaustive model `scripts/arbiter_model.py` (C3), independently reproduced in a separate slot-level model (P = 2 slots, Q = 6 slots) |
| Rule | **unchanged:** strict P priority, at most 2 consecutive P grants while a Q is pending, round-robin within each class, no pre-emption |
| **New frozen bounds** | **P ≤ 269 cycles, Q ≤ 792 cycles**, for J_MAX = 128 and engine-to-engine overhead OVH ≤ 4 cycles |
| Exact model maxima | OVH 0: P 257 / Q 768; OVH 1: P 260 / Q 774; OVH 4: P 269 / Q 792 |
| Rejected (Option 2) | per-request aging gives P ≤ 401 / Q ≤ 528. It weakens the security-relevant RoT bound (G3) to improve a performance bound |

**RTL rules for step c.** Each has an assertion and a test or mutant.
- **A0, round-robin pointer rule** (added after the model check): inside each class the pointer moves to the other requester after **every** grant in that class. The P bound depends on it. A fixed-priority P gives r1 an unbounded wait; a pointer that moves only when both P requesters are pending gives P = 396 cycles, about 3 slots. Mutant: pointer moves only when both pending; the P-bound check must fail.
- **A1, one outstanding job per requester:** no request while that requester's own job is in flight. It is kept as an asserted rule. Correction to the relayed premise: under A0, the exhaustive model shows A1 is **not** load-bearing (early re-request still gives P 269 / Q 792). The "3 slots" seen in the separate model reproduces exactly with the A0-broken pointer variant (396), so the A0 mutant replaces the A1 mutant as the P-bound kill.
- **A2, OVH ≤ 4 cycles** between engine jobs: measured in the bench, failing above 4.
- **A3, every job ≤ J_MAX = 128 cycles:** measured, failing above.

**Verifier timeout check:** `pq_rot_verifier.sv`:4 sets `TIMEOUT_CYCLES = 100000`, counting the whole attestation from start (`:86`, `:66`, `:103`).
- The worst P7 round trip, ESTIMATE, is ≈ 2,700 cycles: KDF ≈ 100, CHALLENGE MAC ≤ 269, transport ≈ 30, endpoint ≈ 600 with D, RESPONSE MAC ≤ 792, transport of 26 flits ≈ 40, RESPONSE verify ≤ 792, tag check ≈ 100.
- That leaves about 37× margin, so there is no false-revoke risk from the new Q bound.

**Test bounds:** the starvation test uses Q ≤ 792; the C4 REVOKE-latency test uses P ≤ 269 plus transport.

- [x] **Signed: Kalash 2026-10-20, Option 1** (instruction relayed in chat after the 21:33 live check).
- [x] **A0 accepted by Kalash 2026-10-21:** the round-robin pointer mutant replaces the A1 mutant as the P-bound kill. A1 stays an asserted rule.

## R7.7 SF-1 under P7

SF-1 (busy-drop suppresses GRANT/REVOKE) is fixed in P7 by the design in `docs/decisions/SF-1-l2-busy-drop.md` § "Design (P7)":
- a reserved peer receive slot;
- a per-source rate limit on the general slot;
- RoT priority on the shared engine (R7.6);
- the ingress source check (R7.5).

## R7.8 Implementation order

Each step freezes its counts before the first run, and has an equivalence check where the function is unchanged.

1. Trim T1–T4 in a `noc_l2_auth` variant (function unchanged). Equivalence bench against the rev 6 wrapper: wire, delivery and counters bit-exact.
2. D in endpoint and verifier (function unchanged). Digests bit-exact against the current engines; latency delta measured.
3. Shared L2 KMAC + arbitration + SF-1 fix + reason codes 5/6 (P7 behaviour).
4. `pq_noc_subsystem` P7 variant:
   - L2 on tiles 3/4 only, plain NIs elsewhere (`CONTROL_ALLOWED = 0`, `ATTESTABLE = 0`);
   - the ingress check;
   - the `PQ_P7` package lengths.
5. Full-subsystem OOC: measured LUT ≤ 75 % (47,550). Mesh timing recheck: the NOC-1 baseline WNS of +0.202 ns must not regress below 0.

## R7.9 Rev 7 sign-off

- [x] **SIGNED by Kalash 2026-10-20 (live check 21:19), with conditions C1–C4.** The ingress source check (R7.5) is approved as mandatory.
- **C1 Ingress check (R7.5).**
  - **Drop rule:** a forged HEAD (`src ≠ g` at local port g) drops the whole packet through its TAIL, a single-flit HEAD_TAIL included. Credits return upstream, so no body flit is orphaned on a wormhole path and no credit leaks.
  - **Test 1:** a forged src at the raw port is dropped (reason 9) with no credit leak; all credits are home after the drain.
  - **Test 2:** legitimate traffic on every port is unaffected. Rerun a NOC-2 subset: perf points and hop probes.
  - **Mutant:** check disabled, so the forged packet reaches the memory commit. It must be killed.
  - **Timing:** recheck mesh timing; register the check if WNS < +0.2 ns.
- **C2 (R7.4):** `CONTROL_ALLOWED = 0` goes into a `rtl/dual_lane` NI variant. The protected NI stays untouched.
- **C3 (R7.6):** an exhaustive Python model of the arbiter proves P ≤ 260 and Q ≤ 516 cycles.
  - It covers all request patterns over a bounded horizon, aging guard included.
  - It is committed as a registered job before the arbiter RTL.
- **C4 (G3 delay):** an I-5 test measures REVOKE delivery latency under saturated data-plane traffic (N-7.5 sat_vc2 style) and fails above a frozen bound.

## R7.5a Amendment: ingress completion watchdog (Kalash 2026-10-21, decision D1; Codex audit F6)

Written before any dependent RTL. The rev 7 text above is left as signed.

| Item | Rule |
|---|---|
| Problem (F6) | The ingress source check (R7.5) rejects forged identities but does not make an own-source packet complete. A raw sender at tile 5 can send a legal own-source HEAD toward tile 3 and withhold its TAIL. The allocator releases an output only on the owner's TAIL (`allocator.sv`:470), so the wormhole through router 4's west output stays locked, and RoT traffic to tile 3 is blocked before it reaches the reserved slot. |
| Mechanism | Every local ingress port g (all six, in the P7 subsystem wrapper; the router is untouched) runs a **completion watchdog** on the packet it is forwarding. It counts **sender-stall cycles**: cycles in which the port owns an unterminated packet (HEAD accepted, terminator not yet accepted) and the sender presents no flit. Mesh backpressure (flit presented, `in_ready = 0`) is not counted. |
| Limit | **W_ING = 64 cycles**, the N-8.1 watchdog budget used on the subsystem NIs (`WD_LIMIT = 64`). |
| Action on expiry | The ingress **forcibly terminates** the packet: it injects one synthetic TAIL flit (data 0, the packet's VC) into the mesh, which releases every wormhole lock on the path. The receiver sees a truncated packet and rejects it with its framing rules (L2 reason 1; NI framing error / `rx_abort`; never a delivery or commit). Any later flits from the sender up to and including its own terminator are discarded at the ingress, and the sender side is not stalled by them. |
| Counting | New ingress reason code **10** ("completion timeout"), counted at port g in the same counter as reason 9. |
| End-to-end REVOKE bound (C4) | **E2E_REVOKE ≤ 1,500 cycles** (30 µs) from the cycle the verifier's `revoke` input is asserted to `authorized[3]` falling. See the derivation below. |
| Test | An own-source HEAD from tile 5 toward tile 3 stalls before its TAIL while the RoT issues REVOKE. The REVOKE is delivered and `authorized[3]` falls within E2E_REVOKE. |
| Mutant | Watchdog disabled. The REVOKE stays blocked, and the mutant is killed by the latency check (a bounded wait followed by a check, not a timeout). |

Derivation of the 1,500-cycle bound (cycles):

| Step | Cycles |
|---|---|
| Verifier to TX valid | 2 |
| Wrapper TX to engine request | 3 |
| P wait (R7.6a) | 269 |
| Engine job (J_MAX, includes the 22-word load) | 128 |
| NI issue and wire | 20 |
| Transport | 10 |
| Ingress release of a blocking packet (W_ING + 16) | 80 |
| Peer slot busy with the previous peer packet (D2): 2 + 269 + 128 + 30 | 429 |
| RX collect | 10 |
| Pre-check | 2 |
| RX P wait | 269 |
| RX engine job | 128 |
| Replay start behind a data pass-through (W_ING + 4) | 68 |
| NI delivery and gate update | 3 |
| **Sum** | **1,421** |

The sum is frozen as 1,500.

## R7.7a Amendment: the peer receive path never drops (Kalash 2026-10-21, decision D2; Codex audit F5)

Written before any dependent RTL. It supersedes the SF-1 P7 statement that "a packet for a busy slot P is impossible in normal operation … counted busy-drop (7)".

- **Rule:** a control packet whose stamped source is the wrapper's peer is **never dropped for occupancy.**
  - While slot P is busy (collecting, verifying, waiting for its replay or replaying), a new peer HEAD is held at the mesh port (`noc_rx_ready = 0`) until slot P is free.
  - Only slot G may drop, with reason 6 (rate limit) or 7.
- **By construction:** `p_slot_drops` stays 0. It is kept as an output and asserted.
- **Deadlock freedom:** the argument is written first, in `docs/decisions/D2-peer-slot-deadlock-freedom.md`. Peer service is bounded and needs only the shared engine and the NI receive side, never tile 3's or tile 4's TX or any mesh resource, so holding the port creates no wait cycle.
- **Tests**, each under hostile own-source traffic as well:
  - held revoke (a stream of REVOKEs);
  - back-to-back GRANT then REVOKE;
  - REVOKE arriving during peer verification;
  - REVOKE arriving during peer replay.

  Every required control is processed, and the tile ends in the expected state.
- **Mutant:** drop-when-busy restored for the peer path. It must be killed by the de-authorization check.

## R7.10 Implementation notes recorded with D1/D2 (2026-10-21, no wire change)

- **Engine job (R7.6, J_MAX):** the shared engine streams the owner's 22 transcript words into one message register, then runs the kmac128.
  - J_MAX = 128 covers the whole job from grant to done: loading, handoff and completion.
  - Measured (scratch, not evidence): 105 cycles for every length.
- **Data hold during replay:** a data HEAD presented while a slot-P replay starts or runs is held at the wrapper's mesh port until the replay ends (≤ 26 flits). This is the same mechanism as D2, and the same requalification applies (D2 doc sec. 5).
- **Slot G holds no flit storage.** It never replays, so it keeps only the HEAD, VC, flit count and the F4 padding half-word that the header pre-check needs. Slot P and the TX payload are LUTRAM.

## R7.5b Amendment: ingress quarantine and parsers (Kalash 2026-10-21, contract Q1; supersedes the R7.5a mechanism)

Source: `docs/decisions/P7-INGRESS-REVOCATION-CONTRACT.md` sec. 1. The R7.5a text is kept as written. Its mechanism is superseded:
the synthetic zero TAIL is deleted, and nothing incomplete or fabricated ever enters the mesh.

- **Raw (untrusted) injector at tile 5:** `noc_ingress_quarantine`, store-and-forward.
  - A 32-deep LUTRAM FIFO with commit/write pointers. Only complete, validated packets are forwarded.
  - HEAD checks: source, type, destination, length = P7 `message_length`, VC, and HEAD_TAIL only for length-1 types.
  - Continuation checks: BODY/TAIL only, same VC, TAIL exactly at `length`.
  - Gap discard: the counter advances only while partially buffered with `in_valid = 0` and `in_ready = 1`, and resets on
    every accepted flit. At W_Q = 64 the partial packet is discarded.
- **Trusted (NI-driven) ports:** `noc_ingress_parser`, non-buffering.
  - HEAD checks only; a failing packet is consumed whole and nothing is forwarded.
  - Mid-packet violations are an NI fault: SVA plus a counter, with no recovery and no fabricated flit.
  - No watchdog.
- **Tile-5 merge:** a packet-atomic round-robin mux between the quarantine and the NI parser.
- **Reason codes** (same counter as reason 9):
  - **9:** forged source;
  - **10:** quarantine gap discard;
  - **11, new:** malformed ingress packet (stray flit, bad HEAD fields, nested HEAD, VC change, early or overlong TAIL).
- **E2E REVOKE bound:** stays a 1,500-cycle target (contract sec. 7). It is measured, never re-derived.

## R7.7b Amendment: corrected D2 wait graph (Kalash 2026-10-21, contract sec. 4)

This corrects R7.7a and `docs/decisions/D2-peer-slot-deadlock-freedom.md`, which claimed no mesh dependency. Each edge of the
peer-hold wait graph is bounded separately:

1. **Peer collection from the mesh:** bounded by trusted senders, the quarantine and the NI W.
2. **Preceding pass-through data in the wrapper:** length ≤ 26 into an always-ready consumer.
3. **Engine service:** P ≤ 269 + J.
4. **Replay into the NI, endpoint or gate:** always-ready consumers.

The engine is released before TX waits on the mesh.

- **SVA:** tile-3 control consumers have `ready == 1` always (a hard stop if that ever becomes conditional).
- **Accounting:** `peer_accepted`, `peer_replayed`, `peer_rejected`, `peer_hold_max`.
- **Quiescence invariant:** accepted == replayed + rejected.
- **SVA:** hold ≤ H_MAX = 512 cycles.

## R7.11 Port note: I-6 trusted clear and fault status (Kalash 2026-11-02, "Approve ports"; written before the I-6 RTL)

No wire-format, message-length or code change. Subsystem ports only (`rtl/dual_lane/pq_noc_subsystem_p7.sv`):

| Port | Dir | Meaning |
|---|---|---|
| `trusted_clear` | in | trusted (RoT-side) clear of every gate's fault counter / reason and of the fault status; not reachable from any application port |
| `fault_sticky` | out | 1 after any fault event until reset or trusted_clear |
| `fault_count[31:0]` | out | cycles with a fault event, saturating |
| `fault_source[2:0]`, `fault_operation[3:0]`, `fault_reason[3:0]`, `fault_epoch[79:0]` | out | last recorded event (map: docs/decisions/I6_CONTRACT.md sec. 3) |

Tile 3's gate trusted fail / timeout come from the RoT verifier (failed with fail_reason). K-3 (endpoint length binding)
answers status 5, an existing code. The memory stand-in's window becomes `A[31:28] == 4'h2` (C-5, already decided).
