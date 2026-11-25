# HP (I-3 / NOC-2 subgate `perf_hop_probes`): expected counts, derived from source before any run

Date 2026-10-20. Derived by reading `NOC_PQATTEST.srcs/sim_1/new/tb_noc_hop_probes.sv`. **No simulation,
compile or elaboration was run for this document** (an I-3 batch was running on the host; the integrator
compiles later). Line numbers are in `tb_noc_hop_probes.sv`.

State: implemented = YES (bench, registry patch, static check). Compiled/elaborated = NO.
XSim-simulated = NO. Reference-checked = NO. Mutation-tested = NO. Formal = NO. Hardware = NO.

A mismatch at run time is a FAIL or INVALID. These expectations are not edited after a run.

## 1. What the bench does

- **Transport.** Production M-F1 rev 5 only: production `NOC_PKG.sv`, `noc_network_interface.sv` and
  `noc_mesh_3x2.sv` (`LINK_PIPE=1`, router `EJECT_PIPE=1` default). No L2, no `rtl/dual_lane/` file.
  Source list = `NOC` (12 production files) + the bench, same as `perf_m0`.
- **Scaffold.** Lines 13-213 are a verbatim copy of `tb_noc_perf.sv` lines 13-213: the mesh, six NIs with
  the per-instance local port binding (the XSim assertion-sampling workaround), and the `r_idle`/`l_idle`
  probes. The static check verifies the copy line for line. `tb_noc_perf.sv`, `perf_bench_body.sv.inc` and
  `prepare_perf_bench.py` are not edited.
- **Probe sequence** (`:535-542`). For each ordered pair (a,b), a≠b, in order a=0..5, b=0..5:
  1. fresh reset (`reset_mesh`, 5 cycles);
  2. probe VC0: `MSG_MEM_WR_REQ` a→b (allocates NI slot 0 at a);
  3. probe VC1: `MSG_MEM_WR_RESP` b→a. It answers that request. Tag 0 = lowest free slot after reset
     (NI `:212-228`). The response frees the slot.
  4. probe VC2: `MSG_ATTEST_CHALLENGE` a→b.

  Each probe sends exactly one packet. It starts only when the mesh is idle with every credit back.
  It ends after delivery + drain to idle + 16 quiet cycles.
- **Timestamps.** Same definitions as N-8 / `tb_noc_perf`:
  - `cyc` counts posedges since reset release.
  - `t_inj` = the NI HEAD→mesh handshake at the source (`m_in_valid && m_in_ready`, HEAD/HEAD_TAIL).
  - `t_del` = destination completion:
    - MAC off: the payload-last handshake;
    - MAC on: `rx_mac_valid`.
  - `MEM_WR_RESP` has no payload. With MAC off it completes on its HEAD_TAIL handshake (`rx_payload_last`
    is set on that flit, NI `:979-980`). `tb_noc_perf` never times responses; this is the same terminator rule.
  - Latency = `t_del − t_inj`.
- **Hop count** = |dx|+|dy| from index y·3+x (`tile_x`/`tile_y`, `:322-327`). `CFG_COORD_MAP` checks that
  `NOC_PKG::tile_to_coord` uses the same index.

### Coverage and exclusions

| Item | Covered | Reason |
|---|---|---|
| 30 ordered pairs a≠b × VC0/VC1/VC2 | yes, 90 probes per build | The production NI has no per-tile message policy: TX accepts any legal msg_type from any tile (`noc_network_interface.sv:339-344`, `:405-423`). So every tile may send ATTEST on VC2. |
| VC1 with an unsolicited response | not used | The NI rejects a response with no matching outstanding slot (`rx_head_resp_ok`, `:862-863`): a protocol error, not a delivery. So the VC1 probe is the genuine answer to the preceding VC0 request. The VC1 set is still all 30 ordered pairs: b→a for every (a,b). |
| 6 local loopback pairs (a=b), all VCs | **excluded** from the registered builds | `noc_router.sv:692-694` `a_no_loopback_local_sync` raises `$error("…LOCAL->LOCAL loopback")` on every cycle a LOCAL-input flit is switched to LOCAL. `NOC_CROSSBAR.sv` X3 says a tile cannot send to itself. The judge rejects any `^Error:` line (`dual_lane_verify.py:129`). The define `HOP_INCLUDE_LOOPBACK` builds them as a diagnostic (not registered, judge-INVALID by construction). |
| `MEM_RD_REQ/RESP`, `ATTEST_RESPONSE/GRANT/REVOKE` | not probed | One representative per VC, as specified. VC0/VC1 use the write pair. VC2 uses the challenge (5 payload flits). |

## 2. CHECKS per build

One `check()` task (`:353-355`): `checks++`, and on failure `errors++` and `[FAIL] <name>`. No other code
touches `checks` or `errors`. Call sites (static check: 11):

| Region | Sites | Executions |
|---|---|---|
| global, `initial` (`:527`, `:533`): `CFG_N_OUTSTANDING`, `CFG_COORD_MAP` | 2 | 1× |
| `probe()` (`:498-503`): `HOP_PRE_IDLE`, `HOP_DELIVERED_ONCE`, `HOP_PAYLOAD`, `HOP_NO_OTHER_PACKET`, `HOP_IDLE_AFTER`, `HOP_NO_CONTENTION` | 6 | unconditional, once per probe |
| class loop (`:560`): `HOP_CLASS_DETERMINISTIC` | 1 | once per present (VC, hops) class |
| VC loop (`:578-579`): `HOP_MONOTONIC`, `HOP_CONST_INCREMENT` | 2 | once per VC |

A class counts as present when it has at least one recorded probe. Probes are recorded whatever their
outcome, so the class count depends only on geometry and `LOOPBACK`.

Geometry (3×2, a≠b), ordered pairs by XY distance: 1 hop = 14 (8 horizontal + 6 vertical), 2 hops = 12
(4 straight + 8 turning), 3 hops = 4. Total 30.

| Build / job | Defines | Probes | Classes | CHECKS arithmetic | CHECKS | ERRORS | RESULT |
|---|---|---|---|---|---|---|---|
| hop_probes_m0 | — | 30×3 = 90 | 3 VCs × {1,2,3} = 9 | 2 + 6·90 + 9 + 2·3 | **557** | 0 | PASS |
| hop_probes_m1 | PQ_MAC_ON | 90 | 9 | 2 + 6·90 + 9 + 2·3 | **557** | 0 | PASS |
| (diagnostic, not registered) | HOP_INCLUDE_LOOPBACK [+PQ_MAC_ON] | 36×3 = 108 | 3 × {0,1,2,3} = 12 | 2 + 6·108 + 12 + 2·3 | **668** | router `$error` lines → judge INVALID | — |

The MAC mode changes packet lengths only (MAC_FLITS = 128/32 = 4). It never changes a count.

## 3. Measured vs checked

**Measured only (printed, never compared with a constant):**
- `t_inj`, `t_del` and latency of every probe;
- each class latency;
- the per-hop increment `inc = L(vc,2) − L(vc,1)` and `L(vc,1)` per VC and MAC mode;
- no latency value appears anywhere in the bench or the registry, except the positivity check `latency=[1-9]\d*`.

**Checked against generator records or source facts:**
- **`HOP_PRE_IDLE`**: before the probe, every router is idle and every credit counter is 4. Slots are
  exactly as expected: slot 0 only at the requester before the VC1 probe, otherwise none.
- **`HOP_DELIVERED_ONCE`**: exactly 1 completion and 1 RX head in the whole mesh, both at the destination.
- **`HOP_PAYLOAD`**: compared against the generator record (`word_of`, `mac_of`, `ctl_of`):
  - header src/dst coordinate, msg_type, length = `message_length()`, control (incl. tag 0);
  - word count = `message_payload_flits()` and every payload word;
  - MAC on: the full 128-bit tag.
- **`HOP_NO_OTHER_PACKET`**:
  - exactly 1 injected HEAD and `len` injected flits mesh-wide, all at the source;
  - exactly 1 ejected HEAD and `len` ejected flits, all at the destination;
  - no `rx_abort`/`rx_protocol_error`/`rx_length_error`/`tx_error`.
- **`HOP_IDLE_AFTER`**: mesh idle (FIFOs, eject path, locks, link stages, NI FSMs), all credits back, and
  slot state as expected: slot 0 held at the requester after VC0, none after VC1/VC2.
- **`HOP_NO_CONTENTION`**: zero cycles, during the whole probe window, of each of the following:
  - any input-FIFO full flag (`full_<port>_vc<v>`);
  - any M9 credit stall (`grant_valid & ~grant_valid_qualified`, the exact suppression M9 applies);
  - LOCAL injection backpressure (`m_in_valid && !m_in_ready`);
  - eject backpressure.

  A failing probe also prints one `HOP_CONTENTION` line.
- **`HOP_CLASS_DETERMINISTIC`**: every probe in the (VC, hops) class has `ok=1` and the same latency (min = max > 0).
- **`HOP_MONOTONIC`**: class latency strictly increases over the present hop counts.
- **`HOP_CONST_INCREMENT`**: `L(h) − L(h−1)` is the same positive value for h = 2..3.

A credit-zero register value is not a stall. The mesh design note (`noc_mesh_3x2.sv:43-45`) says the
credit round trip of 4 equals VC depth 4, so one VC sustains 1 flit/cycle. If that claim is wrong, the
probe check `HOP_NO_CONTENTION` fails. That would be a finding about the RTL, not a bench error.

## 4. Judge (frozen in the registry patch; existing `judge` + `judge_lines`, no new judge code)

- CONFIG (exactly one; every registry key checked):
  `^CONFIG\s*:\s*([^\r\n]+)$` containing `TOP=tb_noc_hop_probes CASE=hop_probes transport=MF1-rev5 l2=none
  w=64 wde=1 n_out=2 tool=xsim-2024.1 MAC_FLITS=<0|4> CLOCK_NS=20 PAIRS=30 PROBES=90 CLASSES=9 LOOPBACK=0`.
- `^\s*CHECKS\s*[:=]\s*(\d+)\s*$` = 557, `^\s*ERRORS\s*[:=]\s*(\d+)\s*$` = 0, `^\s*RESULT\s*[:=]\s*(PASS|FAIL)\s*$` = PASS.
- Rejected anywhere: `^\s*(ERROR:|Error:|FATAL:|Fatal:)`, `assertion…(failed|failure)`, `TB_TIMEOUT`,
  `global timeout`, `[FATAL]`, `STRESS TIMEOUT`, `^\[FAIL\]` (all existing rules).
- `required_lines` (each pattern's `re.findall(…, re.M)` count must equal the frozen count), for M = 0 or 1:
  - 90 lines, each count 1, generated from the pair list:
    `^HOP_PROBE id=\d+ src=S dst=D vc=V msg=K hops=H flits=F t_inj=\d+ t_del=\d+ latency=[1-9]\d* mac=M ok=1$`
    - (V,K,payload) = (0,2,2), (1,3,0), (2,4,5);
    - VC1 has S,D swapped;
    - H = |S%3−D%3| + |S//3−D//3|;
    - F = 1 + payload + 4M.
  - `^HOP_PROBE ` count 90. So there is no extra or failing probe line.
  - 9 lines, each count 1: `^HOP_CLASS vc=V mac=M hops=H probes=N latency=[1-9]\d* min=[1-9]\d* max=[1-9]\d* deterministic=1$`,
    N = 14 / 12 / 4 for H = 1 / 2 / 3.
  - `^HOP_CLASS ` count 9.
  - `^HOP_SUMMARY mac=M loopback=0 vc0_per_hop=[1-9]\d* vc0_hop1=[1-9]\d* vc0_zero_hop=NA vc1_per_hop=[1-9]\d* vc1_hop1=[1-9]\d* vc1_zero_hop=NA vc2_per_hop=[1-9]\d* vc2_hop1=[1-9]\d* vc2_zero_hop=NA monotonic=1 const_increment=1$`, count 1.
  - `^HOP_CONTENTION ` count 0.
- Expected PASS log shape: 1 CONFIG, 90 HOP_PROBE, 9 HOP_CLASS, 1 HOP_SUMMARY, CHECKS : 557, ERRORS : 0,
  RESULT : PASS, no `[FAIL]`.

Zero-hop latency: `vcN_zero_hop=NA` in both registered builds (loopback excluded, §1). Only the diagnostic
`HOP_INCLUDE_LOOPBACK` build measures it.

## 5. Registry patch (`reports/i3_hp/prepare_dual_lane.i3_hp.patch`, against `scripts/prepare_dual_lane.py` @ e824ced)

- Replaces the `perf_hop_probes` gate with `hop_probes_m0` / `hop_probes_m1`:
  - kind `simulation`, selection `I-3`, top `tb_noc_hop_probes`;
  - sources `NOC + [tb_noc_hop_probes.sv]`;
  - checks 557, `required_lines` as in §4;
  - `tb_time_limit=10ms` (watchdog `#8ms`), `sim_timeout=900`;
  - oracle files: this document and the static check.
- `N2_I3` (= NOC-2 stage and the NOC-2 part of `increments['I-3']`) lists both jobs instead of
  `perf_hop_probes`. The length guard goes 13 → 14, plus a frozen-count guard (557/90/9).
- `perf_matrix` is unchanged: its dependencies and `perf_inputs` are untouched; `perf_report.py` is not edited.
- No `post_format_compat` copy: the jobs are created in `noc2_jobs()` after the pfc block, like the other NOC-2 jobs.
- The integrator must regenerate `scripts/dual_lane_jobs.json` (`prepare_dual_lane.py main()`) after applying the patch.

## 6. Open items

1. Nothing here has been compiled. Constructs not yet proven in XSim in this repo:
   - `function automatic int sum6(input int a [NT])` (unpacked-array argument);
   - `N_OUTSTANDING'(1)` size cast;
   - `assign slot_vec[g] = GN[g].ni.txn_valid_q` (the perf bench uses only `|GN[g].ni.txn_valid_q`);
   - `continue` in `initial` loops.

   A compile error is a bench defect. Counts change only if control flow changes.
2. **perf_m0 / hotspot and transpose loopback.** N-8 hotspot sends tile 2 to itself, and transpose has
   the fixed points 0 and 5. The existing log
   `reports/dual_lane_10_20261020_000438_d4ad56ae/perf_m0/.../simulate.log` (read only, not produced here)
   holds 13,619 `Error: noc_router: synchronous LOCAL->LOCAL loopback` lines. `dual_lane_verify.py:129`
   rejects `^Error:`, so perf_m0/m1 will be INVALID as frozen. This needs Kalash's decision: drop loopback
   from the N-8 patterns, or classify that SVA. It is outside this track's allowed files.
3. `reports/i3_n2/test_n2_judge.py:102` asserts `JOBS['perf_hop_probes']` is unimplemented. It must be
   updated when this patch is applied (not an allowed file here).
4. `perf_report.py:156` still prints `isolated_hop_probes='NOT_IMPLEMENTED (separate subgate)'`. That is
   cosmetic, because the gate is now the two jobs in the NOC-2 stage.
5. The tags `transport=MF1-rev5` / `tool=xsim-2024.1` are TB defaults (`HOP_TRANSPORT_REV`, `HOP_TOOL`), as
   in the perf bench.
