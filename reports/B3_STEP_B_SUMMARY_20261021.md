# B-3 step b (M-F1 rev 7 R7.8.2, D): KDF + tag on one kmac128. PASS

Runs, both in one registry identity (no regeneration between them):
- `dual_lane_10_20261021_003514_99ef25e7`: 14 simulation/python jobs, all PASS_FRESH;
- `dual_lane_10_20261021_004017_a04c5c65`: 2 OOC jobs, each run alone, PASS_FRESH.

| Job | Expected | Observed |
|---|---|---|
| arbiter_model (C3, R7.6a) | ARBITER_MODEL: PASS | PASS (P ≤ 269, Q ≤ 792; A0 load-bearing) |
| kshare_variant | generated variants = generator(pinned originals) | PASS |
| ks_s8_golden | 95 / 0 | 95 / 0 |
| ks_s8_mut_* (7) + control_after | targeted kills, 95 / 0 | 7/7 killed, 95 / 0 |
| ks_pq_endpoint_unit / sys | 275 / 0, 37 / 0 | 275 / 0, 37 / 0 |
| ks_mut_wrong_owner (tag computed over the KDF bundle) | killed by s8_golden TAG checks | KILLED: 22 errors, first `[FAIL] G00_TAG`, normal end |
| Attestation latency (s8_golden `LATENCY` lines) | measure the delta | **0 cycles**: all 15 lines identical to the pre-D run 173746 (205–333 cycles) |
| ks_endpoint_ooc | latches 0, WNS/WHS ≥ 0, child check | **16,441 LUT / 15,621 FF**, WNS +10.284, WHS +0.190, child check PASS (15 rows) |
| ks_ooc_verifier (first synthesis of the verifier) | same gate | **7,742 LUT / 8,116 FF**, WNS +10.124, WHS +0.260, child check PASS (8 rows) |

**Area against the D estimate.**

| Block | Before D | After D (measured) | Change |
|---|---|---|---|
| Endpoint | 19,986 (measured) | 16,441 | −3,545 |
| Verifier | ≈ 11,378 (ESTIMATE; never synthesized) | 7,742 | −3,636 (against that estimate) |
| **Combined** | | | **≈ −7,181**, against the −8,884 estimate |

The shared kmac128 (MSG 65 bytes, plus the request mux) saves less than one whole MSG 40/65 KMAC each.

**Verifier timeout:** D adds 0 cycles of latency, so the worst P7 round trip stays ≈ 2,700 cycles (ESTIMATE). That is well inside `TIMEOUT_CYCLES = 100000` (`pq_rot_verifier.sv`:4).

**Updated full-chip arithmetic (ESTIMATE, D-AREA-1).**

| Item | LUT |
|---|---|
| Area-matrix row | 44,000 |
| D shortfall (−7,181 measured vs −8,884) | +1,703 |
| L2 glue above the trimmed assumption (T3/T4 pending) | ≈ +200 |
| **Total** | **≈ 45,900 (72 %)** |

That is still inside the 75 % gate (47,550), but with only ≈ 1.6 k margin. The measured gate is the step-d full-subsystem OOC.

## KDF/tag start exclusivity in pq_kmac_share (structural guarantee)

- **Controller** (`rtl/dual_lane/pq_attest_protocol.sv`):
  - `kdf_start` and `tag_start` are decoded in one `case (state_q)` (`:410-419`), so at most one is high in any cycle.
  - S_TAG_START is reached only via S_KDF_WAIT, which exits only on `kdf_done` (`:596-602`), then the measurement states (`:632-638`).
  - The KDF engine is therefore idle before the tag engine can request.
- **Verifier** (`rtl/dual_lane/pq_rot_verifier.sv`):
  - the starts are `vs==V_KSTART` / `vs==V_TSTART` of the single `vs` (`:66`, `:71`);
  - V_KWAIT exits only on `kd` (`:106`).
- **Checks:** `pq_kmac_share` checks both requesters in the same cycle and a start into a busy engine (procedural `$error`).
- **Mutant `ks_mut_tag_during_kdf`:** `tag_start` is also raised in S_KDF_WAIT. The tag engine then consumes the KDF's done/tag, which must be killed by s8_golden's TAG checks.

## Area pre-check for steps c and d (ESTIMATE, before any RTL; Kalash 00:55)

| Item | Basis | LUT (E) |
|---|---|---|
| SF-1 reserved peer slot + general slot on tiles 3, 4: 2 × 26 flits × 36 bits in LUTRAM (≈ 6 RAM32M each), HEAD/freshness captured to regs, replay by pointer | replaces the single FF quarantine (≈ 300 LUT of read muxes today) | +≈ 100 per tile → **+200** |
| Per-source rate-limit counters (6 × 6-bit) per L2 tile | | **+60** |
| Arbiter (2 classes, A0 pointers, aging counter) | the shared-engine muxes are already in the 7,018 engine estimate | **+60** |
| Ingress source check × 6 (constant compare + whole-packet drop FSM) | | **+150** |
| NI variant `CONTROL_ALLOWED = 0` × 4 (type decode, refuse/drain) | | **+20** |
| T3 (only 2 directed keys per L2 tile in P7: no 6:1 × 256 mux) | already inside the 1,127-LUT trimmed-glue assumption | 0 |
| **New items total** | | **≈ +490** |

**Full chip:** ≈ 45,900 + 490 ≈ **46,400 LUT (73.2 %)** ESTIMATE. That is ≤ 75 % (47,550), with ≈ 1.1 k margin, so this is not a stop.

**Fallbacks if step d lands above 75 %, ranked:**
1. A shared Keccak inside the L2 shared KMAC only. It removes nothing in P7, where there is one L2 KMAC, so in practice the first lever is a shared Keccak between the endpoint KMAC and its measurement SHA3, ≈ −2 k E.
2. Byte-serial KMAC padding (`kmac_128.sv:194`, `kmac_encode.sv:437-445`), ≈ −1 k per KMAC × 3 E.
3. Quarantine in BRAM instead of LUTRAM.

## Rerun with the exclusivity bench (run `dual_lane_10_20261021_010513_a054cee6`)

- The regression is again 14/14 PASS_FRESH, with counts unchanged.
- **ks_excl:** 42 / 0 PASS_FRESH. It made 40 attestations through the D controller with random inputs, with zero exclusivity violations.
- **ks_excl_mut_tag_during_kdf: killed by its targeted check, but the judge marks it INVALID.**
  - Log: `[FAIL] KSHARE_EXCLUSIVE violations=40`, CHECKS 42, ERRORS 1, RESULT FAIL, normal end.
  - Judge reason: "unexpected assertion/fatal/error/timeout". The mutant necessarily also fires the RTL's own procedural checks (`Error: pq_kmac_share: start while the shared kmac128 is busy`, `Error: pq_attestation_tag: kmac start asserted while kmac128 busy`). The judge (`scripts/dual_lane_verify.py`:129-131) rejects any `Error:` line, mutants included.
  - History: run `005757` shows the same mutant **survives** s8_golden (digests stay correct). That is why the separate bench exists.
- **Decision (council, owner asleep, 2026-10-21 01:22): option B.**
  - The result is recorded as above, and the judge is **not** changed autonomously.
  - Proposal for Kalash, option A: a per-mutant-job `expected_diag` list of exact full-line regexes.
    - The lines are stripped before the diagnostic scan.
    - Each listed line must occur at least once, as corroborating evidence.
    - Any other `Error:`/fatal/timeout stays INVALID; non-mutant jobs are unaffected.
    - Unit tests: an allowed line passes, an extra unknown error fails, a missing expected line fails.
  - Mechanism precedent: `adjudicate_n6_mutant`.
  - The I-4/B-gate status is unaffected: no downstream step depends on this job.

## Legacy known-answer benches, round 2 (supporting evidence only): final state

- **KMAC_TB INVALID:** two XSim launch stalls.
- **pq_attestation_tag_tb INVALID:** a launch stall, then an orphan deadlock.
  - The harness instance started at 18:09 with pre-`f72fefa` code.
  - Its timeout killed the xsim front-end (10384), but the kernel xsimk 8320 kept the inherited stdout pipe, so `communicate()` never returned.
  - My background wrapper task was stopped at 01:22. The harness python is gone; orphan xsimk 8320 still runs, and Kalash is killing it.
- Neither bench is rerun now.
- The **fixed harness** writes tool output to files, not pipes, so there is no pipe read to time out. It runs `taskkill /T /F`, then stops leftovers in the bench work dir.
- Its self-test now times the exact deadlock case: front-end killed, grandchild keeps the output handle, sweep disabled. The run returned in 5.7 s; the test fails above 60 s. `reports/i4_dsyn1/legacy/harness_selftest.txt` shows PASS.
- Untracked `sources_1/new/pq_attest_protocol_pkg.sv`, `pq_attest_request.sv` and `pq_attest_response.sv` appear in **no** job's `compiled_sources.json` and not in the registry. No evidence depends on them, and they stay untracked.
