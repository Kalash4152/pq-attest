"""Create a path-preserving local release with a verified ZIP manifest."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile
import merged_release

ROOT=Path(__file__).resolve().parents[1]
TEXT={'.py','.sv','.v','.svh','.vh','.tcl','.xdc','.hex','.mem','.json','.md','.txt','.rpt','.csv','.tsv','.prj','.bat','.cmd','.ps1','.sh','.log','.S'}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--i24',type=Path,required=True)
    ap.add_argument('--i25',type=Path,required=True);ap.add_argument('--replay',type=Path,required=True)
    ap.add_argument('--report',type=Path,required=True);a=ap.parse_args()
    release=json.loads((merged_release.OUT/'release_result.json').read_text());merged_release.validate(release,merged_release.OUT)
    for run in (a.i24,a.i25,a.replay):
        status=json.loads((run/'status.json').read_text())
        if status['increment_status']!='PASS':raise ValueError('unaccepted increment '+str(run))
    if not a.report.is_file():raise ValueError('final Word report missing')
    files=set(ROOT/p for p in merged_release.expected_source_paths())
    registry=json.loads((ROOT/'scripts/dual_lane_jobs.json').read_text())
    for job in registry['jobs']:
        files.update(ROOT/p for p in job.get('sources',[])+job.get('oracle_files',[]))
        files.update(ROOT/job[k] for k in ('script','child_script','gate_script','constraints') if job.get(k))
    baseline=json.loads((ROOT/'automation/dual_lane_payload/baseline_before.json').read_text())
    files.update(ROOT/p for p in baseline['files'] if (ROOT/p).is_file())
    files.add(ROOT/'Pq_Attest_final.zip')
    for folder in ('scripts','rtl/riscv','rtl/dual_lane','sim_riscv','vectors','sw/riscv','docs/decisions','docs/riscv_lane','software/pq_attest_final','automation/dual_lane_payload'):
        files.update(p for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in TEXT and '__pycache__' not in p.parts)
    files.update(p for p in (ROOT/'reports').glob('*GATE*.md'))
    files.update(ROOT/p for p in ('AGENTS.md','docs/DECISION_REGISTER.md','docs/STATUS.md','reports/NEXT_STEP.md',
                                 'reports/PRE_GDS_EXECUTION_20261108.md','reports/PRE_GDS_REQUIREMENT_MATRIX_20261108.md'))
    for run in (a.i24,a.i25,a.replay):
        files.update(p for p in run.rglob('*') if p.is_file() and p.suffix in TEXT and not any(x in p.parts for x in ('snapshot','xsim.dir','.Xil')))
    files.update(p for p in merged_release.OUT.iterdir() if p.is_file() and p.suffix in TEXT|{'.bit'})
    files.add(a.report.resolve())
    missing=[str(p) for p in files if not p.is_file()]
    if missing:raise ValueError('release files missing '+str(missing))
    entries={}
    for p in sorted(files):
        rel=p.resolve().relative_to(ROOT).as_posix()
        entries[rel]=dict(size=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
    metadata=dict(commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),files=entries,
                  profile=9,hardware_validated=False,formal_proof=False,
                  source_runs=[a.i24.name,a.i25.name,a.replay.name],release_bitstream_sha256=release['bitstream_sha256'])
    a.out.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(a.out,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for rel in entries:z.write(ROOT/rel,rel)
        z.writestr('RELEASE_MANIFEST.json',json.dumps(metadata,indent=2)+'\n')
        z.writestr('SHA256SUMS.txt',''.join(v['sha256']+'  '+p+'\n' for p,v in entries.items()))
    with zipfile.ZipFile(a.out) as z:
        if z.testzip() is not None:raise ValueError('ZIP integrity failure')
        for rel,meta in entries.items():
            if hashlib.sha256(z.read(rel)).hexdigest()!=meta['sha256']:raise ValueError('archive hash mismatch '+rel)
    print(f'PRE_GDS_PACKAGE: PASS files={len(entries)} zip_sha256={hashlib.sha256(a.out.read_bytes()).hexdigest()}')

if __name__=='__main__':main()
