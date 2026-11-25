# N2 (I-3 / NOC-2): expected counts and observations, derived from source before any run

Date 2026-10-19. Derived by reading `NOC_PQATTEST.srcs/sim_1/new/tb_noc_perf.sv` (generated from
`scripts/perf_bench_body.sv.inc` by `scripts/prepare_perf_bench.py`). **No simulation, compile or
elaboration was run for this document** (a synthesis job was running on the host; the integrator
compiles later). Line numbers below are in the generated `tb_noc_perf.sv`.

State: implemented = YES (bench, generator, judge/registry patches, report). XSim-simulated = NO.
Compiled/elaborated = NO. Reference-checked = NO. Mutation-tested = NO (controls prepared, not run).
Formal = NO. Hardware = NO. Verilator cross-check = BLOCKED (not installed).

A mismatch at run time is a FAIL or INVALID. These expectations are not edited after a run.

## 1. What the bench does (the parts that set counts)

- One `check()` task (`:367-369`): `checks++`, and on failure `errors++` plus `[FAIL] <name>`.
  Scoreboard, containment, liveness and overflow detectors add to `errors` directly and never to
  `checks`. So CHECKS depends only on control flow, never on traffic or outcome.
- `run_point()` (`:662-716`) makes exactly 14 `check()` calls (`:696-709`), unconditionally, once per call.
- `reset_phase_a()` (`:718-735`) makes 4 (`:728-731`).
- `initial` (`:737-789`) makes 1 global call, `CFG_N_OUTSTANDING` (`:741`), then the build's case:
  SAT_VC2 +3 (`:763-765`), SECOND_CHALLENGE +5 (`:776-780`).
- `scripts/test_dual_lane.py`-independent static check: `reports/i3_n2/check_perf_bench_static.py`
  counts the `check(` call sites per region (point 14, reset 4, SAT 3, SC 5, global 1; 27 sites in all) and
  verifies begin/end, case/endcase, function/task and bracket balance. It passes. It is not a compile.

### Generation arithmetic (all builds)

`start_point()` sets `cyc=0`, releases reset and sets `generation_on=1` at a negedge (`:659`). The
posedge block uses `cyc` and then increments it at its end (`:632`). `run_point()` waits
`repeat(GEN_CYCLES)` negedges (`:668`), so the posedges in the window see cyc = 0..2175. An offer is made
when `generation_on && cyc<2176 && cyc%period==t%period` (`:540`). For every period p in
{64,32,16,8,4,2,1}, p divides 2176 = 2^7 x 17. So each source gets exactly **2176/p offers**.
Up to CAP=256 are queued as records. The rest are cap drops.

| period p | offers/source 2176/p | queued/source min(.,256) | drops/source | offered (x6) | queued (x6) | cap_drops (x6) |
|---|---|---|---|---|---|---|
| 64 | 34 | 34 | 0 | 204 | 204 | 0 |
| 32 | 68 | 68 | 0 | 408 | 408 | 0 |
| 16 | 136 | 136 | 0 | 816 | 816 | 0 |
| 8 | 272 | 256 | 16 | 1632 | 1536 | 96 |
| 4 | 544 | 256 | 288 | 3264 | 1536 | 1728 |
| 2 | 1088 | 256 | 832 | 6528 | 1536 | 4992 |
| 1 | 2176 | 256 | 1920 | 13056 | 1536 | 11520 |

These numbers do not depend on the pattern. The pattern only changes destinations.

## 2. Per-build count table

| Job (registry id) | Defines | Points | CHECKS derivation | CHECKS | Expected ERRORS | RESULT |
|---|---|---|---|---|---|---|
| perf_m0 | — | 28 = 4 patterns x 7 periods (`:784`) | 1 + 28 x 14 | **393** | 0 | PASS |
| perf_m1 | PQ_MAC_ON | 28 | 1 + 28 x 14 | **393** | 0 | PASS |
| perf_ctrl_corrupt | PERF_CTRL_CORRUPT | 1: uniform 1/16 (`:745`) | 1 + 14 | **15** | **2** | FAIL |
| perf_ctrl_drop | PERF_CTRL_DROP | 1: uniform 1/16 (`:749`) | 1 + 14 | **15** | **3** | FAIL |
| perf_ctrl_stall | PERF_CTRL_STALL | 1: hotspot 1/16 (`:753`) | 1 + 14 | **15** | **6** | FAIL |
| n75_sat_vc2_m0 / _m1 | N75_SAT_VC2 (+PQ_MAC_ON) | 1: pattern 4, period 1 (`:757`) | 1 + 14 + 3 | **18** | 0 | PASS |
| n75_reset_m0 / _m1 | N75_RESET (+PQ_MAC_ON) | phase A + 1 point: uniform 1/4 (`:769-770`) | 1 + 4 + 14 | **19** | 0 | PASS |
| n75_second_challenge_m0 / _m1 | N75_SECOND_CHALLENGE (+PQ_MAC_ON) | 1: uniform 1/16 (`:774`) | 1 + 14 + 5 | **20** | 0 | PASS |

The MAC mode never changes a count. `MAC_ENABLE` only selects the completion event
(payload-last vs `rx_mac_valid`, `:617-624`) and packet lengths.

`pfc_perf_m0/m1` (post_format_compat copies, not in I-3) carry 393 automatically. The normal perf build
sends only MEM_WR_REQ/RESP, so the challenge length 5 to 7 change cannot affect it.

## 3. Expected POINT values

All builds also print these POINT tags: `transport=MF1-rev5 w=64 wde=1 seed=0x12345678 n_out=2 tool=xsim-2024.1`.

**Normal builds (each of the 28 points, both MAC modes).**
- offered, queued and cap_drops follow §1.
- accepted = injected = delivered = responses = mem_accepted = queued. Every record is a MEM_WR_REQ.
- missing = unsent = duplicate = mismatched = unknown = 0.
- credits_returned = idle_after_drain = 1.
- drain_cycles ≤ 50000.
- verdict = OK.

**perf_ctrl_corrupt** (target (1,5), word 1, bit 3).
- Point values: offered = queued = 816, cap_drops = 0, accepted = injected = delivered = responses = mem_accepted = 816, mismatched = 1, all other error fields 0, credits_returned = idle_after_drain = 1, verdict = FAIL.
- Why delivered still counts the packet: the corrupted packet is attributed to its expected record, so it counts as delivered.
- Why responses still count it: the memory stand-in answers every received request (`:430-433`), independently of the scoreboard.
- Failing checks: only PERF_NO_MISMATCH.
- ERRORS = 1 SCOREBOARD_PAYLOAD line (`:414`) + 1 failed check = **2**.
- Bit 3 is in the low sequence field, so the delivered word carries seq 13. The old scoreboard keyed on delivered seq would report this against the wrong record. The new one reports it against record (1,5), the head of the (1→4, VC0) list.
  - No other record matches exactly: the address word carries seq 5.
- Destination, recomputed from the TB's LCG (seed 0x12345678+1, 6th step, `d=r%5`, `d>=1 → d+1`): dst = 4.
- Expected word: `data_of(1,5)` = 1<<28 | ((5·193+71)&0xfff)<<16 | 5 = **0x140c0005**. Received word: 0x140c0005 ^ 0x8 = **0x140c000d**.

**perf_ctrl_drop** (record (3,9) removed between the generator and the NI).
- Point values: offered = queued = 816, accepted = injected = delivered = responses = mem_accepted = 815, missing = 1, unsent = 0, credits_returned = idle_after_drain = 1, verdict = FAIL.
- Failing checks: PERF_ACCEPTED (816≠815) and PERF_NO_MISSING.
- ERRORS = 1 SCOREBOARD_MISSING line + 2 failed checks = **3**.
- The next record from 3 to that destination matches by forward search (`:409-410`). The dropped record stays unseen, and the scan of all generator records (`:678-686`) reports it as MISSING.
- dst (LCG, seed+3, 10th step) = 0. kind = 2 (MEM_WR_REQ).
- No slot leaks: the dropped record was never accepted. So drained() is reached, and there is no liveness or drain-bound observation.

**perf_ctrl_stall** (tile 2 memory stand-in stops issuing responses from cycle 512, hotspot 1/16).
- Every source sends only to tile 2.
- After cycle 512, every response at tile 2 is withheld (`resp_eligible`, `:451-453`). Each source fills both NI slots (N_OUTSTANDING=2) and then presents a slot-blocked request forever. Tile 2 itself is included: it sends to itself.
- No handshake happens anywhere while work is pending. LIVENESS_FIRED reason=no_progress therefore fires after 1024 idle cycles (`:627-631`).
  - The pre-stall in-flight set is at most 12 requests (6 sources x 2 slots), at most 36 flits (MAC off). It drains within about 100–200 cycles of cycle 512, so the monitor fires at about cycle ≤ 1750. That is before the generation window ends at 2176.
  - So the drain loop exits at once and drain_cycles = 0.
- Liveness line contents at that moment:
  - first_pending_tile = 0
  - ds_mask = queue_mask = slot_mask = 3f (all six sources blocked with queued work and held slots)
  - resp_backlog_mask = 04 (only tile 2 owes responses)
  - inflight = 0 (the NI at tile 2 kept consuming: rx_ready stays 1)
- Point values: offered = queued = 816, cap_drops = 0, missing = 0 (no record left the queue without delivery), unsent ≥ 1, credits_returned = 1 (mesh empty), idle_after_drain = 0 (slots held), drain_cycles = 0, verdict = FAIL.
- accepted, injected, delivered, responses and mem_accepted are timing-dependent and not frozen. accepted = injected = delivered holds.
- Failing checks: PERF_ACCEPTED, PERF_RESPONSES, PERF_IDLE_AFTER_DRAIN, PERF_BOUNDED_DRAIN, PERF_NO_LIVENESS.
- ERRORS = 1 (LIVENESS_FIRED, `:484`) + 5 = **6**.
- Assumption to watch: the liveness monitor fires before cycle 2176. If it fires later, drain_cycles > 0 and the job is INVALID, not silently accepted.

**n75_sat_vc2** (pattern 4, period 1).
- What each source generates:
  - RoT (tile 4) generates only ATTEST_CHALLENGE, to {0,1,2,3,5} in rotation by seq % 5.
  - Each other source alternates: even seq → ATTEST_RESPONSE (16 words) to RoT, odd seq → MEM_WR_REQ to a uniform destination.
- Record counts: 6 x 256 = 1536 records, of which:
  - 256 CH + 5 x 128 RESP = 896 attestation (VC2)
  - 5 x 128 = 640 memory
- Point values: offered = 13056, queued = 1536, cap_drops = 11520, accepted = injected = delivered = 1536, responses = mem_accepted = 640, other fields as normal, verdict = OK.
- Extra checks:
  - N75_VC2_SATURATED: at least one VC2 credit-zero port-cycle. Five sources converge 17/21-flit packets on one 1-flit/cycle eject.
  - N75_VC2_ATT_DELIVERED: 896/896.
  - N75_VC2_MEM_DELIVERED: 640/640.
- Drain estimate: RoT ingress is about 640 x 17 + 128 x 3 ≈ 11.3 k flits (MAC off) or 640 x 21 + 128 x 7 ≈ 14.3 k (MAC on), well under 50000.

**n75_reset** (uniform 1/4).
- Phase A: traffic for 1000 cycles, then reset asserted for 5 cycles with traffic in flight.
  - At 1/4 the closed loop is saturated (P1 smoke: about 0.059 accepted/cycle/tile), so the NI slots are busy and N75_RESET_HAD_TRAFFIC holds.
  - After 5 synchronous reset edges, every FIFO, eject path, lock, link pipe, NI FSM and slot is at its reset value, and the credits are back at 4. ROUTERS_IDLE, LINKS_IDLE and NI_IDLE hold.
  - Router/NI assertions are `disable iff (rst)`. `a_no_output_after_reset` (`noc_router.sv:716`) checks out_valid=0 one cycle into reset, which holds because the FIFOs are empty.
- Phase B: a full uniform 1/4 point. offered = 3264, queued = 1536, cap_drops = 1728, everything else at 1536, clean.
- The phase A numbers (accepted, delivered, inflight) depend on timing and are not frozen. Only their presence and the idle flags are.

**n75_second_challenge** (uniform 1/16 background).
- Event sequence:
  - RoT challenges tile 0 at cycle 300.
  - Tile 0 becomes busy for 512 cycles. On that first busy edge the spoof tile 5 sends an extra challenge to tile 0.
  - The extra challenge arrives during busy (about 4 hops ≪ 512) and is drained without a response.
  - Tile 0 then responds. RoT issues challenge 2 only after response 1 (one outstanding at any time), and tile 0 answers it.
- Event records: 2 RoT CH + 1 spoof CH + 2 tile-0 RESP = 5. They count as offered and queued (`event_record`, `:384-387`).
- Point values: offered = queued = 816 + 5 = 821, cap_drops = 0, accepted = injected = delivered = 821, responses = mem_accepted = 816, verdict = OK.
- Summary line: rot_issued = 2, rot_responses = 2, rot_max_outstanding = 1, ep_served = 2, ep_drained = 1, ep_drained_src = 5, responses_to_spoof = 0.
- Timeline: about 300 + 2 x (512 + network) ≈ 1.5–1.8 k cycles, inside generation plus drain.

## 4. Judge regexes (exact; frozen in the registry patch)

Common:
```
^CONFIG: TOP=tb_noc_perf CASE=(perf|ctrl_corrupt|ctrl_drop|ctrl_stall|n75_sat_vc2|n75_reset|n75_second_challenge) POINTS=(28|1) MAC_FLITS=(0|4) SEED=305419896 CLOCK_NS=20 W=64 WDE=1 N_OUTSTANDING=2 TRANSPORT=MF1-rev5 TOOL=xsim-2024.1 WARMUP=128 MEASURE=2048 DRAIN=50000 CAP=256 LIVE_WINDOW=1024$
^POINT case=(?P<case>\w+) pattern=(?P<pattern>\d+) period=(?P<period>\d+) mac=(?P<mac>[01]) offered=(?P<offered>\d+) queued=(?P<queued>\d+) cap_drops=(?P<cap_drops>\d+) accepted=(?P<accepted>\d+) injected=(?P<injected>\d+) delivered=(?P<delivered>\d+) responses=(?P<responses>\d+) mem_accepted=(?P<mem_accepted>\d+) missing=(?P<missing>\d+) unsent=(?P<unsent>\d+) duplicate=(?P<duplicate>\d+) mismatched=(?P<mismatched>\d+) unknown=(?P<unknown>\d+) credits_returned=(?P<credits_returned>[01]) idle_after_drain=(?P<idle_after_drain>[01]) drain_cycles=(?P<drain_cycles>\d+) verdict=(?P<verdict>OK|FAIL) transport=(?P<transport>\S+) w=(?P<w>\d+) wde=(?P<wde>[01]) seed=(?P<seed>0x[0-9a-fA-F]{8}) n_out=(?P<n_out>\d+) tool=(?P<tool>\S+)\s*$
^\s*CHECKS\s*[:=]\s*(\d+)\s*$     ^\s*ERRORS\s*[:=]\s*(\d+)\s*$     ^\s*RESULT\s*[:=]\s*(PASS|FAIL)\s*$
^TRACE pattern=(\d+) period=(\d+) mac=([01]) kind=(\d+) source=(\d+) seq=(\d+) dst=(\d+) gen=(-?\d+) accept=(-?\d+) inj=(-?\d+) del=(-?\d+) ok=([01])\s*$
```
Rules:
- Every `^POINT ` line must match. The set of (case, pattern, period) must equal the frozen set, each exactly once.
- Positive jobs: no `^\[FAIL\]` and no `^LIVENESS_FIRED`. Every existing diagnostic and timeout rule still applies.

Controls: each oracle line exactly once. Every `[FAIL]` line must be on the allowlist. No forbidden line. No timeout/fatal.
- corrupt:
  - `^CONTROL_APPLIED kind=corrupt_payload scope=tile_tx source=1 seq=5 word=1 bit=3 cycle=\d+$`
  - `^\[FAIL\] SCOREBOARD_PAYLOAD source=1 seq=5 dst=4 word=1 exp=140c0005 got=140c000d$`
  - `^\[FAIL\] PERF_NO_MISMATCH case=ctrl_corrupt pattern=0 period=16 mac=0$`
  - `^CONTROL_SUMMARY case=ctrl_corrupt applied=1$`
  - forbid `^LIVENESS_FIRED`, `SCOREBOARD_(MISSING|DUPLICATE|UNKNOWN|ADDRESS|TYPE|LENGTH)`, `UNEXPECTED_CONTAINMENT`.
- drop:
  - `^CONTROL_APPLIED kind=drop_packet scope=generator_to_ni source=3 seq=9 cycle=\d+$`
  - `^\[FAIL\] SCOREBOARD_MISSING source=3 seq=9 dst=0 kind=2$`
  - `^\[FAIL\] PERF_ACCEPTED case=ctrl_drop pattern=0 period=16 mac=0$`
  - `^\[FAIL\] PERF_NO_MISSING case=ctrl_drop pattern=0 period=16 mac=0$`
  - `^CONTROL_SUMMARY case=ctrl_drop applied=1$`
  - forbid `^LIVENESS_FIRED`, `SCOREBOARD_(MISSING_MORE|PAYLOAD|DUPLICATE|UNKNOWN|ADDRESS|TYPE|LENGTH)`, `UNEXPECTED_CONTAINMENT`.
- stall:
  - `^CONTROL_APPLIED kind=stall_consumption scope=memory_service tile=2 cycle=512$`
  - `^LIVENESS_FIRED case=ctrl_stall pattern=2 period=16 mac=0 cycle=\d+ reason=no_progress window=1024 first_pending_tile=0 ds_mask=3f queue_mask=3f resp_backlog_mask=04 slot_mask=3f inflight=0$`
  - `^\[FAIL\] PERF_(ACCEPTED|RESPONSES|IDLE_AFTER_DRAIN|BOUNDED_DRAIN|NO_LIVENESS) case=ctrl_stall pattern=2 period=16 mac=0$`, each once.
  - `^CONTROL_SUMMARY case=ctrl_stall applied=1$`
  - forbid `reason=drain_bound`, `SCOREBOARD_`, `UNEXPECTED_CONTAINMENT`.

N-7.5 summary lines (exactly one each; M = 0 or 1):
```
^N75_SAT_VC2 mac=M att_queued=896 att_delivered=896 mem_queued=640 mem_delivered=640 vc2_credit_zero_port_cycles=[1-9]\d*$
^N75_RESET phase=A pattern=0 period=4 mac=M reset_at=1000 reset_len=5 had_traffic=1 accepted=\d+ delivered=\d+ inflight=\d+ routers_idle=1 links_idle=1 ni_idle=1$
^N75_SECOND_CHALLENGE mac=M rot_issued=2 rot_responses=2 rot_max_outstanding=1 ep_served=2 ep_drained=1 ep_drained_src=5 responses_to_spoof=0$
```

## 5. Design choices and justification

- **Scoreboard (attribution fix).** Expectations come only from generator records (kind, destination, seq).
  - Each record is appended to its (source, destination, VC) list at creation.
  - XY routing, per-VC FIFOs and the in-order store-and-forward NI TX preserve order within a list. Each list is fed from a single TB queue: data records or event records, never mixed within one VC.
  - A delivered packet is compared against the head of its list:
    - exact match → delivered;
    - exact match with a later record → those in between stay unseen and are reported as MISSING;
    - match with an earlier record → DUPLICATE;
    - otherwise → TYPE/LENGTH/ADDRESS/PAYLOAD **against the expected head record**.
  - MISSING scans every generator record that left the TB queue, not only `q<accepted`.
  - The memory-response stand-in answers every received request, independently of the scoreboard, so a corrupted packet does not cause a secondary slot leak.
- **TB head-of-line fix.** A slot-blocked memory request is withdrawn when a response or an event record is waiting. The NI has no tile-side valid-stability assertion. Without this, the P1 TB could deadlock at TB level: A waits for a slot that needs B's response, while B's response sits behind B's own slot-blocked request.
- **Drop variant: generator → NI, whole packet.**
  - Removing one flit truncates a wormhole. Per N-7.5, the sender then keeps the lock and the receiving NI raises rx_lerr, giving UNEXPECTED_CONTAINMENT and a hang rather than a clean MISSING.
  - Dropping at mesh eject → NI RX would need to break the per-instance NI binding (`m_out_valid`/`m_out_ready` assigns), which must be kept. It would also leak the source's NI slot, adding a liveness symptom.
  - The generator-level drop creates the record (so it is expected), removes it before the NI, and yields exactly one MISSING.
- **Stall variant: memory service, not rx_ready.**
  - With WDE=1 and W=64, an `rx_ready=0` stall is bounded by the N-8.1 watchdog. It turns into containment aborts (UNEXPECTED_CONTAINMENT) and lost slots, which tests N-8.1 rather than the liveness monitor.
  - Stopping the tile-2 memory stand-in keeps the transport clean and makes the only targeted observation `LIVENESS_FIRED reason=no_progress`.
  - The monitor watches every tile/mesh boundary handshake globally. It fires after 1024 cycles with no handshake while TB work is pending, and the drain loop then stops at once. The result never relies on the drain bound or TB_TIMEOUT.
- **N-7.5 in the same bench, under defines.**
  - One generated file and one module name: no extra duplicate-name surface.
  - The N-7.5 cases reuse exactly the same scaffold, scoreboard, liveness monitor and POINT accounting that the matrix uses.
  - The define only sets the `BUILD` localparam, and every non-normal action is guarded by `BUILD==…`. So all code is compiled in every build, and the normal build executes none of it.
  - The cost: an N-7.5 edit changes the perf identity too, so perf_m0/m1 must rerun after any N-7.5 change.

## 6. Open items for the integrator / Kalash

1. Nothing here has been compiled. XSim may reject a construct I have not seen it accept. Candidates:
   - `string` concatenation in a `check()` argument
   - the `localparam string` from a define
   - `|GN[g].ni.txn_valid_q` (a hierarchical reference into a generate block)
   - the 4-D `int lst[6][6][3][272]`

   A compile error is a bench defect to fix before freezing evidence. The counts do not change unless control flow changes.
2. The stall control freezes `drain_cycles=0` and liveness before cycle 2176 (see §3). The margin is about 400 cycles.
3. The tags `transport=MF1-rev5` and `tool=xsim-2024.1` are TB defaults (`PERF_TRANSPORT_REV`, `PERF_TOOL`). The registry's define regex cannot pass strings. `pfc_perf_*` (rev-6 package) would still print MF1-rev5. Decide whether pfc perf is required in I-3.
4. Controls run in MAC0 only. N-7.5 runs in both MAC modes. Hop probes remain the unimplemented `perf_hop_probes` gate, which blocks NOC-2.
5. Per-source seed `0x12345678+t` is kept (P1 OQ-2).
6. `active_increment` stays I-2 in the patch. Opening I-3 requires switching `docs/decisions/dual_lane_config.json` and the literal together, and adding the PQ-2 ids to `increments['I-3']`.
