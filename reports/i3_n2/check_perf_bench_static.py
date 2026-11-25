"""Pure-Python static checks of the generated tb_noc_perf.sv (NOT a compile; no simulator used).
- generated bench is up to date with its generator inputs
- begin/end, case/endcase, function/endfunction, task/endtask, fork/join, (), {} balance
  after stripping comments and strings
- the number of check(...) call sites per build path matches N2_COUNT_DERIVATION.md
Exit 0 and print STATIC_PERF_BENCH: PASS on success."""
import re,subprocess,sys
from pathlib import Path
R=Path(__file__).resolve().parents[2]
TB=R/'NOC_PQATTEST.srcs/sim_1/new/tb_noc_perf.sv'
def strip(t):
    return re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/',lambda m:'""' if m[0].startswith('"') else ' ',t)
def main():
    fails=[]
    p=subprocess.run([sys.executable,str(R/'scripts/prepare_perf_bench.py'),'--check'],capture_output=True,text=True)
    if p.returncode: fails.append('generated bench stale: '+p.stdout.strip())
    t=strip(TB.read_text())
    words=re.findall(r'\b(begin|end|case|endcase|function|endfunction|task|endtask|fork|join|join_any|join_none|module|endmodule)\b',t)
    for o,c in [('begin','end'),('case','endcase'),('function','endfunction'),('task','endtask'),('module','endmodule')]:
        if words.count(o)!=words.count(c): fails.append(f'{o}/{c} {words.count(o)}/{words.count(c)}')
    depth=0
    for w in words:
        if w=='begin':depth+=1
        if w=='end':depth-=1
        if depth<0: fails.append('end before begin');break
    for o,c in ['()','{}','[]']:
        if t.count(o)!=t.count(c): fails.append(f'{o}{c} {t.count(o)}/{t.count(c)}')
    body=strip((R/'scripts/perf_bench_body.sv.inc').read_text())
    # check() call sites: point task 14, reset phase A 4, SAT 3, SC 5, global CFG 1.
    def sites(region):return len(re.findall(r'\bcheck\(',region))
    point=body[body.index('task automatic run_point'):body.index('endtask',body.index('task automatic run_point'))]
    reset=body[body.index('task automatic reset_phase_a'):body.index('endtask',body.index('task automatic reset_phase_a'))]
    sat=body[body.index('BUILD_N75_SAT_VC2: begin'):body.index('BUILD_N75_RESET: begin')]
    sc=body[body.index('BUILD_N75_SECOND_CHALLENGE: begin',body.index('initial begin')):body.index('default: for(int pat')]
    init=body[body.index('initial begin'):body.index('case(BUILD)',body.index('initial begin'))]
    got=dict(point=sites(point),reset=sites(reset),sat=sites(sat),sc=sites(sc),global_=sites(init),total=sites(body)-1)  # -1: task definition
    want=dict(point=14,reset=4,sat=3,sc=5,global_=1,total=27)
    if got!=want: fails.append(f'check() sites {got} != {want}')
    # No check() inside loops other than the per-point task: run_point is called 28x (perf) or 1x.
    for f in fails: print('FAIL',f)
    print('STATIC_PERF_BENCH:','FAIL' if fails else 'PASS',got)
    return 1 if fails else 0
if __name__=='__main__':raise SystemExit(main())
