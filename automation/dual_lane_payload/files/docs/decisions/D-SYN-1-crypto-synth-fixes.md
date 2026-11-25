# D-SYN-1 — crypto RTL synthesizability fixes (rtl/dual_lane variants only)

**Decided:** Kalash, 2026-10-20. **Trigger:** the first I-4 (PQ-3) run, `dual_lane_10_20261020_114804_a3338659`.
All five OOC tops were INVALID because Vivado 2024.1 `synth_design` rejected the crypto RTL. That run is kept as
history and is never relabelled.

**Plain statement:** before D-SYN-1 the crypto RTL (Keccak, SHA3, KMAC, KDF, measurement, attestation tag, controller)
was **simulation-verified only** and had **never been synthesized**.

## Rule

The protected production files (`NOC_PQATTEST.srcs/sources_1/new/*`, hash-pinned in
`automation/dual_lane_payload/baseline_before.json`; 48 files) are **never written**. Every fix is a variant in
`rtl/dual_lane/` with:
- the original module name;
- an entry in `rtl/dual_lane/variant_provenance.json` (base and variant sha256);
- an explicit source list that uses the variant **instead of** the original (the duplicate-name preflight rejects both
  in one list);
- an equivalence check against the original before any evidence run.

## Root causes and fixes

| # | File:line (original) | Synth error | Root cause | Fix (variant) |
|---|---|---|---|---|
| 1 | `pq_keccak_iota.sv:74` | [Synth 8-280] expression must be constant: first argument to `$isunknown` | An immediate `assert` inside `always_comb` calls `$isunknown`, which is simulation-only, and the block is not guarded from synthesis | `rtl/dual_lane/pq_keccak_iota.sv`: wrap that assertion block in `` `ifndef SYNTHESIS `` / `` `endif ``. No other change |
| 2 | `SHA3_PAD.sv:19` | [Synth 8-3380] loop condition does not converge after 2000 iterations | `for (int i = valid_bytes; i < RATE_BYTES; i++)`: the loop starts at a runtime signal, so synthesis cannot unroll it | `rtl/dual_lane/SHA3_PAD.sv`: `for (int i = 0; i < RATE_BYTES; i++) if (i >= valid_bytes) padded_block[i*8 +: 8] = 8'h00;`. The domain byte (`SHA3_DOMAIN` at `valid_bytes`) and the final `1'b1` at bit `(RATE_BYTES-1)*8+7` are exactly as before, under the same `is_final` / `valid_bytes < RATE_BYTES` conditions |

Neither is a functional bug: the simulated behaviour is unchanged. Both are simulation-only coding constructs.

## Equivalence (before any evidence run)

- **sha3_pad:** exhaustive bench `tb_dsyn1_sha3_pad_equiv` compares the original (a TB-only copy renamed
  `sha3_pad_orig_dsyn1`, generated from the hash-checked protected file) with the variant over the whole input port:
  - every `valid_bytes` value of the port, 0..255 (this includes the 0..136 range);
  - both values of `is_final`;
  - 64 random blocks plus an all-zero and an all-0xFF block per combination.

  Count frozen before the run.
- **keccak_iota:** the diff against the original touches only the `` `ifndef SYNTHESIS `` / `` `endif `` lines (checked
  by script). Bench `tb_dsyn1_iota_equiv` elaborates the variant and compares it with a renamed original copy for every
  `round` value of the port and random states. Count frozen before the run.

## Further errors

Vivado stops at the first failing module, so `synth_design -rtl` (elaboration only, outside the repo, not evidence)
is run on each of the five variant source lists. Any further error gets a row in the table above, a variant and an
equivalence check, repeated until all five elaborate clean.

## Regression on the variant lists (XSim)

- Registered jobs, frozen counts unchanged: s8_golden 95/0, the 7 controller mutants, the control, pq_endpoint_unit
  275/0 and pq_endpoint_sys 37/0.
- Legacy SHA3 / KMAC / Keccak / KDF / measurement / tag known-answer benches: these use a pre-scheduler output format,
  so they run through a harness on the variant lists. Their PASS/FAIL line sets are compared with the historical stage
  logs, and they are reported as harness runs, not scheduler evidence.

Then `--select ooc` (I-4) is rerun one job at a time under the synthesis gate (≥ 2.0 GB free + pagefile ≥ 8 GB).
