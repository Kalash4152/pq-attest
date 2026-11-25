"""Read-only release-profile checks with one negative control per guarded condition."""
from pathlib import Path
import re
import gen_closure_profile_v10 as g
import make_merged_sources as sources

ROOT=Path(__file__).resolve().parents[1]

def literal(text,name):
    m=re.search(r'\b'+name+r"\s*=\s*\d+'h([0-9a-fA-F_]+)",text)
    return None if m is None else int(m[1].replace('_',''),16)

def check(board,profile,core,decoder,srcs,mem_init,image):
    results={}
    for name,ref in [('CONFIG_DATA','CLOSURE_CONFIG'),('CPU_A_IMAGE','CLOSURE_IMEM'),('APPROVED_MEAS','CLOSURE_MEAS')]:
        results[name]=literal(board,name) is not None and literal(board,name)==literal(profile,ref)
    b=re.search(r"\.CPU_BUILD_ID\(32'h([0-9a-fA-F_]+)\)",board)
    results['BUILD']=b is not None and int(b[1].replace('_',''),16)==literal(profile,'CLOSURE_BUILD_ID')
    results['FIRMWARE']=bool(re.search(r'CPU_FW\s*=\s*"demo_fw_v3.hex"',board))
    results['WHOLE']=bool(re.search(r"\.WHOLE_IMEM_MEASUREMENT\(1'b1\)",board))
    for inst,name,want in [('u_cpu_a','CPU_A','WHOLE_IMEM_MEASUREMENT'),('u_cpu_b','CPU_B',"1'b0")]:
        m=re.search(r'`CPU_TILE_MODULE\s*#\((.*?)\)\s*'+inst+r'\b',core,re.S)
        results[name]=m is not None and bool(re.search(r'\.WHOLE_IMEM_MEASUREMENT\('+re.escape(want)+r'\)',m[1]))
    results['FETCH']=bool(re.search(r'if\s*\(local_is_fetch_i\s*&&\s*!is_imem\)',decoder))
    words=[s.strip() for s in image.splitlines() if s.strip() and not s.lstrip().startswith('@')]
    results['SOURCES_AND_MEMORY']=(srcs.count('rtl/riscv/meas_imem_hasher.sv')==1 and
        mem_init==['sw/riscv/demo_fw_v3.hex'] and len(words)==4096 and
        all(re.fullmatch('[0-9a-fA-F]{8}',s) for s in words))
    if not all(results.values()):raise ValueError('profile-10 policy failed: '+','.join(k for k,v in results.items() if not v))
    return results

def main():
    board=(ROOT/'synth/merged/pq_merged_board_top.sv').read_text()
    profile=(ROOT/'sw/riscv/closure_profile_v10.svh').read_text()
    core=(ROOT/'rtl/dual_lane/merged/pq_soc_merged_core.sv').read_text()
    decoder=(ROOT/'rtl/riscv/addr_decode.sv').read_text()
    srcs,_=sources.build();mem=list(sources.MEM_INIT_FILES)
    image=(ROOT/'sw/riscv/demo_fw_v3.hex').read_text()
    args=[board,profile,core,decoder,srcs,mem,image]
    assert len(check(*args))==10
    cases=[]
    for old,new in [('CONFIG_DATA','CONFIG_WRONG'),('CPU_A_IMAGE','IMEM_WRONG'),('APPROVED_MEAS','MEAS_WRONG'),
                    ('CPU_BUILD_ID','BUILD_WRONG'),('demo_fw_v3.hex','demo_fw_v2.hex'),
                    (".WHOLE_IMEM_MEASUREMENT(1'b1)",".WHOLE_IMEM_MEASUREMENT(1'b0)")]:
        cases.append((0,board.replace(old,new),old))
    cases +=[(2,core.replace('.WHOLE_IMEM_MEASUREMENT(WHOLE_IMEM_MEASUREMENT)',".WHOLE_IMEM_MEASUREMENT(1'b0)"),'CPU_A'),
        (2,core.replace(".WHOLE_IMEM_MEASUREMENT(1'b0)",".WHOLE_IMEM_MEASUREMENT(1'b1)"),'CPU_B'),
        (3,decoder.replace('local_is_fetch_i && !is_imem',"1'b0"),'FETCH'),
        (4,[s for s in srcs if not s.endswith('meas_imem_hasher.sv')],'SOURCE'),
        (6,'\n'.join(image.splitlines()[:-1]),'SHORT_IMAGE')]
    for i,value,label in cases:
        bad=list(args);bad[i]=value
        try:check(*bad)
        except ValueError:pass
        else:raise AssertionError('profile-10 negative control survived '+label)
    assert len(cases)==11
    print('MERGED_BOARD_PROFILE_V10: PASS conditions=10 negative_controls=11')

if __name__=='__main__':main()
