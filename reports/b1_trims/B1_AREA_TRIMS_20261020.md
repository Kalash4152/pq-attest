# B-1 area trims: measure first (Kalash 2026-10-20). Analysis only: no RTL, no rev 7, no SF-1/I-5 work

**Labels:**
- **M** = measured OOC synthesis or routed numbers from registered runs.
- **E** = ESTIMATE, with its basis stated.
- **Netlist attribution** = diagnostic Tcl queries on the existing `synth.dcp`. Not evidence, and no new synthesis.

**Inputs:**
- `noc_l2_auth` (P6-S, `PQ_MAC_ON`): run `dual_lane_10_20261020_200142_eb49e57d`, 16,235 LUT / 15,249 FF, WNS +3.743 ns.
- Netlist scripts and outputs are in this folder:
  - `l2_lut_attribution.tcl` / `.txt`;
  - `l2_shared_split.tcl` / `.txt`.
- Option matrix: `area_matrix.py` produces `area_matrix.md`.

**Result:**
- Only four configurations reach the ≤ 75 % target (47,550 LUT). All are **L2 on tiles 3 and 4 only + one shared L2 KMAC**, plus at least two of {D, trim, shared Keccak}.
- Every one of them removes data-plane link authentication (§4).

**STOP for Kalash's decision.**

## 1. Breakdown of the 4,156 non-KMAC LUTs of `noc_l2_auth`

`util_hier` at full depth (`-hierarchical_depth 8`) has no sub-hierarchy in the `noc_l2_auth` top level: 4,156 LUT / 4,455 FF
sit flat beside `ni` (263), `rx_kmac` (5,912) and `tx_kmac` (5,904). The attribution below is therefore by fan-in cone in the
synthesized netlist:
- 4,540 LUT cells, which util packs into 4,156 LUTs;
- 0 cells unattributed;
- a cell counts as "exclusive" when only one register group's cone contains it.

**FF (exact, from the RTL declarations):**

| Side | Registers | FF |
|---|---|---|
| TX ≈ 2,080 | `tp` 16×32 | 512 |
| | `tx_seq` 6×64 | 384 |
| | `tx_transcript` | 704 |
| | `tx_key_q` | 256 |
| | seq/epoch/head/control | ≈ 220 |
| RX ≈ 2,377 | `rb` 26 flits ≈ 936 | 936 |
| | `rx_seq` 6×64 | 384 |
| | `rx_transcript` | 704 |
| | `rx_key_q` | 256 |
| | counters/control | ≈ 100 |
| **Sum** | | **≈ 4,457** (measured 4,455) |

| Contributor (RTL) | LUT cells | Notes |
|---|---|---|
| **`supplied_tag[i*32+:32] = rb[rn-4+i]`** (`noc_l2_auth.sv:163`): runtime-indexed READ of the quarantine, 4 × 32 bits × 26 positions, feeding the MAC compare (`:226`) | **1,156** (72 of them the compare) | the largest single item |
| key select `tx_keys[peer(dest)*256+:256]` (`:110`) and `rx_keys[peer(src)*256+:256]` (`:215`): 6:1 × 256-bit muxes per direction | 515 + 515 = **1,030** | `directed_keys` is a 9,216-bit subsystem input (`pq_noc_subsystem.sv:12`), so these are real muxes |
| transcripts `tx_transcript` (`:118-125`) / `rx_transcript` (`:216-221`): written at **constant** positions. The cost is the per-bit `i<pn ? word : 0` zero-fill | 519 + 512 = **1,031** | redundant: `kmac_encode.sv:408` already masks bytes ≥ `msg_len`. `kmac_128.sv:398` and `kmac_encode.sv:117` re-register `msg_in`, so the transcript is the first of three 704-bit copies |
| `rb[play]` replay read to the NI (`:165`), 26:1 × 36 bits | 294 | |
| `rx_seq[peer(src)]` compare/update (`:230-233`) | 273 | |
| `tx_seq[peer(dest)]` select, +1 and all-ones check (`:74`, `:109`) | ≈ 242 (cone) | |
| epoch compare (`:228`) | 45 | |
| freshness insertion mux, FSMs, counters, output muxes | ≈ 470 | |

**Runtime-indexed part-select writes.** The transcripts are **not** written at runtime-indexed positions. The loops at
`:124` / `:220` use constant `i` with a runtime *condition*. `noc_l2_auth` has **no** runtime-indexed part-select write;
its costs are runtime-indexed **reads** (`:163`, `:165`, `:110`, `:215`). The D-SYN-2-style write pattern does occur in the protected KMAC originals that every L2, KDF and tag engine instantiates:
- `kmac_128.sv:194`, a multi-line `final_block[(msg_len_reg + …)*8 +: 8]`, 89 positions;
- `kmac_encode.sv:437-445`, runtime-indexed byte-array writes `block_data[msg_len_reg + k]`.

That fits the in-context KMAC top + encode cost of ≈ 1.8 k LUT per KMAC.

**Trim proposals (E, per L2 tile).** Cell savings are scaled by 4,156/4,540.

| # | Trim | Saving (E) | Cost (E) |
|---|---|---|---|
| T1 | Capture the 4 MAC words into a 128-bit register while collecting: counter-indexed, 4 positions. Removes the `rb[rn-4+i]` read | ≈ 990 LUT | +40 LUT, +128 FF |
| T2 | Drop both transcripts. Wire `kmac msg_in` from `tp[]` / `rb[]` at constant positions: no zero-fill needed (`kmac_encode.sv:408`), and the kmac re-registers it (`kmac_128.sv:398`) | ≈ 940 LUT, −1,408 FF | 0 |
| T3 | Directed keys from a per-tile key RAM (RAMB18) instead of 6:1 × 256 muxes on a 1,536-bit port | ≈ 940 LUT, −0 FF (key_q kept) | +1 RAMB18, +30 LUT |
| T4 | Quarantine `rb[]` in LUTRAM. HEAD and freshness captured into registers at collect; replay by pointer | ≈ 210 LUT, −≈ 700 FF | +60 LUT |
| **Total** | | **≈ 3,030 LUT (4,156 → ≈ 1,127)** | |

**Additional lever, not in the matrix (E, low confidence).** A D-SYN-2-style byte-serial padding variant of
`kmac_128.sv:194` / `kmac_encode.sv:437-445`, plus removing the duplicate `msg_reg`, could save ≈ 1 k LUT and ≈ 1.4 k FF per KMAC.
It would need its own equivalence campaign.

### Lint extension (done, preflight-enforced)

`dual_lane_preflight.lint_runtime_offset_writes` now checks **every statement**: always_ff, always_comb, always and assign, inside or outside loops.
- Multi-line LHS expressions are joined.
- Sized literals such as `5'd0` are not treated as identifiers.
- Allowed index terms: enclosing for/genvar variables, ALL-CAPS constants, numbers, casts.

In `rtl/dual_lane` it flags 5 existing writes. No RTL change is allowed now, so each is covered by a **line-hash-pinned waiver** in `scripts/rtl_lint_waivers.json`. An unwaived finding, or a stale or unused waiver, fails the preflight.

| Waived write | Positions |
|---|---|
| NI `:1431`, `:1557` (MAC word capture) | 4 |
| endpoint `:202` | 7 |
| verifier `:73` | 16 |
| `SHA3_PAD.sv:23` (D-SYN-1, measured, equivalence-proven) | 137 |

Self-tests in `test_dual_lane.py` (77 tests OK):
- the D-SYN-2 original `pq_measurement.sv:126` is flagged;
- `noc_l2_auth.sv` has no finding;
- protected `kmac_128.sv:194` is found, which needed the multi-line join;
- an outside-loop write and a continuous assign are flagged;
- the waiver hash-pinning and stale-waiver behaviour work.

Protected originals are not in the preflight scope: the lint scans `rtl/dual_lane`.

## 2. Control-message flow map (`pq_noc_subsystem`)

| Message | Sender, tile | Receiver, tile | Citation |
|---|---|---|---|
| ATTEST_CHALLENGE | RoT verifier, tile 4 | endpoint, tile 3 (`TILE_CRYPTO`) | `pq_rot_verifier.sv:47-49`; destination fixed `tile_to_coord(TILE_CRYPTO)` `:48`; verifier on tile 4 `pq_noc_subsystem.sv:91-94,120` |
| ATTEST_RESPONSE | endpoint, tile 3 | verifier, tile 4 | `pq_attest_endpoint.sv:141-142` (`reply_to`); verifier accepts only source `TILE_CRYPTO` `pq_rot_verifier.sv:70`; endpoint on tile 3 `pq_noc_subsystem.sv:87-90,114` |
| ATTEST_GRANT / ATTEST_REVOKE | verifier, tile 4 | **tile 3 only** | `pq_rot_verifier.sv:48-50,99-100` |
| GRANT/REVOKE acceptance | — | gate at every tile, issuer must be `TILE_ROT` | `noc_attest_gate.sv:19,29-33`; gates at all 6 tiles `pq_noc_subsystem.sv:77` |
| Data plane: memory requests | any authorized tile | memory, tile 2 | accepted if `authorized[source] ∥ source == TILE_ROT` (`pq_noc_subsystem.sv:141-142`); commit `:155-156`. **The source is trusted only because L2 authenticated the HEAD (`rhv[2]`)** |
| Raw spoof injection | SPOOF, tile 5 (`TILE_SPOOF`) | anywhere | `pq_noc_subsystem.sv:66` bypasses the tile-5 L2 TX |

**Minimal set of tiles that need `noc_l2_auth` for control messages: tile 3 and tile 4.** The other tiles (0, 1, 2, 5) never send or receive a control message. However:
1. Their gates would accept an *unauthenticated* GRANT that claims `TILE_ROT` (`noc_attest_gate.sv:19`), so a non-L2 tile must be built **never-authorizable**.
2. Memory on tile 2 relies on L2 for source authenticity (§4).

## 3. Keccak census (full chip)

| Where | keccak_f1600 instances | LUT each | Source |
|---|---|---|---|
| `noc_l2_auth` × 6 (tx_kmac, rx_kmac) | 12 | 3,741 | **M**, run 200142 util_hier |
| endpoint: `pq_kdf`, `pq_measurement` (sha3_256), `pq_attestation_tag` | 3 | 3,741 | **M**, endpoint_ooc run 174533 |
| verifier: `pq_kdf`, `pq_attestation_tag` (`pq_rot_verifier.sv:53,56`) | 2 | 3,741 | M per engine (kdf/tag OOC); the verifier itself was never synthesized |
| **Total** | **17** | | **63,597 LUT = 100.3 % of the device in permutations alone** |

Each instance is 2,119 LUT of `keccak_round` (combinational, 1 round/clock) and 1,622 LUT / 1,621 FF of state and control.
A permutation is **24 cycles** (`pq_keccak_f1600.sv:7`).

**Shared Keccak option (S, E):** one permutation core per subsystem.
- **Structure:** each sponge user keeps its 1,600-bit state and FSM and loses its `keccak_round` (2,119 LUT, M). The core adds an N:1 × 1,600-bit state mux, ≈ 1,600 LUT for N ≤ 4 and ≈ 3,200 for N ≤ 16, plus control.
- **Saving:** ≈ (N − 1) × 2,119 − mux.
- **Latency cost:** each permutation waits behind at most N − 1 others, i.e. worst case +(N − 1) × 24 cycles per permutation.
  - Measured attestation latency today is **205–333 cycles** (s8_golden on the D-SYN-2 list, `LATENCY G00..` lines, run 173746).
  - An L2 KMAC is 3 permutations (`kmac_tb` permutation-count test).
- **Requirement:** the shared core needs the same RoT-first priority rule as the shared KMAC.

## 4. Combined option table (E, from measured parts), target ≤ 75 % = 47,550 LUT

**Model** (`area_matrix.py`; every constant cites its source):
- mesh 10,114 (M);
- per L2 tile: glue 4,156 (M) or 1,127 trimmed (E), plus NI 263 (M); 402 (M) per tile without L2;
- per-tile KMAC 5,908 (M, in context), or one shared engine 7,018 (E: 5,908 + 4:1 × 704-bit message mux + 4:1 × 256-bit key mux + arbiter);
- endpoint 19,986 (M) + verifier 11,378 (E);
- D = −8,884 (E: one KMAC fewer in each of endpoint and verifier, +0.7 k muxes each);
- S as in §3.

The BRAM18 column counts the T3 key RAMs. Gate and fault-status glue is not included.

| L2 tiles | L2 KMAC | D | Trim | Shared Keccak | Keccak cores | LUT (E) | % | ≤ 75 % |
|---|---|---|---|---|---|---|---|---|
| 3,4 | 4 per-tile | no | no | no | 9 | 75,556 | 119 % | no |
| 3,4 | 4 per-tile | no | no | yes | 1 | 61,904 | 98 % | no |
| 3,4 | 4 per-tile | no | yes | no | 9 | 69,498 | 110 % | no |
| 3,4 | 4 per-tile | no | yes | yes | 1 | 55,846 | 88 % | no |
| 3,4 | 4 per-tile | yes | no | no | 7 | 66,672 | 105 % | no |
| 3,4 | 4 per-tile | yes | no | yes | 1 | 57,258 | 90 % | no |
| 3,4 | 4 per-tile | yes | yes | no | 7 | 60,614 | 96 % | no |
| 3,4 | 4 per-tile | yes | yes | yes | 1 | 51,200 | 81 % | no |
| 3,4 | 1 shared | no | no | no | 6 | 58,942 | 93 % | no |
| 3,4 | 1 shared | no | no | yes | 1 | 51,647 | 81 % | no |
| 3,4 | 1 shared | no | yes | no | 6 | 52,884 | 83 % | no |
| 3,4 | 1 shared | no | yes | yes | 1 | **45,589** | **72 %** | **yes** |
| 3,4 | 1 shared | yes | no | no | 4 | 50,058 | 79 % | no |
| 3,4 | 1 shared | yes | no | yes | 1 | **45,401** | **72 %** | **yes** |
| 3,4 | 1 shared | yes | yes | no | 4 | **44,000** | **69 %** | **yes** |
| 3,4 | 1 shared | yes | yes | yes | 1 | **39,343** | **62 %** | **yes** |
| all 6 (reference) | 12 per-tile | no | no | no | 17 | 138,888 | 219 % | no |
| all 6 | 12 per-tile | no | yes | no | 17 | 120,714 | 190 % | no |
| all 6 | 1 shared | no | no | no | 6 | 75,010 | 118 % | no |
| all 6 | 1 shared | no | yes | no | 6 | 56,836 | 90 % | no |

The all-6 untrimmed row reproduces the measured composite: 138.6 k, plus 300 for the verifier FSM (E).

**What each choice loses in the threat model (vs today: MAC + freshness on every message on every tile).**
- **L2 on tiles 3, 4 only, and R1 (control-plane MAC only):** data-plane link authentication is removed everywhere.
  - **Lost:**
    - Data packets with a forged source, for example the SPOOF raw injection (`pq_noc_subsystem.sv:66`) claiming an authorized source, would pass the memory check at `:141-142` and commit at `:155-156`. The memory tile would need its own source authentication, or must treat every data packet as unauthenticated.
    - Data-plane replay (per-peer sequence) and in-flight tamper detection.
  - **Required:** gates on tiles 0, 1, 2, 5 must refuse GRANT outright, because they would otherwise accept an unauthenticated GRANT claiming `TILE_ROT`.
  - **Still covered by the NOC-3 L2 bench:** every RX attack step in `scripts/l2_golden.py:210-233` uses control-plane packets (`ch*`, `resp*`, `grant*`):
    - tamper of head, payload, tag and freshness;
    - wrong source, key, destination and VC;
    - length and framing;
    - sequence zero, replay and max; epoch.

    They keep their meaning on tiles 3 and 4.
  - **No longer meaningful:** the TX steps `(T, (2, 2, 0x780, W))`, which MAC a data-plane memory write to tile 2.
- **One shared L2 KMAC:** availability coupling between MAC users. It needs RoT strict priority and a stated starvation bound; SF-1 interacts with it.
- **D:** none (latency inside endpoint/verifier only).
- **Trim (T1–T4):** none (implementation only; needs an equivalence bench per trim).
- **Shared Keccak:** availability/timing coupling across *all* crypto users, so attestation latency depends on L2 load. It needs the same priority rule, plus a note on contention as a timing side channel.

**Observations for the decision:**
- No configuration with per-tile KMACs reaches 75 %.
- Without the shared KMAC, the best is 81 % (all of D, trim and S).
- The cheapest-risk passing row is **minimal + shared KMAC + D + trim (69 %, no shared Keccak)**: it avoids the cross-crypto coupling of S.
- All figures are E built from M parts. A real number needs OOC runs of the chosen variants and of the full subsystem.
