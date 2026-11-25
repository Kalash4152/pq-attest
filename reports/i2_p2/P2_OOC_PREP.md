# I-2 prep track P2: D4 crypto OOC (PQ-3) preparation

Date 2026-10-19. Worktree branch `worktree-agent-a4b58c434cb24bd2a`, base HEAD `0b5c0d6`.

**This is preparation only. It is not evidence.** No synthesis ran, and no Vivado or XSim process was started.
Every number below comes from reading files, from two static self-tests that need no Vivado, or from the
existing I-1 `ni_ooc` reports. Latency is not measured. The status flags stay as they are:
`HARDWARE_VALIDATED=NO`, formal NO.

## 0. Blocker found: `scripts/d4_crypto_ooc.tcl` cannot be edited in place

`automation/dual_lane_payload/update_manifest.json` pins `scripts/d4_crypto_ooc.tcl` with
`before=null, after=9dabc894…7470`. On every `run` (and on `preflight`), `dual_lane.py run()` calls
`install()`, and `install()` raises `InvalidEvidence('dirty-file conflict …')` when a pinned file's hash is
neither `before` nor `after`. Editing the file in place would make **every** scheduler run refuse, I-2 included.

So the prepared child script is **staged** at `reports/i2_p2/d4_crypto_ooc.tcl`
(sha256 `6c7e60ae…9025`). `scripts/d4_crypto_ooc.tcl` is unchanged. The integrator picks one way to install it:

| Option | Action | Pinned files touched |
|---|---|---|
| **B (recommended)** | Copy the staged file to a new path, `scripts/d4_crypto_ooc_child.tcl`, and set `child_script` to that path. The installed 2-line launcher stays as it is. | none |
| A | Overwrite `scripts/d4_crypto_ooc.tcl` and `automation/dual_lane_payload/files/scripts/d4_crypto_ooc.tcl` with the staged file, and set the manifest row's `after` to the new sha256 (`before` stays `null`). | manifest, payload |

The staged file works under both options. Its launcher mode does what the current file does (§3).

Separately, at HEAD `0b5c0d6` in this worktree two rows **already** do not match the manifest. A dry
`install()` raises on them before it ever reaches the d4 row. P2 did not cause either one.

* `docs/STATUS.md`: manifest after `d4093463…`, working tree `070dee91…` (STATUS rev 20 commit).
* `rtl/dual_lane/variant_provenance.json`: manifest after `eb351928…`, working tree `3893c650…`.

The integrator must settle these before any `dual_lane.py run`. That holds for I-2 too, not just I-4.
See open question 1.

## 1. Per-top source-list check

Tool: `reports/i2_p2/p2_source_check.py`, output in `p2_source_check.json` and `.log`. Verdict: `P2_SOURCE_CHECK=PASS`.

For each job the tool takes a deep **copy** of the registry entry and calls
`dual_lane_preflight.source_names()` on it. That call checks that every file exists, that every active
`module`/`package` name is declared exactly once, and that the top is declared. The tool then walks the
instantiations from the top and checks that every instantiated type is declared in the list. Last, it checks
that every package reached through `pkg::` (transitively) is in the list. `dual_lane_jobs.json` is only read.

| Job | Top | Files | Modules / packages declared | Reached from top | Unresolved inst. | Missing pkg | Duplicates | Never reached (harmless extras) |
|---|---|---|---|---|---|---|---|---|
| ooc_pq_kdf | pq_kdf | 23 | 17 / 6 | 11 mod, 3 pkg | 0 | 0 | 0 (preflight PASS) | pq_measurement, pq_attestation_tag, pq_attestation_controller, sha3_256/pad/absorb; sha3_pkg, pq_measurement_pkg, pq_attest_pkg |
| ooc_pq_measurement | pq_measurement | 23 | 17 / 6 | 11 mod, 3 pkg | 0 | 0 | 0 | pq_kdf, pq_attestation_tag, pq_attestation_controller, kmac128/absorb/encode; kmac_pkg, pq_kdf_pkg, pq_attest_pkg |
| ooc_pq_attestation_tag | pq_attestation_tag | 23 | 17 / 6 | 11 mod, 3 pkg | 0 | 0 | 0 | pq_kdf, pq_measurement, pq_attestation_controller, sha3_256/pad/absorb; sha3_pkg, pq_kdf_pkg, pq_measurement_pkg |
| ooc_pq_attestation_controller | pq_attestation_controller | 23 | 17 / 6 | 17 mod, 6 pkg | 0 | 0 | 0 | none |
| endpoint_ooc (waits for PQ-2) | pq_attest_endpoint | 25 | 18 / 7 | 18 mod, 7 pkg | 0 | 0 | 0 | none |
| ni_ooc (I-1 reference) | noc_network_interface | 2 | 1 / 1 | 1 mod, 1 pkg | 0 | 0 | 0 | none |

The current lists are **complete and duplicate-free**. The three engine jobs each read 9 files their top never
reaches. `synth_design -top` elaborates only what the top reaches, so this is harmless. It does make each
engine's reuse identity depend on unrelated protected files: a change to `pq_attest_protocol.sv` would
invalidate the `pq_kdf` OOC result. §5 proposes trimmed 14-file lists, which also pass the same check
(`proposed_jobs` in the JSON).

Neither the file-scope `import` nor `` `include `` occurs in these files: every import is in a module header,
so trimming cannot drop a file-scope dependency.

### Expected child-engine hierarchy (gated post-synthesis)

Instance names were read from the RTL, and `selftest_d4_parsers.tcl` re-checked each one with a regexp.

| Top | Gated instances (path : module) |
|---|---|
| pq_kdf, pq_attestation_tag | `u_kmac`:kmac128, `u_kmac/u_kmac_absorb`, `u_kmac/u_kmac_encode`, `u_kmac/u_keccak`:keccak_f1600, `u_kmac/u_keccak/u_keccak_round` (5) |
| pq_measurement | `u_sha3`:sha3_256, `u_sha3/u_sha3_pad`, `u_sha3/u_sha3_absorb`, `u_sha3/u_keccak_f1600`, `u_sha3/u_keccak_f1600/u_keccak_round` (5) |
| pq_attestation_controller | `u_pq_kdf`, `u_pq_measurement`, `u_pq_attestation_tag`, plus each one's 5 rows above (18) |
| pq_attest_endpoint (provisional) | `controller`:pq_attestation_controller plus the 18 rows above under `controller/` (19) |

The round sub-steps `u_theta u_rho u_pi u_chi u_iota` are **reported but not gated**. `u_rho` and `u_pi` are
pure wiring and may legally hold 0 cells.

## 2. Constraint text (`scripts/d4_crypto_ooc.xdc`, new)

```tcl
create_clock -name clk -period 20.000 [get_ports clk]
set_input_delay  -clock clk 5.000 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock clk 5.000 [get_ports -filter {DIRECTION == OUT}]
```

* These are the same budgets `ni_ooc` used in I-1 (`metrics.txt`: `CLOCK_NS=20 INPUT_BUDGET_NS=5
  OUTPUT_BUDGET_NS=5`), so NI and crypto OOC numbers can be compared. I found no documented reason to deviate.
  Every crypto top latches its request on `start` and registers its result, so the 5 ns external budget leaves
  15 ns for the first and last internal stage. The budgets are **assumed**, not derived; integrated timing is N-14.
* One value is used for both min and max, as in `ni_ooc`. Vivado flags this as methodology `XDCH-2`. `ni_ooc`
  showed 494 such warnings, so expect roughly one per I/O bit here (more than 2000 for the controller).
* Every port is timed, `rst_n` included. There is no false path, no multicycle path and no clock change.
* One difference from `ni_ooc`: the XDC is read **before** `synth_design`, so synthesis is timing-driven. `ni_ooc`
  applied the same three constraints only after synthesis. The timed constraints are identical. Only the
  optimisation target differs.

## 3. Script changes (staged `reports/i2_p2/d4_crypto_ooc.tcl` vs installed 2-line launcher)

1. **Three modes.**
   * *Launcher*, when no job-file argument is given: the same two statements as today, `source
     dual_lane_common.tcl; dual_lane::run ooc`. It never synthesises in the GUI.
   * *Child*, when `argv` is exactly one `*job.tcl`: started only by `dual_lane.py execute()` through
     `child_script`.
   * *Library*, when `::d4ooc_library_only` is set: defines procedures only, for the static self-test.
2. **Child preconditions (fail closed, no tool work).** The child requires:
   * Vivado 2024.1, with no open project;
   * `KIND eq ooc` and `PART eq xc7a100tcsg324-1`;
   * a top with a frozen child expectation (an unknown top is an error);
   * the `XDC` variable present and pointing at a file.
3. **Isolated batch flow.** The flow runs `create_project -in_memory`, then `read_verilog -sv $SOURCES` (the
   scheduler's snapshot copies) and `read_xdc $XDC`. It then runs `synth_design -top $TOP -mode
   out_of_context -flatten_hierarchy none {*}$GENERICS`. These are the same options as `ni_ooc`.
4. **Clock proof.** After synthesis there must be exactly one clock `clk`, with `PERIOD == 20.000`.
5. **Child engines kept and proven.** Hierarchy is kept by `-flatten_hierarchy none`, which is global and
   matches `ni_ooc`. Each gated instance must:
   * exist as exactly one hierarchical (non-primitive) cell;
   * have `REF_NAME` or `ORIG_REF_NAME` starting with the expected module name;
   * have more than 0 leaf cells.

   If any instance fails, the child writes `hier_check.rpt` and `metrics.txt` and then raises an error, so the
   job is INVALID.

   **No per-instance `KEEP_HIERARCHY`/`DONT_TOUCH`**, for three reasons:
   * The RTL is protected (no attributes can be added).
   * An XDC `set_property` on an elaborated cell is unverified without Vivado. An empty match emits `ERROR:`,
     and the scheduler rejects any `^ERROR:` line in the log.
   * `DONT_TOUCH` would keep the unconnected Keccak observation ports (`round_valid`, `round_index`) and block
     constant propagation, which inflates utilization.

   The post-synthesis existence gate is the proof the instructions ask for.
6. **Reports.** The child writes these reports to `OUT`:
   * `utilization.rpt`, `util_hier.rpt` (`-hierarchical_depth 8`, which reaches `…/u_keccak_round/u_theta` under the endpoint);
   * `timing_summary.rpt` (`-check_timing_verbose -report_unconstrained -max_paths 20`);
   * `worst_paths.rpt`, `worst_hold_paths.rpt`, `in_to_out.rpt`;
   * `methodology.rpt`, `drc.rpt`, `hier_check.rpt`;
   * `synth.dcp` (binary; it stays on disk).
7. **`metrics.txt`.** The first eight lines are byte-for-byte the same format as `ni_ooc`: `SCOPE=OOC`,
   `CLOCK_NS=20`, `INPUT_BUDGET_NS=5`, `OUTPUT_BUDGET_NS=5`, `LATCHES`, `WNS`, `WHS`, `CELLS`. The scheduler
   parses `LATCHES`, `WNS`, `WHS` and `CELLS`. Extra `KEY=VALUE` lines are recorded unchanged in `observed`.
   Each value is one line, and `kv` refuses newlines. The `dict(l.split('=',1))` parse keeps the first `=`.
   * provenance: `TOP`, `PART`, `VIVADO`, `SYNTH_OPTIONS`, `CONSTRAINTS`;
   * utilization from `report_utilization`: `LUT`, `LUT_LOGIC`, `LUTRAM`, `SRL`, `FF`, `BRAM`, `DSP`
     (`NA` if a row is missing);
   * primitive-count cross-checks: `CELL_LUT`, `CELL_FF`, `CELL_LUTRAM`, `CELL_SRL`, `CELL_RAMB36`,
     `CELL_RAMB18`, `CELL_DSP`;
   * timing: `TNS`, `TNS_FAILING_ENDPOINTS`, `TIMED_ENDPOINTS`, `THS`, `THS_FAILING_ENDPOINTS`, `WPWS`,
     `DTS_WNS`, `DTS_WHS`, `WNS_FROM`, `WNS_TO`, `WNS_LOGIC_LEVELS`, `WNS_DATAPATH_NS`;
   * `CHECK_TIMING` (all categories) and `UNCONSTRAINED_ENDPOINTS`. This is the sum of `no_clock`,
     `unconstrained_internal_endpoints`, `no_input_delay`, `no_output_delay` and `partial_*`. If the sum is not
     0, the child raises an error (INVALID), because a WNS from a partly constrained netlist proves nothing;
   * `METHODOLOGY_VIOLATIONS` and `METHODOLOGY_RULES` (`ID/Severity:count`), plus `DRC_ERRORS`;
   * child engines: `CHILD_ENGINES`, one `CHILD:<path>` line each (state, module, ref, leaf/lut/ff/dsp counts),
     and `HIER_CHECK`;
   * latency: `MEASURED_LATENCY_CYCLES=PENDING_SIMULATION` and `LATENCY_SOURCE=<text>` (§4).
8. **Timing failure is a FAIL, not an error.** If WNS or WHS is below 0, or there is a latch, the child still
   exits 0. The scheduler then records `GateFailure` (FAIL), and PQ-3 needs the trade-off note.

The parsers reuse the `n25_gate.tcl` patterns (DTS row, `N. checking name (n)`, utilization row), which I-1
proved on 2024.1 output.

**Tcl sanity check (no Vivado).** `tclsh 8.6.15` (ucrt64) ran `selftest_d4_parsers.tcl`; the log is
`selftest_d4_parsers.log`, with `SELFTEST_FAILS=0`. It checked:
* that `info complete` holds for the script and the XDC;
* every parser against the real I-1 `ni_ooc` reports: LUT 412, LUT_LOGIC 388, LUTRAM 24, SRL 0, FF 266, BRAM 0,
  DSP 0, WNS 4.464 and WHS 0.263 (both equal to its `metrics.txt`), 12 check_timing categories with 0 unconstrained, and
  methodology `494 XDCH-2/Warning:494`;
* synthetic cases: an unconstrained sum of 5, and a missing section raising an error;
* that the expected child lists are unique, that an unknown top is rejected, and that every expected instance
  appears in the RTL.

This shows the parsers read the 2024.1 report format. It is **not** a check of the Vivado commands. Those run
for the first time in I-4.

## 4. Measured-latency placeholder (simulation, never synthesis)

| Top | `LATENCY_SOURCE` |
|---|---|
| pq_attestation_controller | Job `s8_golden` (I-2) `simulate.log` lines `LATENCY Gnn cycles=N`. They come from `tb_stg_8_golden` `await_done`, which starts counting at the posedge after `start` falls, so start-to-done is N+1 edges. |
| pq_kdf, pq_measurement, pq_attestation_tag | No registered dual-lane job yet. `pq_kdf_tb`, `pq_measurement_tb` and `pqattest_tb` count cycles but print the count only on timeout, so a sim job that prints start-to-done per engine is needed. |
| pq_attest_endpoint | The PQ-2 `pq_endpoint` job. |

The I-4 integrator copies the measured value into the PQ-3 report next to the OOC metrics. `metrics.txt` stays
`PENDING_SIMULATION`.

## 5. Proposed job-definition diffs (NOT applied)

These follow option B from §0. For option A, use `"child_script": "scripts/d4_crypto_ooc.tcl"`.

`oracle_files` makes the XDC and the child part of both the reuse identity (`run()` `inputs`) and the
`execute()` before/after snapshot. Today the XDC would be in neither, because `constraints` is copied but not
hashed. Trimming `sources` is optional; the current 23-file lists also pass.

```json
{
  "ooc_pq_kdf": {
    "child_script": "scripts/d4_crypto_ooc_child.tcl",
    "constraints": "scripts/d4_crypto_ooc.xdc",
    "oracle_files": ["scripts/d4_crypto_ooc.xdc", "scripts/d4_crypto_ooc_child.tcl"],
    "sources": [
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_pkg.sv",
      "NOC_PQATTEST.srcs/sources_1/new/kmac_pkg.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_kdf_pkg.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_theta.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_rho.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_pi.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_chi.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_iota.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_round.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_f1600.sv",
      "NOC_PQATTEST.srcs/sources_1/new/kmac_encode.sv",
      "NOC_PQATTEST.srcs/sources_1/new/kmac_absorb.sv",
      "NOC_PQATTEST.srcs/sources_1/new/kmac_128.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_kdf.sv"
    ]
  },
  "ooc_pq_measurement": {
    "child_script": "scripts/d4_crypto_ooc_child.tcl",
    "constraints": "scripts/d4_crypto_ooc.xdc",
    "oracle_files": ["scripts/d4_crypto_ooc.xdc", "scripts/d4_crypto_ooc_child.tcl"],
    "sources": [
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_pkg.sv",
      "NOC_PQATTEST.srcs/sources_1/new/SHA3_PKG.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_measurement_pkg.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_theta.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_rho.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_pi.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_chi.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_iota.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_round.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_f1600.sv",
      "NOC_PQATTEST.srcs/sources_1/new/SHA3_PAD.sv",
      "NOC_PQATTEST.srcs/sources_1/new/SHA3_ABSORB.sv",
      "NOC_PQATTEST.srcs/sources_1/new/SHA3_256.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_measurement.sv"
    ]
  },
  "ooc_pq_attestation_tag": {
    "child_script": "scripts/d4_crypto_ooc_child.tcl",
    "constraints": "scripts/d4_crypto_ooc.xdc",
    "oracle_files": ["scripts/d4_crypto_ooc.xdc", "scripts/d4_crypto_ooc_child.tcl"],
    "sources": [
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_pkg.sv",
      "NOC_PQATTEST.srcs/sources_1/new/kmac_pkg.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pqattest_stg7_pkg.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_theta.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_rho.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_pi.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_chi.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_iota.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_round.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pq_keccak_f1600.sv",
      "NOC_PQATTEST.srcs/sources_1/new/kmac_encode.sv",
      "NOC_PQATTEST.srcs/sources_1/new/kmac_absorb.sv",
      "NOC_PQATTEST.srcs/sources_1/new/kmac_128.sv",
      "NOC_PQATTEST.srcs/sources_1/new/pqattest_stg7.sv"
    ]
  },
  "ooc_pq_attestation_controller": {
    "child_script": "scripts/d4_crypto_ooc_child.tcl",
    "constraints": "scripts/d4_crypto_ooc.xdc",
    "oracle_files": ["scripts/d4_crypto_ooc.xdc", "scripts/d4_crypto_ooc_child.tcl"],
    "build_timeout": 7200
  }
}
```

The controller keeps its current 23-file list, which is already minimal: every file is reached. Its
`build_timeout` rises to 7200 to match `mesh_gate`, because it holds three Keccak cores. The other keys are
unchanged: `kind ooc`, `top`, `dependencies []`, `independent true`, `selection ooc`, `build_timeout 3600`.
There are no `generics`, since none of the four tops has parameters.

Applying the diff also needs these steps:
* run `scripts/test_dual_lane.py` first (61 tests pass at this HEAD);
* add the four ids (plus `endpoint_ooc` after PQ-2) to `increments["I-4"]`, and set `active_increment` in the
  registry and in `dual_lane_config.json`;
* expect the PQ-3 *stage* state to read BLOCKED until PQ-2 passes, because `stages` lists PQ-2 as a dependency.

`endpoint_ooc` gets the same three keys once PQ-2 freezes `pq_attest_endpoint.sv`.

## 6. Risks

| Risk | Detail | Mitigation / what to watch in I-4 |
|---|---|---|
| Installation (blocker) | Pinned launcher path; manifest is already stale for STATUS.md and variant_provenance.json (§0). | Integrator settles these before any run. |
| Controller size vs 20 ns | `pq_attestation_controller` instantiates **three independent Keccak-f[1600] cores** (KDF KMAC, measurement SHA3, tag KMAC). That is at least 3×1600 state FFs, plus latched request and response registers and about 1.7k input / 0.8k output ports. Area fits an xc7a100t, but runtime and memory are the largest of the five tops. | Per-core rounds are 1 round per clock (`pq_keccak_f1600.sv`: "One round per clock, 24 rounds"), so clock period does not grow with core count. Size alone is not a timing risk; the paths below are. `build_timeout` 7200. |
| Critical path: variable-offset packing | `pq_measurement`: `config_len_q` (reg) → variable-offset IMEM placement `msg_block[(TILE_ID_BYTES+config_len_q+i)*8 +: 8]` (about a 65:1 byte mux across 1088 bits, high fanout on `config_len_q`) → `sha3_pad` → `sha3_absorb` XOR → `state_reg`, all in one cycle and across 3 kept hierarchy boundaries. `kmac_encode` builds `block_data` from `key_len_reg`/`custom_len_reg` the same way, feeding `kmac_absorb`. | `WNS_FROM`/`WNS_TO`/`WNS_LOGIC_LEVELS` pinpoint it. If WNS < 0, the result is FAIL plus a trade-off note: register `msg_block` (one more cycle of latency), or move the shift to request time. A clock change is not allowed. |
| Keccak round depth | theta (11-input column parity) → rho/pi wiring → chi → iota, plus the state input mux. These are a few LUT levels. | Not expected to limit timing at 20 ns. This is an estimate, not a result. |
| DSP inference | Static grep found **no signal×signal multiply** in any crypto file. The only `*` are constant ×8 index/length scalings (`custom_len_reg * 8`, `key_len_reg * 8`, `(…)*8 +:`), which become shifts. Keccak is XOR/AND/NOT only. | Expect `DSP=0` and `CELL_DSP=0`. A nonzero value is a finding: the per-child `dsp:` counts in `CHILD:` lines locate it. Do not suppress it with `use_dsp`; report it. |
| BRAM/LUTRAM inference | No memory arrays; the iota round constants are a 24-entry ROM → LUTs. | Expect `BRAM=0` and `LUTRAM≈0`. A nonzero value is a finding, not an error. |
| Hierarchy trimming / renaming | `-flatten_hierarchy none` keeps hierarchy, but a whole instance could still be removed if unloaded. Parameterized modules are renamed (`kmac128__parameterized0`, etc.). | Gate on existence, prefix match on `REF_NAME`/`ORIG_REF_NAME`, and leaf > 0. Wiring-only round steps are not gated. |
| Boundary optimisation lost | With hierarchy kept, constants (for example `key_len_sel` fixed in the controller) do not propagate across boundaries, so the numbers are pessimistic compared with a flattened build. | This is intended for per-engine attribution. Label the results "hierarchy kept". |
| XDCH-2 noise | Same min/max IO delay; more than 2000 warnings on the controller. | Expected; recorded in `METHODOLOGY_RULES`. |
| Unverified Vivado commands | `get_property ORIG_REF_NAME` (inside `catch`), `report_methodology -return_string`, `report_utilization -hierarchical_depth 8`, and `get_timing_paths -hold` were not executed in P2. | First I-4 run. Any `ERROR:` makes the job INVALID, so a fault cannot pass silently. |

## 7. Files

* `scripts/d4_crypto_ooc.xdc`: new; the constraints.
* `reports/i2_p2/d4_crypto_ooc.tcl`: the staged child, launcher and library script.
* `reports/i2_p2/selftest_d4_parsers.tcl` and `.log`: the no-Vivado parser and structure self-test.
* `reports/i2_p2/p2_source_check.py`, `.json` and `.log`: the static source-list check.
* `reports/i2_p2/P2_OOC_PREP.md`: this report.

Not touched: `scripts/d4_crypto_ooc.tcl`, `scripts/dual_lane_jobs.json`, `docs/STATUS.md`, all `.sv`, the manifest.

## 8. Open questions

1. **Manifest drift.** STATUS.md and variant_provenance.json differ from `update_manifest.json` at `0b5c0d6`.
   Who refreshes the manifest, and in which increment? Until then, `dual_lane.py run` refuses at `install()`.
2. **Install option** A or B for the child (§0). B touches no pinned file.
3. **Engine latency source.** `pq_kdf`, `pq_measurement` and `pq_attestation_tag` have no registered sim job
   that prints start-to-done. Options: add one in I-4 (a new job, frozen first), or report only the controller
   latency from `s8_golden`.
4. **Unconstrained endpoints.** Should they stay a child-side INVALID? An alternative is a scheduler-side
   FAIL key, but that needs a `dual_lane.py` change, which is out of P2 scope.
5. **Min input delay.** Keep `ni_ooc`'s single value (comparable numbers, XDCH-2 noise), or add `-min 0` for a
   stricter hold check? Changing it would also require re-running `ni_ooc` to keep the two comparable.
