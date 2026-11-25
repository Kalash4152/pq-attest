# Execution blueprint: from today to the final combined bitstream (13 Nov 2026)

Status: **PLAN ONLY. Nothing here is implemented.** Baseline: commit a55b035e, RTL = tag `rtl-rc1-20261112`.
HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

## 1. End goal

Execution amendment, approved by Kalash 2026-11-14: decision 3 / section 3.2's decoder restriction now covers
**every local instruction fetch outside IMEM**, including MMIO, not only DMEM. Data loads/stores are unchanged.
See signed rev-10 section 4b and reports/R10_FETCH_SCOPE_FINDING_20261113.md. This amendment governs wherever the
original plan below says "fetch from data memory". Execution status: reports/R10_EXECUTION_CHECKPOINT_20261113.md.

Kalash opens `NOC_PQATTEST.xpr`, types one command, presses **Generate Bitstream**, and programs the board:

```
source C:/vivado_verilog_proj/NOC_PQATTEST/scripts/merged_gui_runs.tcl
```

That command already exists and was proven on 12 Nov. It backs up the project, syncs the source sets from the generated
list (so the new hasher file and firmware v3 are picked up with no manual step), sets the release options and makes
`synth_merged` / `impl_merged` the active runs. The gate runs before the bitstream is written.
Bitstream: `NOC_PQATTEST.runs/impl_merged/pq_merged_board_top.bit`. No new Tcl file is needed; phase 5 re-tests this one.

## 2. Decisions (council + VLSI review, taken under Kalash's delegation of 13 Nov)

Framed question: which of the proposed changes go into the last RTL revision, given that the design is verified, timing
margin is thin (WHS +0.009 ns) and every change to a verified block forces re-qualification?

| Advisor | Position |
|---|---|
| Contrarian | Every touched verified file is a new risk. Touch only what the security claim needs. The NI fix (C3) re-opens a 1,949-line block for a bug that needs a response 35 times later than the worst measured. |
| First principles | The goal is "attested firmware is the firmware that runs". That needs C1 (measure all of IMEM) and C4 (no code from data memory). Nothing else changes the claim. |
| Expansionist | With C1 + C4 the paper can state full-firmware attestation and show an attack test that fails as it should. That is the highest-value addition per LUT. |
| Outsider | An estimate of +4,000 to +6,000 LUT is not a measurement. Measure before committing. |
| Executor | Trial build first, then one revision, one registry regeneration, one release build. |

| # | Decision | Outcome | Reason |
|---|---|---|---|
| 1 | C1 whole-IMEM measurement (rev 10 points 1, 2, 4) | **DO** | Fixes D-01; no protected file, no packet format |
| 2 | C2 firmware v3, button waits do not time out (rev 10 point 3) | **DO** | Fixes D-02; image changes anyway |
| 3 | C4 refuse instruction fetch from data memory | **DO, inside rev 10** | Completes the claim; demo firmware never runs code from RAM |
| 4 | C3 NI slot-race fix | **DO NOT; document** | Unreachable (16,384 vs 459 cycles); would re-open the NI regression. Changes my earlier "fix if rev 10 goes ahead" advice: rev 10 does not touch the NI, so this would widen the change |
| 5 | C5 stronger checks | **V-01 and V-02 only** | Both sit in benches that are re-run anyway; V-03 / V-05 documented |
| 6 | C6 re-run the two fault-injection controls; T4 coverage measurement | **DO now** | No design file changes |
| 7 | C8 timed re-attestation, C9 untrusted port on the board | **DO NOT** | Not needed for the claim; C9 exposes D-04 |
| 8 | C7 declaration-order fix (D-12) | **Defer to ASIC start** | Vivado accepts it |
| 9 | Board run of the current image | **Recommended now** (Kalash) | Validates the platform before the change |

Biggest uncertainty: measured area and timing of the extra SHA3 instance. What would change the verdict: trial build
over 47,550 LUT or timing not met (then fall back, section 6).

**Gate G0 (rule, not delegable):** revision 10 changes the security scope, so Kalash confirms it in writing
("rev 10 approved") before any design file changes. The draft will first be extended with decision 3.

## 3. Technical blueprint

### 3.1 New block `rtl/riscv/meas_imem_hasher.sv` (tile 3 only)

| Aspect | Design |
|---|---|
| Ports | Same as `meas_window_reader` (start, dedicated IMEM read port, 512-bit output, length, valid, busy), so it drops into `cpu_tile_noc` |
| Data path | Read 4,096 words through read port B (one-cycle latency). 34 words fill one 136-byte SHA3 block exactly. 120 full blocks + a final block of 16 words (64 bytes) |
| Hash | One `sha3_256` instance (existing module, multi-block path). Final block has 64 valid bytes, so the "exactly full final block" corner (D-08) is not reached |
| Output | bytes 0-31 digest; 32-35 length 0x00004000; 36-39 MEAS_BASE; 40-63 zero. `meas_valid` rises after the last block and holds until the next start |
| Restart | A start while busy restarts from word 0 (same rule as the old reader) |
| Reset | Synchronous, active high in the tile; convert for `sha3_256`'s `rst_n` |
| Selection | `cpu_tile_noc` parameter: tile 3 uses the hasher, tile 0 keeps `meas_window_reader` |
| Latency | About 8,000 cycles after reset; the core already holds the attestation start until `meas_valid` |

### 3.2 Other changes

| File | Change |
|---|---|
| `rtl/riscv/cpu_tile_noc.sv` | Reader selection parameter |
| `rtl/riscv/addr_decode.sv` | Fetch from data memory answers with the existing error path (decision 3) |
| `sw/riscv/demo_fw_v3.S`, `.hex` | Button waits unbounded; image padded to 4,096 words (all measured bytes defined) |
| `scripts/gen_closure_profile.py`, `check_closure_profile.py` | Profile 10: `hashlib.sha3_256` over the padded image, reference called with the new 64-byte field |
| `vectors/` generated headers | Regenerated |
| `synth/merged/pq_merged_board_top.sv` | `APPROVED_MEAS`, config profile 10, firmware name |
| `rtl/dual_lane/merged/pq_soc_merged_core.sv` | Only if the parameter must pass through |
| Benches | New includes; V-01 check replaced by a DUT-observed value; V-02 helper confirms acceptance |
| `scripts/make_merged_sources.py` output | New file in the list |
| Registry | New increment I-27, counts frozen before the first run |

Protected files, packet formats, endpoint, verifier, L2, NI, mesh, XDC: **unchanged**.

## 4. Phases, order and gates

| Phase | Work | Gate to pass | Est. |
|---|---|---|---|
| **0. Now, no design change** | Re-run the two controls (C6); measure coverage (T4); Kalash: board run of the current image, itemised | Controls kill; coverage numbers recorded | 0.5 day |
| **G0** | Extend rev 10 draft with decision 3; Kalash: "rev 10 approved" | Signed | - |
| **1. Trial (scratch copy)** | Hasher + tile change in a scratch copy; unit simulation against `hashlib`; full trial build with the release recipe | **G1:** LUT <= 47,550, WNS >= 0, WHS >= 0. Else section 6 | 0.5-1 day |
| **2. Implement** | Section 3 files, in logical commits: hasher + unit bench; tile + decoder; firmware v3; vectors / profile 10; board top; source list | Compiles; unit bench PASS (scratch) | 1 day |
| **3. Verify (I-27)** | `test_dual_lane.py`; freeze counts; one registry regeneration; `python scripts/dual_lane.py run --select I-27` | **G3:** all I-27 jobs PASS_FRESH; gate report written | 1-2 days |
| **4. Release build** | `final_project_update.tcl` flow (`merged_release.py`), run alone; reproduce once | **G4:** gate PASS, numbers recorded, image hash recorded | 2-3 h |
| **5. GUI flow** | Batch test of `merged_gui_runs.tcl` on a project copy with the new sources; then Kalash runs the command and presses Generate Bitstream | **G5:** copy test PASS; Kalash's build gate PASS; hash recorded | 1-2 h |
| **6. Board** | Kalash programs the image; itemised observations | **G6:** hardware record for that hash | Kalash |
| **7. Freeze** | Tag `rtl-rc2`; update sign-off report, STATUS, website data (new area / timing), memory note | Committed | 0.5 day |

I-27 job list (counts fixed at registration):

| Job | Proves |
|---|---|
| Hasher unit bench, 3 images, against `hashlib` | Correct digest over 121 blocks |
| Mutant: hasher skips one word | Bench detects a wrong digest |
| Closure, in-flight, contention, phase sweep, lifecycle with profile 10 | No regression |
| **Attack test: one instruction changed at >= 0x40** | Attestation FAILS (the case rev 9 missed) |
| Control for the attack test (approved value regenerated for the changed image) | Failure is due to the measurement |
| Fetch-from-data-memory test + mutant | Decision 3 works and is detected if removed |
| Profile 10 checker | Vectors match the pinned reference and `hashlib` |
| Matched latency / baseline re-run | Paper numbers for the final design |
| Board build (secure) + gate negative tests | LUT, WNS, WHS, firmware present |

## 5. What Kalash does

| When | Action |
|---|---|
| Phase 0 | Program the current image (`2b2518be...2913`); note LEDs, both UART texts, revoke within 2 minutes, re-attest |
| G0 | Reply "rev 10 approved" |
| Phase 5 | In Vivado: the command in section 1, then Generate Bitstream (about 25-45 min; lid open, on AC) |
| Phase 6 | Program `impl_merged/pq_merged_board_top.bit`; send the itemised observations |

Everything else is done by Claude, with a commit per logical group. `NOC_PQATTEST.xpr` stays uncommitted (standing practice).

## 6. Hard stops and fallbacks

| Trigger | Action |
|---|---|
| Trial or final LUT > 47,550 | Stop, report. Fallback: share the endpoint's Keccak core instead of a second one (needs a wider contract change) |
| Timing not met | Stop, report. Options to offer: register the hasher's block input / digest path; placement-directive sweep within the release recipe |
| Any FAIL needing a design or contract change | Stop, report |
| Attack test passes when it must fail | Stop: the change does not do its job |
| Expected count would need changing after freeze | Stop: never edited; a new job is registered instead |

Rollback: tag `rtl-rc1-20261112` and its image stay valid; all changes are in new or non-protected files.

## 7. Definition of done

1. I-27 gate PASS, release build gate PASS, numbers and image hash recorded.
2. `merged_gui_runs.tcl` proven on a copy with the new sources; Kalash's Generate Bitstream build passes the gate.
3. Board observations recorded against that image hash.
4. Tag `rtl-rc2`, sign-off report and website numbers updated.
