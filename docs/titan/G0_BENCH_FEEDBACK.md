# G0 scratch feedback — Arnav r2

For the later `ebbf491` handoff, see [D11 checkpoint](G0_D11_CHECKPOINT_20261121.md)
and [evidence review](G0_D11_EVIDENCE_REVIEW_20261121.md). The r2 results below
remain the historical record for the earlier ZIP.

Source ZIP SHA-256 6fc7ba5b376ef927d9a9e20aa70ae3516de885514dc4836ad93e9e66657c3947. The four SystemVerilog benches were copied byte-for-byte to sim/titan/g0_arnav_r2. Scratch XSim 2024.1 compiled all four source files against the B0 list with TB_INJECT=1. All four stopped at elaboration, so there are no simulation RESULT lines.

| Bench | Original SHA-256 |
|---|---|
| tb_g0_m1.sv | ce58d23b5cf89ae3f4d673bf3d14a8e2ee6a308e092e4ed6e145ec229d746ece |
| tb_g0_m2.sv | b847a736db37eb49eee01d8f2fa6dc6a0076cae2c6c43653cc70d203ce13cfd5 |
| tb_g0_m3.sv | 37dc4e59808c9d232885951f7bf7edf414416158fbd05fdc82c4f2b20d73008f |
| tb_g0_sd.sv | c31eb4e84db88eb70a882c340141fa519e4d1f76b78cef6a7e7fda8876260fb9 |

The r2 benches hard-code monitor_event and scoreboard_event bits in the CSV. The verdict uses errors==0 without a frozen check count and CONFIG marker. The CSV and waveform locations depend on the simulator working directory. Arnav owns fixes and evidence. D11 schedules a fallback request if fixed evidence is still absent on 3 December.


| Bench | xvlog | xelab | Simulation RESULT |
|---|---|---|---|
| M1 | Exit 0 | Exit 1, load_row undeclared at line 139 | Absent |
| M2 | Exit 0 | Exit 1, load_row undeclared at line 137 | Absent |
| M3 | Exit 0 | Exit 1, load_row undeclared at line 135 | Absent |
| SD | Exit 0 | Exit 1, load_row undeclared at line 157 | Absent |

The benches call load_row(0). The pinned B0 vectors/full_chain.svh defines load_chain, and the r2 ZIP supplies no replacement vectors. Arnav needs to supply the intended dependency or align his bench call with the pinned source. The imports were kept byte-identical, no jobs were registered, and no G0 property evidence was inferred. Scratch logs and compile lists are under C:/vivado_verilog_proj/_g0r2c. A prior invocation included the unused merged core and stopped before elaboration on a macro parsing diagnostic; the corrected run used the subsystem-only closure.
