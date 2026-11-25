# N-8.1 P7 resume checkpoint, 2026-10-25

Base commit: de2f2cc. This is a scratch qualification checkpoint, not an I-5 PASS gate.
Registered jobs launched: 0. Newly accepted/fresh/reused registered results: 0/0/0.
No new area or timing measurements. Prior S1 proxy: synthesis 44,412 LUT, routed WNS +0.165 ns / WHS +0.013 ns.
HARDWARE_VALIDATED=NO; SOC_INTEGRATION_COMPLETE=NO; FORMAL_PROOF=NO.

## Completed

- Resumed the standalone `tb_noc_n81_p7.sv` and preserved the protected original.
- Retained the approved production per-packet bound in `noc_p7_pkg`; no production RTL changes in this checkpoint.
- Removed the obsolete N-8.1 entry from the edit-list generator: the new system bench is standalone.
- Corrected N0's probe: the stalled receive interface is valid/not-ready even after the short packet's allocator lock releases.
- Made the N0 control-confirmed marker conditional on successful checks.
- Strengthened recovery to require exactly one complete later write packet and no new abort.
- Replaced the ineffective extra-payload LONG stimulus with an isolated counterfactual: copied packages give MEM_WR_REQ
  16 payload words / 17 wire flits and omit the copied production elaboration guard. The production bound stays active.
- Added `scripts/prepare_n81_p7_scratch.py` to produce explicit source/define manifests and launch scripts outside the repository.
- Added a normal-ending watchdog-off companion to demonstrate why the LONG recovery occurs.

## Results

| Build | Checks/errors | Process/evidence status |
|---|---:|---|
| Production profile, watchdog on | 20/0 | Prior scratch run completed cleanly; not registered |
| Production profile, watchdog off (N0) | 2/0 | Prior console run exited 0; eject valid=1, ready=0, allocator lock=0, payload=0, containment=0 |
| Counterfactual LONG, watchdog on | 2/0 | XSim compile/elaboration/simulation exited 0 on 2026-10-25; one first-launch failure retained |
| Counterfactual LONG, watchdog off | 2/1, RESULT FAIL | XSim exited 0 normally; exactly the targeted LONG recovery assertion failed; not a timeout kill |
| Automation suite | 107 tests, OK | Re-executed 2026-10-25 |
| P7 NI provenance | PASS | `prepare_p7ni.py --check`, 26 edits |
| Scratch fixture generator | Python compilation PASS | Prepared and used for both final LONG variants |

The enabled LONG run observed upstream_cycles=31, upstream_locked=0, aborts=1, contained=1.
The disabled companion observed upstream_cycles=192, upstream_locked=1, aborts=0, contained=0.
Both ended at 2265 ns. Their expected-check counts are 2; the disabled control is expected to produce one targeted failure.
This demonstrates watchdog-dependent recovery for the counterfactual. It is not a legal production P7 packet.

Evidence: `reports/N81_P7_RESUME_SCRATCH_20261025/summary.json`, per-build logs/manifests/diffs, plus preserved
2026-10-23 diagnostic artifacts. A printed PASS followed by a stuck launcher was never promoted to acceptance.
XSim first-launch stalls/crashes were retried once on the same snapshot; failed startup logs remain alongside the final logs.
The sandbox's temporary-directory cleanup errors in an earlier unit-test invocation were resolved by a normal-permission
run; the final 107-test run passed without changing the tests.

## Exact resume point

The resumed N0/LONG diagnostic task is complete. No registry regeneration, registered simulation, synthesis or routing was
performed. The previous official latest pointer remains the 2026-10-23 I-5 section-8 run, BLOCKED for remaining work.

Next work remains I-5 section 9, in this order:

1. Review scenario coverage before freezing jobs. The standalone bench currently checks eject containment, complete recovery,
   clear/persistence, one answered read transaction and backlog upstream activity/release. It does not measure the proposed
   C1/C2 `T_A == T_B0` matched non-interference criterion, or useful concurrent traffic loss/duplication during backlog.
   Those requirements need explicit new checks/jobs, not a claim inferred from the current 20/0 result.
2. Integrate the approved N-8.1 NI/system profiles, framing, N-7.5 finite liveness and hop adaptations into the section-9 group.
   Derive and freeze each new job's checks and targeted control behavior before its first registered run.
3. Resolve the full-subsystem NOC-2 traffic profile: non-attested tiles cannot send ordinary application data through the
   default authorization gates. Separate an approved transport-measurement profile from security-enabled evidence.
4. Run the section-9 group through `dual_lane.py`; batch identity regeneration once the group is ready. Preserve matching
   existing evidence and re-earn changed dependency closures. Scratch results are not PASS_FRESH/PASS_REUSED substitutes.
5. Write the I-5 gate report only after all required section-8/9 coverage is accepted.

Previously accepted milestones: S1 39/39 on its recorded identities; I-5 section 8 13/13 on run 135247_e283de15, including
tile-4 accounting 30 accepted = 30 replayed + 0 rejected. Hold maxima were zero in that section-8 load; do not claim it
exercised tile-4 backpressure. The later package edit re-identifies dependent P7 jobs when regenerated.

After I-5: measure complete attestation timestamps/overhead; obtain the measured six-core/memory/glue resource budget;
evaluate only justified timing improvements. Keep reset distribution and crypto sharing as separate reviewed design changes.
Original later increments remain I-6 NOC-4 authorization/isolation/revocation, I-7 PQ-4/PQ-5 security/full-chain closure,
and I-8 NOC-5 regression, N-13 full-top timing and reproducible release/launcher qualification.

## Preserved working state

This checkpoint deliberately does not stage unrelated P4 reports, old project edits, latest-pointer edits or foreign files.
The fixture producer writes only a new external scratch directory; it refuses paths inside the live repository.
Do not reuse the earlier malformed-define, invalid eight-word stimulus, failed old N0 probe or interrupted wrapper records
as accepted evidence. No protected source, signed bound, wire format, clock, device, judge rule or frozen registry count changed.
