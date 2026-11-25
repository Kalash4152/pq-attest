# I-1 harness correction and required requalification

The failed run `dual_lane_10_20261008_214701_792bbd0d` is retained unchanged.
N-6 A/C completed all 126 checks and produced their targeted test failures and
causal DUT assertions; the generic diagnostic parser incorrectly rejected those
assertions. TB1 deliberately exercises overflow, underflow and a multi-hot VC
selection; it has six zero-failure summaries, nonzero guarded coverage and two
negative controls, but the generic parser rejected its deliberate diagnostics.

`controlled_diagnostics.py` admits only complete XSim diagnostic blocks with
the reviewed message, instance, file and source locations during the relevant
stimulus phase. It records every admitted diagnostic. Unrelated assertions,
missing phases, coverage holes, inconsistent counters, incomplete test runs and
all timeouts are rejected. This correction does not disable a DUT assertion.

The original full-run credit-loss mutant B produced its targeted T5 failures
and then hit the global watchdog in an unrelated later test. It remains INVALID
and is never counted as a kill. The new `wp0_n6_mut_b_t5` job freezes the same
126-check requirement before its first run. It injects the same WEST VC0 loss
only during the original T4/T5 task, then disables the injection before later
tests. All original checks and test calls remain. Both 126/0 controls compile
the same private bench, so its added control signal is checked without a mutant.
The live router and original N-6 bench are never written. The generator's
exact source/variant hashes and diff are at
`sim/dual_lane/n6_credit_window/source_delta.json`.

The NOC-1 list remains 23 jobs, followed by the separate Python reference job.
The old job's failed registry remains in its original run. Current identity
includes the diagnostic module, child script and native supervision helpers.
Changed identities require fresh execution; prior failures are not relabeled.

The user explicitly authorized Codex to run the I-1 Vivado jobs, superseding
the execution assignment in Revision 4 while preserving its dependency gates
and stop-after-I-1 delivery boundary. Formal proof, board validation and SoC
integration remain NO. Mesh-only timing cannot accept N-13 integrated timing.

## Fresh requalification — 2026-10-09

Installed correction commit: `74c13c0`. The 61 automation self-tests passed
before the new batch. Run `dual_lane_10_20261008_235701_d7b8ee31` subsequently
accepted all 24 I-1 jobs, including fresh controls before/after (126/0), A
(126 checks / 21 targeted errors), B T4/T5 (126 / 4) and C (126 / 5).
Each mutant completed normally; no timeout was accepted as a kill. TB1 passed
all six zero-failure summaries, 21 guarded coverage fields and both negative
controls with only its reviewed causal diagnostics admitted.

Fresh NI OOC and mesh implementation passed. The ten archived N-8.1 records
were reused only after identity and raw-evidence validation. The earlier failed
and interrupted run remains unchanged and unaccepted for its failed jobs.
No protected production source or original N-6 bench was edited. Work is stopped
after I-1; see `reports/I1_COMPLETION_20261009.md` for the complete checkpoint.
