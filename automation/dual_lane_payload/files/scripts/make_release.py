"""DUAL_LANE_10 release manifest (docs/decisions/I8_RELEASE_PLAN.md sec. 4). Text only.

usage: python scripts/make_release.py <release_id> <run_dir> [<run_dir> ...]
Reads the registry (I-8 increment), the given evidence runs (result.json per job) and writes
releases/DUAL_LANE_10_<release_id>/{manifest.json, MANIFEST.md}: commit, release sources with SHA-256, every I-8 job with
its run and state, gate reports, decisions in force, status line. Refuses to write if any I-8 job lacks a PASS record.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PASS = ('PASS_FRESH', 'PASS_REUSED')


def sha(p):
    return hashlib.sha256((ROOT / p).read_bytes()).hexdigest()


def main():
    rid, runs = sys.argv[1], sys.argv[2:]
    reg = json.loads((ROOT / 'scripts/dual_lane_jobs.json').read_text())
    by = {j['id']: j for j in reg['jobs']}
    ids = reg['increments']['I-8']
    rec = {}
    for r in runs:
        for f in (ROOT / 'reports' / r).glob('*/result.json'):
            d = json.loads(f.read_text())
            if f.parent.name in ids and d.get('state') in PASS:
                rec[f.parent.name] = dict(run=r, state=d['state'], identity=d.get('identity'))
    missing = [i for i in ids if i not in rec]
    if missing:
        sys.exit('RELEASE: FAIL no PASS record for ' + ', '.join(missing))
    srcs = sorted({s for i in ids for s in by[i].get('sources', []) + by[i].get('oracle_files', [])})
    commit = subprocess.run(['git', 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True, cwd=ROOT).stdout.strip()
    gates = sorted(str(p.relative_to(ROOT)).replace('\\', '/') for p in (ROOT / 'reports').glob('*_GATE_*.md'))
    m = dict(release=f'DUAL_LANE_10_{rid}', commit=commit, active_increment=reg['active_increment'],
             jobs={i: rec[i] for i in ids}, sources={s: sha(s) for s in srcs}, gate_reports=gates,
             decisions=['docs/DECISION_REGISTER.md', 'docs/decisions/I6_CONTRACT.md', 'docs/decisions/I7_SEC_MATRIX.md',
                        'docs/decisions/I8_RELEASE_PLAN.md', 'docs/decisions/M-F1-interface-freeze.md'],
             status=dict(HARDWARE_VALIDATED='NO', SOC_INTEGRATION_COMPLETE='NO', FORMAL_PROOF='NO'),
             nonce_source='deterministic demo issuer (no TRNG claim)', provisioning='OFFLINE DEMO ONLY')
    out = ROOT / 'releases' / m['release']
    out.mkdir(parents=True, exist_ok=True)
    (out / 'manifest.json').write_text(json.dumps(m, indent=2) + '\n', encoding='utf-8', newline='\n')
    L = [f"# {m['release']}", '', f"- Commit: {commit}", f"- Jobs: {len(ids)} (I-8), all PASS",
         f"- Runs: {', '.join(sorted(set(r['run'] for r in rec.values())))}",
         '- Status: HARDWARE_VALIDATED=NO, SOC_INTEGRATION_COMPLETE=NO, FORMAL_PROOF=NO',
         '- Nonce source: deterministic demo issuer (no TRNG claim); provisioning: OFFLINE DEMO ONLY', '',
         '## Gate reports', ''] + [f'- {g}' for g in gates] + ['', '## Sources (SHA-256)', '', '| File | SHA-256 |', '|---|---|'] + \
        [f'| {s} | {h} |' for s, h in m['sources'].items()] + ['', '## Jobs', '', '| Job | Run | State |', '|---|---|---|'] + \
        [f"| {i} | {rec[i]['run']} | {rec[i]['state']} |" for i in ids]
    (out / 'MANIFEST.md').write_text('\n'.join(L) + '\n', encoding='utf-8', newline='\n')
    print(f"RELEASE: PASS {m['release']} jobs={len(ids)} sources={len(srcs)}")


if __name__ == '__main__':
    main()
