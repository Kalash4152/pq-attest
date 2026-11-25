# Sec. 9 re-earn: P7 adaptation spec (2026-10-23, drafted after Kalash's DUT / MAC-axis decision; defaults proposed)

All P7 benches are new files built by a generator. The generator applies an exact list of line edits to the protected or
generated original, as scripts/prepare_p7ni.py does, so every difference is reviewable and the protected files never
change. Counts are re-derived from the new source and frozen before the first run.

## The common conflict

The old suites use control types (ATTEST CHALLENGE / RESPONSE / GRANT / REVOKE) as traffic between arbitrary tiles. In P7,
control types exist only between tiles 3 and 4 (CONTROL_ALLOWED = 0 at tiles 0, 1, 2, 5). Each NI also has
N_OUTSTANDING = 2 request slots, which retire only on a matching response.

## Per suite (DUT (A): mesh + 6 noc_network_interface_p7, CONTROL_ALLOWED = (tile == 3 || tile == 4))

| Suite | Old vehicle | Conflict | Proposed P7 adaptation (default) |
|---|---|---|---|
| N-8.1 system (tb_noc_n81: B0, A-S0, A-S1, A-S2, N0) | P_A = CPU0 -> SPOOF ATTEST_RESPONSE (26 flits) holding R0.E, R1.E, R2.S, R5.L; C1/C2 MEM_WR_REQ, C3 MEM_RD_REQ | RESPONSE refused at tiles 0 and 5. A MEM_WR_REQ P_A would need a third CPU0 slot (C1a / C1b already hold both) | P_A = CPU0 -> SPOOF MEM_WR_REQ (3 flits, same route). C1a / C1b become MEM_WR_RESP (single flit, no slot, same R0.E contention; their payload scoreboard becomes "delivered, 0 words"). A-S1 accepts HEAD + 1 payload (was + 3). contain_info expects MEM_WR_REQ. delta from p7_length. Everything else unchanged |
| N-8.1 NI unit (tb_ni_n81) | one CPU0 NI; control-type framing and containment cases | tile 0 refuses control in P7 | Two builds: tile 0 (CONTROL_ALLOWED = 0), where control cases become "refused, tx_error / dropped to terminator" checks, and tile 3 (CONTROL_ALLOWED = 1), where the original control cases run with the P7 per-type framing (data types without MAC words) |
| Framing | inside the two N-8.1 suites | P7 per-type length | covered by the two rows above; no separate bench |
| N-7.5 liveness (tb_noc_perf N75_SAT_VC2 / RESET / SECOND_CHALLENGE) | ROT issues CHALLENGEs to every tile; endpoints answer RESPONSE | only 4 -> 3 CHALLENGE and 3 -> 4 RESPONSE exist in P7 | Attestation traffic only between 4 and 3. VC2 saturation by 3 <-> 4 control traffic. Reset and second-challenge cases on tile 3. Other tiles carry data traffic only |
| Hop probes (tb_noc_hop_probes) | per-pair, per-VC latency probes, VC2 via control types | VC2 control only between 3 and 4 | VC0 / VC1 probes on all pairs unchanged. VC2 probes on 3 -> 4 and 4 -> 3 only. Other pairs get one "control refused at the source NI" check each instead of a VC2 probe |
| NOC-2 subset (DUT (B), full pq_noc_subsystem_p7) | tb_noc_perf patterns: uniform / hotspot at loads 1/64, 1/8, 1, MAC off / on | data plain in P7 | Data traffic from tiles 0, 1, 2, 5 through their apps; attestation 4 <-> 3 at the old rate. Run (i) MAC off / on: identical data results by construction, stated in the report. Plus one (ii) point: hotspot at 1/8 with a 10 % control mix 3 <-> 4 |
| Authorization | l3_enforce, security_sec_1_4 (rev 6) | rev-6 gates | Map each old check to a P7 check (f234_p7, p7_refuse_grant, s2_attacks, p7_ingress). Port only the uncovered ones; the mapping table goes in the I-5 report |

## Open choice

N-8.1 system: accept turning C1a / C1b into MEM_WR_RESP, which weakens their payload scoreboard. The alternative keeps them
MEM_WR_REQ and adds a CPU1 responder that answers each request with MEM_WR_RESP, so CPU0's slots retire. That alternative is
closer to the original, but it adds traffic on the reverse route (R1.W, R0 local), which the old disjointness checks do not
see.

## Addendum, 2026-10-23 14:30: the N-8.1 system default does not hold on P7 (scratch evidence, not registered)

Generator: scripts/prepare_p7_benches.py -> tb_noc_n81_p7.sv (the approved default edits). Local scratch run, W = 16, RUNS = 7,
96 checks, 12 FAIL:
- "tile 1 no sticky" fails in every run. The unsolicited MEM_WR_RESP (C1a / C1b) sets a sticky at CPU1, so the C1a / C1b
  default is invalid.
- No multi-hop contention exists. In A-S0 (SPOOF blocked from reset), C1a / C2a complete at exactly the B0 cycles (13 / 20)
  and R0.E releases at cycle 8 in both runs, so the vacuity checks ("at expiry R0.E, R1.E held") fail. Under the A-S2 drip
  the 3-flit P_A completes within W, and containment never triggers.
- Structural reason: the longest packet a non-attested P7 tile may send or receive is MEM_WR_REQ, 3 flits
  (control types are refused, R7.4). A router VC FIFO holds FIFO_DEPTH = 4 flits (rtl/dual_lane/NOC_PKG.sv). A stalled
  endpoint therefore holds only its eject buffer, never an upstream route. The original N-8.1 threat needed a 26-flit
  RESPONSE.
- Tiles 3 / 4 (control allowed, up to 26 flits) have always-ready consumers by contract sec. 4 (SVA), so an endpoint stall
  is excluded there by construction.

Options:
- (a) Re-scope the P7 N-8.1 system bench to what exists. Eject-port containment at SPOOF with a data P_A (sticky / abort /
  info, persistence, recovery, trusted clear); the N0 negative control (watchdog off -> R5.L held, nothing accepted); and a
  checked structural bound in place of the multi-hop vacuity: every P7 packet a non-attested tile can source fits one VC FIFO
  (p7_length <= FIFO_DEPTH for types 0-3), with control types refused. C1 / C2 stay as non-interference checks
  (T_A == T_B0 exactly) using requests answered by responder tiles, so no unsolicited response appears. Recommended.
- (b) Declare N-8.1 system containment not applicable on P7, with the structural bound as the argument, and re-earn only the
  NI-unit containment (tb_ni_n81 ports).
- (c) Retarget to tiles 3 / 4 with long control packets. This only works by violating the sec. 4 always-ready invariant, so
  it is not meaningful; not recommended.

The NI-unit port faces the same vehicle question. In the tile-0 build the framing / containment cases would run on data
packets (at most 3 flits); the tile-3 build keeps the control cases with P7 framing.

## Resume qualification corrections (2026-10-23)

The standalone `tb_noc_n81_p7` replaces the earlier generated edit-list bench. Its default count is 20; the N0 and
counterfactual LONG builds each have 2 checks. Scratch results remain diagnostic until registered and adjudicated.

- N0 with `N81_WDE=0` must observe `m_out_valid[5] && !m_out_ready[5]`, zero accepted payload and zero containment.
  A three-flit packet fits in the 12-entry eject FIFO, so the router allocator's LOCAL packet lock can already be free
  while that receive interface is stalled. Requiring that allocator lock to remain set tests the wrong boundary.
  The control-confirmed marker is emitted only after its checks succeed.
- Requesting eight words from a normal MEM_WR_REQ NI does not create a long packet: its payload count remains two.
  LONG therefore requires an isolated counterfactual source list: MEM_WR_REQ payload 16, wire length 17, exceeding
  the 12-entry eject FIFO. Its copied package has the deliberate false per-packet bound and omits the fatal
  elaboration-guard typedef/instance. Production packages, framing, and the production elaboration guard stay unchanged.
  LONG must observe upstream blocking, containment and subsequent release; a watchdog-off companion must expose the
  absence of that recovery on a normal simulation end. These fixtures are not valid production P7 traffic.

## Port status and two open questions (2026-10-28)

Scratch results below are local xvlog/xelab/xsim runs. They are diagnostic, not evidence; nothing in this section is
registered yet. Sec. 9 registers as one group (Kalash 2026-10-28), so registration waits on questions 1 and 2.

| Suite | Bench | Builds | Scratch result |
|---|---|---|---|
| N-8.1 system | tb_noc_n81_p7.sv (standalone, S2-N81-P7) | default / N0 / LONG | 23 / 2 / 2 checks, 0 errors (commit 2364bc2) |
| N-8.1 NI unit | tb_ni_n81_p7.sv (standalone port of tb_ni_n81) | tile 0 W16 / W1, tile 3 W16 / W1 | 126 / 126 / 123 / 122 checks, 0 errors; counts equal the header derivation |
| N-7.5 liveness | tb_noc_perf_p7.sv (generated, scripts/prepare_p7_benches.py, 15 edits) | SAT_VC2 / RESET / SECOND_CHALLENGE | 18 / 19 / 20 checks, 0 errors; VC2 credit-zero 45 port-cycles; reset with 7 packets in flight; extra challenge drained (src 4), 0 answered |
| hop probes | tb_noc_hop_probes_p7.sv (generated, 15 edits) | one (PQ_MAC_ON) | 414 checks, 0 errors; per-hop +2 on VC0 / VC1, VC2 3 <-> 4 latency 16 |
| tile-4 peer load | already in s2_attacks (I-5 sec. 8, PASS): S2_T4_ACCEPTED, S2_T4_REJECTED, S2_ACCT_T4 | - | no new job |

NI unit, differences from tb_ni_n81 (all forced by P7 framing or R7.4; listed in the bench header): tile-0 vehicles are
MEM_WR_REQ (3 flits) / MEM_RD_REQ (2) and matched MEM_RD_RESP / MEM_WR_RESP; the fault position is k = 1 on a 3-flit packet;
T05 runs in both builds on MEM_WR_RESP with a matched slot; T14 adds a HEAD_TAIL-pending case; T17 needs MAC words (tile 3
only); T21 (tile 0 only) refuses all four control types on RX and TX.

N-7.5 edits: attestation only 4 -> 3 CHALLENGE / 3 -> 4 RESPONSE in the VC2-saturation pattern; the reset case runs that
pattern (control in flight at the reset); the second-challenge endpoint is tile 3, and the extra challenge comes from the RoT
(the only control source in P7); a RoT response beyond the issued challenges counts as an answer to the extra one.

Hop-probe edits: VC0 / VC1 probes on all 30 ordered pairs; VC2 probes on 3 -> 4 and 4 -> 3 only; each of the other 28 pairs
gets one HOP_VC2_REFUSED check (refused at the source NI when the source is non-attested, else at the destination NI). VC2 has
one hop class, so its constant-increment check is not applicable. Count 2 + 6 x 62 + 28 + 7 + 3 + 2 = 414.

### Question 1: the NOC-2 subset cannot carry data from the plain tiles on DUT (B)

On pq_noc_subsystem_p7 the plain tiles 0, 1, 2 and 5 can send no data through their applications:
- noc_attest_gate is built with ATTESTABLE = 0 at those tiles, so `authorized` stays 0;
- the gate passes a request only if `BYPASS_GATE || authorized || app_msg >= MSG_ATTEST_CHALLENGE`
  (noc_attest_gate.sv:21-23), so a data request gets app_ready = 0;
- the NI refuses the control types (CONTROL_ALLOWED = 0);
- tile 4's TX belongs to the verifier (sel_v = g == 4), so tile 4 has no application traffic.

The memory stand-in also serves only authorized sources or the RoT (pq_noc_subsystem_p7.sv, mcollect). The only data sources
on DUT (B) are tile 3's application (after a GRANT) toward the memory, its replies from tile 2, and the raw injector at tile 5
(quarantined, own-source only). So the specified "uniform + hotspot from all tiles at 1/64, 1/8, 1" does not exist on DUT (B).

Options (no bench written yet):
- (a) Data-plane matrix on DUT (A): tb_noc_perf_p7 normal build, uniform and hotspot at periods 64, 8, 1, all six tiles. Add
  the concurrent 4 <-> 3 control loop as TB traffic on VC2 (CHALLENGE / RESPONSE, as in N75_SAT_VC2). The control round-trip
  with and without data load is then measured on DUT (A) too. DUT (B) runs one point: its real control loop (verifier ->
  L2 -> endpoint -> L2 -> verifier, start_attestation repeated) with and without tile-3 data load to the memory plus raw-port
  load at tile 5.
- (b) DUT (B) only, with the load it can carry: tile 3 -> memory data at the three rates, plus raw-port load at tile 5.
  The control round-trip is measured with and without that load. No uniform / hotspot pattern.
- (c) DUT (B) with BYPASS_GATE = 1 as a bench-only build. Not recommended: the memory still refuses unauthorized sources,
  so the plain requesters' slots never retire, and the bypass changes the device under test.

Recommended: (a). It keeps the data-plane patterns on the same router and NI RTL, and measures the real control loop on
DUT (B).

### Question 2: authorization mapping, uncovered rows

Old contract (CODEX_INSTRUCTIONS_R4_FINAL sec. PQ-4; l3_enforce and security_sec_1_4 were placeholders, never implemented)
mapped to the registered P7 checks:

| Old row | P7 check (registered, PASS) | Status |
|---|---|---|
| SEC-1 genuine tile: grant, authorized data works | f234_p7: setup grants, F3_ATTESTATION_GRANTED, F3_APP_WRITE_COMMITTED, F4_CALIB_COMMIT | covered |
| SEC-1 control: corrupt response rejected | s2_attacks M row (L2 MAC, wrong key) + s2_mut_mac_off | covered at L2 |
| SEC-1 control at the verifier: wrong attestation tag in an L2-valid RESPONSE | none at P7 (verifier_revoke runs BYPASS_TAG = 1) | UNCOVERED |
| SEC-2 wrong key | s2_attacks M row | covered |
| SEC-2 wrong identity | s2_attacks I row + s2_mut_id_off | covered |
| SEC-2 wrong measurement, no grant / no commit | none at P7 | UNCOVERED |
| SEC-2 forged response from SPOOF | p7_ingress Q9 + ig_mut_q_src_off / ig_mut_parser_src_off; S2_T4_REJECTED (forged src 5) | covered |
| SEC-3 L2 replay | s2_attacks R row + s2_mut_seq_off | covered |
| SEC-3 attestation replay (old RESPONSE, fresh L2 wrapper) | none at P7 | UNCOVERED |
| SEC-3 stale epoch, reset replay | s2_attacks E row + s2_mut_epoch_off | covered |
| SEC-3 nonce substitution | none at P7 | UNCOVERED |
| SEC-4 runtime substitution (config / imem) at re-attestation | none at P7 | UNCOVERED |
| wrong grant issuer | s2_attacks I row (src != PEER at tile 3); p7_refuse_grant (GRANT at plain tiles) | covered |
| error response | none found | UNCOVERED |
| timeout | verifier_revoke D (unit) | unit only |
| status-clear misuse | P7 ties trusted_clear and ni_status_clr to 0; no clear path exists | not applicable |
| truncated challenge | s2_attacks L row + s2_mut_len_off | covered |
| concurrent SPOOF traffic | p7_c4 SAT_DATA (raw-port flood), sf1_flood | covered |
| l3_enforce: revoke de-authorizes | f234_p7 F2_DEAUTH_* + f234_p7_mut_f2 | covered |
| l3_enforce: authorization at the side effect | f234_p7 F4_* + f234_p7_mut_f4 | covered |
| l3_enforce: plain-tile data refused at the gate | none registered (structural, noc_attest_gate.sv:21) | UNCOVERED |

The six UNCOVERED rows at the verifier (tag, measurement, attestation replay, nonce substitution, substitution, error
response) need the full crypto chain on DUT (B) (real endpoint tag, KDF and measurement). That is a security-scope decision,
so it is put to Kalash with question 1. The plain-tile gate row is small: one check per plain tile (data request,
app_ready = 0, nothing enters the mesh).

### Kalash decisions, 2026-10-28 (DECISION_REGISTER S2-N2P7)

- Q1: option (a). Transport matrix: tb_noc_perf_p7 build N2P7_MATRIX (generator edits N2P7): seven points (control only;
  uniform and hotspot at periods 64, 8, 1), a continuous 4 -> 3 CHALLENGE, 3 -> 4 RESPONSE, 4 -> 3 GRANT loop in every
  point, the 14 NOC-2 point checks plus N2P7_CTRL_LOOP; CHECKS = 106. Subsystem round trip: tb_n2p7_rtt (start pulse ->
  CHALLENGE -> RESPONSE -> GRANT -> GRANT delivered at tile 3, four segments printed), K = 4 per load, loads NONE and
  LOADED (tile-3 writes to the memory + raw-port flood at tile 5); CHECKS = 11. The data-plane numbers are transport
  capacity for authorized tiles; in the P7 subsystem only attested tiles may send data.
- Q2: the six attestation-level rows stay OPEN and move to I-7 / PQ-4 (SEC-1..4). The plain-tile gate row is ported:
  tb_p7_gate_data, GATE_DATA_REFUSED_<g> for g = 0, 1, 2, 5 (the tile first receives an injected GRANT, then offers a
  MEM_WR_REQ); CHECKS = 4.

### Scratch qualification of the new benches (2026-10-29, diagnostic, not registered)

| Bench / build | Checks | Result |
|---|---|---|
| tb_noc_perf_p7 N2P7_MATRIX | 106 | PASS. First run FAIL (bench defect: the non-ring event queue, EXTRA = 16, overflowed at the 17th RoT record, i.e. loop 8); fixed by EXTRA = 64 and LOOP_MAX = 24 loops per point; failing log kept in scratch |
| tb_n2p7_rtt | 11 | PASS after a compile fix (expected_response, written by full_chain.svh, was undeclared). Round trip 1,204 cycles unloaded, 1,205-1,206 loaded (271 commits, 1,889 quarantine forwards in the window) |
| tb_p7_gate_data | 4 | PASS |
| + p7s_control_allowed (CONTROL_ALLOWED = 1 and ATTESTABLE = 1) | 4 | killed: all four GATE_DATA_REFUSED checks fail (GRANT authorizes, data commits) |
| + p7s_gate_bypass (plain-tile gates pass data) | 4 | killed: all four fail (data enters the mesh, no authorization) |
| + ATTESTABLE = 1 alone (not registered) | 4 | survives, 4 / 0 PASS: the P7 NI (CONTROL_ALLOWED = 0) still drops the GRANT (reason 8), so the gate is never authorized. Two independent layers; the ATTESTABLE-only mutant is equivalent at this boundary, so the registered negative controls are the two above |

N2P7 transport: control round trip 81 cycles control-only; 82-86 mean (max 95) under uniform or hotspot data at 1/64, 1/8, 1.
Every point fully accounted (missing / duplicate / unsent 0, credits home, idle after drain).

### 2026-10-29: shared-router non-interference case and registered-run restart

Kalash's scope change (I-5 only, then STOP; Phase B cancelled) asked for one shared-router case in N-8.1 NONINT. Added to
tb_noc_n81_p7: ROT -> MEM (R4.E -> R5.N -> R2.L, routers R5 and R2 shared with the SPOOF backlog, no shared output), with
T_A <= T_B0 + SH_BOUND, SH_BOUND = 2 shared routers x one 3-flit packet = 6 cycles. Default count 23 -> 24, re-frozen before
its next registered run. Scratch: 24 / 0, lat 7 baseline and 7 under backlog. The registered run 133103_f98617a1 was stopped
(own process) after 19 jobs, all PASS_FRESH; it is kept. All I-5 jobs rerun on the regenerated identity.
