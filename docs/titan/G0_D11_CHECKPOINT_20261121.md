# D11 checkpoint — updated Arnav G0 replay

Date: 21 November 2026. Audited commit `975ccfd9` on `kalash/titan-rtl`.
Scope completed: four unchanged-bench XSim scratch replays; verdict/event review;
monitor/scoreboard assessment; S6/S8 readiness review. No job registered.
Registered accepted/fresh/reused counts: N/A (D11 scratch only).
LUT/WNS: not measured. No synthesis, implementation, board or formal run.
HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

| Bench | xvlog / xelab | XSim process exit | Frozen / actual checks | Errors | Final verdict | Printed reachability |
|---|---|---:|---|---:|---|---:|
| M1 | 0 / 0 | 0 | 21 / 21 | 19 | FAIL | 1 |
| M2 | 0 / 0 | 0 | 7 / 7 | 7 | FAIL | 0 |
| M3 | 0 / 0 | 0 | 3 / 3 | 1 | FAIL | 1 |
| SD | 0 / 0 | 0 | 6 / 6 | 2 | FAIL | 1 |

All ran with XSim 2024.1, PQ_MAC_ON, the exact hash-checked 55-file B0 source list,
default TB_INJECT=1 and 20 ns clock. All reached `$finish` within the isolated launcher's
2 ms simulation limit. All CONFIG banners and frozen counts were present.
These are failed benches, not registered evidence and not proof the TITAN design fails.
Previous `load_row` elaboration blocker is resolved by the updated bench wrapper.

ZIP SHA256: `495e768fecb964f096f0371372bf7876931319dd7de44c4540f09b6ba2bd6079`.
Raw artifacts: `C:/vivado_verilog_proj/_g0d11_20261121`, preserved including initial launcher
failures. Final run directories: `attempt3/{m1,m2,m3,sd}`. Source/vector/ZIP hashes,
commands, compiler logs, verdict extracts and summaries are copied text-only under
`docs/titan/d11_evidence_20261121`. Full simulation transcripts remain in scratch.
VCD/build products remain in scratch with hashes in the artifact manifest.

Key findings:

- M1 VCD confirms grant_done at 19,750 ns precedes requester authorization at 24,350 ns;
  checking authorized immediately after grant_done causes the initial check failure.
  Injected revoke/grant checks also sample at the update edge before NBA visibility.
- Four source lists lack monitor sources and the merged-core bind target. Zero monitor
  events is not monitor agreement; no live monitor exists in these runs.
- Unchanged supplied scoreboard reports PASS/exit 0 for two nonexistent inputs. It never
  replays its loaded transaction rows into the model. Reproducer and output saved.
- M3 only models elapsed timeout (`check(1, ...)`), with no actual CPU bridge.
- SD CSV still contains literal stale/suppressed flags, and its absence observation
  checks a single endpoint sample rather than the complete interval.
- S6/S8 preparation matches the S5R integration points and D10/D6/D8 intent, but passing
  G0 witnesses, an actual independent comparison and Kalash's scope decision are pending.

Detailed event matrix, source locations, comparison method and mutation readiness:
`G0_D11_EVIDENCE_REVIEW_20261121.md`.

Needed from Arnav (do not fix his files in this lane):

1. Correct receiving-GRANT wait and injection sampling with bounded waits; retain counts
   or document independently revised frozen checks before running updated benches.
2. Assert accepted HEAD/address/data and actual decision/delivery events, with transaction
   identity, reset interval and generation. Provide raw traces and full absence windows.
3. Provide a compatible live monitor path plus a scoreboard that rejects absent input,
   evaluates real transactions, and passes targeted negative controls.
4. Ground M3 in actual bridge timeout/UNKNOWN if claiming it; distinguish modeled timing.
5. Supply injected versus natural-profile evidence and resolve A-WRAP lifetime/P6 inputs.

The ZIP includes Arnav's revision-11 signature; local revision 11 still says pending.
Record this provenance discrepancy for G0 reconciliation; contract text was not overwritten.
S6 and S8 implementation stays behind G0. Next dependency: corrected independent G0 evidence
and Kalash's explicit G0 scope decision. D11 fallback date remains 3 December 2026.
