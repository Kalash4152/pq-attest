# Review of "Updated Codex instructions, Revision 3" (another agent), checked against the live tree

**Reviewer:** Claude, for Kalash. **Date:** 2026-10-08.

**What I checked:** the live Windows tree `C:\vivado_verilog_proj\NOC_PQATTEST`, read on 2026-10-08. I hashed files, grepped logs, read the decision documents and the dual-lane reports.

**What I did not do:** run Vivado, Python, or any build.

**Verdict:** Revision 3 is technically careful and mostly correct. It was, however, written **without access to the live tree** (its own §10 says so), and the live tree has moved on. Five of its premises are now wrong, and if Codex follows it literally it would either rebuild work that already exists or reuse evidence that is no longer valid. Apply the Revision 4 changes in §3 before handing it to Codex.

---

## 1. Claims I verified as correct

| Revision 3 claim | Live check |
|---|---|
| `Pq_Attest_final.zip` SHA-256 `047bb5a9…` | ✅ matches (repo root, untracked) |
| `PQ_Attest (2).zip` `62abec08…`, `(3).zip` `538cc776…` | ✅ match |
| Protected RTL hashes in Appendix A (router `6bd5d997`, NI `83f3b884`, `NOC_PKG` `e741a32d`, stg7 `c7962f81`, controller `07cae635`, `tb_noc_n81` `b5280370`, `tb_ni_n81` `a2c4f9b0`, `wp0_common.tcl` `2c77a882`) | ✅ all match the live tree |
| `software/kmac128_ref.py` `73d9b064…` (the repo copy) | ✅ matches, and **differs** from the ZIP copy (`ac8076e6…`) |
| N-8.1 session `wp0_n81_20261002_000837`: 11/11 passed, attempt 1 for every job | ✅ `summary.txt`, `SESSION=PASS` |
| NI OOC: WNS +4.656, WHS +0.263, in-to-out delay 5.309 ns | ✅ `reports/n81_ni_ooc_2026-10-02` |
| Mesh gate: WNS +0.202 / WHS +0.047, 0 failing out of 18,237, 0 DRC errors | ✅ `reports/n25_run3pe_2026-10-02/gate_summary.txt` (Performance_ExplorePostRoutePhysOpt, HEAD 1e3141c) |
| pipe0/pipe1: GuardChecks 111, ProtocolErrors 0, InjBlocked 0 | ✅ `logs/n7_pipe0_d7_2026-10-05.log`, `n7_pipe1_d7_2026-10-05.log` (both RESULT PASS) |
| 16-byte vs 32-byte key-profile mismatch (RTL uses 32; teammate examples use 16) | ✅ correct and important. The RTL sets `key_len_sel=2'b01`; the teammate demo calls `derive_tile_key(...,16)` |
| Measurement has no length boundary (config‖imem split ambiguity) | ✅ correct. This matches an item that was open historically ("decide length-prefix ambiguity", S-6) |
| The verifier is stateless and has no allowlist | ✅ consistent with `attestation_protocol.verifier_check` |
| SHA3 debts: `is_final` is read live, and a full 136-byte final block gets no extra padding | ✅ consistent with the project history |
| An integrated mesh + NI timing run is not a 10f prerequisite (N-8.1 places it in N-14) | ✅ correct reading of the N-8.1 spec |
| Two different meanings of "S8-2" (MAC format vs endpoint) | ✅ real ambiguity; a `STAGE_MAP.md` is a good fix |

The software results in Appendix B (8 suites, 11/11, 16/16 and so on) were run by that agent under Python 3.12. I did **not** rerun them. Kalash's Windows machine has Python 3.13 (`dual_lane_config.json`), so they still need to be reproduced there.

---

## 2. Errors and omissions, each with live evidence

| # | Revision 3 says | Live reality | Required change |
|---|---|---|---|
| **E1** | `run_dual_lane_10.tcl` is "TO BE CREATED BY CODEX" (§1, §7.1) | It **already exists** and has been run three times today. The working tree contains `scripts/run_dual_lane_10.tcl`, `dual_lane.py`, `dual_lane_common.tcl`, `dual_lane_jobs.json`, `dual_lane_verify.py`, `test_dual_lane.py`, `prepare_*.py`, `automation/dual_lane_payload/`, `tb_noc_perf.sv`, `tb_noc_l2_auth.sv`, `tb_stg_8_golden.sv` and `tb_pq_full_chain.sv`, plus seven decision documents. Latest run: `reports/dual_lane_10_20261008_150300_5231be0b` = **FAIL** (NOC-1). | Tell Codex to **audit and extend** the existing framework, not write a parallel one. Two launchers would mean two evidence trees that contradict each other. |
| **E2** | "Read docs/STATUS.md, HANDOFF_2026-09-26, M-F1, N-8.1, 7c…" (§2.1) | **All six are deleted in the working tree** (`git status`: D). They exist only at HEAD. | First action: `git checkout HEAD -- docs/` (non-destructive; restores only the deleted files). Codex must read the frozen contracts from the restored files, not from memory. |
| **E3** | Not mentioned | `sim_1/new/ni_tb.sv`, which should hold `tb_noc_ni` (161 checks), was **overwritten on 2026-10-02 08:07** with a copy of the D7 mesh testbench (`module tb_noc_mesh_n7`). That module is also defined in `sources_1/new/tb_noc_mesh.sv`, so the project has a **duplicate module definition**. This is why the dual-lane runner marks `n81_nitb` INVALID. | Add to NOC-1 step 1: restore `ni_tb.sv` from HEAD and keep the overwritten copy in `_recovery_backup/`. Add a preflight rule: **no module name may be defined twice across all enabled sources**. |
| **E4** | Reuse WP-0 N-6 mutation evidence "if identity matches" (§2.2, NOC-1 step 2) | It does **not** match. `wp0_common.tcl` was edited after session `155153` (my define injection and crash-retry change, 1 Oct). The existing runner correctly marks all five N-6 mutation jobs INVALID. | State plainly: **rerun** `n6_mutation.tcl`. It is cheap and does not touch the live router. |
| **E5** | "Kalash retained ownership of OD-1…; otherwise dependent gates BLOCKED" (§3) | `docs/decisions/dual_lane_config.json` records OD-1 to OD-6 as **ACCEPTED** by Kalash on 2026-10-08, with the instruction quoted. The `DUAL_LANE_10_CONTRACT.md`, `S8-1`, `S8-2`, `N-9`, `N-10`, `N-7.5` and `N-8` documents exist. | Codex must take those live acceptances as the starting point and verify their provenance. Kalash should confirm them once in writing. If they are accepted, OD-1 dependent gates are **not** blocked; the next step is **writing M-F1 rev 6**, which no document has done yet. |
| **E6** | PQ-1 must follow `Pq_Attest_final.zip` (§1.2), and must not substitute a self-authored model | The existing `scripts/s8_golden.py` imports **`software/kmac128_ref.py`** (the repo copy `73d9b064`), **not** the ZIP. The ZIP is pinned in neither `dual_lane_config.json` nor `dual_lane_jobs.json`. As built, the PQ-1 oracle **violates** Revision 3's own mandatory contract. | Name this explicitly: re-point `s8_golden.py` to an extracted, hash-pinned `PQ_Attest/software/` (ZIP `kmac128_ref.py`, `measurement_ref.py`, `attestation_ref.py`). Add the ZIP SHA and per-module hashes to the job identity. Keep the repo `kmac128_ref.py` only as a supplementary KAT. |
| **E7** | PQ-4 "recover accepted E1–E4 definitions" | **They do not exist historically.** In the project record, "E4" means *Engineer 4*, the verification/automation workstream (`handoff-corrections-2026-09-22`). The live job name `security_e1_e4` was coined today. | Rename the matrix to **SEC-1 to SEC-4 (new contract, 2026-10-08)**. Remove "recover", so that no agent later claims it was approved historically. |
| **E8** | Error encoding is an open proposal (§3) | Two **conflicting** live documents: OD-2 (accepted) uses per-cause status 2–10 with sixteen zero words; `S8-2-tile-attest-endpoint.md` says "All errors use sixteen zero words and status 10". | Add to the decision register: one status table, owned by PQ-1, written into rev 6. The endpoint document must cite it. |
| **E9** | One-retry crash path: "verify the exact first-attempt functional result first" (§2.2, §7.3) | In `wp0_common.tcl` the retry requires a nonzero exit, an `hs_err` file and `$finish` in the log. It then **judges the second attempt** and refuses a second crash. The dual-lane config has `retry_limit: 0`. | Revision 3's stricter rule (the first attempt must already show a complete PASS banner and config) is a sound improvement. Make it the rule for the shared helper, and keep `retry_limit=0` as the default. |
| **E10** | Not mentioned | `README.md` and `Run_M9_2.ps1` at the repo root belong to the **OV5642 camera project** (M9.2). | Move them out of the repo before any source glob or manifest step. |
| **E11** | Assumes Codex can implement all ten packages in one delivery | Codex has no Vivado. Every HDL gate needs Kalash's PC, and a single 10-package payload is very hard to review. | §3 R4-9: deliver in **gated increments**, each a small reviewable payload, with Kalash running the launcher in between. |
| **E12** | "Bind coordinates 0–5 to 56-bit tile IDs" (decision still open) | Already decided in OD-3: index `y*3+x` → ASCII `TILE_00`…`TILE_05` (7 bytes). | Reference it. Note that the teammate demo uses `TILE_01` as a string, which is consistent with that scheme. |
| **E13** | §2.4 notes the `.xpr` uses an incremental DCP and AutoDisabled sources | The `.xpr` is modified and uncommitted (+114 lines) and still lists `design_1.bd`, a stale block design. | Add to the preflight: hash the `.xpr`, and never alter it from a child job (the existing contract already requires this). |
| **E14** | Not mentioned | **No Lane-2 acknowledgement** of M-F1 rev 5 §5a exists. The `tb6_1.sv` L46 one-bit cast is still unresolved (Revision 3 covers this in NOC-1 step 6, which is good). | Record "Lane-2 ack = OPEN" in the decision register. It blocks N-14 only. |

---

## 3. Revision 4: changes to apply to the instruction set

Insert these as a new §0 ("Live-tree reconciliation, 2026-10-08"). They take precedence over §1–§7.

- **R4-1. Existing framework.** Inventory and reuse the existing dual-lane framework. Run `scripts/test_dual_lane.py` and `dual_lane.py preflight` first. Extend the registry; do not create a second launcher. Any rewrite of an existing helper must preserve its tested behaviour and be justified by a failing self-test.
- **R4-2. First three actions, all reversible, no RTL:**
  - (a) `git checkout HEAD -- docs/`
  - (b) restore `NOC_PQATTEST.srcs/sim_1/new/ni_tb.sv` from HEAD, keeping the overwritten copy in `_recovery_backup/ni_tb_OVERWRITTEN_d7mesh_2026-10-02.sv.txt`
  - (c) move the OV5642 `README.md` and `Run_M9_2.ps1` out of the repo.
  Record before and after hashes in `docs/BASELINE_CURRENT.md`.
- **R4-3. Duplicate-module preflight.** Parse every enabled `.sv` in each job's explicit source list. FAIL if any `module`/`package` name has more than one definition. The `ni_tb.sv` overwrite would have been caught.
- **R4-4. Evidence that must be rerun (not reused):** the WP-0 N-6 mutation (stale harness identity) and `n81_nitb` (overwritten testbench). Everything else in the N-8.1 matrix is `PASS_REUSED` from `20261002_000837`.
- **R4-5. Python authority wiring.**
  - Extract `Pq_Attest_final.zip` once to `software/pq_attest_final/PQ_Attest/` and mark it read-only. Its ZIP SHA and per-module SHAs go into `dual_lane_config.json` → `python_reference`.
  - `s8_golden.py`, `full_chain_golden.py` and `l2_golden.py` must import from that path.
  - CI check: the repo `software/kmac128_ref.py` and the ZIP copy must agree on every shared KAT. Record the diff in `PYTHON_REFERENCE_BASELINE.md`.
- **R4-6. Key profile decision (Kalash).** Default is `TILE_KEY_BYTES=32`, which matches the RTL and keeps S-7/S-8 evidence. Reproduce the teammate's 16-byte examples unchanged as a separate compatibility job. Only change the RTL if Kalash picks 16.
- **R4-7. Decisions.** Treat OD-1 to OD-6 as accepted, per `dual_lane_config.json`, pending one written confirmation from Kalash. The next blocking artefact is **M-F1 rev 6** (Q-C/R-B wire, single status table, N-9 freshness extension). Its compatibility requalification belongs to PQ-1 and NOC-3, as Revision 3 already says.
- **R4-8. Naming.** Rename E1–E4 to SEC-1…SEC-4 (new, 2026-10-08). Add to `STAGE_MAP.md`: "E4 (historical) = Engineer 4 workstream".
- **R4-9. Delivery increments.** Codex delivers one increment at a time. Kalash runs `source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/run_dual_lane_10.tcl` after each. No increment may start dependent work until the previous one's gate is PASS.

| Increment | Contents | Gate |
|---|---|---|
| I-1 | R4-2/R4-3, D7 five-job job definitions, STATUS rev 18, STAGE_MAP / DECISION_REGISTER | NOC-1 PASS |
| I-2 | R4-5 Python pinning, contract matrix, `s8_golden` re-pointed, 7 controller mutants, M-F1 rev 6 text | PQ-1 PASS |
| I-3 | NOC-2 performance and liveness; PQ-2 endpoint (parallel) | NOC-2, PQ-2 |
| I-4 | PQ-3 D4 OOC | PQ-3 |
| I-5 | NOC-3 N-9 | NOC-3 |
| I-6 | NOC-4 N-10 | NOC-4 |
| I-7 | PQ-4 SEC matrix; PQ-5 full chain | PQ-4, PQ-5 |
| I-8 | NOC-5 (N-11 / N-12 / N-13) and release | NOC-5 |

- **R4-10. Windows environment.** The reference interpreter is the Python 3.13 path in `dual_lane_config.json`. Reproduce the teammate's 8-suite run there through a bounded wrapper. Verilator is **not** installed on Windows (only in the Linux VM), so the NOC-2 cross-simulator check is `BLOCKED` unless Kalash installs Verilator. Do not mark it NOT_REQUIRED.

---

## 4. Kalash's decisions, smallest set first

1. **Confirm OD-1 to OD-6** as recorded in `dual_lane_config.json` (one line is enough). Then Codex may write M-F1 rev 6.
2. **Key profile:** 32 bytes (keeps RTL and evidence; recommended) or 16 bytes (matches the teammate examples; requires S-7/S-8 requalification).
3. **Status table:** OD-2 per-cause codes (recommended) or a single code 10.
4. **Measurement boundary:** keep it unencoded, as the reference does (recommended for this assignment; document it as a limitation), or add length prefixes (requires a protocol revision and re-vectoring).

## 5. Immediate next action

Give Codex Revision 3 **plus this review** as its §0 overrides, and scope the first delivery to **I-1 only**. Its acceptance is the existing launcher showing `NOC-1 = PASS` with `n81_nitb` 161/0 and a fresh WP-0 N-6 session (3/3 mutants killed, 2×126/0).
