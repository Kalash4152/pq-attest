"""make_team_package.py -- build _export/PQ_ATTEST_TEAM_PACKAGE_<date>.zip for the team (Lane 1, 2026-11-07).
Contents: the exact merged-board source list, constraints, firmware, benches, the latest merged build (bitstream + reports),
gate / status reports, scripts and docs, plus README.md (docs/handoff/TEAM_PACKAGE_README_20261107.md) and SHA256SUMS.txt.
Usage: python -I scripts/make_team_package.py
"""
import hashlib, re, sys, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATE = '20261107'
OUT = ROOT / '_export' / f'PQ_ATTEST_TEAM_PACKAGE_{DATE}.zip'

def merged_sources():
    t = (ROOT / 'scripts/merged_bitstream_sources.tcl').read_text(encoding='utf-8')
    m = re.search(r'sources \{([^}]*)\}', t)
    return m.group(1).split()

entries = []   # (arcname, path)
def add(arc_dir, rel, keep_path=True):
    p = ROOT / rel
    if not p.is_file(): raise SystemExit(f'missing {rel}')
    entries.append((f'{arc_dir}/{rel}' if keep_path else f'{arc_dir}/{p.name}', p))
def add_glob(arc_dir, pattern, keep_path=True):
    for p in sorted(ROOT.glob(pattern)):
        if p.is_file(): add(arc_dir, p.relative_to(ROOT).as_posix(), keep_path)

for s in merged_sources(): add('rtl', s)
add('constraints', 'synth/merged/pq_merged_board_arty.xdc', False)
for f in ['sw/riscv/demo_fw.S', 'sw/riscv/demo_fw.hex', 'sw/riscv/memtest.S', 'sw/riscv/memtest.hex', 'sw/riscv/status_regs.h',
          'scripts/rv32_asm.py', 'scripts/hex_to_svh.py']: add('firmware', f, False)
for f in ['rtl/dual_lane/merged/tb_merged_real.sv', 'sim_riscv/include/demo_fw.svh', 'sim_riscv/include/memtest.svh',
          'sim_riscv/include/hello_words.svh', 'sim_riscv/app_port_checker.sv']: add('sim', f)
for tb in ['tb_cpu_tile_noc', 'tb_demo_fw', 'tb_memtest', 'tb_two_tiles', 'tb_two_programs', 'tb_adapter_a3', 'tb_tile_status',
           'tb_mem_bram_dp', 'tb_addr_decode_v2', 'tb_gpio', 'tb_tmem_app_bridge', 'tb_meas_window_reader',
           'tb_app_port_checker', 'tb_bridge_decode_table', 'tb_tile_top', 'tb_conformance', 'tb_random_latency']:
    add('sim', f'sim_riscv/{tb}.sv')
# newest COMPLETED merged build (a build in progress has no result.txt / bitstream yet; merged_build moves older builds aside)
done = [d for d in (ROOT / 'NOC_PQATTEST.runs_merged').glob('merged_board*')
        if (d / 'result.txt').is_file() and (d / 'pq_merged_board_top.bit').is_file()]
if not done: raise SystemExit('no completed merged build found')
B = max(done, key=lambda d: (d / 'result.txt').stat().st_mtime).relative_to(ROOT).as_posix() + '/'
print('build folder:', B)
for f in ['pq_merged_board_top.bit', 'result.txt', 'utilization.rpt', 'utilization_hier.rpt', 'timing_summary.rpt', 's4f3_mesh_util.rpt']:
    add('build', B + f, False)
add('build', B + 'vivado.log', False)
for f in ['I13_GATE_20261107.md', 'I14_GATE_20261107.md', 'I15_GATE_20261107.md', 'I16_GATE_20261107.md', 'I17_GATE_20261107.md',
          'MERGED_BUILD_20261107.md', 'HARDWARE_RUN_20261107.md', 'RISCV_STATUS_20261107.md', 'RISCV_LANE_COMPLETION_20261107.md',
          'OVERNIGHT_20261107.md', 'I12_GATE_20261106.md', 'I11_GATE_20261106.md', 'I10_GATE_20261106.md', 'I9_GATE_20261105.md',
          'LANE1_COMPLETE_CHECKLIST_20261106.md', 'LANE_AUDIT_20261106.md']:
    add('reports', 'reports/' + f, False)
add_glob('reports/tile_ooc_synthesis_B7', 'docs/riscv_lane/b7_20261107/*', False)
add_glob('reports/tile_ooc_implementation_A9', 'docs/riscv_lane/a9_20261107/*', False)
add_glob('reports/merged_gate_negative_tests', 'docs/riscv_lane/i17_gate_tests_20261107/*', False)
add('reports', 'docs/riscv_lane/RESOURCES.md', False)
for f in ['scripts/merged_project_update.tcl', 'scripts/merged_bitstream_flow.tcl', 'scripts/merged_bitstream_sources.tcl',
          'scripts/make_merged_sources.py', 'scripts/merged_provision.py', 'scripts/merged_impl.tcl', 'scripts/merged_board_gate.tcl',
          'scripts/test_merged_board_gate.tcl', 'scripts/s4_mesh_split.tcl', 'synth/s4/noc_mesh_3x2_bb.sv',
          'synth/riscv/b7_cpu_tile_noc_ooc.tcl', 'synth/riscv/a9_cpu_tile_noc_impl.tcl']:
    add('scripts', f, False)
for f in ['docs/decisions/M-F1-rev8-INTEGRATION-DRAFT.md', 'docs/proposals/RISCV_TAKEOVER_PLAN_20261106.md',
          'docs/handoff/RISCV_LANE_QUESTIONNAIRE_20261107.md', 'docs/handoff/RISCV_LANE_A1_RESPONSE_20261107.md',
          'docs/riscv_lane/CPU_TILE_NOC_README.md', 'docs/handoff/BRIEF_RISCV_LANE_v2_20261101.md', 'docs/DECISION_REGISTER.md']:
    add('docs', f, False)

seen = set()
for a, _ in entries:
    if a in seen: raise SystemExit(f'duplicate entry {a}')
    seen.add(a)
sums = [f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {a}' for a, p in entries]
readme = (ROOT / 'docs/handoff/TEAM_PACKAGE_README_20261107.md').read_bytes()
OUT.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('README.md', readme)
    for a, p in entries: z.write(p, a)
    z.writestr('SHA256SUMS.txt', '\n'.join(sums) + '\n')
h = hashlib.sha256(OUT.read_bytes()).hexdigest()
print(f'{OUT.relative_to(ROOT).as_posix()}: {len(entries) + 2} files, {OUT.stat().st_size / 1e6:.1f} MB, sha256 {h}')
