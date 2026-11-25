# Codex instruction set, Revision 4 (final): five NoC + five PQ-Attest steps

**Issued for:** Kalash Bheda. **Date:** 2026-10-08.
**Supersedes:** Revision 3 and the Codex checkpoint future plan.
**Repo:** `C:\vivado_verilog_proj\NOC_PQATTEST`, branch `noc/credit-integration`, HEAD `1e3141c`.
**Tools:** Vivado/XSim 2024.1, Python 3.13 (path in `dual_lane_config.json`), PowerShell, git.
**Not available:** Verilator on Windows, and board access. There are 0 hardware runs.

The verified facts below come from a live-tree read by Claude on 2026-10-08. Where this document and the live tree disagree, the **live tree wins**: record the difference and stop that step.

---

## 0. Verified state at intake (Codex checkpoint audited)

| Item | Verified |
|---|---|
| Protected production RTL | Unchanged. Router `6bd5d997`, NI `83f3b884`, `NOC_PKG` `e741a32d`, stg7 `c7962f81`, controller `07cae635` |
| Secure variants | Under `rtl/dual_lane/`. The `NOC_PKG.sv` variant changes only the challenge width (160→224) and length (5→7). The `noc_network_interface.sv` variant **adds one output** (`tx_auth_preview`) and leaves the state machine untouched. New modules: `noc_l2_auth`, `noc_attest_gate`, `noc_fault_status`, `pq_attest_endpoint`, `pq_rot_verifier`, `pq_noc_subsystem`. These are implemented but **unqualified**. |
| Latest run | `reports/dual_lane_10_20261008_150300_5231be0b` = FAIL. Accepted packages: 0/10. `full_chain` 16/0 at `DEMO=1` (demo only). |
| `n81_nitb` INVALID | `sim_1/new/ni_tb.sv` (the `tb_noc_ni` 161-check NI testbench) was overwritten on 2026-10-02 08:07 with a D7 mesh testbench. That file defines module `tb_noc_mesh_n7`, which **also** exists in `sources_1/new/tb_noc_mesh.sv`, so the module is defined twice. The two files are **not** byte-identical. |
| WP-0 N-6 mutation INVALID | `wp0_common.tcl` changed after session `155153`. The cause is the harness, not the RTL. |
| Six committed documents deleted in the working tree | STATUS, HANDOFF-0926, the 10-01 handoff, M-F1 rev 5, N-8.1 rev 1, 7c. They exist at HEAD. |
| **Teammate ZIP not used** | `Pq_Attest_final.zip` (SHA-256 `047bb5a981050f11a572a60e850f7c7511ff5d636f7903c6a8d239891003c6a0`) is in the repo root. **No script references it.** `scripts/s8_golden.py` re-implements the composition on top of the repo `software/kmac128_ref.py` (`73d9b064`), which differs from the ZIP copy (`ac8076e6`). This is the main PQ-lane gap. |
| Stray files | `README.md` and `Run_M9_2.ps1` at the repo root belong to the OV5642 project. |

---

## 1. Decisions (council-reviewed; Kalash to confirm in one line)

| ID | Decision | Rationale | Impact |
|---|---|---|---|
| **K-1 Key profile** | **`TILE_KEY_BYTES = 32`** is the system profile. Add a separate job that reproduces the teammate's 16-byte examples **unchanged**. | The teammate KDF supports both lengths. The RTL (S-5/S-7/S-8) is qualified at 32 bytes. Switching to 16 would requalify three stages for no security gain. | No RTL change. Every PQ job records `TILE_KEY_BYTES=32`. |
| **K-2 Status codes** | **OD-2 per-cause codes** (1 success, 2 reject, 3 busy, 4 stale, 5 malformed, 6 tag, 7 measurement, 8 identity, 9 epoch, 10 internal) in `tx_control[10:7]`, carried by a fixed 16-word response that is all zero on error. The endpoint emits only the codes it can actually detect: 2, 3, 5, 10. Codes 4 and 6–9 belong to the verifier. | Single-code-10 (the S8-2 document) loses diagnostics. The codes fit in 4 bits. | Fix `S8-2-tile-attest-endpoint.md` to cite OD-2. |
| **K-3 Measurement boundary** | **Keep the unencoded `tile‖config‖imem`**, exactly as in the teammate reference. Document the split ambiguity as limitation **L-1**. Mitigate it in the offline profile by **fixing `config_len` and `imem_len` per tile** as provisioned constants, recorded next to the whitelist digest. With a fixed split, the same concatenated bytes cannot be reinterpreted. The verifier cannot see the lengths, so this is a **provisioning** guarantee, not a cryptographic one. | The teammate reference governs. A length prefix would be a protocol fork that needs Kalash plus the teammate. | None now. The question returns only in a future protocol revision. |
| **K-4 Restoration** | **Restore, preserving everything first.**<br>(a) Copy the current `ni_tb.sv` to `_recovery_backup/ni_tb_OVERWRITTEN_2026-10-02.sv.txt`, then `git show HEAD:<path> > ni_tb.sv`.<br>(b) `git checkout HEAD -- <the 6 deleted docs>`.<br>This is not blind: the deleted files have no local content to lose, the HEAD copies are the committed frozen contracts, and both steps can be undone (`git rm` / copy back). | A frozen interface contract must be readable in the tree. The duplicate module definition is a live compile hazard. | Unblocks `n81_nitb`. Codex's "do not blindly restore" is satisfied by the backup and the hash record. |
| **K-5 PQ authority** | The teammate ZIP governs PQ semantics. It is verified by the 10-step blueprint in §4.0. `s8_golden.py` becomes a **thin adapter over the ZIP's real API**. The repo `kmac128_ref.py` is demoted to a supplementary KAT. | This is Kalash's explicit instruction, and the existing oracle violates it. | Re-qualifies PQ-1 oracle identity. |
| **K-6 Delivery** | Eight increments (§5). Kalash runs the launcher between them. Each increment is a small, reviewable payload. | Codex cannot run Vivado, and one 10-package drop cannot be reviewed. | — |
| OD-1 to OD-6 | Recorded ACCEPTED in `dual_lane_config.json` on 2026-10-08. Kalash confirms once in writing. | — | M-F1 rev 6 is the next document to write. |

---

## 2. Rules (all steps)

1. **Never write** the five protected production RTL files, `tb_ni_n81.sv` (`a2c4f9b0`), `tb_noc_n81.sv` (`b5280370`), the teammate ZIP, or the extracted reference sources. Secure changes go in `rtl/dual_lane/` variants with an explicit source list. Variants that reuse production module or package names may **never** appear in the same compile list as their originals.
2. **Duplicate-name preflight:** every job's source list must contain each `module`/`package` name exactly once, or the job FAILs.
3. **Evidence** comes only from `scripts/run_dual_lane_10.tcl`, `dual_lane.py run --select …` or the WP-0 runners. Allowed states are `PASS_FRESH` and identity-matched `PASS_REUSED`.
   - Expected counts are frozen in `dual_lane_jobs.json` **before** a job's first run.
   - A timeout is never a kill or a pass.
   - Retries default to 0.
4. Never weaken a check, change an expected value or edit a reference vector to pass. A timing failure is FAIL. No clock, pin or CDC changes.
5. **Wire changes** only through an M-F1 revision document, written **before** the RTL that uses it. Then requalify every affected job.
6. **Reporting:** keep implemented, XSim-simulated, reference-checked and mutation-tested as separate claims. Formal proof and hardware validation are `NO`.
7. **Git:** one commit per logical group, author `Kalash Bheda <kkalash.bheda@gmail.com>`. Never `reset --hard` or `clean -fd`.

---

## 3. NoC lane: next five steps

### NOC-1: Baseline repair and requalification (historical N-8.1 10e/10f close-out)
1. Apply K-4. Move `README.md` and `Run_M9_2.ps1` to `C:\vivado_verilog_proj\OV5642_CAMERABRING_UP\` (or `_recovery_backup/foreign/`). Record before and after hashes in `docs/BASELINE_CURRENT.md`.
2. Add the duplicate-name preflight (Rule 2) to `dual_lane_common.tcl`/`dual_lane.py`, and a self-test that injects a duplicate and expects FAIL.
3. Fresh jobs:
   - `n81_nitb` (`tb_noc_ni`, 161/0);
   - WP-0 N-6 mutation with the current helper: 3 targeted kills plus 2 × 126/0 controls, `LIVE_ROUTER_UNCHANGED=YES`.
4. D7 five-job session. Use the **valueless** `N7_PIPE0` define injected as a quoted `-d` in `compile.bat`. Expected: pipe1 1756/0 and pipe0 1762/0, each with `GuardChecks=111`, `ProtocolErrors=0` and `InjBlocked=0`; M8 47/0; N-6 126/0; TB1 `OVERALL: PASS`.
5. Reuse NI OOC (`n81_ni_ooc_2026-10-02`) and the mesh gate (`n25_run3pe_2026-10-02`) if their identity matches; otherwise rerun only those.
6. Diagnose the `tb6_1.sv` L46 `logic'` cast. If it affects exercised addresses, fix it with the package width and rerun N-6. Otherwise record it as debt.
7. Write `docs/STATUS.md` rev 18, `docs/STAGE_MAP.md` and `docs/DECISION_REGISTER.md` (§1 decisions plus provenance; "E4 (historical) = Engineer 4 workstream").

**Acceptance:** NOC-1 = PASS with all 23 jobs valid, and the protected-hash comparison unchanged.

### NOC-2: N-8 performance + N-7.5 finite liveness
- Follow `docs/decisions/N-8-performance-plan.md` (OD-6): 4 patterns × 7 rates × 2 MAC modes = 56 points, seed `0x12345678`, warm-up 128, measurement 2048, drain ≤ 50,000, `N_OUTSTANDING=2`.
- `tb_noc_perf.sv` keeps the per-instance port binding (the XSim assertion-sampling workaround).
- The scoreboard uses generator records only.
- Controls (each must produce its *targeted* observation):
  - corrupt one payload → payload mismatch identified;
  - remove one flit → that packet is reported missing;
  - stall consumption → liveness monitor fires.
- N-7.5 runs: saturated VC2, reset/drain, second challenge.
- `perf_report.py` writes CSV and curves.
- The Verilator cross-check is **BLOCKED (not installed)**. Do not mark it passed.

**Acceptance:** all 56 points fully accounted for, idle after drain with all credits returned, controls effective. Every result is tagged with transport revision, MAC mode, W, seed and tool.

### NOC-3: N-9 L2 authentication (after M-F1 rev 6)
- Write **M-F1 rev 6** first:
  - Q-C challenge: 7 words, padding 208–223 = 0, lengths 8/12;
  - R-B response: 16 words;
  - OD-2 status table;
  - N-9 secure packet: HEAD + 5 freshness words + payload + 4 MAC words, maximum length 26;
  - KMAC128-16 with `NOC-L2-AUTH-v1`;
  - transcript: HEAD(4)‖VC(1)‖ver(1)‖epoch(10)‖seq(8)‖payload.
- Qualify `noc_l2_auth.sv` with `tb_noc_l2_auth.sv` against `l2_golden.py`. That oracle must call the **ZIP's** `kmac128`.
- Tests: tamper header, payload and tag; wrong source and wrong key; replay; reset/old-boot replay; sequence wrap; truncated or overlong packets; overload drain.
- Bypass controls (MAC, sequence, epoch, identity) must each let their attack succeed.
- Rerun the N-8.1 framing jobs on the variant identity.
- Measure authentication latency and area against NOC-2.

**Acceptance:** zero NI delivery and zero slot retirement on every rejected packet, no deadlock, every control effective.

### NOC-4: N-10 trusted authorization
- **Connect** `noc_fault_status` to the subsystem (it is currently unconnected).
- Test `noc_attest_gate` **integrated**, at every untrusted boundary:
  - blocked after reset;
  - grant only from RoT (index 4) with status 1 and a whitelist match;
  - a worker grant with a valid MAC is rejected;
  - revoke, failure, timeout and reset-during-challenge all block;
  - trusted clear and retry work;
  - memory responses are gated too.
- Mutants (each caught): gate bypass, issuer check removed, revocation ignored.

**Acceptance:** no protected commit without a valid grant; fault source, operation, reason and epoch are observable.

### NOC-5: N-11 / N-12 / N-13, three separate sub-gates
- **N-11:** consume the PQ-4 SEC matrix evidence when the identity matches.
- **N-12:** clean final regression of every gate on one release identity.
- **N-13:** an isolated batch synth+impl of `pq_noc_subsystem` (mesh + 6 NIs + L2 + endpoint + verifier + gates) at 20 ns, using explicit sources and no incremental DCP. Requirements: WNS/WHS/WPWS ≥ 0, TNS/THS = 0, 0 route/DRC errors, no unexplained unconstrained paths. Report LUT, FF, LUTRAM, BRAM and DSP, both secure and insecure profiles.
- Produce `releases/DUAL_LANE_10_<id>/` with a manifest.

**Out of scope:** N-14 SoC integration (Lane 2) and the bitstream.

---

## 4. PQ-Attest lane: next five steps

### 4.0 Blueprint: verifying the teammate ZIP as PQ authority (all of it goes in PQ-1)

| # | Step | Output | Pass rule |
|---|---|---|---|
| V1 | **Pin.** Hash the ZIP; it must equal `047bb5a9…`. Record the hashes of `PQ_Attest (2).zip` (`62abec08…`) and `(3).zip` (`538cc776…`) as historical inputs only. | `docs/decisions/PYTHON_REFERENCE_BASELINE.md` §1 | Hash matches; otherwise `BLOCKED_ZIP_MISMATCH` |
| V2 | **Extract once, read-only** to `software/pq_attest_final/` (keep the internal `PQ_Attest/` root). Ignore `__pycache__`/`.pyc` and the RTL inside the ZIP. Record each `.py` SHA-256 (e.g. `kmac128_ref.py ac8076e6…`, `measurement_ref.py a56b3041…`, `attestation_ref.py c07e19d3…`, `attestation_protocol.py 4faed19d…`, `run_all_tests.py a199d2f2…`). | Hash table in `dual_lane_config.json` → `python_reference` | Hashes match the ZIP members |
| V3 | **Reproduce the teammate's own suite** on Windows Python 3.13. Run it in a disposable copy (`kdf_vectors.py` writes files), through a bounded wrapper with a 120 s timeout per suite. **Parse the raw output**, because exit code 0 alone is insufficient: `measurement_ref.py` can print FAIL and still exit 0. | `reports/.../python_ref/suite.json` | 8/8 suites; the parsed per-test results show zero FAIL lines |
| V4 | **External KATs.** Check the ZIP's `kmac128` against the NIST SP 800-185 KMAC128 samples 1–3, and its SHA3-256 against `hashlib` at lengths 0, 3, 135, 136, 137, 271, 272, 273 and 512. | `python_kats.json` | All match. A KAT failure stops PQ-1; it is never "fixed" in the reference. |
| V5 | **Repo-copy reconciliation.** Diff the repo `software/kmac128_ref.py` (`73d9b064`) against the ZIP copy. Compare outputs on the same KATs plus 24 cross cases (L = 16/32; message lengths 0/4/167/168/169/400; empty and `PQ-ATTEST-AUTH` customization). | `PYTHON_REFERENCE_BASELINE.md` §2 | Identical outputs. Otherwise record a discrepancy; the ZIP wins. |
| V6 | **Contract extraction.** Read the real APIs: `derive_tile_key(root, tile, epoch, context, key_bytes)`, `measure_tile(tile, config, imem)`, `generate_attestation_tag(...)`, `tile_respond(...)`, `verifier_check(...)`. Write the Python↔RTL matrix: primitive, output length, customization, encoding, field widths (tile 7, epoch 10, nonce 16, measurement 32, tag 32), byte order (byte i at `[i*8 +: 8]`), and the 97-byte packing. | `docs/verification/PYTHON_RTL_CONTRACT_MATRIX.md` | Every row is marked MATCH, ADAPTER (lossless, documented) or MISMATCH (with exact bytes) |
| V7 | **Adapter.** Rewrite `scripts/s8_golden.py`, `full_chain_golden.py` and `l2_golden.py` as **thin adapters** that import `software/pq_attest_final/PQ_Attest/software/*`. Allowed: byte↔SV-word packing, `key_bytes=32` per K-1, and the hardware-profile validation (nonce exactly 16 bytes, config/imem ≤ 64, context ≤ 14). Not allowed: changing the algorithm, customization, truncation or lengths. | `vectors/*.json/.svh` regenerated, with hashes | A diff against the previous vectors is explained line by line |
| V8 | **Profile split.** Job `py_teammate_examples`: reproduce the teammate's 16-byte example outputs **unchanged** (e.g. root `bytes(range(32))`, `TILE_01`, `EPOCH_0001`, `PQ-ATTEST-KDF`: key16 `9c699e78…27c`, key32 `f3d22e09…6989`). Job `py_rtl_profile_32`: the system vectors. | Two jobs | Both PASS; never mixed |
| V9 | **RTL comparison.** `tb_stg_8_golden` compares the full 776-bit response, plus the key, measurement and tag checkpoints, against the V7 vectors. Mandatory cases: the 8 Stage-7 vectors; context length 0 and 14; config/imem 0/0, 64/64, 64/0, 0/64; non-trivial patterns; distinct consecutive requests; invalid lengths; start while busy; reset in each phase. | XSim log + result JSON | Bit-exact on all cases; 95/0 (frozen count) |
| V10 | **System-policy layer** (outside the immutable reference). The ZIP's verifier is stateless and has no whitelist, so the RoT model adds outstanding-challenge retirement, duplicate rejection and a digest whitelist. A test must show: the teammate verifier gives ACCEPT, the system policy gives REJECT for a duplicate or unapproved measurement, and **both** verdicts are recorded. | `PYTHON_RTL_COMPATIBILITY`, `POLICY_LAYER` records | Both behaviours demonstrated |

Limitations to carry into every report: **L-1** split ambiguity (K-3); **L-2** a stateless reference verifier; **L-3** deterministic demo keys and nonces; **L-4** a full 136-byte SHA3 final block and `is_final` stability are outside the promised API (135-byte cap).

### PQ-1: S-8 freeze + teammate-reference oracle
- Run V1–V10.
- Run 7 controller mutants (lost measurement, lost tag, key length, wrong transcript, field order, stale nonce, wrong key) plus a control after them. Each must be killed by its **targeted** check.
- Publish the S-8 part of M-F1 rev 6 (shared with NOC-3).
- Requalify the variant `NOC_PKG` (224-bit challenge) through `post_format_compat`. That means rerunning every job that compiles `NOC_PKG`.

**Acceptance:** V1–V10 pass; 95/0 bit-exact; 7/7 targeted kills; rev 6 committed; compatibility jobs pass.

### PQ-2: NoC attestation endpoint (historical S-8.2/C2; working label PQ-2)
- Qualify `rtl/dual_lane/pq_attest_endpoint.sv` per `S8-2` (corrected to OD-2).
- Decide the zero-byte `pq_attest_request.sv`/`pq_attest_response.sv`: delete them, recording that in the register, since the endpoint replaces them.
- Mark `pq_attest_protocol_pkg.sv` as orphaned and excluded.
- Behaviour:
  - reply-to latched at HEAD;
  - crypto starts only after a complete, valid 7-word challenge;
  - `rx_ready=1` always (with an SVA);
  - a busy endpoint drains and counts;
  - TX words stay stable under backpressure;
  - reset cancels everything.
- Unit testbench plus system testbench (RoT challenge, SPOOF stalling).
- Mutants: tag word swap, epoch/nonce offset, wrong reply-to, `rx_ready` stall. Each must produce its targeted observation.

**Acceptance:** all PQ028-matrix cases pass and 4/4 targeted kills. Functional only; secure acceptance comes after NOC-3.

### PQ-3: D4 crypto OOC
- `scripts/d4_crypto_ooc.tcl` as an isolated batch child job, never in the GUI project.
- Five tops: `pq_kdf`, `pq_measurement`, `pq_attestation_tag`, `pq_attestation_controller`, `pq_attest_endpoint`.
- 20 ns with documented I/O delays, child engines kept (no trim).
- Per top: LUT/FF/LUTRAM/BRAM/DSP, latches, WNS/WHS, unconstrained paths, methodology.
- Measure attestation latency in cycles.

**Acceptance:** all five complete with provenance. A timing failure = FAIL plus a trade-off note (pipelining or a shared engine). No silent clock change.

### PQ-4: S-9 / N-11 shared security matrix (SEC-1 to SEC-4, new 2026-10-08 contract, **not** historical E1–E4)

| ID | Attack | Expected | Targeted control |
|---|---|---|---|
| SEC-1 | genuine tile | grant; authorized data works | corrupt response → rejected |
| SEC-2 | wrong key / identity / measurement, forged response from SPOOF | no grant, no commit | disable that specific check → unauthorized grant |
| SEC-3 | L2 replay and attestation replay (separate cases), stale epoch, nonce substitution, reset replay | rejected for the stated reason | disable freshness → replay succeeds |
| SEC-4 | runtime substitution (changed config/imem) at re-attestation | revoked and isolated | disable whitelist or enforcement → substituted state is granted |

Plus: wrong grant issuer, error response, timeout, status-clear misuse, truncated challenge, concurrent SPOOF traffic. Use the actual NOC-3 and NOC-4 modules, not testbench stand-ins.

**Acceptance:** every attack is rejected with zero unauthorized commits, and every control makes its attack observable.

### PQ-5: S-10 offline full chain
- Run `tb_pq_full_chain` in **non-demo** mode, judged by the V7 adapter oracle.
- Sequence: challenge → authenticated transport → endpoint → KDF/measure/tag → response → RoT verifies (teammate verifier **and** policy layer) → grant → authorized write → revoke/substitution → blocked.
- Also: repeated distinct transactions, backpressure, reset at each boundary, coexisting SPOOF, retry/timeout.
- Report the nonce source as "deterministic demo issuer". There is **no** TRNG claim, because S-4 is replay only.

**Acceptance:** fresh PASS with all dependencies accepted on compatible identities; `HARDWARE_VALIDATED=NO`.

---

## 5. Increments and order

| Increment | Contents | Gate Kalash runs |
|---|---|---|
| **I-1** | NOC-1 steps 1–7, plus PQ-1 V1–V6 (Python only; can run in parallel) | `run_dual_lane_10.tcl`: NOC-1 PASS; `python_ref` PASS |
| I-2 | PQ-1 V7–V10, controller mutants, M-F1 rev 6, `post_format_compat` | PQ-1 PASS |
| I-3 | NOC-2 ∥ PQ-2 | NOC-2, PQ-2 |
| I-4 | PQ-3 | PQ-3 |
| I-5 | NOC-3 | NOC-3 |
| I-6 | NOC-4 | NOC-4 |
| I-7 | PQ-4 → PQ-5 | PQ-4, PQ-5 |
| I-8 | NOC-5 (N-11, N-12, N-13) and release | NOC-5 |

A dependent increment never starts before its gate passes. Independent audit and documentation work may continue in parallel.

**Final report fields:**

```
NOC_PACKAGES_ACCEPTED=n/5
PQ_PACKAGES_ACCEPTED=n/5
DUAL_LANE_STATUS=…
SOURCE_IDENTITY=…
PYTHON_REFERENCE_ZIP=Pq_Attest_final.zip
PYTHON_REFERENCE_SHA256=047bb5a9…
TILE_KEY_BYTES=32
PYTHON_RTL_COMPATIBILITY=…
EVIDENCE_DIR=…
HARDWARE_VALIDATED=NO
SOC_INTEGRATION_COMPLETE=NO
```

## 6. Immediate task for Codex

Start **I-1**. The first file-system actions are K-4 (a) and (b) and moving the stray files, each with a hash record. Then the duplicate-name preflight and its self-test. Then PQ-1 V1–V3.

Stop after I-1 and report. Kalash will then run:

```tcl
source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/run_dual_lane_10.tcl
```
