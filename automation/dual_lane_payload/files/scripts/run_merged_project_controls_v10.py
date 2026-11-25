"""Run the isolated Vivado project-update test without touching the main XPR."""
import argparse
from pathlib import Path
import re
from seed_campaign import run

ROOT=Path(__file__).resolve().parents[1]

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve()
    run(['C:/xilinx_vivado/Vivado/2024.1/bin/vivado.bat','-mode','batch','-nojournal','-log',str(out/'project_vivado.log'),
         '-source',str(ROOT/'scripts/test_merged_project_update_v10.tcl'),'-tclargs',str(ROOT),str(out)],
        out,out/'project_stdout.txt',300)
    s=(out/'project_update_result.txt').read_text()
    if not re.fullmatch(r'MERGED_PROJECT_COPY: PASS source_and_firmware_files=72 idempotent=YES\s*',s):
        raise ValueError('combined project source count/update test failed')
    print('MERGED_PROJECT_CONTROLS: PASS files=72 idempotent=YES')

if __name__=='__main__':main()
