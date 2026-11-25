# Evidence package for Engineer 4 (E4_EVIDENCE_20261106): read this first

**From:** Kalash Bheda (Lane 1) · **To:** Engineer 4 · **Date:** 2026-11-06

Here are the eight items you asked for, as the **exact committed versions** behind the 5-6 November registered runs, with
`MANIFEST.json` (source path, run id, job state per file) and `SHA256SUMS.txt`. The repository commit is in `MANIFEST.json`
(`repository_commit`). Please verify the hashes before you start, and quote the package name and commit in every report.

## 1. What is in each folder

| Your item | Folder | Contents |
|---|---|---|
| 1. I-5 gate | `01_I5_gate/` | `reports/I5_GATE_20261029.md` (the round-trip table: 1,204 cycles) |
| 2. Signed M-F1 rev 8 | `02_MF1_rev8_signed/` | `M-F1-rev8-INTEGRATION-DRAFT.md` (status SIGNED 2026-11-05; the file name keeps "DRAFT" for history), the base `M-F1-interface-freeze.md` (rev 1-7) and `DECISION_REGISTER.md` (rows M-F1 rev 8, I9-D1..D7) |
| 3. C4 REVOKE | `03_C4_revoke/` | `S1_GATE_20261023.md` (C4 max 486 cycles, bound 1,500), `P7-INGRESS-REVOCATION-CONTRACT.md`, bench `tb_p7_c4.sv`; the registered re-run `i9r_s3_p7_c4` is in folder 05 |
| 4. Arbiter bounds | `04_arbiter_bounds/` | `D2-peer-slot-deadlock-freedom.md`, `STEP_C_DESIGN_P7_L2_SHARED.md`, `SF-1-l2-busy-drop.md`, `l2_arbiter.sv` (signed bounds P <= 269, Q <= 792, J <= 128 are also quoted in the I-5 gate) |
| 5. Hop probes + round trip | `05_hop_probes_rtt/` | benches `tb_noc_hop_probes_p7.sv`, `tb_n2p7_rtt.sv`; `NOC_PKG.sv` (`N_OUTSTANDING = 2`); registered run `dual_lane_10_20261105_145813_9ca6a347`: `i9r_hop_probes_p7` (414 checks), `i9r_n2p7_rtt`, `i9r_n2p7_matrix`, `i9r_s3_p7_c4` (result.json + simulate.log each); `I9_GATE_20261105.md` |
| 6. E4 final intake | `06_E4_final_intake/` | `E4_FINAL_INTAKE_20261106.md` and the response you received |
| 7. I-11 | `07_I11/` | `tb_i11_noc_spec.sv`, `tb_i9_integ.sv`, `I11_GATE_20261106.md`, registered run `dual_lane_10_20261106_163900_ff77f562` (7 jobs: result.json + simulate.log / stdout.log) |
| 8. I-10 D2 vectors | `08_I10_D2/` | `vectors/d2_k3_64.json/.svh` (registered), generator `scripts/d2_golden.py`, `tb_i10_d2.sv`, `I10_GATE_20261106.md`, registered run `dual_lane_10_20261106_004336_aacf4cd0` (5 jobs) |

Logs (`simulate.log`, `stdout.log`) are the on-disk logs of those registered runs. They are not in git (logs are git-ignored),
so their hashes in this manifest are the reference.

## 2. Instructions for the Step 12 / 13 rebuild

1. **Use only registered numbers.** Tag every number `MEASURED_REGISTERED (run id, job)` or `DERIVED_ANALYTICAL_BOUND (formula +
   inputs)`. No number without a tag. Nothing from your earlier 78-126-cycle model may be reused unless re-derived here.
2. **Inputs to use:**
   - control round trip 1,204 cycles (I-5 table; min = mean = max over 4 attestations, full subsystem);
   - C4 REVOKE maximum 486 cycles, bound 1,500;
   - signed arbiter bounds P <= 269, Q <= 792, J <= 128;
   - per-hop / per-class latency from `i9r_hop_probes_p7`;
   - `N_OUTSTANDING = 2` NI slots;
   - timeouts: BRIDGE_TIMEOUT 4,096 (D7), VERIFIER_TIMEOUT 100,000, NI_SLOT_TIMEOUT 8,192 in the merged build
     (> BRIDGE_TIMEOUT, contract sec. 6).
3. **Worst legitimate CPU wait (contract sec. 5):** tile-3 port held during an attestation (about 1.2k cycles) + NI
   store-and-forward + mesh round trip + memory front-end service. Show the composition and the inputs.
4. **Proposed BRIDGE_TIMEOUT:** above that worst case with a stated margin, and below VERIFIER_TIMEOUT. If your number is below
   4,096, give the margin explicitly; D7 changes only when Kalash accepts it.
5. **Step 13 slot model:** 2 slots (not 4) and the I-9 timeout semantics: a stale slot is dropped and freed, never delivered
   (`tb_i9_integ` checks I9_SLOT_HELD / SLOT_RECOVER / STALE_DROPPED).
6. Regenerate figures 05 / 06 from the rebuilt model.

## 3. Instructions for Step 18 and D2

- **Step 18:** regenerate the list from the JSON only. Use our real file names (sec. 3 of the intake report). Mark each
  proposal as one of:
  - **implemented**: I-11 `i11_mut_yfirst`, `i11_mut_attest_vc0`, `i11_mut_window_over`;
  - **already covered**, naming the killed control;
  - **not a killable control**, with the reason.

  Do not list files that are not in the design (`TRNG_SOURCE.sv`, `pq_kdf_message_builder.sv`).
- **D2:** rename your vector files (for example `vectors/e4_d2_measurements.*`) or read our registered `vectors/d2_k3_64.*`.
  Never write to our file names.

## 4. Ground rules (unchanged)

- Do not modify anything from this package or from the Lane 1 RTL; work on your copies.
- Keep your accepted suite working: we run it as `e4_verification_v2` with frozen counts **387 tests / 15 stages**. If your
  rebuild changes either count, tell us **before** you send it, with the reason, so we can register a new version.
  Never change an existing count silently.
- **Commit your work** and give us the commit id with the next package (your HEAD is still `b62b78d`).
- Classification wording stays: Python model checking. Not RTL simulation, not hardware, not formal.

## 5. What to send back

One zip with:
1. your rebuilt Step 12 / 13 model and report;
2. the corrected Step 18 list;
3. renamed D2 files;
4. updated pytest / regression counts;
5. your commit id;
6. a manifest with SHA-256.

Kalash
