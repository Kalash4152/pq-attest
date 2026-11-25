---
title: "House Engineering Method (Kalash Bheda / PQ-Attest lineage)"
subtitle: "How we design, write RTL, test, record evidence and report. Read before executing any handoff. v1, 19 Nov 2026"
---

# 0. How to use this document

This is the **method**, not a project plan. It records how the PQ-Attest / TITAN work is actually done in `C:\vivado_verilog_proj\NOC_PQATTEST`. Every rule below comes from one of three places: the repo's own files (`CLAUDE.md`, `docs/DECISION_REGISTER.md`, `docs/CODEX_INSTRUCTIONS_R4_FINAL_2026-10-08.md`, `scripts/dual_lane_jobs.json`, `scripts/prepare_i9.py`, the RTL and benches under `rtl/dual_lane/`), Kalash's written engineering-lessons record, or decisions Kalash made in review.

A topic handoff (stages, interfaces, dates) tells you **what** to build. This document tells you **how**. If the two conflict, stop and ask; do not pick one silently.

Placeholders: `<TOPIC>` = short project tag, `<lane>` = the RTL variant folder, `I-<n>` = increment number.

# 1. The seven root causes (why the rules exist)

Every rule in this document prevents one of these. They come from real failures on MVDR anti-jamming and PQ-Attest.

| # | Root cause | Real event | Rule |
|---|---|---|---|
| RC-1 | Reasoning from a representation instead of the artifact | judged a project from a stale zip; reported a fix as applied when the commit had failed | read the working tree, the generated `.prj`, the bitstream hash. A zip, summary, cache or memory is not the artifact |
| RC-2 | Ambiguous evidence read as confirmation | a 49/0 testbench run was consistent with both patched and unpatched RTL | before using a PASS as proof of X, ask: would it look different if X were false? |
| RC-3 | Interface change treated as a local edit | added a port without grepping instantiations: a bench input floated, every KAT changed | grep every instantiation before touching a port list; write down byte order, reset polarity, ownership of each spec step |
| RC-4 | Expensive hypothesis before the cheap probe | three wrong diagnoses before reading the `.xpr` (30 of 34 files were disabled) | rank hypotheses by cost to test; run the cheapest discriminating probe first |
| RC-5 | State that fails silently | unconnected port read as `'z`; short `'h` literal zero-extended; stale compiled library | a hang or a wall of errors is usually environment state: check enabled files, stale libs, port connections, literal widths |
| RC-6 | Verification that cannot fail | benches with PASS banners and no negative control; a "restart" test that reused the same inputs | every bench gets a negative control and a mutant; a protocol test must change an input |
| RC-7 | Not matching the codebase's proven pattern | invented a module-header style no working module used | copy the pattern that already compiles in this repo |

# 2. Project lifecycle (the order is not optional)

```
Topic frozen ─▶ Contract doc(s) ─▶ Interface-freeze revision (signed) ─▶ Decision register rows
   ─▶ Increment I-n: register jobs + FREEZE expected counts ─▶ implement ─▶ run via the evidence system
   ─▶ Gate report + commit ─▶ PASS? continue to I-n+1 : HARD STOP for Kalash
   ─▶ ... ─▶ RTL freeze tag ─▶ results freeze tag ─▶ release evidence (hashes) ─▶ paper/report
```

1. **Contract first.** Behaviour is written in a contract doc under `docs/decisions/` before RTL. The repo's example is `docs/decisions/P7-INGRESS-REVOCATION-CONTRACT.md`. Its sections run: one section per mechanism (each with numbered rules), area and timing, a latency definition, a test matrix (registry IDs, frozen counts, expected reason, one effective negative control each), re-earn versus reuse, a **Claims** section listing the exact words allowed in STATUS, reports and the paper, and the execution order.
2. **Interface freeze before dependent RTL.** Any wire/format/field change gets a new numbered revision doc (`M-F1-rev<k>-<NAME>.md` pattern), written and approved **before** the RTL that uses it. Revisions are **additive**: "Additive to signed revision k; historical contracts and evidence are retained." Each revision opens with Date and Authority ("Kalash approved … in chat before dependent implementation"), then Frozen decisions (numbered), Boundaries retained, and Milestones and evidence.
3. **Decision register.** Every decision is one row in `docs/DECISION_REGISTER.md`: `| ID | Decision (precise, testable) | Authority + date + doc § |`. Use short IDs (Q1–Q6, I6-RETRY, S3-A1, D5-BOARD). A decision withdrawn after measurement stays in the register as **WITHDRAWN** with the reason and the numbers (example: S3-A5, withdrawn because it saved 1,600 FF but cost ≈790 LUT per engine). Never delete history.
4. **Increments.** Work is delivered in small increments `I-<n>`, each a reviewable logical group with its own jobs, gate and commit. I-n+1 starts only after I-n is PASS.
5. **Freeze and tag.** Feature-complete and results freezes are git tags. After a freeze, only bug fixes, each with a written bug note, and every result cites the freeze tag.

# 3. Repository discipline

- **Protected originals are never written.** The production RTL and its benches stay byte-identical (hash-checked). Secure or experimental changes go into **variants** in `rtl/<lane>/` with **explicit source lists**.
- **Never put a variant and its original in one source list.** A duplicate-name preflight fails any job whose source list defines a module or package name twice.
- **Generated files are never hand-edited.** They are produced by a generator script (pattern: `scripts/prepare_i9.py`). The pattern:
  - The docstring names the contract doc, every output file, what changed in each, and states that **every new parameter defaults to today's behaviour** (so all existing benches run unchanged).
  - Inputs are **pinned by SHA-256** in a `*_provenance.json`.
  - Edits are a list of `(anchor, replacement)` pairs applied by a helper that **aborts unless each anchor matches exactly once**.
  - Each output starts with `// GENERATED by scripts/<gen>.py from <src> (<tag>, <contract doc>). Do not edit.`
  - A companion `check_*.py` regenerates and byte-compares, and is itself a registered job.
  - Usage line in the docstring: `python scripts/prepare_x.py; python scripts/check_x.py`.
- **New behaviour is parameter-gated** with a default equal to the old behaviour, so every old bench is a regression for free ("re-run, counts unchanged").
- **Live tree wins.** If a handoff document and the live tree disagree, record the difference and stop that step.

# 4. RTL coding standard (as practised in `rtl/dual_lane/`)

**Match the file you are editing.** `rtl/dual_lane/` is written in a compact style (several statements per line); `sources_1/new/` is spaced. Do not reformat existing code.

| Topic | Rule |
|---|---|
| File head | `` `timescale 1ns/1ps ``; one-line purpose comment above the module |
| Module header | ANSI ports, `#(parameter ...)` list with a trailing comment naming the decision for each non-obvious parameter (e.g. `parameter int MAX_BUSY_RETRIES=3, // C-1/C-2 (I-6): ...`). Port types are package-qualified (`noc_pkg::coord_t`, `noc_pkg::msg_type_e`); `import noc_pkg::*;` goes **inside the module body**. Never `module m import pkg::*; #(...)` in the header (xvlog rejects it, RC-7) |
| Constants | come from the package; widths derived with `$clog2` and guarded by an elaboration check |
| Reset | dual-lane modules: synchronous, active-high `rst` (`if(rst) begin ... end else begin ... end`). **Reset polarity is not uniform** in the repo (e.g. `keccak_f1600` vs other crypto blocks): check each module and write it in the interface doc |
| Clocking | single clock `clk`, 20 ns (50 MHz). No clock, pin or CDC changes without Kalash |
| Sequential | one `always_ff @(posedge clk)` per state group; default assignments at the top of the else branch (`m_ev<=0;`); **all non-blocking**; never mix `=` and `<=` on one variable |
| Combinational | `always_comb` or `assign`; handshake muxes are **continuous assignments only** (repo rule "S1 valid/ready rule, no transients") |
| FSM | `typedef enum logic [k:0] {V_IDLE, V_REQ, ...} vs_t; vs_t vs;`: states prefixed by a block letter; every state has an exit; a `default` returns to idle |
| Handshakes | valid/ready; data and control **stable while valid && !ready**; a consumer never assumes a pulse it might miss |
| Decision IDs in comments | every non-obvious line cites the rule it implements: `// F4: authorization at the side-effect point`, `// Q2: ...`, `// I-9: ...`. A reader must be able to go from any line to its contract section |
| Fault/reason codes | one reason map in the contract (e.g. reasons 1..13); RTL emits one-cycle `*_event` pulses with `source/operation/reason` registered together; priority between sources is documented |
| Byte order | byte *i* at `[i*8 +: 8]` everywhere, fixed at the producer, never swapped per consumer |
| Literals | every sized literal on one line and full width; a short `'h` literal zero-extends silently |
| Control inputs | no default port values on control inputs (a default hides exactly the failure it would cause) |
| One owner per spec step | exactly one module performs each protocol/crypto step; write the owner in the contract |
| Bench-only hooks | behind a parameter (pattern `TB_INJECT`: `if(TB_INJECT) begin: TBI ... end else begin: NOTBI ...`), tied off when 0 |
| Checks in RTL | `$error`/assertions only inside `// synthesis translate_off` … `translate_on` |
| Synthesis | no latches, no `initial` in synthesizable RTL (memories initialised by the documented mechanism only), no vendor primitives outside board tops |

**xvlog rejections (do not rediscover):** `context`/`config` as identifiers (rename `context_in`, `config_data`) · `import pkg::*;` plus `#()` in a header · scoped `pkg::PARAM` in an ANSI port declaration · member select on a cast `t'(x).field` · part-select on a function call `f(x)[7:0]` · hierarchical enum labels from a bench · `initial` inside a package · string concatenation (use `$sformatf`) · zero-width vectors.

The editor's red underline is not a compiler. `xvlog` is the only opinion that counts.

# 5. Testbench standard

1. **Header comment states the frozen check count** and when it was frozen, e.g. `// Fourteen revision-9 merged lifecycle checks, frozen before registration.`
2. **Output convention** (parsed by the evidence system): per check `[PASS] <name>` / `[FAIL] <name>`, then `CHECKS : <n>`, `ERRORS : <n>`, `RESULT : PASS|FAIL`, and a config line `CONFIG: TOP=<tb> CHECKS=<n>`. A **watchdog** `initial begin #<limit>; $display("TB_TIMEOUT ..."); $display("RESULT : FAIL"); $finish; end`. A timeout is always FAIL.
3. **Golden data comes from the reference model**, never typed by hand. Vectors live in `.svh` include files generated by a Python script; the bench carries the exact generator command as a comment (`// python scripts/merged_provision.py --words sw/riscv/demo_fw.hex (2026-11-07)`).
4. **Teammate/reference software is authoritative and read-only.** It is pinned by SHA-256 and extracted read-only. Adapters are thin wrappers over its real API; they are not re-implementations.
5. **TSETTLE timing:** drive at `negedge`, wait `#1`, sample; inside a wait loop `@(posedge clk); #1;`. Reading right after the edge returns the pre-edge value and misses one-cycle pulses.
6. **Black-box:** observe through ports or exported status, not hierarchical enum labels. Hierarchical writes are allowed only for documented setup (e.g. loading a memory image).
7. **Negative control in every bench:** a job variant (`"negative": true`, `"variant_of": <job>`) where one targeted defect is injected and the bench must FAIL on the **targeted** check.
8. **Mutants:** a mutant counts as killed only if it **completes its frozen check count**, fails the **targeted causal check**, and shows **no unrelated FAIL**. Phase-isolated mutants run only their targeted phase, each with an unmutated control on the same phase-select that must pass.
9. **A protocol test must change an input.** A restart with the same inputs proves nothing.
10. **Adapters are self-tested first** against a hand-computed anchor; a round-trip test alone also passes for the identity function.

# 6. Evidence system (the only way a result counts)

- Results count **only** when produced through the registry runner: `python scripts/dual_lane.py run --select <increment-or-job>` (or the Tcl launcher). Accepted states: `PASS_FRESH`, or `PASS_REUSED` when the job identity (sources + hashes + defines + config) matches exactly. Everything else is not evidence.
- **Registry entry** (`scripts/dual_lane_jobs.json`, schema 2). Fields in actual use:
  - Identity: `id`, `kind` (simulation / python / ooc / implementation / reuse / gate), `top`, `sources` (explicit, ordered), `defines`, `include_dirs`, `config`.
  - Expectations: `checks` (frozen count) and `checks_basis` (one sentence: what the checks are and when they were frozen).
  - Variants: `negative`, `variant_of`, `mutant`.
  - Scheduling: `selection` (the increment), `dependencies`, `independent`, `build_timeout`, `sim_timeout`, `tb_time_limit`.
  - Implementation jobs: `max_lut` and similar ceilings.
  - Result: `evidence` (log directory).

  Example of a good `checks_basis`: "8 frozen matched workload checks: boot/admission/setup/completion/exact transfers/commits/all words/protocol and no fault".
- **Freeze expected counts before the first run.** Never change an expected count, weaken a check, or edit a reference vector to make something pass.
- Run `scripts/test_dual_lane.py` (the runner's own self-tests, including controlled-diagnostics tests) **before any registry change**. Batch registry changes: at most one regeneration per logical group, never mid-batch.
- Retries default to 0. A timeout is never a pass or a kill.
- **Judge/automation hardening needs negative tests.** Historical runs are re-evaluated only by explicit re-adjudication into new records, never by relabelling old ones.
- Evidence directories are committed **text-only** (log, json, txt, rpt, tsv, csv, md, tcl, bat, prj, sv). Binary products (`.dcp`, `.bit`, `.wdb`, …) stay on disk with their recorded SHA-256.
- For a new topic either add a new `selection` to this runner or replicate the runner with the same semantics. Do not invent a weaker one.

# 7. Claims vocabulary and status

- Keep these claims **separate**: **implemented** · **XSim-simulated** · **reference-checked** · **mutation-tested**. Formal proof and hardware validation are reported as **NO** unless a named tool run or a recorded board run exists.
- Status flags in `docs/STATUS.md` and every gate report: `HARDWARE_VALIDATED=NO`, `SOC_INTEGRATION_COMPLETE=NO`, `FORMAL_PROOF=NO` until Kalash flips them with evidence.
- Paper-level evidence classes (when formal exists): U unbounded proof · B(k) bounded · S simulation · F failed · X inconclusive.
- Every deliverable file that was not compiled says so: **"Not compiled — no simulator in this session."**
- The Claims section of the contract fixes the exact words used in STATUS, reports and the paper. Do not paraphrase into stronger words.

# 8. Numbers and provenance

Every number carries: tool + version, exact part, clock, post-synth vs post-route, date, commit. Example: `39,962 LUT / 29,187 FF / 20 BRAM36, WNS +0.182 ns, WHS +0.007 ns | Vivado 2024.1 | xc7a100tcsg324-1 | 50 MHz | post-route | 14 Nov 2026`.

- FPGA utilisation is never ASIC area.
- Re-measure before re-using a number from an older report; label un-rerun figures ("Report B, not re-run").
- Bitstreams are identified by SHA-256. Whole-file hashes can differ only in timestamp header bytes; prove it with a payload comparison instead of assuming it.
- A measured budget is a hard limit (the repo's: full-subsystem LUT > 47,550 is a HARD STOP).

# 9. Gates, reports and stopping rules

- **Gate report at every increment boundary**, committed. It starts with: commit hash · accepted / fresh / reused counts · measured LUT / WNS · open blockers · next dependency · `HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO`. Then the evidence table, deviations, and what was not done.
- **PASS → continue automatically** to the next increment.
- **HARD STOP and wait for Kalash on:** any FAIL that needs a design or contract change · a measured budget exceeded · any new security-scope question · any change to a signed bound, wire format, device, clock or budget · a timing FAIL.
- When blocked: write `BLOCKED.md` (what, exact failure lines, what was tried, what is needed, since when). Escalate after 2 working days.
- Keep a **cut list**: anything that slips is recorded, never silently dropped.

# 10. Debug procedure

1. Define expected vs observed precisely.
2. Reproduce with the smallest bench and a fixed seed.
3. Find the **first** cycle of divergence (event CSV + waveform).
4. List hypotheses; order by **cost to test**; run the cheapest discriminating probe first. In Vivado this is usually: read the `.xpr`, read the generated `<top>_vlog.prj` (what was actually compiled), check `is_enabled` on every file, force a clean simulation (`close_sim; reset_simulation -simset sim_1 -mode behavioral; launch_simulation`).
5. Fix the root cause in the source or generator, never in a generated file or a check.
6. Re-run the failing job, then the whole increment.
7. Record the **root cause** (not the symptom) in the gate report and, if it is a new pattern, in the lessons record.

Known environment traps: orphaned `xsimk.exe`/`xsim.exe` wedge XSim (`rc=139`); never kill a Vivado/XSim job you did not start; at most 2 concurrent Vivado/XSim processes (16 GB RAM); synthesis/implementation runs alone.

# 11. Git

- One branch per person (e.g. `arnav/<topic>`), cut from the current integration branch. Never commit to `main` directly; never force-push; never `git reset --hard`, `git clean`, or restore from zip snapshots.
- One commit per logical group, message `<TOPIC> I-<n>: <what>`; the author line is given by the repo owner for that repo.
- Generated files are committed together with the generator change that produced them, and the check job passes in the same commit.
- Do not commit tool project files that are policy-excluded (e.g. the main `.xpr`) or binary build products.

# 12. Communication

- **Status first, conclusion first.** One line of what was read live before claims ("pre-output check").
- Address the owner by name; be brief; no narration.
- Separate facts, assumptions, inferences and recommendations. Label anything not run as **UNVERIFIED**.
- "Written is not working; ran is not passed." Paste the exact result line and log path for every claimed result.
- Disagree with a handoff in writing when the live tree contradicts it. Never patch around it silently.
- When in doubt about scope, do less and report more. An unrequested change to working RTL is worse than a gap left open.

# 13. Checklists

**Before writing code:** read the actual files in the live tree · grep every instantiation of anything whose ports you touch · find and copy the existing pattern for this kind of module · confirm the contract/interface revision that authorises the change exists and is approved.

**Before registering a job:** source list explicit, no duplicate names · `checks` and `checks_basis` frozen · negative variant defined · `test_dual_lane.py` passes.

**Before claiming anything:** would the evidence look different if the claim were false? · did the write land (size/mtime read back)? · is the number's provenance complete? · is the claim word from the allowed vocabulary?

**At each increment boundary:** gate report written · evidence committed text-only · STATUS flags unchanged unless evidenced · next dependency named.

# Appendix A. Templates

**A1. Interface revision doc** (`docs/decisions/<IFACE>-rev<k>-<NAME>.md`)
```
# <IFACE> revision <k>: <name>
Date: <yyyy-mm-dd>. Authority: <who approved, where, before dependent implementation>. Additive to signed revision <k-1>.
## Frozen decisions
1. <field/bit/semantic, exact widths and encodings>
## Boundaries retained
<part, clock, pins, protected originals, signed bounds that do not change>
## Milestones and evidence
<increments, jobs, what proves each decision>
```

**A2. Decision register row**
```
| <ID> | <precise, testable decision> | <Kalash yyyy-mm-dd>, `docs/decisions/<doc>.md` sec. <n> |
```

**A3. Registry job**
```json
{ "id": "<topic>_<block>_<case>", "kind": "simulation", "top": "tb_<block>",
  "sources": ["<pkg first>", "...", "<tb last>"], "defines": [], "include_dirs": ["vectors"],
  "checks": <n>, "checks_basis": "<n> frozen checks: <list>, frozen <date> before first run",
  "selection": "I-<n>", "dependencies": [], "independent": true,
  "build_timeout": 1200, "sim_timeout": 600, "tb_time_limit": "<t>" }
```
Negative variant: same plus `"negative": true, "variant_of": "<id>"` and the define that injects the defect.

**A4. Bench skeleton**
```systemverilog
`timescale 1ns/1ps
// <N> <topic> checks for <block>, frozen <date> before registration.
module tb_<block>;
  import <pkg>::*;
  logic clk = 0, rst = 1; always #10 clk = ~clk;
  int checks = 0, errors = 0;
  task automatic check(input string name, input bit ok);
    checks++; if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  // DUT, stimulus at negedge, sample after #1 ...
  initial begin
    $display("CONFIG: TOP=tb_<block> CHECKS=<N>");
    // ...
    $display("CHECKS : %0d", checks); $display("ERRORS : %0d", errors);
    $display("RESULT : %s", (errors == 0 && checks == <N>) ? "PASS" : "FAIL"); $finish;
  end
  initial begin #<limit>; $display("TB_TIMEOUT <block>"); $display("RESULT : FAIL"); $finish; end
endmodule
```

**A5. Gate report head**
```
# <TOPIC> I-<n> gate: PASS|FAIL
Commit <hash> · accepted <a> (fresh <f> / reused <r>) · LUT <x> / WNS <y> (<provenance>) · blockers: <list|none> · next: <dependency>
HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO
## Evidence  | job | state | checks | log |
## Deviations from the plan
## Not done / cut list
```

**A6. Generator skeleton**
```python
"""I-<n> (<contract doc>, signed <date>). Generates, by exact-anchor edits that must match once, from pinned sources
(hashes in rtl/<lane>/<x>_provenance.json): <out file> <what changed>. Every new parameter defaults to today's behaviour.
The original files are not edited. Usage: python scripts/prepare_<x>.py; python scripts/check_<x>.py (job <x>_variant)."""
def edit(text, pairs):
    for a, b in pairs:
        n = text.count(a)
        if n != 1: raise SystemExit(f"anchor matched {n} times: {a[:60]!r}")
        text = text.replace(a, b)
    return text
```
