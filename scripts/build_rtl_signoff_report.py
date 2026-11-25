"""Build the final RTL design-freeze sign-off report (13 Nov 2026) as HTML; Word renders it to .docx / .pdf
(scripts/render_completion_report.ps1). Content is fixed here; fresh tool results are read from a small JSON so the report
cannot claim a run that did not happen.
Usage: python -I scripts/build_rtl_signoff_report.py <fresh_results.json> <out.html>
"""
import html
import json
import sys
from pathlib import Path

R = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
E = html.escape
B = []


def p(t): B.append(f'<p>{E(t)}</p>')
def h1(t, brk=False): B.append(('<br clear="all" style="page-break-before:always">' if brk else '') + f'<h1>{E(t)}</h1>')
def h2(t): B.append(f'<h2>{E(t)}</h2>')
def ul(items): B.append('<ul>' + ''.join(f'<li>{E(i)}</li>' for i in items) + '</ul>')
def note(t): B.append(f'<p class="note">{E(t)}</p>')


def table(headers, rows, widths=None):
    w = widths or [0] * len(headers)
    out = ['<table>', '<tr>' + ''.join(f'<th{(" width=" + chr(34) + str(x) + "%" + chr(34)) if x else ""}>{E(h)}</th>' for h, x in zip(headers, w)) + '</tr>']
    for i, r in enumerate(rows):
        out.append(f'<tr class="{"alt" if i % 2 else ""}">' + ''.join(f'<td>{E(str(c)).replace(chr(10), "<br>")}</td>' for c in r) + '</tr>')
    B.append('\n'.join(out) + '\n</table>')


sim = R['sims']
sim_ok = all(s['result'] == 'PASS' for s in sim.values())
sim_rows = [[k, s['cmd'], s['checks'], s['result'], s['note']] for k, s in sim.items()]

# ---------------------------------------------------------------------------------------------------- title and verdict
B.append('<p class="title">Final RTL design-freeze sign-off report</p>')
p('NoC + PQ-Attest + two RISC-V CPU tiles  |  Artix-7 xc7a100tcsg324-1, Arty A7-100T  |  Audit date 13 November 2026  |  Prepared for Kalash Bheda')
p(f'Audited revision: branch noc/credit-integration, commit {R["head"]}. The active RTL, constraints and firmware are identical to tag '
  'rtl-rc1-20261112 (commit 416379e1); the only later source change is the block-design shell synth/merged/pq_merged_board_bd_ref.v, '
  'which is not in the build list.')
B.append('<p class="verdict">Conclusion: B. RTL CONDITIONALLY CLOSED: specific verification and implementation conditions remain.</p>')
p('The hardware RTL is functionally complete for the approved scope and can be frozen now. No defect was found that breaks the '
  'demonstrated behaviour of the board build. Closure is conditional because (1) the measured 64-byte firmware window contains '
  'only the jump stub of the current firmware, which weakens the "firmware is measured" claim and needs your decision; (2) the '
  'demo firmware turns itself into FAIL after a few minutes without a button press; (3) the current image has not been run on the '
  'board; and (4) several verification gaps and latent corner-case defects are documented below. None of these needs a change to '
  'the protected RTL files.')

h1('1. Executive engineering verdict', brk=False)
table(['Question', 'Answer', 'Evidence'], [
    ['Is the RTL implementation complete?', 'Yes, for the approved scope.', 'Original R4 plan NOC 5/5 and PQ 5/5; increments I-9 to I-26 PASS; all 70 active sources read by independent reviewers.'],
    ['Is the original approved scope satisfied?', 'Yes for the approved scope. The original one-page proposal had items that were later scoped out (section 3).', 'docs/CODEX_INSTRUCTIONS_R4_FINAL, RESEARCH_SCOPE_AND_GDS_PLAN, DECISION_REGISTER.'],
    ['Is the architecture correct?', 'Yes. The RTL matches the approved six-tile architecture; all connections checked.', 'Reviewer traces of pq_noc_subsystem_p7, pq_soc_merged_core, board top.'],
    ['Are all active modules integrated?', 'Yes. 70 sources, no unused active module except noc_addr_decoder (test-only, harmless).', 'Source list scripts/merged_bitstream_sources.tcl; synthesis log.'],
    ['Is the verification evidence sufficient?', 'Sufficient for the demonstrated behaviour; gaps remain (no coverage, no formal, a few weak checks).', 'Section 5.'],
    ['Are existing results current and reproducible?', 'Yes. Preflight PASS, harness self-tests PASS, fresh simulations ' + ('PASS' if sim_ok else 'see section 5') + ', current build gate PASS.', 'Section 5 and 6.'],
    ['Are mandatory RTL tasks outstanding?', 'No mandatory RTL change found. Two firmware items and one scope decision remain.', 'Defect register, section 8.'],
    ['Can the RTL be frozen?', 'Yes, conditionally (section 13).', 'Section 9 checklist.'],
    ['Is the design ready for final FPGA validation?', 'Yes, with the button-timing note in section 10.', 'Gate PASS on the 12 Nov build.'],
    ['Can ASIC RTL-to-GDSII planning begin?', 'Yes. ASIC adaptations are wrapper/configuration work, not RTL rework.', 'Section 11.'],
], [28, 32, 40])

# ---------------------------------------------------------------------------------------------------- baseline
h1('2. Audited project baseline')
table(['Item', 'Value'], [
    ['Repository', 'C:\\vivado_verilog_proj\\NOC_PQATTEST, branch noc/credit-integration, HEAD ' + R['head']],
    ['Working tree', 'Uncommitted: NOC_PQATTEST.xpr and two line-ending-only decision documents (standing practice). Untracked, not in any build: pq_attest_protocol_pkg.sv, pq_attest_request.sv, pq_attest_response.sv, backup copies, the GUI block-design source set.'],
    ['Top level', 'pq_merged_board_top (board wrapper) > pq_soc_merged_core > two cpu_tile_noc + pq_noc_subsystem_p7 + tile-2 BRAM'],
    ['Active sources', '70 files + firmware sw/riscv/demo_fw_v2.hex, from scripts/merged_bitstream_sources.tcl'],
    ['Defines', 'PQ_MAC_ON, CPU_TILE_MODULE=cpu_tile_noc, REAL_CPU_TILE'],
    ['Constraints', 'synth/merged/pq_merged_board_arty.xdc (12 pins, 100 MHz clock, MMCM-derived 50 MHz design clock)'],
    ['Device, board, clock', 'xc7a100tcsg324-1, Arty A7-100T, one 50 MHz clock'],
    ['Tools', 'Vivado / XSim 2024.1 (build 5076996); Python 3.13; no Verilator; no formal tool; no code-coverage collection'],
    ['Verification harness', 'scripts/dual_lane.py with 615 registered jobs (501 simulation incl. 231 mutants, 64 Python, 22 OOC synthesis, 12 implementation, 10 reuse, 6 unimplemented gates)'],
    ['Current build', '12 Nov 2026 17:35 (GUI flow): image sha256 2b2518be...2913; release flow 14:05: 9dd6dca6...7000'],
    ['ASIC artifacts', 'None (plan only: docs/proposals/RESEARCH_SCOPE_AND_GDS_PLAN_20261106.md)'],
], [24, 76])
h2('Files inspected')
table(['Group', 'Files', 'Inspected by'], [
    ['NoC core', '13 (packages, FIFO, crossbar, XY routing, arbiter, allocator, credit counter, datapath, router, mesh, address decoder, NI p7_i9)', 'Independent reviewer, every line'],
    ['Cryptography', '29 (Keccak, SHA3, KMAC, KDF, measurement, tag, shared-engine variants)', 'Independent reviewer, every line, against FIPS 202 / SP 800-185 and the Python reference'],
    ['Attestation and subsystem', '13 (protocol s3, L2 arbiter / engine / auth / pair, quarantine, parser, endpoint, gate, fault status, verifier, reset bridge, subsystem)', 'Independent reviewer, every line, against M-F1 rev 9'],
    ['RISC-V tiles, core, board', '14 + XDC + firmware source (PicoRV32 itself: integration only)', 'Independent reviewer, every line'],
    ['Verification environment', 'Harness, registry, 8 top-level benches in full, gate reports I-24 to I-26', 'Independent reviewer'],
    ['Tool evidence', 'Synthesis and implementation logs, gate summary, timing, CDC, methodology, DRC reports of the current build', 'Audit lead'],
], [22, 50, 28])
note('Not inspected line by line: the third-party PicoRV32 core (integration only), about 580 older benches beyond their headers, waveform files.')

# ---------------------------------------------------------------------------------------------------- traceability
h1('3. Original plan versus actual implementation', brk=True)
p('Sources: the original one-page proposal (PQ-Attest_OnePager.pdf), the approved plan docs/CODEX_INSTRUCTIONS_R4_FINAL_2026-10-08.md '
  '(five NoC and five PQ-Attest steps, increments I-1 to I-8), later approved revisions M-F1 rev 6 to rev 9, and '
  'docs/proposals/RESEARCH_SCOPE_AND_GDS_PLAN_20261106.md (approved scope and exclusions).')
table(['#', 'Requirement', 'Source', 'Implementation', 'Verification evidence', 'Status'], [
    ['R1', 'Two RV32I soft cores', 'One-pager', 'Two PicoRV32 tiles (tiles 3 and 0), with MUL/DIV/compressed enabled', 'Closure bench (fresh), board 7 Nov', 'VERIFIED COMPLETE'],
    ['R2', '2D mesh NoC, deterministic XY routing', 'One-pager, NOC-1..5', '3x2 mesh, 6 routers, 5 ports, wormhole, credits, 3 VCs', 'tb_i11_noc_spec + XY mutant, tb_noc_mesh', 'VERIFIED COMPLETE'],
    ['R3', 'Memory subsystem', 'One-pager', 'Tile-2 BRAM behind a front end that checks authorization at access time', 'Closure, phase sweep, in-flight benches', 'VERIFIED COMPLETE'],
    ['R4', 'Hardware root of trust', 'One-pager, PQ-2..5', 'RoT verifier on tile 4: CHALLENGE, GRANT, REVOKE, timeout', 'Full-chain, verifier-revoke, closure', 'VERIFIED COMPLETE'],
    ['R5', 'Keccak / SHA-3 primitive', 'One-pager, PQ-1/PQ-3', 'Keccak-f[1600], SHA3-256, KMAC128, KDF', 'Vectors from the hash-pinned Python reference; NIST SP 800-185 sample', 'VERIFIED COMPLETE'],
    ['R6', 'NTT (shared ML-KEM / ML-DSA kernel)', 'One-pager', 'Not implemented', 'none', 'APPROVED DEFERRED (scoped out: symmetric only)'],
    ['R7', 'Post-quantum-signed measurement', 'One-pager', 'Symmetric KMAC128 tag instead of a signature', 'Full chain', 'APPROVED DEFERRED (scope: symmetric only)'],
    ['R8', 'NI withholds routing until the tile is attested', 'One-pager, NOC-4', 'Per-tile authorization gates; tile 3 attestable; tile 0 refused locally', 'Gate benches + mutants, closure', 'VERIFIED COMPLETE (one tile attested)'],
    ['R9', 'Continuous verification while running', 'One-pager', 'Authorization checked on every memory access; re-attestation on demand (button 1); no timer', 'Phase sweep, closure re-attest', 'PARTIALLY COMPLETE (no periodic re-attestation)'],
    ['R10', 'Overhead vs non-attested baseline (area, latency, throughput)', 'One-pager', 'Fixed-admission research baseline built and measured', 'I-25 matched experiment', 'VERIFIED COMPLETE'],
    ['R11', 'Spoofed-tile threat model over a physical link, second board', 'One-pager', 'SPOOF injection port + quarantine (simulation); no second board', 'tb_p7_ingress, tb_i7_sec', 'PARTIALLY COMPLETE (simulation only; tied off on the board)'],
    ['R12', 'L2 link authentication with replay rejection', 'NOC-3, M-F1 rev 6/7', 'KMAC128 tag, 80-bit epoch, 64-bit sequence on tiles 3/4', 'tb_s2_attacks, tb_i7_sec + replay mutants', 'VERIFIED COMPLETE'],
    ['R13', 'Measurement over tile ID, config and 64-byte IMEM window', 'D2 / K-3, RESEARCH_SCOPE', 'Implemented as specified', 'tb_i10_d2, closure', 'IMPLEMENTED; see finding D-01 (window holds only the jump stub)'],
    ['R14', 'FPGA demonstration on the board', 'One-pager, plan step 12', 'Current image gate PASS; 7 Nov image "PASS" (not itemised)', 'HARDWARE_RUN_20261107.md', 'IMPLEMENTED BUT INSUFFICIENTLY VERIFIED (current image not on board)'],
    ['R15', 'ASIC GDSII with the college Cadence flow', 'RESEARCH_SCOPE phase A', 'Not started', 'none', 'APPROVED DEFERRED (next phase)'],
], [4, 20, 12, 25, 21, 18])

h2('Items flagged on the website as "not built": why, and should we build them?')
table(['Item', 'Why it was not built', 'Should we build it?'], [
    ['Second board and physical attacker link', 'The spoofed-tile threat is exercised on one chip through the SPOOF injection port, which made a second board unnecessary for the protocol evidence. Integration time went to the two CPU tiles instead.',
     'Not as two boards. The cheaper and stronger option is to drive the existing injection port from the board (for example a PMOD or a second UART into the quarantine) so the forged-packet rejection becomes board evidence instead of simulation only. That is a small RTL change in the board top plus a contract revision; worth doing only if the paper needs a hardware attack demonstration.'],
    ['NTT, ML-KEM, ML-DSA, post-quantum signatures', 'Scoped out on 6 Nov (RESEARCH_SCOPE): the attestation protocol was built on symmetric KMAC128. A lattice signature engine would be a separate large block on an FPGA already at 55 % LUTs, and NTT alone is not a post-quantum scheme.',
     'Not in this phase. Keep it as future work and keep the honest wording ("symmetric, hash-based; post-quantum signatures not implemented"). If the "PQ" claim must be strengthened, the realistic next step is a verify-only ML-DSA block in a separate study, not added to this frozen design.'],
    ['Attestation of every tile', 'The demo needs one attested tile and one refused tile. Each attestable tile adds an endpoint (about 6,600 LUTs) and link authentication (about 6,600 LUTs for the pair).',
     'No. The mechanism is per-tile and parameterised (ATTESTABLE); the paper can state that it generalises. Building more copies adds area, not new evidence.'],
    ['Periodic (continuous) re-attestation', 'Rev 9 chose RoT- or button-started attestation only; a periodic start was not requested.',
     'Optional and cheap: a timer in the board top (not a protected file) that pulses start_attestation every few seconds would match the original "continuous" wording. It changes behaviour, so it needs your decision and a re-run of the closure and lifecycle benches.'],
    ['Formal proof, side-channel protection, TRNG', 'Out of scope by decision (RESEARCH_SCOPE section 4). No formal tool is available on this machine.',
     'Formal: worth doing later on a few small properties (gate cannot set authorized without GRANT, replay rejected) if the college has JasperGold. Side-channel protection and a TRNG: no, state as limitations.'],
    ['ASIC flow (RTL to GDSII)', 'Planned as the next phase; needs the college tools and PDK.', 'Yes, it is the next milestone (section 11).'],
], [20, 38, 42])
note('Missed from the original plan in substance: the two-board physical attack demonstration, post-quantum signatures / NTT, attestation of every unit, and continuous re-attestation. All four were scoped out or narrowed by later decisions; none is an unfinished approved requirement.')

# ---------------------------------------------------------------------------------------------------- file-by-file
h1('4. File-by-file audit summary')
table(['Group / file', 'Purpose', 'Status', 'Findings'], [
    ['NOC_PKG, noc_p7_pkg', 'Types, header layout, per-type MAC', 'Clean', 'Duplicate package names across folders are kept apart by explicit source lists (INFO)'],
    ['NOC_FIFO, CROSSBAR, XY_ROUTING, arbiter, allocator, credit counter, datapath', 'Router internals', 'Clean', 'No latch / driver / loop issues; wormhole lock per physical output (by design); unguarded immediate asserts (INFO); credit counter lacks `timescale (INFO)'],
    ['noc_router, noc_mesh_3x2', 'Router and 3x2 mesh with LINK_PIPE', 'Clean', 'All 24 data and 14 credit links checked; out-of-mesh destinations would block a VC (LOW, unreachable)'],
    ['noc_addr_decoder', 'Address decoder', 'Not used by the active design', 'Test-only'],
    ['noc_network_interface_p7_i9', 'NI TX/RX, outstanding table, watchdog, slot timeout', 'One latent defect', 'D-03 slot double-free race (MEDIUM, latent)'],
    ['Keccak / SHA3 / KMAC / KDF / measurement / tag (29 files)', 'Cryptography', 'Clean; conformance verified by reading', 'D-08 to D-11 (LOW, guarded by the parent); secrets kept in registers after use (INFO); dead logic (INFO); D-12 use-before-declaration in SHA3_256_xp.sv'],
    ['pq_attest_protocol_s3, endpoint, verifier', 'Attestation protocol', 'Clean', 'D-07 GRANT vs fail ordering (LOW); nonce/epoch freshness is the input\'s responsibility (INFO); stale "not compiled" header (INFO)'],
    ['l2_arbiter, l2_kmac_engine, l2_auth, l2_pair', 'Link authentication', 'Clean', 'Replay rejection, full-width tags, owner routing all hold'],
    ['ingress parser / quarantine / merge', 'Ingress checks', 'Clean', 'D-04 data packets to tile 4 can disturb attestation (MEDIUM, tied off on the board)'],
    ['noc_attest_gate, noc_fault_status, rst_bridge', 'Authorization gate, fault record, reset', 'Clean', 'D-14 clear-vs-event ordering (LOW)'],
    ['pq_noc_subsystem_p7_i9', 'Subsystem top, memory front end', 'Clean wiring', 'D-05 front end drops a request while busy (MEDIUM, not reachable in the merged build)'],
    ['cpu_tile_noc, tile_top, adapter, decoder, memories, UART, GPIO, status', 'RISC-V tile', 'Clean', 'D-06 DMEM is executable (MEDIUM, scope); D-15 minor UART / poison behaviours (LOW)'],
    ['tmem_app_bridge, meas_window_reader', 'Remote memory bridge, measurement window', 'Clean', 'Refusal never sends a packet (verified); window reads exactly bytes 0x00-0x3F'],
    ['pq_soc_merged_core, pq_merged_board_top, XDC', 'Core and board wrapper', 'Clean', 'MMCM 1000 MHz VCO, exactly 50 MHz; all 13 ports pinned; synchronisers correct; missing ASYNC_REG (INFO)'],
    ['demo_fw_v2.S / .hex', 'Demo firmware', 'Two issues', 'D-01 measured window holds only the jump stub (HIGH, scope); D-02 waits time out into FAIL after a few minutes (HIGH, demo)'],
], [24, 22, 16, 38])

# ---------------------------------------------------------------------------------------------------- verification
h1('5. Verification evidence', brk=True)
h2('Fresh checks run for this audit (13 Nov 2026, current sources)')
table(['Check', 'Command / method', 'Checks', 'Result', 'Notes'],
      [['Harness preflight', 'python -E scripts/dual_lane.py preflight', '249 guarded files, 615 source lists', 'PASS', 'Protected files and harness unchanged'],
       ['Harness self-tests', 'python -E scripts/test_dual_lane.py', '150 tests', 'PASS', 'Includes the controlled-diagnostics tests'],
       ['Freshness of sources', 'git diff since the accepted I-26 run (b80baee1)', '-', 'PASS', 'Only the block-design shell changed; not in the build'],
       ['Core changes since I-24', 'git diff -w 392deb80 05733498 (core) and 423a81c4 392deb80 (bridge)', '-', 'Comments only / one elaboration-time check', 'Closes most of verification gap V-06']] + sim_rows +
      [['CDC and timing checks', 'report_cdc, check_timing on the routed 12 Nov checkpoint (12 Nov 21:05)', '-', 'PASS', 'No clock-to-clock crossings; 0 unconstrained endpoints, loops, latch loops'],
       ['Static scans', 'grep of the 70 active sources', '-', 'PASS', '0 TODO/FIXME; 11 initial blocks: 8 guarded, 3 legitimate (FIFO $fatal check, PicoRV32 register init, BRAM firmware load)']],
      [18, 34, 12, 10, 26])
h2('Historical evidence (accepted gate runs)')
p('Increments I-13 to I-26 PASS; I-25 accepted 17/17 in run 170116 (3 fresh, 14 identity-matched reuse); I-26 3/3 fresh in run 225013. '
  'Recorded failures (I-25 runs 132805 and 124233) were kept, diagnosed (tool environment, wall-clock timeout during sleep, a gate '
  'comparing the wrong property) and fixed with negative controls; no expected count was changed.')
h2('Verification gaps (not defects in the design)')
table(['ID', 'Gap', 'Evidence', 'Effect'], [
    ['V-01', 'MC_CONFIG_BINDING compares two testbench constants', 'tb_merged_closure.sv:77', 'That check cannot fail because of the DUT'],
    ['V-02', 'The spoof injection helper does not confirm the flit was accepted', 'tb_i9_integ.sv:182-187', 'I9_UNAUTH_NO_BRAM could pass vacuously'],
    ['V-03', 'CHECKS printed as a constant in two benches', 'tb_random_latency.sv:421, tb_mixed_conformance.sv:410', 'Skipped checks would not be caught by the count (offset by RESULT conditions)'],
    ['V-04', 'Random-latency campaign covers instruction fetches only', 'tb_random_latency.sv:241-242', '"1000 seeds" are 1000 single-read runs'],
    ['V-05', '"Something happened" style checks', 'tb_merged_inflight.sv:91,93; tb_merged_phase_sweep.sv:74; tb_i10_d2.sv:130', 'Weaker than exact expected values'],
    ['V-06', 'In-flight and contention benches and their mutant controls last ran on an older hash of the core', 'Run records 020751 / 225013', 'Closed for the benches: code difference is comments plus one elaboration check, and both benches PASS fresh in this audit. The two mutant controls were not re-run.'],
    ['V-07', 'No code coverage, no functional coverage on the final design, no formal proof', 'Harness has no coverage flags', 'Untested corners cannot be ruled out'],
    ['V-08', 'Board run of the current image not done; 7 Nov run not itemised', 'HARDWARE_RUN_20261107.md', 'FPGA validation open'],
], [7, 38, 28, 27])

# ---------------------------------------------------------------------------------------------------- tools
h1('6. Compilation, lint, synthesis and timing')
table(['Item', 'Result', 'Status'], [
    ['Fresh XSim compile of all 70 sources', 'Compiles with the project flow option --relax. Strict compile fails on SHA3_256_xp.sv:70 (identifier used before declaration).', 'PASS with note (D-12)'],
    ['Synthesis (12 Nov 17:35)', '0 errors, 0 critical warnings. Warning classes: unconnected / unused PicoRV32 ports (expected), constant-driven ports, removed unused registers, ignored SVA, one unreachable PicoRV32 case item, one trimmed register (pq_measurement_xp.sv:80). No latch, multi-driver or loop warnings.', 'PASS'],
    ['Implementation', 'Route errors 0, DRC 0, methodology 12 (11 XDCH-2 warnings: same min/max I/O delay; 1 RTGT-1 advisory). Four tool warnings (power estimate, virtual grid, DRC tab).', 'PASS'],
    ['Timing at 20 ns', 'WNS +0.120 ns, TNS 0, WHS +0.009 ns, THS 0, pulse-width slack +3.000 ns. Hold margin is thin but positive.', 'PASS (current build)'],
    ['Resources', '34,952 LUT (55 %), 25,328 FF, 20 BRAM36, 0 DSP, 12 IOB', 'Measured'],
    ['Firmware in the bitstream', 'Gate checks 4/4 IMEM BRAMs initialised for each CPU', 'PASS'],
], [24, 60, 16])

# ---------------------------------------------------------------------------------------------------- clock reset
h1('7. Clock, reset and integration findings')
ul(['One clock domain: 100 MHz board clock to MMCM (VCO 1000 MHz, inside the 600-1200 MHz range of the -1 grade) to exactly 50 MHz; BUFGs on clock and feedback.',
    'Reset: asserted asynchronously while the MMCM is unlocked, released synchronously after 16 clean cycles with button 0 released; the subsystem uses a 2-flop reset bridge.',
    'Asynchronous inputs (three buttons, one switch) pass through two-flop synchronisers; buttons are debounced (2^20 cycles, about 21 ms). ASYNC_REG attributes are missing (INFO).',
    'report_cdc lists no crossings; check_timing: 0 unclocked pins, 0 unconstrained endpoints, 0 loops. I/O paths are declared false with justification.',
    'Integration: every parent-child connection in the subsystem, core and board top was checked for order, width and polarity; bench-only hooks (TB_INJECT, BYPASS_*) are off in the build.',
    'UART: 434 clocks per bit, 115,207 baud (+0.006 %). Memories: 5 x 16 KB = 20 RAMB36.'])

# ---------------------------------------------------------------------------------------------------- defects
h1('8. Remaining defect register', brk=True)
table(['ID', 'Severity', 'File / module', 'Problem', 'Evidence', 'Impact', 'Required action', 'Blocks freeze?'], [
    ['D-01', 'HIGH (scope)', 'sw/riscv/demo_fw_v2.S:3-6 with K3_IMEM_LEN=64', 'The 64 measured bytes hold only "j main", "j handler" and NOPs; all program code from 0x40 is outside the measurement', 'Confirmed: first 16 hex words', 'A modified firmware with the same first 64 bytes passes attestation, which is the attack attestation is meant to catch. Runtime exposure is limited because the CPU cannot write its IMEM.', 'Decision (security scope, hard stop). Recommended: measure the whole IMEM in a contract revision (multi-block SHA3 over 16 KB is 121 blocks of 136 bytes; reading 4,096 words plus 121 permutations is roughly 8,000 cycles, about 0.16 ms at 50 MHz, re-using the existing core). Minimum: state in the paper that the window covers the boot vectors only. Re-arranging the firmware cannot fix it: 64 bytes hold 16 instructions.', 'Blocks the claim, not the RTL'],
    ['D-02', 'HIGH (demo)', 'demo_fw_v2.S:59-66, 83-90', 'Wait loops run out after 268,435,455 iterations and jump to FAIL', 'Confirmed by reading; at about 30 to 40 cycles per iteration on PicoRV32 this is roughly 2.5 to 4.5 minutes (estimate, not measured)', 'Board shows a false FAIL if revoke / re-attest is not pressed in time', 'Firmware change (wait without a limit on the board, keep the bound in simulation), then re-run the closure profile and lifecycle benches; or a board procedure with a time limit. No RTL change; the measured window, and so APPROVED_MEAS, is unaffected (itself a symptom of D-01).', 'No (blocks a clean board demo)'],
    ['D-03', 'MEDIUM (latent)', 'noc_network_interface_p7_i9.sv:765-770, 823-826', 'Slot timeout can free a slot in the same cycle its multi-flit response header is accepted', 'Confirmed by reading', 'Needs a read response exactly 16,384 cycles late; measured worst case is 459 cycles', 'Fix in a later revision (exclude the matching slot from ageing) or document', 'No'],
    ['D-04', 'MEDIUM (availability)', 'pq_rot_verifier.sv:106-115; ingress policy', 'A data packet to tile 4 during verification makes attestation fail', 'Confirmed by reading', 'Denial of service only; impossible on the board (port tied off)', 'Document as limitation; destination policy if the port is ever enabled', 'No'],
    ['D-05', 'MEDIUM (availability)', 'pq_noc_subsystem_p7_i9.sv:313', 'Memory front end ignores a request header that arrives while busy', 'Confirmed by reading', 'Not reachable in the merged build (one outstanding request, one authorised tile)', 'Document; fix if more tiles are authorised', 'No'],
    ['D-06', 'MEDIUM (scope)', 'addr_decode.sv:231', 'Instruction fetch from writable DMEM is allowed', 'Confirmed by reading', 'Code written to DMEM can run unmeasured; demo firmware does not do it', 'Decision: accept and document, or refuse fetches from DMEM', 'No'],
    ['D-07', 'LOW', 'noc_attest_gate.sv:39 vs :47', 'A GRANT in the same cycle as a trusted fail leaves authorized set until the following REVOKE', 'Confirmed by reading', 'Bounded transient', 'Document', 'No'],
    ['D-08..D-11', 'LOW (latent)', 'SHA3_PAD.sv:17; pq_measurement.sv:72-73, 135; pq_kdf.sv:141-147, 223; kmac_128_xp_a5.sv:251-258', 'Full-block final not padded; oversize request dropped silently; context length 15 / key-length codes; start lost in DONE', 'Confirmed by reading; all guarded by the parent', 'None in this design', 'Document; fix only if the blocks are reused', 'No'],
    ['D-12', 'LOW (portability)', 'SHA3_256_xp.sv:70', 'Identifier used before its declaration', 'Fresh strict compile error', 'Vivado accepts it with --relax; ASIC tools may not', 'Fix in an ASIC wrapper copy before Genus', 'No'],
    ['D-13', 'LOW', 'NI:363; NOC_XY_ROUTING.sv:71; allocator.sv:210', 'Self-addressed packets cause an assertion message; an out-of-mesh destination would block a VC', 'Confirmed; both unreachable today', 'None now', 'Document', 'No'],
    ['D-14', 'LOW', 'noc_attest_gate.sv:36; noc_fault_status.sv:8', 'Clear and fault event in the same cycle handled differently in two blocks', 'Confirmed by reading', 'Diagnostic counters only', 'Document', 'No'],
    ['D-15', 'LOW', 'tmem_app_bridge.sv:175; adapter:212; uart_mmio.sv:57-74; board top:132', 'Stale error code, poison executed as an instruction, silent UART writes, possible UART low pulse at power-up', 'Confirmed (one suspected)', 'Cosmetic or firmware-only triggers', 'Document', 'No'],
    ['INFO', 'INFO', 'various', 'Secrets stay in registers after use; dead logic; stale comments; missing ASYNC_REG; duplicate module names handled by source lists', 'Reviewer reports', 'None', 'Optional clean-up', 'No'],
], [6, 9, 15, 18, 12, 14, 16, 10])

# ---------------------------------------------------------------------------------------------------- checklist
h1('9. RTL freeze checklist')
table(['Check', 'Result'], [
    ['All mandatory requirements accounted for', 'PASS'],
    ['All mandatory modules implemented', 'PASS'],
    ['No known functional blocker in the board build', 'PASS'],
    ['No integration blocker', 'PASS'],
    ['No critical lint / elaboration issue in the project flow', 'PASS (strict compile note D-12)'],
    ['Regressions pass on the current baseline', 'PASS (accepted gates + fresh simulations ' + ('PASS' if sim_ok else 'not all PASS') + ')'],
    ['Warnings examined and classified', 'PASS'],
    ['Configuration reproducible', 'PASS (four identical builds; preflight PASS)'],
    ['Documentation reflects the hardware', 'PASS with notes (stale comments, D-01 wording)'],
    ['Measurement binds the firmware as claimed', 'FAIL (D-01)'],
    ['Demo firmware runs indefinitely without operator action', 'FAIL (D-02)'],
    ['Code / functional coverage', 'NOT TESTED'],
    ['Formal proof of security properties', 'NOT TESTED'],
    ['Current image validated on the board', 'NOT TESTED'],
], [70, 30])

# ---------------------------------------------------------------------------------------------------- fpga
h1('10. Remaining FPGA validation')
p('Only the board run remains; synthesis, implementation, timing and bitstream are done for the current sources.')
table(['Step', 'Acceptance criterion'], [
    ['1. Program the recorded image', 'Record the sha256 of the .bit programmed (2b2518be...2913 or 9dd6dca6...7000)'],
    ['2. Power-up', 'LED 3 blinks (about 0.67 s period); within about 1 s LED 0 lights (tile 3 authorised)'],
    ['3. CPU A UART (switch 0 down)', 'Text "PASS T3 cycles=..." and LED 2 on; LED 1 and the green LED off'],
    ['4. CPU B UART (switch 0 up)', 'Text "PASS T0 REFUSED OK" and the red LED on'],
    ['5. Revoke (button 2) within 2 minutes of power-up (D-02, safety margin on the 2.5 to 4.5 minute estimate)', 'LED 0 off; CPU A reports the refused access'],
    ['6. Re-attest (button 1) within 2 minutes of the revoke', 'LED 0 on again; CPU A reports recovery'],
    ['6b. Optional: wait 5 minutes without pressing anything', 'Confirms D-02 on hardware: LED 2 goes out and the green LED lights (expected with the current firmware)'],
    ['7. Record', 'Itemised observations against the image hash in a hardware record'],
], [40, 60])

# ---------------------------------------------------------------------------------------------------- asic
h1('11. ASIC handoff assessment')
table(['Category', 'Item'], [
    ['A. Changes to existing RTL', 'None required by this audit.'],
    ['B. Adaptations by wrapper or configuration', 'ASIC top without MMCM / BUFG (clock from a pad); memories as SRAM macros or smaller flip-flop arrays; firmware loading (the FPGA uses $readmemh initial values, an ASIC needs a boot ROM or loader); demo secrets as inputs or an OTP model; register file not zero-initialised (PicoRV32 REGS_INIT_ZERO is simulation only); fix D-12 in the ASIC copy.'],
    ['C. Normal physical-design tasks', 'Genus synthesis with SDC from the XDC, Conformal LEC, Innovus floorplan / place / CTS / route, Tempus STA, Voltus power, DRC / LVS, gate-level simulation.'],
    ['Prerequisites to confirm first', 'Licensed tools and server access; PDK (gpdk045 / 090 or a foundry PDK); SRAM compiler availability; standard-cell and technology files.'],
], [26, 74])

# ---------------------------------------------------------------------------------------------------- scope
h1('12. Scope decision')
p('The existing RTL development scope can be closed. Freeze the 70 active sources, the constraints and the release recipe as of tag '
  'rtl-rc1-20261112. Two items need your decision before the board run and the paper: D-01 (what the measurement must cover) and '
  'D-02 (firmware wait limits). Both are firmware or contract decisions; neither touches a protected RTL file. Technology-specific '
  'adaptation (section 11) belongs to the ASIC phase. The items in section 3 marked deferred belong to future work.')

# ---------------------------------------------------------------------------------------------------- sign-off
h1('13. Final sign-off matrix', brk=True)
table(['Sign-off gate', 'Verdict', 'Evidence', 'Outstanding conditions'], [
    ['RTL implementation', 'CONDITIONAL GO', 'All approved functions present; five independent line-by-line reviews; no blocker', 'D-01 decision'],
    ['RTL verification', 'CONDITIONAL GO', '615 registered jobs, 231 mutants, accepted gates, fresh preflight and simulations', 'V-01 to V-07; no coverage, no formal'],
    ['RTL freeze', 'CONDITIONAL GO', 'No mandatory RTL change found; sources unchanged since RC1', 'D-01 and D-02 decided (firmware / contract)'],
    ['FPGA validation', 'INSUFFICIENT EVIDENCE', 'Current build gate PASS; 7 Nov board "PASS" not itemised', 'Itemised board run of the current image (section 10)'],
    ['ASIC handoff', 'CONDITIONAL GO', 'No RTL rework needed; adaptations identified', 'PDK, memories, firmware loading, D-12'],
], [18, 16, 36, 30])

h1('14. Final decision', brk=False)
for q, a in [
    ('Q1. Is every mandatory component of the RTL project finished?', 'Yes. Every approved hardware block is implemented, integrated and verified for the demonstrated behaviour.'),
    ('Q2. Is there any mandatory RTL coding, debugging or verification work left?', 'No mandatory RTL coding. Firmware work (D-02) and one scope decision (D-01) remain; the verification gaps are improvements, not blockers.'),
    ('Q3. Can we officially freeze the current RTL?', 'Yes, conditionally: freeze the RTL now and record D-01 and D-02 decisions. If D-01 is resolved by widening the window, that is a contract change and reopens the freeze.'),
    ('Q4. Is the only remaining FPGA work the board validation?', 'Yes, plus the firmware timing note (D-02) for the procedure.'),
    ('Q5. Can we move on to the ASIC scope without unresolved RTL debt?', 'Yes. The ASIC items are adaptations and physical design, not RTL debt.'),
]:
    B.append(f'<p class="q">{E(q)}</p>'); p(a)
B.append('<p class="verdict">B. RTL CONDITIONALLY CLOSED: specific verification or implementation conditions remain.</p>')
p('Why: the design is complete and the evidence for the demonstrated behaviour is current and reproducible, but the measured firmware '
  'window does not cover the program (D-01), the demo firmware times out into FAIL (D-02), the current image has not been run on the '
  'board, and verification has no coverage or formal component. HARDWARE_VALIDATED=NO for this image, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO.')

CSS = ('body{font-family:Calibri,Arial,sans-serif;font-size:10.5pt;line-height:1.15}'
       'p{margin:0 0 6pt 0}.title{font-size:22pt;font-weight:bold;margin:0 0 6pt 0}'
       'h1{font-size:15pt;margin:12pt 0 6pt 0;color:#17365D}h2{font-size:12pt;margin:10pt 0 4pt 0}'
       '.verdict{font-size:12.5pt;font-weight:bold;border:1.5pt solid #17365D;padding:6pt;margin:8pt 0}'
       '.q{font-weight:bold;margin-top:8pt}.note{font-size:9.5pt;color:#444}'
       'table{border-collapse:collapse;width:100%;margin:0 0 8pt 0}'
       'th{background:#17365D;color:#fff;font-size:9.5pt;text-align:left;border:1px solid #D9D9D9;padding:3pt 4pt}'
       'td{font-size:9.5pt;border:1px solid #D9D9D9;padding:3pt 4pt;vertical-align:top}tr.alt td{background:#F1F5F9}'
       'li{margin:0 0 4pt 0}@page{size:8.5in 11in;margin:0.6in 0.6in}')
doc = ('<html><head><meta charset="utf-8"><title>Final RTL design-freeze sign-off report</title><style>' + CSS +
       '</style></head><body>' + '\n'.join(B) + '</body></html>')
out = Path(sys.argv[2]); out.parent.mkdir(parents=True, exist_ok=True); out.write_text(doc, encoding='utf-8')
print('SIGNOFF_HTML_CREATED', out, 'sims_all_pass' if sim_ok else 'SIMS_NOT_ALL_PASS')
