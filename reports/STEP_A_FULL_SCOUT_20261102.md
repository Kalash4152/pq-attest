# Step A, full scout: where every LUT of P7 goes and how to shrink it (2026-11-02; nothing in the design changed)

- **Evidence:** registered run `reports/dual_lane_10_20261023_121951_d99f256c/p7_subsystem_pnr/`:
  - `util_hier_routed.rpt` (depth 8);
  - `routed.dcp`, read-only, from which every primitive cell (98,475: LUT, FF, CARRY4, LUTRAM, MUXF) was dumped on
    2026-11-02 and grouped by the RTL signal it implements;
  - the 123-endpoint near-critical timing report.
- **Totals:** routed, Vivado 2024.1, xc7a100tcsg324-1, 20 ns: **43,935 LUT (2,014 LUTRAM) / 36,102 FF**, budget 47,550.
- **Estimates are marked "est."** and need a synthesis run to confirm. FF is not the constraint (28 % used); LUT is.
- **Supersedes** the candidate list in reports/STEP_A_AREA_TIMING_20261102.md, which only covered the top blocks.

## 1. Inventory (registered routed, LUT / FF)

| Area | LUT | FF | What inside costs the LUTs (measured from the netlist) |
|---|---|---|---|
| **E1** endpoint KMAC (KDF + tag) | 6,816 | 5,054 | Keccak core 3,741; **wrapper's own 1,600-bit state copy 1,601**; absorb 836; kmac_encode packing (`block_data`) 1,289 |
| **E2** endpoint measurement SHA3 + builder | 8,559 | 5,930 | Keccak core 3,741; **wrapper state copy 1,601**; **padding 1,255**; **absorb XOR 1,088**; builder shift copies of config / imem 1,046; block assembly 258 |
| **E3** L2 KMAC engine | 6,129 | 6,387 | Keccak core 3,741; wrapper state copy 1,601; absorb 211; encode about 890; key select mux 256 |
| **E4** verifier KMAC | 7,175 | 4,997 | Keccak core 3,741; wrapper state copy (same structure as E1); encode about 1,050 |
| Verifier logic | 696 | 3,132 | response capture 248; FSM / compare 210; 32-bit timer 74 |
| Endpoint logic | 370 | 502 | response serializer 25:1 x 32 bits 260 |
| Endpoint controller | 34 | 2,401 | registers only (request copy, response) |
| L2 wrappers (x2) | about 1,780 | about 2,300 | transcript word muxes about 200; TX flit mux 94; rate limiter 58; 32-bit `int extension` counter 35 each |
| Mesh (6 routers) | 10,263 | 1,934 | per router: allocator about 460 (input arbiters 222), crossbar 296, credit control 209, datapath 161, LUTRAM FIFOs |
| NIs (4 plain + 2 L2) | about 1,050 | about 800 | TX flit mux about 48 each, RX decode |
| Ingress, gates, quarantine, merge | 438 + 132 | 754 | |
| Status counters (all blocks) | **about 950** | **1,457** | about 45 x 32-bit event counters (gates, parsers, quarantine, L2 peer, memory, endpoint, verifier) + 356 CARRY4 |
| Top / memory stand-in | 212 | 283 | |

**Two structural findings the first pass missed:**
1. **Every KMAC / SHA3 wrapper keeps a second copy of the 1,600-bit Keccak state.** The wrapper stores the permutation result
   (`state_reg <= keccak_state_out`) and absorbs the next block from that copy. But the core's own `state_out` is contractually
   held stable from `done` until the next start (pq_keccak_f1600.sv header), so the copy holds data the core already holds.
   The cost is 1,601 LUT + 1,600 FF per engine (four engines).
2. **The measurement is always exactly one SHA3 block.** `MEASURE_MSG_MAX_BYTES = 135` < `RATE_BYTES = 136`
   (pq_measurement_pkg.sv:53, SHA3_PKG.sv:8), and `req_len_ok` rejects anything longer. So the measurement SHA3:
   - always absorbs into an all-zero state, which makes the absorb XOR (1,088 LUT) and the state copy (1,601 LUT) redundant;
   - pads with a run-time 136-byte mux (1,255 LUT) that the byte-serial builder could replace by writing the two pad bytes
     itself.

## 2. Opportunities, ranked by LUT saved per unit of risk

| # | Change | LUT saved (est.) | FF saved (est.) | Signed bounds / latency | Verification to re-earn | Risk |
|---|---|---|---|---|---|---|
| **T1** | Replicate the Keccak FSM select per lane (timing) | about 0 (+50 FF) | | none (cycle-identical) | crypto KATs, P&R | low |
| **A6** | **Single-block SHA3 for the measurement:** builder writes the pad bytes; the core loads the padded block directly; drop SHA3 pad, absorb and state copy | **3.5-3.9k** | 1.6k | none (same digest, same or fewer cycles) | s8 golden, endpoint unit / sys, dsyn2 measurement equivalence, mutants | low-medium |
| **A5** | **Drop the wrapper state copy in the KMAC engines:** absorb from the core's held `state_out` (block 0 from zero) | **1.3-1.6k per engine; 4.0-4.8k for E1 + E3 + E4** | 4.8k | none (cycle-identical) | KMAC KATs (s8, l2e engine, l2p7, verifier), system benches | medium (relies on the core's hold contract; A1 sharing must not start the other owner mid-message, which the controller sequence already guarantees) |
| **A1** | Share one Keccak core at tile 3 (E1 + E2) | 2.1-3.0k | 1.6k | none | already designed; scratch: 45 / 45 isolation, 95 / 95 s8 golden, 3 / 3 mutants killed | medium |
| **A3** | Specialise `kmac_encode` to each instance's fixed key and customization lengths | 1.0-1.5k (three engines) | about 0 | none | KMAC KATs | low-medium |
| **B1** | Status counters: 32 -> 16-bit saturating, or remove the ones nothing reads | 0.4-0.6k | 0.7k | none, but **the counter widths belong to the I-6 fault-status / SoC register design** | benches that read counts | low (decide inside I-6) |
| B2 | L2 wrapper `int extension` (0..5) -> 3 bits; verifier 32-bit timer -> 17 bits (TIMEOUT_CYCLES = 100,000) | about 0.1k | about 0.1k | none | L2 / verifier benches | low |
| **A2** | Merge the verifier KMAC (E4) into the L2 engine (E3) at tile 4 | 4.5-6k (less if A5 is done first: about 4.5k) | 5k | **changes signed bounds** (Q, P, C4, L2 verdict, RTT) | l2e, arbiter, sf1, s2, revoke, C4 | high |
| D1 | Measurement shifts the controller's config / imem copy in place instead of its own | about 0 | 1.0k | none | measurement | low; FF only, low value |
| C1 | Mesh / router simplification (allocator, crossbar, credit) | unknown; needs its own study | | transport | NOC-1..3 re-earn | high; **protected RTL; not now** |
| X | Keccak round folding (2 cycles / round) | about 1.0-1.3k per core | | **doubles permutation latency**; bounds change | everything crypto | high; not now |
| A4 | Remove duplicate message buffers | 0 | about 2k | none | | FF only, rejected |

## 3. What the combinations are worth (est., routed; from 43,935)

| Package | Est. LUT after | Headroom to 47,550 | Signed-bound changes |
|---|---|---|---|
| T1 + A1 (the earlier choice) | 41.0-41.8k | 5.7-6.5k | none |
| **T1 + A1 + A6 + A5** | **33.5-35.5k** | **12-14k** | **none** |
| + A3 + B1 + B2 | 31.5-33.5k | 14-16k | none (B1 inside I-6) |
| + A2 | 27-29.5k | 18-20.5k | yes (Kalash decision) |

**Timing:**
- T1 removes the fanout pattern behind 121 of 123 near-critical endpoints.
- Router 5 (+0.184 ns, 21 levels, protected) stays the limiter.
- A5 / A6 / A1 remove about 6k LUT of crypto placed around tiles 3-4, which should lower congestion. That route-dominated
  router path (75 % route) is the one that might gain, but only a P&R run will tell.

## 4. EQAC review of the new items

- **A6:**
  - **Correctness rests on one bound,** max 135 bytes < rate 136, enforced by `req_len_ok` (pq_measurement.sv). The pad bytes
    the builder writes must equal SHA3 padding for one block: 0x06 at offset len, 0x80 OR-ed at byte 135; when len = 135,
    both land in byte 135 as 0x86.
  - **Required checks:** an equivalence bench across all lengths 7..135 against the existing SHA3 path or the Python
    reference, plus a mutant for the len = 135 combined-pad corner.
  - **Verdict:** CONDITIONAL APPROVAL, with the exhaustive length bench required.
- **A5:**
  - **Hidden dependency:** `state_out` must not change between permutations of one message. It changes only on start or
    reset. With A1 the measurement can start the shared core only between controller phases, never inside a KMAC message;
    the R5 exclusivity check already enforces that.
  - **Mutant to kill:** absorb from a stale or zero state on blocks 1-2.
  - **Verdict:** CONDITIONAL APPROVAL; a mutant must be killed by the KATs.
- **B1:** it is really a requirements question. Counter widths should be decided when I-6 defines the fault-status register
  map, so they are not changed twice.
- **A2:** unchanged. It is now much less necessary: T1 + A1 + A6 + A5 already gives 12-14k headroom without touching a bound.

## 5. Recommendation (production readiness gate for the scout)

- **The scout is complete.** All blocks are attributed, and estimates are labelled.
- **Recommended Step B re-sequence:**
  - **S3 = T1 + A1 + A6 + A5,** with no signed-bound changes, about -8.5 to -10.5k LUT (est.);
  - then A3;
  - B1 inside I-6;
  - A2 only if the budget still needs it after the measurement.
- **Status of the work already started:** the S3 T1 + A1 variants, generator, bench and three mutants exist **in scratch
  only**. They are not registered and not run through the harness. If the re-sequence is approved, A6 and A5 are added to
  the same S3 contract **before** any registered run.
- **Verdict:** **APPROVED WITH MINOR OBSERVATIONS** to move to Step B with the re-sequenced package.
