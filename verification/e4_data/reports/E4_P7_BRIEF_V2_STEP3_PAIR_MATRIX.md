# PQ-Attest Engineer 4 — Brief v2 Step 3: Directed Pair Matrix Report

**Date:** 2026-11-06  
**Author:** Engineer 4 (Python Verification Team)  
**Status:** COMPLETE (Structural Verification Passed)  
**Target Architecture:** PQ-Attest P7 Dual-Lane 3×2 Mesh Topology  
**Git HEAD Revision:** `b62b78de2005d67539a9941d9a9c65bb4497db5f`  

---

## 5.1 Objective and Scope

The objective of Brief v2 Step 3 is to implement and validate the complete six-tile directed communication pair matrix for the PQ-Attest architecture using the authoritative SystemVerilog RTL source declarations and the Engineer 4 Python verification framework.

### Scope
- **Matrix Generation:** Enumerate all $N(N - 1) = 6 \times (6 - 1) = 30$ legal directed ordered pairs $(src, dest)$.
- **Self-Pair Rejection:** Explicitly detect, reject, and count all 6 self-pairs where $src == dest$.
- **Reverse-Direction Distinction:** Ensure reverse-direction ordered pairs (e.g., $0 \to 1$ vs $1 \to 0$) are maintained as separate, distinct communication flows with distinct identifiers and routing paths.
- **Route Oracle Integration:** Reconcile route metadata directly with the authoritative RTL dimension-order XY routing logic (`NOC_XY_ROUTING.sv`) and the Python reference model (`xy_route_oracle.py`).
- **Classification:** This is a **Python-level structural verification task**. It establishes topological and routing invariants and does not claim independent RTL simulation or physical hardware validation.

---

## 5.2 Topology Provenance

The 3×2 mesh topology, tile mapping, coordinates, and ports are directly parsed from the authoritative SystemVerilog package declarations in the checked-out repository.

### Inspected Authoritative RTL Sources

| File Path | SHA-256 Digest | Authoritative Role |
|---|---|---|
| `rtl/dual_lane/NOC_PKG.sv` | `e428af103c9a0096f47f9ad97215a33b919dc9035c2a5e9d1255ff9fdd33a7be` | Defines `MESH_X=3`, `MESH_Y=2`, `NUM_TILES=6`, `tile_id_e`, `coord_t`, `tile_to_coord()`, `coord_to_tile()`, and `port_exists()` |
| `NOC_PQATTEST.srcs/sources_1/new/NOC_XY_ROUTING.sv` | `6b92bf51f142279a37272372bbdda75b1412ac930772dd17ded3d41c454d7416` | Implements dimension-order XY routing logic: X-first (EAST/WEST), then Y (SOUTH/NORTH), then terminal LOCAL |
| `rtl/dual_lane/noc_p7_pkg.sv` | `8a10decc6d39c5b1dcb097f2aa638e8fb348e88d7a2fb85a696083d3a5ffe4f0` | P7 protocol extensions and security layer contracts |

### Logical Topology & Tile Coordinate Mapping

The topology consists of a 3×2 2D Cartesian mesh (`MESH_X = 3`, `MESH_Y = 2`):

```
       Row 0 (y=0)       Row 1 (y=1)
Col 0: [Tile 0: CPU0  ]  [Tile 3: CRYPTO]
Col 1: [Tile 1: CPU1  ]  [Tile 4: RoT   ]
Col 2: [Tile 2: MEMORY]  [Tile 5: SPOOF ]
```

| Tile ID | RTL Identifier | Architectural Role | Coordinates $(x, y)$ | Attestable Role | Permitted Gate Role |
|:---:|:---:|:---:|:---:|:---:|:---:|
| **0** | `TILE_CPU0` | CPU Core 0 | $(0, 0)$ | No | Insecure Initiator |
| **1** | `TILE_CPU1` | CPU Core 1 | $(1, 0)$ | No | Insecure Initiator |
| **2** | `TILE_MEMORY` | Shared SRAM / Peripherals | $(2, 0)$ | No | Memory Target Endpoint |
| **3** | `TILE_CRYPTO` | Attestable Accelerator | $(0, 1)$ | **Yes** | Dynamic Gate Target (Needs RoT Grant) |
| **4** | `TILE_ROT` | Root of Trust | $(1, 1)$ | **Yes** (Master) | Trusted Security Authority |
| **5** | `TILE_SPOOF` | Adversarial / Test Endpoint | $(2, 1)$ | No | Insecure Initiator / Adversary |

---

## 5.3 Complete Directed Pair Matrix

All 30 legal directed pairs are generated deterministically in ordered representation $(src, dest)$ with deterministic pair identifiers `T{src}_TO_T{dest}`:

| Pair ID | Source | Destination | Source Coordinates | Destination Coordinates | Route | Status |
|---|---|---|---|---|---|---|
| `T0_TO_T1` | CPU0 (T0) | CPU1 (T1) | (0,0) | (1,0) | EAST | VALID |
| `T0_TO_T2` | CPU0 (T0) | MEMORY (T2) | (0,0) | (2,0) | EAST -> EAST | VALID |
| `T0_TO_T3` | CPU0 (T0) | CRYPTO (T3) | (0,0) | (0,1) | SOUTH | VALID |
| `T0_TO_T4` | CPU0 (T0) | RoT (T4) | (0,0) | (1,1) | EAST -> SOUTH | VALID |
| `T0_TO_T5` | CPU0 (T0) | SPOOF (T5) | (0,0) | (2,1) | EAST -> EAST -> SOUTH | VALID |
| `T1_TO_T0` | CPU1 (T1) | CPU0 (T0) | (1,0) | (0,0) | WEST | VALID |
| `T1_TO_T2` | CPU1 (T1) | MEMORY (T2) | (1,0) | (2,0) | EAST | VALID |
| `T1_TO_T3` | CPU1 (T1) | CRYPTO (T3) | (1,0) | (0,1) | WEST -> SOUTH | VALID |
| `T1_TO_T4` | CPU1 (T1) | RoT (T4) | (1,0) | (1,1) | SOUTH | VALID |
| `T1_TO_T5` | CPU1 (T1) | SPOOF (T5) | (1,0) | (2,1) | EAST -> SOUTH | VALID |
| `T2_TO_T0` | MEMORY (T2) | CPU0 (T0) | (2,0) | (0,0) | WEST -> WEST | VALID |
| `T2_TO_T1` | MEMORY (T2) | CPU1 (T1) | (2,0) | (1,0) | WEST | VALID |
| `T2_TO_T3` | MEMORY (T2) | CRYPTO (T3) | (2,0) | (0,1) | WEST -> WEST -> SOUTH | VALID |
| `T2_TO_T4` | MEMORY (T2) | RoT (T4) | (2,0) | (1,1) | WEST -> SOUTH | VALID |
| `T2_TO_T5` | MEMORY (T2) | SPOOF (T5) | (2,0) | (2,1) | SOUTH | VALID |
| `T3_TO_T0` | CRYPTO (T3) | CPU0 (T0) | (0,1) | (0,0) | NORTH | VALID |
| `T3_TO_T1` | CRYPTO (T3) | CPU1 (T1) | (0,1) | (1,0) | EAST -> NORTH | VALID |
| `T3_TO_T2` | CRYPTO (T3) | MEMORY (T2) | (0,1) | (2,0) | EAST -> EAST -> NORTH | VALID |
| `T3_TO_T4` | CRYPTO (T3) | RoT (T4) | (0,1) | (1,1) | EAST | VALID |
| `T3_TO_T5` | CRYPTO (T3) | SPOOF (T5) | (0,1) | (2,1) | EAST -> EAST | VALID |
| `T4_TO_T0` | RoT (T4) | CPU0 (T0) | (1,1) | (0,0) | WEST -> NORTH | VALID |
| `T4_TO_T1` | RoT (T4) | CPU1 (T1) | (1,1) | (1,0) | NORTH | VALID |
| `T4_TO_T2` | RoT (T4) | MEMORY (T2) | (1,1) | (2,0) | EAST -> NORTH | VALID |
| `T4_TO_T3` | RoT (T4) | CRYPTO (T3) | (1,1) | (0,1) | WEST | VALID |
| `T4_TO_T5` | RoT (T4) | SPOOF (T5) | (1,1) | (2,1) | EAST | VALID |
| `T5_TO_T0` | SPOOF (T5) | CPU0 (T0) | (2,1) | (0,0) | WEST -> WEST -> NORTH | VALID |
| `T5_TO_T1` | SPOOF (T5) | CPU1 (T1) | (2,1) | (1,0) | WEST -> NORTH | VALID |
| `T5_TO_T2` | SPOOF (T5) | MEMORY (T2) | (2,1) | (2,0) | NORTH | VALID |
| `T5_TO_T3` | SPOOF (T5) | CRYPTO (T3) | (2,1) | (0,1) | WEST -> WEST | VALID |
| `T5_TO_T4` | SPOOF (T5) | RoT (T4) | (2,1) | (1,1) | WEST | VALID |

All 15 unordered tile pairings produce 2 distinct directed flows with distinct reverse paths.

---

## 5.4 Self-Pair Rejection Results

All 6 diagonal self-pairs where $src == dest$ were submitted to the pair generator and independently asserted to fail validation with `SelfPairRejectedError`:

| Attempted Self-Pair | Source Role | Destination Role | Generator Outcome | Rejection Detail |
|:---:|:---:|:---:|:---:|---|
| `0 -> 0` | CPU0 | CPU0 | **REJECTED** | `SelfPairRejectedError: source tile 0 == destination tile 0` |
| `1 -> 1` | CPU1 | CPU1 | **REJECTED** | `SelfPairRejectedError: source tile 1 == destination tile 1` |
| `2 -> 2` | MEMORY | MEMORY | **REJECTED** | `SelfPairRejectedError: source tile 2 == destination tile 2` |
| `3 -> 3` | CRYPTO | CRYPTO | **REJECTED** | `SelfPairRejectedError: source tile 3 == destination tile 3` |
| `4 -> 4` | RoT | RoT | **REJECTED** | `SelfPairRejectedError: source tile 4 == destination tile 4` |
| `5 -> 5` | SPOOF | SPOOF | **REJECTED** | `SelfPairRejectedError: source tile 5 == destination tile 5` |

**Total Self-Pairs Rejected:** 6 of 6 (100% rejection rate). No self-pairs leaked into the generated matrix.

---

## 5.5 Coverage Calculations

The theoretical number of directed pairs on an $N$-node network with self-communication forbidden is:
$$N \times (N - 1) = 6 \times (6 - 1) = 30$$

### Coverage Metrics Summary

| Metric | Required / Expected Value | Measured Value | Audit Outcome |
|---|:---:|:---:|:---:|
| **Expected Legal Directed Pairs** | 30 | 30 | EXACT MATCH |
| **Actual Generated Pairs** | 30 | 30 | EXACT MATCH |
| **Unique Generated Pairs** | 30 | 30 | EXACT MATCH |
| **Missing Legal Pairs** | 0 | 0 | ZERO DEFECTS |
| **Duplicate Legal Pairs** | 0 | 0 | ZERO DEFECTS |
| **Accepted Self-Pairs** | 0 | 0 | ZERO DEFECTS |
| **Directed Pair Coverage** | 100.0% | 100.0% | **COMPLETE** |

The coverage evaluator strictly penalizes coverage if any missing, duplicate, or self-pair is observed.

---

## 5.6 Test Results

All new and existing test suites were executed cleanly in the local environment.

### 1. Step 3 Dedicated Test Suite
Command:
```bash
python -m pytest verification/tests/test_p7_pair_matrix.py -v
```
Output:
```
============================= test session starts =============================
platform win32 -- Python 3.13.5, pytest-9.0.2, pluggy-1.6.0
rootdir: C:\Users\Arnav Bhandari\PQ_Attest
collected 28 items

verification/tests/test_p7_pair_matrix.py::test_exact_pair_count PASSED  [  3%]
verification/tests/test_p7_pair_matrix.py::test_explicit_self_pair_rejection[0] PASSED [  7%]
verification/tests/test_p7_pair_matrix.py::test_explicit_self_pair_rejection[1] PASSED [ 10%]
verification/tests/test_p7_pair_matrix.py::test_explicit_self_pair_rejection[2] PASSED [ 14%]
verification/tests/test_p7_pair_matrix.py::test_explicit_self_pair_rejection[3] PASSED [ 17%]
verification/tests/test_p7_pair_matrix.py::test_explicit_self_pair_rejection[4] PASSED [ 21%]
verification/tests/test_p7_pair_matrix.py::test_explicit_self_pair_rejection[5] PASSED [ 25%]
verification/tests/test_p7_pair_matrix.py::test_all_six_self_pairs_rejected_count PASSED [ 28%]
verification/tests/test_p7_pair_matrix.py::test_negative_source_tile PASSED [ 32%]
verification/tests/test_p7_pair_matrix.py::test_source_tile_greater_than_max PASSED [ 35%]
verification/tests/test_p7_pair_matrix.py::test_negative_destination_tile PASSED [ 39%]
verification/tests/test_p7_pair_matrix.py::test_destination_tile_greater_than_max PASSED [ 42%]
verification/tests/test_p7_pair_matrix.py::test_invalid_tile_types[0] PASSED [ 46%]
verification/tests/test_p7_pair_matrix.py::test_invalid_tile_types[1] PASSED [ 50%]
verification/tests/test_p7_pair_matrix.py::test_invalid_tile_types[None] PASSED [ 53%]
verification/tests/test_p7_pair_matrix.py::test_invalid_tile_types[1.5] PASSED [ 57%]
verification/tests/test_p7_pair_matrix.py::test_invalid_tile_types[True] PASSED [ 60%]
verification/tests/test_p7_pair_matrix.py::test_invalid_tile_types[False] PASSED [ 64%]
verification/tests/test_p7_pair_matrix.py::test_invalid_tile_types[invalid_val6] PASSED [ 67%]
verification/tests/test_p7_pair_matrix.py::test_generator_produces_no_duplicates PASSED [ 71%]
verification/tests/test_p7_pair_matrix.py::test_injected_duplicate_detected PASSED [ 75%]
verification/tests/test_p7_pair_matrix.py::test_missing_pair_detection PASSED [ 78%]
verification/tests/test_p7_pair_matrix.py::test_reverse_direction_distinction PASSED [ 82%]
verification/tests/test_p7_pair_matrix.py::test_complete_coverage_metrics PASSED [ 85%]
verification/tests/test_p7_pair_matrix.py::test_coverage_penalization_on_self_pair PASSED [ 89%]
verification/tests/test_p7_pair_matrix.py::test_topology_matches_noc_pkg_declarations PASSED [ 92%]
verification/tests/test_p7_pair_matrix.py::test_dimension_order_xy_route_properties PASSED [ 96%]
verification/tests/test_p7_pair_matrix.py::test_generated_manifest_artifact PASSED [100%]

============================= 28 passed in 0.23s ==============================
```

### 2. Full Verification Suite
Command:
```bash
python -m pytest verification -q
```
Output:
```
........................................................................ [ 27%]
........................................................................ [ 55%]
........................................................................ [ 83%]
...........................................                              [100%]
259 passed in 8.07s
```

### 3. Regression Runner Pipeline
Command:
```bash
python verification/p7_regression.py
```
Output:
```
==============================================================================
  REGRESSION RESULT: PASS (Passed: 15, Failed: 0, Skipped: 0)
==============================================================================
```
All 15 stages passed, including full pytest execution (259/259 passed), baseline artifact validation, and historical file hash integrity checks.

---

## 5.7 Routing Assumptions and Limitations

Route metadata was computed and included for all 30 pairs because an authoritative RTL source of truth and a verified routing oracle exist in the repository:

1. **RTL Source of Truth:**
   - Module: `noc_xy_routing` in `NOC_PQATTEST.srcs/sources_1/new/NOC_XY_ROUTING.sv`
   - Contract: Resolves X dimension completely before resolving Y dimension.
     - `Dx > Cx` $\to$ `PORT_EAST`
     - `Dx < Cx` $\to$ `PORT_WEST`
     - `Dy > Cy` $\to$ `PORT_SOUTH`
     - `Dy < Cy` $\to$ `PORT_NORTH`
     - `Dx == Cx && Dy == Cy` $\to$ `PORT_LOCAL`
2. **Oracle Alignment:**
   - Evaluated using `verification/xy_route_oracle.py`, matching the RTL routing logic hop-for-hop.
3. **Limitations:**
   - Route metadata represents the ideal combinational dimension-order paths without dynamic contention, buffer exhaustion, VC arbitration stalls, or dynamic backpressure.
   - Physical timing and flit latency vary by packet length and network load.

---

## 5.8 Verification Classification

> **The Python pair-matrix generator produced and validated 30 unique directed non-self communication pairs across six tiles. Six self-pairs were explicitly rejected. Routing metadata was included only where supported by the inspected RTL routing contract. This is Python-level structural verification, not independent RTL simulation or hardware validation.**

---

## 5.9 Artifacts Generated

1. [`verification/p7_pair_matrix.py`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/p7_pair_matrix.py): Core pair-matrix generator, validator, and coverage engine.
2. [`verification/tests/test_p7_pair_matrix.py`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/tests/test_p7_pair_matrix.py): 28 unit and negative regression tests covering all requirements.
3. [`verification/generated/p7_pair_matrix.json`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/generated/p7_pair_matrix.json): Complete machine-readable directed pair matrix artifact.
4. [`reports/E4_P7_BRIEF_V2_STEP3_PAIR_MATRIX.md`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/reports/E4_P7_BRIEF_V2_STEP3_PAIR_MATRIX.md): This report.

