# D-SYN-2 — pq_measurement message-assembly architecture (decision pending)

**Status:** DECIDED by Kalash 2026-10-20: **Option 2, byte-serial assembly.** Reason (data check): the frozen vectors use 7 length layouts and TILE_01/TILE_03 each use 3, so Option 1 would regenerate vectors and re-freeze s8_golden (95), endpoint (275/37) and the legacy bench, which the rules forbid. Option 2 changes no vector and no count; only latency grows (+req_len+1 cycles, ≤ 136 ≈ 2.7 µs). The production
`NOC_PQATTEST.srcs/sources_1/new/pq_measurement.sv` stays protected; the fix will be an `rtl/dual_lane` variant.

## Finding (I-4 run `dual_lane_10_20261020_145731_31d5e260`, `ooc_pq_measurement`, on the D-SYN-1 variant list)

**FAIL:** WNS −0.700 ns, TNS −28.622 ns at 20 ns. **120,581 LUTs, 190 % of the xc7a100t's 63,400.** 4,984 FF, 0 latches,
child-engine check PASS. D-SYN-1 is not the cause: the `sha3_pad` variant is 1,104 LUTs and is proven bit-identical.

### Root cause

`pq_measurement.sv` builds the whole SHA3 block combinationally from registered fields (`:106-130`):

```systemverilog
for (int i = 0; i < CONFIG_MAX_BYTES; i++)
    if (i < int'(config_len_q))
        msg_block[(TILE_ID_BYTES + i)*8 +: 8] = config_q[i*8 +: 8];                       // :117-119
for (int i = 0; i < IMEM_MAX_BYTES; i++)
    if (i < int'(imem_len_q))
        msg_block[(TILE_ID_BYTES + int'(config_len_q) + i)*8 +: 8] = ...imem_q[i*8 +: 8];  // :124-126
```

The imem write offset `TILE_ID_BYTES + config_len_q + i` is a runtime value. Every one of the 136 block bytes can come
from any imem byte, depending on `config_len_q`. Synthesis therefore builds a per-byte comparator plus priority/mux chain
(last assignment wins) for every byte position, and the result feeds the absorb XOR in the same cycle.

**Utilization** (`util_hier.rpt`):

| Instance | Module | LUTs | FFs |
|---|---|---|---|
| pq_measurement (top) | — | 120,581 | 4,984 |
| ↳ u_sha3 | sha3_256 | 7,551 | 3,492 |
| ↳↳ u_keccak_f1600 | keccak_f1600 | 3,741 | 1,621 |
| ↳↳ u_sha3_absorb | sha3_absorb | 1,088 | 0 |
| ↳↳ u_sha3_pad (D-SYN-1 variant) | sha3_pad | 1,104 | 0 |
| **message assembly** (top level, outside u_sha3) | — | **≈ 113,000** | — |

**Critical path** (`worst_paths.rpt`): `msg_block1__2__3_rep__7/C` → `u_sha3/state_reg_reg[0][2][11]/D`. Data path
20.660 ns (logic 4.617 ns, route 16.043 ns), **32 logic levels (LUT6 × 23)**, slack −0.700 ns.

## Data check: which (config_len, imem_len) the frozen vectors and the teammate ZIP use

Script `reports/i4_dsyn2/measurement_data_check.py`; output `reports/i4_dsyn2/measurement_data_check.json`. The ZIP ran
in a disposable copy with `measure_tile` instrumented; the ZIP itself was not modified.

| Source | Layouts (config_len / imem_len) |
|---|---|
| s8_golden (also py_rtl_profile_32, the PQ-1 32-byte profile) | 0/0, 64/64, 64/0, 0/64, 16/16, 33/17, 1/1, 64/64 (8 random tile IDs) |
| full_chain | TILE_03: 16/16 ×3 |
| endpoint_golden | TILE_03: 16/16 ×4, 64/64, 0/0 |
| legacy pq_measurement_tb (M01–M06) | TILE_01: 16/16 ×3, 0/0, 64/64; TILE_02: 16/16 |
| teammate ZIP `measurement_ref.py` | the same six as the legacy bench |
| other ZIP modules | do not call `measure_tile` |

**Result: NOT clean.**
- There are 7 distinct layouts: 0/0, 0/64, 1/1, 16/16, 33/17, 64/0, 64/64.
- TILE_01 and TILE_03 each use 3 layouts (0/0, 16/16, 64/64).
- So neither one fixed layout nor one fixed layout per tile covers the frozen vectors.

## Options

The "per block" figure is the dominant term; the estimates below are not synthesis results.

| | Option 1: parameterized fixed lengths | Option 2: byte/word-serial assembly | Option 3: word-aligned lengths |
|---|---|---|---|
| Mechanism | `CONFIG_LEN` / `IMEM_LEN` become parameters (or a small tile-ID-indexed constant table). The offsets are constants, so assembly is wiring | A small FSM writes tile, config and imem bytes (or 4-byte words with a byte-lane funnel shift) into the 136-byte block register one per cycle, then starts SHA3 | Lengths restricted to multiples of 4, so the offset mux is over 34 word positions instead of 136 byte positions |
| Est. area | ≈ 7.5–8.5 k LUTs (SHA3 core plus wiring) | ≈ 7.5 k (SHA3) + 1–3 k (write decoder, counter, funnel) ≈ **8.5–10.5 k LUTs**, plus ~1.1 k FF for the block register (if not reused) | ≈ 30 k LUTs (about ¼ of the mux); still above the 10 k target |
| Timing | trivially closes | short paths (one byte/word write per cycle); expected to close at 20 ns | better, but still a wide mux into the absorb |
| Latency | unchanged | + up to 135 cycles (byte-serial) or ≈ 34 (word-serial) per measurement, vs. the ~200-cycle controller today | unchanged |
| Digest compatibility | identical **only** for the chosen layout | **identical for every length 0..64** (same bytes, same order) | identical only for multiples of 4 |
| Vectors / frozen counts | **breaks**: s8_golden (6 of 8 layouts), endpoint (2 of 6), legacy bench (2 of 6) and the ZIP examples would need regenerated vectors and re-frozen counts | **no vector or count change**; only cycle counts move (the benches' bounded waits are far larger) | breaks 33/17 and 1/1 (s8_golden) |
| K-3 / C-10 | closes C-10 (fixed per-tile lengths) | C-10 stays a provisioning rule (lengths fixed per tile beside the whitelist), not enforced in hardware | — |

## Recommendation

**Option 2 (serial assembly)**, because the data check is not clean.
- It keeps every frozen vector, the teammate examples, and all I-1..I-3 counts unchanged. Only the measurement latency
  grows.
- Prefer **byte-serial** for the first variant, as the simplest to prove equivalent. Move to word-serial with a byte-lane
  funnel only if the latency matters.

Option 1 remains the cheapest hardware. It would also close C-10, but only if Kalash accepts regenerating the affected
vectors and re-freezing their counts (s8_golden 95, endpoint 275/37, legacy measurement bench).

### Acceptance once Kalash decides

1. `rtl/dual_lane/pq_measurement.sv` variant (same module name), provenance entry, D-SYN-1-style variant lists.
2. **Equivalence:** the variant's digest must be identical to the current RTL for every in-profile vector, and
   exhaustively over lengths. Planned bench: config_len 0..64 × imem_len 0..64 × several data patterns, comparing the
   variant with a TB-only renamed original. The count is frozen before the run.
3. `ooc_pq_measurement` runs **alone first**. Target: **≤ 10 k LUTs and WNS ≥ 0**.
4. Then `ooc_pq_attestation_controller` and `endpoint_ooc`, and the XSim regression on the variant lists (s8_golden 95/0,
   7 mutants, pq_endpoint_unit/sys), with counts unchanged.

## Implementation (Option 2)

- `rtl/dual_lane/pq_measurement.sv`: same module name and ports. A new state `S_BUILD` writes one byte per cycle into the registered block `msg_block_q`:
  - the byte index is the counter `build_idx_q`, and the write is a 136-way constant-index decoder;
  - the source is `tile_id_q[k]` (7-way counter select), else the low byte of the right-shifting `config_sh_q`, else of `imem_sh_q`;
  - no runtime-offset part-select appears inside a loop.
- `msg_block_q` is cleared at accept. This is belt-and-braces: `sha3_pad` already zeroes bytes ≥ valid_bytes. The equivalence bench proves it with junk data beyond the lengths (random and 0xFF patterns).
- Header contracts are unchanged:
  - `valid_bytes`/`is_final` are registered at accept and held to done;
  - done is a one-cycle pulse with busy low;
  - a start while busy is ignored;
  - the accept-time length check is unchanged.

  busy is also high in S_BUILD.
- **Consumers:** none assumes a fixed latency.
  - Controller: `pq_attest_protocol.sv:607-614` waits on `measurement_done`, with no cycle count.
  - Endpoint: waits on the controller's done.
  - Verifier: `pq_rot_verifier.sv:4`, TIMEOUT_CYCLES = 100000.
  - Bench: `tb_stg_8_golden` bounds its waits at 80000 cycles.
- **Exact latency:** `done_var − done_ref = req_len + 1`, where req_len = 7 + config_len + imem_len. That is req_len write cycles plus one cycle with `build_idx_q == valid_bytes`.
- **Equivalence** (`tb_dsyn2_measurement_equiv`, CHECKS 33809, frozen before the first run):
  - 65 config_len × 65 imem_len × 4 patterns (random, all-0x00, all-0xFF, counting with tile TILE_03), each with a digest check and an exact-latency check;
  - 9 protocol checks: start while busy, reset mid-assembly, back-to-back, over-length request.
- **Mutant** `dsyn2_imem_off_by_one`: the imem source is off by one (imem[k−7−config_len+1]), and the targeted check `MEAS_EQUIV_DIGEST` must kill it.
- **Preflight lint:** `dual_lane_preflight.lint_runtime_offset_writes` flags any runtime-offset part-select write inside a for-loop in rtl/dual_lane. It flags the protected original's line 126 and passes all variants.

### Global `$assertoff` window in the equivalence bench (B4 only)

XSim 2024.1 ignores the scope arguments of `$assertoff` (warning: "with scope arguments is not supported yet. All ..."), so
the bench uses unscoped `$assertoff;` / `$asserton;` around the over-length case B4 only (`tb_dsyn2_measurement_equiv.sv:111`
and `:116`). The window contains only B4: set config_len 64 / imem_len 65 (req_len 136 > 135), one start pulse, 300 idle
cycles, and the two B4 checks. Part A and B1–B3 run with all assertions on.

- **Window:** sim time **18,095,100 ns → 18,098,120 ns** (3,020 ns = 302 clocks: pulse 2 + 300).
- **Debug run, not evidence** (`reports/i4_dsyn2/b4_assert_debug/`: `debug_b4.py`, `debug_stdout_NOT_EVIDENCE.txt`).
  - Same bench with the two lines replaced by time markers, so assertions stay ON for the whole run. This is the only diff (CR-insensitive).
  - Same D-SYN-2 source list. The first XSim launch stalled and was relaunched once.
  - Result: CHECKS 33809, ERRORS 0, RESULT PASS.
- **Every assertion that fired in the entire run** (2 messages, both inside the window, both at 18,095,115 ns, the posedge carrying the
  over-length start):

| Instance | Assertion | File:line |
|---|---|---|
| `u_ref` | `a_request_within_limit` | `sim/dual_lane/dsyn2/pq_measurement_orig_dsyn2.sv:272-276` |
| `u_var` | `a_request_within_limit` | `rtl/dual_lane/pq_measurement.sv:206-209` |

No other assertion (`a_no_full_final_block`, `a_done_one_cycle`, sha3/keccak assertions) fired anywhere. The global window therefore hides only
the two expected `a_request_within_limit` errors.
