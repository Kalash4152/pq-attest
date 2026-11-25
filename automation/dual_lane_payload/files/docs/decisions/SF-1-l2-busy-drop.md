# SF-1 — L2 single receive slot with drop-when-busy lets attacker traffic suppress RoT GRANT/REVOKE

**Recorded:** Kalash, 2026-10-20. **Severity:** security (blocking).
**Blocks:** acceptance of NOC-3 (I-5) and NOC-4 (I-6) until the items below exist.

## Finding

`rtl/dual_lane/noc_l2_auth.sv` (the P6 L2 boundary) has one receive quarantine. `noc_rx_ready` is always 1 (`:157`).
A packet arriving while the receiver is in any state other than `R_IDLE`/`R_COLLECT` is consumed and dropped at its
terminator with local reason 7 (busy-drop) (`:181-185`). The receiver stays busy through `R_PREP`, `R_START`,
`R_WAIT` (KMAC verification) and `R_PLAY` for every packet, authentic or not.

So any tile, including SPOOF, can occupy tile T's receiver with junk that fails authentication only after the KMAC.
A trusted RoT control packet that arrives in that window is dropped:
- **dropped GRANT:** a healthy tile stays unauthorized (denial of service);
- **dropped REVOKE:** a revoked tile stays authorized. **That is a security failure.**

## Evidence (debug-only trace, scratch copy of `tb_pq_endpoint_sys`; not acceptance evidence)

Run `dual_lane_10_20261020_000438_d4ad56ae`, job `pq_endpoint_sys`, reproduced with monitors:

| Time | Event |
|---|---|
| 17.05 µs | RoT verifier `V_GRANT` (`grant_done`) |
| 18.23 µs | tile-3 L2 receiver starts collecting S2's 17-flit SPOOF packet (`rs`: IDLE → COLLECT → PREP → START → WAIT) |
| 18.73 µs | RoT GRANT head `04965080` injected at tile 4 |
| **19.01 µs** | **tile-3 L2 `rejected_count` 0 → 1, `reject_reason = 7` (busy-drop): the GRANT is discarded** |
| 20.21 µs | SPOOF packet rejected, reason 2 (MAC) |

`authorized[3]` never rises after the S1 grant. In S6 a GRANT reached an idle receiver and authorized the tile, which
shows the race is timing-dependent.

The repaired system bench waits for GRANT delivery before starting S2, so it **no longer exercises this collision**.
SF-1 needs its own attack test (below).

## Required before NOC-3 / NOC-4 acceptance

1. **Design fix** (RTL in a `rtl/dual_lane` variant, after Kalash picks an option):

| Option | Mechanism | Pros | Cons |
|---|---|---|---|
| A. Reserved RoT slot | A second quarantine buffer used only by packets whose HEAD claims source = RoT on VC2 (GRANT/REVOKE/CHALLENGE). A claim that later fails the MAC is dropped. | Bounded extra area (one 26-flit buffer plus a second KMAC run or arbitration); RoT control never waits behind untrusted traffic | An attacker spoofing a RoT source can still occupy the RoT slot. That needs a per-source rate limit, or verify-before-replace (B) |
| B. Verify-before-drop / priority preempt | When a RoT-claimed HEAD arrives while busy with a non-RoT packet, abort the non-RoT verification, drop *that* packet and collect the RoT one | No second buffer | Needs abortable KMAC/state; the RoT claim is still unauthenticated at preempt time, so a forged RoT header can evict honest traffic (DoS on others, not on revocation) |
| C. Backpressure instead of drop | Deassert `noc_rx_ready` while busy, so later packets wait in the mesh | No loss of trusted packets | Head-of-line blocking; a flood stalls the mesh (liveness/N-7.5 impact); breaks the "NI never backpressures" assumption of N-8.1 containment |
| D. Fail-safe REVOKE | Gate auto-de-authorizes on a missed heartbeat or timeout, with the RoT re-sending REVOKE until acknowledged | Covers lost REVOKE even under loss | Needs a new ack/heartbeat message, so an M-F1 revision first; more traffic |

   The recommendation is A plus a per-source rate limit (or A+B for RoT-claimed headers). The decision is Kalash's; no
   RTL is written yet.
2. **Attack test:** a SPOOF flood (back-to-back packets keeping tile T's receiver busy) during REVOKE delivery. Pass
   condition: the tile ends **de-authorized**, with no protected commit after the revoke. Also the GRANT variant: the
   tile ends authorized.
3. **Mutant:** restoring single-slot drop-when-busy must be **killed** by the attack test's targeted check, not by a
   timeout.

## Design (P7): PROPOSED 2026-10-20, doc only, no RTL

> **Superseded statements (2026-10-21):** the bounds 260 / 516 cycles quoted below are superseded by M-F1 R7.6a (P <= 269, Q <= 792). The claim "a packet for a busy slot P is impossible ... counted busy-drop (7)" is superseded by M-F1 R7.7a (D2: the peer path holds, never drops). Incomplete raw packets are handled by R7.5a (D1). The text is kept as written.

**Chosen by Kalash (2026-10-20):** option A (reserved RoT receive slot) plus a per-source rate limit, combined with RoT priority on
the shared L2 KMAC engine (M-F1 R7.6). This section makes it concrete for P7, where L2 exists only on tiles 3 and 4 (M-F1 R7.0).

### Why A + rate limit needs the ingress source check (M-F1 R7.5)

A rate limit or a reserved slot keyed on the **claimed** source cannot tell a forged RoT claim from a genuine one before the MAC.
Consider an attacker at the raw port (`pq_noc_subsystem.sv`:66) sending forged src = 4 packets, timed to each slot opening:
- the attacker can keep the single reserved slot occupied whenever the genuine REVOKE arrives;
- a rate limit only fixes when it may do so.

So A + rate limit **defends SF-1 only if the claimed source is the true source**. P7 makes that true:
- every NI stamps its own tile as `src`;
- the **ingress source check** drops any HEAD entering local port g with `src ≠ g` (reason 9), including at the raw port.

After that, a packet in tile 3's reserved slot is genuinely from tile 4's NI.

### Mechanism (per L2 wrapper, tiles 3 and 4)

1. **Two receive slots** replace the single quarantine (`noc_l2_auth.sv`:145, 182–185):
   - **Slot P (reserved peer slot):** a 26-flit quarantine used only by control-type packets whose stamped src = the wrapper's
     single control peer (tile 3: src 4 = RoT; tile 4: src 3). On tile 3, slot P is the "reserved RoT receive slot".
   - **Slot G (general slot):** a 26-flit quarantine for every other control-type packet. Under P7 these are all illegitimate:
     a non-peer source is refused with reason 5 in the header pre-check, without a KMAC request. G only collects and drains;
     it never holds the engine.
   - **Data-plane packets** bypass both slots (M-F1 R7.1).
2. **Slot steering is decided on the HEAD** from the stamped src and msg_type, which are trusted after the ingress check. A packet
   for a busy slot P is impossible in normal operation: tile 4's NI sends one control packet at a time and the verifier is
   single-outstanding (`pq_rot_verifier.sv`:47). If it happens anyway (fault), it is counted busy-drop (7) on **slot P**, and a
   counter `p_slot_drops` is exported.
3. **Per-source rate limit on slot G:** at most one admission per **T_RL = 64 cycles** per stamped source. Excess packets are
   consumed and dropped with reason 6. This bounds how much of the wrapper's receive bandwidth any single tile can burn, though
   slot G never touches the engine.
4. **Engine priority:** a slot-P verification is requester r1 (class P) on the shared engine. It waits at most 260 cycles (R7.6).
5. **Verification order is unchanged:** framing → header pre-check → MAC → epoch → sequence. The packet is replayed to the NI only
   after authentication (R6.7.4–5).

### Guarantees and their bounds

- **G3 (REVOKE never suppressed):**
  - a REVOKE from tile 4 lands in slot P, which no other source can occupy;
  - slot P is free whenever the RoT sends, because the RoT is single-outstanding;
  - its verification starts within 260 cycles and finishes within 260 + J_MAX = 388 cycles (7.8 µs) of the TAIL.
  - Under a SPOOF flood at the raw port at line rate, the flood is dropped either at ingress (forged src) or in slot G (own src
    5, reason 5 or 6). Slot P and class P are untouched.
- **Liveness of the RESPONSE path:** tile 4's slot P receives tile 3's RESPONSE. It is class Q on the engine, so its wait is
  ≤ 516 cycles (R7.6).

### Tests (I-5; counts frozen before the first run)

- **SF-1 attack test:**
  - **Load:** a SPOOF raw-port flood at tile 3, back-to-back forged src = 4 control packets and own-src (5) control packets, while the RoT sends REVOKE to an authorized tile 3.
  - **Pass:** `authorized[3]` falls; no protected commit after the REVOKE is delivered; and `p_slot_drops == 0`. A GRANT variant must end with the tile authorized.
- **Mutant:** restore single-slot drop-when-busy (slot P disabled, all control packets through one quarantine). It must be killed by the targeted check `authorized[3]==0 after REVOKE`, not by a timeout.
- **Ingress test:** a forged src = 4 HEAD at the raw port is dropped with reason 9 and never reaches tile 3.
  - **Mutant:** ingress check off. It must be killed by the ingress drop-count check, and by the SF-1 test whenever the forged packets reach slot P.
- **Starvation test:** continuous class-P load (held `revoke`) checks every class-Q wait ≤ 516 cycles. Every job is measured and checked ≤ J_MAX = 128.

## Relation to other items

- Related to rev-6 C-6 (busy-drop counted per flit) and to OD-4 (pre-delivery authentication).
- Independent of C-1/C-2 (endpoint busy retry), which concerns the endpoint's status 3, not the L2 receiver.
