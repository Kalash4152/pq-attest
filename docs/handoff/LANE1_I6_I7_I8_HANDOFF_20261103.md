# Lane 1 handoff: increments I-6, I-7 and I-8 (what to do, how, and what to deliver)

- **Owner:** Kalash Bheda. **Written:** 2026-11-03.
- **Repository:** `C:\vivado_verilog_proj\NOC_PQATTEST`, branch `noc/credit-integration`.
- **Purpose:** a self-contained work order for doing I-6, I-7 and I-8 by hand (with an AI assistant). Read it top to bottom
  once; then work increment by increment.
- **Authority if anything here disagrees with these documents** (in this order):
  1. `CLAUDE.md`;
  2. `docs/CODEX_INSTRUCTIONS_R4_FINAL_2026-10-08.md` (R4 plan, sec. 3-5: NOC-4, NOC-5, PQ-4, PQ-5);
  3. `docs/DECISION_REGISTER.md`;
  4. `docs/proposals/PLAN_NEXT10_ALL_LANES_20261030.md` (Lane 1 steps 1-9);
  5. the P7 contracts in `docs/decisions/`.

---

## 1. Where the project stands (start state)

| Item | Value |
|---|---|
| Milestones | **NOC 3 / 5, PQ 3 / 5** (I-5 PASS, 2026-10-29) |
| Last increment | **S3 PASS** (2026-11-02): area / timing rework, `reports/S3_GATE_20261102.md` |
| Design | M-F1 rev 7, "P7": 3x2 mesh, L2 MAC on control only, attestation on tiles 3 (endpoint) and 4 (RoT verifier), guarded ingress, plain tiles refused |
| Area | **37,398 LUT** routed (budget **47,550**), FF 32,810 |
| Timing | **WNS +0.126 ns**, WHS +0.015 ns at 20 ns. Met, but below the **+0.3 ns merge target**; every critical path is in the mesh routers (protected RTL) |
| Active increment | `S3` in both `scripts/dual_lane_jobs.json` and `docs/decisions/dual_lane_config.json` |
| Current P7 source list | the **S3** list: P7 sources with `rtl/dual_lane/pq_keccak_f1600.sv`, `pq_attest_protocol_s3.sv` and the `*_xp.sv` files (see `s3_list()` in `scripts/prepare_dual_lane.py`). **Every new I-6..I-8 job must start from this list, not the older P7 list.** |
| Validation | `HARDWARE_VALIDATED=NO`, `SOC_INTEGRATION_COMPLETE=NO`, `FORMAL_PROOF=NO` |

**Tile map** (tile = y * 3 + x):

| Tile | Name | Role |
|---|---|---|
| 0 | CPU0 | plain |
| 1 | CPU1 | plain |
| 2 | MEMORY | shared-memory stand-in |
| 3 | CRYPTO | attested: endpoint |
| 4 | ROT | verifier |
| 5 | SPOOF | untrusted injector |

**Control traffic:** only 4 -> 3 (CHALLENGE 12, GRANT 5, REVOKE 5 flits) and 3 -> 4 (RESPONSE 21).

---

## 2. Ground rules (from CLAUDE.md; breaking one invalidates the work)

**Never:**
- **Write a protected file:**
  - `NOC_PQATTEST.srcs/sources_1/new/{noc_router, noc_network_interface, NOC_PKG, pqattest_stg7, pq_attest_protocol, allocator, noc_mesh_3x2, SHA3_*, pq_kdf, pq_measurement}.sv`;
  - `sim_1/new/{tb_ni_n81, tb_noc_n81}.sv`;
  - `software/pq_attest_final/**`;
  - the ZIP.

  Changes go into `rtl/dual_lane/` **variants**, with explicit source lists.
- Put a variant and its production original in **one** source list.
- Change an expected count, weaken a check, edit a reference vector, or count a timeout as a pass or a kill.
- Claim a simulation, synthesis or timing result you did not run. Keep these separate: implemented / XSim-simulated /
  reference-checked / mutation-tested. Formal and hardware are always NO.
- Use `git reset --hard`, `git clean`, force-push, or restore from zip snapshots.
- Kill a Vivado/XSim job you did not start.

**Always:**
- **Evidence only comes from the registered harness:** `python scripts/dual_lane.py run --select <selection>`. Accepted
  states: PASS_FRESH, or identity-matched PASS_REUSED.
- **Freeze every new job's expected count before its first run.**
- **Wire / format changes** (any port, field or length on the network) need a new M-F1 revision document **before** the RTL.
- **Run `scripts/test_dual_lane.py` before any registry change, and check its exit code** (not a piped `tail`).
- **Commit per logical group:**
  `git -c user.name="Kalash Bheda" -c user.email="kkalash.bheda@gmail.com" commit ...`.
- **Evidence directories hold text only;** binaries stay on disk with their recorded hashes.
- **At most 2 concurrent Vivado/XSim processes;** synthesis / implementation jobs run alone (16 GB RAM).
- **At every increment boundary,** write the gate report and commit.

**HARD STOP (stop and decide before continuing) on:**
- any FAIL that needs a design or contract change;
- measured LUT > 47,550;
- a new security-scope question;
- any change to a signed bound, the wire format, the device, the clock or the budget;
- the **N-13 timing FAIL**.

---

## 3. How every increment is done (the mechanics)

The same eight moves for I-6, I-7 and I-8:

1. **Contract first.** Write `docs/decisions/<INC>_CONTRACT.md`:
   - what changes;
   - invariants;
   - the job list with **frozen counts**;
   - mutants and their oracle **and kill scope** (the scope must cover every failure the fault *causes*, not just the
     oracle line);
   - acceptance;
   - DECISION_REGISTER rows.
2. **RTL as variants.**
   - Edit `rtl/dual_lane/` originals that are not protected, or generate variants with a script, as in
     `scripts/prepare_s3.py` (exact-anchor edits plus a provenance file).
   - Keep module names; swap files in the source list.
3. **Benches.**
   - New benches in `NOC_PQATTEST.srcs/sim_1/new/`.
   - Each one prints `CHECKS : n`, `ERRORS : n`, `RESULT : PASS|FAIL`, ends with `$finish`, and has an internal
     timeout that prints `TB_TIMEOUT` (never a pass).
4. **Scratch check, not evidence.** Compile, elaborate and simulate once in a scratch Vivado project before registering;
   fix anything there.
5. **Register** in `scripts/prepare_dual_lane.py`:
   - add an increment block, with selection `i6` / `i7` / `i8`;
   - mutants get `mutant`, `oracle` and, where needed, `kill_scope`;
   - the mutant anchors go in `mutation()` in `scripts/dual_lane.py`, with the file mapping;
   - **then:**
     1. set `active_increment` in `docs/decisions/dual_lane_config.json`;
     2. run `python scripts/prepare_dual_lane.py` (this order matters: the harness refuses a payload built before the
        config switch);
     3. run `python scripts/test_dual_lane.py` (exit code 0);
     4. commit (registry, payload and config together).
6. **Run:**
   - `python scripts/dual_lane.py run --select <inc>`;
   - then any OOC / P&R job **alone**, with its own selection (for example `i6_pnr`).
   - A job may only depend on jobs in the **same selection** (a self-test enforces this).
7. **Gate report:** `reports/<INC>_GATE_<date>.md`. It **starts with**:
   - commit;
   - accepted / fresh / reused counts;
   - measured LUT / WNS;
   - open blockers;
   - next dependency;
   - `HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO`.

   List every irregularity (INVALID runs, re-adjudications) without relabelling history.
8. **Update** `reports/NEXT_STEP.md`, `docs/OPEN.md` and `docs/sessions/2026-11.md`; then commit.

**Lessons already paid for:**
- On this FPGA, deleting a register can **add** LUTs (the S3 A5 withdrawal). Measure, don't assume.
- A mutant's kill scope must include the fields computed from the corrupted value (the S3 `state_in` INVALID).
- The OOC flow's child-engine check (`scripts/d4_crypto_ooc_child.tcl`) lists the expected hierarchy. If you move or remove
  an engine, update it structure-aware, as S3 did for `u_perm`, never by dropping rows that still exist.
- Never source a big project-update Tcl inside the Vivado GUI: it hung twice. Use `scripts/install_xpr_update.sh` with
  Vivado closed.

---

## 4. I-6 = NOC-4: trusted authorization (target **NOC 4 / 5**)

**Goal:**
- No protected commit happens without a valid grant.
- Every fault's source, operation, reason and epoch is observable.
- The gate is tested **integrated** at every untrusted boundary.

### 4.1 Work items

| ID | Item | Where today | What to build |
|---|---|---|---|
| C-1 / C-2 | **Verifier retry on endpoint BUSY** (DECISION_REGISTER C-1/C-2: bounded retry, max 3, then fail) | `rtl/dual_lane/pq_rot_verifier.sv` has **no retry** logic | retry FSM: BUSY -> retry up to 3 times -> 4th BUSY = fail closed (attestation_failed, REVOKE path). Add the rule to `scripts/policy_layer.py`, so the Python model and the RTL agree |
| N-10 status | **Fault status** | `rtl/dual_lane/noc_fault_status.sv` exists but is **not instantiated** | instantiate it in the P7 subsystem; record source, operation, reason and epoch for every fault event; sticky plus a count |
| Trusted inputs | **trusted fail / timeout / clear** | tied to `1'b0` at `rtl/dual_lane/pq_noc_subsystem_p7.sv:121` | drive them from the RoT verifier (fail, timeout) and a trusted clear; gates must block on fail / timeout and recover only on a trusted clear |
| C-5 | **0x2 memory window** (decided, commit 7d90d70; not built) | memory stand-in checks `address[31:28]==4'h8` at `pq_noc_subsystem_p7.sv:248` | accept `A[31:28] == 4'h2`, remote = `0x2T00_0000` |
| K-3 | **Length binding** | not built | a fixed expected length per tile / message type, beside the whitelist; a mismatch is rejected with its own reason |
| B1 (area) | **Status counter widths** | about 45 x 32-bit counters, about 950 LUT (Step A scout) | while defining the fault-status register map, choose the widths (for example 16-bit saturating) and drop counters nothing reads. Expected saving: about 0.4-0.6k LUT (estimate) |

**Bench consequence of C-5:** these files drive the old address `0x8200_0100`:
- `tb_n2p7_rtt.sv`, `tb_p7_c4.sv`, `tb_p7_gate_data.sv`, `tb_p7_ingress.sv`, `tb_pq_full_chain.sv`;
- `sim/dual_lane/f234/tb_sys_f234_body.svh`;
- `synth/p7_board/pq_p7_board_top.sv`.

Make **new versions** (new file names, for example `*_i6.sv`) that use `0x2200_0100`, and register them as new jobs with
the same counts. **Never edit reference vectors.** Old jobs stay as history.

**If any port changes** (for example a status bus out of the subsystem), write an **M-F1 revision note first**.

### 4.2 Verification required (from R4 NOC-4 and the plan)

**One integrated gate bench** (for example `tb_i6_gate`) on the S3 subsystem, with cases:
1. blocked after reset;
2. grant accepted **only** from the RoT (tile 4), with status 1 and a whitelist match;
3. a worker grant with a **valid MAC** is rejected (issuer check);
4. revoke, failure, timeout and reset-during-challenge each block;
5. trusted clear and retry work;
6. memory responses are gated too (F4 / Q2 still hold);
7. **4 BUSY replies -> exactly 3 retries, then fail**;
8. each fault produces the right source / operation / reason / epoch in `noc_fault_status`;
9. the 0x2 window: `0x2200_0100` accepted; an `0x8...` address -> refused with its reason;
10. K-3: a wrong length for a tile -> rejected with the K-3 reason.

**Mutants** (each must be KILLED by its targeted check, with no timeout or fatal):
- gate bypass;
- issuer check removed;
- revocation ignored;
- retry unbounded;
- fault status not recorded;
- K-3 check off.

**Regression:** re-run the S3 system set on the I-6 RTL (n2p7 RTT, C4 bound, F2-F4, S2 attacks, gate data, ingress)
using the new 0x2 bench versions.

**Area and timing:** an `i6_p7_pnr` job (copy of `s3_p7_pnr` with the I-6 list), run alone. Report LUT, FF, WNS and WHS
against S3.

### 4.3 Deliverables (I-6)

| File | Content |
|---|---|
| `docs/decisions/I6_CONTRACT.md` | items, invariants, frozen jobs and counts, mutants with scopes, acceptance |
| DECISION_REGISTER rows | C-1/C-2 implementation, fault-status map (including B1 widths), C-5 build, K-3 table |
| M-F1 revision note | only if a port or field changes |
| `rtl/dual_lane/...` | retry FSM, fault-status wiring, trusted inputs, 0x2 window, K-3, counter widths |
| `scripts/policy_layer.py` | retry rule (the Python model agrees with the RTL) |
| benches | `tb_i6_gate` plus the `*_i6` 0x2 versions |
| registry | `i6` and `i6_pnr` selections, frozen counts, mutants |
| `reports/I6_GATE_<date>.md` | gate report |

### 4.4 Acceptance (I-6 -> NOC 4 / 5)

- Every `i6` job PASS (fresh or identity-matched); every mutant KILLED.
- 0 protected commits without a valid grant.
- Fault fields observable for every fault class.
- **LUT <= 47,550**, WNS >= 0 (report against the +0.3 ns target).

---

## 5. I-7 = PQ-4 then PQ-5: security matrix and offline full chain (target **PQ 5 / 5**)

**Rule:** use the **real** NOC-3 / NOC-4 modules (the I-6 subsystem), never testbench stand-ins.

### 5.1 PQ-4: SEC-1..4 matrix (R4 sec. 4, contract 2026-10-08)

| ID | Attack | Expected result | Targeted control (a mutant that must make the attack succeed) |
|---|---|---|---|
| SEC-1 | genuine tile | grant; authorized data works | corrupt the response -> rejected |
| SEC-2 | wrong key / identity / measurement; forged response from SPOOF | no grant, no commit | disable that specific check -> unauthorized grant |
| SEC-3 | L2 replay **and** attestation replay (separate cases); stale epoch; nonce substitution; reset replay | rejected for the **stated reason** | disable freshness -> replay succeeds |
| SEC-4 | runtime substitution (changed config / imem) at re-attestation | revoked and isolated | disable whitelist or enforcement -> substituted state granted |

**Must include the 6 attestation rows still OPEN after I-5:**
1. wrong tag at the verifier;
2. wrong measurement;
3. attestation replay;
4. nonce substitution;
5. config / imem substitution at re-attestation;
6. error response.

**Plus:** wrong grant issuer, timeout, status-clear misuse, truncated challenge, concurrent SPOOF traffic.

**Expected values:**
- They come from the frozen teammate reference (`software/pq_attest_final/`, read only) and `scripts/policy_layer.py`.
- **Not** from the RTL itself.
- The Engineer 4 lane's step 7 vectors (their brief) can supply them once they are on P7 rules.

**Acceptance:**
- Every attack is rejected for its stated reason, with **0 unauthorized commits**.
- Every targeted control (mutant) makes its attack observable (KILLED by the right check).

### 5.2 PQ-5: offline full chain (R4 sec. 4)

**Bench:** `tb_pq_full_chain` in **non-demo** mode on P7. Make a new P7 / I-6 version; the old bench is rev-5 and drives
`0x8200_0100`. It is judged by the V7 adapter oracle.

**Chain:** challenge -> L2-authenticated transport -> endpoint (KDF, measure, tag) -> response -> RoT verifies (teammate
verifier **and** policy layer) -> GRANT -> authorized write -> revoke / substitution -> blocked.

**Also:**
- repeated distinct transactions;
- backpressure;
- reset at each boundary;
- coexisting SPOOF traffic;
- retry and timeout (from I-6).

**Report** the nonce source as **"deterministic demo issuer"**. There is **no TRNG claim**.

**Acceptance:** fresh PASS with all dependencies accepted on compatible identities; `HARDWARE_VALIDATED=NO`.

### 5.3 Deliverables (I-7)

| File | Content |
|---|---|
| `docs/decisions/I7_SEC_MATRIX.md` | each row: attack, stimulus, expected reason, oracle source, targeted control, frozen check count |
| benches | SEC matrix bench(es) and the P7 full-chain bench |
| vectors | from the teammate reference / policy layer, generated by a script, with SHA-256 recorded; never hand-edited |
| registry | `i7` selection, counts frozen before the first run, controls as mutants with kill scopes |
| `reports/I7_GATE_<date>.md` | gate report: PQ-4 and PQ-5 results; the 6 OPEN rows closed (or still OPEN, with the reason) |

---

## 6. I-8 = NOC-5: N-11, N-12, N-13 and release (target **NOC 5 / 5**)

| Sub-gate | What | Done when |
|---|---|---|
| **N-11** | Consume the PQ-4 SEC-matrix evidence on the **matching identity** (same sources as the release) | identities match; no re-run needed, or re-run fresh |
| **N-12** | A clean final regression of **every gate** (I-1 .. I-7 jobs that apply to P7) on **one release identity** | all PASS on one identity |
| **N-13** | Isolated batch synthesis + implementation of the full subsystem at 20 ns, explicit sources, no incremental DCP, S1-PNR-DIR flow, **secure and insecure profiles** | WNS / WHS / WPWS >= 0, TNS / THS = 0, 0 route / DRC errors, no unexplained unconstrained paths; LUT, FF, LUTRAM, BRAM, DSP reported. **A FAIL is a HARD STOP.** |
| Release | `releases/DUAL_LANE_10_<id>/` with a manifest: sources and hashes, run IDs, gate reports | manifest complete and committed |

**N-13 notes:**
- **A real-pin top is needed.** The subsystem has more ports than the package's 210 I/O, so N-13 needs a top-level
  wrapper (decision D5).
- **The existing board wrapper is NOT valid for N-13 area.**
  - `synth/p7_board/pq_p7_board_top.sv` (D5-BOARD) feeds **constant demo secrets**, so synthesis trims about 10k LUT of
    ingress and crypto logic (33,970 vs 37,398).
  - For N-13, inputs must come from **registers or a ROM loaded at run time** (non-constant), and every status output must
    be observable, so nothing constant-folds.
- **Timing risk:** today the subsystem has +0.126 ns, router-limited (protected RTL). If N-13 fails, the first candidates
  are **flow-only**:
  - router pblocks;
  - `phys_opt` replication;
  - reset replication (the reset net has about 8k sinks).

  Only then would a router RTL change be considered (registered FIFO output, +1 cycle per hop). That changes NoC latency
  bounds, so it is a hard stop for a decision.

**Deliverables (I-8):**
- `docs/decisions/I8_RELEASE_PLAN.md`;
- the N-13 wrapper (non-constant provisioning);
- the `i8` / `i8_pnr` jobs;
- `reports/I8_GATE_<date>.md`;
- the release manifest.

---

## 7. Order, dependencies and checkpoints

```
I-6 (NOC-4) --gate--> I-7 PQ-4 --> I-7 PQ-5 --gate--> I-8 N-11 -> N-12 -> N-13 --gate--> release
                       ^ E4 vectors help                           ^ D5 wrapper needed
```

- I-(n+1) starts only after the I-n gate is PASS.
- **Measure area after each increment.** Room left is about 10.2k LUT. Area options held in reserve:
  - A3: kmac_encode specialisation, about 1-1.5k (estimate);
  - A2: tile-4 KMAC merge, about 4.5k (estimate); changes signed bounds, so it is a decision.
- **Not part of I-6..I-8** (separate Lane 1 steps; keep them out of these increments):
  - the integration contract;
  - the TMEM <-> NI bridge;
  - CPU integration and the merge.

## 8. Open items to keep in mind

- A lint waiver for `rtl/dual_lane/kmac_128_xp.sv:202` (an inherited production line) awaits acknowledgement.
- The Vivado project (`NOC_PQATTEST.xpr`) and the board bitstream still use the pre-S3 source list. Refresh with
  `scripts/install_xpr_update.sh` (Vivado closed) when needed.
- The RISC-V lane has a new addendum (`docs/handoff/BRIEF_RISCV_LANE_AREA_ADDENDUM_20261103.md`). Their tile size feeds
  the area budget.

## 9. Prompt for the AI assistant (paste this)

> You are assisting Kalash on NOC_PQATTEST (FPGA NoC plus post-quantum attestation, Vivado/XSim 2024.1, xc7a100tcsg324-1,
> one 20 ns clock). Read `CLAUDE.md`, then `docs/handoff/LANE1_I6_I7_I8_HANDOFF_20261103.md`.
>
> We are doing increments I-6 (NOC-4), I-7 (PQ-4 then PQ-5) and I-8 (NOC-5), in that order.
>
> For each increment:
> 1. Write the contract document first (frozen job counts, mutants with oracles and kill scopes).
> 2. Make RTL changes only in `rtl/dual_lane/` variants, starting from the S3 source list.
> 3. Scratch-check, register the jobs (switch the config's active increment BEFORE running `prepare_dual_lane.py`, then
>    run `test_dual_lane.py` and check its exit code).
> 4. Run the harness, then write the gate report.
>
> Never:
> - edit a protected file or a reference vector;
> - lower an expected count;
> - count a timeout as a pass;
> - claim a result that was not run.
>
> Stop and ask Kalash on:
> - any FAIL needing a design or contract change;
> - LUT > 47,550;
> - a new security question;
> - any change to a signed bound, wire format, device, clock or budget;
> - an N-13 timing FAIL.
>
> Label every number as post-route, post-synthesis, estimate or not run.
