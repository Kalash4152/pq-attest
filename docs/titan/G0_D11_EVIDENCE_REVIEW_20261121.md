# G0 D11 evidence review and S6/S8 readiness — 21 November 2026

Scope: Kalash authorized scratch replay of Arnav's four updated benches, G0 evidence review,
S6/S8 plan review and a checkpoint. No implementation, registry, contract or bench changes.
This is D11 scratch evidence, not PASS_FRESH/PASS_REUSED or a G0 acceptance decision.
HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

## Baselines and integrity

- TITAN worktree: `C:/vivado_verilog_proj/_titan`, branch `kalash/titan-rtl`,
  HEAD `975ccfd9` at intake. Tracked working tree clean before this review.
- ZIP: `C:/Users/kalas/Downloads/TITAN_KALASH_HANDOFF_20261121.zip`,
  SHA256 `495e768fecb964f096f0371372bf7876931319dd7de44c4540f09b6ba2bd6079`.
  Its README identifies Arnav branch `arnav/titan-verif`, commit `ebbf491` (external provenance).
- Isolated extraction and runs: `C:/vivado_verilog_proj/_g0d11_20261121`.
  All four benches and both vector includes compared byte-for-byte with their ZIP entries.
- All 55 source hashes checked against `ARNAV_NOC_FILE_LIST_20261121.md`; selected matching
  bytes from `_t4rr`. This is the pinned B0 subsystem profile, not S5R TITAN hardware.
  `sources.prj` contains exactly those 55 files plus one unmodified G0 bench.
- Supplied `sim/g0/full_chain.svh` and pinned vector both hash to
  `eb38c2501903229287ab650c8c590fd1660d0b95f02814dafbcd3a05c03564f6`.
  `load_row` is now a bench-local wrapper around `load_chain`, assigning BOOT and KEYS.
- Tool: Vivado/XSim 2024.1. `PQ_MAC_ON`, bench default `TB_INJECT=1`, 20 ns clock.
  Includes: supplied sim/g0 first, supplied archive root, TITAN root.
  No natural-control profile is implied by the injected default run.

## Commands and replay disposition

The machine-readable manifests contain full argv, tool exit status, elapsed time and hashes.
Normal compile is `xvlog --relax -sv -d PQ_MAC_ON -i <sim/g0> -i <intake> -i <root> -prj sources.prj`;
elaborate `xelab --relax --debug typical --mt off xil_defaultlib.<top> -s <top>`;
simulate `xsim <top> -tclbatch bounded.tcl` from the case directory.
The launcher allows at most 2 ms simulated time and 240 s wall time per simulation.
Only an actual final RESULT with its frozen count and zero errors can be a bench-reported PASS.
Reaching either bound without a final verdict is incomplete, never a pass or mutation kill.

Preserved launcher diagnostics:

1. Strict compile (attempt 1): all four exit 1 at pinned SHA3_256_xp.sv:70,
   `ctrl_state` used before declaration. The established flow uses `--relax`; no source changed.
2. Attempt 2 compiled, but xelab rejected `--mt 1` (legal single-thread setting is `off`).
3. Attempt 3 uses `--relax` and `--mt off`. Initial xsim invocations rejected the unquoted
   Windows absolute CSV plusarg (`Expected a switch but found C`). Final replay uses the
   supplied default relative CSV names in a pre-created isolated `results/g0` directory.
   Bench code and vector bytes were not edited. Initial invocation logs remain preserved.

Final case results are in the checkpoint and `simulation_summary.json` beside the run logs.

All four compiled and elaborated with exit 0 in attempt 3. All four bounded simulation
invocations exited 0 via normal `$finish` before 2 ms, but their actual RESULT was FAIL:
M1 checks/errors 21/19; M2 7/7; M3 3/1; SD 6/2. Thus the previous unresolved-load_row
elaboration failure is resolved, while **none** is an accepted passing G0 bench.
Their printed reachability bits were M1=1, M2=0, M3=1, SD=1; these do not override FAIL.

### First-divergence diagnosis (unaltered M1 VCD)

The M1 trace shows `grant_done` rising at 19,750 ns and falling at 19,770 ns; tile-3
`authorized` rises only at 24,350 ns. The check at tb_g0_m1.sv:150–151 treats verifier
completion as if the transported GRANT has already reached the requester. That premise
is false for this run (4,600 ns/230 cycles between pulses). The check needs the receiving
gate transition and a bounded wait; Arnav owns any fix.

The first injected REVOKE clears authorized at 24,450 ns and the injected GRANT raises
it at 24,630 ns. Each is on the posedge at which the bench deasserts injection and checks
the registered output, before its nonblocking update is visible. Both associated bench
checks fail even though the waveform contains the subsequent transition. Keep the
receiving gate sample convention explicit; recommend drive on negedge and check after
the sampled edge/NBA (or use a clocking block). This is a bench scheduling diagnosis,
not authorization to change timing or gate RTL. Parsed transitions and original VCD hash
are saved with the scratch evidence. Other case failures have the same initial-grant
check pattern; no corrected bench was run to claim closure.

## Verdict-to-witness acceptance map

| Case | Frozen count | Required event chain | Current bench limitations / required cross-check |
|---|---:|---|---|
| M1 | 21 | Requester/tag generation accepted under epoch k; actual authorized 1→0→1; same write reaches tile 2 and commits after regrant, with old request stamp | `tb_g0_m1.sv:165–210` discards handshake booleans, samples authority at a posedge with injected updates, polls RAM and timestamps the later observation, not commit enable. Require accepted HEAD/address/data and commit edge trace; prove transition ordering for the same transaction. Nine sweep rows alone cannot prove it. |
| M2 | 7 | Read accepted, responder offer and requester HEAD recorded, revoke boundary, actual data-valid delivery while unauthorized; distinguish before-HEAD from after-HEAD revoke | `tb_g0_m2.sv:179–195` looks at `dut.rhv`/`dut.rpv` and magic data, not an independently keyed exported-response trace. The data check does not itself require rpv or successful handshake booleans. Initial memory preload is before reset; verify retained fixture data. D6 HEAD-latched semantics must be classified separately. |
| M3 | 3 | Accepted bridge transaction; actual timeout/UNKNOWN for that transaction; later same-request memory side effect | `tb_g0_m3.sv:162–165` waits 4200 cycles and calls `check(1, ...)`. Subsystem top has no CPU bridge. This is explicitly modeled elapsed time; cannot establish software UNKNOWN or a real bridge-timeout race, even if the bench prints PASS. CSV hard-codes 4096 and records observation time. |
| SD | 6 | Tile-2 request arrival and denial reason; no definitive response throughout a bounded window; live/stale slot transition and actual release cause for matching tag | `tb_g0_sd.sv:174–186` does not assert m_ev arrival or reason, checks response only after 200 cycles, and assumes slot 0. Both CSV rows hard-code stale/suppressed bits. Last-word case checks memory unchanged but not full response suppression or slot release. `sd_seen_count` increments unconditionally. |

The restored CONFIG and frozen RESULT checks resolve r2's missing verdict-count discipline.
They do not validate each check's meaning. Compare actual final checks against 21/7/3/6;
do not infer a property from a normal simulator exit, CSV presence, or the supplied summary report.
Benches contain unbounded `grant_done`/authorization waits: a missing verdict needs diagnosis.

## Does the monitor actually run?

No finality-monitor source is in these 55+1 project lists. No bench instantiates it.
The existing `rtl/dual_lane/titan/titan_mon_bind.sv:69–97` wrapper instantiates
`tb_matched_memory_v10` and binds `titan_mon_taps` to `pq_soc_merged_core`; G0 tops
instantiate `pq_noc_subsystem_p7` directly. Therefore these replays cannot claim a live monitor.
Check both elaborated instance presence and startup/heartbeat plus transaction events in any
future monitor-enabled run; empty TITAN_EVENT output alone is ambiguous for a quiet workload.
Do not add the merged wrapper as another simulation top just to obtain monitor output.

Historical S2 monitor semantics must remain unchanged: accepted GRANT/REVOKE shadow bumps,
NI-allocation issue stamp, stale-slot rise rather than final slot release, bridge timeout
associated with last issue tag. S5R uses D10 registered authorization rise and first-valid
application HEAD epoch capture. Reconcile these differences explicitly before comparing events.

## Scoreboard challenge and comparison procedure

Confirmed scratch reproducer:

```
python -E <intake>/scripts/titan/verif/scoreboard.py --mode 0 --monitor-csv <absent_monitor.csv> --bench-csv <absent_bench.csv>
```

Exit **0**, `[PASS] Scoreboard and Monitor in 100% agreement.` with both paths nonexistent.
Raw output: `_g0d11_20261121/scoreboard_empty_input.txt`. The supplied scoreboard's
`load_monitor_csv` / `load_bench_csv` silently return on missing paths; `reconcile` only
compares summary counters. `bench_txns` is loaded but never replayed through the model.
Consequently zero model counters can agree with absent/empty events while transactions
were never evaluated. This is a verification-tool defect to return to Arnav under D11.
The supplied G0 sweep schemas also differ from SCOREBOARD.md's transaction schema.

Required future comparison (review plan, not an implemented checker):

1. Fail closed on missing inputs, malformed rows, absent expected case/transaction count,
   missing live-monitor instance evidence or incomplete final verdicts. Validate schemas.
2. Emit a transaction ledger from actual handshakes/decisions, not sweep summary flags.
   Key `(run, case, reset interval, requester, NI tag, allocation generation)`; tags/cycles reuse.
3. Preserve pre/post-edge convention. Record request first-valid stamp separately from
   NI allocation stamp, actual authorized transitions and receiving gate events.
4. Feed those events through Arnav's reference model in B0 mode; assert nonzero processing
   for cases that require transactions. Compare event identities and first divergent cycle,
   then counts. P1 is broader than M1; P2 and D6 after-HEAD behavior are distinct;
   M3 requires bridge identity; SD expiry differs from slot/credit release. P6 remains X.
5. Include negative controls: missing/empty files, one altered tag, one deleted event,
   duplicate response, changed ordering, injected mismatch, and a nonempty agreeing fixture.
6. Classify each gap as observed / not observed in exercised profile / inconclusive.
   Cross-check Arnav's supplied claim against local raw witnesses. Only Kalash selects G0 scope.

## S6 and S8 readiness against S5R and signed revision 11

Reviewed `S6_S9_VERIFICATION_PREP_20261121.md`, S5R report, generated S5R subsystem,
`titan_epoch_tracker_r1.sv`, `titan_epoch_stamp.sv`, local revision 11 and the signed copy
in Arnav's ZIP. The archive records Arnav's signature dated 21 Nov; the local document still
says pending. Preserve both; reconcile the document through the normal owner lane rather
than silently overwriting the local signed contract. H1 and D10 both specify only 0→1 rises.

| Stage | Assessment | Required details before implementation |
|---|---|---|
| S6 | Preparation is usable; implementation held at G0 | Last-word guard must drive internal-array effects and external `mem_en` identically (S5R :349–387), including reads. Snapshot remains first-valid epoch, not a replacement at tile-2 HEAD or inner NI allocation. Preserve tag, strobes and tile-4 bypass. Test actual same-edge authenticated revoke per D8, authorization+epoch combinations, stale reads/writes, both tags, and address priority D2. Mutation set must kill inverted equality, HEAD-resampling, bypass removal without timeout acceptance. |
| S8 | Preparation is usable with boundary cases explicit; implementation held at G0 | Filter exported memory read responses (:391–405), not arbitrary raw NI data. Preserve responder `rd_gate` (:331–333). Mode 3 authority only; mode 5 authority+echo. D6 fixes decision on accepted HEAD including same-cycle HEAD/data, then holds through data/last/abort; revoke after that HEAD does not retroactively deny it. Writes pass unchanged, denied read data zero, DENIED_FILTER local, no extra cycle. Mutations: writing-filter, missing mask, per-word decision. Recheck matched 32-cycle median after the selected implementation. |

S5R's registered historical result is 20/20 PASS_FRESH, 14/14 immutable golden matches,
with stamping and two-tag observations. It establishes neither commit guard nor read filter.
The older `titan_epoch_tracker.sv` is historical; S5R instantiates `titan_epoch_tracker_r1`.
No source list or job registry was changed by this review.

Open G0 inputs: credible local M1/M2/SD witnesses, real monitor comparison, actual bridge
M3 evidence if claimed, independent scoreboard processing, injected/natural profile separation,
A-WRAP lifetime and receiving-gate interval proof (63*T_GG >8192, T_GG>=131), full-mesh P6,
and Kalash's scope decision. Do not revert to superseded 31*T_GG or bump-on-REVOKE semantics.
S6/S8 implementation, fresh job registrations and frozen counts remain behind G0.
