# TITAN S10–S11 regression matrix draft

21 November 2026. Plan only, from S5R checkpoint dad730cd. Use the S1 golden CSV and the selected G0 branch. Every future run or matrix cell must name the mode, exact source identity and selected increment. No cell in this draft is a new result.

## Mode expectations to confirm after G0

| Mode | Original profile | Required distinguishing check if selected | Evidence boundary |
|---|---|---|---|
| 0 / B0 | Revision-10 behavior | All 14 S1 cases match check observations, completion periods and recorded latency medians. Confirm every independently established B0 G0 witness using identical scenario inputs. | Reference for both functional and cycle comparisons. |
| 1 / B1 | Explicit denial and outcome mapping | Reachable silent-denial cases retire by the intended response, with matching tag and one definitive result, zero denial data, and zero unintended memory effects. | A previously reachable M1/M2 case is tracked separately. |
| 2 / B2 | D3 global drain comparator | On accepted REVOKE, backpressure new HEADs globally; in-progress traffic drains and all traffic resumes. Test a second REVOKE, idle release, no drop and bounded observation of a stuck drain. Record drain cycles and request latency. | Do not derive a P5 bound from the experiment. Confirm exact drain and denial composition in the approved mode map. |
| 3 / B3 | Read filter and outcome mapping | On the reachable M2 sweep, compare the response HEAD/data/last/abort, zero data on filtered reads, and confirm write pass-through. Verify zero additional cycles on the clean matched workload. | State the D6 HEAD boundary used in the oracle. |
| 4 / B4 | Epoch tracker/stamp/guard with silent drop | Re-run the same reachable M1 inputs with zero stale commits; check same-cycle REVOKE, two tags, and stale-read memory admission. Record any SD events. | The S4R/S5R results cover the tracker and stamp only. |
| 5 / TITAN | Combined selected blocks | Run the reachable G0 sweeps with the selected guard, denial and filter behavior. Check one CPU outcome, no unintended effects, and compare transaction outcomes with the monitor/scoreboard. | Report M3 as an observation and separate proof/coverage of P5, P6 and A-WRAP. |

## Suite and evidence matrix

| Suite | S10 run | S11 run | Acceptance and captured evidence |
|---|---|---|---|
| Frozen baseline | Mode 0 exact comparison against all 14 S1 rows/jobs and their metrics. Non-revoking common workloads in all selected modes. | Repeat on the integrated source identity. | Use archived check names/order, emitted observations and completion periods. Preserve the B0 secure matched read/write median of 32 cycles. For other modes, use the approved behavior/latency target for each workload. |
| Registered merged core | Run representative shared and distinguishing cases as blocks are composed. | In-flight, approved-change attack, contention and phase sweep across all approved modes. Full approved regression in modes 0 and 5 where selected. | Existing job checks stay frozen. Capture per-mode side effects, exact outcomes, latency/control traces and the mode configuration line. |
| G0 and follow-up races | M1, M2, M3 and SD on the branches relevant to the accepted reference witnesses. | Repeat the accepted sweeps against the integrated identity. | Preserve traffic assumptions and input hashes. Map each case to monitor/scoreboard agreement, memory effects, definitive outcomes and retirement. Record unreachable or inconclusive cases explicitly. |
| Unit controls and mutants | Retain stage evidence by exact source hash. Select fresh reruns where composition affects the origin or oracle. | Requalify agreed mutations and integration controls against freeze candidate. | A targeted negative control needs the complete intended assertions, the expected failure and a normal verdict. |
| Firmware smoke | Identify the release defines, revision-10/padded demo firmware and board/core mode plumbing from the qualified lists. | XSim boot in mode 5 where selected, with mode 0 comparison. Justify intended UART differences against the outcome contract. | Capture exact firmware hash, UART output, required boot/attestation and memory checks, and the B0 equivalence verdict. |
| Compilation and lint | Elaborate each requested mode using one same-name source variant and an explicit list. | Run against the final source list and record new diagnostics against the baseline. | Check source identity, package resolution, mode propagation, and no diagnostic suppression. Keep optional lint results distinct from Vivado evidence. |

The six profiles describe the original full scope. A reduced G0 scope gets explicit out-of-scope cells and an updated objective from Kalash. Use the current D1 source-list swap and the registered dual_lane.py runner. Mode 0 and mode 5 releases may use different explicit lists as appropriate, with the board part, clock, pins and firmware identity recorded. The original S11 macro instruction has been superseded by D1.

For every matrix result record stage, mode, bench, frozen counts, acceptance state, raw observations, completion cycles, P1/P2/P3/P4/SD/M3 counters where observed, P6 class, run and source manifest. P5 and A-WRAP get separate bound records. Pass the S10 gate on approved matrix cells before integrating S11. The S11 freeze note and tag require the full selected matrix and firmware/lint results. FPGA metrics belong to S12.
