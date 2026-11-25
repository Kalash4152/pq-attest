# I-1 completion and stop checkpoint — 2026-10-09

I-1 completed with scheduler exit code 0 and 24/24 accepted jobs: 14 fresh,
10 matching historical reuses. NOC-1 is accepted. Work is stopped at Kalash's
request; I-2 has not started. The current ten-package release remains BLOCKED.

Built and tested source commit: `74c13c0` on `noc/credit-integration`.
This closeout changes documentation and its guarded payload copies only.
Evidence: `reports/dual_lane_10_20261008_235701_d7b8ee31/`, whose `status.json`
retains job identities, process status, observations and artifact hashes.
`reports/I1_CLOSEOUT_VERIFY_20261009.json` confirms all 24 artifact sets and
all 14 fresh source manifests still match at closeout, plus the protected hashes.
The launcher is installed at `scripts/run_dual_lane_10.tcl` and remains limited
to the frozen I-1 registry. It has not qualified later packages.

```text
NOC_PACKAGES_ACCEPTED=1/5
PQ_PACKAGES_ACCEPTED=0/5
DUAL_LANE_STATUS=BLOCKED
SOURCE_IDENTITY=dee22ceec8dc09e421f6a43e93890ffb21a391cb244022a314d179742a9d25c8
PYTHON_REFERENCE_ZIP=Pq_Attest_final.zip
PYTHON_REFERENCE_SHA256=047bb5a981050f11a572a60e850f7c7511ff5d636f7903c6a8d239891003c6a0
TILE_KEY_BYTES=32
PYTHON_RTL_COMPATIBILITY=NOT_RUN
EVIDENCE_DIR=C:/vivado_verilog_proj/NOC_PQATTEST/reports/dual_lane_10_20261008_235701_d7b8ee31
HARDWARE_VALIDATED=NO
SOC_INTEGRATION_COMPLETE=NO
ACTIVE_INCREMENT=I-1
INCREMENT_STATUS=PASS
FORMAL_PROOF=NO
```

## Changes and acceptance evidence

Baseline recovery restored the NI bench and six contracts with hash records;
overwritten and foreign files were preserved in recovery storage. The teammate
ZIP and extracted Python files remain immutable. Source-list collision checks,
atomic payload installation, bounded isolated jobs and source protection are
installed. The latest correction admits only exact causal XSim diagnostics
inside reviewed stimulus phases, checks complete per-test outcomes and rejects
unrelated errors or timeouts. Mutant B now has a separately identified private
T4/T5 injection window retaining all original 126 checks and test calls.

| Gate | Accepted observation |
|---|---|
| N-8.1 NI, M0/W16, M0/W1, M1/W16, M1/W1 | PASS_REUSED: 115/0, 114/0, 113/0, 112/0 |
| N-8.1 N-6 | PASS_REUSED: 126/0 |
| N-8.1 system M0/W16, M0/W64, M0/N0, M1/W16, M1/N0 | PASS_REUSED: 97/0, 43/0, 19/0, 43/0, 19/0; N0 expected-failure controls validated |
| Restored NI bench | PASS_FRESH: 161/0 |
| N-6 control before / after | PASS_FRESH: 126/0 each, same private bench |
| N-6 mutations A, B T4/T5, C | PASS_FRESH: KILLED; 126 checks each, 21 / 4 / 5 targeted errors; normal completion |
| D7 pipe1 / pipe0 | PASS_FRESH: 1756/0 / 1762/0; GuardChecks=111 each, ProtocolErrors=0, InjBlocked=0 |
| D7 M8 / N-6 | PASS_FRESH: 47/0 / 126/0 |
| D7 TB1 | PASS_FRESH: six zero-failure summaries, 21 positive guarded coverage fields, 2/2 negative controls |
| NI OOC | PASS_FRESH: WNS 4.464 ns, WHS 0.263 ns, zero latches; 747 cells; LUT 412, LUTRAM 24, FF 266, BRAM/DSP 0 |
| Mesh-only implementation | PASS_FRESH: 20 ns, WNS 0.202 ns, WHS 0.047 ns, WPWS 8.750 ns; TNS/THS/TPWS 0; route/DRC errors 0 |
| Python reference audit | PASS_FRESH: 8/8 teammate suites, 3 KMAC KATs, 9 SHA3 boundary comparisons, 24 repo/ZIP comparisons |

The installed automation correction passed 61/61 self-tests before this batch.
Preflight covered 71 guarded updates and 52 explicit source lists. All 48
protected hashes matched before and after execution. Existing user edits were
preserved; this does not establish the final I-8 clean-clone release gate.

Mesh reports and `routed.dcp` are saved under the run's `mesh_gate/`. The fresh
isolated build used Vivado 2024.1, `xc7a100tcsg324-1`, unchanged 20 ns XDC and
`Performance_ExplorePostRoutePhysOpt`, with no incremental checkpoint. Mesh
utilization: LUT 10114, LUTRAM 1716, FF 2178, BRAM 0, DSP 0. Timing has no
reported issues beyond the gate's known reset/LED exceptions. NI OOC uses
a 20 ns clock and 5 ns input/output budgets. Neither gate accepts integrated
subsystem timing or proves hardware operation.

Earlier failed and interrupted directories remain preserved. In particular,
the interrupted `dual_lane_10_20261008_214701_792bbd0d` mesh child wrote a partial
checkpoint after its parent stopped; it lacks completed supervision,
source-after and a gate verdict. It was never relabeled PASS. The old full-run
B watchdog remains an invalid mutation result, separate from the new scoped B.

## Stop and next delivery

An elevated Windows process audit at `2026-10-08T18:53:41.1229696Z` found no
process owned by the completed I-1 batch; its scheduler lock is absent.
Unrelated processes were left alone. No next-stage job or automation is started.

Resume at I-2: implement thin adapters to the pinned teammate reference;
separate its original 16-byte examples from the 32-byte RTL system profile;
consolidate Q-C/R-B, statuses, measurement boundaries and the approved L2/NI
revision in M-F1 rev 6 before dependent RTL; then execute golden comparisons,
controller mutations and post-format compatibility gates. PQ-1 is unaccepted
until those gates pass. Next increments cover performance/liveness and endpoint,
crypto OOC, L2, authorization/fault registers, security/full chain, and final
integrated timing and reproducible release, in the recorded dependency order.

Carried limitations: L-1 unencoded measurement split ambiguity (fixed per-tile
lengths must be recorded); L-2 stateless Python verifier; L-3 deterministic demo
keys/nonces; L-4 SHA3 full 136-byte final block and `is_final` stability are
outside the promised 135-byte API. There is no TRNG claim. Effective endpoint,
L2, authorization, replay and integrated security controls are still pending.
