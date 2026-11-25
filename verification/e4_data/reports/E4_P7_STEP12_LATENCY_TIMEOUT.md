# PQ-Attest Engineer 4 — Step 12: Latency and Timeout Model (Evidence-Grounded Rebuild)

**Date:** 2026-11-06  
**Author:** PQ-Attest Engineer 4  
**Reviewer:** Kalash Bheda (Lane 1, NoC + PQ-Attest)  
**Status:** COMPLETE (Rebuilt from Authoritative Registered Evidence; Evidence-Corrected)  
**Evidence Package:** `E4_EVIDENCE_20261106` (folders `01_I5_gate/`, `02_MF1_rev8_signed/`, `03_C4_revoke/`, `04_arbiter_bounds/`, `05_hop_probes_rtt/`)  
**Single Source of Truth:** [`verification/generated/p7_latency_model_results.json`](file:///c:/Users/Arnav%20Bhandari/PQ_Attest/verification/generated/p7_latency_model_results.json)

---

## 1. Executive Summary

This report replaces the previous preliminary latency model with an **evidence-grounded rebuild** derived strictly from Lane 1's authoritative registered runs, signed gate reports, and integration contracts.

The earlier analytical 78–126 cycle round-trip model and 72-cycle KMAC formula are discarded. Instead, the model incorporates:
1. The **1,206-cycle** measured full-subsystem attestation round trip under the **LOADED** condition (maximum over 4 attestations: 1,206, 1,206, 1,205, 1,205; mean 1205.5), representing the worst measured port hold. The **1,204-cycle** measurement under the **NONE** condition (208 + 524 + 350 + 122 cycles) is retained as a labelled reference.
2. The **486-cycle** measured C4 revocation maximum and **1,500-cycle** contractual upper bound.
3. The signed arbiter bounds: **$P \le 269$ cycles** (Tile 3 class P), **$Q \le 792$ cycles** (Tile 4 class Q), and **$J \le 128$ cycles** (job duration), with explicit documentation of which bounds apply to CPU wait calculations.
4. The measured per-hop / per-flit transport latencies from registered job `i9r_hop_probes_p7`.
5. A rigorous derivation of the **worst legitimate CPU wait** at Tile 3 during attestation ($W_{\text{nominal}} = 1,234$ cycles under LOADED max hold, $W_{\text{contention\_P}} = 1,503$ cycles, $W_{\text{contention\_C4}} = 1,720$ cycles, $W_{\text{extreme}} = 2,734$ cycles).
6. A technically defensible recommendation regarding `BRIDGE_TIMEOUT = 4,096` per contract D7 (PROPOSED, pending Kalash approval).

---

## 2. Authoritative Registered Inputs & Classification

Every numeric input and derived parameter carries an explicit evidentiary classification:
- **`MEASURED_REGISTERED`**: Directly observed in a registered Vivado/XSim run log or signed report.
- **`DERIVED_ANALYTICAL_BOUND`**: Analytically computed upper bound with documented formula.
- **`ANALYTICAL_ASSUMPTION`**: Engineer 4 allowance with no registered source (not a measurement).
- **`CONTRACT_ESTIMATE`**: Estimate explicitly stated in the signed contract (not a measurement).
- **`CONFIGURATION_PARAMETER`**: Registered bench or signed configuration parameter.
- **`REVIEWER_STATED_CONFIGURATION`**: Value stated in reviewer intake documents (not in inspected contract text/RTL).
- **`PROPOSED_RECOMMENDATION`**: Engineer 4 recommendation pending Kalash approval.

| Parameter | Value | Unit | Classification | Registered Run ID / Job | Source Document / Provenance |
|---|---:|---|---|---|---|
| **Attestation RTT (LOADED Max)** | **1,206** | cycles | `MEASURED_REGISTERED` | `dual_lane_10_20261029_140104_d9fb229d` (`n2p7_rtt`) | `reports/I5_GATE_20261029.md` (LOADED condition: min 1205, mean 1205.5, max 1206 over 4 runs; writes + flood) |
| **Attestation RTT (NONE Reference)** | **1,204** | cycles | `MEASURED_REGISTERED` | `dual_lane_10_20261029_140104_d9fb229d` (`n2p7_rtt`) | `reports/I5_GATE_20261029.md` (NONE condition: min = mean = max = 1,204 over 4 runs; 208+524+350+122) |
| **Contract Worst Attestation (ESTIMATE)** | **2,700** | cycles | `CONTRACT_ESTIMATE` | None (Analytical Estimate) | `docs/decisions/M-F1-interface-freeze.md` R7.6a (Verifier timeout check: ~2,700c) |
| **C4 REVOKE Maximum Latency** | **486** | cycles | `MEASURED_REGISTERED` | `dual_lane_10_20261105_145813_9ca6a347` (`i9r_s3_p7_c4`) | `reports/S1_GATE_20261023.md` / `reports/I5_GATE_20261029.md` |
| **C4 REVOKE Bound** | **1,500** | cycles | `DERIVED_ANALYTICAL_BOUND` | Contractual Upper Bound | `docs/decisions/P7-INGRESS-REVOCATION-CONTRACT.md` |
| **Arbiter Engine P Bound (Tile 3)** | **269** | cycles | `DERIVED_ANALYTICAL_BOUND` | Signed Arbitration Ceiling | `docs/decisions/D2-peer-slot-deadlock-freedom.md` / M-F1 R7.6a |
| **Arbiter Engine Q Bound (Tile 4)** | **792** | cycles | `DERIVED_ANALYTICAL_BOUND` | Signed Arbitration Ceiling | `docs/decisions/D2-peer-slot-deadlock-freedom.md` / M-F1 R7.6a |
| **Arbiter Job Bound ($J_{\text{MAX}}$)** | **128** | cycles | `DERIVED_ANALYTICAL_BOUND` | Maximum Single Job Duration | `docs/decisions/D2-peer-slot-deadlock-freedom.md` / M-F1 R7.6 |
| **Outstanding NI Slots ($N_{\text{OUTSTANDING}}$)** | **2** | slots | `MEASURED_REGISTERED` | `dual_lane_10_20261105_145813_9ca6a347` (`i9r_hop_probes_p7`) | `rtl/dual_lane/NOC_PKG.sv` (`CFG_N_OUTSTANDING` check) |
| **Proposed Bridge Timeout** | **4,096** | cycles | `PROPOSED_RECOMMENDATION` | Architecture Proposal (Row D7) | `docs/decisions/M-F1-rev8-INTEGRATION-DRAFT.md` (Row D7: '[PROPOSED, needs Kalash]') |
| **Merged Build NI Slot Timeout** | **8,192** | cycles | `REVIEWER_STATED_CONFIGURATION` | Reviewer Intake Statement | `E4_FINAL_INTAKE_20261106.md` / `E4_FINAL_RESPONSE_20261106.md` (cites M-F1 rev 8) |
| **Bench NI Slot Timeout** | **600** | cycles | `CONFIGURATION_PARAMETER` | `dual_lane_10_20261106_163900_ff77f562` (`i11_i9_integ`) | `tb_i9_integ.sv` line 5 (`NI_SLOT_TIMEOUT = 600`), `I9_GATE_20261105.md` |
| **Global Verifier Timeout** | **100,000** | cycles | `CONFIGURATION_PARAMETER` | Architecture Watchdog Constant | `docs/decisions/M-F1-interface-freeze.md` R7.6a (`pq_rot_verifier.sv:4`) |

---

## 3. Registered Hop-Probe Latency Measurements

Extracted directly from `i9r_hop_probes_p7` simulate log (`dual_lane_10_20261105_145813_9ca6a347`):

| Distance ($H$ hops) | Message Size ($F$ flits) | Measured Latency | Classification | Empirical Model |
|---|---|---:|---|---|
| 1 hop | 1 flit (RD_RESP ACK) | **5 cycles** | `MEASURED_REGISTERED` | $3 + 2(1) + 0 = 5$ |
| 1 hop | 3 flits (MEM_REQ / DATA) | **7 cycles** | `MEASURED_REGISTERED` | $3 + 2(1) + 2 = 7$ |
| 1 hop | 12 flits (Payload burst) | **16 cycles** | `MEASURED_REGISTERED` | $3 + 2(1) + 11 = 16$ |
| 2 hops | 1 flit | **7 cycles** | `MEASURED_REGISTERED` | $3 + 2(2) + 0 = 7$ |
| 2 hops | 3 flits | **9 cycles** | `MEASURED_REGISTERED` | $3 + 2(2) + 2 = 9$ |
| 3 hops | 1 flit | **9 cycles** | `MEASURED_REGISTERED` | $3 + 2(3) + 0 = 9$ |
| 3 hops | 3 flits (Tile 3 $\leftrightarrow$ Tile 2) | **11 cycles** | `MEASURED_REGISTERED` | $3 + 2(3) + 2 = 11$ |

**Transport Formula:** For $F$ flits over $H$ hops in an unloaded mesh, $L(H, F) = 3 + 2H + (F - 1)$ clock cycles.

---

## 4. Worst Legitimate CPU Wait Model (M-F1 rev 8 Sec. 5)

Under M-F1 rev 8 Section 3 Rule 6 and Section 5, CPU A at Tile 3 shares its application port with the attestation endpoint. When an attestation sequence executes, `app_ready[3]` is held low by the attestation gate for the duration of the attestation exchange (~1.2k cycles). This is a normal, legitimate architectural wait that must be tolerated by `BRIDGE_TIMEOUT`.

### 4.1 Latency Composition

The complete legitimate CPU wait is composed of the following sequential stages:

```
  CPU A Read Request Raised
           │
           ▼
┌──────────────────────────────────────┐
│ 1. Attestation Port Hold             │  1,206 cycles (MEASURED_REGISTERED, LOADED max)
│    (app_ready[3] held low by gate)   │  [Reference: 1,204 cycles under load=NONE]
└──────────────────────────────────────┘
           │ (Port released upon GRANT delivery)
           ▼
┌──────────────────────────────────────┐
│ 2. NI Store-and-Forward Delay        │  3 cycles (ANALYTICAL_ASSUMPTION)
│    (Header framing & tag assignment) │
└──────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│ 3. Forward Mesh Transport            │  11 cycles (MEASURED_REGISTERED, i9r_hop_probes_p7)
│    Tile 3 (0,1) -> Tile 2 (2,0):     │  [3 Manhattan hops, 3 flits: HEAD, ADDR, TAIL]
└──────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│ 4. Memory Front-End & BRAM Read      │  2 cycles (ANALYTICAL_ASSUMPTION)
│    (1 cycle decode + 1 cycle BRAM)   │
└──────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│ 5. Reverse Mesh Transport            │  11 cycles (MEASURED_REGISTERED, i9r_hop_probes_p7)
│    Tile 2 (2,0) -> Tile 3 (0,1):     │  [3 Manhattan hops, 3 flits: HEAD, DATA, TAIL]
└──────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│ 6. Egress Delivery to app_rx         │  1 cycle (ANALYTICAL_ASSUMPTION)
│    (Handshake to CPU bridge)         │
└──────────────────────────────────────┘
```

### 4.1a Composition Validation (Sequential vs Overlapping)

**Verdict: Sequential. No component is double-counted.**

| Boundary | Event |
|---|---|
| **Hold interval begins** | Attestation start (I-5 round-trip table, column "start") |
| **Hold interval ends** | GRANT delivered at Tile 3 (`n2p7_rtt`: GRANT HEAD into mesh → delivered at Tile 3) — 1,206 cycles (LOADED max) / 1,204 cycles (NONE) |
| **CPU request service begins** | `app_ready[3]` rises and the NI accepts the CPU request, strictly after the endpoint releases the port |
| **CPU request service ends** | Response delivered on `app_rx[3]` (28 cycles total service path) |

**Justification for adding the 28-cycle service path:**
1. M-F1 rev 8 Sec. 3 Rule 6: `app_ready[3] = 0` while the endpoint owns the port, so the CPU request cannot be accepted by the NI during the hold.
2. M-F1 rev 8 Sec. 5 explicitly defines the worst legitimate wait as additive: port hold + NI store-and-forward + mesh round trip + front-end service.
3. The I-5 hold interval contains only attestation traffic (CHALLENGE / RESPONSE / GRANT). No CPU memory-request NI, mesh or memory service lies inside it.

**Limits of this evidence (stated, not hidden):**
- The exact RTL cycle at which `app_ready[3]` rises is not a registered measurement. It is taken as the GRANT-delivered boundary; an earlier release would only reduce the wait.
- The hold is assumed to begin no earlier than attestation start; an earlier start would add cycles the measurement does not capture.
- Of the 28 service-path cycles, 22 are registered hop-probe transport. The 3-cycle NI, 2-cycle front-end, and 1-cycle egress allowances (6 cycles) are `ANALYTICAL_ASSUMPTION`.
- Sensitivity: inflating the whole 28-cycle path 3× (84 cycles) still gives $4,096 / (1,206 + 84 + 1,500) = 1.47\times$ margin over the extreme bound.

### 4.2 Wait Totals Under Varying System Conditions

1. **Nominal Legitimate Wait (LOADED max hold):**
   $$W_{\text{nominal}} = 1,206 + 3 + 11 + 2 + 11 + 1 = \mathbf{1,234\,\text{cycles}}$$
   *(Reference NONE condition wait: $1,204 + 28 = \mathbf{1,232\,\text{cycles}}$).*
2. **With Arbiter Class P Engine Contention:**
   When an attestation job experiences maximum Class P arbitration hold ($T_{\text{arb\_p}} = 269$ cycles):
   $$W_{\text{contention\_P}} = 1,234 + 269 = \mathbf{1,503\,\text{cycles}}$$
3. **With C4 Maximum Revocation Transient:**
   If a revocation sequence executes concurrently ($T_{\text{c4\_max}} = 486$ cycles):
   $$W_{\text{contention\_C4}} = 1,234 + 486 = \mathbf{1,720\,\text{cycles}}$$
4. **With Theoretical Extreme C4 Bound:**
   Under the absolute contractual revocation bound ($T_{\text{c4\_bound}} = 1,500$ cycles):
   $$W_{\text{extreme}} = 1,234 + 1,500 = \mathbf{2,734\,\text{cycles}}$$
5. **Contract Analytical Estimate Reference:**
   Under the contract R7.6a estimated attestation round trip (~2,700 cycles, including Q-class bounds):
   $$W_{\text{contract\_est}} = 2,700 + 28 = \mathbf{2,728\,\text{cycles}}$$

### 4.3 Arbiter Bounds Applicability (P, Q, J)

| Bound | Cycles | Classification | Provenance | Traversed by CPU Req? | Added to CPU Wait? | Rationale |
|---|---:|---|---|:---:|:---:|---|
| **$J_{\text{MAX}}$** | 128 | `DERIVED_ANALYTICAL_BOUND` | M-F1 R7.6 / I-5 A3 assertion | **No** | **No** | Maximum duration of a single cryptographic engine job. Already encompassed within the measured attestation hold (1,204c / 1,206c) and within P and Q bounds. Adding it separately would double count. |
| **$P$** | 269 | `DERIVED_ANALYTICAL_BOUND` | M-F1 R7.6a re-frozen bound | **No** | **Yes** (in contention scenario) | Upper bound on engine wait for RoT-class traffic at Tile 3 ($r_0, r_1$). Applied once as a conservative single-wait contention increment ($W_{\text{contention\_P}} = 1,503$c). |
| **$Q$** | 792 | `DERIVED_ANALYTICAL_BOUND` | M-F1 R7.6a re-frozen bound | **No** | **No** (captured in contract estimate) | Upper bound on engine wait for non-RoT traffic at Tile 4 ($r_2, r_3$: RESPONSE MAC and verify). Affects attestation duration under starvation load; reflected in the contract estimate (~2,700c) rather than added directly to the measured P scenario. |
| **CPU Path** | — | `EVIDENCE_NOTE` | I5 hop table / M-F1 Sec. 5 | **No** | **No** | CPU memory requests and responses travel on plain data VCs in P7 and do not use the shared L2 KMAC engine. They never encounter KMAC engine arbitration. |

---

## 5. Proposed BRIDGE_TIMEOUT & Margin Analysis

Contract M-F1 rev 8 Row D7 defines:
> `BRIDGE_TIMEOUT`: 4,096 cycles until Engineer 4's Step 12 worst-case model is accepted, then that value rounded up to a power of 2. Must exceed the worst legitimate wait (Sec. 5).

### 5.1 Safety Margin Quantification

Comparing the proposed `BRIDGE_TIMEOUT = 4,096 cycles` against derived legitimate wait bounds:

| Condition | Legitimate Wait | Proposed `BRIDGE_TIMEOUT` | Safety Factor | Safety Margin (%) | Evaluation |
|---|---:|---:|---:|---:|---|
| **Nominal Wait (LOADED max)** | 1,234 cycles | 4,096 cycles | **3.32x** | +232% | Robust tolerance of standard attestations |
| **Reference NONE Wait** | 1,232 cycles | 4,096 cycles | **3.32x** | +232% | Labelled unloaded reference |
| **Arbiter P Contention** | 1,503 cycles | 4,096 cycles | **2.73x** | +173% | Ample margin during engine contention |
| **C4 Revoke Maximum** | 1,720 cycles | 4,096 cycles | **2.38x** | +138% | Safe under worst measured revocation |
| **Contract Estimate** | 2,728 cycles | 4,096 cycles | **1.50x** | +50% | Exceeds R7.6a analytical estimate |
| **Extreme C4 Bound** | 2,734 cycles | 4,096 cycles | **1.50x** | +50% | Conservative margin under theoretical worst case |
| **Verifier Timeout Separation** | 4,096 cycles | 100,000 cycles | **24.4x** | +2,341% | Over 24x separation from verifier watchdog |

### 5.2 Technical Recommendation

**Recommendation: Retain `BRIDGE_TIMEOUT = 4,096 cycles`** (PROPOSED, Pending Kalash approval per contract D7).

**Justification:**
1. A value of 4,096 cycles is well above the derived worst legitimate wait of 1,234–1,720 cycles, providing a **2.38x safety factor** over worst-case measured C4 revocation contention and a **1.50x safety factor** over the extreme theoretical bound (2,734 cycles).
2. Attempting to reduce `BRIDGE_TIMEOUT` below 2,048 cycles would severely degrade margin against transient C4 revocation delays (1,720 cycles) and would cause false timeouts during normal CPU operations.
3. 4,096 cycles sits comfortably ($24.4\times$ below) the global `VERIFIER_TIMEOUT = 100,000 cycles`, ensuring that bridge request drops are completely decoupled from root-of-trust security epoch expirations.

---

## 6. Architectural Integrity Disclaimers

- `HARDWARE_VALIDATED=NO`
- `SOC_INTEGRATION_COMPLETE=NO`
- `FORMAL_PROOF=NO`
- `RTL_MODIFICATIONS=0`
- `PYTHON_MUTANTS_ARE_RTL_MUTANTS=NO`
- `SYNTHETIC_STIMULUS_IS_RTL_EVIDENCE=NO`
