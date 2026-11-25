# S4 contract: area package (written before any S4 change, 2026-11-04)

Kalash approved items 1-4 of reports/area_study_20261104/AREA_STUDY.md (2026-11-04, "Approve items 1-4"). Base: release
DUAL_LANE_10_20261103 (I-6 / I-7 RTL, S3 list). No signed bound, latency, wire format, clock, pin or device change. Router
RTL untouched. The timing lever (lookahead router variant) is NOT part of S4.

## 1. What changes

| ID | Item | Where | Change |
|---|---|---|---|
| S4-F1 | synthesis `-flatten_hierarchy rebuilt` | P7 implementation flows only: the registered OOC P&R child (job field `synth_flatten`), the N-13 flow (`scripts/n13_impl.tcl`), the project runs | flow setting; same RTL. Simulation is unaffected. |
| S4-F2 | synthesis `-directive AreaOptimized_high` | same flows (job field `synth_directive`) | flow setting; same RTL |
| S4-A5 | KMAC wrapper state copy removed (the S3-A5 change, re-measured as a gain under S4-F1) | new variants by `scripts/prepare_s4.py` from pinned sources: `rtl/dual_lane/kmac_128_a5.sv` (module kmac128; L2 engine E3, verifier E4) and `rtl/dual_lane/kmac_128_xp_a5.sv` (module kmac128_xp; tile-3 shared engine E1); the S4 list swaps them for `kmac_128.sv` / `kmac_128_xp.sv` | absorb base = 0 in BLOCK0, else the core's held `state_out`; squeeze reads `state_out`; the 1,600-bit copy is deleted. Cycle-identical; same tags. S3 files are not edited. |
| S4-SOC | SoC output profile | `synth/p7_soc/pq_p7_soc_core.sv`: the subsystem with the observation-only exports unconnected (endpoint_response, L2 / ingress / quarantine / peer / memory / endpoint / verifier counters and reasons, gate fault counters, memory_last_data). Kept: authorization, attestation status, app handshakes, raw-port ready, memory_commits, the I-6 fault status. | no subsystem RTL change; the benches keep every port. This is the area of record for SoC integration. |

Hierarchy check under S4-F1 (`scripts/d4_crypto_ooc_child.tcl`): `-flatten_hierarchy rebuilt` legitimately merges
`kmac_absorb` into its parent KMAC (measured on the area-study netlist: every other expected instance stays present). When
the job's `synth_flatten` is `rebuilt`, the three `.../u_kmac_absorb` rows become informational; their parent `kmac128` /
`kmac128_xp` rows stay gated (present, right module, non-empty). Every other row is unchanged. Recorded as SYNTH_OPTIONS.

## 2. Invariants

- S4-A5: cycle-identical to the S3 wrappers; the same tag for every input (golden vectors, L2 engine digests, full chain).
- S4-F1 / F2: the RTL and every simulation are unchanged; only the netlist structure changes. Area and timing are
  measured by the S4 P&R jobs; the N-13 gate (WNS / WHS / WPWS >= 0, TNS / THS = 0, 0 route / DRC errors, check_timing
  clean, LUT <= 47,550) applies unchanged.
- S4-SOC: the kept outputs are exactly the list above; nothing functional is removed (the dropped outputs feed nothing).

## 3. Jobs (counts frozen here, before the first run)

Selection `s4`:
- `s4_variant` (python `scripts/check_s4.py`, marker `S4_VARIANT: PASS`): the two A5 files equal their generation;
- every release (`rel`) job whose source list holds `kmac_128.sv` or `kmac_128_xp.sv` (54 jobs), re-pointed to the S4
  list, counts unchanged, plus the 5 Python jobs they depend on (s2_vectors_check, s3_variant, i6_benches,
  i6_retry_vectors, i7_vectors); ids `s4_<release id without rel_>`;
- `s4_mut_absorb_zero_xp`: A5 control on `kmac_128_xp_a5.sv` (blocks 1-2 absorb from zero), on `s4_s3_s8_golden`; oracle
  `^\[FAIL\] G\d\d_`, kill scope the same;
- `s4_mut_absorb_zero_core`: the same control on `kmac_128_a5.sv`, on `s4_s3_l2e_engine`; oracle `^\[FAIL\] L2E_DIGEST`,
  kill scope `^\[FAIL\] L2E_(DIGEST|RST_\w+_FRESH_OK)`.

Selections run alone, one after the other: `s4_pnr` (`s4_p7_pnr`, OOC, all ports, S4 list, F1 + F2), `s4_soc_pnr` (`s4_soc_pnr`,
OOC, `pq_p7_soc_core`), `s4_n13_secure`, `s4_n13_insecure` (N-13 tops, F1 + F2; the secure top keeps every output
observable as R4 requires).

## 4. Acceptance

All `s4` jobs PASS_FRESH (controls KILLED); the four implementation jobs PASS their gates. Report LUT / FF / WNS / WHS
against the release (OOC 37,666 / +0.358; N-13 secure 38,054 / +0.260; insecure 11,848 / +0.460). Expected (area study,
estimates): OOC about 31.5k LUT, SoC profile about 32k LUT. A timing FAIL in N-13 is a HARD STOP (CLAUDE.md).
Gate report reports/S4_GATE_<date>.md. HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.

## 5. Notes before the first run

- Lint (scripts/rtl_lint_waivers.json): the A5 copies carry the same inherited production line as `kmac_128_xp.sv:202`
  (`final_block[(msg_len_reg + ...)*8 +: ...]`, the waiver that still awaits Kalash's acknowledgement). Two waivers with the
  same text and reason, line- and hash-pinned: `kmac_128_a5.sv:204`, `kmac_128_xp_a5.sv:211`. No other lint finding.
- Harness (scripts/dual_lane.py): job fields `synth_flatten` (none | rebuilt) and `synth_directive` ('' | AreaOptimized_high)
  are validated and passed to the implementation children as SYNTH_FLATTEN / SYNTH_DIRECTIVE; absent = the old flow.


## 6. Revision 1 (2026-11-05, before any revision-1 change): S4-F3 mesh split

Why: the S4 gate FAILED (`s4_p7_pnr` WNS -0.018 ns, reports/S4_GATE_20261104.md); `-flatten_hierarchy rebuilt` deepens the
protected router path (27 logic levels vs 21). Kalash delegated the decision ("decide and move ahead", 2026-11-05). Measured
(not evidence): KEEP_HIERARCHY on the NoC makes it worse (reports/s4_hier_study_20261105, H1 -0.365 / H2 -0.477 ns); the T4
lookahead router variant gives +0.016 ns only (parked, docs/decisions/T4_LOOKAHEAD_CONTRACT.md sec. 5); **M1, the protected
mesh synthesized out of context with the release settings and linked into the S4-synthesized rest: 32,457 LUT, WNS +0.334 ns,
WHS +0.013 ns, 21 levels** (reports/s4_m1_study_20261105).

S4-F3 (implementation flows only; RTL and simulation unchanged): when a job sets `synth_mesh_split: true`,
1. `noc_mesh_3x2` is synthesized alone, out of context, from the job's own sources, with the release settings
   (`-flatten_hierarchy none`, no directive, `-generic LINK_PIPE=1`, 20 ns clock on `clk`);
2. the rest of the design is synthesized with S4-F1 + F2, the mesh as a black box (fixed declaration
   `synth/s4/noc_mesh_3x2_bb.sv`, same ports, used only by this flow and never with `noc_mesh_3x2.sv` in one synthesis);
3. both checkpoints are linked (`link_design`, mesh checkpoint scoped to the single `noc_mesh_3x2` instance), then the
   unchanged S1-PNR-DIR implementation runs.
Fail-closed: exactly one `noc_mesh_3x2` instance; every instantiation in the job's sources is `#(.LINK_PIPE(1'b1))`; no black
box left after link; mesh cell count > 0.

Jobs (counts frozen here): the `s4` selection is unchanged (re-run because the registry changes); four new implementation
jobs replace the failed ones in the S4 increment, same tops / sources / gates plus `synth_mesh_split: true`:
`s4r_p7_pnr` (sel `s4r_pnr`), `s4r_soc_pnr` (sel `s4r_soc_pnr`), `s4r_n13_secure`, `s4r_n13_insecure`. The S4 FAIL / INVALID
records stay as history; nothing is relabelled. Acceptance as sec. 4 with the s4r jobs; OOC margin target >= +0.2 ns (report).
Project bitstreams use the same split flow (batch child, scripts/p7_bitstream_flow.tcl), not project synthesis runs.
