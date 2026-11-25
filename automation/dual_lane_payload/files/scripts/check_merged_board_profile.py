"""Read-only consistency checks for the actual board wrapper's qualified revision-9 profile."""
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]

def check(board,profile):
    pairs=[('CONFIG_DATA','CLOSURE_CONFIG'),('CPU_A_IMAGE','CLOSURE_IMEM'),('APPROVED_MEAS','CLOSURE_MEAS')]
    for name,reference in pairs:
        want=re.search(r'\b'+reference+r"\s*=\s*\d+'h([0-9a-fA-F_]+)",profile)
        got=re.search(r'\b'+name+r"\s*=\s*\d+'h([0-9a-fA-F_]+)",board)
        if not want or not got or int(want[1].replace('_',''),16)!=int(got[1].replace('_',''),16):
            raise ValueError('board/profile mismatch '+name)
    build=re.search(r"CLOSURE_BUILD_ID\s*=\s*32'h([0-9a-fA-F_]+)",profile)
    use=re.search(r"\.CPU_BUILD_ID\(32'h([0-9a-fA-F_]+)\)",board)
    if not build or not use or int(build[1].replace('_',''),16)!=int(use[1].replace('_',''),16):raise ValueError('board build identity mismatch')
    if not re.search(r'CPU_FW\s*=\s*"demo_fw_v2.hex"',board):raise ValueError('wrong board firmware filename')

def main():
    board=(ROOT/'synth/merged/pq_merged_board_top.sv').read_text();profile=(ROOT/'sw/riscv/closure_profile.svh').read_text()
    check(board,profile)
    mutations=[('CONFIG_DATA','CONFIG_WRONG'),('CPU_A_IMAGE','IMEM_WRONG'),('APPROVED_MEAS','MEAS_WRONG'),
               ('CPU_BUILD_ID','BUILD_WRONG'),('demo_fw_v2.hex','demo_fw.hex')]
    for old,new in mutations:
        try:check(board.replace(old,new),profile)
        except ValueError:pass
        else:raise AssertionError('board profile control not caught '+old)
    print('MERGED_BOARD_PROFILE: PASS conditions=5 negative_controls=5')

if __name__=='__main__':main()
