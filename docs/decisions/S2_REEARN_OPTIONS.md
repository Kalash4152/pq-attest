# Contract sec. 9 re-earn on P7: decisions needed before registration (2026-10-23)

Context:
- I-5 sec. 8 is done: run 135247, 13 / 13 PASS_FRESH.
- Sec. 9 asks for these to be re-run on P7: N-8.1 containment, framing, authorization, N-7.5 finite liveness, a NOC-2 subset (uniform and hotspot at 1/64, 1/8, 1, in both MAC modes, plus the hop probes) and all synthesis.
- All synthesis is already done (B-4).

## What the existing evidence measures

| Jobs | Bench | DUT |
|---|---|---|
| n81_ni_* | tb_ni_n81 (protected) | one production noc_network_interface |
| n81_sys_*, n81_nitb, n81_n6 | tb_noc_n81 (protected), tb_noc_ni, tb_n6_two_tile_stress | mesh + 6 production NIs |
| perf_*, n75_* | tb_noc_perf (generated from the tb_noc_n81 scaffold) | mesh + 6 production NIs, MAC on every packet under PQ_MAC_ON |
| hop_probes_* | tb_noc_hop_probes (scaffold copied from tb_noc_perf) | same |

## What P7 changes for those measurements

- **Per-type MAC:** data types 0-3 are plain and control types 4-7 keep 4 MAC words. The "both MAC modes" NOC-2 axis no longer changes data packets at all.
- **Non-attested tiles:** tiles 0, 1, 2 and 5 refuse control types both ways (CONTROL_ALLOWED = 0). Only tiles 3 and 4 have L2.
- **Ingress:** parsers on every NI port, and the raw port behind the quarantine.

As a result, latencies, throughput, counts and some expected verdicts differ from the rev-6 derivations. Every re-earned job needs a new bench file (the protected benches stay untouched), new frozen counts and a new derivation note.

## Decision 1: DUT level

- **(A) Mesh + 6 noc_network_interface_p7** (CONTROL_ALLOWED as in P7, no L2, no ingress). Closest to the old scaffold, so the derivations port with the fewest changes. It measures the P7 NI and mesh only.
- **(B) The full pq_noc_subsystem_p7.** The real P7 data path (parsers, L2 pass-through on tiles 3/4, gates). More realistic, but every old check has to be re-derived, and traffic generation must go through the tile applications.
- **Recommendation:** (A) for N-8.1 / framing / N-7.5 / hop probes, where the property is NI / mesh-level, and (B) for the NOC-2 subset.

## Decision 2: "both MAC modes" for the NOC-2 subset under P7

- **(i)** PQ_MAC_ON off / on as before. On P7 this only changes control traffic, so data-only loads are identical by construction; report it as such.
- **(ii)** Replace the axis with "control mix 0 % / 10 %" so the MAC cost on the control plane shows up.
- **Recommendation:** (i), with the identity stated in the report, plus one (ii) point.

## Decision 3: authorization re-earn

- **Option:** the P7 subsystem bench (refuse_grant, f234, S2 identity) already covers authorization. Re-earning could mean re-running the old authorization jobs (l3_enforce, security_sec_1_4) ported to P7.
- **Recommendation:** list the old authorization checks and map each one to an existing P7 check; port only the uncovered ones.

## Proposed order once decided

1. One registration group: the ported benches, compile-checked, counts frozen from source.
2. Run one at a time.
3. I-5 gate report.

Nothing in this file is registered. No protected bench is edited.
