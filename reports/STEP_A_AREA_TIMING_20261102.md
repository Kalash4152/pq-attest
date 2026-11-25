# Step A: area and timing reduction study, 2026-11-02 (measurement and ranking only, no RTL changed)

- **Scope:** Kalash go-ahead for Step A only (2026-11-02). Step B (which candidates to apply) is Kalash's decision.
- **Design:** pq_noc_subsystem_p7, I-5 state, xc7a100tcsg324-1, 20 ns, budget 47,550 LUT.
- **Evidence:**
  - registered run `reports/dual_lane_10_20261023_121951_d99f256c/p7_subsystem_pnr/`: `util_hier_routed.rpt`,
    `worst_paths_routed.rpt`, `routed.dcp`;
  - two read-only reports regenerated from that checkpoint on 2026-11-02 (Vivado 2024.1): `report_timing -slack_lesser_than 0.5
    -nworst 1 -unique_pins` (123 endpoints) and `report_high_fanout_nets -timing`.
- **Not evidence of a fix.** Every saving below is an estimate until a registered run measures it.
- **Hardware / formal:** NO.

## 1. Where the area is (registered routed, 43,935 LUT / 36,102 FF)

| Block | LUT | FF | Notes |
|---|---|---|---|
| **Four Keccak/KMAC engines** | **26,800 (61 %)** | **20,500** | each has its own `keccak_f1600` core: 3,741 LUT + 1,621 FF |
| - E1: endpoint `pq_kmac_share` (tile 3; KDF + tag, already shared) | 6,816 | 5,054 | kmac128 #(32,16,65) |
| - E2: endpoint `pq_measurement` / `sha3_256` (tile 3) | 7,284 (+1,275 wrapper) | 3,492 | SHA3-256 |
| - E3: L2 `l2_kmac_engine` (serves the tile-3 and tile-4 L2 wrappers) | 5,925 | 5,404 | kmac128 #(32,14,88) |
| - E4: verifier `pq_kmac_share` (tile 4) | 6,808 | 4,997 | kmac128 #(32,16,65) |
| Mesh (6 routers) | 10,263 | 1,934 | datapath 4,070 (LUTRAM FIFOs), allocator 3,347, crossbar 1,048; protected RTL |
| Everything else (NIs, L2 wrappers, gates, ingress, controller glue) | about 6,900 | about 13,700 | |

**Per KMAC engine:** keccak_f1600 3,741 (round logic 2,119: theta 1,152, chi 960); kmac_encode 889-1,055; kmac_absorb 368-401;
kmac128 own logic 927-1,619.

**The main finding:** E1 and E2 are both at tile 3 and run **strictly one after the other**. The endpoint sequence is
`S_KDF_*` -> `S_MEAS_*` -> `S_TAG_*` (rtl/dual_lane/pq_attest_protocol.sv:412-664), and E1 is already shared between KDF and
tag under a registered exclusivity check (ks_excl). Yet E2 carries a third full Keccak core that is never busy at the same
time as E1.

## 2. Where the timing is (registered routed: WNS +0.165 ns, WHS +0.013 ns)

123 endpoints have less than 0.5 ns of slack.

| Group | Endpoints < 0.5 ns (< 0.3 ns) | Worst slack | Logic levels | Cause |
|---|---|---|---|---|
| E4 verifier Keccak state | 59 (21) | +0.165 | 1 | `FSM_onehot_fsm_state_reg[0]` drives 1,618 loads; path 19.67 ns, **97 % route** |
| E2 measurement Keccak state | 22 (8) | +0.230 | 1 | same net pattern, 1,618 loads |
| E3 L2 engine Keccak state | 40 (8) | +0.257 | 1 | same net pattern, 1,618 loads |
| Router 5 local VC2 FIFO -> link register | 2 (1) | +0.184 | 21 | real logic depth: FIFO read, allocator, crossbar, link valid (75 % route) |

- **Fanout is the dominant problem:** 121 of 123 near-critical endpoints come from one RTL pattern. In
  `pq_keccak_f1600.sv:81-153`, `fsm_state` selects the next value of the 1,600-bit `state_reg` (load / round / hold), so one
  onehot bit fans out to the whole state. E1 has the same net (fanout 1,618, slack +1.56 ns).
- **The real logic path:** only the router 5 path is genuine depth, and the router RTL is protected.

## 3. Candidates, ranked

| # | Candidate | Expected effect (estimate) | Signed bounds / contracts | Re-verification | Risk |
|---|---|---|---|---|---|
| **T1** | **Replicate the Keccak FSM select** (RTL `max_fanout` / explicit replicated select register in a dual_lane keccak variant, or flow-level `phys_opt -force_replication_on_nets`) | removes 121 / 123 near-critical endpoints; WNS limited next by router 5 (+0.184); area +~100 FF | none (cycle-identical) | crypto KATs + P&R; cycle-identical, so bench counts unchanged | low |
| **A1** | **Share one Keccak core at tile 3 between E1 (KDF + tag) and E2 (measurement)** | about **-2.5 to -3.0k LUT, -1.6k FF** (3,741 core minus a ~800-1,600 LUT 1,600-bit input mux) | none expected: phases are already sequential, no extra cycles if the select is combinational | endpoint unit / sys, s8 golden (ks), dsyn2 measurement equiv, ks_excl + a new exclusivity mutant, n2p7_rtt, f234_p7, l2p7, p7_c4, P&R | medium |
| **A2** | **Merge E4 (verifier) and E3 (L2 engine) at tile 4 into one KMAC behind the existing RoT-priority arbiter** | about **-5 to -6k LUT, -5k FF** (one full kmac128 minus arbitration and a (32,16,88) union) | **changes signed bounds**: engine Q <= 792 / P <= 269, C4 REVOKE (486 of 1,500), L2 verdict 107 cycles, RTT 1,204 | l2e engine + mutants, arbiter bounds + mutants, sf1, s2 attacks, verifier_revoke, p7_c4, n2p7_rtt, P&R | **high** |
| A3 | Specialise `kmac_encode` to the fixed key and custom lengths per instance (message stays variable) | about -0.3 to -0.6k LUT per instance, -1 to -1.5k total; needs a run to confirm | none | KMAC KATs, l2e, endpoint, s8 | low-medium |
| A4 | Drop the duplicate message buffer (kmac_encode and kmac128 both register msg) | FF only, about -0.5 to -0.8k FF per engine; LUT unchanged | none | KMAC KATs | low; **FF is not the budget** (28 %), so low value |
| T2 | Router 5 path (21 levels) | +0.184 -> at least +0.3 needs RTL retiming in a router variant or a floorplan | transport (NOC-1..3 evidence) | full NoC rerun | high; **not proposed now** |

**Projection** (estimates, routed):
- **T1 + A1:** about 41.0-41.5k LUT; WNS about +0.18 ns (router-limited, still below +0.3).
- **T1 + A1 + A2:** about 35.5-36.5k LUT, leaving about 11-12k LUT for I-6 .. I-8 and the CPU bridge.
- **T1 + A1 + A2 + A3:** about 34.5-35.5k LUT.

## 4. EQAC review (red team)

- **T1 (fanout):**
  - **Weakness:** replication only moves the problem if the replicas are placed badly. Vivado's phys_opt already ran
    AggressiveExplore and did not fix it, so explicit RTL replication per state slice (e.g. 25 select copies, one per
    64-bit lane) is more reliable than relying on the tool.
  - **Equivalence:** must be cycle-identical. Proof: unchanged KAT outputs, unchanged bench counts, mutants still killed.
  - **Verdict:** APPROVED for Step B.
- **A1 (tile-3 Keccak share):**
  - **Isolation weakness:** after the KDF, the shared core's `state_reg` holds key-derived state, and the measurement
    wrapper must not be able to read it. `state_out` must be gated to the current owner (as pq_kmac_share already does for
    KDF / tag), and the core loads the measurement's own `state_in` before its first round.
  - **New checks needed:** an exclusivity assertion (owner change only while idle), and a mutant that grants both owners
    at once, which must be killed.
  - **If the select is registered,** the RTT grows by up to 2 cycles per phase, which must be re-measured, not assumed.
  - **Verdict:** CONDITIONAL APPROVAL. Conditions: owner-gated `state_out`, exclusivity assertion and killed mutant, unchanged
    KATs.
- **A2 (tile-4 KMAC merge):**
  - **Mixed trust domains:** L2 link keys and root-derived verifier keys would share one engine. The existing key-live
    mutant (l2e_mut_key_live) shows the key-isolation property is testable, but the scope grows.
  - **Denial of service:** an L2 flood could delay attestation. The RoT-priority arbiter with aging (R7.6a) bounds this, but
    Q, P, C4 and RTT all move.
  - **Changes a signed bound,** which is a CLAUDE.md hard stop: Kalash decides, and a new bound must be written before the
    RTL.
  - **Verdict:** CONDITIONAL APPROVAL as a separate decision, only after A1 has landed and been measured.
- **A3:** worthwhile only after A1 / A2; the saving is uncertain until synthesised.
- **A4:** REJECTED for now (FF is not the constraint).
- **T2:** DEFERRED. It touches protected transport RTL. Re-measure first: after T1 / A1 / A2 the router-5 route delay
  (75 % of its path) may shrink with lower congestion.

## 5. Production readiness gate for Step A

- **Measured and attributed:** area and timing, from registered artefacts. Yes.
- **Ranked with estimates labelled as estimates:** yes.
- **Open blockers:**
  - A2 needs a signed-bound decision;
  - the +0.3 ns merge target is not reachable by T1 + A1 alone (router 5 at +0.184).
- **Verdict: CONDITIONAL APPROVAL to proceed to Step B with T1 + A1.** A2 is a separate Kalash decision.

## 6. Proposed Step B choices for Kalash

1. **T1 + A1 (recommended first):** no signed-bound changes; about -2.5..-3k LUT, timing limited only by router 5.
2. **T1 + A1, then A2:** about -8..-9k LUT in total; A2 needs new signed bounds written before its RTL.
3. **T1 only:** timing fix, no area change.
