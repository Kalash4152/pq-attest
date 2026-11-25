# PQ-Attest Engineer 4 — Step 13: NI Slot-Leak Analysis (Two-Slot Model Rebuild)

**Date:** 2026-11-06  
**Author:** PQ-Attest Engineer 4  
**Reviewer:** Kalash Bheda (Lane 1, NoC + PQ-Attest)  
**Status:** COMPLETE (Rebuilt for Authoritative Two-Slot Architecture)  
**Evidence Package:** `E4_EVIDENCE_20261106` (folders `05_hop_probes_rtt/`, `07_I11/`)  
**Single Source of Truth:** [`verification/generated/p7_ni_slot_analysis.json`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/generated/p7_ni_slot_analysis.json)

---

## 1. Executive Summary & Design Source of Truth

In the previous handoff report, the text erroneously mentioned "4 slots". The actual registered PQ-Attest architecture has strictly:
$$\mathbf{N_{\text{OUTSTANDING}} = 2}$$
The Network Interface tracking table (`noc_network_interface_p7_i9.sv`) implements exactly **two** tracking slots with 1-bit tags (`0` and `1`), verified in Lane 1's hop-probe testbench assertion `CFG_N_OUTSTANDING`.

This report documents the evidence-grounded rebuild of the NI slot-leak analysis using the authoritative two-slot architecture and registered I-9 timeout and recovery semantics.

### Formal Definition of Slot Leak
> A **slot leak** occurs when an NI tracking slot remains in an allocated / occupied state after its owning transaction has completed, timed out autonomously, or been cleared by hardware reset.

Across all 14 evaluated transaction sequences, **zero slot leaks** were observed:
$$\text{Total Leaks} = 0 \quad (\text{Leak Rate} = 0.0\%)$$

---

## 2. Registered I-9 Timeout and Recovery Semantics

The model directly mirrors the behavior and assertion contracts codified in Lane 1's `tb_i9_integ.sv`:

1. **`I9_SLOT_HELD` (Capacity Saturation & Backpressure):**
   - Two outstanding requests exhaust available table capacity (`N_OUTSTANDING = 2`).
   - Any third allocation request presented while both slots are held is refused at the application interface (`app_ready` held low), preventing slot overwriting or tag aliasing.
2. **`SLOT_RECOVER` / `I9_SLOT_RECOVER` (Autonomous Timeout Recovery):**
   - If a response is lost or withheld, the per-slot watchdog counter releases the slot at `cycle_alloc + timeout`.
   - The slot is returned to `IDLE` state and becomes immediately available for new transaction allocation, preventing permanent Denial-of-Service or slot starvation.
3. **`STALE_DROPPED` / `I9_STALE_DROPPED` (Late / Stale Response Rejection):**
   - A late response arriving after slot timeout has elapsed is discarded unconditionally.
   - The late response is **never delivered** to the CPU (`app_rx_head_valid` remains deasserted); a late-response counter increments, ensuring stale data never corrupts software state.

### 2.1 Timeout Configuration & Provenance Distinction

The verification infrastructure and generated evidence explicitly differentiate the two timeout configurations:

| Timeout Identifier | Value | Evidentiary Classification | Provenance / Source | Application Scope |
|---|---:|---|---|---|
| `bench_timeout_cycles` | **600** | `CONFIGURATION_PARAMETER` | `tb_i9_integ.sv` line 5 (`NI_SLOT_TIMEOUT = 600`), `I9_GATE_20261105.md` Section 2 | Applied to all 14 Step 13 simulation sequences and Step 12 timeout scenarios |
| `merged_ni_slot_timeout_cycles` | **8,192** | `REVIEWER_STATED_CONFIGURATION` | `E4_FINAL_INTAKE_20261106.md` / `E4_FINAL_RESPONSE_20261106.md` (citing M-F1 rev 8) | Referenced in timeout hierarchy only; RTL default is 0 (off); not synthesized |

These two timeout values are distinct and never conflated:
- In `verification/generated/p7_ni_slot_analysis.json`, both `bench_timeout_cycles: 600` and `merged_ni_slot_timeout_cycles: 8192` are emitted under `metadata` alongside their individual provenance records.
- Every scenario record explicitly specifies `timeout_applied_cycles: 600` and `timeout_applied_kind: "BENCH"`.
- Unit tests (`test_p7_ni_slot_analysis.py::test_step13_timeout_metadata_unambiguity_and_conflation_prevention`) enforce strict differentiation and fail if the values are conflated or if provenance is missing.

---

## 3. Transaction Sequences & State Transition Table

The 14 transaction sequences were executed against the two-slot behavioral model (`verification/p7_ni_slot_analysis.py`). Every sequence documents initial state, events, state transitions, final state, occupancy, delivery outcome, and leak result:

| # | Scenario Name | Initial Slot State | Expected State Transition | Delivery / Drop Outcome | Final Occupancy | Leak Result | Registered I-9 Check |
|---|---|---|---|---|---:|---|---|
| **01** | Normal Completion | IDLE (0/2) | IDLE $\to$ ALLOC $\to$ RESP $\to$ IDLE | DELIVERED | 0 | **`NO_LEAK`** | Standard transaction flow |
| **02** | Two Outstanding Slots | IDLE (0/2) | IDLE $\to$ SATURATED (2/2) $\to$ RETIRE $\to$ IDLE | BOTH DELIVERED | 0 | **`NO_LEAK`** | `I9_SLOT_HELD` |
| **03** | One Lost Response | IDLE (0/2) | BOTH_OCC $\to$ RETIRE_1 $\to$ TIMEOUT_0 $\to$ IDLE | SLOT 1 DELIVERED; SLOT 0 DROPPED | 0 | **`NO_LEAK`** | `SLOT_RECOVER` |
| **04** | Both Lost Responses | IDLE (0/2) | IDLE $\to$ BOTH_OCC $\to$ TIMEOUT_BOTH $\to$ IDLE | NEITHER DELIVERED | 0 | **`NO_LEAK`** | `SLOT_RECOVER` |
| **05** | Timeout Boundary | IDLE (0/2) | ALLOC $\to$ BOUNDARY $\to$ TIMEOUT $\to$ IDLE | TIMED_OUT | 0 | **`NO_LEAK`** | `SLOT_RECOVER` |
| **06** | Reset One Occupied | OCCUPIED (1/2) | OCCUPIED_1 $\to$ RESET $\to$ IDLE | RESET_ABORTED | 0 | **`NO_LEAK`** | Reset quiescence |
| **07** | Reset Both Occupied | OCCUPIED (2/2) | OCCUPIED_2 $\to$ RESET $\to$ IDLE | RESET_ABORTED | 0 | **`NO_LEAK`** | Reset quiescence |
| **08** | Late Response | IDLE (0/2) | ALLOC $\to$ TIMEOUT $\to$ LATE_ARRIVE $\to$ DROP | DROPPED (never delivered to `app_rx`) | 0 | **`NO_LEAK`** | `STALE_DROPPED` |
| **09** | Stale Response Tag Reuse | IDLE (0/2) | ALLOC_OLD $\to$ TIMEOUT $\to$ REALLOC $\to$ DELIVER | NEW DELIVERED; OLD DROPPED | 0 | **`NO_LEAK`** | `SLOT_RECOVER` + `STALE_DROPPED` |
| **10** | Repeated Timeout Cycles | IDLE (0/2) | 10 $\times$ (ALLOC $\to$ TIMEOUT $\to$ FREED) | 10 $\times$ TIMED_OUT | 0 | **`NO_LEAK`** | `SLOT_RECOVER` (repeated) |
| **11** | Unexpected Response | OCCUPIED (1/2) | OCCUPIED_0 $\to$ UNMAPPED_RESP $\to$ DROPPED | DROPPED (unmapped tag) | 1* | **`NO_LEAK`** | `STALE_DROPPED` (*slot 0 active) |
| **12** | Backpressure / Saturation | IDLE (0/2) | IDLE $\to$ SATURATED (2/2) $\to$ REFUSE_NEW | 3rd ALLOCATION REFUSED | 2** | **`NO_LEAK`** | `I9_SLOT_HELD` (**at capacity) |
| **13** | Duplicate Release | IDLE (0/2) | ALLOC $\to$ RETIRE $\to$ DUP_RESP $\to$ DROP | FIRST DELIVERED; SECOND DROPPED | 0 | **`NO_LEAK`** | `STALE_DROPPED` |
| **14** | Invalid Allocation | IDLE (0/2) | IDLE $\to$ REJECT_OR_TIMEOUT $\to$ IDLE | SAFE RECOVERY | 0 | **`NO_LEAK`** | `SLOT_RECOVER` |

---

## 4. Invariant Verification Results

The test suite validates seven formal invariants across all scenarios:

1. **`INV_MAX_CAPACITY` (PASS):** Total active slots never exceeds 2 (`slots_occupied <= 2`).
2. **`INV_NO_DUPLICATE_CONCURRENT_ALLOCATION` (PASS):** Both active slots never share identical tags (`tag_0 != tag_1`).
3. **`INV_CORRECT_SLOT_RELEASE` (PASS):** A valid response decrements occupancy by exactly 1 and clears the matching tag.
4. **`INV_TIMEOUT_RELEASE` (PASS):** Unanswered requests release autonomously without software intervention.
5. **`INV_RESET_CLEANUP` (PASS):** Synchronous reset instantaneously returns both slots to IDLE without stranded state.
6. **`INV_LATE_STALE_REJECTION` (PASS):** Out-of-order or late responses cannot match, deliver, or corrupt subsequent allocations.
7. **`INV_NO_PERMANENT_LEAK` (PASS):** After all operations settle, available capacity returns to $100\%$ (2 slots).

---

## 5. Architectural Integrity Disclaimers

- **Verification Methodology:** Python behavioral model checking. Not fresh RTL simulation, not hardware, not formal.
- `HARDWARE_VALIDATED=NO`
- `SOC_INTEGRATION_COMPLETE=NO`
- `FORMAL_PROOF=NO`
- `RTL_MODIFICATIONS=0`
- `PYTHON_MUTANTS_ARE_RTL_MUTANTS=NO`
- `SYNTHETIC_STIMULUS_IS_RTL_EVIDENCE=NO`
