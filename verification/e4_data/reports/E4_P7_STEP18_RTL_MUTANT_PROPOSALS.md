# PQ-Attest Engineer 4 — Step 18: Grounded RTL Mutant Proposals & Evidence Reconciliation

**Date:** 2026-11-06  
**Author:** PQ-Attest Engineer 4  
**Reviewer:** Kalash Bheda (Lane 1)  
**Status:** COMPLETE (Reconciled with Lane 1 I-11 Registered Run)  
**Single Source of Truth:** [`verification/generated/p7_rtl_mutant_proposals.json`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/generated/p7_rtl_mutant_proposals.json)  

---

## 1. Executive Summary & Triage Overview

During the November 6 final intake review, Kalash Bheda triaged all 15 Engineer 4 RTL mutant proposals against the 49 existing killed RTL controls in Lane 1 and registered testbenches. The 15 proposals map to real RTL locations and fall into three exclusive triage categories:

- **Implemented in RTL by Lane 1 (I-11):** **3** proposals (`01`, `03`, `10`). These exposed real verification oracle gaps and were registered as live RTL negative controls in run `dual_lane_10_20261106_163900_ff77f562`.
- **Already Covered by Existing Killed Controls:** **9** proposals (`02`, `05`, `06`, `07`, `08`, `09`, `13`, `14`, `15`). These correspond directly to existing negative controls in S2, I-6, I-7, I-9, and I-10.
- **Not a Killable Control:** **3** proposals (`04`, `11`, `12`). These represent protocol-guaranteed invariants, benign specification questions, or architecturally unreachable bounds.

```
Total Proposals: 15
  ├── Implemented by Lane 1 (I-11): 3 (100% killed in registered run)
  ├── Already Covered:              9 (100% killed in baseline runs)
  └── Not a Killable Control:        3 (invariants / unreachable)
```

---

## 2. Oracle-Independence Findings from I-11

A critical verification insight emerged from proposals `01` and `03` during the I-11 intake:

1. **Routing Inversion (`01_ROUTING`, `NOC_XY_ROUTING.sv`):**
   - Mutating XY routing to YX routing previously survived all 414 checks of `tb_noc_hop_probes_p7` because the bench checked hop *counts*, which remain invariant under dimension order reversal.
   - In response, Kalash implemented `tb_i11_noc_spec.sv` with literal coordinate trajectory assertions (`SPEC_XY_*`), killing `i11_mut_yfirst` across all 12 diagonal routing paths.
2. **Attestation VC Inversion (`03_VC_ALLOC`, `NOC_PKG.sv`):**
   - Mapping attestation messages to VC 0 instead of VC 2 previously survived because existing testbenches computed the expected VC dynamically using `message_to_vc()`—the very package function under mutation.
   - Kalash resolved this with literal expected VC constants (`SPEC_VC_ATTEST_4..7`) from M-F1, killing `i11_mut_attest_vc0`.
3. **BRAM Window Overshoot (`10_MEMORY_WINDOW`, `pq_noc_subsystem_p7_i9.sv`):**
   - Previously, only the window shrink direction was controlled. Proposal 10 prompted the addition of `i11_mut_window_over`, killed by `I9_WINDOW_OUT_ERR` when an address with `OFF >= 0x4000` is rejected before reaching the BRAM macro.

---

## 3. Grounded RTL Mutant Proposals & Triage Table

| # | ID | Target RTL File | Category | Triage Outcome | Registered Run / Evidence | Oracle Kill Signature |
|---|---|---|---|---|---|---|
| 01 | `RTL_MUT_01_ROUTING` | `NOC_XY_ROUTING.sv` | Routing | **`implemented`** | dual_lane_10_20261106_163900_ff77f562 (job: i11_mut_yfirst) | Killed by 12 x SPEC_XY_* in tb_i11_noc_spec (every diagonal route fails literal spec assertion). |
| 02 | `RTL_MUT_02_CREDIT` | `noc_credit_counter.sv` | Credit Handling | **`already_covered`** | dual_lane_10_20261029_140104_d9fb229d (job: pfc_wp0_n6_mut_b_t5) | KILLED: Credit underflow / permanent stall detected by credit counter assertion. |
| 03 | `RTL_MUT_03_VC_ALLOC` | `NOC_PKG.sv` | VC Allocation | **`implemented`** | dual_lane_10_20261106_163900_ff77f562 (job: i11_mut_attest_vc0) | Killed by 4 x SPEC_VC_ATTEST_4..7 in tb_i11_noc_spec (literal M-F1 VC table comparison). |
| 04 | `RTL_MUT_04_FIFO_PROTECTION` | `NOC_FIFO.sv` | FIFO Protection | **`not_a_killable_control`** | N-7 / credit benches protocol invariant | N/A (credit flow control never writes a full FIFO). |
| 05 | `RTL_MUT_05_NI_TIMEOUT` | `noc_network_interface_p7_i9.sv` | NI Timeout and Slot Release | **`already_covered`** | dual_lane_10_20261105_145813_9ca6a347 (job: i9_mut_no_timeout) | KILLED by tb_i9_integ: SLOT_RECOVER fails when slot is not autonomously freed after T_SLOT cycles. |
| 06 | `RTL_MUT_06_STALE_RESPONSE` | `noc_network_interface_p7_i9.sv` | Late/Stale Response Handling | **`already_covered`** | dual_lane_10_20261105_145813_9ca6a347 (job: i9_mut_stale_deliver) | KILLED by tb_i9_integ: I9_STALE_DROPPED fails if app_rx_head_valid pulses for expired tag. |
| 07 | `RTL_MUT_07_AUTHENTICATION` | `noc_l2_auth_p7.sv` | Authentication | **`already_covered`** | dual_lane_10_20261029_140104_d9fb229d (jobs: s2_mut_mac_off, i7_mut_tag_off) | KILLED by s2_attacks and i7_mut_tag_off: corrupt tag accepted into secured core. |
| 08 | `RTL_MUT_08_REPLAY_PROTECTION` | `pq_rot_verifier.sv` | Replay Protection | **`already_covered`** | dual_lane_10_20261029_140104_d9fb229d (jobs: s2_mut_epoch_off, i7_mut_tag_off SEC_STALE_EPOCH, i7_mut_l2_epoch_off) | KILLED: SEC_STALE_EPOCH triggered by mismatch in reconstructed KMAC verification digest. |
| 09 | `RTL_MUT_09_AUTHORIZATION` | `noc_attest_gate.sv` | Authorization | **`already_covered`** | dual_lane_10_20261029_140104_d9fb229d (jobs: i6_mut_gate_bypass I6G_RESET_BLOCKED, p7_gate_mut_bypass) | KILLED: Gate violation flag raised on unauthorised flit egress. |
| 10 | `RTL_MUT_10_MEMORY_WINDOW` | `pq_noc_subsystem_p7_i9.sv` | Memory Window | **`implemented`** | dual_lane_10_20261106_163900_ff77f562 (job: i11_mut_window_over) | KILLED by I9_WINDOW_OUT_ERR (out-of-window access correctly caught before reaching BRAM macro). |
| 11 | `RTL_MUT_11_BYTE_ENABLES` | `pq_noc_subsystem_p7_i9.sv` | Byte Enables | **`not_a_killable_control`** | dual_lane_10_20261105_145813_9ca6a347 (job: i9_mut_bram_lanes) | N/A (all-zero wstrb is a specification question, not an established defect; byte-lane mapping is separately killed by i9_mut_bram_lanes). |
| 12 | `RTL_MUT_12_MEASUREMENT_LENGTH` | `pq_measurement_hasher.sv` | Measurement Length | **`not_a_killable_control`** | dual_lane_10_20261029_140104_d9fb229d (job: s8_golden 95/0) | N/A (length greater than 135 bytes is unreachable past K-3). |
| 13 | `RTL_MUT_13_IMEM_64B` | `pq_attest_endpoint.sv` | IMEM Bytes 16-63 | **`already_covered`** | dual_lane_10_20261106_004336_aacf4cd0 (job: i10_mut_window16) | KILLED by tb_i10_d2: digest mismatch when bytes 16..63 are excluded from Keccak sponge absorb. |
| 14 | `RTL_MUT_14_TILE_IDENTITY` | `pq_rot_verifier.sv` | Tile Identity | **`already_covered`** | dual_lane_10_20261029_140104_d9fb229d (jobs: s2_mut_id_off, i7_mut_tag_off SEC_WRONG_IDENTITY) | KILLED: SEC_WRONG_IDENTITY asserted on tile ID alteration. |
| 15 | `RTL_MUT_15_NONCE_HANDLING` | `pq_rot_verifier.sv` | Nonce Handling | **`already_covered`** | dual_lane_10_20261029_140104_d9fb229d (job: i7_mut_nonce_stale) | KILLED: Stale nonce error asserted when previously presented nonce is reused. |

---

## 4. Detailed Proposal Specifications

### Proposal 01: `RTL_MUT_01_ROUTING`
- **Target File:** `NOC_XY_ROUTING.sv`
- **Category:** Routing
- **Intended Defect:** Route Y-dimension before X-dimension on mesh hops.
- **Triage Classification:** `implemented`
- **Review Detail:** Real gap identified by E4: survived every existing bench (hop-probes passed 414/414) because YX preserves hop count.
- **Registered Evidence:** dual_lane_10_20261106_163900_ff77f562 (job: i11_mut_yfirst)
- **Kill Signature:** Killed by 12 x SPEC_XY_* in tb_i11_noc_spec (every diagonal route fails literal spec assertion).
- **Oracle Independence:** Oracle-independence fix: tb_i11_noc_spec checks literal M-F1 coordinate expectations, not derived hop counts.

### Proposal 02: `RTL_MUT_02_CREDIT`
- **Target File:** `noc_credit_counter.sv`
- **Category:** Credit Handling
- **Intended Defect:** Suppress credit return pulse when VC FIFO flit is popped.
- **Triage Classification:** `already_covered`
- **Review Detail:** Already covered by Lane 1 credit loss mutant control.
- **Registered Evidence:** dual_lane_10_20261029_140104_d9fb229d (job: pfc_wp0_n6_mut_b_t5)
- **Kill Signature:** KILLED: Credit underflow / permanent stall detected by credit counter assertion.
- **Oracle Independence:** Existing credit benches assert return balance independently.

### Proposal 03: `RTL_MUT_03_VC_ALLOC`
- **Target File:** `NOC_PKG.sv`
- **Category:** VC Allocation
- **Intended Defect:** Remap ATTESTATION message to VC 0 instead of VC 2 in message_to_vc().
- **Triage Classification:** `implemented`
- **Review Detail:** Real gap identified by E4: survived because existing benches derived expected VC using the same package function under test.
- **Registered Evidence:** dual_lane_10_20261106_163900_ff77f562 (job: i11_mut_attest_vc0)
- **Kill Signature:** Killed by 4 x SPEC_VC_ATTEST_4..7 in tb_i11_noc_spec (literal M-F1 VC table comparison).
- **Oracle Independence:** Oracle-independence fix: tb_i11_noc_spec uses literal M-F1 table constants rather than calling message_to_vc().

### Proposal 04: `RTL_MUT_04_FIFO_PROTECTION`
- **Target File:** `NOC_FIFO.sv`
- **Category:** FIFO Protection
- **Intended Defect:** Remove FIFO full check on push.
- **Triage Classification:** `not_a_killable_control`
- **Review Detail:** Not a killable control: credit flow control never writes a full FIFO.
- **Registered Evidence:** N-7 / credit benches protocol invariant
- **Kill Signature:** N/A (credit flow control never writes a full FIFO).
- **Oracle Independence:** Credit flow control ensures FIFO full condition is unreachable in normal operation.

### Proposal 05: `RTL_MUT_05_NI_TIMEOUT`
- **Target File:** `noc_network_interface_p7_i9.sv`
- **Category:** NI Timeout and Slot Release
- **Intended Defect:** NI slot timeout counter comparison disabled (never expires).
- **Triage Classification:** `already_covered`
- **Review Detail:** Already covered by I-9 negative control.
- **Registered Evidence:** dual_lane_10_20261105_145813_9ca6a347 (job: i9_mut_no_timeout)
- **Kill Signature:** KILLED by tb_i9_integ: SLOT_RECOVER fails when slot is not autonomously freed after T_SLOT cycles.
- **Oracle Independence:** Checks autonomous slot deallocation independently of response arrival.

### Proposal 06: `RTL_MUT_06_STALE_RESPONSE`
- **Target File:** `noc_network_interface_p7_i9.sv`
- **Category:** Late/Stale Response Handling
- **Intended Defect:** Deliver late/stale response arriving after slot timeout.
- **Triage Classification:** `already_covered`
- **Review Detail:** Already covered by I-9 negative control.
- **Registered Evidence:** dual_lane_10_20261105_145813_9ca6a347 (job: i9_mut_stale_deliver)
- **Kill Signature:** KILLED by tb_i9_integ: I9_STALE_DROPPED fails if app_rx_head_valid pulses for expired tag.
- **Oracle Independence:** Monitors app_rx interface for unauthorized pulses following slot retirement.

### Proposal 07: `RTL_MUT_07_AUTHENTICATION`
- **Target File:** `noc_l2_auth_p7.sv`
- **Category:** Authentication
- **Intended Defect:** L2 KMAC authentication tag comparison forced valid.
- **Triage Classification:** `already_covered`
- **Review Detail:** Already covered by S2 and I-7 negative controls.
- **Registered Evidence:** dual_lane_10_20261029_140104_d9fb229d (jobs: s2_mut_mac_off, i7_mut_tag_off)
- **Kill Signature:** KILLED by s2_attacks and i7_mut_tag_off: corrupt tag accepted into secured core.
- **Oracle Independence:** Exhaustive negative vector testbench injects invalid KMAC digests.

### Proposal 08: `RTL_MUT_08_REPLAY_PROTECTION`
- **Target File:** `pq_rot_verifier.sv`
- **Category:** Replay Protection
- **Intended Defect:** Verifier ignores epoch / sequence mismatch.
- **Triage Classification:** `already_covered`
- **Review Detail:** Already covered by I-7 and S-2 controls. Verifier has no separate epoch compare; epoch is cryptographically bound into the expected tag.
- **Registered Evidence:** dual_lane_10_20261029_140104_d9fb229d (jobs: s2_mut_epoch_off, i7_mut_tag_off SEC_STALE_EPOCH, i7_mut_l2_epoch_off)
- **Kill Signature:** KILLED: SEC_STALE_EPOCH triggered by mismatch in reconstructed KMAC verification digest.
- **Oracle Independence:** Epoch freshness is cryptographically embedded into message digest, not tested by an arithmetic comparator.

### Proposal 09: `RTL_MUT_09_AUTHORIZATION`
- **Target File:** `noc_attest_gate.sv`
- **Category:** Authorization
- **Intended Defect:** Attestation gate allows data packets while in reset or unauthorized state.
- **Triage Classification:** `already_covered`
- **Review Detail:** Already covered by I-6 and P-7 gate controls.
- **Registered Evidence:** dual_lane_10_20261029_140104_d9fb229d (jobs: i6_mut_gate_bypass I6G_RESET_BLOCKED, p7_gate_mut_bypass)
- **Kill Signature:** KILLED: Gate violation flag raised on unauthorised flit egress.
- **Oracle Independence:** Gate monitors data transit independently of control state.

### Proposal 10: `RTL_MUT_10_MEMORY_WINDOW`
- **Target File:** `pq_noc_subsystem_p7_i9.sv`
- **Category:** Memory Window
- **Intended Defect:** Allow Tile-2 BRAM accesses outside the 16KB window (OFF >= 0x4000).
- **Triage Classification:** `implemented`
- **Review Detail:** Real gap identified by E4: previously only the window shrink direction was controlled. Implemented as new control in I-11.
- **Registered Evidence:** dual_lane_10_20261106_163900_ff77f562 (job: i11_mut_window_over)
- **Kill Signature:** KILLED by I9_WINDOW_OUT_ERR (out-of-window access correctly caught before reaching BRAM macro).
- **Oracle Independence:** Front-end decodes address bits [31:14] and generates error response without forwarding to BRAM.

### Proposal 11: `RTL_MUT_11_BYTE_ENABLES`
- **Target File:** `pq_noc_subsystem_p7_i9.sv`
- **Category:** Byte Enables
- **Intended Defect:** Commit memory write when wstrb is all-zero (wstrb = 4'b0000).
- **Triage Classification:** `not_a_killable_control`
- **Review Detail:** Not a killable control: all-zero wstrb is a specification question, not an established defect.
- **Registered Evidence:** dual_lane_10_20261105_145813_9ca6a347 (job: i9_mut_bram_lanes)
- **Kill Signature:** N/A (all-zero wstrb is a specification question, not an established defect; byte-lane mapping is separately killed by i9_mut_bram_lanes).
- **Oracle Independence:** Byte lane mapping is tested by reading back partial-word stores.

### Proposal 12: `RTL_MUT_12_MEASUREMENT_LENGTH`
- **Target File:** `pq_measurement_hasher.sv`
- **Category:** Measurement Length
- **Intended Defect:** Accept attestation measurement message with length > 135 bytes.
- **Triage Classification:** `not_a_killable_control`
- **Review Detail:** Not a killable control: length greater than 135 bytes is unreachable past K-3.
- **Registered Evidence:** dual_lane_10_20261029_140104_d9fb229d (job: s8_golden 95/0)
- **Kill Signature:** N/A (length greater than 135 bytes is unreachable past K-3).
- **Oracle Independence:** Unit invalid-length vectors tested in standalone s8_golden bench.

### Proposal 13: `RTL_MUT_13_IMEM_64B`
- **Target File:** `pq_attest_endpoint.sv`
- **Category:** IMEM Bytes 16-63
- **Intended Defect:** Endpoint controller truncates IMEM measurement read length to 16 bytes instead of 64 bytes.
- **Triage Classification:** `already_covered`
- **Review Detail:** Already covered by I-10 D2 negative control.
- **Registered Evidence:** dual_lane_10_20261106_004336_aacf4cd0 (job: i10_mut_window16)
- **Kill Signature:** KILLED by tb_i10_d2: digest mismatch when bytes 16..63 are excluded from Keccak sponge absorb.
- **Oracle Independence:** D2 test vectors require exact 87-byte measurement message hash.

### Proposal 14: `RTL_MUT_14_TILE_IDENTITY`
- **Target File:** `pq_rot_verifier.sv`
- **Category:** Tile Identity
- **Intended Defect:** Truncate or ignore tile ID comparison during attestation verification.
- **Triage Classification:** `already_covered`
- **Review Detail:** Already covered by I-7 and S-2 controls. Verifier has no separate tile ID compare: tile ID is bound directly into KDF personalization string and KMAC tag.
- **Registered Evidence:** dual_lane_10_20261029_140104_d9fb229d (jobs: s2_mut_id_off, i7_mut_tag_off SEC_WRONG_IDENTITY)
- **Kill Signature:** KILLED: SEC_WRONG_IDENTITY asserted on tile ID alteration.
- **Oracle Independence:** Cryptographic identity binding prevents identity substitution without valid key and digest.

### Proposal 15: `RTL_MUT_15_NONCE_HANDLING`
- **Target File:** `pq_rot_verifier.sv`
- **Category:** Nonce Handling
- **Intended Defect:** Verifier accepts repeated nonce from previous challenge (nonce reuse).
- **Triage Classification:** `already_covered`
- **Review Detail:** Already covered by I-7 control. Nonce issuer is deterministic demo logic (no TRNG claim).
- **Registered Evidence:** dual_lane_10_20261029_140104_d9fb229d (job: i7_mut_nonce_stale)
- **Kill Signature:** KILLED: Stale nonce error asserted when previously presented nonce is reused.
- **Oracle Independence:** Verifier tracks issued challenge nonces and rejects duplicates.

---

## 5. Architectural Integrity Disclaimers

- `HARDWARE_VALIDATED=NO`
- `SOC_INTEGRATION_COMPLETE=NO`
- `FORMAL_PROOF=NO`
- `RTL_MODIFICATIONS=0` (Engineer 4 made zero edits to RTL)
- `PYTHON_MUTANTS_ARE_RTL_MUTANTS=NO` (Python mutants are reference model tests; RTL controls were executed and registered by Lane 1)
