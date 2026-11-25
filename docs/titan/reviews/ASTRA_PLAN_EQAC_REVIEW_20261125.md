# EQAC review: TITAN "Astra" plan (25 Nov 2026)

**Reviewed live:**
- `_titan/docs/titan/TEN_STAGE_BLUEPRINT_20261122.md` and `EXECUTION_PLAN_TO_PAPER_20261121.md`;
- `DECEMBER_CORE_HANDOFF_20261122.md` and `G0_LOCAL_REVIEW_20261122.md` (all untracked in `_titan`);
- `NOC_PQATTEST/docs/handoff/TITAN_CLAUDE_20261121_25/README.md`;
- `CLAUDE_PROJECT_HANDOFF_20261124.md`;
- the `kalash/titan-rtl` log (head `bee21769`, no commits since 21 Nov 21:20).

**Verdict: CONDITIONAL APPROVAL.** Evidence discipline is excellent: provenance, scratch vs registered, and preserved
failures are all handled well. Two critical planning defects must be fixed before December work starts.

## Critical (fix before 1 Dec)

**C1. Scope drift without a recorded owner decision.**
- **What the records say:** December's working scope is "B0 + S4R + S5R"; S7 is conditional; S6/S8 are deferred; the
  target is an engineering handoff by 31 Dec.
- **Why it is critical:**
  - The epoch tracker and stamp **enforce nothing**. With no commit guard (T3), denial responder (T4) or read filter
    (T5), P1/P2/P4 cannot be shown and B1–B4/TITAN cannot be compared. That is no paper.
  - It contradicts the frozen plan (RTL feature-complete 3 Jan, results freeze 17 Jan, paper 1 Feb) and the owner's
    standing instruction not to cut scope.
- **Fix:**
  - Kalash states in writing which scope governs. If the frozen scope governs, restore S6–S11 to the December plan.
  - Record the narrowed scope as **withdrawn**, kept as history.

**C2. G0 gates construction instead of claims, and has no measurable pass criteria.**
- **The problem:**
  - S6/S8 are held until the G0 evidence is "credible" or "accepted", and the current disposition is "inconclusive".
  - G0 depends on benches from another lane that still fail (D11: 19/21, 7/7, 1/3, 2/6 errors).
  - The records also say "Arnav does not owe an XSim run", so nobody is obliged to produce a passing G0 run. The gate
    cannot close.
- **Fix:**
  1. **Decouple building from claiming.** Build S6, S7, S8 and S9 now, mode-gated. `TITAN_MODE=0` stays bit-identical
     to B0, so the 14 golden matches are the guard. G0 then decides which **claims and modes enter the paper**, not
     whether the RTL exists. The risk of building is near zero; the risk of waiting is missing 3 Jan.
  2. **Measurable G0 acceptance per case.** A case is accepted when all of these hold:
     - it runs as a registered `dual_lane.py` job with frozen counts;
     - a live passive monitor and an independent ledger agree on transaction identity;
     - a negative control is killed;
     - the evidence class is stated as **natural** (TB_INJECT=0), **compressed-legitimate** (injected GRANT/REVOKE timing
       the RoT could legitimately produce) or **injected-only**.

     The paper may claim natural and compressed-legitimate results, each labelled. "No research claim from injected-only"
     is kept.
  3. **Assign execution.** Arnav freezes the bench counts. Kalash's lane (Codex) registers and runs the benches
     unchanged. Arnav adjudicates the results.

## Important

**I1. Missed timing watch.** S5R adds logic on the request control path into the NI. DECISION_REGISTER "Timing watch"
requires an OOC/mesh timing check before the gate, but no TITAN LUT/WNS exists since S0. Run I-T5T now. The release S4
flow with the mesh split is enough. Gate: LUT ≤ 47,550, WNS ≥ 0; flag below +0.3 ns.

**I2. The monitor contradicts D10.** The S2 monitor bumps its epoch on every message and disagrees with D10 in 3 of 5
cases (`G0_INTAKE_D10_AUDIT`). Add a D10-aware monitor as a **new** simulation-only job before S6 verification. Keep the
S2 results as they are.

**I3. A-WRAP has a concrete remaining obligation; make it a task, not prose.** We have T_GG ≥ 360 (conditional), so the
budget is 63·T_GG = 22,680 cycles. The open item is the maximum stamp lifetime L, from stamp capture to last possible
effect. Owners: Arnav for the derivation, Codex for the measurement of maximum observed age in the contention benches.
If L cannot be bounded, state assumption A-LIFE (fair arbitration) in the paper.

**I4. P6 is a Tier-1 claim with no scheduled run.** The observation map exists (14 directed links, 42 VC lanes, NI slot
ledger). Schedule a bench-only ledger checker job in S7 week, because denials are exactly where credit and slot bugs
appear.

**I5. Rev 11 signature discrepancy left open for 4 days.** Close it today: Arnav sends his signature line for the
canonical copy, and Codex records it with the digest.

**I6. Uncommitted planning state.** Six planning records plus the CLAUDE.md change are untracked or modified in
`_titan`. Commit them as one docs-only commit, so the plan the team follows has a hash.

## Complexity / simplification

**S1. The plan documents are evidence ledgers, not plans.** `EXECUTION_PLAN` is 35 KB, including a 108-row hash table.
- Move the hash and provenance tables to a manifest JSON or MD file next to the evidence.
- Keep the plan to one page: dated critical path, owner per item, acceptance criterion, buffer.

**S2. One authoritative date table.** G0 currently appears as 30 Nov, 6 Dec and "decision by 30 Nov / review 27 Nov",
and the end date as 31 Dec handoff vs 3 Jan freeze. Keep a single table: frozen milestones, plus any owner-approved
change with its date.

**S3. Throughput.** Four days have passed with no RTL commit while planning and intake reviews multiplied. Set a rule:
every working day produces either a registered result or a closed decision. Reviews of incoming packets are time-boxed
to 2 hours.

## Optional

**O1.** "≥3 placement seeds per physical design" on FPGA means 6 modes × 3 = 18 runs, each run alone. Keep 3 seeds
for B0, B1 and TITAN only; use 1 seed for the ablations.

**O2.** Name the early-warning metric for 3 Jan: S6–S9 registered PASS by 22 Dec, otherwise escalate.

## Proposed corrected critical path (if the frozen scope governs)

| Dates | Kalash / Codex | Arnav | Exit |
|---|---|---|---|
| 26–27 Nov | I-T5T timing watch; commit planning docs; D10 monitor job | rev 11 signature; freeze G0 bench counts | timing PASS; signature recorded |
| 27 Nov–3 Dec | S6 guard, then S7 denial (mode-gated); P6 ledger job | fix benches; adjudicate the registered G0 runs | S6, S7 PASS |
| 3–6 Dec | S8 filter; register and run Arnav's G0 benches | G0 report with evidence classes | **G0: claims and modes decided** |
| 6–25 Dec | S9 bridge (code 6); S10 modes B0–B4/TITAN | formal F1–F6 on standalone blocks; mutants | S8–S10 PASS |
| 25 Dec–3 Jan | S11 merged core + firmware, full regression | ledger v1 | **RTL feature-complete 3 Jan** |
| 3–17 Jan | S12 FPGA per mode; S13 experiments | E1–E3; freeze re-run | **results freeze 17 Jan** |
| 17 Jan–1 Feb | S14 cut to the combined team; paper | verification sections | **paper 1 Feb** |

## Production-readiness gate (plan as written)

| Question | Status |
|---|---|
| Functionally correct path to the goal? | **No** under core-only scope (C1) |
| Verifiable gates? | **No** for G0 (C2); yes for S-stages |
| Optimized / simple? | Partially (S1–S3) |
| Documented / traceable? | Yes (strong) |
| Failure modes reviewed? | Yes (strong) |
| Blockers? | C1, C2 |

**Verdict: CONDITIONAL APPROVAL.** Fix C1 and C2 first; I1–I6 within the week.
