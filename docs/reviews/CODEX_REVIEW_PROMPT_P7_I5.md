# Codex red-team review: the next two stages (P7 integration → I-5)

**From:** Kalash Bheda (owner, NOC_PQATTEST), with help from his review assistant
**To:** Codex, the independent third-party reviewer
**Date:** 2026-10-21 · **Baseline commit:** `b83e025` (verify it's still current before you start)
**Repository:** `C:\vivado_verilog_proj\NOC_PQATTEST` · branch `noc/credit-integration`

---

## 0. Your role and how to work

You're the project's outside challenger. Your last audit, the one with findings F1–F8, found real defects that
the builders had missed. F2, F3 and F4 were then confirmed in the live source. This review asks you to do the same
**before** the next two stages are built, so the plan doesn't fail halfway through.

Rules for this review:

1. **Read-only.** Don't edit repository files and don't start Vivado/XSim or `dual_lane.py run`. You may run Python
   models or scripts in a **temporary copy outside the repo**, and you may read anything.
2. **Evidence or it didn't happen.** Every claim cites `file:line`, a report path or a run ID. Separate these
   categories:
   **Confirmed** (from source or logs) · **Strongly supported** (a static argument) · **Plausible** · **Speculative**.
3. **Attack the plan, not only the code.** I want counterexamples, missing tests, hidden assumptions, wrong orderings,
   and acceptance criteria that could pass while the requirement is still violated.
4. **Don't reopen signed decisions unless you find a correctness or security defect in them.** These are signed:
   P7 profile (D-AREA-1), M-F1 rev 7 + R7.6a, the arbiter bounds P ≤ 269 / Q ≤ 792 (J_MAX 128, OVH ≤ 4, A0 pointer rule),
   KDF/tag KMAC sharing, D-SYN-1/2, at most three BUSY retries then fail closed, proposal A (expected_diag),
   the 75 % LUT ceiling (47,550), and the 20 ns clock on xc7a100tcsg324-1.
   If you challenge one of them, say exactly which defect forces it.
5. **Constraints the plan must respect:** no edits to protected sources (`CLAUDE.md`; changes go in `rtl/dual_lane/`
   variants); XSim 2024.1 only, with no Verilator and no formal tool; 16 GB RAM, so at most one Vivado/XSim process at
   a time and synthesis runs alone; evidence only through `dual_lane.py` jobs with counts frozen before the run;
   the teammate Python ZIP (`software/pq_attest_final/`, SHA-256 `047bb5a9…`) is the authoritative PQ reference.

---

## 1. The two stages under review

### Stage S1: P7 integration and measured feasibility (the "B-4" work; gate = measured full-subsystem fit)

| # | Work item | Plan source |
|---|---|---|
| S1.1 | Focused reproducers on the **current** RTL for F2 (revoke lost while busy, `pq_rot_verifier.sv:99`), F3 (TX ownership switch, `pq_noc_subsystem.sv` ~:88), F4 (authorization only at HEAD, `pq_noc_subsystem.sv` ~:140). Keep the failing runs, then fix, then add a mutant per fix. | Kalash addendum B |
| S1.2 | Finish the shared L2 KMAC engine (`l2_kmac_engine.sv`, 22-word transcript load before KMAC) on the accepted `l2_arbiter.sv`. Bit-exact against ZIP-derived vectors; real jobs ≤ 128 cycles **including load and handoff**. | Codex §4, STEP_C doc |
| S1.3 | P7 L2 wrappers on tiles 3 and 4 (`noc_l2_auth_p7.sv`, `noc_l2_p7_pair.sv`). Peer slot plus general slot; general-slot rate limit (reason 6). Slots must be LUTRAM/BRAM, not FF. | R7.7, SF-1 doc |
| S1.4 | **Decision D2:** the peer-class receive path never drops; it backpressures while the peer slot is busy. A deadlock-freedom argument is written before the RTL. `p_slot_drops == 0` is asserted. | Kalash addendum A |
| S1.5 | **Decision D1:** an ingress completion watchdog on every local port. A packet that doesn't reach TAIL within W cycles is forcibly terminated at ingress, and the truncated packet is rejected by framing. New reason code via amendment R7.5a. | Kalash addendum A |
| S1.6 | Ingress source check (C1): whole-packet drop through TAIL, HEAD_TAIL included, with credits returned. Plain NI variants (`noc_network_interface_p7.sv`) on tiles 0/1/2/5 with CONTROL_ALLOWED = 0 and ATTESTABLE = 0. Refuse-GRANT test + mutant. | R7.4, R7.5, C1, C2 |
| S1.7 | The full P7 `pq_noc_subsystem` OOC synthesis. **Hard stop if LUT > 47,550.** WNS ≥ 0, no latches, DRC = 0, hierarchy retained, mesh timing rechecked (historical mesh WNS +0.202 ns). | Codex §8, addendum C |

### Stage S2: I-5 / NOC-3, L2 authentication under P7

| # | Work item |
|---|---|
| S2.1 | P7-adjusted attack matrix on the control plane: tamper (head/payload/tag/freshness), wrong key, wrong peer, wrong dest/VC, replay, old epoch, sequence zero/wrap/exhaustion, reset replay, truncated/overlong, overload. |
| S2.2 | Retired data-MAC cases replaced by plain-framing, ingress-check and watchdog tests. |
| S2.3 | Effective negative controls (MAC, sequence, epoch, identity) and the 4 bypass controls. |
| S2.4 | SF-1: SPOOF flood during REVOKE (the tile ends de-authorized), the held-revoke case, and the C4 end-to-end REVOKE latency bound under saturated data traffic. |
| S2.5 | Compatibility regression: N-8.1 containment and a NOC-2 subset (perf points + hop probes) rerun on P7 framing. Authentication latency and engine contention measured. |
| S2.6 | Gate: every rejected control packet causes zero trusted delivery and zero slot retirement; every mechanism has a killed mutant; I-5 report. |

**Known numbers** (check them; don't assume):

- **Area:**
  - estimate ≈ 46,400 LUT (73.2 %), ceiling 47,550;
  - measured: endpoint 16,441, verifier 7,742, trimmed P6 L2 wrapper 14,446, mesh 10,114 (routed), NI 402 each (OOC);
  - shared L2 KMAC ≈ 7,018 (estimate).
- **Arbiter:** RTL maxima P 268 / Q 664 (`reports/NIGHT_20261021.md`).
- **Attestation latency:** 205–333 cycles; verifier `TIMEOUT_CYCLES = 100000` (`pq_rot_verifier.sv:4`).

---

## 2. Questionnaire

Answer **every** question using the format in §3. "N/A" or "fine" without reasoning doesn't count as an answer.

### A. Plan ordering and gates

- **A1.** Is S1's order (reproduce F2–F4 → engine → wrappers → D1/D2 → ingress/NI → full synthesis) dependency-correct?
  Would a different order expose the area or deadlock risk earlier and more cheaply? Should a *skeleton*
  full-subsystem synthesis (empty or stub L2) run **first** to measure the fixed cost and catch an overrun before the
  detailed work?
- **A2.** Is "LUT ≤ 47,550 measured at OOC" a sufficient feasibility gate, given that N-13 is a routed full implementation?
  What utilization or congestion level would you treat as a routing risk on xc7a100t (LUTRAM share, control-set count,
  carry chains)? Propose a concrete second criterion.
- **A3.** The addendum lets Claude Code continue automatically through PASSing gates and hard-stop only on listed events.
  List the events that **should** be hard stops but aren't in that list.
- **A4.** Registry regeneration re-identifies every job. Which jobs from I-1…B-3 must be **re-run**, and which may only be
  re-adjudicated, when S1 changes `pq_noc_subsystem`, the NI variant and the package lengths? Identify any accepted
  evidence that silently becomes stale.

### B. D1: ingress completion watchdog (incomplete raw packets)

- **B1.** The watchdog must not kill legitimate packets that are stalled by **downstream backpressure**. Specify exactly
  what it counts: cycles where the sender withholds the next flit (`valid=0` mid-packet) versus cycles where the
  network refuses it (`ready=0`). Does the N-8.1 W contract define it this way? Cite it.
  Give a counterexample if the plan's wording is ambiguous.
- **B2.** What value of W is safe and still bounds REVOKE latency? Relate it to the 26-flit maximum, the NI's own
  W, and the C4 bound.
- **B3.** Forced termination injects a TAIL (or truncation marker) into the mesh. Check that the router/allocator
  (`allocator.sv` ~:470) releases the output lock, that credits balance, and that **every** receiver type (L2 wrapper,
  plain NI, memory stand-in, endpoint) rejects the truncated packet without delivery and without slot retirement.
  Does any receiver accept a short MEM_WR_REQ as valid?
- **B4.** Can an attacker at the raw port defeat the watchdog with a slow drip (a flit every W−1 cycles)? What bounds
  the hold time then? Is a total packet-duration limit needed as well?
- **B5.** Does the watchdog on the six local ports hurt mesh timing (WNS +0.202 ns) or the area margin (~1.1k LUT)?
  Estimate both.

### C. D2: peer-class backpressure instead of drop (SF-1)

- **C1.** Build the wait-for graph: the tile-3 L2 RX peer slot → the shared engine (r1) → the arbiter (P class) → the
  engine busy with r2/r3 → tile-3 TX / tile-4 RX → the mesh → tile-3 ejection. Is there **any** cycle? Pay particular
  attention to the case where the tile-3 **replay into the NI/endpoint/gate stalls** because the consumer doesn't drain.
  Does anything guarantee that control replay at tile 3 is always consumed in bounded time?
- **C2.** When tile-3 ejection backpressures a peer packet, other packets destined for tile 3 (data on the same VC,
  responses) queue behind it. Which VCs carry control versus data (`message_to_vc`)? Is there head-of-line blocking that
  can delay a REVOKE behind attacker data, or the reverse?
- **C3.** The peer class is decided from the HEAD's `src` field. With the ingress check, only tile 4 can produce
  `src = 4`. Is that true for **every** path into tile 3, including packets that pass through tile 4's router from
  elsewhere? Can a packet *routed through* tile 4 carry `src = 4`?
- **C4.** Held revoke: the verifier re-enters V_REVOKE while `revoke` stays high (`pq_rot_verifier.sv` ~:82, :117).
  With backpressure, can repeated REVOKEs fill the mesh or starve Q-class traffic past 792? Should the verifier
  issue REVOKE once per edge or epoch?
- **C5.** Is "`p_slot_drops == 0` asserted" a meaningful guarantee? Which mutant proves the assertion and the test
  can actually detect a drop?

### D. F2 / F3 / F4 fixes

- **D1.** F2: define the **revocation boundary** precisely. If REVOKE arrives in V_KWAIT…V_TWAIT, or in the same cycle
  that the tag-check passes, what must happen, and in what priority? If the GRANT is already on the wire (V_GRANT,
  `tx_ready` low), must the verifier send REVOKE immediately after? Write the full state × event table you expect, and
  point out any cell the plan leaves undefined.
- **D2.** F3: what ownership granularity is correct (packet-atomic from HEAD acceptance to the last payload)? What
  happens to an application packet that is half accepted when a challenge arrives: wait for it, or abort it? Is an
  abort even representable in the frozen framing? Do the same review for the **RX side** at tile 3 (endpoint versus
  application) and for memory-response arbitration at tile 2.
- **D3.** F4: should authorization be checked at commit for **writes only**, or should **read responses** be suppressed
  after revoke too (a read issued before revoke, returned after)? Which does the threat model (R7.5 G2) require?
  Define the "side-effect boundary".
- **D4.** For each fix, is the planned reproducer certain to fail on the **current** RTL? Give the exact stimulus timing
  that triggers it, so the failing run isn't accidentally a pass.

### E. Shared L2 KMAC engine and arbiter

- **E1.** Verify J_MAX: the 22-word load + KMAC128 (key block + message + any final block) × 24-cycle permutations + the
  handoff. Is ≤ 128 cycles plausible for the longest control transcript (RESPONSE, 88 bytes)? Show the arithmetic. If it
  exceeds 128, the signed P/Q bounds are void. What then?
- **E2.** The arbiter evidence assumed one outstanding job per requester (A1) and a fixed OVH ≤ 4. Do the real wrappers
  guarantee A1? Where?
- **E3.** Request, key, transcript, owner and completion association: what is the worst-case cross-talk (one requester
  receives another's tag)? Which test would catch a one-cycle owner mismatch?
- **E4.** What reset behavior is required mid-load and mid-permutation, so there's no stale `done` after reset? Is the
  reset synchronous everywhere? Are there RDC concerns between `rst` and the arbiter grant registers?

### F. Area and timing realism

- **F1.** Rebuild the 46,400 estimate from measured components. Which line items are still estimates? Give a realistic
  error band. My concern: estimates have run 0–20 % optimistic, and the margin is 1,150 LUT.
- **F2.** Will the SF-1 slots actually infer LUTRAM (asynchronous read? reset on memory contents?)? What coding
  pattern guarantees it in Vivado 2024.1?
- **F3.** If S1.7 lands over 47,550, rank the fallbacks that **don't** weaken security (for example shared Keccak inside
  the L2 engine only, LUTRAM conversion, trimming the plain-NI variant) and give an estimated saving for each.
- **F4.** Which new logic sits on paths that could hit the mesh's +0.202 ns critical path? Should the ingress check or
  watchdog be registered by default?

### G. Stage S2 (I-5) test design

- **G1.** Map each **retained** R6/R7 attack case to the exact mechanism it exercises, and each mechanism to a
  negative control that disables it. Which mechanism has no effective negative control?
- **G2.** Which attacks become **newly possible** under P7, given that data packets carry no MAC? Is each one either
  tested or documented as an accepted residual risk?
- **G3.** Is `l2_golden.py` fully on the ZIP's `kmac128` (P3 fix 724c96e, guard 31fb455)? Are the P7 transcripts
  (single peer, R7.1 lengths) generated by the oracle and not by the RTL?
- **G4.** Define the C4 REVOKE end-to-end latency: the start event, the end event (`authorized[3]` falling), every
  component in between, and the frozen bound. Is saturated data traffic the true worst case, or is it
  watchdog-terminated raw traffic plus a held revoke?
- **G5.** Which N-8.1, NOC-2 and N-7.5 results must be **re-earned** on P7 framing? Which can't be reused because the
  wrapper now backpressures RX during replay?
- **G6.** Are the I-5 acceptance criteria machine-checkable by the judge today (Codex F8: mutant check counts, unrelated
  `[FAIL]`, OOC area and DRC)? Which criterion would still be a manual claim?

### H. Threat model and claims

- **H1.** Write, in at most 6 sentences, the exact security claim P7 can honestly make after S2, including its
  assumptions (trusted NI/routers/links, the raw-port model) and residual risks. Flag any word in our docs that overclaims.
- **H2.** Is the raw-port + ingress-check + watchdog model a reasonable stand-in for "an agent without an NI"? What
  real attack does it **not** cover?

### I. Schedule and process risk

- **I1.** List the top 5 ways S1+S2 could stall or burn days: tooling (XSim launch stalls, orphan xsimk pipe deadlock,
  antivirus), RAM (~1–3 GB free), identity churn, judge gaps. Give a mitigation for each.
- **I2.** What single artifact, produced first, would most reduce the risk to the whole remaining plan?

---

## 3. Required answer format

For **each** question:

```
<ID> | Verdict: OK / GAP / DEFECT / BLOCKER | Confidence: Confirmed / Strong / Plausible / Speculative
Evidence: file:line / report / run id
Reasoning: (short)
Counterexample or failing scenario: (if any; concrete stimulus and timing)
Required change to the plan: (exact; test name, acceptance criterion, or ordering change)
```

Then finish with:

1. **Top 10 risks, ranked** (likelihood × impact), each mapped to its question ID.
2. **Plan corrections:** a numbered list that can be pasted directly into Claude Code's instruction.
3. **Go / No-go** for starting S1 as written, and the minimum change needed to make it Go.
4. **Anything we didn't ask** that you'd block on.

Don't soften findings. If you think a signed decision is wrong, say so and prove it.
