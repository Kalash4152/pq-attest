# PQ-Attest NoC lane and PQ-Attest lane: live-folder reconciliation, next five packages per lane, and NQ/PQ answers

**Prepared:** 2026-10-08, for Kalash, Codex and any successor assistant.
**Source:** I read the live Windows tree `C:\vivado_verilog_proj\NOC_PQATTEST` directly on 2026-10-08 (git, hashes, logs, reports, decision documents and `Pq_Attest_final.zip`). No RTL was changed and no build or mutation was run.

**Basis tags used in this document:**

- `LIVE`: read from the live tree today.
- `HEAD`: from the content of git commit `1e3141c`.
- `LOG`: from a recorded run.
- `REC`: a decision recorded in a file, which I have not independently verified.
- `HIST`: from my conversation history only, with no file supporting it.
- `NEW`: my recommendation.
- `UNK`: unknown.

**Evidence ladder terms:**

- *implemented*
- *simulated (XSim)*
- *simulated (Verilator)*
- *reference-checked*
- *mutation-tested*
- *formally proven*
- *hardware-validated*

Nothing in this project is formally proven or hardware-validated.

---

## 0. Corrections to both questionnaires, from the live sweep (read first)

| # | Live finding | Effect |
|---|---|---|
| C1 | **`sim_1/new/ni_tb.sv` has been overwritten.** It should hold `tb_noc_ni`, the NI unit testbench (161 checks). Since 2026-10-02 08:07 it holds a copy of the D7 N-7 mesh testbench, module `tb_noc_mesh_n7`. That module is also defined in `sources_1/new/tb_noc_mesh.sv`, so the project now has **two definitions of the same module**. | This is why the dual-lane runner marks `n81_nitb` INVALID. It is the same accident class as the earlier Stage-7 overwrite. Restore it from HEAD. |
| C2 | **Six tracked documents are deleted in the working tree:**<br>• `docs/STATUS.md`<br>• `docs/HANDOFF_2026-09-26.md`<br>• `docs/PQ_ATTEST_AI_HANDOFF_2026-10-01.md`<br>• `docs/decisions/M-F1-interface-freeze.md` (rev 5)<br>• `docs/decisions/N-8.1-ni-endpoint-containment.md` (rev 1, frozen)<br>• `docs/decisions/7c-flow-control.md` | The authoritative interface freeze is now readable only from git. The new decision documents (§N-9 etc.) reference it but cannot replace it. Restore all six from HEAD; deleting a freeze is not a decision. |
| C3 | **The "not implemented" claims in the questionnaires are out of date.** A dual-lane framework already exists, all untracked:<br>• `scripts/run_dual_lane_10.tcl`, `dual_lane.py` and `dual_lane_jobs.json`<br>• new testbenches `tb_noc_perf`, `tb_noc_l2_auth`, `tb_stg_8_golden`, `tb_pq_full_chain`<br>• oracles `s8_golden.py`, `l2_golden.py`, `full_chain_golden.py`<br>• vectors under `vectors/`<br>• seven new decision documents.<br>Three runs were made today. The latest, `reports/dual_lane_10_20261008_150300_5231be0b`, ends **FAIL**. | The results are spelled out in rows C4 and C5 and in the ledger. |
| C4 | **The NOC-1 failure is caused by the harness and testbench, not the RTL.**<br>• `n81_nitb` is INVALID because of C1.<br>• The five WP-0 N-6 mutation jobs are INVALID because `wp0_common.tcl` was edited after the 2026-10-01 15:51 session (my define-injection and crash-retry edits). That is the runner's identity rule working as intended.<br>• The other ten N-8.1 jobs are `PASS_REUSED` from `wp0_n81_20261002_000837` (11/11). | Fix C1, then rerun the N-6 mutation with the current harness. |
| C5 | The full chain shows `chain_python` PASS_FRESH and `full_chain` PASS_FRESH (16/0, `DEMO=1`), but **PQ-5 is BLOCKED** because its dependencies are not met. | This is demo-level functional evidence only. It is not S-10 acceptance. |
| C6 | **The original Python reference was found.** `Pq_Attest_final.zip` (untracked, repo root) contains `PQ_Attest/software/attestation_ref.py`, `attestation_protocol.py`, `kmac128_ref.py`, `measurement_ref.py`, `security_regression.py`, `cross_module_regression.py` and others. | Questionnaire item 9 and PQ012 are corrected: the reference exists. Its `kmac128_ref.py` **differs** from `software/kmac128_ref.py` in the repo, and the size of that difference is unknown until someone diffs them. |
| C7 | **`dual_lane_config.json` records OD-1 to OD-6 as ACCEPTED** by Kalash on 2026-10-08, quoting the instruction "Approve the proposed offline profile; work through the L2/NI revision…" | I was not in that chat, so this is `REC`, not something I verified. Kalash, please confirm. Note also that **M-F1 rev 6 has not been written**: the accepted wire changes (Q-C/R-B, the N-9 freshness words) exist only in the new documents. |
| C8 | **Two files from another project are in this repo.** `README.md` and `Run_M9_2.ps1` at the repo root are from the OV5642 camera project (M9.2). | Move them out. |
| C9 | **"Security experiments E1–E4" have no historical definition.** In the project history, "E4" means *Engineer 4* (the verification/automation workstream, P0–P3). The `security_e1_e4` job name was invented on 2026-10-08. | Rename it (S-9/N-11 attack matrix). Do not cite it as historical. |
| C10 | **Protected RTL is intact.** SHA256 prefixes: router `6bd5d997`, NI `83f3b884`, `NOC_PKG` `e741a32d`, stg7 `c7962f81`, S-8 controller `07cae635`, `tb_ni_n81` `a2c4f9b0`. `tb_noc_n81` is `b5280370` (the per-instance binding fix, accepted in run 20261002 but **uncommitted**). | Commit it together with its evidence. |

---

## 1. Corrected status ledger, both lanes

| Gate | Implemented | Simulated (XSim) | Reference-checked | Mutation-tested | Evidence | Valid against today's tree? |
|---|---|---|---|---|---|---|
| N-2.5 mesh timing (`noc_mesh_synth_top`) | yes | n/a | n/a | n/a | `reports/n25_run3pe_2026-10-02/gate_summary.txt`: WNS +0.202, WHS +0.047, 0/18,237 failing, 0 route/DRC errors, LUT 10,114, FF 2,178, HEAD 1e3141c | Yes, **mesh only**. NI and crypto are not included. |
| N-7 D7 pipe1 / pipe0 | yes | PASS (`logs/n7_pipe1_d7_2026-10-05.log`, `n7_pipe0_d7_2026-10-05.log`) | golden counts 1756 / 1762 (HIST) | D7b 1 mutant killed (Verilator, 09-24) | — | Partial. No complete five-job D7 session (pipe1, pipe0, M8, N-6, TB1) on the current overlay. |
| N-6 two-tile + NI | yes | 126/0 (`wp0_n81_20261002`) | no independent golden | 3/3 (`wp0_n6_mutation_20261001_155153`) | — | The 126/0 result is valid. **The mutation session is INVALID** because the harness was edited afterwards (C4). |
| N-8.1 NI containment | yes | **11/11 XSim** (`wp0_n81_20261002_000837`), both N0 markers present | Verilator matches | 7/7 (Verilator only) | NI OOC: WNS +4.656, WHS +0.263 (`reports/n81_ni_ooc_2026-10-02`) | 10 of 11 reusable. **`n81_nitb` is invalid** (C1). |
| N-8 performance, N-7.5, N-9, N-10, N-11 to N-13 | testbenches and plans exist (untracked) | NOT_RUN | — | — | `docs/decisions/*.md` (2026-10-08) | Not started as evidence. |
| S-1 to S-6 | yes | historical/current smoke results: 49/0, 11/0, 19/0, 35/0, 33/0 | S-1 against a golden model | none for S-2, S-4, S-6 | STATUS rev 17 (HEAD) | Unchanged sources. |
| S-7 tag | yes | 105/0 | NIST-validated Python vectors | 4/4 | `logs/s7_run*`, hash `c7962f81` | Valid. |
| S-8 controller | yes | 54/0 and 146/0 | against the RTL chain (not Python) | 4/4 (ref TB) | `logs/s8_*_2026-09-26.log` | Valid as controller evidence. The Python golden (`s8_golden`, 95 checks, 7 mutants) is NOT_RUN. |
| Full chain (demo) | testbench | 16/0 `PASS_FRESH` | Python oracle `full_chain_golden.py` | none | dual_lane run 150300 | Demo only. Its stage is BLOCKED. |
| D4 crypto OOC | script exists (`d4_crypto_ooc.tcl`) | — | — | — | — | NOT_RUN. |

---

## 2. Next five packages per lane (all can be driven by Codex)

**Global rules for Codex:**

- Never edit `noc_router.sv`, `noc_network_interface.sv`, `NOC_PKG.sv`, `pqattest_stg7.sv` or `pq_attest_protocol.sv` unless a stage card authorizes it.
- Every run goes through `scripts/run_dual_lane_10.tcl` (Vivado 2024.1) or `scripts/dual_lane.py run --select <sel>`.
- Evidence must be `PASS_FRESH` or `PASS_REUSED` with a matching identity. Never edit an expected count to get a pass.
- A timing failure is a FAIL. Never weaken a check.

### NoC lane

| Step | Historical stage | Codex scope (automatable) | Acceptance |
|---|---|---|---|
| **NOC-1** baseline repair and requalification | N-8.1 10e/10f close-out + hygiene | 1. `git show HEAD:NOC_PQATTEST.srcs/sim_1/new/ni_tb.sv > ni_tb.sv` (restores `tb_noc_ni`; keep the overwritten copy under `_recovery_backup/`).<br>2. `git checkout HEAD -- docs/` for the six deleted documents.<br>3. Move the OV5642 `README.md` and `Run_M9_2.ps1` out of the repo.<br>4. Rerun `n81_nitb` (161) and the WP-0 N-6 mutation (3 kills + 2 controls of 126) under the current harness.<br>5. Run one complete five-job D7 session: pipe1 1756, pipe0 1762 (`N7_PIPE0`), M8 47, N-6 126, TB1 PASS.<br>6. Commit the accepted testbench, script and log changes in **separate** commits. | dual-lane `NOC-1 = PASS` with all 23 jobs valid; `LIVE_ROUTER_UNCHANGED=YES`; `STATUS.md` rev 18 written from the evidence. |
| **NOC-2** | N-8 performance + N-7.5 finite liveness | Run the `tb_noc_perf` matrix per `N-8-performance-plan.md`: 4 patterns × 7 rates × MAC on/off = 56 points, seed `0x12345678`. Independent generator-record scoreboard. Three negative controls (corrupt one payload, remove one flit, stall consumption). Saturated-VC2, reset/drain and second-challenge liveness runs. | All 56 points fully accounted for (no loss or duplicates, idle after drain, credits returned). Each control produces its *targeted* observation; a timeout alone does not count. Curves written as data. No formal claim. |
| **NOC-3** | N-9 L2 authentication | **First** write M-F1 rev 6 (§N-9 wire: 5 freshness words, max length 26, KMAC128-16 `NOC-L2-AUTH-v1`). Then implement the wrapper and NI-preview per `N-9-l2-authentication.md`. Run `tb_noc_l2_auth` against `l2_golden.py`, plus four bypass controls (MAC, sequence, epoch, identity). | Tamper, replay, reset-replay and wrong-key cases give zero NI delivery, zero slot retirement and no deadlock. Every control makes its targeted attack succeed. Earlier N-8.1/N-6 jobs are rerun if any shared source changed. |
| **NOC-4** | N-10 L3 enforcement | Trusted authorization gate at every untrusted application boundary per `N-10-attestation-enforcement.md`; fault/status counters; trusted clear. | Protected traffic is blocked after reset, revoke, failure and timeout. A grant only from RoT with status 1. A worker grant with a valid MAC is rejected. The gate is tested *integrated*, not standalone. |
| **NOC-5** | N-11 security attacks → N-12 final regression → N-13 FPGA closure (separate gates) | Shared attack matrix with PQ-4; full regression of every gate; integrated synthesis/implementation of mesh + NIs + L2 wrappers + endpoint + gate at 20 ns. | N-11: every attack has a working negative control. N-12: all jobs fresh on one identity. N-13: integrated WNS ≥ 0, WHS ≥ 0, 0 route/DRC errors, utilization reported. N-14 SoC integration (Lane 2) remains **out of scope**. |

### PQ-Attest lane

| Step | Historical stage | Codex scope (automatable) | Acceptance |
|---|---|---|---|
| **PQ-1** | S-8 field freeze (S8-1 to S8-5) + independent oracle | 1. Import `Pq_Attest_final.zip` read-only to `software/pq_attest_final/`, and diff its `kmac128_ref.py` against the repo copy.<br>2. Cross-check `s8_golden.py` against `attestation_ref.py`, `kdf`, `measurement_ref` and NIST KMAC/SHA3 KATs.<br>3. Run `s8_python`, `s8_golden` (95 checks) and the seven controller mutants, plus the control.<br>4. Write **M-F1 rev 6 §S8** (Q-C/R-B wire, OD-2 status codes). | The oracle agrees with the original reference on every vector. 95/0. 7/7 mutants killed, each by its targeted check. Rev 6 is committed **before** any packetizer RTL. |
| **PQ-2** | S-8.2 / C2 tile-attest endpoint | Implement `pq_attest_endpoint` per `S8-2-tile-attest-endpoint.md` and HANDOFF-0926 C2.1. Decide whether it replaces or deletes the zero-byte `pq_attest_request.sv` and `pq_attest_response.sv`. Unit testbench, then system testbench (mesh + NIs + endpoint on CRYPTO; RoT issues the challenge; SPOOF stalls). | Mandatory matrix in PQ028 passes. Four mutants killed: tag word order, epoch/nonce offset, wrong reply-to, `rx_ready` stall. RX stall budget is 0 (with an SVA). |
| **PQ-3** | D4 crypto OOC | `d4_crypto_ooc.tcl`: `pq_kdf`, `pq_measurement`, `pq_attestation_tag`, `pq_attestation_controller` and the endpoint, each OOC at 20 ns with `DONT_TOUCH`/keep on the child engines. | WNS ≥ 0 / WHS ≥ 0 (or the failure recorded as FAIL). LUT, FF, LUTRAM, BRAM and DSP reported per engine. Labelled OOC only. |
| **PQ-4** | S-9 security regression (shared with N-11) | Attack matrix PQ034 against the full NoC path with N-9/N-10 enabled; one negative control per attack. | Every attack is rejected with zero grant. Every control makes its attack observable. |
| **PQ-5** | S-10 full chain (offline) | `tb_pq_full_chain` in non-demo mode, checked by the independent `full_chain_golden.py`: challenge → verify → grant → authorized transfer → revoke. Deterministic nonce source (S-4 TRNG is replay only). | Fresh PASS with dependencies satisfied. Production entropy, key provisioning and board validation are explicitly *not* claimed. S-11 final freeze follows. |

**Order (corrected):** NOC-1 → PQ-1 → {NOC-2 ∥ PQ-2} → PQ-3 → NOC-3 → NOC-4 → PQ-4 → PQ-5 → NOC-5.

- NOC-2 and PQ-2 are independent of each other.
- The NOC-3 → NOC-2 dependency in `dual_lane_jobs.json` is a sequencing preference, not a technical one.
- **Shared sub-gates, run once:** the M-F1 rev 6 compatibility jobs (`post_format_compat`), the N-11/S-9 attack matrix and the N-13 integrated closure.

---

## 3. Decisions: accepted vs open

| Item | State | Basis |
|---|---|---|
| D1 LSB-first byte order (byte i at `[i*8 +: 8]`) | Accepted | HIST + S-6/S-7 testbenches |
| FD-1 B′; router frozen; containment in the NI | Accepted | M-F1 rev 4/5 (HEAD) |
| N-8.1 rev 1 spec, AM-1 to AM-6 | Accepted (frozen) | HEAD `d454a17` |
| M-F1 rev 5 §5a remote memory | Accepted by Lane 1; **no Lane-2 acknowledgement found** | HEAD `9576ed7` |
| OD-1 Q-C + R-B; OD-2 status codes; OD-3 offline trust; OD-4 L2 freshness; OD-5 policy; OD-6 N-8 matrix | **ACCEPTED (REC)** on 2026-10-08 | `docs/decisions/dual_lane_config.json`. Kalash to confirm; I was not in that chat. |
| M-F1 rev 6 (the document that carries OD-1/OD-4 onto the wire) | **Not written** | LIVE |
| Production watchdog W | Open (16 and 64 are test profiles only) | OD-5 |
| `root_secret` source on the FPGA | Open; demo stand-in only | OD-3 |
| Nonce origin in production (TRNG) | Open; replay source only | S-4 |
| Disposition of the zero-byte request/response files and `pq_attest_protocol_pkg.sv` | Open; excluded from builds | contract |
| Remove `design_1.bd` from the `.xpr` | Open | LIVE (`.xpr` L395) |

---

## 4. NoC questionnaire NQ001–NQ045

Format: Answer · Status · Evidence · Remaining issue.

| ID | Answer | Status | Evidence | Remaining issue |
|---|---|---|---|---|
| NQ001 | Repo `NOC_PQATTEST`, branch `noc/credit-integration`, HEAD `1e3141c`. Dirty: `ni_tb.sv` (overwritten), `tb_noc_n81.sv` (binding fix), `tb_noc_mesh.sv` (N7_PIPE0), `.xpr` (+114 lines), `n6_mutation.tcl` / `n81_xsim.tcl` (WP-0), 6 documents deleted, large untracked set. Part `xc7a100tcsg324-1`. Synthesis top `noc_mesh_synth_top`; simulation fileset `sim_1`; constraint `n25_mesh.xdc` @ 20 ns. | Confirmed | LIVE git; `reports/n25_run3pe_2026-10-02/gate_summary.txt` | Restore C1/C2; commit in logical groups. |
| NQ002 | Not recorded in the inspected documents (HIST): the per-instance XSim binding root cause; quoted `-d` defines because cmd splits `=`; XSim crash on exit → one bounded retry; `vivado.zip` removal. All are accepted engineering fixes, not user decisions. | Confirmed (HIST + LOG) | `logs/wp0_sysdbg_*`, `wp0_define_proof_*` | Record them in STATUS rev 18. |
| NQ003 | Rev 5 is the latest *committed* freeze. Rev 6 is needed for OD-1/OD-4 and is not written. No Lane-2 acknowledgement of §5a was found. | Confirmed | HEAD `9576ed7` | Lane-2 sign-off; write rev 6. |
| NQ004 | 10e: full XSim regression (N-7, M8, N-6, TB1) + N-7 pipe0 define fix. 10f: NI OOC (labelled OOC) + N-2.5 re-gate. Done: N-8.1 11/11, NI OOC, N-2.5 re-gate (10-02), pipe0/pipe1 PASS (10-05). Remaining: one complete five-job D7 session and a valid `n81_nitb`. | Corrected | STATUS rev 17 L240–241 (HEAD); logs above | NOC-1. |
| NQ005 | Stale: STATUS rev 17 (deleted in the working tree), HANDOFF-0926, `VERIFICATION_LOG.md` (09-10), `NOC_WORKSTREAM.md` (09-09). M-F1 rev 5 is still current. The 10-01 handoff predates the N-8.1 XSim and OOC evidence. | Confirmed | LIVE | Write STATUS rev 18 from the dual-lane evidence. |
| NQ006 | Protected: router, NI, `NOC_PKG`, stg7, S-8 controller, `tb_ni_n81`, `tb_noc_n81`, decision documents. Unsafe: `mut/noc_router.sv.orig` (stale; the WP-0 flow no longer uses it), `tb_noc_mesh.sv.pre_d7_define`, `d7_regression.tcl.pre_d7_define`, the duplicate root `d7_regression.tcl`, the overwritten `ni_tb.sv`, `pq_attest_protocol_pkg.sv`, zero-byte files, OV5642 strays, zip snapshots. | Confirmed | LIVE | Move backups under `_recovery_backup/`. |
| NQ007 | Yes. The flow snapshots the live router with a hash check, generates mutants from that snapshot into private copies, redirects the compile `prj` (never overwriting the live file), requires a targeted oracle message per mutant, and re-hashes the live router at the end. | Confirmed | `wp0_common.tcl` `n6_main`; session 155153 | That session is now invalid on identity; rerun. |
| NQ008 | Untested: Vivado or helper crash mid-job, timeout kill, power loss between redirect and restore. Mitigated because the live file is never written; residue is limited to temporary filesets. | Proposed | `NEW` | Fault-injection test of the harness (kill during a job), then check the tree hash and fileset cleanup. |
| NQ009 | 11 jobs: `tb_ni_n81` m0w16 115, m0w1 114, m1w16 113, m1w1 112; `tb_noc_ni` 161; N-6 126; `tb_noc_n81` m0w16 97, m0w64 43, m0n0 19 (N0), m1w16 43, m1n0 19 (N0). All passed with 1 attempt. | Confirmed | `wp0_n81_20261002_000837/summary.txt` | `n81_nitb` now invalid (C1). |
| NQ010 | Yes. The change is wiring only (39 ports go through local variables); stimulus and checks are identical. In XSim, assertions sampled the wrong array element: `get_value` showed `noc_tx_valid=1` in HEAD while the assertion fired, and the mesh input bit was correct. With the fix, all five configurations give 0 `Error:` lines with the same counts. Verilator (same RTL) never fired. | Confirmed (LOG); the reversed-index mechanism is inferred | `logs/wp0_sysdbg_1`, `wp0_sysdbg_2` | Rerun the fixed testbench in Verilator. |
| NQ011 | Identity = RTL + testbench + package hashes, generated compile/elaborate/simulate scripts and `prj` after define injection, `wp0_common.tcl`/`wp0_support.ps1`, Vivado version, defines, expected count/config contract. | Confirmed | `sources_before.tsv`, dual-lane `identity` | The rule invalidates on harness edits (deliberately strict). |
| NQ012 | Sound. A retry happens only if all three hold: the exit code is nonzero, an `hs_err` file exists, and the log contains `$finish called`. Assertions, mismatches and wrong configs still fail via `judge_pass`. The crashed attempt is preserved, and a second crash is INVALID. `retry_limit=0` in the dual-lane config. | Confirmed | `wp0_common.tcl` L~340 | Dual-lane disables the retry; that is fine. |
| NQ013 | Script `scripts/d7_regression.tcl` + `tb_noc_mesh.sv` (`N7_PIPE0`, 10-02 09:53). Expected jobs: pipe1 1756, pipe0 1762, M8 47, N-6 126, TB1 PASS. I have **no** complete accepted five-job session. | Confirmed / gap | LIVE | NOC-1 step 5. |
| NQ014 | Remaining weaknesses: no harness fault-injection test; XSim `--incr` within a fresh workspace (low risk); `.xpr` state preserved but not hashed; untracked scripts mean identity is not anchored in git. | Proposed | `NEW` | Commit scripts; add a `.xpr` hash to the preflight. |
| NQ015 | Index `i = y*3 + x`: CPU0(0,0), CPU1(1,0), MEMORY(2,0), CRYPTO(0,1), RoT(1,1), SPOOF(2,1). VC0 request, VC1 response, VC2 attestation. XY routing; two-stage round-robin; FD-1 per-output lock to the terminator; credits between routers. | Confirmed | `NOC_PKG.sv` L186–191; N-8.1 §9.1 | — |
| NQ016 | LINK_PIPE=1, EJECT_PIPE=1, FIFO depth 4 × 3 VCs, credit RTT 4 = depth (I-1), LOCAL credit 12 = EJECT_DEPTH (I-3). Invariants: credit count in range, I-3 negative proven, drain checks require every credit returned. | Confirmed | M-F1 rev 4/5; `logs/i3_negative_*` | Not formally proven. |
| NQ017 | Terminator-only RX, framing rules F1–F10, DISCARD, per-packet watchdog W (counts HEAD-pending), sticky flag + counter + info with a trusted clear, slot freed at the terminator, VC/type/length reject, TX store-and-forward. It contains a stalling or malformed *receiver*. It does not contain a truncating *sender* (no router timeout), forged content or replay. | Confirmed | N-8.1 rev 1 | N-9/N-10. |
| NQ018 | §5a: data window only, `OFF = A[23:0]`, 16 KB on processor tiles, little-endian, `wstrb[i]` = byte i, `A[1:0]` = 00, err ⇔ out-of-window, misaligned or misrouted; one response per request with echoed tag. The `logic'` 1-bit cast at `tb6_1.sv` L46 is real latent code. Its effect on N-6 checks has not been analysed. | Confirmed / UNK effect | rev 5; `tb6_1.sv` L46 | Fix and rerun N-6. |
| NQ019 | Today the NI accepts the request at the TX IDLE handshake, allocates the slot on accept, and retires on the RX response terminator. Under N-9, response retirement must move behind the RX quarantine; the design replays only authenticated packets to the NI. | Confirmed / Proposed | NI RTL; `N-9-l2-authentication.md` | NOC-3. |
| NQ020 | A legal tile stall is up to W cumulative cycles per packet. W=16/64 are test profiles; the production budget is open. The crypto endpoint must keep `rx_ready=1` (RX stall 0) and compute after full consumption. | Confirmed | OD-5; HANDOFF C2.1 | Choose a production W. |
| NQ021 | Accepted (REC) as Q-C: 7 words, epoch bits 0–79, nonce 80–207, zero padding 208–223; 8 / 12 flits MAC off/on. **No committed protocol revision yet.** | Corrected | `DUAL_LANE_10_CONTRACT.md` OD-1 | Write rev 6. |
| NQ022 | Accepted (REC) as R-B: 16 words = measurement ‖ tag. R-A (25 words) would need NI capacity requalification (the TX buffer is 16). | Confirmed (REC) | OD-1 | — |
| NQ023 | The RoT reconstructs the tile ID from the authenticated source coordinate (`TILE_0n` map) and the epoch/nonce from its single outstanding-challenge record. One mesh-wide outstanding challenge removes ambiguity. Source authenticity requires N-9. | Confirmed (REC) | OD-3, OD-5 | Secure only after NOC-3. |
| NQ024 | Errors: 16 zero words; status 1 = success, 2–10 = failures (OD-2). The S8-2 endpoint document uses status 10 for all endpoint errors, which **is not the same** as OD-2's per-cause codes. Second challenge is drained/rejected. One outstanding challenge. RX always consumes. | Corrected | OD-2 vs `S8-2-tile-attest-endpoint.md` | Reconcile status codes in rev 6. |
| NQ025 | Yes. Already-valid gates: 10 N-8.1 jobs, NI OOC, N-2.5 re-gate. Remaining: C1/C2 restoration, the `n81_nitb` rerun, the WP-0 N-6 mutation rerun, the five-job D7 session, STATUS rev 18. | Confirmed | dual-lane run 150300 | — |
| NQ026 | `N-8-performance-plan.md` (OD-6): 4 patterns × 7 rates × 2 MAC modes, seed `0x12345678`, 128 warm-up, 2048 measured, drain ≤ 50,000, N_OUTSTANDING=2 with response stand-ins. Neighbor replaces the historical bit-complement pattern. | Confirmed (REC) | that document | — |
| NQ027 | Generation, accept, injection and delivery timestamps; loss, duplicate and corruption checks against generator records; idle and credit-return after drain; queue/network/total latency; throughput per tile. | Confirmed (REC) | same | — |
| NQ028 | Finite saturated VC2, reset/drain and second-challenge tests; truncating-sender limitation stated; no formal proof exists or is claimed. | Confirmed (REC) | `N-7.5-finite-liveness.md` | Formal proof optional (future research). |
| NQ029 | KMAC128, 16-byte output, `NOC-L2-AUTH-v1`. Transcript: HEAD(4) ‖ VC(1) ‖ version(1) ‖ boot epoch(10) ‖ sequence(8) ‖ payload(4n), maximum 88 bytes. Per-directed-peer demo keys. | Confirmed (REC) | `N-9-l2-authentication.md` | Key provisioning is demo only. |
| NQ030 | 64-bit per-peer sequence starting at 1, strictly increasing, committed only after authentication; wrap refuses transmission; reset needs a new boot epoch. Needs new wire fields: 5 freshness words, maximum length 26, i.e. a protocol revision. | Confirmed (REC) | same | Rev 6. |
| NQ031 | TX computes the MAC on a preview of the actual header, recomputing if the slot changes. RX fully quarantines 26 flits before KMAC, then replays to the NI; overload is drained and counted. | Confirmed (REC) | same | Quarantine size and resources to be measured. |
| NQ032 | Header/payload/tag tamper, wrong source/key, replay, reset replay, malformed framing, plus four bypass controls. Require zero NI delivery, zero slot retirement, no deadlock. | Confirmed (REC) | same | — |
| NQ033 | Only RoT (index 4) grants or revokes, with status 1. Protected classes are blocked after reset. Challenge/response transport stays allowed. Revoke, failure and timeout block. | Confirmed (REC) | `N-10-attestation-enforcement.md` | — |
| NQ034 | Fault counters and reason are observable; trusted clear is separate from worker ports. The exact processor-visible register map is **UNK**. | Unknown | same | Lane-2 register map. |
| NQ035 | Historically separate gates: N-11 security attacks, N-12 final regression, N-13 FPGA closure at 50 MHz, then N-14 SoC integration. Grouping them as NOC-5 is acceptable only as three ordered sub-gates. N-14 is omitted and remains Lane-2-dependent. | Corrected | STATUS rev 17 L178–179 | — |
| NQ036 | Integrated top = mesh + 6 NIs + L2 wrappers + endpoint + gate. Mesh-only timing excludes the NI/auth boundary paths; NI OOC uses assumed 5 ns I/O budgets. Acceptance: WNS ≥ 0, WHS ≥ 0, 0 route/DRC errors, full utilization report. | Confirmed | gate reports | That top does not exist yet. |
| NQ037 | Confirmed with NOC-2 ∥ PQ-2 (§2). | Corrected | — | — |
| NQ038 | Kalash owns shared fields. One document (M-F1 rev N) is the single authority. Agents propose changes only through it, and the compatibility job runs before either lane advances. | Proposed | `NEW` | — |
| NQ039 | `NOC_PKG`/NI change → all N-8.1, N-6, N-7, perf and N-2.5 gates. Router change → everything. Testbench change → that testbench only. Harness change → reused evidence becomes invalid (strict rule). Crypto child change → S-x + S-8 + full chain + D4. | Proposed | identity rule | Encode as a matrix in `dual_lane_jobs.json`. |
| NQ040 | Already exists: `run_dual_lane_10.tcl` (preflight, rollback, identity, `PASS_REUSED`/`FRESH`). Missing: committing it to git, `.xpr` hash, harness fault test. | Corrected | LIVE `scripts/dual_lane.py` | — |
| NQ041 | Per job: sources before/after, generated scripts, process exit codes, bounded timeouts, CONFIG banner, counts, N0 markers, protected hashes. Mostly implemented. | Confirmed | `reports/dual_lane_*/<job>/result.json` | — |
| NQ042 | Vivado 2024.1 (`C:/xilinx_vivado/...`) works. Python 3.13 (`.../Python313/python.exe`) works (`chain_python` ran). PowerShell works. Git works. Verilator exists only in the Linux VM, not on Windows. | Confirmed | `dual_lane_config.json`; runs | — |
| NQ043 | End state after NOC-5: implemented and XSim-simulated authenticated/authorized NoC, mutation/negative-control tested, integrated timing closed at 20 ns. **Not** formally proven, **not** hardware-validated. Processor/firmware/board work remains. | Proposed | — | — |
| NQ044 | Risks, highest first:<br>1. Unconfirmed decision provenance and missing rev 6 (Kalash).<br>2. N-9 resources/timing: 12 KMAC engines + quarantines may not fit or close (measure).<br>3. Lane-2 acknowledgement (Lane 2).<br>4. Production W and `root_secret` (Kalash).<br>5. Duplicate-module / overwrite accidents (Codex hygiene). | Proposed | — | — |
| NQ045 | **Immediate task: NOC-1 steps 1–2** (restore `ni_tb.sv` and the six documents from HEAD), then run the `n81_nitb` and WP-0 N-6 jobs. Command: in the Vivado Tcl console, with the project open, `source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/n81_xsim.tcl`, then `source .../scripts/n6_mutation.tcl`. Then `run_dual_lane_10.tcl` to re-evaluate NOC-1. | Proposed | scripts exist (LIVE) | — |

---

## 5. PQ-Attest questionnaire PQ001–PQ045

| ID | Answer | Status | Evidence | Remaining issue |
|---|---|---|---|---|
| PQ001 | Same repo and HEAD as NQ001.<br>• Sources: `SHA3_256.sv`, `kmac128` set, `pq_kdf.sv`, `pq_measurement.sv`, `pqattest_stg7.sv` (`c7962f81`), `pq_attest_protocol.sv` (`07cae635`).<br>• Testbenches: S-x testbenches, `tb_stg_8`, `tb_stg_8_ref`, `tb_stg_8_golden`, `tb_pq_full_chain`.<br>• Python: `software/kmac128_ref.py`, `gen_stage7_vectors.py`, `scripts/s8_golden.py`, `full_chain_golden.py`, plus `Pq_Attest_final.zip`.<br>• Vectors: `vectors/s8_golden.*`, `full_chain.*`.<br>• Scripts: `s8_xsim.tcl`, `d4_crypto_ooc.tcl`. | Confirmed | LIVE | Commit the untracked oracle and testbench files. |
| PQ002 | Accepted earlier (HIST): D1 byte order; D3 nonce origin was left open; S-8 not to change the NoC; architecture explained before RTL. Recorded 2026-10-08 (REC): OD-1 to OD-6. Abandoned but still on disk: `pq_attest_protocol_pkg.sv` (orphan duplicate), the two zero-byte files, the C1.1/R-A options. | Confirmed / REC | HANDOFF-0926 (HEAD); config JSON | Kalash to confirm OD-1 to OD-6. |
| PQ003 | S-8 = attestation protocol (S8-1 fields, S8-2 MAC, S8-3 nonce 128→160, S8-4 status, S8-5 errors). "S-8.2" = endpoint C2 (HANDOFF-0926). D4 = crypto OOC before any whole-design resource claim. S-9 = security regression. S-10 = full chain TRNG→KDF→measure→attest→verify. S-11 = final freeze. The mapping is preserved, except that S-10 historically includes TRNG, which is replay only, so PQ-5 must state that limitation. | Corrected | STATUS rev 17 L182–208 | — |
| PQ004 | Authoritative: `pq_attest_protocol.sv` (`pq_attestation_controller`). The zero-byte request/response files were Kalash placeholders for the wire endpoint and have no content. `pq_attest_protocol_pkg.sv` is an orphan duplicate with an unaccepted status table; it is disabled by `s8_xsim.tcl` and excluded by the contract. | Confirmed | LIVE | Decide: delete, or reuse the names for the PQ-2 endpoint. |
| PQ005 | Current `pqattest_stg7.sv` = git-restored version, SHA256 prefix `c7962f8108675408`, 14,309 B. On 09-25 it was overwritten with Stage-8 package text, which broke elaboration; the bad copy is `_recovery_backup/pqattest_stg7_OVERWRITTEN_stage8pkg_2026-09-25.sv.txt`. Codex must never write to it, and must never "restore" from snapshots or zips. | Confirmed | LIVE hash | Same risk materialised again in `ni_tb.sv` (C1). |
| PQ006 | See §1. Accepted today: S-7 (simulated, reference-checked, mutation-tested), S-8 controller (simulated, reference-checked against RTL, mutation-tested 4/4), S-1 to S-6 at smoke/current level. | Confirmed | logs | No formal or hardware evidence. |
| PQ007 | SHA3-256 (FIPS 202); KMAC128 (SP 800-185); KDF = KMAC128; measurement = SHA3-256; tag = KMAC128. "PQ" claim: symmetric primitives with 128-bit security against Grover-type attack are assumed adequate. **No public-key post-quantum algorithm exists in this design.** | Confirmed / Proposed claim | S8-1 doc; `kmac128_ref.py` | Write the claim precisely in the paper. |
| PQ008 | Yes: `encode_string(tile) ‖ encode_string(epoch) ‖ encode_string(context)`, KMAC128 keyed by root, empty customization. RTL uses 32 bytes (`key_len_sel=01`). The reference allows 16 or 32; the original demo used 16 with context `PQ-ATTEST-KDF`. | Confirmed | `Pq_Attest_final/.../kmac128_ref.py` L414–439; S8-1 | Fix the controller context value in rev 6. |
| PQ009 | Yes: `SHA3-256(tile ‖ config[:config_len] ‖ imem[:imem_len])`, ≤ 135 bytes (one rate block). The config/imem boundary is **unencoded**, so (config ‖ imem) splits are ambiguous. This was a known open item ("decide length-prefix ambiguity"). | Confirmed + open risk | STATUS S-6 line; `pq_measurement.sv` | Kalash to decide whether to accept or add length prefixes. |
| PQ010 | Yes: KMAC128(key, tile ‖ epoch ‖ nonce ‖ measurement, 32, `"PQ-ATTEST-AUTH"`). The customization is the ASCII bytes, encoded by KMAC as `encode_string(S)` inside `bytepad`. | Confirmed | `attestation_ref.py` L13, L28 | — |
| PQ011 | Yes, byte i at `[i*8 +: 8]`. Canonical example: tile `"TILE_03"` → byte 0 = `0x54` ('T') in bits 7:0. Epoch 10 B, nonce 16 B, measurement and tag 32 B, in natural digest byte order. Do not confuse with SV hex literals, which are reversed. | Confirmed | S8-1 doc | Add explicit example vectors to rev 6. |
| PQ012 | **Found:** `Pq_Attest_final.zip` → `PQ_Attest/software/*` (attestation, KDF, measurement, security, cross-module regression). Repo `kmac128_ref.py` ≠ zip copy, delta UNK. | Corrected | LIVE `unzip -l` | Import read-only and diff. |
| PQ013 | Independent because it uses hashlib SHA3 plus a self-tested KMAC (NIST SP 800-185 samples) and never reads DUT outputs. Inputs: root, tile, epoch, context, config/imem + lengths, nonce. Checkpoints: key, measurement, tag, 97-byte response. Cross-check against `Pq_Attest_final` reference vectors. | Confirmed (design) | S8-1 doc; `s8_golden.py` | Run it (`s8_python`). |
| PQ014 | Test: 0, 1, 64, 65 (reject) for config/imem; total 7 + 128 = 135 (maximum); context 0–14 and 15 (reject). The full 136-byte final block is outside the API (SHA3 pads incorrectly at `valid_bytes=136`). `is_final` must stay stable until done. | Confirmed | S8-1; HIST SHA3 debt | An SVA on `is_final` stability is still missing. |
| PQ015 | Inputs: `tile_id[55:0]`, `epoch[79:0]`, `nonce[127:0]`, `root_secret[255:0]`, `context_in[111:0]` with `context_len[3:0]` ≤ 14, `config_data[511:0]` with `config_len[6:0]` ≤ 64, `imem[511:0]` with `imem_len[6:0]` ≤ 64. Outputs: `response[775:0]`, `busy`, `done`, `err`, `status[2:0]`, `error_code[3:0]`. Reset `rst_n` active-low synchronous. | Confirmed | `tb_stg_8_ref.sv` L30–55 | — |
| PQ016 | All request inputs are latched at accept (children receive latched copies; S-6 latches internally). Second start while busy: ignored. Invalid lengths: rejected before any engine starts. Reset in any phase: return to idle. | Partly confirmed | ref TB R3 child-busy check | "Reset in every phase" has no test yet. |
| PQ017 | Yes: 97 B, offsets 0/7/17/33/65, no padding. | Confirmed | `tb_stg_8_ref` L126–130 | — |
| PQ018 | 54/0: sequencing and status. 146/0: R1 boundaries, R2 12 random, R3 5 rejects, R4 recovery, bit-exact against the RTL chain. No defines. Missing: reset mid-run, input change during run, Python oracle. | Confirmed | logs 09-26 | PQ-1. |
| PQ019 | Four mutants: measurement dropped, tag computed without measurement, tag dropped, config ≤ 65 accepted. `tb_stg_8` checks status only, not bytes. The new golden adds 7 mutants (lost measurement or tag, key length, wrong transcript, field order, stale nonce, wrong key). | Confirmed | Verilator 09-25 log; `dual_lane_jobs` | Run them. |
| PQ020 | Controller: `err=1`, status INVALID_REQUEST (`3'b011`), `error_code` 1 = context, 2 = length; context is reported first. Whether `response` is cleared on error is **UNK**, so stale success data is possible. | Unknown in part | ref TB R3 | Add a check: response zero or invalid when `err`. |
| PQ021 | Q-C accepted (REC), no committed revision. | Corrected | OD-1 | Rev 6. |
| PQ022 | R-B accepted (REC). R-A would mean 25 words, NI requalification and changed SPOOF numbers. | Confirmed | OD-1 | — |
| PQ023 | As NQ023. Wrong-tile protection requires N-9 source authentication. | Confirmed | — | — |
| PQ024 | Type ATTEST_CHALLENGE, source must be RoT (authenticated), length 7, padding zero, complete payload; else drain and count. Epoch/nonce freshness is enforced by the RoT record. | Confirmed (REC) | S8-2 doc | — |
| PQ025 | Endpoint states IDLE → RX(7) → RUN → TX_REQ → TX_FILL(16); `rx_ready=1` always; TX words stable under backpressure; reply-to latched at HEAD; reset cancels everything. | Confirmed (design) | S8-2; HANDOFF-0926 C2.1 | Not implemented. |
| PQ026 | A busy endpoint drains a second challenge with no response; the issuer times out. Store-and-forward NI TX means no router lock is held during crypto. | Confirmed (REC) | OD-5 | — |
| PQ027 | Mesh-wide single outstanding challenge (VC2 carries both directions). Endpoint RX stall 0 ≪ W. | Confirmed (REC) | N-7.5 doc | — |
| PQ028 | Reset in every state; truncated, overlong and wrong-pad challenges; wrong type/issuer; duplicate and busy arrival; MAC on/off; sustained TX backpressure; reply-to; word offsets; SPOOF stall in the system testbench. | Confirmed | S8-2 + C2.2 | — |
| PQ029 | Trusted: RoT, CRYPTO endpoint, NoC fabric, L2 wrappers. Untrusted: worker tiles, SPOOF (can stall, malform, replay, forge headers). Physical attacks and side channels are out of scope. | Confirmed (REC) | OD-3 | — |
| PQ030 | Demo root only in RoT + CRYPTO; per-tile keys derived by KDF inside the trusted boundary. A compromised worker never holds the root. Production storage is open. | Confirmed (REC) / open | OD-3 | `root_secret` decision. |
| PQ031 | RoT issues nonces (unique per epoch, retired on completion, timeout or reset). Epoch is provisioned externally at boot. Deterministic test values are demo only. No production entropy claim (S-4 is replay only). | Confirmed (REC) | OD-3 | TRNG qualification is out of scope. |
| PQ032 | The RoT holds an independent measurement whitelist; a grant only on status 1 **and** a whitelist match. | Confirmed (REC) | N-10 doc | Whitelist provisioning is demo only. |
| PQ033 | **No historical E1–E4 security experiments exist.** E4 = Engineer 4 workstream (C9). | Corrected | handoff-corrections 09-22 | Define the S-9/N-11 matrix (PQ034). |
| PQ034 | Wrong identity or key; stale epoch; nonce substitution; replay (same epoch); modified config or imem; forged response (from SPOOF); transport tamper (header, payload, tag); reset-assisted replay; second-challenge race; truncated challenge. | Proposed | `NEW` | — |
| PQ035 | One control per attack: disable that specific check (nonce compare, epoch compare, whitelist, MAC, sequence, source identity) in a test-only build. The attack must then produce an unauthorized grant or delivery. | Proposed | N-9 doc controls | — |
| PQ036 | Detection only at explicit re-attestation trigger or interval; grant expiry on timeout or revoke. No claim about changes between measurements. | Confirmed (REC) | OD-5 | Interval value is open. |
| PQ037 | `pq_kdf`, `pq_measurement` (one `sha3_256`), `pq_attestation_tag` (KMAC), `pq_attestation_controller` (one each), endpoint. Use `DONT_TOUCH` on children and output XOR-fold or keep on response bits. | Proposed | `d4_crypto_ooc.tcl` exists | Confirm the script contents. |
| PQ038 | 20 ns, I/O delay 5 / 5 ns labelled as an assumption, `report_timing -unconstrained` for in-to-out, WNS/WHS ≥ 0, report LUT, FF, LUTRAM, BRAM, DSP. | Proposed | `n81_ni_ooc.tcl` template | — |
| PQ039 | Latency: measured cycles per attestation (unknown; three Keccak permutation chains). There is no initiation-interval requirement, since one challenge is outstanding. If timing fails, multicycle Keccak or a slower crypto clock domain is a **new decision** (it introduces CDC). Never change the clock silently. | Proposed | — | Measure in PQ-3. |
| PQ040 | Fresh challenge (RoT) → endpoint computes → response → RoT verifies with an independent oracle → grant → authorized memory transfer succeeds → revoke → transfer blocked. Final outcome judged by `full_chain_golden.py`. | Confirmed (design) | `tb_pq_full_chain` | Non-demo run. |
| PQ041 | Confirmed with NOC-2 ∥ PQ-2. Shared gates: rev 6 compatibility, the attack matrix, N-13 closure. | Corrected | — | — |
| PQ042 | Rev 6 (wire) invalidates N-8.1 MAC-on jobs, N-6, perf and endpoint jobs. A crypto child change invalidates S-x, S-8, D4 and the full chain. Owner: Kalash. | Proposed | identity rule | — |
| PQ043 | Exists: `dual_lane.py` registry, vector generation, identity hashes, `PASS_REUSED`/`FRESH`/`BLOCKED`, rollback. Missing: commit, `.xpr` hash, harness fault test. | Corrected | LIVE | — |
| PQ044 | Offline subsystem acceptance (simulated, reference-checked, mutation-tested, OOC timing). Remaining afterwards: processor/firmware (Lane 2), physical entropy, key provisioning, board validation, any formal security proof. | Proposed | — | — |
| PQ045 | **Immediate PQ task: PQ-1a.** Import `Pq_Attest_final.zip` read-only; diff the two `kmac128_ref.py` copies; run `s8_python` and cross-check it against `attestation_ref.py` vectors. Acceptance: byte-identical key, measurement and tag on all vectors. Then `s8_golden` + 7 mutants. | Proposed | LIVE | Kalash to confirm OD-1 to OD-6 and the measurement-boundary decision (PQ009). |

---

## 6. Decisions needed from Kalash, ranked

1. **Confirm OD-1 to OD-6** as recorded in `dual_lane_config.json`, and authorize **M-F1 rev 6** to carry them. This blocks NOC-3, PQ-2 and everything after them.
2. **Status codes:** OD-2's per-cause codes (2–10) or the endpoint's single code 10 (NQ024/PQ020).
3. **Measurement boundary:** accept the unencoded config‖imem boundary or add length prefixes (PQ009). Adding prefixes invalidates S-6, S-8 and the vectors.
4. Fate of the zero-byte request/response files and `pq_attest_protocol_pkg.sv`.
5. Production watchdog W and `root_secret` source. These do not block the five packages but block any release claim.

---

## 7. Codex handoff addendum (self-contained)

```
REPO  C:\vivado_verilog_proj\NOC_PQATTEST  branch noc/credit-integration  HEAD 1e3141c
TOOLS Vivado/XSim 2024.1 (reference), Python 3.13, PowerShell, git. No Verilator on Windows.
PROTECTED (never write): sources_1/new/{noc_router.sv 6bd5d997, noc_network_interface.sv 83f3b884,
  NOC_PKG.sv e741a32d, pqattest_stg7.sv c7962f81, pq_attest_protocol.sv 07cae635},
  sim_1/new/{tb_ni_n81.sv a2c4f9b0, tb_noc_n81.sv b5280370}, docs/decisions/* from HEAD.
RULES  Evidence only via scripts/run_dual_lane_10.tcl or the WP-0 runners. Never change expected counts,
  never weaken checks, never restore from zips/snapshots, never edit a file to "fix" a duplicate module
  without checking git. Timing failure = FAIL. Wire changes only via a new M-F1 revision document.
TASK 1 (NOC-1a): git show HEAD:<path> for ni_tb.sv and the 6 deleted docs; move the overwritten ni_tb.sv
  to _recovery_backup/; move README.md + Run_M9_2.ps1 (OV5642) out of the repo. Verify that only one
  module tb_noc_mesh_n7 and one module tb_noc_ni exist across the sources.
TASK 2 (NOC-1b): Kalash runs n81_xsim.tcl, then n6_mutation.tcl, then run_dual_lane_10.tcl.
  Expect n81_nitb 161/0, N-6 mutation 3/3 + 2x126/0. NOC-1 still needs the 5-job D7 session.
TASK 3 (PQ-1a): unzip Pq_Attest_final.zip -> software/pq_attest_final/ (read-only); diff kmac128_ref.py;
  cross-check s8_golden.py against attestation_ref.py; then dual_lane.py run --select <s8 selection>.
DONE = reports/dual_lane_latest.json shows NOC-1 PASS and PQ-1 PASS, with committed evidence.
```

**Immediate next task:** NOC-1a. It is file restoration only, with no RTL change.
