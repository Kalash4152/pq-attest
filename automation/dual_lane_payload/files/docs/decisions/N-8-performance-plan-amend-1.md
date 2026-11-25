# OD-6 / N-8 performance plan — amendment 1 (2026-10-20)

**Decided:** Kalash, 2026-10-20. Amends `docs/decisions/N-8-performance-plan.md` (OD-6, approved 2026-10-08).
Everything not listed here is unchanged.

## Change

- **Hotspot** (pattern 2, destination MEMORY index 2): source tile 2 is **idle**. The original text said
  "including its local loopback"; that is withdrawn.
- **Transpose** (pattern 1, `2*x+y` permutation): its two fixed points (tiles 0 and 5) are **idle**. The original text
  said "including its two fixed points"; that is withdrawn.
- **Idle means:** the source generates no offers at all. It still appears in every per-tile report line with `offered=0`
  and all derived counters 0; it is never omitted. It still serves as a destination and memory stand-in where the
  pattern targets it (hotspot tile 2 keeps receiving).
- **Uniform** (pattern 0, skips the source) and **neighbor** (pattern 3, Hamiltonian cycle with no fixed point) are
  unchanged.

## Reason

The production router forbids local-to-local traffic: `noc_router.sv:690-693`, `a_no_loopback_local_sync`. The first
I-3 batch (`dual_lane_10_20261020_000438_d4ad56ae`) logged 15,144 of these errors in perf_m0, 45,432 in perf_m1 and 106
in perf_ctrl_stall. This amendment matches the hop probes, which exclude loopback pairs for the same reason
(`reports/i3_hp/HP_COUNT_DERIVATION.md`). Kalash chose to amend the plan, **not** to classify the router check.

## Effect on frozen expectations

- **perf_m0 / perf_m1:** offered and queued now count active sources: uniform 6, transpose 4, hotspot 5, neighbor 6.
  CHECKS is unchanged (393: the 28 `check()` call sites are textually identical).
- **perf_ctrl_stall** (hotspot 1/16): offered = queued = 680, and liveness masks `ds/queue/slot = 3b`. CHECKS 15 and
  ERRORS 6 are unchanged.
- **Unaffected:** perf_ctrl_corrupt and perf_ctrl_drop (uniform 1/16) and the six N-7.5 jobs (patterns 0 and 4).

The superseded counts (816 / `3f`, 6-source transpose and hotspot rows) stay in `reports/i3_n2/N2_COUNT_DERIVATION.md`
and in the first-batch evidence as history. They are superseded by this amendment, not edited.
Derivation: `reports/i3_n2/N2_AMEND1_DERIVATION.md`.
