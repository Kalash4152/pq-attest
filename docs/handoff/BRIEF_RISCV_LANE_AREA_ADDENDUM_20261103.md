# RISC-V lane: area and timing addendum (steps 11-20)

- **From:** Lane 1 (Kalash), 2026-11-03.
- **For:** the RISC-V CPU tile team, and the AI assistant you work with.
- **Adds to:** `BRIEF_RISCV_LANE_NEXT10_20261031.pdf` (steps 1-10). Everything in that brief still applies: the ground
  rules, the ten TMEM signals, the address map, and steps 1-10. This document adds **new work only**.

## 0. Why this addendum exists

All three lanes share one FPGA (xc7a100tcsg324-1, 63,400 LUTs). The system has a hard area budget of **47,550 LUTs**
(75 % of the device; above that, routing gets crowded and timing fails).

| Item | LUT | Status |
|---|---|---|
| Lane 1 NoC + attestation subsystem (P7, after this week's area work) | 37,398 | **measured, routed** |
| Lane 1 next increment (I-6: retry, fault status, address map) | about 1,000-3,000 | estimate |
| Lane 1 bridge (TMEM -> network) + memory front end | about 1,500 | estimate |
| Margin kept free for routing and timing | about 2,500 | rule of thumb |
| **Left for the RISC-V lane: both CPU tiles together** | **about 3,000-3,500** | **budget for you** |

**Lane 1 has just cut its own design by 6,537 LUTs (-14.9 %).** Your tile is next. Your last measured `tile_top` was **1,674
LUT, 1,102 FF, 0 DSP**, with 4 BRAM inside the tile. Two of those (tile 0 and tile 3) are about 3,350 LUT, which is right at
the edge of the budget.

**Your targets:**

| Per CPU tile (`tile_top`, including the adapter and peripherals) | Target | Hard limit |
|---|---|---|
| LUT | **<= 1,300** | 1,600 |
| FF | <= 1,100 | 1,500 |
| LUTRAM | report it | - |
| BRAM | 0 inside the tile if memories live outside (step 7 of the first brief); otherwise report the count | - |
| DSP | allowed; there are 240 unused on the device. Moving the multiplier into DSPs **saves LUTs** | 4 |
| Timing, out of context at 20 ns | **WNS >= +1.0 ns** | WNS >= +0.5 ns |

**Why the timing margin is so high:**
- Lane 1's own design has only +0.126 ns left.
- Once the CPUs are placed next to it, every path gets longer.
- A CPU tile that barely meets 20 ns alone will fail inside the full chip.

**Do not trade correctness for area.** Steps 1-6 of the first brief (bug fixes and tests) come first. Area changes are
applied only after step 2 (TMEM conformance) passes, and every area change must re-pass the tests (step 18).

## 1. How to measure: use exactly this recipe, so our numbers compare

Use Vivado 2024.1, part `xc7a100tcsg324-1`, top `tile_top`, out of context, hierarchy kept. This is the same flow Lane 1
uses.

`tile_ooc.xdc`:
```tcl
create_clock -name clk -period 20.000 [get_ports clk]
set_input_delay  -clock clk 5.000 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock clk 5.000 [get_ports -filter {DIRECTION == OUT}]
```

`measure_tile.tcl` (run with `vivado -mode batch -source measure_tile.tcl`):
```tcl
read_verilog -sv [glob rtl/*.sv rtl/*.v]          ;# your file list, repo-relative
read_xdc tile_ooc.xdc
synth_design -top tile_top -part xc7a100tcsg324-1 -mode out_of_context -flatten_hierarchy none
report_utilization -hierarchical -hierarchical_depth 4 -file reports/util_hier_synth.rpt
opt_design; place_design; phys_opt_design; route_design
report_utilization -file reports/util_routed.rpt
report_utilization -hierarchical -hierarchical_depth 4 -file reports/util_hier_routed.rpt
report_timing_summary -max_paths 10 -file reports/timing_routed.rpt
report_high_fanout_nets -max_nets 20 -timing -file reports/fanout.rpt
report_drc -file reports/drc.rpt
report_methodology -file reports/methodology.rpt
```

**Always report:**
- **post-route** numbers, labelled "post-route";
- the git commit ID of the RTL that was measured.

A number without its report file is not accepted.

## 2. Where CPU-tile area usually goes, and the knobs you have

You may **not** edit `picorv32.v`, but PicoRV32 is configured through **parameters** on its instance, and those are
yours to choose.

| Knob (PicoRV32 parameter or your design) | What it controls | Typical effect | Condition |
|---|---|---|---|
| `ENABLE_MUL` / `ENABLE_FAST_MUL` | multiplier: iterative in LUTs vs. DSP-based | FAST_MUL moves the multiply into DSP48s and **usually saves LUTs**; it is also faster | check software needs `mul` |
| `ENABLE_DIV` | hardware divider | a sizeable LUT block. If programs rarely divide, a software divide (libgcc) costs no LUTs | software audit (step 13) |
| `COMPRESSED_ISA` | RV32C decoder | saves IMEM (BRAM) but costs LUTs. Choose on measured numbers, not habit | changes `-march`; Lane 1 must agree |
| `ENABLE_COUNTERS`, `ENABLE_COUNTERS64` | rdcycle / rdinstret counters | 64-bit counters cost about twice the 32-bit ones. Step 8 needs `rdcycle`; check whether 32 bits are enough | keep `ENABLE_COUNTERS=1` |
| `BARREL_SHIFTER`, `TWO_STAGE_SHIFT` | shifter structure | barrel = fast and big; two-stage = smaller; neither = smallest and slowest | measure both |
| `TWO_CYCLE_ALU`, `TWO_CYCLE_COMPARE` | split ALU / compare over 2 cycles | can **raise timing margin** cheaply | measure |
| `ENABLE_IRQ`, `ENABLE_IRQ_QREGS`, `ENABLE_IRQ_TIMER` | interrupts | turn off if the demo uses none | software audit |
| `ENABLE_PCPI`, `ENABLE_TRACE` | co-processor port, trace | off unless used | - |
| `ENABLE_REGS_DUALPORT` | register file read ports | affects LUTRAM and speed | measure |
| `CATCH_MISALIGN`, `CATCH_ILLINSN` | traps | **keep on**: step 3 (bus errors) needs traps | do not turn off |
| Peripherals (UART, GPIO, `tile_status`, timer) | each has registers and decode | remove anything the two demo programs do not use; UART TX only if RX is unused | demo needs |
| Local address decode | compares on the address | decode only the bits the map needs (upper nibble / region bits), not full 32-bit compares | keep the map exact |
| Memories | IMEM / DMEM | must map to **BRAM** (inferred `reg [31:0] mem [...]` with a registered read), never LUTRAM or flip-flops | check util: LUTRAM count |
| Debug taps (`dbg_*`) | observation ports | keep them out of the synthesized netlist (leave unconnected at the top, or `ifdef` for simulation) | step 3 fixes their meaning |
| Reset | every flip-flop with a reset | reset only what needs a known value; a reset on a datapath register can cost a LUT | keep the CPU reset correct |

**One lesson from Lane 1 this week:** deleting a register does **not** always save LUTs. On this FPGA a register's enable
and reset pins are free; if removing it turns those into logic, LUTs go **up**. Lane 1 removed a state copy and lost +790
LUTs per engine. **Measure every change; never assume it.**

## 3. Steps 11-20 (new)

Steps 11, 12 and 13 can start **now**, in parallel with steps 1-6: they only measure. Steps 14-17 change the design and
start **after step 2 passes**.

### Step 11: Baseline measurement with the common recipe
- **Do:** run section 1 on the current `tile_top`. Fill a table per submodule from `util_hier_routed.rpt`: PicoRV32,
  adapter, each peripheral, memories, decode.
- **Done when:** `RESOURCES.md` has the post-route table (LUT, FF, LUTRAM, BRAM, DSP; WNS, WHS) with the commit ID, and
  the report files are in the package.

### Step 12: PicoRV32 parameter sweep (measurement only)
- **Do:** build the same `tile_top` with different PicoRV32 parameter sets and measure each one with section 1. At least
  these:
  1. the current configuration (baseline);
  2. `ENABLE_FAST_MUL=1` (DSP multiply) instead of the iterative one;
  3. `ENABLE_DIV=0`;
  4. `ENABLE_COUNTERS64=0`;
  5. `BARREL_SHIFTER=0, TWO_STAGE_SHIFT=1` and `=0, =0`;
  6. `COMPRESSED_ISA=0`;
  7. `ENABLE_IRQ=0` (if the demo uses none);
  8. `TWO_CYCLE_ALU=1`, `TWO_CYCLE_COMPARE=1` (for timing).
- **Done when:** `PARAM_SWEEP.md` has one row per configuration (LUT, FF, DSP, LUTRAM, WNS), all post-route, with the
  report files. **No configuration is adopted in this step.**

### Step 13: Software needs audit
- **Do:** for Program A and Program B (step 8), disassemble the hex builds (`riscv32-unknown-elf-objdump -d`) and count:
  - multiply and divide instructions;
  - compressed instructions;
  - interrupts / CSRs used;
  - which peripherals and addresses are touched.
- **Also do:** build each program for `-march=rv32i`, `rv32im` and `rv32imc`, and record the code size of each.
- **Done when:** `SW_AUDIT.md` lists, per feature, "used / not used" with the evidence. From the audit and step 12, propose
  ONE configuration, with its expected LUT saving, in `AREA_PROPOSAL.md`.
- **Send the proposal to Lane 1 before applying it.** An ISA change (for example dropping C or M) changes the toolchain
  flags and needs Kalash's agreement.

### Step 14: Apply the agreed configuration (after step 2 PASS and Lane 1 agreement)
- **Do:** set the agreed PicoRV32 parameters at the instance (not inside `picorv32.v`), and rebuild the programs with the
  matching `-march`.
- **Done when:** section 1 measured, and the step 18 regression PASSes.

### Step 15: Peripheral and decode diet
- **Do:** for each peripheral, state whether Program A or B uses it.
  - Remove or park unused ones behind a parameter defaulting to off.
  - Reduce the local decode to the bits the address map needs.
  - Make `tile_status` use the synchronous reset through `reset_sync` (finding O5).
- **Done when:** the per-submodule table shows the saving, and every removed address returns a **bus error** (never
  silent 0), which is tested.

### Step 16: Memories in BRAM, outside the tile where agreed
- **Do:** make sure IMEM / DMEM infer **BRAM** (check `util_routed.rpt`: no LUTRAM or flip-flop arrays for memory). Follow
  decision D3 from the first brief for where memories live.
  - If IMEM stays inside the tile, report its BRAM count explicitly.
  - The 4 BRAM inside the current tile must be explained (finding O5).
- **Done when:** LUTRAM is only the register file (or zero), and the BRAM count matches the documented memory sizes.

### Step 17: Timing hygiene for integration
- **Do:**
  - from `timing_routed.rpt`, list the 10 worst paths with their logic levels;
  - from `fanout.rpt`, list any net with fanout > 500 and fix it, for example by registering or duplicating the driver;
  - make sure every TMEM output is driven straight from a flip-flop (no logic between the register and the port), so
    Lane 1's bridge gets a full cycle.
- **Done when:** WNS >= +1.0 ns target (hard limit +0.5 ns) at 20 ns, with the 5 ns I/O budgets of section 1, and the
  TMEM-output check written in `TIMING.md`.

### Step 18: Regression after every area change
- **Do:** after each change in steps 14-17, re-run:
  - TMEM conformance (step 2): 0 errors;
  - random-latency stress (step 4): 1,000 / 1,000 seeds;
  - bus-error tests (step 3);
  - memtest (step 7);
  - Programs A and B in `tb_two_tiles` (step 8).
- **Also do:** add **three mutants** of the adapter, each a deliberately broken copy, made by a script and never
  committed as the real design:
  1. capture each request twice (the old bug);
  2. drop `tmem_err`;
  3. return read data one cycle late.

  Each must make at least one test FAIL.
- **Done when:** every test PASSes on the real design, and each mutant is caught, with the logs in the package.

### Step 19: Two tiles together (the real cost)
- **Do:** synthesize and implement a small top with **two** `tile_top` instances (tile ID 0 and tile ID 3, the two demo
  programs' memories), out of context with the section 1 recipe.
- **Done when:** `RESOURCES.md` shows the two-tile total and confirms it is <= 2 x the single-tile number, with WNS
  reported.

### Step 20: Area report and re-submission
- **Do:** write `AREA_REDUCTION.md`:
  - before / after table per submodule;
  - each change, its measured saving and its cost (speed, code size, features);
  - every number labelled post-route, with its report file and commit.
- **Package** it with the step 10 package (git-tracked, clean tree, SHA-256 of the zip, commit ID).
- **Done when:** Lane 1 can re-run section 1 on your commit and get the same numbers within a few LUTs.

## 4. What to send back

| File | Contents |
|---|---|
| `RESOURCES.md` | baseline and final per-submodule tables; single-tile and two-tile totals |
| `PARAM_SWEEP.md` | step 12 table |
| `SW_AUDIT.md` | step 13 evidence |
| `AREA_PROPOSAL.md` | the one configuration you propose, **sent before applying it** |
| `AREA_REDUCTION.md` | before / after, with costs |
| `TIMING.md` | worst paths, fanout fixes, TMEM-output check |
| `reports/` | every `.rpt` the numbers come from |
| `logs/` | every simulation log behind a PASS |

## 5. Rules (in addition to section 3 of the first brief)

- **Measure, then change.** No area change goes in without a before / after number from section 1.
- **Never** edit `picorv32.v`, change the TMEM signals, add a clock, or add a clock-domain crossing.
- **Never** turn off traps (`CATCH_MISALIGN`, `CATCH_ILLINSN`), weaken a test, or lower an expected count to save area.
- **An ISA change needs Lane 1's agreement first** (step 13), because Lane 1's software expectations and the demo depend on
  it.
- **Report honestly:** "post-route measured", "post-synthesis", "estimate" and "not run" are different; label each one.

## 6. Prompt for your AI assistant (paste this)

> You are helping the RISC-V CPU tile team of the PQ-Attest project. Read `BRIEF_RISCV_LANE_NEXT10_20261031.pdf` (steps
> 1-10) and this addendum (steps 11-20). The FPGA is xc7a100tcsg324-1, Vivado 2024.1, one 20 ns clock. Our tile is
> PicoRV32 (do not edit `picorv32.v`; configure it only through its parameters) plus an adapter to a 10-signal TMEM bus,
> peripherals and memories. Our area budget is <= 1,300 LUT per tile (hard limit 1,600) and WNS >= +1.0 ns out of context
> with 5 ns I/O budgets.
>
> Work in this order:
> 1. Steps 1-6 of the first brief (bug fixes and tests) must pass first.
> 2. In parallel, do only measurements: steps 11, 12 and 13, using exactly the recipe in section 1.
> 3. Write AREA_PROPOSAL.md and stop: Lane 1 must agree before any ISA change.
> 4. Then apply changes one at a time (steps 14-17). After each one, run the step 18 regression and record the
>    before / after numbers.
>
> Never claim a number without the report file behind it. Never weaken a test. Never turn off traps. Label every result as
> post-route, post-synthesis, estimate or not run.
