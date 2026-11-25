"""DEBUG ONLY (not evidence): run tb_dsyn2_measurement_equiv with the B4 $assertoff/$asserton replaced by
time markers, assertions ON throughout, and list every assertion message with its time."""
import json, re, subprocess, shutil, sys
from pathlib import Path
ROOT = Path(r'C:\vivado_verilog_proj\NOC_PQATTEST'); VIV = Path(r'C:\xilinx_vivado\Vivado\2024.1\bin')
W = Path('C:/npqc_dbgb4'); shutil.rmtree(W, ignore_errors=True); W.mkdir()
job = next(j for j in json.loads((ROOT / 'scripts/dual_lane_jobs.json').read_text())['jobs'] if j['id'] == 'dsyn2_measurement_equiv')
tbrel = 'NOC_PQATTEST.srcs/sim_1/new/tb_dsyn2_measurement_equiv.sv'
t = (ROOT / tbrel).read_text()
assert t.count('    $assertoff;\n') == 1 and t.count('    $asserton;\n') == 1
t = t.replace('    $assertoff;\n', '    $display("B4_WINDOW_START t=%0t", $time);\n').replace('    $asserton;\n', '    $display("B4_WINDOW_END t=%0t", $time);\n')
(W / 'tb_dbg.sv').write_text(t)
srcs = [str(W / 'tb_dbg.sv') if s == tbrel else str(ROOT / s) for s in job['sources']]
(W / 'p.prj').write_text(''.join(f'sv xil_defaultlib "{Path(s).as_posix()}"\n' for s in srcs) + f'verilog xil_defaultlib "{(VIV.parent / "data/verilog/src/glbl.v").as_posix()}"\n')
def run(c, to):
    p = subprocess.Popen(c, cwd=W, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try: return p.communicate(timeout=to)[0]
    except subprocess.TimeoutExpired: subprocess.run(['taskkill', '/PID', str(p.pid), '/T', '/F']); return 'TIMEOUT'
cmd = [str(VIV / 'xvlog.bat'), '--relax', '-prj', 'p.prj', '-log', 'xvlog.log'] + sum((['-d', d] for d in job.get('defines', [])), []) + sum((['-i', str(ROOT / i)] for i in job.get('include_dirs', [])), [])
run(cmd, 900)
run([str(VIV / 'xelab.bat'), '--debug', 'typical', '--relax', '--mt', 'off', '-L', 'xil_defaultlib', '-L', 'unisims_ver', '--snapshot', 'h', 'xil_defaultlib.' + job['top'], 'xil_defaultlib.glbl', '-log', 'elab.log'], 900)
for a in range(2):
    out = run([str(VIV / 'xsim.bat'), 'h', '-R', '-log', f'sim_a{a}.log'], 600)
    if 'RESULT' in out: break
    print('launch attempt', a, 'no RESULT (stall?)')
(W / 'debug_stdout.txt').write_text(out)
for l in out.splitlines():
    if re.search(r'B4_WINDOW|Error|error|Assert|assert|^CHECKS|^ERRORS|^RESULT|TB_TIMEOUT|\[FAIL\]', l): print(l[:240])
