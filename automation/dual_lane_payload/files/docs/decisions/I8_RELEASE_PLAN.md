# I-8 plan: NOC-5 (N-11, N-12, N-13) and the DUAL_LANE_10 release (written before the I-8 runs, 2026-11-03)

Source plan: docs/handoff/LANE1_I6_I7_I8_HANDOFF_20261103.md sec. 6; R4 NOC-5. Starts after the I-7 gate PASS.
Kalash's decisions 2026-11-02: N-13 insecure profile = mesh + 6 plain NIs; N-13 top = shift chain + MISR
(DECISION_REGISTER N13-PROFILES, N13-TOP). No RTL change in I-8 (release identity = the I-7 sources).

## 1. N-11: PQ-4 evidence on the matching identity

The release regression (N-12) re-runs i7_sec, its 8 controls, i7_full_chain and its control fresh on the release identity
in the same run as every other job. N-11 is satisfied by those records (same identity as the release); no separate job.

## 2. N-12: one-identity regression (selection `rel`)

One registry state, one release source list (S3 list + the I-6 / I-7 in-place files), every job fresh in one run:

- every P7-applicable job of I-5, S3, I-6 and I-7, positives AND negative controls (the controls show the checks are
  not vacuous on the release RTL);
- each job's list mapped to the release list (the S3 substitution where a Keccak core is present; the `*_i6` 0x2 bench
  copies in place of their originals);
- duplicates removed (same top, same mapped sources, same mutant): one record per distinct check;
- counts unchanged from the source jobs (frozen there); dependencies mapped inside `rel`.

Excluded: rev-5 / rev-6 jobs (not P7), the WP0 / N-8.1 production-mesh jobs (they apply to the protected rev-5 mesh build,
not the P7 subsystem), OOC jobs of pre-S3 engines (superseded by S3 / I-6 P&R).

## 3. N-13: isolated batch synthesis + implementation (selections `n13_secure`, `n13_insecure`, each run alone)

- Tops: `synth/n13/pq_p7_n13_top.sv` (secure: the unchanged `pq_noc_subsystem_p7`) and `synth/n13/pq_p7_n13_insecure_top.sv`
  (mesh + 6 plain P7 NIs, CONTROL_ALLOWED = 1). Inputs from a run-time serial shift chain (sdi, sen), outputs XOR-folded
  into a 64-bit MISR on sdo: nothing constant-folds, everything is observable. 5 pins (clk, rst, sdi, sen, sdo).
- Flow `scripts/n13_impl.tcl`: non-project, explicit sources, no incremental DCP, `-flatten_hierarchy none`, XDC read
  before synthesis, S1-PNR-DIR directives, real pins (`synth/n13/pq_p7_n13.xdc`: 20 ns, every I/O timed with 5 ns budgets).
- Gate `scripts/n13_gate.tcl`: WNS / WHS / WPWS >= 0, TNS / THS = 0, 0 route errors, 0 DRC errors, check_timing clean
  (no unexplained unconstrained path), secure LUT <= 47,550. Reports LUT, FF, LUTRAM, BRAM, DSP, IOB, power (vectorless).
- **A FAIL is a HARD STOP** (CLAUDE.md): first candidates are flow-only (pblocks, phys_opt replication, reset replication)
  and need Kalash; a router RTL change is never made here.
- The wrapper adds about 3.3k FF (shift chain) and an XOR fold; its cost is reported separately from the subsystem.

## 4. Release

`releases/DUAL_LANE_10_<id>/MANIFEST.md` + `manifest.json`: commit, release source list with SHA-256, run IDs and states
of `rel`, `rel_pnr`, `n13_secure`, `n13_insecure`, the gate reports I-5 .. I-8, decisions in force, and the status line
HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO. Text only.

## 5. Acceptance

All `rel` jobs PASS_FRESH (controls KILLED) on one identity; `rel_p7_pnr` and both N-13 jobs PASS; manifest committed.
Gate report reports/I8_GATE_<date>.md.

## 6. Notes during I-8

- Run `dual_lane_10_20261103_130900_78265e94`: n13_secure INVALID before any tool ran (build_timeout 14,400 s exceeds the
  harness supervisor limit of 7,200 s). Set to 7,200 s (the P7 P&R takes about 13 min). Kept as history.
- Run `dual_lane_10_20261103_130942_83368db2`: n13_secure recorded PASS_FRESH but its record is **defective and not used**:
  the n13_gate utilization parser (backslashes lost when the file was written) matched an empty string, so N13_LUT etc.
  were empty and the 47,550 LUT check compared an empty value. Timing in that run: WNS +0.260, WHS +0.016, clean; the
  routed utilization report shows LUT 38,054 / FF 35,857 / LUTRAM 2,014 / BRAM 0.5 / DSP 0. Fix: correct pattern, and
  every utilization metric must parse as a number or the gate FAILs; scripts/test_n13_util.tcl proves the parser on that
  report and the absent-row negative. n13_secure is re-run fresh; the release uses only the re-run.

