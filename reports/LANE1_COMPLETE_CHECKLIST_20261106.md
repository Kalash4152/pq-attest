# NoC lane + PQ-Attest lane: everything planned and done, project start to 2026-11-06

✅ planned and done (with evidence) · 🟡 done in part / closed differently (reason given) · ⬜ not done yet · ➖ out of scope by decision

Sources: docs/STATUS.md (rev 20 / 21 history), docs/CODEX_INSTRUCTIONS_R4_FINAL_2026-10-08.md, the gate reports
reports/I1..I10, S1, S3, S4, docs/DECISION_REGISTER.md, reports/LANE_AUDIT_20261106.md.
**Bottom line:** the NoC lane is complete (NOC 5/5); the PQ-Attest lane is complete (PQ 5/5); both are integrated into one
P7 subsystem, which has released bitstreams and is ready for the CPU merge.
HARDWARE_VALIDATED=NO · SOC_INTEGRATION_COMPLETE=NO · FORMAL_PROOF=NO.

---

## Phase 0: foundation and recovery (September 2026)

### Recovery (M-0)
- ✅ Working-tree snapshot, git lock removed, Task-7 WIP committed as baseline
- ✅ `kmac_encode.sv` and `stage3_golden_tb.sv` restored; benches moved to sim_1; EOL renormalized
- ✅ S-7 mutation results recorded; N-7 log committed

### NoC lane, stages N-1 to N-8.1
| Stage | Planned | Status |
|---|---|---|
| N-1 Architecture | 3x2 mesh, 5 ports, 3 VCs, 32-bit flit, XY wormhole, tile map, header / flit format, N_OUTSTANDING = 2 | ✅ |
| N-1 7c flow control | credits router <-> router, ready / valid router <-> NI | ✅ frozen (docs/decisions/7c-flow-control.md) |
| N-2 Datapath (FIFO, crossbar, datapath) | RTL + TB1 | ✅ TB1 OVERALL PASS, NEG 2/2 · 🟡 separate datapath mutation run not done; router mutations covered by N-6 (3/3) and the later harness controls |
| N-2.5 Synthesis probe | 50 MHz on Artix-7 | ✅ WNS +0.202 after D7 (LINK_PIPE) and D7b (EJECT_PIPE) fixes |
| N-3 Routing / allocation | XY, arbiter, allocator | ✅ 491,520-vector arbiter check, 0 mismatch |
| N-3.5 Router M8 | router + credit bench | ✅ 30/0, later 47/0 |
| N-4 Credit M9 | credit counter in the router | ✅ M8 bench 47/0 |
| N-5 NI M10 / decoder M11 | standalone NI + decoder | ✅ (superseded by the N-8.1 NI) |
| N-6 Two tiles with NIs | stress bench, no bypasses | ✅ 126/0, mutation 3/3 killed |
| N-7 3x2 mesh | full mesh bench | ✅ 1,756/0 (pipe1), 1,762/0 (pipe0) |
| N-7.5 Deadlock freedom | XY + VC-class argument + dynamic evidence | ✅ (and the finite-liveness runs in NOC-2) |
| M-F1 rev 1 to 3 | transport interface freeze | ✅ rev 3 signed |
| N-8.1 NI endpoint containment (FD-1 B') | terminator-only RX FSM, watchdog, discard, TX store-and-forward, slot free | ✅ M-F1 rev 4; NI 115/0, tb_noc_ni 161/0, 7/7 NI mutants killed; SPOOF system bench |

### PQ-Attest lane, stages S-1 to S-8
| Stage | Planned | Status |
|---|---|---|
| S-1 Keccak-f[1600] | permutation core | ✅ 600 golden lanes + negative control; later bit-exact in every KAT |
| S-2 SHA3-256 | hash core | ✅ 49/0, byte order fixed; later hashlib KATs at 9 lengths (PQ-1 V4) |
| S-3 KMAC128 | MAC core | ✅ 11/0 + L = 128 KAT; later NIST SP 800-185 samples 1-3 (PQ-1 V4) |
| S-4 TRNG conditioning | nonce source | 🟡 RTL exists (19/0 historical); **not integrated**: the design uses a deterministic demo nonce (no TRNG claim, decision S-4 "replay only") |
| S-5 Tile-key KDF | KDF over root secret | ✅ 35/0; later teammate-reference bit-exact |
| S-6 Measurement | SHA3 over tile id, config, IMEM | ✅ 33/0; later single-block rewrite (D-SYN-2, A6) with equivalence 33,809/0 |
| S-7 Attestation tag | KMAC tag | ✅ 105/0 + 4/4 mutants killed |
| S-8 Attestation protocol | controller + endpoint | ✅ became PQ-1 / PQ-2 below (pq_attestation_controller + tb_stg_8) |
| S-9, S-10, S-11 | security regression, full chain, freeze | ✅ became PQ-4, PQ-5 and the release below |

---

## Phase 1: the R4 dual-lane plan (8 Oct to 3 Nov 2026), ten packages

### NOC-1 (I-1, 24/24, 2026-10-09)
- ✅ K-4 file moves with hash records
- ✅ Duplicate-name preflight + self-test (injected duplicate -> FAIL)
- ✅ n81_nitb 161/0; WP-0 N-6 mutation (3 kills + controls)
- ✅ D7 five-job session (pipe1 1,756/0, pipe0 1,762/0, M8 47/0, N-6 126/0, TB1 PASS)
- ✅ NI OOC and mesh gate reused on matching identity
- ✅ tb6_1 L46 cast diagnosed: no effect on exercised addresses, recorded as debt
- ✅ STATUS / STAGE_MAP / DECISION_REGISTER written

### PQ-1 (I-2, 36/36, 2026-10-19): teammate reference as the PQ authority
- ✅ V1 ZIP pinned (SHA-256 047bb5a9...c6a0) · ✅ V2 extracted read-only · ✅ V3 teammate suite 8/8 reproduced
- ✅ V4 external KATs (NIST KMAC samples 1-3; SHA3 at 9 lengths) · ✅ V5 repo-copy reconciliation
- ✅ V6 Python <-> RTL contract matrix · ✅ V7 thin adapters (s8 / full-chain / L2 golden)
- ✅ V8 profile split (16-byte examples vs 32-byte system) · ✅ V9 RTL bit-exact 95/0 (PYTHON_RTL_COMPATIBILITY = MATCH)
- ✅ V10 system policy layer (teammate ACCEPT vs policy REJECT, both recorded)
- ✅ 7/7 controller mutants killed · ✅ M-F1 rev 6 signed · ✅ post_format_compat re-runs

### NOC-2 (I-3, 2026-10-20): performance + liveness
- ✅ 56-point performance plan (4 patterns x 7 rates x 2 MAC modes), scoreboard from generator records
- ✅ Controls: corrupted payload, removed flit, stalled consumer, each with its targeted observation
- ✅ N-7.5 runs: saturated VC2, reset / drain, second challenge
- ✅ CSV + curves report
- ➖ Verilator cross-check: BLOCKED (not installed on Windows), reported as BLOCKED, never as passed

### PQ-2 (I-3): attestation endpoint
- ✅ Endpoint qualified (reply-to latched, crypto only after a valid 7-word challenge, rx_ready = 1 with SVA, busy drain,
  stable TX under backpressure, reset cancels)
- ✅ Unit + system benches; 4/4 mutants killed (tag swap, nonce offset, wrong reply-to, rx stall)
- ✅ Zero-byte request / response files deleted, orphan package recorded as excluded (closed 2026-11-06, PQ2-FILES)

### PQ-3 (I-4, 33/33, 2026-10-20): crypto OOC
- ✅ Five tops (KDF, measurement, tag, controller, endpoint) at 20 ns, 0 latches, child engines kept
- ✅ D-SYN-1 / D-SYN-2: measurement 120,581 -> 8,763 LUT, equivalence 33,809/0
- ✅ Attestation latency measured

### NOC-3 (I-5, 2026-10-29): L2 authentication
- ✅ M-F1 rev 6 / rev 7 (P7: control-plane MAC on tiles 3 / 4, KMAC128-16 `NOC-L2-AUTH-v1`)
- ✅ Attacks: tamper header / payload / tag, wrong source / key, replay, old-boot replay, sequence wrap, truncated /
  overlong, overload drain
- ✅ Bypass controls (MAC, sequence, epoch, identity) each let their attack through (killed)
- ✅ Latency / area vs NOC-2 (L2 adds +113-115 cycles); signed arbiter bounds (Q <= 792, P <= 269)
- ✅ S1 / B-4 P7 subsystem package PASS (2026-10-23)

### NOC-4 (I-6, 24/24, 2026-11-03): trusted authorization
- ✅ Fault status connected and observable (source, operation, reason, epoch)
- ✅ Gate integrated at every untrusted boundary: blocked after reset, grant only from RoT with status 1 + whitelist,
  worker grant rejected, revoke / failure / timeout / reset block, trusted clear + retry, memory responses gated
- ✅ Verifier busy retry (C-1 / C-2), K-3 enforced in hardware, C-5 0x2 window
- ✅ Mutants killed: gate bypass, issuer check off, revoke ignored (+ trusted off, fault-status off, K-3 off, old window)

### PQ-4 (I-7, 2026-11-03): security matrix SEC-1 to SEC-4
- ✅ 30/30 checks on the real modules; 8 controls killed
- ✅ Genuine tile, wrong key / identity / measurement, SPOOF forgery, L2 + attestation replay, stale epoch, nonce
  substitution, reset replay, runtime substitution, wrong issuer, error response, timeout, status-clear misuse,
  truncated challenge, concurrent SPOOF

### PQ-5 (I-7): offline full chain
- ✅ 21/21 non-demo: challenge -> L2 transport -> endpoint -> response -> verifier (teammate + policy) -> grant ->
  authorized write / read -> revoke / substitution blocked; reset at 5 boundaries; timeout + retry; coexisting SPOOF
- ✅ Nonce reported as "deterministic demo issuer" (no TRNG claim)

### NOC-5 (I-8, 76/76, 2026-11-03): release
- ✅ N-11: SEC matrix consumed on the release identity
- ✅ N-12: 73/73 on one identity (39 positives + 34 controls killed)
- ✅ N-13: secure and insecure profiles closed at 20 ns, every I/O timed
- ✅ Release `releases/DUAL_LANE_10_20261103/` with manifest

**R4 plan result: NOC 5/5 ✅ · PQ 5/5 ✅**

---

## Phase 2: area, timing and release builds (22 Oct to 5 Nov 2026)

- ✅ S1 (B-4 P7 subsystem, OOC routed)
- ✅ S3 area package (Keccak sharing A1, single-block SHA3 A6, KMAC state-copy removal A5, T1 fanout): −6.5k LUT, timing met
- ✅ S4 area / timing package (flatten + AreaOptimized, mesh split S4-F3, A5 KMAC): **N-13 secure 32,708 LUT (−14 %),
  WNS +0.275 ns**; one HARD STOP (WNS −0.018) fixed by S4-F3 and re-run, 66/66
- ✅ Vivado project updated to the release sources (36 simulation sets)
- ✅ Kalash's release run: **36/36 ALL VERIFIED**, three bitstreams with timing met

  | Bitstream | LUT | Slack (ns) |
  |---|---|---|
  | p7_soc | 32,118 | +0.184 |
  | p7_area | 32,830 | +0.091 |
  | p7_board | 29,319 | +0.017 |

- ✅ B1 counters measured (narrowing adds LUT) -> closed; A3 measured (about −0.4k) -> parked with a reopen trigger
- ➖ Faster router timing: needs the protected router RTL, which was not approved; T4 lookahead parked (+0.016 ns only)

---

## Phase 3: integration for the CPU merge (5 to 6 Nov 2026)

- ✅ M-F1 rev 8 integration contract **signed** (D1 CPUs at tiles 3 + 0, D2 64-byte IMEM, D4 52k LUT, D6 NI slot timeout,
  D7 bridge timeout 4,096); xp:202 lint waiver acknowledged
- ✅ I-9 integration RTL: app_rx export, NI slot timeout, tile-2 BRAM port + 16 KB window, K-3 length parameter;
  **60/60 PASS** (13-check bench, 53 re-runs, 5 new controls killed)
- ✅ I-10 D2 qualification: 64-byte vectors from the teammate reference + hashlib; **6/6 PASS** (12-check bench, both
  controls killed)
- ✅ Engineer 4 package: re-run 224/224 + 15/15, imported, harness job with frozen counts, response sent (4 findings)
- ✅ Merge prep: stub-CPU merged skeleton 7/7 (scratch and project mode); skeleton bitstream LUT 29,420, WNS +0.337;
  project-update Tcl tested on a copy; provisioning helper; board bring-up checklist
- ✅ Research scope + plan to GDSII (college Cadence flow)
- ✅ Full audit against the original plan (reports/LANE_AUDIT_20261106.md); STATUS.md rev 21

---

## Not done yet (outside the two lanes, or waiting on others)

- ⬜ Merge with the real RISC-V CPUs (waiting on the RISC-V package; contract sec. 8 settles then)
- ⬜ Engineer 4 fixes F1 (pinned KMAC reference) and F3 (layout independence)
- ⬜ Board run (Kalash; checklist ready) -> only then HARDWARE_VALIDATED can change
- ⬜ Paper measurements: insecure baseline re-measured with the S4 flow; latency re-confirmed on the final design
- ⬜ ASIC to GDSII (college Cadence; step A0 = confirm tools, PDK, memory compiler)
- ➖ Formal proof of the security properties, side-channel evaluation, TRNG integration, asymmetric PQC (by scope decision)
