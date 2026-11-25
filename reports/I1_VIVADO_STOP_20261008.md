# I-1 Vivado stop checkpoint — 2026-10-08

Resume audit correction: an elevated mesh child continued after the parent was
interrupted and wrote a post-route checkpoint at 22:05. The earlier sandbox
process check did not establish that every elevated child had stopped. The
child has no completed supervisor status, source-after manifest or gate verdict,
so that partial build remains unaccepted. A privileged process check on resume
found no surviving process owned by this evidence directory. Unrelated XSim
processes are left alone. New runs record each supervisor PID for precise
process-tree cancellation and catch keyboard interruption explicitly.

The earlier stop report claimed that no Vivado/XSim children remained, but its
sandbox process check did not see the elevated mesh child described above.
That claim is withdrawn. A later privileged resume audit found no surviving
process owned by this run; unrelated processes were left alone. The temporary
scheduler lock was removed after that audit. The raw run is preserved at
`reports/dual_lane_10_20261008_214701_792bbd0d/`.

## Fresh evidence

| Job | Observed result |
|---|---|
| `n81_nitb` | PASS_FRESH, 161 checks, 0 errors |
| `wp0_n6_control_before` | PASS_FRESH, 126 checks, 0 errors |
| `d7_n7_pipe1` | PASS_FRESH, 1756 checks, 0 errors |
| `d7_n7_pipe0` | PASS_FRESH, 1762 checks, 0 errors |
| `d7_m8` | PASS_FRESH, 47 checks, 0 errors |
| `d7_n6` | PASS_FRESH, 126 checks, 0 errors |
| `ni_ooc` | PASS_FRESH, WNS 4.464 ns, WHS 0.263 ns, 0 latches, 747 cells |

`d7_tb1` produced the expected foundation PASS but its deliberate negative
stimulus also emits assertion diagnostics. The generic adjudicator therefore
left it `INVALID`; a scoped reviewer was prepared under
`reports/i1_tb1_review/` and passed 61 synthetic-log tests. It has not been
installed into the launcher.

The N-6 mutations reached their targeted failures, but the generic adjudicator
did not accept them: `n6_a` and `n6_c` were rejected because their intentional
DUT assertions were treated as unexpected diagnostics; `n6_b` reached the
credit-loss checks and then timed out in a later test. The control-after job was
therefore blocked. No mutation is counted as killed.

`mesh_gate` was still in synthesis/implementation when the user requested the
stop. It has no timing verdict and is not a pass. The prior run status remains
`FAIL`; package acceptance remains NOC 0/5 and PQ 0/5.

The original protected RTL and user-owned dirty files were not changed by the
batch run. The live launcher and registry were not changed by the draft
adjudicator work. Continue from this checkpoint by reviewing the scoped
diagnostic adjudicator, then rerun the three N-6 mutation jobs and TB1 before
accepting NOC-1; only after NOC-1 and `python_ref` pass may I-2 begin.
