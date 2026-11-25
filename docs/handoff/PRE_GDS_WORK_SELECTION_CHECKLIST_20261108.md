# RTL verification and pre GDS work selection checklist

For Kalash Bheda. Independently reviewed 8 November 2026 against the live repository, the original plans and your completion checklist.

**Conclusion:** the two CPUs, NoC and PQ-Attest are implemented and combined. The current image meets FPGA timing. Whole RTL acceptance still has open contract, verification and release items. There is no justified exact completion percentage.

## How to fill this in

Tick **Select** for work you want done. Leave it blank to hold; write **defer** or **out of scope** explicitly where appropriate. A tick authorizes only the described work; a listed contract/security decision must be answered before its dependent implementation. You can return this Markdown file or reply with item IDs and option letters.

Selection boxes are **not completion marks**. “Done” means supported by evidence, not selected for future work. Existing verified milestones are listed separately below. No work selected here has been run by this review.

## Existing baseline checked live

| Area | Evidence checked | State |
|---|---|---|
| Two real CPU tiles at 3 and 0 plus NoC plus PQ-Attest | Active 70-source merged list; no missing sources or duplicate module declarations | Implemented and integrated |
| Vivado main project | `dl_merged_src` contains all 70 sources plus firmware; correct top and defines | Source fileset matches |
| Current source identity | 70/70 hashes match the registered I-17 compiled sources | Matched |
| Registered verification | I-12 model suite and I-13 through I-17 gates | PASS within each recorded scope |
| Latest combined build | 34,987 LUT; 25,276 FF; 20 BRAM36; WNS +0.237 ns; WHS +0.035 ns | Build completed 7 November 21:38 |
| Board | Kalash reported PASS on an earlier image | Latest image and itemized observations not confirmed |
| Final release | SOC_INTEGRATION_COMPLETE remains NO; formal security proof NO | Open |

Latest image SHA-256: `ae0d894677dae2b8814653d1595e7c7dd483f01800b2cad358dffe9226b112c2`.

## A Decisions before dependent changes

### D01 Who may initiate attestation

- [ ] **Select D01** — Close the attestation initiation policy.

Choose one: **A RoT/button only**; **B CPU may request and RoT decides**; **C another explicitly specified policy**.

Recommendation: A for the present release. Today CPU request outputs are not connected to RoT start. If B/C, define busy handling, retries, request ownership and measurement stability, then implement and test them. Even under A, document/test the CPU request's existing local measurement-reader effect.

**Answer:**

### D02 CPU bus error acceptance

- [ ] **Select D02** — Decide whether to meet original A3 IRQ/retirement requirements or explicitly revise the scope.

Choose **A meet the original brief**; **B accept poison plus sticky STATUS and recorded IRQ wiring without claiming handler/retirement behavior**.

Recommendation: A. Existing adapter tests prove fault signaling, not real CPU handler entry before the next retired instruction. Firmware currently masks IRQs. If tests reveal the promised ordering cannot be achieved without a design/contract change, stop and review that change before implementing it.

**Answer:**

### D03 What is bound into measured config

- [ ] **Select D03** — Freeze the meaning of the 16 config bytes.

Choose **A retain fixed provisioned demo bytes and document them**; **B bind actual TILE_ID/BUILD_ID fields**.

Recommendation: A for minimal change unless the paper requires build identity binding. The current board config is bytes 00..0f; it is not assembled from CPU BUILD_ID. B needs explicit byte layout, provisioning and reference requalification.

**Answer:**

### D04 Final firmware scope

- [ ] **Select D04** — Choose **A firmware v2 matching the original demo brief** or **B retain the one-shot v1 with accepted omissions**.

Recommendation: A. Include bounded waits, explicit pass/fail output, post-revoke retry, appropriate error handling and defined cycle measurements. Changing the IRQ code within the first 64 bytes changes the measured boot image and therefore requires approved re-provisioning; do not promise APPROVED_MEAS stays unchanged before the implementation is designed.

**Answer:**

### D05 Remaining interface differences

- [ ] **Select D05** — Decide **A implement the brief's NI status MMIO window at 0x10003000** or **B explicitly exclude it**.
- [ ] **Select D06** — Accept/document **first fault until W1C** STATUS behavior, or request a defined change to the brief's “last fault” behavior.
- [ ] **Select D07** — Keep assembler-only firmware, or request an exact approved GCC version for C workloads. GCC is not required for the current assembly demo.
- [ ] **Select D08** — Agree final sign-off criteria: accepted scope; required registered verification; gated final image; exact-image board record if required for the release; reproducible archive and local sign-off tag. Remote publication is separate.

**Answers D05–D08:**

## B RTL and contract work

- [ ] **Select R01 — Forward NI_SLOT_TIMEOUT to both CPU tiles.** Definite nondefault-configuration wiring issue; current defaults match. Done when timeout/drain stays consistent for tested supported nondefault settings and default regressions still pass. Maintain stub compatibility if the stub remains supported.
- [ ] **Select R02 — Check parameter boundaries.** Supported NI timeout versus 16-bit age counter, timeout/drain inequalities, memory sizes/windows and measurement base/alignment. Reject unsupported values or define behavior; do not silently expand the supported configuration.
- [ ] **Select R03 — Correct or formally redefine debug address tap.** Today dbg_pc_o is the current memory address, including data accesses. Match the agreed last-instruction-fetch definition; use RVFI for retired PC tests.
- [ ] **Select R04 — Implement selected policy/MMIO/config changes.** Only items selected in section A; each needs its contract first and targeted tests afterward. No new features implied.
- [ ] **Select R05 — Close M-F1 sections 7–9 and interface tables.** Exact measurement/config bytes, initiation policy, one-cycle BRAM read latency, 16 KB shared window, timeouts, read suppression and write authorization boundary.
- [ ] **Select R06 — Publish layered error semantics.** TMEM bridge error data zero; CPU adapter returns poison; attestation error packets have a separate all-zero payload rule. Include exact fault/status values and side-effect rules.
- [ ] **Select R07 — Complete selected firmware.** Bound authorization/UART waits, correct result strings, post-revoke access, fault handling and measurement instrumentation. Validate generated hex/include and provisioning against the pinned reference.

## C Verification work

These are completion tasks, not a request to weaken existing checks or replace actual evidence with a new checklist.

- [ ] **Select V01 — Real CPU error-handler and RVFI tests.** Remote read/write and local-unmapped faults, masked/unmasked behavior, handler entry and retirement/data-use ordering as agreed in D02. Add controls that expose missing IRQ/error behavior.
- [ ] **Select V02 — Merged remote-error path.** Actual memory-side error reaches CPU poison, fault code and address; no silent successful transaction or unintended write.
- [ ] **Select V03 — Revoke during an active write/read.** Sweep relevant phases; continuously monitor BRAM enables/commits and response behavior. Use the signed authorization-low boundary, not zero-latency cancellation at the raw revoke pulse.
- [ ] **Select V04 — Traffic contention during attestation.** Prove bounded progress, exact request/capture/response counts, no loss/duplication/corruption, and correct arbiter ownership.
- [ ] **Select V05 — Real CPU access after revoke and recovery.** CPU A actively retries and is refused; then test the agreed re-attestation/recovery sequence. A parked CPU with no new commits is insufficient.
- [ ] **Select V06 — Nondefault NI timeout and late-drain tests.** Repeated timeouts, stale responses, slot reuse and subsequent valid traffic; verify R01/R02.
- [ ] **Select V07 — Conformance and random-latency evidence closure.** Register required legacy benches; preserve 1,000-transaction checks; count actual completed seeds/transactions; save per-seed results and operation-size/alignment coverage. One transaction per seed is not a complete memory-operation campaign.
- [ ] **Select V08 — Requirement-to-evidence matrix.** Map original NoC/PQ plans, RISC-V A1–A10/B1–B7, integration and E4 requirements to exact runs, checks, source identities, controls, accepted deviations or remaining gaps. Empty checklist boxes alone do not mean existing tests were never run.
- [ ] **Select V09 — Security and reset gap tests.** First audit existing coverage; add missing tag/identity/epoch/sequence, malformed framing, window/byte-lane, exhaustion/recovery, reset-during-transaction and simultaneous valid/malicious traffic cases. Document attacker capability and evidence layer.
- [ ] **Select V10 — Register I-18 or equivalent closure group.** Freeze counts before execution, add causal mutants, bounded fail/timeout rules and machine-readable results; preserve failed runs unchanged.
- [ ] **Select V11 — Final affected regression.** Run approved harness checks and relevant NoC/PQ/CPU/merged jobs against final source identities after all selected changes. No unexplained failures; all omissions explicitly accepted.

**Verification exclusions or additions:**

## D Vivado and release build work

- [ ] **Select B01 — Make the actual bitstream path enforce the full registered gate.** Today the release bitstream writer and registered gate are separate. Final image must have a PASS gate, correct part/top/clocks, clean route/DRC/check_timing, setup/hold closure and approved resource limits.
- [ ] **Select B02 — Harden merged_result and build concurrency.** Check child exit code, parse failures, full gate verdict, LUT bound, image existence/hash and provenance; refuse overlapping implementation launches. Add negative tests for each refusal.
- [ ] **Select B03 — Verify firmware in both CPUs.** Current gate checks nonzero INIT in CPU A, not exact expected images in both CPUs. Establish reproducible image/source provenance and appropriate netlist checks.
- [ ] **Select B04 — Reconcile final main project.** Source filesets, definitions, includes, firmware and XDC match the frozen manifest. Keep old native runs clearly identified as historical; use the explicit merged flow for combined results.
- [ ] **Select B05 — Build and archive the final gated combined image.** Both real CPUs, NoC and PQ-Attest; utilization/hierarchy/timing/DRC/route/clock reports, source/firmware hashes and exact build configuration.
- [ ] **Select B06 — Review timing exceptions and reset crossings.** Document asynchronous human/UART IO and synchronizer/reset assumptions. Existing clean check_timing is useful but is not a CDC/RDC proof or an ASIC IO constraint specification.

## E Documentation reproducibility and board record

- [ ] **Select C01 — Update current navigation/status documents.** NEXT_STEP, STATUS, B5 notes and skeleton-era comments currently lag later evidence. Keep historical gate records intact.
- [ ] **Select C02 — Replace unsupported completion claims.** Separate implemented, registered RTL simulation, Python model, routed FPGA, owner-reported hardware and formal proof. A3's original CPU acceptance remains open unless explicitly changed.
- [ ] **Select C03 — Assemble a reproducible release.** Preserve repository paths, include all scripts/reference/include dependencies and a frozen manifest. The existing team ZIP is suitable for review but has not established clean-folder replay.
- [ ] **Select C04 — Validate release replay.** New directory, documented dependencies, compile/simulation/build through the approved Vivado flow; record exact commands and results. No ZIP restoration over the working project.
- [ ] **Select C05 — Itemized final-image board record.** Kalash programs the exact final hash, records LEDs and both UART outputs, reset, revoke, re-attest and active post-revoke refusal; record actual repeats and failures. Existing owner-reported PASS belongs to an older hash.
- [ ] **Select C06 — Final sign-off report and local release tag.** All selected mandatory criteria closed; accepted omissions and limitations explicit. Remote push only if separately authorized.

## F Measurements before GDS if selected

These support the paper and evaluation. They can overlap the ASIC feasibility work after RTL freeze; they are not missing functional blocks.

- [ ] **Select M01 — Matched combined insecure baseline.** Same two CPUs, NoC, memories, clock, workload and implementation conditions; controlled security bypass/removal. Existing old N-13 insecure results are not an equivalent combined-system comparison.
- [ ] **Select M02 — Attestation and revocation latency.** Define exact start/stop events, cycles/ns, workload and outstanding-request handling; distinguish requested revoke from effective commit denial.
- [ ] **Select M03 — Secure memory and NoC overhead.** Reads/writes, latency, throughput and contention under identical configurations; distributions only with a justified repeat protocol.
- [ ] **Select M04 — Publish raw experiment data and claim matrix.** CSV/JSON, scripts, configurations, seeds, hashes and limitations; model/RTL/board/ASIC results separated. No invented power or security claims.

**Must these measurements block your FPGA RTL sign-off, or run afterward in parallel with ASIC preparation? Answer:**

## G ASIC prerequisites before starting the flow

- [ ] **Select G01 — College tool and PDK discovery.** Exact licenses/versions, access, legal academic use, standard-cell libraries/corners, tech LEF, RC/extraction and DRC/LVS decks, compute/storage.
- [ ] **Select G02 — Memory and boot decision.** 80 KB total current memory; SRAM macro ports/latency/byte enables and IMEM measurement read port; ROM versus loading, initialization/reset semantics and provisioning. No compiler or macro availability assumed.
- [ ] **Select G03 — ASIC top and IO plan.** Core-only versus pads, external clock/reset, removal/replacement of FPGA-only primitives, real ASIC SDC/load/drive/corners; preserve the FPGA baseline.
- [ ] **Select G04 — DFT scope decision.** Scan/ATPG/MBIST requirements or explicit academic-demonstrator exclusion; test modes and functional safety. Do not invent manufacturing coverage.
- [ ] **Select G05 — Equivalence and verification handover plan.** ASIC wrapper/memory changes compared against frozen functional baseline; LEC versus security proof distinguished; define required macro models and netlist tests.
- [ ] **Select G06 — Written go/no-go for ASIC start.** Accepted FPGA closure/deviations and complete ASIC prerequisites; choose supported ASIC configuration before synthesis/floorplan/CTS/route/sign-off begins.

## H Optional extensions outside the current completion scope

Leave these unselected unless you intentionally expand the project. Each needs its own specification and requalification.

- [ ] **Select X01 — Full-program measurement beyond 64 bytes.** New measurement profile/reference/provisioning and claim scope.
- [ ] **Select X02 — Fresh challenge/nonce generation and lifecycle.** Explicit trusted source, reset/rollback model and replay requirements; no simple LFSR-as-TRNG assumption.
- [ ] **Select X03 — Attest tile 0 as well.** New provisioning and a defined isolation demonstration.
- [ ] **Select X04 — Formal security/property proofs.** Tools, assumptions, bounds and proof scope agreed first.
- [ ] **Select X05 — More timing/area optimization.** Preserve functionality and signed 20 ns target; demonstrate measured benefit.
- [ ] **Select X06 — Other extension.** UART RX, extra CPU, C benchmarks or another specifically defined feature.

**X06 description:**

## Selection summary for Kalash

**Decisions and option letters:**

**Work IDs selected now:**

**Work IDs deferred:**

**Accepted exclusions or deviations:**

**Board work I will perform:**

**College information I can supply:**

**My final definition of whole RTL complete:**

Recommended order: decisions → contract → bounded RTL/firmware changes → CPU/merged verification → affected regression → gated final image → board/release record → accepted FPGA freeze. ASIC discovery can proceed in parallel; ASIC implementation starts only after its handover/go decision.

Detailed findings and source locations: `reports/RTL_AND_PRE_GDS_CLOSURE_REVIEW_20261108.md`. Folder/source evidence: `reports/rtl_closure_review_20261108/`.
