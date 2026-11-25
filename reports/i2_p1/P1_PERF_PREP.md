# P1 perf prep (I-3 NOC-2, prepare only)

Date 2026-10-19. Branch `worktree-agent-a09432629de0aa7ab`, base 0b5c0d6 (noc/credit-integration).

**This is not evidence.** Nothing here was produced by `scripts/dual_lane.py run`. I built in a
scratch directory with flags that copy the registry export, and ran one 200 us MAC-off smoke run
to see that the bench starts. No expected counts are frozen. `dual_lane_jobs.json` and `STATUS.md`
are unchanged.

## 1. Build status

Source list: the 12 `sources_1/new` files from `perf_m0`/`perf_m1`, plus `sim_1/new/tb_noc_perf.sv`
and Vivado's `glbl.v`, in registry order. Tool: Vivado/XSim 2024.1.

The flags copy the registry's export_simulation scripts (taken from d7_tb1 `compile.bat`/`elaborate.bat`):

```
xvlog.bat --relax [-d PQ_MAC_ON] -prj p.prj -log xvlog.log
xelab.bat --debug typical --relax --mt 2 -L xil_defaultlib -L uvm -L unisims_ver -L unimacro_ver \
          -L secureip --snapshot tb_noc_perf_behav xil_defaultlib.tb_noc_perf xil_defaultlib.glbl -log elaborate.log
xsim.bat tb_noc_perf_behav -tclbatch smoke.tcl     (smoke.tcl = "run 200us; quit")
```

| Step | Before fix | After fix |
|---|---|---|
| `prepare_perf_bench.py` regenerates the committed TB | byte-identical (sha 40092a76…) | regenerated from the edited include |
| xvlog, MAC-off | RC 0, 0 warnings | RC 0, 0 warnings |
| xelab, MAC-off | **RC 1**: `ERROR: [VRFC 10-2991] 'fifo_full' is not declared under prefix 'r' [tb_noc_perf.sv:269]`, then `[XSIM 43-3322] Static elaboration ... failed` | RC 0, 0 warnings, `Built simulation snapshot tb_noc_perf_behav` |
| xvlog + xelab, MAC-on (`-d PQ_MAC_ON`) | not attempted (same error) | RC 0 / RC 0, 0 warnings |
| xsim smoke, MAC-off, 200 us | — | RC 0. Printed the CONFIG line and the PERF and MONITOR lines for points (uniform, period 64/32/16), plus 2639 TRACE lines. No `[FAIL]`, no fatal error. |

**Fix.** `noc_router` has no `fifo_full[]` array. Its per-port/VC full flags are separate named
signals, `full_<north|south|east|west|local>_vc<0..2>`. In `perf_bench_body.sv.inc` the
`full_cycles[g][v]` monitor now adds up those 5 port flags for each VC. The `credit_count` monitor
is unchanged. I then regenerated the TB with `prepare_perf_bench.py`.

- The per-instance NI port binding in the scaffold (copied from `tb_noc_n81.sv`) is untouched.
- No RTL or production file was edited.

**What the smoke run showed (scratch only, not evidence).**
- Uniform 1/64 and 1/32 drain within the generation window (`elapsed=2176`). Uniform 1/16 drains
  17 cycles after it (`elapsed=2193`).
- A dry run of the report parser on the smoke log (`_p1_scratch/report`) shows uniform 1/8
  delivering about 0.059 packets/cycle/tile, against 0.125 offered. Mean queue latency is about
  895 cycles.
- This fits a closed-loop limit from N_OUTSTANDING=2: 2 slots / ~34-cycle round trip ≈ 0.059. The
  network itself is not the bottleneck. The curves will show the NI outstanding limit, not mesh
  saturation, and the write-up should say so.

## 2. Review against N-8 / N-7.5 / NOC-2

| Requirement | Status | Where / note |
|---|---|---|
| 4 patterns: uniform, transpose, hotspot, neighbor | PRESENT | `destination()`. Uniform: `rng%5`, skip self. Transpose: `2*(s%3)+s/3`. Hotspot: tile 2, including self. Neighbor: 0→1→2→5→4→3→0. All match N-8. |
| 7 rates 1/64..1 | PRESENT | `period=64>>rate`, rate 0..6. Injection is deterministic, one offer every `period` cycles (`cyc%period==t%period`), not Bernoulli. N-8 does not say which. |
| 2 MAC modes = 56 points | PRESENT (split) | Each build runs 28 points. `perf_m0` has no define and `perf_m1` uses `PQ_MAC_ON`. `perf_report.py` needs both logs to reach 56. |
| Seed 0x12345678, LCG 1664525/1013904223 | PARTIAL | The LCG matches. Each source is seeded `0x12345678+t`, which N-8 does not state (OQ-2). The CONFIG line carries `SEED=305419896`. |
| Warm-up 128, measurement 2048 | PARTIAL | The TB only has `GEN_CYCLES=2176` (=128+2048). The window [128,2176) is applied in `perf_report.py` only. The TB prints no window markers. |
| Drain ≤ 50,000 | PRESENT | `DRAIN=50000` bounded loop, then `check(drained(),"PERF_BOUNDED_DRAIN")`. |
| Cap 256 per source, separate generator drops | PRESENT | `CAP=256`. `offered`, `generated`, `drops` are kept separately. `PERF_GENERATOR_ACCOUNTING` checks offered = generated + drops. |
| Reset between points | PRESENT | 5-cycle `rst` before each point, with all TB state cleared. |
| N_OUTSTANDING=2 preserved | PRESENT (implicit) | `NOC_PKG.sv:337`, unchanged. The TB does not print or assert it (OQ-3). |
| Memory-response stand-in, so NI slots retire | PRESENT | Each destination queues `MSG_MEM_WR_RESP` to the source. `drained()` requires responses == accepted. |
| Scoreboard uses generator records only | PARTIAL | Expected destination and address come from `expected_dest[src][seq]`. Expected data is the pure function `data_of(src,seq)`. But the lookup key (src, seq) is read from the DUT (`rx_src`, `rx_pd[15:0]`). If seq bits are corrupted, the packet is attributed to a different seq; this shows up as MISSING plus PAYLOAD/ADDRESS/DUPLICATE/UNKNOWN, not one clean mismatch. Per-(src,dst) order is not checked. The MISSING scan covers `q<accepted[t]` only. Packets queued but never accepted are covered only through `drained()` (`qread==generated`). |
| Timestamps gen/accept/inj/del | PRESENT | `tgen`, `taccept` (tile handshake), `tinj` (HEAD of WR_REQ into the mesh, in order per source). `del` is payload-last for MAC-off and `rx_mac_valid` for MAC-on. All match N-8. |
| Read-only monitors | PARTIAL | Present: per-VC FIFO full port-cycles (after this fix), credit-zero port-cycles, eject busy, NI tx_busy cycles, injection-link flits. Missing: NI fill level, inter-router link flits (only tile→mesh is counted), lock-held cycles. |
| Idle after drain, all credits returned | PRESENT inside the check, NOT REPORTED | `drained()` covers: `r_idle` (FIFOs empty, eject empty, no `output_locked`, every `credit_count==4`), `l_idle` (link pipes), `tx_busy`/`rx_busy`, TB state. It shows only as one pass/fail check, with no per-point field and no diagnostic saying which resource is not idle. |
| Control: corrupt one payload → mismatch identified | MISSING | No control hook in the TB. The detector exists (`[FAIL] SCOREBOARD_PAYLOAD source= seq=`), but no build injects a corruption. |
| Control: remove one flit → that packet missing | MISSING | No hook. The detector exists (`[FAIL] SCOREBOARD_MISSING source= seq=`). See OQ-5 on which flit to remove. |
| Control: stall consumption → liveness monitor fires | MISSING | There is no liveness monitor separate from the drain bound. A stall would only show as `[FAIL] PERF_BOUNDED_DRAIN`, which is a timeout-shaped result and is not acceptable as a kill (N-8, CLAUDE.md). A named observation is needed. |
| N-7.5 saturated VC2 | MISSING | The TB sends only `MSG_MEM_WR_REQ`/`RESP` (VC0/VC1, `message_to_vc`). No VC2 / attestation traffic. |
| N-7.5 reset/drain | PARTIAL | Reset is applied only after a full drain. There is no reset while traffic is in flight followed by idle/credit checks. |
| N-7.5 second challenge | MISSING | No attestation traffic, so no second-challenge test. |
| Result tags: transport revision, MAC, W, seed, tool | PARTIAL | CONFIG has `MAC_FLITS`, `SEED`, `CLOCK_NS`. Missing: W (64) and WDE (1), N_OUTSTANDING, transport revision, tool. `perf_report.py` hardcodes seed and clock and does not parse CONFIG. |
| perf_report CSV + curves | PRESENT, gaps | See section 4. |
| Verilator cross-check | BLOCKED (not installed) | `scope.json` writes `cross_simulator: NOT_RUN`. |
| Isolated hop probes | MISSING | Named in `perf_matrix.unimplemented`. Nothing in the TB. |
| Registry wiring | NOTE | The `NOC-2` stage lists only `perf_matrix` (kind gate, `unimplemented`). `perf_m0`/`perf_m1` (`checks: 84` = 28×3) are not stage jobs (OQ-1). |

## 3. Proposed per-point accounting contract (proposal only, nothing frozen)

Emit one line per point per build, after the drain, in addition to the existing PERF, MONITOR and
TRACE lines. Totals are mesh-wide; the per-tile PERF lines stay as they are.

```
POINT pattern=<0-3> period=<64|32|16|8|4|2|1> mac=<0|1> seed=0x12345678 w=<W> wde=<0|1> n_out=<N_OUTSTANDING> offered=<n> queued=<n> cap_drops=<n> accepted=<n> injected=<n> delivered=<n> responses=<n> missing=<n> duplicate=<n> mismatched=<n> unknown=<n> credits_returned=<0|1> idle_after_drain=<0|1> drain_cycles=<n> verdict=<OK|FAIL>
```

Field definitions:
- `injected`: WR_REQ HEAD flits accepted by the mesh at the tile ports.
- `delivered`: first-time `delivery()` calls.
- `missing`: generated-and-dequeued records (`q<qread[s]`) that were never seen.
- `duplicate`: delivery of a record already seen.
- `mismatched`: payload or address mismatch.
- `unknown`: delivery whose source or seq is out of range.
- `credits_returned`: every router `credit_count[p][v]==4` (split out of `r_idle`).
- `idle_after_drain`: `r_idle && l_idle && !tx_busy && !rx_busy && ds==0 && resp_rd==resp_wr` on all tiles.
- `drain_cycles`: cycles waited after `GEN_CYCLES`.

Judge regex, one line per point, with exactly 28 lines per build:

```
^POINT pattern=([0-3]) period=(64|32|16|8|4|2|1) mac=([01]) seed=0x12345678 w=(\d+) wde=([01]) n_out=(\d+) offered=(\d+) queued=(\d+) cap_drops=(\d+) accepted=(\d+) injected=(\d+) delivered=(\d+) responses=(\d+) missing=(\d+) duplicate=(\d+) mismatched=(\d+) unknown=(\d+) credits_returned=([01]) idle_after_drain=([01]) drain_cycles=(\d+) verdict=(OK|FAIL)$
```

Proposed expectations for a normal build (to be frozen by the owner, not by P1):
- The set of (pattern, period) pairs equals the full 4×7 product, with `mac` equal to the build's mode.
- `offered == queued + cap_drops`.
- `queued == accepted == injected == delivered == responses`.
- `missing = duplicate = mismatched = unknown = 0`.
- `credits_returned = idle_after_drain = 1`.
- `drain_cycles <= 50000`.
- `n_out = 2`, `w = 64`, `wde = 1`.

Proposed liveness line, emitted when the drain bound is reached, or by a monitor that tracks
progress (for example, no delivery and no flit movement for K cycles while work is pending):

```
LIVENESS_FIRED pattern=<p> period=<r> mac=<m> tile=<t> cycle=<c> reason=<no_progress|drain_bound> pending_src=<s> pending_seq=<q> fifo_nonempty_mask=<hex> credits_short_mask=<hex> locks=<hex> rx_busy=<0|1>
```

Proposed control lines. Each control is a separate build gated by an `ifdef`, so the 84-check normal
build is unchanged:

```
CONTROL kind=corrupt_payload target_source=<s> target_seq=<q> bit=<b>
CONTROL kind=drop_flit target_source=<s> target_seq=<q> flit=<idx>
CONTROL kind=stall_consumption target_tile=<t> from_cycle=<c>
```

Pass rule for each control: `RESULT : FAIL`, plus the targeted oracle line naming the same target:
- corrupt: `[FAIL] SCOREBOARD_PAYLOAD source=<s> seq=<q>`
- drop: `[FAIL] SCOREBOARD_MISSING source=<s> seq=<q>`
- stall: `LIVENESS_FIRED ... tile=<t> reason=no_progress`

`TB_TIMEOUT` or `$fatal` must not appear. A drain-bound timeout alone is never a pass.

## 4. perf_report.py gaps (not edited)

- Points are keyed from TRACE lines, so a point with traces but no PERF block still counts. The
  smoke log produced "4/56 points" with an incomplete uniform 1/8 point. Fix: require every point to
  have 6 PERF rows, and `len(traces in point) == Σ delivered`.
- Does not check `queued == accepted`, or zero missing, duplicate and mismatched counts (no fields
  exist yet).
- Seed (305419896), clock (20), window [128,2176) and `framing_only` are hardcoded instead of
  parsed from CONFIG. It does not record W, N_OUTSTANDING, transport revision or tool.
- Ignores MONITOR lines (FIFO-full and credit-stall occupancy are never reported).
- p95 uses `sorted[int(.95*(n-1))]`, a lower-nearest-rank variant. The method should be stated in
  `scope.json`.

## 5. Open questions

- **OQ-1:** Should the `NOC-2` stage list `perf_m0`/`perf_m1` as well as `perf_matrix`? Who
  implements the `perf_matrix` gate (it needs both 28-point runs, the controls and the hop probes)?
- **OQ-2:** Is the per-source seed `0x12345678+t` acceptable, or should one LCG stream be shared or
  split in a documented way?
- **OQ-3:** Should CONFIG gain `W=64 WDE=1 N_OUTSTANDING=2 TRANSPORT_REV=<id> TOOL=xsim-2024.1`?
  Extra keys do not break the existing judge regex, but they change the TB, so the identity changes.
- **OQ-4:** Adding per-point POINT and idle checks through `check()` changes CHECKS (currently
  84). Should they be counted fields parsed by the judge, or new checks with a refrozen count?
- **OQ-5:** Which flit should "remove one TB-local flit" remove?
  - Removing a payload flit between NI TX and the mesh truncates a wormhole. N-7.5 says the
    sender may then keep the lock for good, and the receiving NI may raise `rx_lerr`. That gives
    UNEXPECTED_CONTAINMENT/drain timeout, not just MISSING.
  - Cleaner alternatives: drop a complete packet at the TB generator → NI boundary after its record
    is created, or drop at mesh eject → NI RX in the TB, with the NI fed a well-formed stream.
- **OQ-6:** N-7.5 saturated VC2 and second challenge need attestation-message traffic (VC2). Do they
  belong in `tb_noc_perf`, or in a separate N-7.5 TB with its own jobs?
- **OQ-7:** The judge's controlled-FAIL path today exists only for `mutant` jobs, through `oracle`.
  Do controls reuse that (`mutant`-like `oracle` with no source mutation), or need a new judge
  kind? Either way it means a registry and `test_dual_lane.py` change, which is out of P1 scope.
- **OQ-8:** Throughput at uniform ≥1/8 is limited by N_OUTSTANDING (see section 1). Should the
  report label this explicitly as the NI-limited regime?

## 6. Changed files (sha256 after change)

| File | sha256 |
|---|---|
| `scripts/perf_bench_body.sv.inc` | a68ac2e319c6ad5b1cf3b05d10efdd823a9392db35cf39ceb6d72383054290c1 |
| `NOC_PQATTEST.srcs/sim_1/new/tb_noc_perf.sv` (regenerated) | e879a63d4c5ed53199797fbbff0a8f92dea50065b609a2db25d8204d1981c067 |
| `scripts/prepare_perf_bench.py` (unchanged) | cfca665f854107338ae7dac0d39535e5d1be1f6c3655d4e37c903c49ecb1fb1e |
| `scripts/perf_report.py` (unchanged) | d9232d09c214cc150180b26f177841c756d1b2f532eb3eb4e7ce47fe0b4ab516 |

Scratch build products are in `_p1_scratch/` (not committed).
