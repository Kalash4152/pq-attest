# Claude Code resume pack: NOC_PQATTEST, picking up after Codex I-1

**Prepared:** 2026-10-19 for Kalash. It is based on a read-only review of the live tree. I changed nothing.

**What is in this file:**

- **Part A** is the review verdict: what Codex finished and what is wrong.
- **Part B** is `CLAUDE.md`. Copy it to the repo root, so Claude Code loads it every session.
- **Part C** is the kickoff prompt. Paste it as the first message.
- **Part D** is the parallel (multitask) setup.
- **Part E** lists the remaining tasks per package: five NoC and five PQ.

---

## A. Review of the Codex state (verified live 2026-10-19)

**Facts checked in the live folder:**

| Item | State |
|---|---|
| Branch / HEAD | `noc/credit-integration` @ `a896c89` (I-1 closeout). Codex commits: `8a82ab8`, `858c95d`, `2fd1138`, `74c13c0`, `a896c89`. |
| Latest run | `reports/dual_lane_10_20261008_235701_d7b8ee31`: **NOC-1 PASS_FRESH**. All nine other packages are BLOCKED because each is "outside active I-1". |
| I-1 evidence | 24/24 jobs accepted (14 fresh, 10 reused). Includes `n81_nitb` 161/0; N-6 mutants A, B (scoped T4/T5) and C killed, with 2×126/0 controls; D7 pipe1 1756/0, pipe0 1762/0, M8 47/0, N-6 126/0, TB1 pass; NI OOC WNS +4.464; mesh WNS +0.202 / WHS +0.047; Python reference audit 8/8 suites, KATs, 24/24 repo/ZIP comparisons. |
| Protected RTL | 48 hashes reported unchanged (`I1_CLOSEOUT_VERIFY_20261009.json`). |
| Teammate ZIP | Pinned and extracted to `software/pq_attest_final/` (tracked). |
| Decision register | `docs/DECISION_REGISTER.md` records K-1 to K-6 and OD-1 to OD-6 with their provenance. |

**Assessment:** I-1 is genuinely closed. The evidence trail is the strongest the project has had. Seven findings to act on:

| # | Finding | Severity | Action |
|---|---|---|---|
| F1 | **Accepted evidence was built from untracked or uncommitted sources:**<br>• modified (not committed): `tb_noc_n81.sv`, `tb_noc_mesh.sv`<br>• untracked: all of `rtl/dual_lane/`, `sim/dual_lane/`, `vectors/`, `scripts/s8_golden.py`, `full_chain_golden.py`, `l2_golden.py`, `perf_*`, the four new TBs, and seven decision documents under `docs/decisions/`<br>Hashes are recorded, but nothing reproducible exists in git. | High | First task: commit them in logical groups, after checking that their hashes equal the ones recorded in `status.json`. |
| F2 | **Mutant B was weakened**: credit loss is limited to T4/T5. The original full-run B timed out, which counts as INVALID, not as a kill. | Medium (documented) | Keep scoped B as a separately named mutant (that is legitimate). Record in STATUS that full-run B produced no kill. |
| F3 | **"Controlled diagnostics" admit specific assertion errors** during reviewed negative-stimulus phases (TB1, mutants). This is a correct mechanism, but it is a masking risk. | Medium | Every whitelist entry needs the exact phase, instance, file:line and expected count. A self-test must prove that an unlisted assertion still fails the job. Codex reports 61 self-tests; re-run them before every increment. |
| F4 | **`scripts/s8_golden.py` still imports the repo `kmac128_ref`**, not the ZIP. This is plan item V7 and is pending in I-2. | Known | I-2 Track A. |
| F5 | **Foreign OV5642 files are back at the root**: `run_m9_2.py`, `selfcheck_m9_2.py`, `sim/tb_m9_s308.sv` (dated 10-02), plus the 85 MB `scripts.zip` snapshot. | Low | Move them into `_recovery_backup/foreign/` with hashes. Never add them to a source list. |
| F6 | **The registry only defines the `I-1` increment.** The jobs for I-2 to I-8 exist in `jobs` but have not been grouped into increments. | Medium | Each track adds its own increment block. A single integrator owns the edits (Part D). |
| F7 | **M-F1 rev 6 has not been written.** Several prepared variants (`rtl/dual_lane/*`) already depend on rev-6 semantics. | High | I-2 Track B writes rev 6 **before** any dependent gate runs. |

---

## B. `CLAUDE.md` (save as `C:\vivado_verilog_proj\NOC_PQATTEST\CLAUDE.md`)

```markdown
# NOC_PQATTEST — rules for Claude Code

Owner: Kalash Bheda. Address him as Kalash. Be concise and conclusion-first. Open every reply
with a one-line pre-output check (what was read live).

## Ground truth
- Repo C:\vivado_verilog_proj\NOC_PQATTEST, branch noc/credit-integration.
- Tools: Vivado/XSim 2024.1 at C:/xilinx_vivado/Vivado/2024.1 (reference simulator),
  Python C:/Users/kalas/AppData/Local/Programs/Python/Python313/python.exe, PowerShell, git.
  No Verilator on Windows. No board/hardware access.
- Part xc7a100tcsg324-1, single clock, 20 ns. No clock, pin or CDC changes.
- Authoritative docs: docs/CODEX_INSTRUCTIONS_R4_FINAL_2026-10-08.md (plan),
  docs/DECISION_REGISTER.md, docs/decisions/*.md, docs/STATUS.md, reports/I1_COMPLETION_20261009.md.
- Teammate Python reference (governs PQ semantics): Pq_Attest_final.zip
  SHA-256 047bb5a981050f11a572a60e850f7c7511ff5d636f7903c6a8d239891003c6a0,
  extracted read-only at software/pq_attest_final/. TILE_KEY_BYTES=32 is the system profile.

## Never
- Write the protected files: sources_1/new/{noc_router.sv, noc_network_interface.sv, NOC_PKG.sv,
  pqattest_stg7.sv, pq_attest_protocol.sv, allocator.sv, noc_mesh_3x2.sv, SHA3_*.sv, pq_kdf.sv,
  pq_measurement.sv}, sim_1/new/{tb_ni_n81.sv, tb_noc_n81.sv}, software/pq_attest_final/**, the ZIP.
  Secure changes go only in rtl/dual_lane/ variants with explicit source lists.
- Put a variant and its production original in one source list (duplicate-name preflight).
- Change an expected count, weaken a check, edit a reference vector, or count a timeout as a kill/pass.
- Claim a simulation, synthesis or timing result that was not run. Separate: implemented /
  XSim-simulated / reference-checked / mutation-tested. Formal and hardware are always NO.
- git reset --hard, git clean, force-push, or restore from zip snapshots.
- Kill a running Vivado/XSim job you did not start.

## Always
- Evidence only through: python scripts/dual_lane.py run --select <increment>  (or the Tcl
  launcher scripts/run_dual_lane_10.tcl). States: PASS_FRESH or identity-matched PASS_REUSED.
- Freeze each new job's expected counts in scripts/dual_lane_jobs.json BEFORE its first run.
- Wire/format changes only via a new M-F1 revision doc written BEFORE the dependent RTL.
- Run scripts/test_dual_lane.py (and test_controlled_diagnostics.py) before any registry change.
- Commit per logical group: git -c user.name="Kalash Bheda" -c user.email="kkalash.bheda@gmail.com"
  with the trailer lines the session provides.
- At most 2 concurrent Vivado/XSim processes (16 GB RAM). Synthesis/implementation jobs run alone.
- Stop at every increment boundary and report the gate table; I-n+1 starts only after I-n PASS.
```

---

## C. Kickoff prompt (paste as the first Claude Code message)

```
Read CLAUDE.md, docs/CODEX_INSTRUCTIONS_R4_FINAL_2026-10-08.md, docs/DECISION_REGISTER.md,
reports/I1_COMPLETION_20261009.md and docs/CLAUDE_CODE_RESUME_2026-10-19.md (Parts A, D, E).
Verify live: git log -5, git status, protected hashes vs reports/I1_CLOSEOUT_VERIFY_20261009.json,
reports/dual_lane_latest.json. Report any drift before acting.

Then execute in order:
1. I-1.5 hygiene (Part E0): F1 commits after hash match, F5 foreign files to recovery, F2 STATUS note.
2. Start I-2 with the parallel tracks in Part D (A: Python adapters, B: M-F1 rev 6, C: controller
   mutants/golden registry, P: prep-only for I-3/I-4). Use subagents for A/B/C in separate git
   worktrees; you are the integrator and sole owner of dual_lane_jobs.json and STATUS.md.
3. When all I-2 tracks merge, run `python scripts/dual_lane.py run --select I-2`, report the gate
   table, and stop.
Do not start dependent acceptance early. Prep work for later increments is allowed only where
Part D marks it P (prepare-only, no evidence claimed).
```

---

## D. Multitask setup (how Claude Code finishes faster without corrupting evidence)

### D1. Topology

- **Main session = Integrator.** It alone edits `scripts/dual_lane_jobs.json`, `docs/STATUS.md` and `docs/DECISION_REGISTER.md`. It alone runs `dual_lane.py run`, and it merges the worktrees.
- **Subagents run one per track**, each in its own **git worktree**: Agent tool with `isolation: "worktree"`, or manually `git worktree add ..\NOC_wt_<track> -b wt/<track>`.
- Subagents may write only inside their track's file allowlist. They return a diff summary plus test output. They never run the launcher and never touch the registry.
- **Vivado concurrency:**
  - at most 2 XSim jobs at once;
  - synthesis/implementation runs alone;
  - Python and documentation tracks are unlimited.
- **Merge rule:** a worktree branch merges only when its own unit checks pass and `test_dual_lane.py` passes on the merged tree.

### D2. Track allocation per increment

`P` = prepare only: code, TBs and scripts with no evidence claims. Acceptance waits for the gate.

| Increment | Parallel tracks (subagents) | File allowlist | Gate (integrator runs) |
|---|---|---|---|
| **I-1.5** (now, ~1 h) | Integrator only | git, `_recovery_backup/`, STATUS | commits clean; hashes match |
| **I-2 (PQ-1)** | **A** Python adapters V7–V8 · **B** M-F1 rev 6 (doc only) · **C** golden/mutant job definitions + `tb_stg_8_golden` review · **P1** NOC-2 bench compile-fix (prep) · **P2** D4 scripts for the 4 existing crypto tops (prep) | A: `scripts/*_golden.py`, `vectors/` · B: `docs/decisions/M-F1-*` · C: `sim_1/new/tb_stg_8_golden.sv`, a job-def patch file · P1: `tb_noc_perf.sv`, `perf_*` · P2: `scripts/d4_crypto_ooc.tcl` | `--select I-2`: `s8_python`, `s8_golden` 95/0, 7 mutants + control, `post_format_compat` |
| **I-3 (NOC-2 ∥ PQ-2)** | **N2** perf matrix + N-7.5 runs · **Q2** endpoint unit/system TB + 4 mutants · **P3** L2 TB oracle wiring (prep) | N2: perf files · Q2: `pq_attest_endpoint.sv` variant, endpoint TBs · P3: `tb_noc_l2_auth.sv`, `l2_golden.py` | `--select I-3` (XSim ≤ 2 parallel) |
| **I-4 (PQ-3)** | Integrator, synthesis serial | `d4_crypto_ooc.tcl` | 5 OOC tops |
| **I-5 (NOC-3)** | **N3a** `noc_l2_auth` fixes · **N3b** 4 bypass controls + attack cases | `rtl/dual_lane/noc_l2_auth.sv`, L2 TB | `--select I-5` + N-8.1 rerun on variant |
| **I-6 (NOC-4)** | **N4a** connect `noc_fault_status` · **N4b** gate TB + 3 mutants | `rtl/dual_lane/noc_attest_gate.sv`, `noc_fault_status.sv`, `pq_noc_subsystem.sv` | `--select I-6` |
| **I-7 (PQ-4 → PQ-5)** | **S1** SEC-1/2 · **S2** SEC-3/4 (+ extra cases) · then full chain non-demo | `tb_pq_security.sv`, `tb_pq_full_chain.sv` | `--select I-7` |
| **I-8 (NOC-5)** | Integrator: N-12 regression (XSim ≤ 2), then N-13 impl alone | release folder | N-11/N-12/N-13 |

Prep tracks P1–P3 are what make this faster. They overlap the next increment's coding with the current gate, while acceptance order stays strict.

### D3. Subagent prompt template

```
Track <X> of increment <I-n> in worktree ..\NOC_wt_<x> (branch wt/<x>). Read CLAUDE.md first.
Allowed files: <allowlist>. Goal: <task from Part E>. Acceptance for your handoff: <unit check>.
Do not run dual_lane.py run, do not edit dual_lane_jobs.json/STATUS.md, do not touch protected files.
Return: changed files with sha256, the exact commands you ran with outputs, and open questions.
```

---

## E. Remaining work: done vs to do

### E0. I-1.5 hygiene (do first)

1. For each untracked or modified file listed in F1, compare its sha256 with the identity recorded in `reports/dual_lane_10_20261008_235701_d7b8ee31/status.json`. If they match, commit:
   - TB fixes (`tb_noc_n81`, `tb_noc_mesh` N7_PIPE0);
   - `rtl/dual_lane` + `variant_provenance`;
   - `sim/dual_lane`;
   - oracles + `vectors/`;
   - the four new TBs;
   - the seven decision documents;
   - the evidence logs/reports (`git add -f`).
   If a hash does not match, stop and report the file.
2. F5: move `run_m9_2.py`, `selfcheck_m9_2.py`, `sim/tb_m9_s308.sv` and `scripts.zip` to `_recovery_backup/foreign/`, recording their hashes.
3. STATUS rev 18: NOC-1 accepted; scoped mutant B and the full-run B history; limitations L-1 to L-4.

### NoC lane

| Pkg | Already done | To finish |
|---|---|---|
| **NOC-1** | ✅ ACCEPTED (24/24) | Only the E0 commits |
| **NOC-2** N-8 + N-7.5 | `tb_noc_perf.sv`, `perf_bench_body.sv.inc`, `prepare_perf_bench.py`, `perf_report.py` written; plan `N-8-performance-plan.md` (OD-6); jobs `perf_m0/m1` (84 checks) and `perf_matrix` registered | Compile-check (P1). Freeze per-point accounting contracts. Run 56 points + 3 controls (corrupt / drop / stall) + saturated-VC2, reset/drain and second-challenge liveness. Curves. Verilator cross-check = BLOCKED (not installed). |
| **NOC-3** N-9 | `rtl/dual_lane/noc_l2_auth.sv`, NI preview variant, `tb_noc_l2_auth.sv` (unfinished, unregistered), `l2_golden.py`, `vectors/l2_golden.*`, design doc | M-F1 rev 6 (I-2B) first. Repoint `l2_golden` KMAC to the ZIP. Register and finish the TB. Attack cases (tamper ×3, wrong source/key, replay, reset/old-boot replay, wrap, truncated/overlong, overload). 4 bypass controls. Rerun N-8.1 on the variant. Latency/area against NOC-2. |
| **NOC-4** N-10 | `noc_attest_gate.sv`, `noc_fault_status.sv` (**unconnected**), `pq_rot_verifier.sv`, `pq_noc_subsystem.sv`; demo full chain showed grant/revoke | Connect fault/status. Integrated gate tests: reset-block, RoT-only grant + status 1 + whitelist, worker-MAC grant rejected, revoke/timeout/failure/reset-during-challenge, trusted clear, response gating. 3 mutants (bypass, issuer, revoke). |
| **NOC-5** N-11/12/13 | Mesh-only timing passes; NI OOC passes | N-11 consumes the PQ-4 evidence. N-12 full fresh regression on one identity. N-13 isolated synth+impl of `pq_noc_subsystem` at 20 ns (secure and insecure profiles), full report set, release folder. |

### PQ lane

| Pkg | Already done | To finish |
|---|---|---|
| **PQ-1** S-8 + teammate oracle | V1–V6 done (pin, extract, 8/8 suites, KATs, 24 comparisons, `PYTHON_REFERENCE_BASELINE.md`); internal Python oracle matched the 6/6/8 legacy vectors; earlier raw 95/0 golden run exists but is INVALID (config changed mid-run) | **V7:** rewrite `s8_golden.py` / `full_chain_golden.py` / `l2_golden.py` as thin adapters importing `software/pq_attest_final/PQ_Attest/software/*`. **V8:** jobs `py_teammate_examples` (16 B, unchanged) and `py_rtl_profile_32`. **V9:** `s8_golden` 95/0 bit-exact + 7 mutants + control on one identity. **V10:** policy-layer verdicts. M-F1 rev 6 (with Track B). `post_format_compat` rerun of every job compiling the 224-bit `NOC_PKG` variant. |
| **PQ-2** endpoint | `rtl/dual_lane/pq_attest_endpoint.sv` (code-10-only errors, **unqualified**), `S8-2` doc | Align errors to OD-2 (2/3/5/10). Delete or retire the zero-byte request/response files and `pq_attest_protocol_pkg.sv` (register entry). Unit TB + system TB (RoT, SPOOF). Full PQ028 matrix. 4 mutants (tag swap, offset, reply-to, `rx_ready` stall). `rx_ready=1` SVA. |
| **PQ-3** D4 | `scripts/d4_crypto_ooc.tcl` written; jobs `ooc_pq_*` and `endpoint_ooc` registered | Run 4 crypto tops (prep in I-2 P2, run in I-4) + endpoint after PQ-2. Keep-hierarchy checks, per-top utilization, WNS/WHS, latency cycles. FAIL plus a trade-off note if timing misses. |
| **PQ-4** S-9 / N-11 | Job renamed `security_sec_1_4` ✅ | Write `tb_pq_security.sv` with SEC-1 to SEC-4 + extra cases (wrong issuer, error response, timeout, clear misuse, truncated challenge, concurrent SPOOF). One targeted bypass control per attack. Real NOC-3/NOC-4 modules. |
| **PQ-5** S-10 | `tb_pq_full_chain.sv` 16/0 at `DEMO=1` (functional only) | Non-demo run with the ZIP-adapter oracle; repeated transactions, backpressure, reset at each boundary, SPOOF, retry/timeout; latency breakdown. Nonce labelled as a deterministic demo issuer. |

**Final report fields per increment** (unchanged from R4): `NOC_PACKAGES_ACCEPTED`, `PQ_PACKAGES_ACCEPTED`, `DUAL_LANE_STATUS`, `SOURCE_IDENTITY`, `PYTHON_REFERENCE_SHA256`, `TILE_KEY_BYTES=32`, `PYTHON_RTL_COMPATIBILITY`, `EVIDENCE_DIR`, `HARDWARE_VALIDATED=NO`, `SOC_INTEGRATION_COMPLETE=NO`.
