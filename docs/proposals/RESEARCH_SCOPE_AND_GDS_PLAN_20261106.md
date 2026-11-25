# Research scope and plan to GDSII, PQ-Attest NoC (draft for Kalash, 2026-11-06)

Status words used below: **DONE** = measured or registered here; **TO DO** = planned; **CONFIRM** = must be checked
before it goes in the paper. Nothing here is a claim yet.

---

## 1. What the paper is about (one sentence)

> **Hardware-enforced, attestation-gated access control for a Network-on-Chip SoC using only quantum-resistant symmetric
> primitives (SHA3-256 / KMAC128): a tile may touch shared memory only after an on-chip Root-of-Trust has verified its
> measured code, and the network itself enforces that decision, at a measured area, latency and timing cost.**

**Working title (pick one; refine after the literature search):**
- *PQ-Attest: Attestation-Gated Access Control for Network-on-Chip SoCs with Quantum-Resistant Symmetric Cryptography*
- *Enforcing Remote Attestation in the Network-on-Chip: A Quantum-Resistant, Mutation-Verified FPGA-to-ASIC Study*

## 2. Research question and hypothesis

**RQ1 (security):** Can the NoC itself (network-interface gates, link authentication and ingress filtering) enforce
"no memory side effect without a valid, fresh attestation" against a malicious tile, using only symmetric primitives?

**RQ2 (cost):** What does that enforcement cost in area, timing and latency compared with the same NoC without security,
on FPGA (Artix-7) and on an ASIC (Cadence flow)?

**RQ3 (assurance):** Can the security properties be shown with a reproducible, mutation-tested verification method
instead of claims, short of formal proof?

**Hypothesis:** the enforcement fits in a small multiple of the insecure NoC, closes timing at 50 MHz on Artix-7, and adds
latency only at attestation time (about 1.2k cycles), not to every authorized memory access. **CONFIRM** the last part
with a measurement (section 5, E4).

## 3. Contributions (what we can honestly claim after the merge)

| # | Contribution | Evidence we have | Still needed |
|---|---|---|---|
| C1 | **Architecture:** RoT verifier tile + attested CPU tile; NI attestation gates; L2 KMAC link authentication (tiles 3 / 4); ingress parser and quarantine against spoofed / partial packets; fail-closed verifier (busy retry, timeout); REVOKE; authorization decided at the side effect (F4) and read suppression (Q2) | RTL + M-F1 contract revs 1 to 8 | figures (block diagram, packet formats, attestation sequence) |
| C2 | **Threat model and properties** (malicious tile: injection, spoofing, replay, substitution, stale nonce, revoke race) | SEC matrix (tb_i7_sec, 30 checks), full chain (21), I-6 gate (25), D2 (12), all registered with killed controls | a written threat model and a property list mapped to the benches |
| C3 | **Cost of security** on FPGA | N-13 secure 32,708 LUT, WNS +0.275 (S4); insecure 11,848 (I-8, *older flow*) | **re-measure the insecure baseline with the S4 flow** (same flow for both, or the ratio is unfair); latency table (E1 to E5) |
| C4 | **Area-optimization study** (Keccak sharing, single-block SHA3, KMAC state-copy removal, flatten / mesh split) | −14 % (S4), probes for A3 / B1 | one consolidated table |
| C5 | **Verification methodology:** frozen counts before runs, identity-checked reuse, mutation controls that must be killed by a named oracle, independent Python reference, E4 Python models | harness + gate reports I-1 to I-10 | totals (jobs, controls, kill ratio) collected in one table |
| C6 | **System integration:** two RV32 CPU tiles on the NoC, demo on an Arty A7 board | skeleton ready; real CPUs TO DO | merged registered runs + **board run** |
| C7 | **ASIC implementation to GDSII** (college Cadence flow) with FPGA vs ASIC comparison | none yet | section 6 |

**CONFIRM before claiming novelty:** do the literature search first (NoC security, NoC firewalls / secure NIs,
remote attestation for SoC / FPGA, Keccak hardware). The claim is likely the **combination**: attestation enforced
inside the NoC, symmetric-only, with measured cost and mutation-verified properties. Not "first ever".

## 4. Scope

**In scope:**
- 3x2 mesh NoC with 6 tiles (2 CPUs, memory, crypto endpoint, RoT, injection port), one clock domain at 50 MHz.
- Measurement = SHA3-256 over TILE_ID, 16-byte config and the first 64 bytes of IMEM (D2).
- KMAC128 attestation tags and link MACs; KDF from a root secret.
- Malicious-tile threat model at the packet level.
- FPGA (Artix-7) implementation, board demo, and ASIC GDSII with the college Cadence flow.

**Out of scope (state these in the paper as limitations):**
- Side channels (power, EM, timing) and fault injection.
- Physical attacks; key storage / provisioning hardware; TRNG (the nonce is a demo constant).
- Asymmetric post-quantum cryptography (ML-KEM, ML-DSA). Word the "post-quantum" claim exactly as in
  docs/reviews/IPD_III_Report_Corrections_20261030.md C6: symmetric only, 128-bit strength, no formal PQ proof.
- Full-IMEM measurement (only 64 bytes; say exactly that).
- Formal verification (NO); silicon tapeout (GDSII only, unless a shuttle is found).
- Denial of service beyond the signed arbiter / REVOKE bounds.

## 5. Evaluation plan (experiments for the paper)

| ID | Experiment | Status |
|---|---|---|
| E1 | Area: insecure NoC vs secured subsystem vs merged SoC (LUT / FF / BRAM), **same S4 flow** | secured DONE; insecure re-measure TO DO; merged TO DO |
| E2 | Timing: WNS / WHS at 20 ns, critical path location | DONE for P7; merged TO DO |
| E3 | Attestation latency: challenge to GRANT (cycles, µs), REVOKE latency (C4 bound), retry / timeout behaviour | partly DONE (RTT 1,204, C4 ≤ 486; **CONFIRM** current values after S3 / S4 changes) |
| E4 | Authorized memory access latency with vs without the security path (does the gate add per-access cycles?) | TO DO (bench on merged design) |
| E5 | Security matrix: each attack -> blocked, with the bench and the killed control that proves the check bites | DONE (registered); table TO DO |
| E6 | Verification statistics: jobs, checks, controls, kill ratio, Python reference / E4 models | DONE; collect TO DO |
| E7 | Board demonstration (LEDs / UART per the board checklist) | TO DO after the merge |
| E8 | ASIC: area (µm²), cell count, fmax, power estimate, FPGA vs ASIC | TO DO (section 6) |

## 6. Plan after the two zips are merged (to GDSII)

### Phase M: merge and freeze (about 2 to 4 days)
1. Check the RISC-V and E4 packages; integrate the real `cpu_tile_noc` (merge-prep files are ready).
2. Register and run the merged jobs (bridge co-sim, demo), gate report.
3. Merged bitstream (`merged_build`): timing and area gates; Kalash's board run (board checklist). **HARDWARE_VALIDATED**
   only with a recorded board report.
4. **Freeze the RTL for the paper** (git tag). Everything after this point is measured on the frozen tag.

### Phase P: paper evidence (about 1 to 2 weeks, can overlap phase A)
5. Re-measure the insecure baseline with the S4 flow (E1), the latencies (E3 / E4), and collect E5 / E6 tables.
6. Literature search (15+ references, confirmed on IEEE Xplore), comparison table, threat model, figures.

### Phase A: ASIC to GDSII with the college Cadence flow (Kalash, 2026-11-06; about 4 to 8 weeks)

**Flow:** Genus (synthesis) -> Conformal LEC (RTL vs netlist equivalence) -> Innovus (floorplan, place, CTS, route) ->
Tempus (sign-off STA) -> Voltus (power / IR) -> Pegasus or Calibre (DRC / LVS, whichever the college has) -> GDSII.
Gate-level simulation: Xcelium if licensed (else XSim with the PDK's Verilog cell models).

**Confirm with the college first (A0, blocks everything else):**
- which tools and versions are licensed, and where they run (a Linux server, remote login, lab hours);
- **which PDK:** Cadence generic **gpdk045 / gpdk090** (no foundry NDA; layouts publishable, but no real fab), or a real
  foundry PDK (for example 180 nm / 65 nm through the college): real numbers, but an NDA usually forbids publishing
  layouts and cell-level detail;
- whether there is an **SRAM memory compiler** for that PDK (decides how the memories are built);
- the standard-cell library (.lib / .lef), tech LEF, QRC tech files and DRC / LVS rule decks (PVS or Calibre).

**Steps:**
- **A1. ASIC-ready RTL** (no change to protected files; new `rtl/asic/` wrappers only):
  - an ASIC top without the MMCM / BUFG (clock from a pad), reset synchronizer kept; pad ring only if the college requires
    it (a core-only GDS is enough for the paper);
  - **memories:** 2 CPUs x IMEM / DMEM 16 KB + tile-2 16 KB = 80 KB as on the FPGA. With a memory compiler: SRAM macros.
    Without one: flip-flop / latch arrays, which forces **smaller memories** for the ASIC (for example 1-4 KB each); state
    the size in the paper;
  - inferred LUTRAM FIFOs become flip-flops (automatic; check the area);
  - demo secrets become input ports or an OTP / eFuse model, never constants in the GDS;
  - Genus reads SystemVerilog directly (no sv2v needed); fix any construct it rejects in the wrappers, not in protected RTL.
- **A2. Synthesis (Genus)** at 20 ns with the generic flow (syn_generic / syn_map / syn_opt); SDC with clock,
  input / output delays and the async-input false paths from the board XDC. Record area, cell count, worst slack, then
  try 10 ns as a stretch result.
- **A3. Equivalence (Conformal LEC):** RTL vs synthesized netlist, and again after place-and-route. This is
  *implementation* equivalence, not a security proof: FORMAL_PROOF (of the security properties) stays NO.
- **A4. Floorplan (Innovus):** die / core size from the synthesis area (about 60-70 % utilization), macro placement
  (SRAMs, Keccak cores near the crypto tiles), power rings and stripes, pin placement.
- **A5. Place, CTS, route, optimization (Innovus):** place_opt, ccopt (CTS), route, post-route optimization; hold fixing.
- **A6. Sign-off:** Tempus multi-corner STA (ss / tt / ff), Voltus power (vectorless + VCD / SAIF from a bench) and IR
  drop, DRC / LVS / antenna clean, GDSII stream out.
- **A7. Gate-level simulation with SDF** of 2-3 key benches (full chain, SEC subset, D2) on the routed netlist.
- **A8. Results for E8:** area µm² / mm², cell count, utilization, fmax per corner, power, FPGA vs ASIC table.

**ASIC risks:** licence / server access time; PDK NDA vs what the paper may show (use gpdk045 for figures if needed);
no memory compiler -> smaller memories; runtime of a few hundred thousand cells (fine on a lab server, not this laptop);
keep the FPGA flow untouched so the paper's FPGA numbers stay reproducible.

### Phase W: write (about 2 to 3 weeks)
7. Paper draft: introduction, threat model, architecture, implementation (FPGA + ASIC), verification, evaluation,
   limitations, related work. Then internal review against the IPD-III corrections list (C1 to C10).

## 7. Decisions needed from Kalash
1. **Title and venue** (conference / journal and its deadline): fixes the page limit and the timeline.
2. **ASIC flow: college Cadence (decided 2026-11-06).** Still to confirm with the college: tools / versions, PDK (gpdk045 or foundry), memory compiler, server access (A0).
3. **ASIC memory size:** full 16 KB per memory (large die) or reduced for the ASIC (state it in the paper).
4. **Authorship / contribution table** (Lane 1, RISC-V lane, Engineer 4), as in IPD-III correction C10.
