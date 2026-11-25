# PQ-Attest Engineer 4 — I-9 Integration: Python Reference Model Extension Report

> **Verification Classification:** Python reference-model extension and Python-model mutation analysis for the signed I-9 integration contract. Existing Kalash I-9 XSim evidence is used as behavioral reference where applicable. This work does not constitute new RTL simulation, formal proof or hardware validation.

---

## 1. Executive Summary

This report documents the implementation and verification of the **I-9 Integration Reference Model** within the Engineer 4 Python verification framework, addressing the requirements established by the signed I-9 integration contract (**M-F1 revision 8**) and confirmed in Kalash's November 6, 2026 review letter (`E4_RESPONSE_20261106.md`).

The I-9 integration release introduces four key architectural extensions over the baseline P7 architecture:
1. **NI Slot Timeout and Release Model:** Two outstanding transaction slots (`N_OUTSTANDING = 2`) with 1-bit tags. A deterministic slot timeout of **600 cycles** (`NI_SLOT_TIMEOUT = 600`) frees a slot whose response has not arrived, permitting immediate reuse by subsequent requests.
2. **Late and Stale Response Drop Policy:** Late responses arriving after slot timeout and stale responses arriving after tag reuse are deterministically dropped and **never delivered to the application** (`app_rx`).
3. **`app_rx` Memory-Response Export Restriction:** Memory responses (`MEM_RD_RESP`, `MEM_WR_RESP`) are restricted to export strictly to **CPU tiles 0 and 3**. Responses addressed to tiles 1, 2, 4, and 5, as well as non-memory response packets, are excluded from the `app_rx` export path.
4. **Tile-2 BRAM 16 KB Window & Byte-Lane Write-Enables:** Tile-2 remote memory implements a strict **16 KB window** (`0x2200_0000` to `0x2200_3FFF`), accepting boundary address `0x2200_3FFC` and rejecting out-of-window address `0x2200_4000`. Memory writes are controlled by 4 individual byte-lane write-enables (`wstrb[3:0]`), with unselected byte lanes strictly preserving prior memory state.

---

## 2. I-9 Contract & Testbench Provenance

### Source & Evidence Registry

- **Git Revision:** `b62b78de2005d67539a9941d9a9c65bb4497db5f`
- **I-9 Integration Contract:** M-F1 revision 8 (referenced in `PQ_Attest_S4_Evidence/01_s4_source_list/dual_lane_jobs.json` §11 and `E4_RESPONSE_20261106.md` §5). Note that the historical working-tree document `docs/decisions/M-F1-interface-freeze.md` records revision 4 (`58f24bf5...`), whereas the active signed contract governing I-9 is frozen in the S4 job registry.
- **RTL Testbench Reference:** `tb_i9_integ` (13 named checks, configuration: `TOP = tb_i9_integ`, `CHECKS = 13`, `VERIFIER_TIMEOUT = 3000`, `NI_SLOT_TIMEOUT = 600`, `MEM_ADDR_BITS = 14`).
- **Negative Control Jobs:** 5 negative controls registered in `dual_lane_jobs.json` under increment `I-9`:
  - `i9_mut_no_timeout`: mutant `i9n_no_timeout`, oracle `^\[FAIL\] I9_SLOT_RECOVER`
  - `i9_mut_stale_deliver`: mutant `i9n_stale_deliver`, oracle `^\[FAIL\] I9_STALE_DROPPED`
  - `i9_mut_rx_all`: mutant `i9s_rx_all`, oracle `^\[FAIL\] I9_RX_ACCOUNTED`
  - `i9_mut_bram_lanes`: mutant `i9s_bram_lanes`, oracle `^\[FAIL\] I9_BYTE_LANES`
  - `i9_mut_window_1k`: mutant `i9s_window_1k`, oracle `^\[FAIL\] I9_WINDOW_TOP_OK`

### Source Files & Cryptographic Hashes

| Component | Path | SHA-256 Hash |
| :--- | :--- | :--- |
| Live NI Implementation | `rtl/dual_lane/noc_network_interface_p7.sv` | `80a59a7f9a5cb14f7ae0ba2c3fc196026c7f23e5db489d07268ad618d2426064` |
| Live L2 Auth | `rtl/dual_lane/noc_l2_auth_p7.sv` | `f1833f9cdfe1e78d2f5d04315d3604b86d37986d76a823f63713504678f4f901` |
| Live L2 Pair | `rtl/dual_lane/noc_l2_p7_pair.sv` | `eb24f4f189075a5088659962c110ea89c1093a1966f7a4cf96546174781915e9` |
| Live Subsystem | `rtl/dual_lane/pq_noc_subsystem_p7.sv` | `5d1d482e96051c013f18b7ef65fcead42847aa25c8003be9aa8d8edd09d396a5` |
| NoC Package | `rtl/dual_lane/NOC_PKG.sv` | `e428af103c9a0096f47f9ad97215a33b919dc9035c2a5e9d1255ff9fdd33a7be` |
| P7 NoC Package | `rtl/dual_lane/noc_p7_pkg.sv` | `8a10decc6d39c5b1dcb097f2aa638e8fb348e88d7a2fb85a696083d3a5ffe4f0` |
| S4 Job Registry | `PQ_Attest_S4_Evidence/01_s4_source_list/dual_lane_jobs.json` | `be0669bf7a58aab75314ee39cdc59292d13f2dd799e4fe125f9c879b4272f0f4` |
| I-9 Reference Model | `verification/p7_i9_model.py` | `2ca9b6b20742f66e7d2f49086c022ae4bdcf6e47d64559582c8813597deb5d47` |
| I-9 Test Suite | `verification/tests/test_p7_i9_model.py` | `9256f9115d58eda6081789901f82d7191bbad590f332eeb68ba23556c267e9d5` |

---

## 3. NI Slot Lifecycle and Timeout Semantics

The Network Interface maintains up to two outstanding remote memory transactions:
- **Allocation Policy:** Priority-encoder allocation selects the lowest-numbered free slot (`tx_slot_available`, `tx_alloc_tag = 0` if slot 0 is free, else `1`). If both slots are occupied, allocation returns `None` and backpressure is exerted.
- **Tag Assignment:** The 1-bit transaction tag matches the slot index (`tag = slot_id`).
- **Timeout Duration:** Parameterized by `NI_SLOT_TIMEOUT = 600` clock cycles.
- **Slot Release on Timeout:** When `current_cycle >= alloc_cycle + 600`, the transaction is marked timed-out, recorded in the timed-out registry, and the slot is transitioned from `OCCUPIED` to `FREE`.
- **Slot Independence:** The timeout timer is per-slot. An expiration on slot 0 has zero effect on the countdown or state of active slot 1.
- **Immediate Reuse:** Once released by timeout, the slot is immediately available for new allocations.

---

## 4. Late and Stale Response Classification

The model exposes a comprehensive classification engine for every incoming packet:

| Classification | Condition | Delivery Decision | Drop Reason | Resulting Slot State |
| :--- | :--- | :---: | :---: | :---: |
| `VALID_MATCH` | Matches active transaction tag, expected type, and destination coordinates | `DELIVER`* | `NONE` | `FREE` (slot released) |
| `LATE_TIMED_OUT` | Response arrives after transaction timed out and slot is empty | `DROP` | `SLOT_TIMED_OUT` | `FREE` |
| `STALE_REUSED` | Response belongs to an old transaction whose tag was subsequently reused | `DROP` | `STALE_TAG_REUSED` | `OCCUPIED` (active txn untouched) |
| `UNMATCHED_ALREADY_COMPLETED` | Duplicate response arrives for already completed transaction | `DROP` | `ALREADY_COMPLETED` | `FREE` |
| `INVALID_TAG` | Tag value exceeds slot capacity (`tag >= N_OUTSTANDING`) | `DROP` | `INVALID_TAG_VALUE` | Unchanged |
| `MISMATCHED_SRC` | Arriving source coordinates do not match destination of request | `DROP` | `SRC_DEST_MISMATCH` | `OCCUPIED` |
| `MISMATCHED_TYPE` | Arriving message type does not match expected response type | `DROP` | `MSG_TYPE_MISMATCH` | `OCCUPIED` |
| `NON_MEMORY_TYPE` | Non-memory packet arrives on memory response path | `DROP` | `NON_MEMORY_RESPONSE` | Unchanged |

*\*Delivery of `VALID_MATCH` is conditional upon passing the `app_rx` destination tile export policy.*

---

## 5. `app_rx` Memory-Response Export Policy

The application receive interface (`app_rx`) exports qualified responses:
1. **Eligible Message Types:** Only memory responses qualify:
   - `MSG_MEM_RD_RESP` (`0x1`)
   - `MSG_MEM_WR_RESP` (`0x3`)
2. **Authorized CPU Tiles:** Memory responses are delivered to **CPU tile 0** and **CPU tile 3** ONLY (`AUTHORIZED_APP_RX_CPU_TILES = {0, 3}`).
3. **Unauthorized Destinations:** Responses addressed to tiles 1, 2, 4, and 5 are rejected with drop reason `UNAUTHORIZED_APP_RX_DESTINATION` and `exported_to_app_rx = False`.
4. **Non-Memory Exclusions:** Attestation packets (`MSG_ATTEST_CHALLENGE`, `MSG_ATTEST_RESPONSE`, `MSG_ATTEST_GRANT`, `MSG_ATTEST_REVOKE`) cannot use the memory response export path.

---

## 6. Tile-2 BRAM 16 KB Window

The Tile-2 memory endpoint implements the physical BRAM decode:
- **Base Address:** `0x2200_0000` (Tile 2 memory window: `addr[31:28] == 0x2`, `tile == 0x2`).
- **Window Size:** 16 KB ($16,384\text{ bytes} = 4,096\text{ 32-bit words}$).
- **Window Limits:** `0x2200_0000` (inclusive lower bound) to `0x2200_4000` (strictly exclusive upper bound).
- **Exact Boundary Verifications:**
  - `0x2200_0000`: First valid aligned address (**ACCEPTED**).
  - `0x2200_3FFC`: Last valid aligned word address (**ACCEPTED**).
  - `0x2200_4000`: First address beyond the 16 KB window (**REJECTED** with `BRAM_OUT_OF_BOUNDS`).
- **Alignment Enforcement:** Word accesses require `addr[1:0] == 2'b00`. Misaligned accesses (`0x2200_0001`, `0x2200_0002`, `0x2200_0003`) are rejected with `BRAM_MISALIGNED`.

---

## 7. BRAM Byte-Lane Write-Enable Semantics

Writes are controlled by a 4-bit write strobe (`wstrb[3:0]`):
- `wstrb[0]` controls byte lane 0 (`[7:0]`).
- `wstrb[1]` controls byte lane 1 (`[15:8]`).
- `wstrb[2]` controls byte lane 2 (`[23:16]`).
- `wstrb[3]` controls byte lane 3 (`[31:24]`).
- **Partial-Write Fidelity:** When `wstrb[i] == 1`, lane $i$ takes `wdata[8*i+7 : 8*i]`. When `wstrb[i] == 0`, lane $i$ strictly preserves its prior value.
- **Zero-Strobe Writes:** `wstrb == 0x0` performs an accepted no-op write leaving all 32 bits untouched.
- **Full-Word Writes:** `wstrb == 0xF` updates all 4 byte lanes simultaneously.

---

## 8. Python-Model Mutation Analysis

Eight targeted Python-model mutants were implemented in `verification/p7_i9_model.py` and evaluated:

| Mutant ID | Mutant Symbol | Requirement Tested | Expected Oracle Signature | Test Kill Assertion | Kill Status |
| :---: | :--- | :--- | :--- | :--- | :---: |
| `I9-MUT-01` | `i9n_no_timeout` | NI Slot Timeout Release | `^[FAIL] I9_SLOT_RECOVER` | Slot 0 remained occupied after 600 cycles | **KILLED** |
| `I9-MUT-02` | `i9m_late_deliver` | Late Response Rejection | `^[FAIL] I9_LATE_DROPPED` | Late response after timeout returned DELIVER | **KILLED** |
| `I9-MUT-03` | `i9n_stale_deliver` | Stale Tag Rejection | `^[FAIL] I9_STALE_DROPPED` | Stale response completed active txn on reused tag | **KILLED** |
| `I9-MUT-04` | `i9s_rx_all` | app_rx Tile 0/3 Restriction | `^[FAIL] I9_RX_ACCOUNTED` | Memory response to tile 1 exported to app_rx | **KILLED** |
| `I9-MUT-05` | `i9m_window_inclusive` | 16 KB Exclusive Boundary | `^[FAIL] I9_WINDOW_LIMIT_STRICT` | Access to 0x2200_4000 incorrectly accepted | **KILLED** |
| `I9-MUT-06` | `i9s_window_1k` | 16 KB Capacity Check | `^[FAIL] I9_WINDOW_TOP_OK` | Access to 0x2200_3FFC incorrectly rejected | **KILLED** |
| `I9-MUT-07` | `i9s_bram_lanes` | Byte-Lane Enable Fidelity | `^[FAIL] I9_BYTE_LANES` | Write with wstrb=0x1 overwrote all 4 bytes | **KILLED** |
| `I9-MUT-08` | `i9m_disabled_lanes` | Unselected Lane Preservation | `^[FAIL] I9_LANE_PRESERVE` | Unselected lanes 1..3 zeroed out on partial write | **KILLED** |

**Mutation Score:** **8 / 8 mutants killed (100.0%)**.

---

## 9. Contract-Derived Reference Vectors

Nine reference integration vectors were generated and exported to `verification/generated/p7_i9_vectors.json`:

| Vector ID | Description | Provenance | Result |
| :--- | :--- | :--- | :---: |
| `VEC-I9-01-ALLOC-FULL` | Two transaction slots allocated; third allocation blocked | Contract-derived (M-F1 rev 8 §11) | **PASS** |
| `VEC-I9-02-TIMEOUT-RELEASE` | Slot 0 expires at 600 cycles and is freed while slot 1 remains pending | Contract-derived (M-F1 rev 8 §11 / job: `i9_integ`) | **PASS** |
| `VEC-I9-03-LATE-DROP` | Late response for timed-out slot 0 dropped and not delivered | Contract-derived (M-F1 rev 8 §11 / job: `i9_integ`) | **PASS** |
| `VEC-I9-04-APP-RX-CPU0` | Memory response exported to CPU tile 0 | Contract-derived (M-F1 rev 8 §11) | **PASS** |
| `VEC-I9-05-APP-RX-CPU3` | Memory response exported to CPU tile 3 | Contract-derived (M-F1 rev 8 §11) | **PASS** |
| `VEC-I9-06-APP-RX-TILE1-DROP` | Memory response to non-CPU tile 1 rejected from app_rx | Contract-derived (M-F1 rev 8 §11) | **PASS** |
| `VEC-I9-07-BRAM-BOUNDARY-3FFC` | Tile-2 BRAM word read at 0x2200_3FFC accepted | Contract-derived (E4_RESPONSE_20261106 §5) | **PASS** |
| `VEC-I9-08-BRAM-BOUNDARY-4000` | Tile-2 BRAM word read at 0x2200_4000 rejected | Contract-derived (E4_RESPONSE_20261106 §5) | **PASS** |
| `VEC-I9-09-BRAM-BYTE-LANES-PARTIAL` | Partial write with wstrb=0x5 updates lanes 0 and 2; preserves 1 and 3 | Contract-derived (mem_bram.sv / M-F1 rev 8 §11) | **PASS** |

---

## 10. Regression Suite Results & Traceability

### A. Focused I-9 Test Suite
`python -m pytest verification/tests/test_p7_i9_model.py -v`:
- **40 tests passed, 0 failed** in 0.28s.

### B. Full Verification Test Suite
`python -m pytest verification -q`:
- **323 tests passed, 0 failed** in 9.20s.
- Breakdown: 283 pre-existing tests + 40 new I-9 unit and mutant tests.

### C. One-Command Regression Suite (`python verification/p7_regression.py --full`)
All **15 stages** passed:
- `01_ENV_DISCOVERY`: Git HEAD `b62b78d`, Python 3.13.5 (**PASS**)
- `02_BASELINE_SNAPSHOT`: Baseline SHA-256 recorded for 40 protected files (**PASS**)
- `03_PROTOCOL_EXTRACTION`: Extracted protocol matrix from dual_lane SV sources (**PASS**)
- `04_PROTOCOL_VALIDATION`: Verified frozen architecture invariants (**PASS**)
- `05_PACKET_MODEL_REGRESSION`: 19 passed, 0 failed (**PASS**)
- `06_SECURITY_MODEL_REGRESSION`: 30 passed, 0 failed (**PASS**)
- `07_DIFFERENTIAL_VECTORS`: 12 passed, 0 failed (**PASS**)
- `08_RELEASE_EVIDENCE_RECONCILE`: 12 passed, 0 failed (**PASS**)
- `09_INTEGRATION_SCENARIOS`: 12 passed, 0 failed (**PASS**)
- `10_COVERAGE_AUDIT`: 4 passed, 0 failed (**PASS**)
- `11_MUTATION_ANALYSIS`: 12 passed, 0 failed (**PASS**)
- `12_FULL_PYTEST`: **323 passed, 0 failed** in 10.74s (**PASS**)
- `13_ARTIFACT_VALIDATION`: All generated artifacts validated (**PASS**)
- `14_HISTORICAL_INTEGRITY`: 0 modifications to protected RTL or historical reports (**PASS**)
- `15_FINAL_SUMMARY`: Generated regression summary (**PASS**)

### D. Validation-Only Baselines
- `--validate-only --baseline s4`: **PASS** (6 passed, 0 failed, 9 skipped).
- `--validate-only --baseline nov3`: **PASS** (6 passed, 0 failed, 9 skipped).

### E. Relocatable Output Build
- Full regression with `--repo-root . --data-dir . --out ./build/e4_results --full`: **PASS** (15 passed, 0 failed). Built all 12 artifacts into `--out`.

---

## 11. Deliverables Inventory

| Deliverable | Path | Status |
| :--- | :--- | :---: |
| I-9 Reference Model | `verification/p7_i9_model.py` | Complete |
| I-9 Unit Test Suite | `verification/tests/test_p7_i9_model.py` | Complete (40/40 PASS) |
| I-9 Reference Vectors | `verification/generated/p7_i9_vectors.json` | Complete (9/9 PASS) |
| I-9 Mutation Results | `verification/generated/p7_i9_mutation_results.json` | Complete (8/8 KILLED) |
| Engineering Report | `reports/E4_P7_I9_MODEL_EXTENSION.md` | Complete |

---

## 12. Hardware Disclosures and Final Stop Notice

- **RTL Integrity:** Confirmed zero modifications to `rtl/dual_lane/*` via `git diff rtl/dual_lane`.
- **Harness Integrity:** Confirmed zero modifications to Kalash's acceptance harness.
- **Contract Provenance Note:** The physical SystemVerilog testbench `tb_i9_integ.sv` and the markdown file for `M-F1 rev 8` are not checked into the working repository as independent text files; their authoritative requirements, parameters (`NI_SLOT_TIMEOUT: 600`), and negative-control kill signatures are sourced from `dual_lane_jobs.json` and Kalash's signed review `E4_RESPONSE_20261106.md`.
- **Stop Condition:** As explicitly instructed in Section 15, all work ceases upon completion of Task I-9. No subsequent tasks (D2 64-byte IMEM measurement, latency modeling, measurement-window vectors, link monitoring, report figures, bridge oracle or bridge vectors) have been initiated.

