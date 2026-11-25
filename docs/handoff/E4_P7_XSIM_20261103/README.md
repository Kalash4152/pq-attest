# P7 XSim results for Engineer 4 (Arnav): release DUAL_LANE_10_20261103

From Lane 1 (Kalash). Vivado/XSim 2024.1, xc7a100tcsg324-1, 20 ns. All registered results come from one harness run on one
source identity: `reports/dual_lane_10_20261103_140235_46039411` (release regression, I-8 N-12; commit 19f06a0 registry,
release f99e0d5). HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

## 1. Results for the benches you asked about (`summary.tsv`)

| Bench | Registered job | Kind | CHECKS | ERRORS | RESULT |
|---|---|---|---|---|---|
| tb_l2p7_equiv | rel_s3_l2p7_equiv | positive | 2425 | 0 | PASS |
| tb_p7_gate_data | rel_p7_gate_data | positive | 4 | 0 | PASS |
| tb_p7_gate_data | rel_p7_gate_mut_control_allowed | control: CONTROL_ALLOWED forced 1 | 4 | 4 | FAIL = mutant KILLED (expected) |
| tb_p7_gate_data | rel_p7_gate_mut_bypass | control: plain-tile gate bypassed | 4 | 4 | FAIL = mutant KILLED (expected) |
| tb_p7_refuse_grant | rel_i6_p7_refuse_grant | positive | 12 | 0 | PASS |
| tb_p7_c4 | rel_s3_p7_c4 | positive | 18 | 0 | PASS |
| tb_ni_n81_p7 | rel_n81p7_ni_t0w16 / t0w1 / t3w16 / t3w1 | positive (4 builds) | 126 / 126 / 123 / 122 | 0 | PASS |
| tb_p7_ingress | rel_i6_p7_ingress | positive | 39 | 0 | PASS |
| tb_l2_kmac_engine | rel_s3_l2e_engine | positive (registered KMAC128 evidence) | 8020 | 0 | PASS |
| **kmac_tb** (KMAC_TB) | none: **scratch run, not registered** | positive | 11 tests | 0 | STAGE 3 PASS |
| tb_i7_sec | rel_i7_sec | PQ-4 SEC-1..4 security matrix | 30 | 0 | PASS |
| tb_pq_full_chain_p7 | rel_i7_full_chain | PQ-5 full chain, non-demo | 21 | 0 | PASS |

`kmac_tb` is not in the registry; it was run once in a scratch project on the release KMAC sources (list in
`logs/SCRATCH_kmac_tb/sources.txt`). Treat it as an observation, not registered evidence.

## 2. What is in this folder

- `logs/<job>/simulate.log` (full transcript with every `[PASS]` / `[FAIL]` line, CHECKS, ERRORS, RESULT), `compile.log`,
  `elaborate.log`, `result.json` (harness verdict and source identity).
- `logs/<job>/*.bat` and `*.prj`: the exact xvlog / xelab / xsim commands and file order XSim used.
- `sources/`: every RTL, bench and include file those jobs compiled, paths kept; `sources_sha256.tsv` hashes them. Also
  the I-6 / I-7 contracts, gate reports and the release manifest.
- **No waveforms (.wdb):** no positive scenario failed, and the harness runs with signal logging off. The only failing
  runs are the deliberate controls (mutants), which fail by design. I can produce a .wdb for any scenario on request.

## 3. RTL changes since the last project ZIP (important for your differential vectors)

All P7 changes are in `rtl/dual_lane/` (protected production files untouched):

1. **S3 (area):** Keccak FSM select replicated per lane (cycle-identical); one Keccak shared at tile 3 by the KDF / tag
   KMAC and the measurement SHA3; measurement SHA3 specialised to one block. Outputs and latency are unchanged (golden vectors
   plus an exhaustive 33,809-check equivalence bench). Files: `pq_keccak_f1600.sv`, `kmac_128_xp.sv`, `SHA3_256_xp.sv`,
   `pq_kmac_share_xp.sv`, `pq_measurement_xp.sv`, `pq_attest_protocol_s3.sv` (replacing `pq_attest_protocol.sv` in the list).
2. **I-6 (NOC-4):**
   - **memory window moved to `A[31:28] == 4'h2`: use `0x2200_0100`** (was `0x8200_0100`; an `0x8...` access now gets the
     error reply, ctl bit 10). The `*_i6` benches are the old ones with only this address changed;
   - verifier: endpoint BUSY (status 3) is **retried up to 3 times with the same challenge**, the 4th BUSY or any other
     non-1 status fails closed (REVOKE); new output `fail_reason` (8 timeout, 9 status != 1, 10 malformed, 11 measurement,
     12 tag);
   - endpoint K-3: `config_len` / `imem_len` must be 16 / 16, otherwise status 5 (malformed);
   - subsystem: new input `trusted_clear` (tie 0 if unused) and fault-status outputs (`fault_sticky`, `fault_count`,
     `fault_source`, `fault_operation`, `fault_reason`, `fault_epoch`); the verifier's failure / timeout blocks tile 3's gate
     directly;
   - gate: new outputs `fault_event`, `fault_source`, `fault_operation`.
3. **I-7:** bench-only hooks under `TB_INJECT` (no logic when `TB_INJECT = 0`).

So vectors built for the old ZIP must be regenerated for: the 0x2 window, BUSY handling (retry, not immediate revoke),
the K-3 lengths, and the new subsystem ports.

## 4. Your 14 differential scenarios

These results are not yet mapped to your 14 scenarios: I don't have your generated vectors or the mapping. Send
the vectors (or the generator), the scenario table, and which bench each scenario targets. I'll run them on the release
RTL in Vivado 2024.1 and return the XSim logs. `tb_i7_sec` (attack matrix: wrong tag / measurement / key / identity, stale epoch,
attestation and L2 replay, nonce substitution, error response, imem substitution, forged SPOOF response, truncated
challenge, status-clear misuse, concurrent SPOOF) may already cover several of them; its log is in `logs/rel_i7_sec`.

## 5. Second, independent run inside the Vivado project (2026-11-04)

Kalash re-ran all 35 release benches inside `NOC_PQATTEST.xpr` with `scripts/run_release_all.tcl`: **ALL VERIFIED 35/35**
(each bench checked for RESULT PASS, ERRORS 0, no timeout and CHECKS equal to the frozen count; the one expected-FAIL
control, n81p7_long_n0, failed exactly as specified). Table: `project_run/release_project_sims.txt`; the logs of the
benches you asked about are in `project_run/<simset>/simulate.log`. The release bitstreams built afterwards meet timing
(accurate-area image 38,168 LUT, WNS +0.368 ns); not run on hardware.

## 6. How these were run

- Registered: `python scripts/dual_lane.py run --select rel` (all release jobs; one isolated XSim project per job).
- In the Vivado project `NOC_PQATTEST.xpr`: each release bench is a simulation set `dl_rel_<job>`; in the Tcl console
  `dl_sim rel_<job>` (e.g. `dl_sim rel_s3_p7_c4`), `dl_list` lists them.
- Defines: P7 benches compile with `PQ_MAC_ON`; include dirs per bench as in the `.prj` files.
- Scripts in `scripts/`: `run_release_all.tcl` (project run + verification + bitstreams), `release_expected.tcl` (frozen
  counts, controls), `update_NOC_PQATTEST_xpr.tcl` (project simulation sets), `dual_lane.py` / `dual_lane_export.tcl`
  (the registered harness).
