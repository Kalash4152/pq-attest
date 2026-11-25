"""Prepare, but never run/register, isolated N-8.1 P7 diagnostic builds.

Use a new directory outside the repository. Run compile.bat, elaborate.bat,
then simulate.bat sequentially in that directory with a real console.
LONG fixtures deliberately change only their COPIED packages, never P7 RTL.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
S = 'NOC_PQATTEST.srcs/sources_1/new/'
BENCH = 'NOC_PQATTEST.srcs/sim_1/new/tb_noc_n81_p7.sv'
SOURCES = ['rtl/dual_lane/NOC_PKG.sv', 'rtl/dual_lane/noc_p7_pkg.sv'] + [S + f for f in (
    'NOC_FIFO.sv', 'NOC_CROSSBAR.sv', 'NOC_XY_ROUTING.sv', 'NOC_arbiter.sv', 'allocator.sv',
    'noc_credit_counter.sv', 'NOC_DATAPTAH.sv', 'noc_router.sv', 'noc_mesh_3x2.sv', 'noc_addr_decoder.sv'
)] + ['rtl/dual_lane/noc_network_interface_p7.sv', BENCH]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--mode', choices=['default', 'n0', 'long', 'long_n0'], required=True)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--vivado', type=Path, default=Path('C:/xilinx_vivado/Vivado/2024.1'))
    args = ap.parse_args()
    out = args.out.resolve()
    if out == ROOT or out.is_relative_to(ROOT):
        ap.error('--out must be outside the live repository')
    out.mkdir(parents=True, exist_ok=False)
    long_packet = args.mode.startswith('long')
    wd = int(args.mode not in ('n0', 'long_n0'))
    original = {}
    for rel in SOURCES:
        dst = out / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        original[rel] = hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()
        shutil.copy2(ROOT / rel, dst)
    (out / 'scratch_defines.svh').write_text(
        f'`define N81_WDE {wd}\n' + ('`define N81P7_LONG\n' if long_packet else ''), encoding='utf-8')
    bench = out / BENCH
    bench.write_text('`include "scratch_defines.svh"\n' + bench.read_text(encoding='utf-8'), encoding='utf-8')
    if long_packet:
        pkg = out / SOURCES[0]
        text = pkg.read_text(encoding='utf-8')
        anchor = "MSG_MEM_WR_REQ:       return 5'd2;"
        if text.count(anchor) != 1:
            raise RuntimeError('counterfactual payload anchor changed')
        pkg.write_text(text.replace(anchor, "MSG_MEM_WR_REQ:       return 5'd16; // COUNTERFACTUAL ONLY"), encoding='utf-8')
        profile = out / SOURCES[1]
        text = profile.read_text(encoding='utf-8')
        if text.count('p7_packet_bound_check_t') != 2:
            raise RuntimeError('counterfactual elaboration-guard anchors changed')
        profile.write_text('\n'.join(line for line in text.splitlines()
                                     if 'p7_packet_bound_check_t' not in line) + '\n', encoding='utf-8')
    glbl = args.vivado / 'data/verilog/src/glbl.v'
    (out / 'sources.prj').write_text(
        f'sv xil_defaultlib -i "{out.as_posix()}" ' +
        ' '.join(f'"{(out / rel).as_posix()}"' for rel in SOURCES) +
        f'\nverilog xil_defaultlib "{glbl.as_posix()}"\nnosort\n', encoding='utf-8')
    commands = {
        'compile': 'xvlog --relax -d PQ_MAC_ON -prj sources.prj -log xvlog.log',
        'elaborate': ('xelab --incr --relax --debug typical --mt 2 -L xil_defaultlib -L unisims_ver '
                      '-L unimacro_ver -L secureip --snapshot n81 xil_defaultlib.tb_noc_n81_p7 '
                      'xil_defaultlib.glbl -log xelab.log'),
        'simulate': 'xsim n81 -tclbatch sim.tcl -log simulate.log',
    }
    for name, command in commands.items():
        tool, rest = command.split(' ', 1)
        (out / (name + '.bat')).write_text(
            f'@echo off\ncall "{(args.vivado / "bin" / (tool + ".bat")).as_posix()}" {rest}\n'
            'exit /b %errorlevel%\n', encoding='utf-8')
    (out / 'sim.tcl').write_text('run 100us\nquit\n', encoding='utf-8')
    manifest = dict(mode=args.mode, registered=False, counterfactual=long_packet, wd_enable=wd,
                    expected_checks=20 if args.mode == 'default' else 2,
                    expected_errors=1 if args.mode == 'long_n0' else 0,
                    expected_result='FAIL' if args.mode == 'long_n0' else 'PASS',
                    original_sources=original,
                    fixture_sources={rel: hashlib.sha256((out / rel).read_bytes()).hexdigest() for rel in SOURCES},
                    generated_files={name: hashlib.sha256((out / name).read_bytes()).hexdigest() for name in (
                        'scratch_defines.svh', 'sources.prj', 'compile.bat', 'elaborate.bat', 'simulate.bat', 'sim.tcl')},
                    glbl=dict(path=str(glbl), sha256=hashlib.sha256(glbl.read_bytes()).hexdigest()))
    (out / 'fixture_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(out=str(out), mode=args.mode, registered=False)))


if __name__ == '__main__':
    main()
