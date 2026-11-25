# Step c design: shared L2 KMAC, arbiter, SF-1 slots (M-F1 rev 7 R7.6/R7.6a/R7.7, SF-1 § Design (P7))

Status: **DESIGN, doc only.** Written 2026-10-21 by Claude Code before any step-c RTL.

Inputs:
- M-F1 rev 7 (signed with C1–C4), R7.6a bounds (P ≤ 269, Q ≤ 792, J_MAX 128, OVH ≤ 4), A0 accepted;
- `scripts/arbiter_model.py` PASS_FRESH (run 214044 / 010513).

## 1. Structure

| Block | Content | Instances |
|---|---|---|
| `l2_kmac_engine` (new) | one `kmac128` #(32, 14, 88), the R7.6a arbiter, 4 request ports r0..r3, transcript muxes | 1 |
| `noc_l2_auth_p7` (new variant, tiles 3 and 4) | trimmed wrapper (T1, T2 kept) plus a `PEER` parameter, 2 receive slots (P = peer, G = general), per-source rate limit on G, one directed key per direction, request ports to the engine (tx and rx) | 2 |

The engine owns the only L2 KMAC. Each `noc_l2_auth_p7` keeps its FSMs, but `T_START` and `R_START` become requests and `T_WAIT` and `R_WAIT` wait for the engine's grant + done. There is no local KMAC.

Requester map (R7.6):

| Requester | Wrapper and path | Class |
|---|---|---|
| r0 | tile 4 TX | P |
| r1 | tile 3 slot P (src = 4) | P |
| r2 | tile 3 TX | Q |
| r3 | tile 4 slot P (src = 3) | Q |

Tile 4's slot G and tile 3's slot G never request: a non-peer source is refused with reason 5 before any KMAC (R7.2).

## 2. Arbiter (exactly the model in `scripts/arbiter_model.py`)

- Grants happen only while the engine is free and after OVH idle cycles.
- P is granted unless 2 consecutive P grants were made while a Q request was pending; in that case Q is granted.
- The consecutive-P counter resets on a Q grant and on any P grant made while no Q is pending.
- **A0:** the class pointer flips after every grant in that class.
- No pre-emption.
- **A1:** a requester keeps `req` until `grant` and cannot raise `req` while its own job is in flight (assertion).
- **A2:** OVH ≤ 4 cycles between `done` and the next grant when a request is pending (assertion plus measurement).
- **A3:** every job ≤ J_MAX = 128 cycles from grant to done (assertion plus measurement).

## 3. SF-1 slots (SF-1 § Design (P7))

| Slot | Admits | Storage | Engine use |
|---|---|---|---|
| P | control-type packets with stamped src = `PEER` | 26 × flit, LUTRAM; HEAD and F0..F4 captured to registers at collect (T4); replay by pointer | the wrapper's P/Q requester (r1 or r3) |
| G | every other control-type packet; drained after the header pre-check (reason 5) | same LUTRAM structure | never |

- Data-plane packets bypass both slots (R7.1).
- **Rate limit on G:** at most one admission per T_RL = 64 cycles per stamped source (6 counters, 6 bits); excess is dropped with reason 6.
- **Busy policy:**
  - a packet for a busy slot P (not expected, since the RoT is single-outstanding) counts busy-drop 7 and increments `p_slot_drops`;
  - for a busy slot G, the arrival is dropped with reason 7 as in rev 6.

## 4. Benches and mutants (counts derived and frozen in a count-derivation doc before the first run)

| Job | Bench | What it checks |
|---|---|---|
| `l2e_arbiter_bounds` | `tb_l2_kmac_engine` (engine alone, random and adversarial request patterns, fixed J) | every grant wait ≤ 269 (P) / ≤ 792 (Q); A1/A2/A3 assertions never fire; per-requester digest = reference KMAC (`software/kmac128_ref.py` via a vector file) |
| `l2e_mut_a0_pointer` | same | pointer moves only when both P are pending; **must fail the P-bound check** (model: 396) |
| `l2e_mut_no_aging` | same | guard removed; **must fail the Q-bound check** (model: unbounded under continuous P) |
| `l2p7_equiv_ctrl` | `tb_l2p7_pair` (tiles 3 and 4 wrappers + engine) | control-plane packets bit-exact against the rev 6 wire (R6.5–R6.8) for 4↔3 traffic; reasons 1/2/3/4/5/6/7 covered; data-plane pass-through bit-exact plain framing |
| `sf1_flood_revoke` | `tb_l2p7_pair` + raw-port flood model | REVOKE during a back-to-back forged flood ends de-authorized; `p_slot_drops == 0`; GRANT variant ends authorized; REVOKE latency ≤ 269 + transport (C4 at unit level) |
| `sf1_mut_single_slot` | same | slot P disabled (single quarantine); **killed by `authorized==0 after REVOKE`**, not by a timeout |
| `l2e_ooc` | OOC: `l2_kmac_engine` + 2 × `noc_l2_auth_p7` | compare against the pre-check (B3 summary): ≈ 7.0 k engine + 2 × ≈ 1.3 k wrappers |

## 5. Open points for Kalash (no RTL decision taken on them)

- **Option A of the mutant-judge proposal** (B3 summary). Step-c mutants that intentionally trip A1–A3 assertions face the same judge rule, so the decision is needed before they run.
- **Reference vectors for the engine bench.** The proposal is to generate KMAC128 (KEY 32, CUSTOM `NOC-L2-AUTH-v1`, ≤ 88-byte) vectors from `software/kmac128_ref.py`, with the generator pinned as an oracle file.

## 6. Area realism: SF-1 slot implementation (Kalash 01:32, task 2). ESTIMATE, before RTL

Per L2 tile (3 and 4), two receive slots P and G, each 26 flits × 36 bits = 936 bits.

| Implementation | LUT per slot (E) | FF per slot (E) | Per tile, 2 slots | Basis |
|---|---|---|---|---|
| FF (today's `rb[]` style) | ≈ 300 (26:1 × 36 replay mux, measured 294 cells) + ≈ 40 control | 936 + HEAD/freshness regs ≈ 200 | ≈ +680 LUT, ≈ +2.3 k FF | B-1 attribution `l2_shared_split.txt` |
| **LUTRAM** (RAM32M: 32 deep × 6 bits per 4 LUTs; 36 bits → 6 RAM32M = 24 LUTM) | ≈ 24 LUTM + ≈ 60 control/pointer | HEAD/freshness capture ≈ 200 | **≈ +170 LUT, ≈ +0.4 k FF** | RAM32M is 32×6 per 4 LUT (7-series CLB) |
| BRAM (RAMB18, 512 × 36) | ≈ 40 control | ≈ 200 | ≈ +80 LUT + 2 RAMB18 | 1 RAMB18 per slot; BRAM is 0 % used today |

**Specified in the design: LUTRAM.**
- **Why:**
  - the area pre-check counted +100 per tile for both slots; LUTRAM gives ≈ +170 per tile against the measured 294-cell FF read mux it replaces, which nets to ≈ +100 when that mux is removed;
  - the FF version would add ≈ +680 per tile, ≈ +1.4 k over both tiles, which would eat almost all of the ≈ 1.1 k margin;
  - BRAM is the fallback if LUTRAM read-port needs (replay plus capture) do not fit.
- **Read ports:** replay reads one flit per cycle, which is the LUTRAM read port. HEAD, freshness F0–F4 and the 4 MAC words are captured into registers during collect (T1/T4), so no other parallel read is needed.

**Revised step c/d total (ESTIMATE):** ≈ 45,900 + 490 (pre-check, with LUTRAM slots) ≈ **46,400 LUT (73.2 %)**. That is unchanged and ≤ 75 %. With FF slots it would be ≈ 47,800 (75.4 %), over the gate, so FF slots are excluded by design.
