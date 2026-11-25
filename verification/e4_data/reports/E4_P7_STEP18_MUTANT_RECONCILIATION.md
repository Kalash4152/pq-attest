# PQ-Attest Engineer 4 — Step 18 RTL Mutant Reconciliation Report

**Date:** 2026-11-06  
**Author:** PQ-Attest Engineer 4  
**Reviewer:** Kalash Bheda (Lane 1, NoC + PQ-Attest)  
**Status:** COMPLETE & RECONCILED  
**Single Source of Truth:** [`verification/generated/p7_rtl_mutant_proposals.json`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/generated/p7_rtl_mutant_proposals.json)  
**Registered Run (I-11):** `dual_lane_10_20261106_163900_ff77f562`

---

## 1. Background & Review Feedback

In the previous handoff, the Step 18 Markdown report and JSON manifest contained discrepancies regarding target source files:
- Target files such as `TRNG_SOURCE.sv` and `pq_kdf_message_builder.sv` were named; however, `TRNG_SOURCE.sv` is not present in this design (the nonce issuer is deterministic demo logic), and KDF logic is partitioned differently.
- BRAM windowing and byte-enable logic reside in `pq_noc_subsystem_p7_i9.sv` (tile-2 front end), not `noc_ingress_quarantine.sv`.
- I-9 NI timeout and slot logic reside in `noc_network_interface_p7_i9.sv`.
- The verifier contains no standalone epoch or tile-ID comparator; both fields are cryptographically bound into the expected KMAC authentication tag.

During the November 6 final intake, Kalash Bheda performed an exhaustive triage of all 15 JSON proposals against Lane 1's 49 existing killed RTL controls. Crucially, Lane 1 implemented proposals 01, 03, and 10 as live RTL controls under registered run `dual_lane_10_20261106_163900_ff77f562` (I-11).

---

## 2. Oracle-Independence Breakthrough (I-11)

Proposals 01 and 03 revealed critical testbench oracle gaps that survived existing testbenches:

1. **Proposal 01 (YX Routing Inversion, `NOC_XY_ROUTING.sv`):**
   - Inverting routing to Y-before-X survived all 414 checks of `tb_noc_hop_probes_p7` because the testbench only verified total hop counts, which remain identical whether routing XY or YX.
   - *Fix:* Kalash introduced `tb_i11_noc_spec.sv`, which tests literal intermediate hop coordinate assertions (`SPEC_XY_*`), killing mutant `i11_mut_yfirst` across all 12 diagonal mesh routes.
2. **Proposal 03 (Attestation VC Inversion, `NOC_PKG.sv`):**
   - Mapping attestation messages to VC 0 instead of VC 2 survived because existing benches derived the expected VC by calling `message_to_vc()`—the exact package function under test.
   - *Fix:* `tb_i11_noc_spec.sv` uses literal constant values directly from the M-F1 specification, killing mutant `i11_mut_attest_vc0` via 4 assertions (`SPEC_VC_ATTEST_4..7`).
3. **Proposal 10 (BRAM Window Overshoot, `pq_noc_subsystem_p7_i9.sv`):**
   - Previously only the window shrink direction was controlled. Proposal 10 added `i11_mut_window_over`, which was verified killed by `I9_WINDOW_OUT_ERR`.

---

## 3. Triage Summary Table

| # | Proposal ID | Target RTL File | Category | Exclusive Classification | Registered Evidence | Killed By / Rationale |
|---|---|---|---|---|---|---|
| **01** | `RTL_MUT_01_ROUTING` | `NOC_XY_ROUTING.sv` | Routing | **`implemented`** | `dual_lane_10_20261106_163900_ff77f562` | 12 x `SPEC_XY_*` in `tb_i11_noc_spec` |
| **02** | `RTL_MUT_02_CREDIT` | `noc_credit_counter.sv` | Credit Handling | **`already_covered`** | `dual_lane_10_20261029_140104_d9fb229d` | `pfc_wp0_n6_mut_b_t5` |
| **03** | `RTL_MUT_03_VC_ALLOC` | `NOC_PKG.sv` | VC Allocation | **`implemented`** | `dual_lane_10_20261106_163900_ff77f562` | 4 x `SPEC_VC_ATTEST_4..7` in `tb_i11_noc_spec` |
| **04** | `RTL_MUT_04_FIFO_PROTECTION` | `NOC_FIFO.sv` | FIFO Protection | **`not_a_killable_control`** | N-7 / Credit protocol invariant | Credit flow control never writes a full FIFO. |
| **05** | `RTL_MUT_05_NI_TIMEOUT` | `noc_network_interface_p7_i9.sv` | NI Timeout / Slots | **`already_covered`** | `dual_lane_10_20261105_145813_9ca6a347` | `i9_mut_no_timeout` in `tb_i9_integ` |
| **06** | `RTL_MUT_06_STALE_RESPONSE` | `noc_network_interface_p7_i9.sv` | Late / Stale Response | **`already_covered`** | `dual_lane_10_20261105_145813_9ca6a347` | `i9_mut_stale_deliver` in `tb_i9_integ` |
| **07** | `RTL_MUT_07_AUTHENTICATION` | `noc_l2_auth_p7.sv` | Authentication | **`already_covered`** | `dual_lane_10_20261029_140104_d9fb229d` | `s2_mut_mac_off`, `i7_mut_tag_off` |
| **08** | `RTL_MUT_08_REPLAY_PROTECTION` | `pq_rot_verifier.sv` | Replay Protection | **`already_covered`** | `dual_lane_10_20261029_140104_d9fb229d` | `i7_mut_tag_off` (`SEC_STALE_EPOCH`), `s2_mut_epoch_off` |
| **09** | `RTL_MUT_09_AUTHORIZATION` | `noc_attest_gate.sv` | Authorization | **`already_covered`** | `dual_lane_10_20261029_140104_d9fb229d` | `i6_mut_gate_bypass`, `p7_gate_mut_bypass` |
| **10** | `RTL_MUT_10_MEMORY_WINDOW` | `pq_noc_subsystem_p7_i9.sv` | Memory Window | **`implemented`** | `dual_lane_10_20261106_163900_ff77f562` | `I9_WINDOW_OUT_ERR` on `i11_mut_window_over` |
| **11** | `RTL_MUT_11_BYTE_ENABLES` | `pq_noc_subsystem_p7_i9.sv` | Byte Enables | **`not_a_killable_control`** | `dual_lane_10_20261105_145813_9ca6a347` | All-zero wstrb is a specification question, not an established defect. |
| **12** | `RTL_MUT_12_MEASUREMENT_LENGTH` | `pq_measurement_hasher.sv` | Measurement Length | **`not_a_killable_control`** | `dual_lane_10_20261029_140104_d9fb229d` | Length greater than 135 bytes is unreachable past K-3. |
| **13** | `RTL_MUT_13_IMEM_64B` | `pq_attest_endpoint.sv` | IMEM Bytes 16–63 | **`already_covered`** | `dual_lane_10_20261106_004336_aacf4cd0` | `i10_mut_window16` in `tb_i10_d2` |
| **14** | `RTL_MUT_14_TILE_IDENTITY` | `pq_rot_verifier.sv` | Tile Identity | **`already_covered`** | `dual_lane_10_20261029_140104_d9fb229d` | `i7_mut_tag_off` (`SEC_WRONG_IDENTITY`), `s2_mut_id_off` |
| **15** | `RTL_MUT_15_NONCE_HANDLING` | `pq_rot_verifier.sv` | Nonce Handling | **`already_covered`** | `dual_lane_10_20261029_140104_d9fb229d` | `i7_mut_nonce_stale` (demo nonce issuer) |

---

## 4. Single Source of Truth Enforcement

- The generator script `verification/p7_rtl_mutant_proposals.py` produces `verification/generated/p7_rtl_mutant_proposals.json`.
- The markdown report `reports/E4_P7_STEP18_RTL_MUTANT_PROPOSALS.md` is strictly generated from `p7_rtl_mutant_proposals.json`, ensuring absolute consistency between documentation and machine-readable manifests.
- Python tests in `verification/tests/test_p7_rtl_mutant_proposals.py` (4/4 passed) validate that every proposal links to an existing RTL source file, contains valid classification enums, and matches Kalash's exact triage breakdown (3 implemented, 9 already covered, 3 not killable).

---

## 5. Architectural Integrity Disclaimers

- `HARDWARE_VALIDATED=NO`
- `SOC_INTEGRATION_COMPLETE=NO`
- `FORMAL_PROOF=NO`
- `RTL_MODIFICATIONS=0`
- `PYTHON_MUTANTS_ARE_RTL_MUTANTS=NO`
- `SYNTHETIC_STIMULUS_IS_RTL_EVIDENCE=NO`

