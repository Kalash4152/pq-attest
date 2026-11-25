# PQ-Attest: project handoff for an AI successor, from the start to 1 Oct 2026, with the forward plan

**Owner:** Kalash Bheda (Lane 1: NoC and crypto). Lane 2 is a separate team building the processor tile (`picorv32_adapter.sv`, `addr_decode.sv`).
**Prepared:** 2026-10-01. Every live file fact below was re-read on the user's machine on this date.
**Repo:** `C:\vivado_verilog_proj\NOC_PQATTEST`, branch `noc/credit-integration`, HEAD `9576ed7`. 250 files are tracked.
**Tools:** Vivado/XSim 2024.1 on Kalash's Windows PC is the reference simulator. Verilator 5.48/5.49 runs in a Linux VM as a cross-check; its helpers are not in the repo. Part `xc7a100tcsg324-1` (Arty A7-100T).

> **Read this first: questionnaire mapping status.** The text of Q001–Q112 and O1–O12 did not survive this session's context reset, and I will not reconstruct question wording I cannot see. This document answers every topic the questionnaire covers in the required record format (Answer / Basis / Evidence / Remaining issue), and the P0 material comes first. **The per-ID mapping is pending.** If Kalash re-pastes the questionnaire, each record here maps directly onto an ID. The only archive observation I can reconcile from the record is **O4** (the `n6_mutation.tcl` `.orig` restore hazard), plus a full `mut.zip` against live-tree check (§7).

**Basis tags used throughout:** `LIVE` = live file fact (1 Oct) · `LOG` = log result · `DEC` = decision accepted by Kalash · `ASSUME` = assumption · `PROP` = proposal · `UNK` = unknown.

**Progress terms used throughout:** implemented · elaborated · lint checked · simulated · reference checked · mutation tested · formally proven · hardware validated. **No module in this project is formally proven or hardware validated.**

---

## Part 1: One-page summary

**What it is.** PQ-Attest is a 3×2 mesh network-on-chip SoC on an Arty A7-100T. It has six tiles: CPU0=0 (0,0), CPU1=1 (1,0), MEMORY=2, CRYPTO=3, ROT=4, SPOOF=5. A crypto lane, built on Keccak (SHA3-256, KMAC128, KDF, measurement, tag), produces remote-attestation responses. The NoC uses:

- XY routing and wormhole switching, with a per-output-port lock (FD-1);
- 3 virtual channels (VC0 = request, VC1 = response, VC2 = attestation), each 4 deep;
- credit-based links between routers, and ready/valid at the LOCAL port.

**Where it stands.**

| Lane | Stage | Strongest evidence |
|---|---|---|
| NoC | N-2.5 timing | Router fabric closed at **50 MHz** (WNS +0.202 ns, PhysOpt, RTL `acd1f73`) |
| NoC | M-F1 interface freeze | **Rev 5** (`9576ed7`) |
| NoC | N-8.1 network-interface (NI) endpoint containment | Implemented, simulated and mutation tested 7/7, **Verilator only**. XSim regression and OOC synthesis have **not been run**. |
| Crypto | S-1 … S-7 | Simulated in XSim; S-7 reference checked and mutation tested 4/4 |
| Crypto | S-8 controller | Implemented. XSim 54/0 and 146/0 (bit-exact against an independent reference chain); mutation tested 4/4 |
| Integration | NoC ↔ crypto, processor tile, SoC top | **Not started.** Blocked on the S-8 width decision (rev 6) and on Lane 2. |

**The three things most likely to cause damage:**

1. **`scripts/n6_mutation.tcl` reverts the live router.** It restores `mut/noc_router.sv.orig` (35,612 B, 23 Sep) over the live `noc_router.sv` (37,857 B). Do not run it as-is (§3, P0-3).
2. **N-8.1 has never been simulated in XSim.** Every N-8.1 number is Verilator only. Do not call it verified.
3. **S-8 response and challenge widths conflict with the frozen transport.** The response is 776 bits against 512 bits of wire payload, and the challenge needs 208 bits against 160. This is undecided and owned by Kalash (rev 6).

**Next action:** Kalash runs `n81_xsim.tcl` (11 jobs), then `n81_ni_ooc.tcl`, then the N-2.5 re-gate. After that he decides the S-8 widths, which become M-F1 rev 6.

---

## Part 2: P0 records (read before touching anything)

**P0-1 · Repo identity and HEAD**

- **Answer:** Branch `noc/credit-integration`, HEAD `9576ed7` ("M-F1 rev 5: §5a remote memory access semantics").
- **Chain:** `9576ed7 ← 48b52f2 ← ead8800 ← ab48fe6 ← c3c3d12 ← d454a17 ← 3c74fb5 ← d6035ed ← f73eb88 ← ac079e9 ← e67062e ← acd1f73`.
- **Basis:** LIVE.
- **Evidence:** `git log --oneline -12`, run 2026-10-01.
- **Remaining issue:** None.

**P0-2 · Working tree is not clean**

- **Answer:**
  - `M NOC_PQATTEST.xpr`: +90/−10 lines, uncommitted Vivado edits, including an incremental-synthesis DCP reference.
  - Untracked: `pq_attest_protocol_pkg.sv` (orphan duplicate package); `pq_attest_request.sv` and `pq_attest_response.sv` (**0 bytes**, Kalash placeholders, 25 Sep); `NOC_PQATTEST.srcs/utils_1/`; `_recovery_backup/`; `mut.zip`.
  - `vivado.zip`, noted earlier, is **no longer present**.
- **Basis:** LIVE.
- **Evidence:** `git status --short` and `git diff --stat NOC_PQATTEST.xpr`, 2026-10-01.
- **Remaining issue:** These need Kalash's disposition. Do not commit the `.xpr` blindly, and do not add the 0-byte files to any fileset (an empty module file is harmless, but it is ambiguous intent).

**P0-3 · O4: the `n6_mutation.tcl` restore hazard**

- **Answer:** The script copies `mut/noc_router.sv.orig` over the live router: line 50 runs `n6_run control_restored`, and line 51 runs `file copy -force $R/mut/noc_router.sv.orig $SRC`. The `.orig` is 35,612 B from 23 Sep. The live router is 37,857 B and carries D7 (LINK_PIPE), D7b (EJECT_PIPE) and the M-F1 work. **Running the script silently reverts the router to its pre-D7 state.**
- **Basis:** LIVE.
- **Evidence:** `scripts/n6_mutation.tcl` (sha256 `184d5f630a08f30e…`, 2,503 B), lines 24, 50, 51 and 55; `ls -la mut/`.
- **Remaining issue:** Not fixed. This is WP-0. The fix: snapshot the live router to a temp file first, restore from that snapshot, regenerate the mutants from the current router, and add a sha256 check after the restore.
- **Modifies files:** YES. It modifies the live RTL.

**P0-4 · Width conflict blocks S-8 transport**

- **Answer:**
  - **Response:** the controller emits 776 bits (TILE_ID@0 7B · EPOCH@7 10B · NONCE@17 16B · MEAS@33 32B · TAG@65 32B). The frozen wire payload is 512 bits.
  - **Challenge:** it needs epoch+nonce = 208 bits. The wire carries 160 bits.
  - **Recommended (PROP):** Q-C (challenge = 7 flits) plus R-B (response = measurement‖tag, 16 flits; TILE_ID, EPOCH and NONCE are already known to the verifier).
  - **Alternative (PROP):** R-A (the full 776 bits, 25 flits).
- **Basis:** LIVE (the RTL widths) + PROP (the options).
- **Evidence:** `pq_attest_protocol.sv` (`07cae635a062bd0d…`, 21,337 B); M-F1 rev 5 explicitly defers S-8 widths to rev 6.
- **Remaining issue:** **This is Kalash's decision.** M-F1 rev 6 cannot be written until it is made.

**P0-5 · Highest verified state per lane**

- **Answer:** See the ledger in Part 3.
- **NoC:**
  - The router mesh is simulated in XSim and in Verilator.
  - N-6 is mutation tested 3/3. It is **not** reference checked, because no independent golden model exists.
  - The N-8.1 NI is simulated and mutation tested 7/7, in Verilator only.
- **Crypto:**
  - S-7 and S-8 are reference checked and mutation tested 4/4, in XSim.
  - S-1 is simulated against a golden model with narrow stimulus.
- **Basis:** LOG.
- **Evidence:** `logs/` (listed in §7); `docs/STATUS.md` rev 17, lines 143, 182–207 and 233.
- **Remaining issue:** Nothing is formally proven or hardware validated.

**P0-6 · What has NOT been run (never claim it)**

- **Answer:**
  - N-8.1 XSim regression, 11 jobs;
  - NI OOC synthesis;
  - N-2.5 re-gate after the NOC_PKG/NI change;
  - N-7 pipe0 generic fix rerun;
  - D4 crypto OOC synthesis;
  - any whole-SoC synthesis;
  - any bitstream or hardware run;
  - the Python end-to-end golden for S-8.
- **Basis:** LIVE.
- **Evidence:** No `logs/n81_*xsim*` and no `reports/n81_ni_ooc_*` exist. The last XSim in the `.sim` directory is `tb_stg_8_ref`, 25 Sep 20:38.
- **Remaining issue:** The run order is WP-1 → WP-3.

**P0-7 · Interface contracts in force**

- **Answer:** M-F1 rev 5 is the binding contract between NoC transport and endpoints. N-8.1 rev 1 is frozen as the implementation spec.
- **Basis:** DEC.
- **Evidence:** `docs/decisions/M-F1-interface-freeze.md` (`c1bb98df4f56682b…`, 22,795 B, `9576ed7`); `docs/decisions/N-8.1-ni-endpoint-containment.md` (`85c2f4f2e8cca088…`, 50,966 B, `d454a17`).
- **Remaining issue:** Rev 5 §5a went to Lane 2 and has had **no reply or rebuttal yet**. Treat it as binding on Lane 1 and proposed to Lane 2 until they acknowledge it.

**P0-8 · Secrets**

- **Answer:** `root_secret` is a 256-bit **input port** with no on-chip source. TBs drive random or test values. TRNG_SOURCE is replay only. No real secret exists anywhere in the repo.
- **Basis:** LIVE + DEC (the source is undecided).
- **Evidence:** `tb_stg_8_ref.sv` lines 34 and 170 (random `root_secret`).
- **Remaining issue:** Kalash must decide the source. On Artix-7 the BBRAM/eFUSE AES key is not readable by user logic, and the user eFUSE (FUSE_USER) is only 32 bits, so neither can hold a 256-bit secret directly. Candidates are an ROT-tile register initialised from the bitstream (encrypted bitstream recommended), or a PUF later. Treat the source as UNK.

**P0-9 · Status document is stale**

- **Answer:** `docs/STATUS.md` is still rev 17 (26 Sep). It does not record M-F1 rev 5 or this handoff.
- **Basis:** LIVE.
- **Evidence:** STATUS.md line 1; sha `2d42da65b5954c60…`.
- **Remaining issue:** Bump it to rev 18 in WP-0.

---

## Part 3: Module evidence ledger

Paths are relative to `NOC_PQATTEST.srcs/`; RTL is in `sources_1/new` and TBs in `sim_1/new`. Hashes are the first 16 hex characters of SHA256, taken on 1 Oct.

| Module (file) | sha256 / size | Highest state reached | Evidence (log, tool) | Gap to next level |
|---|---|---|---|---|
| `NOC_PKG.sv` | `e741a32da93ed598` / 20,573 | elaborated, simulated (via all TBs) | all NoC logs | PQ_MAC_ON path (`MAC_ENABLE=1`) is only exercised by N-8.1 Verilator runs |
| `noc_router.sv` (M8) | `6bd5d99794358361` / 37,857 | simulated (XSim `mf1`: N-7 pipe1 1756/0, M8 47/0, N-6 126/0, TB1 PASS); synthesized and implemented at 50 MHz (WNS +0.202, WHS +0.047, LUT 10,114, FF 2,178, 0/18,237 failing endpoints, mesh-level, at `acd1f73`) | `logs/*_mf1_2026-09-25.log`, `reports/n25_mf1_2026-09-25/` | Router-level mutation; N-7 pipe0 define fix; the reset SVA `a_no_output_after_reset` was reported firing earlier (handoff-corrections 22 Sep) and its current state needs rechecking |
| `noc_network_interface.sv` (M10, N-8.1) | `83f3b884de6928ab` / 56,968 | implemented, simulated in Verilator (tb_ni_n81: m0w16 115/0, m0w1 114/0, m1w16 113/0, m1w1 112/0; tb_noc_ni 161/0; N-6 126/0), mutation tested 7/7 (Verilator) | `logs/n81_*_verilator_2026-09-25.log` | **XSim never run**; OOC synthesis never run |
| SPOOF system (`tb_noc_n81.sv`, mesh + 6 NIs) | `904eb38ecb58e11a` / 26,837 | simulated in Verilator, 5 configurations | `logs/n81_sys_*` | Results below this table; XSim pending |
| N-6 two-tile (`tb6_1.sv`) | `13d1252de7a941e8` / 52,513 | simulated (126/0), mutation tested 3/3 | `logs/n6_*` | No independent golden model, so not reference checked. Latent bug: the `logic'` 1-bit cast at L46 (`CPU1_REMOTE_ADDR`) |
| `pqattest_stg7.sv` (S-7 tag) | `c7962f8108675408` / 14,309 | simulated (105/0), reference checked, mutation tested 4/4 | `logs/s7_runA/B`, `Claude outputs/S7_MUTATION_PASS.md` | Restored from git on 25 Sep after being overwritten; the overwritten copy is in `_recovery_backup/` |
| `pq_attest_protocol.sv` (S-8 `pq_attestation_controller`) | `07cae635a062bd0d` / 21,337 | implemented, elaborated, simulated (XSim `tb_stg_8` 54/0), reference checked (`tb_stg_8_ref` 146/0, bit-exact against an independent `pq_kdf → pq_measurement → pq_attestation_tag` chain), mutation tested 4/4 (mA–mD all killed by the ref TB; **all 4 survive `tb_stg_8`**) | `logs/s8_ctrl_tb_2026-09-26.log`, `logs/s8_ref_tb_2026-09-26.log`, `logs/s8_mutation_verilator_2026-09-25.log` | No Python end-to-end golden (`Pq_Attest_final` is not in the repo); no OOC synthesis; transport widths (P0-4) |
| S-1 Keccak-f[1600] | — | simulated against a golden model (narrow stimulus) | STATUS L182 | Mutation testing |
| S-2 SHA3-256 | — | simulated (historical, 49/0) | STATUS L185 | Mutation testing; `is_final` latch issue; full-final-block padding issue |
| S-3 KMAC128 | — | simulated (11/0 at `45e831f`) | `logs/s3_kmac_2026-09-23.log` | — |
| S-4 TRNG conditioner | — | simulated (historical, 19/0), replay source only | STATUS L192 | No real entropy source |
| S-5 KDF (`pq_kdf.sv`) | — | simulated (35/0 at `db37449`) | `logs/s5_kdf_2026-09-23.log` | — |
| S-6 measurement (`pq_measurement.sv`) | — | simulated (33/0 at `db37449`) | `logs/s6_meas_2026-09-23.log` | Mutation testing |

**SPOOF containment evidence** (Verilator, `tb_noc_n81`, 25 Sep, Basis LOG):

| Run | Checks | Result |
|---|---|---|
| m0w16 | 97/0 | Δ = 12, 9, 15, 15. Expiry at cycle 42 (= t0 27 + 15). Release order 51 < 53 < 55 < 57. |
| m0w64 | 43/0 | Δ = 60, 57, 63, 63, so Δ grows 1:1 with W (+48 cycles for +48 W). |
| m0n0 | 19/0 | Watchdog off: blocking CONFIRMED, T_bound 79. |
| m1w16 | 43/0 | MAC on: Δ = 13, 13, 15, 15. |
| m1n0 | 19/0 | MAC on, watchdog off: CONFIRMED, T_bound 107. |

All results are within the bound T_A ≤ T_B0 + W + δ(M), with δ(0)=12 and δ(1)=28.

---

## Part 4: Project history, from the start to now

| Date | Commit | Event | Basis |
|---|---|---|---|
| ≤ 6 Sep | — | Golden-vector Python models (`golden/`); NoC M2–M7 unit work | LIVE (file dates) |
| 9–10 Sep | — | `.xpr` backups; `VERIFICATION_LOG.md`, `PLAN_COMPLIANCE_AUDIT.md` | LIVE |
| 15–18 Sep | `73a45f9` … `f6ad8c2` | `git init` (the response to losing the `NOC_PKG.sv` content). Crypto S-1…S-5 compile clean. `context` → `context_in` keyword fix. | project doc handoff-v2 |
| 18–22 Sep | — | D1 SHA3 byte order resolved (LSB-first). S-6, S-7 (105/0, mutation 4/4). N-7 rigorous mesh 1761/0. | logs |
| 23 Sep | `609550c` … | Decision 7c flow control. N-4 credit ports. N-6 with NIs, no bypasses, 126/0, mutation 3/3. N-2.5 runs 1–2. | `docs/decisions/7c-flow-control.md`, logs |
| 24 Sep | — | D7 LINK_PIPE, D7b EJECT_PIPE (credit RTT 4 = depth 4, I-1). N-2.5 run 3: PhysOpt closes 50 MHz. | `reports/n25_run3pe_2026-09-24` |
| 25 Sep | `e67062e` → `acd1f73` | M-F1 rev 1 (transport-only, FD-1 = B′). I-3 negative proven (LOCAL credits 12 = EJECT_DEPTH). Gate passes on the final RTL. | `logs/i3_negative_*`, `reports/n25_mf1_*` |
| 25 Sep | `ac079e9`, `f73eb88`, `d6035ed` | M-F1 rev 2 and rev 3 (signed by delegation) | git |
| 25 Sep | `3c74fb5`, `d454a17` | N-8.1 architecture, external review applied, rev 1 frozen; M-F1 rev 4 (AM-1..AM-6) | git |
| 25 Sep | `c3c3d12` | N-8.1 NI RTL + unit TB; Verilator evidence; mutation 7/7 | logs |
| 25–26 Sep | `ab48fe6`, `ead8800` | S-8 controller (Kalash) + TBs; stg7 restored; XSim 54/0 and 146/0 | logs |
| 26 Sep | `48b52f2` | SPOOF system TB (Verilator 10/10 configurations PASS); WD_ENABLE=0 counter fix; `HANDOFF_2026-09-26.md`; STATUS rev 17 | git |
| 30 Sep | `9576ed7` | M-F1 rev 5 §5a: Lane 2 remote-memory contract | git |
| 30 Sep | — | `mut.zip` archive created (identical to the live tree, §7) | LIVE |

---

## Part 5: Decisions and interface contracts

| ID | Decision | Basis | Where recorded |
|---|---|---|---|
| D1 | All crypto byte order is LSB-first: byte i at `[i*8 +: 8]` | DEC | handoff-v2, S-6/S-7 TBs |
| 7c | Credit-based flow control between routers; ready/valid at LOCAL | DEC | `docs/decisions/7c-flow-control.md` |
| D7 / D7b | LINK_PIPE=1 and EJECT_PIPE=1; credit RTT 4 = FIFO depth 4 (I-1); LOCAL credits 12 = EJECT_DEPTH (I-3) | DEC + LOG | STATUS L65–106 |
| FD-1 B′ | Wormhole with a per-output lock. A stalled tile cannot block others beyond a bound. Containment lives in the NI and **the router is not changed**. | DEC | M-F1 §10, N-8.1 |
| N-8.1 | The endpoint containment mechanism, listed in full below | DEC (frozen rev 1) | N-8.1 doc |
| M-F1 rev 5 §5a | Remote memory access, listed in full below | DEC (Lane 1); awaiting Lane 2 acknowledgement | M-F1 §5a |
| S-8 field order | TILE_ID@0 · EPOCH@7 · NONCE@17 · MEAS@33 · TAG@65 (776 bits), matching the Python field order | DEC (Kalash's controller) | `pq_attest_protocol.sv`, `tb_stg_8_ref.sv` L9–11 |
| N-2.5 | 50 MHz closure is qualified to its implementation conditions (PhysOpt, RTL `acd1f73`) | DEC | `acd1f73` message |

**N-8.1 mechanism:**

- terminator-only RX, with F1–F10 framing rules and RX_DISCARD;
- a per-packet cumulative watchdog W that includes HEAD-pending time and expires on the W-th stall cycle;
- a sticky flag, a counter and an info report, with a trusted clear;
- the transaction slot is freed at the terminator;
- VC, message-type and length rejection;
- TX store-and-forward;
- SPOOF bound T_A ≤ T_B0 + W + δ(M), with δ(0)=12 and δ(1)=28.

**M-F1 rev 5 §5a remote memory access:**

- **Payload words:** RD_REQ [A]; WR_REQ [A, WDATA]; RD_RESP [RDATA]; WR_RESP has none.
- **Byte lanes:** little-endian; `wstrb[i]` = byte i; `A[1:0]` must be 00.
- **Window:** data memory only. OFF = A[23:0]. On a processor tile the window is 16 KB at local 0x4000+OFF; on the MEMORY tile it is up to 16 MB, sized by its owner.
- **Errors:** err=1 if and only if the offset is out of the window, the access is misaligned, or it is misrouted. On error a read returns 0 and a write has no effect. `wstrb=0` is a no-op with err=0.
- **Responses:** exactly one response per request, echoing the tag, sent to `rx_src_coord`. The responder must stay within W on `rx_ready`.

**Open decisions (owner: Kalash):**

- **OD-1:** S-8 widths (P0-4), which become M-F1 rev 6.
- **OD-2:** the `root_secret` source.
- **OD-3:** S-8 nonce origin (verifier-issued vs tile-generated). This also settles whether a real TRNG is in scope.
- **OD-4:** disposition of the 0-byte, orphan and duplicate files (`pq_attest_request/response.sv`, `pq_attest_protocol_pkg.sv`, `ni_tb-1.sv`).
- **OD-5:** whether to keep the incremental-synthesis DCP in the `.xpr`.
- **OD-6:** production value of `WD_LIMIT`. 16 is a TB default; N-6 uses 64. It must be ≥ the worst legitimate tile stall plus margin.
- **OD-7:** the 7.5 deadlock option. Options are A (per-VC lock), B (consumption rule plus an N-8 test, recommended) and C.

---

## Part 6: Open issues and work packages (the forward plan)

### WP-0 · Hygiene (about 30 min; Claude can do it; modifies files)

1. Fix `n6_mutation.tcl`:
   - snapshot the live router;
   - regenerate `mut/*.svmut` from the current router;
   - restore from the snapshot;
   - check sha256 after the restore.
2. STATUS → rev 18: add M-F1 rev 5, this handoff, and the open decisions above.
3. Fix the 1-bit `logic'` cast at `tb6_1.sv` L46. Use `NOC_PKG`'s typed width.
4. Remove the `vivado.zip` mention from earlier notes, since the file is gone.

**Acceptance:** after running `n6_mutation.tcl` in a scratch copy, `git diff` shows no change to `noc_router.sv`.

### WP-1 · N-8.1 XSim regression (Kalash runs it; it writes logs)

- **Run (in the Vivado Tcl console, project open):**
  ```tcl
  source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/n81_xsim.tcl
  ```
  The script runs 11 jobs and sets defines through `xsim.compile.xvlog.more_options`. An INVALID result is printed and the script continues.
- **Acceptance:**
  - every job ends `RESULT : PASS`;
  - check counts equal the Verilator counts above (115/114/113/112, 161, 126, and SPOOF 97/43/19/43/19), or any difference is explained;
  - logs are committed with `git add -f`, because `*.log` is gitignored.
- **On failure:** XSim is the reference. Debug the first divergence; do not edit the TB to pass.

### WP-2 · NI OOC synthesis (Kalash runs it; it writes `reports/n81_ni_ooc_<date>/`)

- **Run (Windows cmd):**
  ```
  cd C:\vivado_verilog_proj\NOC_PQATTEST
  C:\xilinx_vivado\Vivado\2024.1\bin\vivado.bat -mode batch -source scripts/n81_ni_ooc.tcl -log logs/n81_ni_ooc.log -nojournal
  ```
- **Acceptance:**
  - no latches;
  - WNS ≥ 0 at 20 ns under an **assumed** budget of 5 ns in and 5 ns out;
  - the unconstrained in-to-out delay is recorded for N-14;
  - the result is labelled OOC only.

### WP-3 · Regressions after the N-8.1 change

- **N-2.5 re-gate:** run `n25_gate.tcl` with the same PhysOpt strategy. Acceptance: WNS ≥ 0, and LUT/FF compared with 10,114 / 2,178.
- **`d7_regression.tcl`:** RTAG n81.
- **N-7 pipe0:** use the `-d` define fix, not `-generic_top`.

### WP-4 · M-F1 rev 6: S-8 transport widths (needs Kalash's decision OD-1 first)

- **Default proposal:** Q-C challenge (7 flits on VC2) plus R-B response (measurement‖tag, 16 flits).
- **Rev 6 must specify:**
  - flit-to-byte mapping (LSB-first, as D1);
  - message types;
  - the VC2 tag;
  - error and status codes (OPEN-1..5 in STATUS L101).
- **Then:** check `rx_len` limits in the NI against the new lengths.

### WP-5 · S-8 Python end-to-end golden

- Bring `Pq_Attest_final` (Python) into `software/`, or rebuild it from `kmac128_ref.py` and `gen_stage7_vectors.py`.
- Generate vectors and compare against `tb_stg_8_ref`.
- **This turns "reference checked against RTL children" into "reference checked against an independent spec".**

### WP-6 · S-8 network wrapper (`pq_attest_request.sv` / `pq_attest_response.sv`)

- **Architecture before RTL** (Kalash's standing rule): an NI RX challenge parser → controller → TX packetizer at the frozen widths.
- **TB:** challenge in at the NI, response out, compared bit-exact against the Python golden.

### WP-7 · N-8 performance (after WP-1–3)

- traffic generator;
- injection sweep 1..64;
- latency, throughput, occupancy and credit-stall monitors;
- an **independent scoreboard**, which moves N-6/N-7 toward reference checked;
- N-7.5 deadlock evidence.

### WP-8 · D4 crypto OOC synthesis

Required before any whole-design resource claim.

### Later (STATUS L253–254)

N-9 L2 MAC (`MAC_ENABLE=1`, re-gate) → N-10 L3 enforcement → N-11/S-9 security regression → S-10 full chain → N-12 final regression → N-13 FPGA closure → N-14/S-11 SoC integration, with Lane 2's processor tile.

### Known issues, report-only (do not fix without being asked)

- SHA3 `is_final` is read live rather than latched.
- A full final block gets no padding (FIPS 202 needs an extra block).
- The `a_no_output_after_reset` SVA fired earlier; needs rechecking.
- `n25_mesh.xdc` sets 50 MHz while the board oscillator is 100 MHz. Pins were written "from memory" and need checking against the Digilent master XDC before any bitstream.
- `ni_tb-1.sv` duplicates module `tb_noc_ni`; it is not in the `.xpr`.

---

## Part 7: Evidence inventory

**Archive (`mut.zip`), checked LIVE on 1 Oct:**

- SHA256 `c5af0ea94133d689c914e55ec4103aaf64f56e2db24ff2b7c6f274f41e8616c5`; 627 entries, 62,219,621 B uncompressed.
- Extracted and hash-compared per file against the live tree: **536 files identical, 0 different, 0 only in the zip.**
- It is therefore a faithful snapshot of the working tree at `9576ed7` plus the dirty state, **without `.git`**. History must come from the live repo, not the zip.
- Any O-observation that claims the zip and the live tree differ in content is refuted by this check. An observation about missing history is confirmed.

**Decision docs** (`docs/decisions/`):

| File | SHA256 (first 16) | Size (B) |
|---|---|---|
| `7c-flow-control.md` | `f38ffdae655a1638` | 2,941 |
| `M-F1-interface-freeze.md` | `c1bb98df4f56682b` | 22,795 |
| `N-8.1-ni-endpoint-containment.md` | `85c2f4f2e8cca088` | 50,966 |

Also: `docs/STATUS.md` (`2d42da65b5954c60`) and `docs/HANDOFF_2026-09-26.md` (`df5572d1212a1535`).

**Logs** (`logs/`, 72 files) by family:

- `n2_*`, `n35_m8_*`, `n6_*`, `n7_*`: XSim and Verilator results for the D7/D7b/mf1 rounds;
- `n81_*`: Verilator only;
- `s3`–`s8`: crypto;
- `i3_negative_verilator`;
- `recovery_snapshot_2026-09-23.txt`.

**Reports:** `reports/n25_{2026-09-23, run2, run3default, run3pe, mf1_2026-09-25}`.

**Scripts:**

| Script | sha (first 16) | Modifies files? |
|---|---|---|
| `n81_xsim.tcl` | `0bf85fedfdd388d8` | Writes logs and xsim dirs; changes project sim properties (more_options) |
| `n81_ni_ooc.tcl` | `dd7e552c3e0086fc` | Writes `reports/n81_ni_ooc_<date>/` (in-memory project) |
| `s8_xsim.tcl` | `9286fabef4fa5e29` | Writes logs; **disables `pq_attest_protocol_pkg.sv` in the fileset** |
| `n6_mutation.tcl` | `184d5f630a08f30e` | **YES: overwrites `noc_router.sv`** (P0-3) |
| `d7_regression.tcl`, `step2_regression.tcl` | — | Write logs; set sim properties |
| `n25_gate.tcl`, `n25_run3.tcl`, `n25_physopt.tcl`, `n25_timing_triage.tcl` | — | Launch synthesis/implementation runs; write reports |
| `verilator_build.sh` | — | Writes the build dir |

**Python:**

- `golden/golden_model.py` and `rtl_model.py`, with `gv_*.txt` (NoC M2–M7 vectors);
- `software/kmac128_ref.py`, which reproduces the 3 NIST SP 800-185 KMAC128 samples, and `gen_stage7_vectors.py`.

**Project docs mirrored to the claude.ai project:** `claude/M-F1-interface-freeze-DRAFT.md` (rev 5), `claude/N-8.1-ni-endpoint-containment.md`, `claude/HANDOFF_2026-09-26.md`, `claude/final-plan-2026-09-22.md` (STATUS), and `claude/engineering-lessons-combined.md`.

---

## Part 8: Rules a successor must keep

1. Sweep the whole folder before every response, and say what you checked.
2. Never claim a simulation, synthesis or hardware run that was not run. Put the tool, version and log path on every number, and label post-synth vs post-route and OOC vs integrated.
3. XSim is the reference simulator and Verilator is a cross-check. XSim rejects `$urandom(seed)`; use `-d` defines rather than `-generic_top`.
4. Never kill a running simulation. Give Tcl for every rerun.
5. Explain the architecture before writing RTL, and go module by module.
6. Grep every instantiation before changing a port list (RC-3).
7. After `device_commit_files`, verify md5. Stale copies have landed before.
8. Commit with `git -c user.name="Kalash Bheda" -c user.email="kkalash.bheda@gmail.com"` and the Co-Authored-By/session trailer. `*.log` needs `git add -f`.
9. Do not change the router for N-8.1 or S-8 fit. Containment lives in the NI.
10. No secrets in the repo, docs or logs.

---

## Part 9: Transfer acceptance (the successor ticks these off)

- [ ] `git rev-parse HEAD` = `9576ed7` (or a later commit, with every commit after it explained).
- [ ] The sha256 values for the 10 key files match Part 3/7, or the differences are explained.
- [ ] WP-0 is done **before** any mutation run.
- [ ] WP-1 logs are present and their counts reconciled against Verilator.
- [ ] Kalash has given a decision on OD-1, or the successor is explicitly holding.
- [ ] Lane 2 has acknowledged rev 5 §5a.
- [ ] STATUS rev 18 is written.

## Completeness record

- **Fully answered:** the handoff from the start to now, the forward plan, P0 material, the ledger, decisions, work packages, the evidence inventory and transfer acceptance.
- **Questionnaire IDs:** Q001–Q112 are **not mapped by ID**, because the question text is not available in this session. O4 is reconciled. The `mut.zip` against live-tree check covers any O-item about archive fidelity. O1–O3 and O5–O12 are **unreconciled for the same reason**.
- **UNK:** Lane 2 source state; `Pq_Attest_final` Python location; production W; `root_secret` source; current state of the reset SVA.
