# S2 / I-5 matrix plan (contract sec. 8 and sec. 9), drafted 2026-10-22, not yet registered

Status (2026-10-23): sec. 8 rows REGISTERED as increment I-5 - tb_s2_attacks (25 vectors from scripts/gen_s2_vectors.py, 30 checks;
pair level with the tile-3 gate), nine L2 negative controls (s2_mut_mac_off / bind_ctl / id_off / st_dest / st_vc / seq_off /
epoch_off / seq_wrap / len_off) and s2_mut_rl_off on the SF-1 bench; scratch runs (not evidence): control 30/0, every control
killed by its targeted row, no RTL diagnostic lines. Deviations from the table below: the 'type' case is not an L2 row (reserved
types are data-plane, refused by the NI, AM-5); TX sequence exhaustion is not reachable in simulation (2^64 sends) - the RX
no-wrap rule is tested instead. The sec. 9 re-earn group is still a plan. Each row gets one registry job (counts frozen from its TB header before
the first run), the expected reason asserted per packet, and one negative control. The control must make the attack
succeed **observably**, with the attack's own check failing for the right reason, not only through MAC.

P7 reason codes (rtl/dual_lane/noc_l2_auth_p7.sv, pq_noc_subsystem_p7.sv, ingress):
- 1 framing/header pre-check
- 2 MAC
- 3 epoch
- 4 sequence (zero or <= rx_seq)
- 5 non-peer source
- 6 rate limit
- 7 occupancy drop (unreachable under D2)
- 8 control HEAD at a non-attested tile
- 9 ingress source
- 10 incomplete (gap watchdog)
- 11 malformed / nested / overlong

## Row map

| Row | Mechanism / reason | Existing evidence (B-4) | S2 job (new) | Negative control |
|---|---|---|---|---|
| payload/tag corruption, wrong key | MAC / 2 | l2p7_equiv (bit flip; tile-5 key), unit level | s2_mac (subsystem: tile 4 -> 3 GRANT with one flipped payload bit, with a wrong K[4->3]) | `BYPASS_MAC=1`: the corrupted GRANT authorizes tile 3 |
| header-field mutation | transcript binding / 2 | none dedicated | s2_hdr_bind: each HEAD field (type, control, length, dest) changed after MAC | mutant: the field omitted from the transcript (rtl/dual_lane variant hook) -> accepted |
| wrong peer/source, valid MAC recomputed | identity / 5 | l2p7_equiv (src claim changed), p7_ingress Q9 at the raw port | s2_identity: genuine key, recomputed MAC, src != PEER at tile 3 | identity check disabled (slot G reason 5 off) -> accepted; asserted reason 5, not 2 |
| wrong dest / VC / type | structural / 1, 11 | parser / quarantine head_ok (p7_ingress) | s2_struct: one case per field | that one check disabled (per-field mutant) |
| duplicate / old sequence | replay / 4 | l2p7_equiv (replay of previous) | s2_replay: replay at the subsystem; old seq after a newer one | `BYPASS_SEQUENCE=1` -> the replayed REVOKE / GRANT acts twice |
| old epoch, reset replay | epoch / 3 | l2p7_equiv (other boot epoch) | s2_epoch: packet captured before reset, replayed after the reset with a new epoch | `BYPASS_EPOCH=1` -> accepted |
| sequence zero / wrap / exhaustion | sequence lifecycle / 4 | none | s2_seq_life: seq 0, wrap at 2^64-1, TX refusal at exhaustion | forbidden transition allowed (mutant) |
| short / overlong control packet | framing / 1, 11 | l2p7_equiv (truncation) | s2_len: length-1 and length+1 control packets at tile 3 | that length boundary disabled (mutant) |
| flood / occupancy | D2 hold, rate limit / 6 | sf1_flood, sf1_mut_peer_drop, sf1_mut_single_slot (P1), sf1_acct | reuse + s2_rl_off control | drop restored (existing mutant) / rate limit disabled (new mutant: reason 6 never) |
| data-source spoof | ingress source / 9 | p7_ingress Q9, ig_mut_q_src_off, ig_mut_parser_src_off | reuse | existing mutants |
| nested HEAD, incomplete raw packet | quarantine / 10, 11 | p7_ingress Q11/QE/QW, ig_mut_q_nested_off / no_cap / partial / gap_any | reuse | existing mutants |

## Cross-cutting checks

- **Rejected control packets:** zero trusted delivery and zero slot retirement. Implemented as an SVA in noc_l2_auth_p7 plus a
  counter compared in every s2_* job.
- **Plain-data aborts:** N-8.1 retirement allowed. The data-plane jobs keep the N-8.1 counters.
- **Identity mutants** must fail through reason 5. The bench asserts the reason per packet, so a MAC failure (reason 2) does
  not count.
- **Measured:** authentication latency per message type (GRANT/REVOKE 24 B, CHALLENGE 52 B, RESPONSE 88 B) and engine
  contention (P/Q maxima under the s2 load). l2e_engine already bounds P <= 269 and Q <= 792; S2 reports the subsystem values.

## Sec. 9 re-earn list (new P7 evidence)

- N-8.1 containment adapted to P7.
- Framing.
- F2-F4: done in B-4 (f234_p7, plus phase jobs).
- Authorization.
- N-7.5 finite liveness.
- NOC-2 subset: uniform and hotspot at 1/64, 1/8, 1, both MAC modes, plus the hop probes.
- All synthesis: p7_subsystem_ooc / l2e_ooc done in B-4, P&R in B-4.

Re-adjudicate only, with identical source closure, parameters, vectors and tool: the KMAC/SHA3 KATs, s8_golden and its
mutants, the arbiter jobs, the endpoint unit and the exclusivity jobs. Old results stay history and are never relabelled
as P7 qualification.

## Order

1. B-4 PASS gate report.
2. One S2 registration group: the s2_* benches and their mutants and controls, compile-checked first.
3. Run one at a time.
4. Sec. 9 re-earn group.
5. I-5 gate report.
