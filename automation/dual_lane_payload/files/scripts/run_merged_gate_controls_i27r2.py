"""Run six routed-design acceptance controls in a separate Vivado process."""
import argparse
import json
from pathlib import Path
import re
from seed_campaign import run

ROOT=Path(__file__).resolve().parents[1]

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve()
    rec=json.loads((out.parent/'i27r2_board_secure/result.json').read_text())
    if rec['state'] not in ('PASS_FRESH','PASS_REUSED'):raise ValueError('unaccepted routed dependency')
    dcp=out.parent.parent/rec['fresh_run']/'i27r2_board_secure/routed.dcp'
    if not dcp.is_file():raise ValueError('accepted checkpoint missing')
    run(['C:/xilinx_vivado/Vivado/2024.1/bin/vivado.bat','-mode','batch','-nojournal','-log',str(out/'controls_vivado.log'),
         '-source',str(ROOT/'scripts/test_merged_board_gate.tcl'),'-tclargs',str(dcp),str(out/'cases')],
        out,out/'controls_stdout.txt',1600)
    s=(out/'cases/negative_tests.txt').read_text()
    if re.findall(r'^GATE_NEGATIVE_TESTS: (.*)$',s,re.M)!=['PASS (6/6)']:raise ValueError('routed gate controls did not pass')
    if len(re.findall(r'^NEG .* OK$',s,re.M))!=6:raise ValueError('missing control results')
    if re.findall(r'^IDENTITY_CONTROL wrong_top verdict=(\S+) (\S+)$',s,re.M)!=[('FAIL','OK')]:raise ValueError('wrong-top identity control did not fail as required')
    print('MERGED_GATE_CONTROLS: PASS cases=6')

if __name__=='__main__':main()
