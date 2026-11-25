"""Registered phase-0 code-coverage measurement using XSim, no coverage target.

2024.1 refuses code coverage in standalone mode (XSIM 43-5031); use its front end.
"""
import argparse
import csv
import hashlib
import html
import json
import os
from pathlib import Path
import re
import subprocess

from seed_campaign import BIN, run, system_awake, judge_version
from dual_lane_verify import judge

ROOT=Path(__file__).resolve().parents[1]

def module_scores(text):
    rows=[]
    for tr in re.findall(r'<tr\b[^>]*>(.*?)</tr>',text,re.S|re.I):
        cells=[html.unescape(re.sub(r'<[^>]*>','',c)).strip()
               for c in re.findall(r'<td\b[^>]*>(.*?)</td>',tr,re.S|re.I)]
        if len(cells)==10 and cells[0].isdigit():
            rows.append(dict(module=cells[1],instances=cells[2],hierarchy=cells[3],
                statement_percent=cells[4],branch_percent=cells[5],condition_percent=cells[6],
                toggle_percent=cells[7],source=cells[8]))
    if not rows:raise RuntimeError('no module scores in coverage report')
    return rows

def checked_log(path):
    text=path.read_text(errors='replace')
    if not text.strip():raise RuntimeError('empty tool log '+str(path))
    if re.search(r'^\s*(ERROR:|FATAL:)|Code Coverage Options cannot be used',text,re.M|re.I):
        raise RuntimeError('tool diagnostic in '+str(path))
    return text

def measure(job,out):
    work=out/job['top'];work.mkdir(parents=True,exist_ok=False)
    manifest={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest()
              for p in job['sources']+job.get('oracle_files',[])}
    (work/'input_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    for p in (ROOT/'sw/riscv').glob('*.hex'):
        (work/p.name).write_bytes(p.read_bytes())
    (work/'compile.prj').write_text(''.join(
        ('verilog' if p.endswith('.v') else 'sv')+' xil_defaultlib "'+(ROOT/p).as_posix()+'"\n'
        for p in job['sources']))
    opts=[]
    for d in job.get('defines',[]):opts+=['-d',d]
    for d in job.get('include_dirs',[]):opts+=['-i',str(ROOT/d)]
    run([BIN/'xvlog.bat','--relax','-prj',work/'compile.prj',*opts],work,work/'compile.log',1200)
    checked_log(work/'compile.log')
    run([BIN/'xelab.bat','--relax','--mt','2','--debug','typical',
         '--cc_type','sbct','--cov_db_dir',str(work/'coverage'),'--cov_db_name','measured',
         'xil_defaultlib.'+job['top'],'-s','measured'],work,work/'elaborate.log',1800)
    checked_log(work/'elaborate.log')
    (work/'run.tcl').write_text('run all\nquit\n')
    run([BIN/'xsim.bat','measured','-tclbatch',work/'run.tcl','-log',work/'simulate.log'],
        work,work/'simulate_process.log',3600)
    after={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in manifest}
    result=judge((work/'simulate.log').read_text(errors='replace'),job,
        {s:dict(exitCode=0,timedOut=False,interrupted=False) for s in ['compile','elaborate','simulate']},manifest,after)
    run([BIN/'xcrg.bat','-cov_db_dir',str(work/'coverage'),'-cov_db_name','measured',
         '-report_dir',str(work/'coverage_report'),'-report_format','all'],work,work/'coverage_report.log',300)
    checked_log(work/'coverage_report.log')
    reports=[p.relative_to(work).as_posix() for p in (work/'coverage_report').rglob('*') if p.is_file()]
    if not reports:raise RuntimeError('coverage report is empty')
    scores=module_scores((work/'coverage_report/codeCoverageReport/modules.html').read_text(errors='replace'))
    with (work/'module_coverage.csv').open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=list(scores[0]));w.writeheader();w.writerows(scores)
    unexercised=[r for r in scores if r['statement_percent']=='0']
    (work/'unexercised_modules.json').write_text(json.dumps(unexercised,indent=2)+'\n')
    return dict(top=job['top'],checks=job['checks'],result=result,reports=reports,
        module_count=len(scores),unexercised_modules=unexercised)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args()
    out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
    reg=json.loads((ROOT/'scripts/dual_lane_jobs.json').read_text())
    rows=[]
    with system_awake():
        run([BIN/'xvlog.bat','-version'],out,out/'version.txt',30)
        judge_version((out/'version.txt').read_text(errors='replace'))
        for jid in ['i21_merged_closure','i23_inflight','i23_contention']:
            print('COVERAGE_START '+jid,flush=True)
            rows.append(measure(next(j for j in reg['jobs'] if j['id']==jid),out))
            (out/'measurement.json').write_text(json.dumps(rows,indent=2)+'\n')
    print('R10_COVERAGE: PASS benches=3 target=measurement_only',flush=True)

if __name__=='__main__':main()
