# Final progress report, 2026-10-29: NOC_PQATTEST (Lane 1) and the two handoff lanes

- **Repository:** branch noc/credit-integration at dd52255 when this was written. The branch is not merged.
- **Project state:** STOPPED after I-5, per Kalash's scope change of 2026-10-29. Phase B was cancelled and I-6 was not started.
- **Validation status:** HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.
- **Sources:** reports/NEXT_STEP.md, reports/I5_GATE_20261029.md, reports/S1_GATE_20261023.md, docs/STATUS.md,
  reports/RISCV_HANDOFF_CHECK_20261029.md and reports/E4_HANDOFF_CHECK_20261029.md.

## 1. Lane 1: NoC + PQ attestation (two milestone tracks)

**Where it stands:** NOC 3 / 5 and PQ 3 / 5. The design is M-F1 rev 7 (P7):
- control-plane-only MAC;
- L2 on tiles 3 and 4;
- one shared L2 KMAC with RoT priority;
- a guarded ingress;
- non-attested tiles refuse data and control.

| Increment | Date | Result | Milestone |
|---|---|---|---|
| I-1 / I-1.5 | 2026-10-09 / 10-19 | PASS (baseline and hygiene) | |
| I-2 | 2026-10-19 | 36 / 36 accepted | NOC-1, PQ-1 |
| I-3 | 2026-10-20 | 22 / 22 PASS_FRESH | NOC-2, PQ-2 |
| I-4 | 2026-10-20 | 33 / 33; crypto synthesized for the first time; D-SYN-1/2 cut measurement 120,581 -> 8,763 LUT | PQ-3 |
| B-4 / S1 (P7 area rework) | 2026-10-23 | 39 / 39 PASS_FRESH (21 mutants killed) | area decision closed |
| **I-5 / S2** | **2026-10-29** | **30 / 30 (13 sec. 8 + 17 sec. 9)** | **NOC-3** |

### Measured results

These are OOC proxy figures for xc7a100t at 20 ns:

- **Area:** 44,412 LUT out of the 47,550 budget. The full-chip estimate in I-4 was 105-112k; D-AREA-1 / P7 brought it down to this.
- **Timing:** routed WNS +0.165 ns (flagged: below the +0.3 merge target), WHS +0.013 ns (thin).
- **Bounds:**
  - C4 REVOKE latency maximum 486 cycles, against a bound of 1,500;
  - engine P <= 269, Q <= 792, J <= 128.
- **Security matrix:** the attack matrix at L2 is 30 / 0, and 10 of 10 negative controls were killed.
- **Latency:**
  - L2 verdict: 107 cycles;
  - full attestation round trip: 1,204 cycles idle, 1,205-1,206 under load;
  - L2 overhead on a GRANT: +113 to +115 cycles over the 9-cycle transport time.

### Not done

All of the following are waiting for Kalash.

- **I-6 (NOC-4):**
  - C-1/C-2 retry;
  - fault status;
  - trusted fail / timeout / clear;
  - the 0x2 map;
  - K-3 binding.
- **I-7 (PQ-4 / PQ-5):** the SEC-1..4 matrix, including the 6 attestation rows recorded OPEN:
  - wrong tag;
  - wrong measurement;
  - replay;
  - nonce substitution;
  - config / imem substitution;
  - error response.
- **I-8 (NOC-5):**
  - regression;
  - **N-13 full-top timing**, which is the real timing gate; the figures above are only an OOC proxy;
  - release qualification.
- **Merge** of noc/credit-integration.

## 2. RISC-V lane (PQ_ATTEST.zip, SHA-256 273e3057...): NOT ACCEPTED

**Blocking findings:**
- **Adapter double-capture bug:** 24 core transfers produce 31 adapter requests, including duplicate writes. The CPU stalls at PC 0x12C.
- **tb_conformance FAIL:** 3,996 stability, 999 fetch and 1,999 protocol errors.
- **tb_random_latency hangs.** It covers 20 transactions on one seed; 1,000 seeds are required.
- **Bus errors return 0 silently**, and dbg_trap is tied to 0.

**Also missing or incomplete:**
- missing: memory_tile, the second BRAM port, memtest, the traffic generator, assertions and the tile timing report;
- tile_top synthesis shows 4 BRAM where 0 are required;
- tb_addr_decode is stale.

**What works:** UART benches PASS, tb_two_tiles runs, and tile_top synthesizes to 1,674 LUT.

## 3. Engineer 4 lane, verification (pqattest1.zip, SHA-256 7cb4a3f3...): ACCEPTED for rev 5 only

- **Reproduced here:**
  - 103 / 0 tests, run through a pytest-free runner;
  - the cross-module consistency check: PASS;
  - the crypto references (8 / 8 suites PASS) are byte-identical to the frozen teammate reference;
  - the extra SHA3 RTL passes 3 / 3 vectors (two of its files are 0 bytes).
- **Not valid for P7 until:**
  - message lengths are parsed from the package; they are hard-coded today (CHALLENGE = 5, P7 = 7), and the check passes against both;
  - MAC framing is per-type;
  - the 6 LOCAL self-pairs are removed;
  - the P7 authorization rules (R7.4) are modelled.

## 4. Integration conclusion

The three lanes cannot be integrated yet.

1. **RISC-V adapter:** its bug must be fixed and the conformance test must pass. This blocks the RISC-V lane.
2. **Lane 1 decisions:**
   - In P7, the CPU tiles 0/1 and the memory tile 2 are not attestable, so their data is refused. This conflicts with the
     brief's demo: attest the CPU tiles, or change the demo.
   - Fix the remote address mismatch: REMOTE_BASE is 0x2T00_0000, but the memory stand-in decodes 0x8xxx_xxxx.
   - Build the TMEM <-> NI bridge (not started).
3. **Area (estimate, not measured):**
   - 44,412 + 2 x 1,674 = 47,760 LUT. That is 75.3 % of the device, and above the 47,550 subsystem budget.
   - With the bridges and the memory tile it is about 49-51k.
   - Kalash decision: raise the budget or trim.
4. **Engineer 4:** re-baseline the tooling to P7 before it is used as an integration oracle.
