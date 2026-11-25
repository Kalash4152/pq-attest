# Independent RTL verification and pre GDS completion review

Date: 8 November 2026. Owner: Kalash Bheda. Review baseline: Git `2eda1e2c`, branch `noc/credit-integration`.

## Conclusion

The combined FPGA design exists, is integrated, and has passing registered simulation and implementation evidence. It is **not yet ready for an unconditional whole RTL sign-off or immediate ASIC implementation**. The remaining work is concentrated in contract reconciliation, several verification gaps, a small parameter-wiring correction, release automation, firmware acceptance, reproducibility, and the ASIC handover definition. A rewrite of the CPU, NoC, or crypto subsystem is not justified by this review.

Do not assign a numerical completion percentage: there is no agreed weighted denominator. “All major blocks implemented” and “all acceptance requirements closed” are different statements. Keep `SOC_INTEGRATION_COMPLETE=NO` until the agreed closure gate passes.

The supplied completion checklist is useful, but its proposed tasks are review input, not authorization to change security scope, clocks, budgets, contracts, or protected files. This review did not change RTL, the project, constraints, reference vectors, registry, or historical results. No new simulation, synthesis, formal proof, or board test was performed.

## Scope and method

- Read the supplied `PQ_Attest_Project_Completion_and_Research_Readiness_Checklist.docx` in full, including tables.
- Inventoried all top-level directories and recursively enumerated their files and nested directory counts. Git internals are metadata, not design collateral. Generated caches, snapshots, historical exports and backups were classified rather than mistaken for active sources.
- Checked the active merged 70-source list, source existence, duplicate module declarations, project XML, defines, firmware file, current source hashes against the registered I-17 snapshot, build scripts, constraints, final reports, and key integration/CPU/bridge/measurement/testbench behavior.
- Read original R4 requirements, the RISC-V brief, takeover plan, signed M-F1 revision 8, decision register, I-12 through I-17 evidence and current finalization questions.
- This is a targeted independent engineering review plus a complete folder inventory, **not a claim of line-by-line verification of every historical file or binary**, coverage closure, or exhaustive bug freedom. The evidence inventory accompanies this report.

## What is independently confirmed

| Item | Live result | Scope |
|---|---|---|
| Active source list | 70 existing sources, no duplicate module declarations in that list | Static preflight; not a fresh elaboration |
| Main project | `dl_merged_src` contains all 70 sources plus `demo_fw.hex`; top `pq_merged_board_top`; defines `PQ_MAC_ON`, `CPU_TILE_MODULE=cpu_tile_noc`, `REAL_CPU_TILE` | Project XML checked |
| Source identity | All 70 I-17 compiled-source hashes match the current live source files | Ties reviewed RTL to registered implementation evidence |
| I-12 | 1/1 PASS_FRESH; E4 389 pytest and 15 pipeline stages | Python/model verification, not RTL simulation |
| I-13 | 8/8 PASS_FRESH | Registered RISC-V unit/wrapper simulations |
| I-14 | 10/10 accepted, 2 fresh and 8 identity-matched reuses | Includes six mutant controls |
| I-15 | 2/2 PASS_FRESH | Real merged co-simulation and word-order mutant |
| I-16 | 9/9 PASS_FRESH | Decode, memory test, two programs, affected regressions and no-guard control |
| I-17 | 1/1 PASS_FRESH | Combined routed board design; clocks, firmware presence, route/DRC/timing gate |
| Latest detached build | `done.txt` says exit 0; bitstream completed 7 November at 21:38; 34,987 LUT, 25,276 FF, WNS +0.237 ns, WHS +0.035 ns | Latest combined FPGA build, not a new run in this review |
| Latest image SHA-256 | `ae0d894677dae2b8814653d1595e7c7dd483f01800b2cad358dffe9226b112c2` | Latest image differs from older packaged image |
| I-17 implementation details | 20 BRAM36, 0 DSP; TNS/THS 0; zero route/DRC errors; clean check_timing; generated 20 ns clock from 10 ns input | Registered routed design |
| Board | Owner reported “Board shows PASS” for image `d738b12b...67e3` | Not an independent hardware test; not proof for latest image |

Registered runs inspected: `20261106_210307_146335d7`, `20261107_030257_27d6857f`, `20261107_041824_5860345c`, `20261107_052418_df416a7c`, `20261107_133233_2d7fc6dd`, `20261107_181412_f2ba6d56`, each under `reports/dual_lane_10_...`.

## Findings requiring closure

### F1 CPU interrupt acceptance remains unverified against the original brief

**Priority: high. Category: firmware and verification; RTL impact depends on result.**

The original RISC-V brief A3 requires remote-read error handler entry before the next instruction retires, remote-write error handling, local-unmapped error handling, and an RVFI sequence check. `sim_riscv/tb_adapter_a3.sv` instantiates the adapter alone and proves poison/fault pulses and addresses, not CPU handler entry or retirement ordering. `rtl/riscv/tile_top.sv:178` wires the IRQ, but `sw/riscv/demo_fw.S:16` loops at the vector and the demo leaves interrupts masked.

Therefore “A3 complete” is too broad for the original brief. Add a real CPU error-handler/RVFI bench and effective controls. If the original retirement requirement cannot be met by the selected IRQ mechanism, stop for an explicit contract decision; do not rename a bus-fault pulse as proof of a precise exception. Keeping interrupts masked may be an intentional reduced demo scope, but requires an explicit accepted deviation. It cannot silently make this requirement optional.

### F2 Four promised merged scenarios are not covered by the existing merged test

**Priority: high. Category: verification.**

`rtl/dual_lane/merged/tb_merged_real.sv:96` revokes only after both demo CPUs have finished their one-shot work; line 98 establishes the commit baseline after a 300-cycle delay. The test proves stable denial state afterward, but cannot detect every commit during that delay and does not generate a new CPU access after revoke.

Register an I-18 or equivalent logical group for:

1. A real memory-side error reaching CPU A with correct poison, STATUS code and fault address.
2. Revoke while a request is active, with continuous write-enable/commit monitoring at the specified authorization boundary.
3. Application-port contention during attestation, with exact request/response accounting and bounded progress.
4. A real CPU retry after revoke being refused, followed by recovery/re-attestation as required by the selected contract.

Use the signed boundary: the first cycle in which `authorized[src]` is low, **not necessarily the raw button or RoT revoke pulse**. The contract permits propagation latency. Read suppression and write commit rules differ. Monitor each phase before and after the boundary. Every new required check needs an effective causal control, frozen counts, bounded timeout and a registered result.

### F3 Attestation request policy is open and configuration claims do not match the board input

**Priority: high. Category: owner decision and contract; conditional RTL.**

`pq_soc_merged_core.sv:107` and `:120` collect CPU `attest_req_o`, but only external `start_attestation` feeds start logic at line 139. Choose RoT-only or an explicitly defined CPU-request policy before sign-off. RoT-only can close this without adding a request path; CPU-request support requires busy/retry/measurement-coherency tests. A CPU STATUS write still starts the local measurement reader, so document or test that behavior even if it cannot start the RoT.

`synth/merged/pq_merged_board_top.sv:82` provisions CONFIG_DATA as bytes 00..0f, whereas CPU BUILD_ID at line 101 is `0x20261107`. The measured config is not currently assembled from the live TILE_ID/BUILD_ID registers, despite the contract's open wording. Either document fixed provisioned config honestly, or approve a new binding and re-provision/requalify its reference values. Do not merely change expected vectors to fit a new interpretation.

### F4 NI timeout parameter is not forwarded to CPU bridges

**Priority: medium. Category: definite RTL parameter-wiring defect outside the default configuration.**

`pq_soc_merged_core.sv:45` exposes NI_SLOT_TIMEOUT and forwards it to the subsystem, but the CPU instances at lines 97 and 110 omit `.NI_SLOT_TIMEOUT(NI_SLOT_TIMEOUT)`. Each CPU therefore keeps its default 8192 and uses that for its bridge drain interval (`cpu_tile_noc.sv`). The current default build is consistent; a nondefault merged parameter can break the intended relationship.

Forward the parameter to both real tiles, maintain explicit stub compatibility if retained, and test nondefault settings and timeout/drain recovery. Also validate supported timeout ranges against the NI's 16-bit age counter. This is not evidence that the current default image fails.

### F5 Release build does not enforce the registered implementation gate

**Priority: high. Category: Vivado automation.**

`scripts/merged_bitstream_flow.tcl:37` writes the bitstream without calling `merged_gate`. The registered `merged_impl.tcl` does call the gate, but does not itself emit the board bitstream. `merged_result` at `scripts/merged_project_update.tcl:131` checks that done/result files exist and that WNS/WHS parse as nonnegative; it does not validate the done exit code, artifact hash, complete gate verdict, or LUT limit in its success condition. LUT over 52,000 is printed separately after “BUILT, TIMING MET”.

Unify the final image with a fail-closed gate: successful child exit, correct part/top/clock, full routed gate, valid firmware in both CPUs, valid artifact and source hashes, and approved budget. Add negative tests for nonzero exit, missing/truncated result, missing image, negative/non-numeric timing, over-budget resources, and failed gate. Distinguish a failed sign-off from a successfully generated but unusable `.bit` file. Add a running-job guard to prevent a second `merged_build` from moving an active run directory or starting another implementation.

The I-17 firmware check currently proves nonzero INIT content in CPU A, not exact expected firmware or CPU B. Strengthen provenance/firmware checking for the final release; existing I-17 claims must retain their original scope.

### F6 Several original RISC-V acceptance details still need disposition

**Priority: medium to high. Category: contract, firmware, verification, small conditional RTL.**

- A8 asks for bounded polling, PASS/FAIL-first UART lines, `REFUSED OK`, cycle measurement and an actual post-revoke fault demonstration. Current `demo_fw.S:45` waits indefinitely for authorization; line 70 can wait indefinitely for UART space; line 65 parks forever after the first result. Implement v2 for the original brief, or explicitly accept deviations.
- The brief lists a bridge-status NI MMIO window at `0x10003000`. `addr_decode.sv` decodes IMEM, DMEM, UART, GPIO and STATUS, with no NI window. Decide whether to implement a defined status window or remove it from the accepted scope/map through a recorded deviation.
- The brief's synthesis debug definition is the last instruction fetch address. `tile_top.sv:387` assigns current `mem_addr`, which also represents data accesses. Correct the tap or its approved definition; it is not a retired PC. RVFI remains the correct simulation evidence for retirement.
- B4 originally describes the last fault; current STATUS intentionally retains the first fault until W1C. Preserve useful existing behavior and record the accepted semantic difference, including simultaneous clear/set tests.
- A4 source runs one transaction per seed in one process and prints a fixed “1000 completed” line. That is not the brief's per-seed process/log list or full sizes/alignment campaign. Preserve historical PASS scope; add counted completion, seed/result records and the missing memory-operation matrix. Do not infer those dimensions from the number 1000.

### F7 Layered error semantics need explanation rather than an unnecessary RTL change

The TMEM bridge intentionally returns zero with `tmem_err`; the adapter converts that error into CPU-facing `0xBADBE00x`. Thus “TMEM error data zero” and “CPU receives poison” can both be correct at different interfaces. Update the CPU memory contract and error table to name the layer. Distinguish these from the all-zero attestation error-response packet, which is a third contract. Keep causes 1 decode, 2 refused, 3 remote, 4 timeout, 5 local unmapped explicit.

### F8 Documentation and package reproducibility are not closed

`reports/NEXT_STEP.md` still points to I-11; `docs/STATUS.md` still points to pre-merge work; B5 notes say unregistered although I-14 registers it; merged source/XDC headers still say skeleton/not registered. These are stale descriptions, not failed RTL tests.

`scripts/make_team_package.py` reorganizes sources under `rtl/<original path>` and flattens scripts while their code expects repository-relative `scripts/`, `synth/`, `sw/` and other paths. It omits the standard harness and several include/reference dependencies. The README's full-repository commands do not make this ZIP a standalone reproducible release. It is a review package until proven otherwise. Produce a path-preserving release with all dependencies and a clean-directory replay.

The latest bitstream hash is `ae0d...12c2`; the earlier team package points to `fa0b...cd51`, and the reported board PASS points to `d738...67e3`. Keep all three records distinct. A changed bitstream hash alone is not proof of changed logic or functional failure, but it needs an explicit provenance record.

## Corrections to the supplied checklist

1. Keep its definition of completion against a frozen scope and its separation of RTL, simulation, board and ASIC evidence.
2. Correct the board baseline: revoke/re-attest is expected functionality, not itemized owner-observed evidence yet.
3. Add F1, F4, F5 and the omitted brief details in F6; the checklist currently understates these.
4. Do not mark all module/security tests as unperformed simply because boxes are empty. Map each requirement to existing I-1..I-17 evidence first; add only genuine gaps and affected requalification.
5. “Read error returns zero versus poison” is primarily an interface-layer clarification, not necessarily a contradictory implementation.
6. Measure revocation against the signed authorization boundary and bounded delivery semantics, not instant cancellation at a raw request pulse.
7. The initial 64-byte boot stub jumps to application code beyond the measured window. Do not claim full firmware integrity, even if later application code is read-only. Fixed demo nonce/secrets do not establish deployment freshness. Link replay/sequence tests have a different scope from fresh challenge attestation.
8. The old insecure N-13 baseline exists. What is missing for a research comparison is a matched **combined two-CPU** baseline and final workload measurements; do not say no baseline ever existed.
9. A fair baseline, latency and research plots can run in parallel after freeze. They are research-readiness work, not inherently prerequisites to starting ASIC synthesis. If the owner includes them in pre-GDS completion, track them as a separate exit criterion.
10. Do not require UVM, a new simulator, formal security proof, TRNG or public-key PQC to close the existing release unless explicitly added to scope. Formal implementation equivalence in the ASIC flow is distinct from proving security properties.
11. Do not push a tag or publish a release automatically. Prepare a local frozen release and tag after the agreed evidence is complete; remote publication is a separate authorized action.

## Full remaining work before the GDS flow

The order below is a plan, not a claim that these tasks have run or approval of open decisions.

| ID | Work | Completion criterion | Owner/dependency |
|---|---|---|---|
| P01 | Resolve final release scope | Written decisions for CPU attestation initiation, original A3/A8 semantics, config binding, NI MMIO, firmware/toolchain and explicit exclusions | Kalash; blocks dependent changes |
| P02 | Close interface contract | Numbered M-F1 note for sections 7–9; exact parameters, byte order, memory latency/map, fault layers and revocation boundary; any true wire change uses a new revision first | RTL team after P01 |
| P03 | Correct bounded RTL issues | NI timeout forwarding; selected debug/MMIO/request-path changes only; parameter limits tested | RTL team; protected files untouched |
| P04 | Close CPU error behavior | CPU read/write/local-error handler tests and RVFI ordering, including masked/unmasked behavior and no poisoned-data use where required | Verification + firmware; stop for contract conflict |
| P05 | Complete accepted firmware | Bounded loops, precise result text, post-revoke access, fault/status handling and cycle-counter behavior; reproducible hex/header generation | Firmware; preserve or explicitly revise boot profile |
| P06 | Execute missing merged scenarios | I-18 error/in-flight revoke/contention/post-revoke retry tests plus causal controls, per-cycle side-effect checks, bounded progress | Verification after P02–P05 |
| P07 | Build requirement-to-evidence matrix | R4 NoC/PQ, RISC-V A1–A10/B1–B7, integration and E4: every requirement PASS with evidence, accepted deviation, or open; separate models and RTL | Verification/docs |
| P08 | Register remaining required stress evidence | A2/A4 conformance/random campaigns with exact counts, seeds, operation matrix and termination; preserve existing checks; register any required legacy bench | Verification; Vivado/XSim only |
| P09 | Close security and reset coverage | Audit invalid tag/identity/epoch/sequence/window, malformed traffic, exhaustion/recovery, slot lifecycle, reset at protocol phases, valid+malicious traffic; add missing cases only | Verification; scoped attacker model |
| P10 | Requalify final source closure | Harness tests before registry change, frozen new counts, one registry regeneration per group, applicable NoC/PQ/I9–I18 regressions on final source identities, no unexplained failures | Verification; after changes |
| P11 | Harden final build/result flow | One gated image path, concurrency guard, exit/hash/budget/gate enforcement, both-CPU firmware provenance and negative automation tests | Vivado/scripts |
| P12 | Final implementation and project reconciliation | Main merged fileset/defines/XDC/firmware match source manifest; isolated combined implementation passes clock/route/DRC/setup/hold gate; review timing exceptions and hierarchy | Vivado; keep original clock/device/pins |
| P13 | Itemize final board evidence | Program exact final hash; record LEDs/UART/reset/revoke/re-attest/post-revoke refusal and actual repeat count; preserve failures | Kalash; no remote board access assumed |
| P14 | Freeze complete release and docs | Current status/README/contract/design log/error map/limitations, source+script+firmware+XDC+bitstream hashes, review package replay from clean directory, final sign-off report/local tag | Docs/release |
| P15 | Complete selected pre-GDS measurements | Matched secure/insecure combined baseline; defined attestation/revoke/memory latency and throughput; raw CSV/JSON, controls and configuration IDs; power only if supported | Research verification; after freeze, can overlap P16 |
| P16 | ASIC feasibility and handover decision | Actual college tool versions/licenses, PDK/legal use, libraries/corners, SRAM models/ports/init, LEF/RC/rule decks, IO/pads, compute and DFT decision; written go/no-go and approved ASIC configuration | Kalash/college + physical design team |

No run-time estimate is reliable until P01 decides the error/IRQ scope and P16 establishes the memory/tool environment. P03 is a small bounded correction; P04/P06/P09/P10 are the substantial verification work.

## Verification closure matrix to prepare

Use one row per requirement, not one row per file. Minimum columns: requirement ID; frozen specification/revision; tested module/configuration; expected check count; source identity; reference identity; job/run ID; result; causal mutant and observed kill; log path; coverage limitation; accepted deviation; reviewer.

Required review families:

- CPU/adapter: real-core transfers versus captures/responses at drain, compressed/back-to-back fetch, stalls, error IRQ/retirement, local and remote faults, widths/alignment, distinct programs.
- NoC/NI: supported source/destination and VC/routing matrix, credits/FIFO boundaries, stalls/fairness, malformed framing, request tag reuse, stale responses, repeated timeouts and reset cleanup.
- Crypto/attestation: pinned Python reference and KAT boundaries, configuration/IMEM split, exact 64-byte profile, tag/identity/epoch mismatch, interrupted/busy transactions, fail-closed grant.
- Memory/bridge: all byte lanes/window boundaries, write commit authorization, read suppression, one outstanding, late drain, concurrent valid/malicious traffic and resource recovery.
- Merged/board: P04/P06 cases, real firmware loading in both CPUs, provisioned measurement, boot/reset sequence, end-to-end observed results on the exact final image.

Coverage percentages, universal DoS resistance, formal proof and physical fault/side-channel resistance are not established by this review. Do not infer them from a large PASS count. Python E4 tests supplement the RTL checks rather than replace them.

## What is not missing FPGA RTL by default

UART RX, another CPU, TRNG, public-key PQC, full-IMEM measurement and a higher clock are feature extensions. They do not need to be added to finish the present scope. GCC is unnecessary for the current assembly image unless the selected C workload requires it. Do not enlarge security claims to avoid documenting these limits.

## ASIC handover boundary

The FPGA design is not yet an ASIC-portable sign-off target. Before starting the GDS flow, P16 must decide:

- Core-only versus pad-inclusive top, allowed external clock/reset behavior and test-mode ownership.
- Replacement boundary for MMCM/BUFG and FPGA power-up initialization; reset/read-before-write behavior must remain specified.
- Memory implementation: two CPUs each with 16 KB IMEM and 16 KB DMEM plus 16 KB shared memory, 80 KB total; dedicated IMEM measurement port needs compatible macro behavior or an approved arbitration model.
- Firmware/boot and key provisioning. `$readmemh` in FPGA synthesis is not an ASIC loading mechanism; choose ROM/loading and distinguish demo constants from deployed secret storage.
- SRAM wrappers and collision/latency/byte-write semantics; a macro compiler is not assumed. Without compatible macros, choose an explicitly labelled alternative or revise scope, rather than asserting smaller memories are unavoidable.
- ASIC SDC for actual IO/load/driving cells/corners. Do not copy the FPGA board's zero IO delays and broad human-IO false paths as ASIC sign-off constraints.
- Scan/test/MBIST goal or explicit academic demonstrator exclusion; tie-offs and functional-mode safety; no invented ATPG coverage.
- Equivalence and re-verification plan for the ASIC wrapper, memories and initialization. Implementation LEC is separate from security proof.

Only after the FPGA release scope is closed and ASIC handover is accepted should a separate ASIC source list/configuration proceed to synthesis, equivalence, floorplan, placement, CTS, routing, extraction, STA and physical sign-off. Do not claim GDSII or ASIC PPA from the present FPGA numbers.

## Folder classification

Active authority is the explicit merged source list and its verified dependencies, not “every .sv in the repository”.

- Active design and tests: `rtl/`, `synth/`, `NOC_PQATTEST.srcs/`, `sim/`, `sim_riscv/`, `vectors/`, `sw/`, `scripts/`.
- Specification/reference/verification: `docs/`, `software/`, `golden/`, `verification/`, `automation/`.
- Evidence/release: `reports/`, `logs/`, `releases/`, `_export/`, `riscv_a1/`.
- Vivado generated/project state: `NOC_PQATTEST.cache`, `.gen`, `.hw`, `.ip_user_files`, `.runs`, `.runs_s4`, `.runs_merged`, `.sim`, `vivado_p7/`, `vivado_sim/`, `.Xil/`.
- Historical/support material: `_recovery_backup/`, `mut/`, `WP0_package/`, `WP0_r2/`, `Claude outputs/`, `.claude/`, `.pytest_cache/`, root ZIPs and project backups. These were inventoried; they are not all final-build dependencies. Nothing was deleted.

## Final answer for Kalash

**All three major RTL lanes are implemented and combined. Whole RTL acceptance is still open.** The next substantive work is to resolve the scope questions, close CPU error and merged adversarial verification, correct the timeout parameter forwarding, enforce one trustworthy final Vivado gate, and create a reproducible signed-off release. Board details and college ASIC prerequisites are separate dependencies. Research experiments should be tracked explicitly rather than used to claim that the functional RTL is either entirely missing or already 100% complete.
