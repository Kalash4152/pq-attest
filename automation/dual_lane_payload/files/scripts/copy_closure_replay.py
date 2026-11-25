"""Copy declared inputs into a new directory, without prior run records or build products."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import merged_release
from package_pre_gds_release import TEXT

def main():
    ap=argparse.ArgumentParser();ap.add_argument('destination',type=Path);a=ap.parse_args();dest=a.destination.resolve()
    if dest.exists():raise ValueError('replay destination must be new')
    files=set(ROOT/p for p in merged_release.expected_source_paths())
    reg=json.loads((ROOT/'scripts/dual_lane_jobs.json').read_text())
    for j in reg['jobs']:
        files.update(ROOT/p for p in j.get('sources',[])+j.get('oracle_files',[]))
        files.update(ROOT/j[k] for k in ('script','child_script','gate_script','constraints') if j.get(k))
    baseline=json.loads((ROOT/'automation/dual_lane_payload/baseline_before.json').read_text())
    files.update(ROOT/p for p in baseline['files'] if (ROOT/p).is_file())
    for folder in ('scripts','rtl/riscv','rtl/dual_lane','sim_riscv','vectors','sw/riscv','docs/decisions','software/pq_attest_final','automation/dual_lane_payload'):
        files.update(p for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in TEXT and '__pycache__' not in p.parts)
    files.add(ROOT/'Pq_Attest_final.zip');files.add(ROOT/'AGENTS.md')
    # The harness installs every payload entry before a run: copy the whole payload whatever the suffix
    # (I-26 first attempt d279fe2b refused: .gitattributes / .sv.inc payload files were filtered out by the TEXT rule).
    files.update(p for p in (ROOT/'automation/dual_lane_payload').rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    entries={}
    for p in sorted(files):
        rel=p.resolve().relative_to(ROOT)
        if rel.parts[:1]==('reports',) and any(part.startswith('dual_lane_10_') for part in rel.parts):continue
        if p.name=='install_journal.json':continue
        if not p.is_file():raise ValueError('missing replay input '+str(rel))
        target=dest/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,target)
        h=hashlib.sha256(p.read_bytes()).hexdigest()
        if hashlib.sha256(target.read_bytes()).hexdigest()!=h:raise ValueError('copy hash mismatch '+str(rel))
        entries[rel.as_posix()]=h
    (dest/'REPLAY_INPUT_MANIFEST.json').write_text(json.dumps(entries,indent=2)+'\n')
    if list((dest/'reports').glob('dual_lane_10_*/status.json')):raise ValueError('prior run records leaked into replay')
    print('CLEAN_REPLAY_INPUTS: PASS files='+str(len(entries)))

if __name__=='__main__':main()
