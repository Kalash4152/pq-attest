"""Save a stopped working-tree checkpoint; never launch Vivado or simulation."""
import ast
import json
from pathlib import Path
import subprocess
import sys

from dual_lane import ROOT, atomic, install, now
from dual_lane_verify import artifacts_valid, sha
from prepare_dual_lane import main as prepare


def main():
    payload = ROOT / 'automation/dual_lane_payload'
    if (ROOT / 'automation/dual_lane.lock').exists():
        raise RuntimeError('Inspect active/interrupted scheduler before checkpointing')
    logs = payload / 'checkpoint_checks'
    logs.mkdir(exist_ok=True)
    checks = {}
    # These are software/oracle checks only, with immutable vector verification.
    for name, script in [('automation', 'test_dual_lane.py'),
                         ('s8_oracle', 's8_golden.py'),
                         ('chain_oracle', 'full_chain_golden.py'),
                         ('l2_oracle', 'l2_golden.py')]:
        result = subprocess.run([sys.executable, str(ROOT / 'scripts' / script)],
                                capture_output=True, text=True, timeout=60, cwd=ROOT)
        log = logs / (name + '.log')
        atomic(log, result.stdout + result.stderr)
        checks[name] = dict(exit_code=result.returncode, log=str(log.relative_to(ROOT)),
                            sha256=sha(log))
        print(f'{name}: exit {result.returncode}', flush=True)
    syntax = []
    for script in (ROOT / 'scripts').glob('*.py'):
        ast.parse(script.read_text(encoding='utf-8-sig'), filename=str(script))
        syntax.append(script.name)
    checks['python_syntax'] = dict(state='PASS', files=syntax)
    import tkinter
    interp = tkinter.Tcl()
    tcls = ['dual_lane_common.tcl', 'dual_lane_export.tcl',
            'run_dual_lane_10.tcl', 'd4_crypto_ooc.tcl']
    for name in tcls:
        if interp.call('info', 'complete', (ROOT / 'scripts' / name).read_text()) != 1:
            raise RuntimeError('Incomplete Tcl source: ' + name)
    # Define bootstrap procedures only; do not invoke dual_lane::run.
    interp.call('source', str(ROOT / 'scripts/dual_lane_common.tcl'))
    checks['tcl_structure'] = dict(state='PASS', files=tcls,
                                   scope='structure/bootstrap loading; no Vivado execution')
    prepare()
    rows = install(ROOT, payload / 'update_manifest.json', dry=True)
    checks['payload_preflight'] = dict(state='PASS', files=len(rows),
                                       already_installed=sum(r['state'] == 'ALREADY_INSTALLED' for r in rows))
    baseline = json.loads((payload / 'baseline_before.json').read_text())
    changes = {rel: dict(before=h, after=sha(ROOT / rel) if (ROOT / rel).is_file() else None)
               for rel, h in baseline['files'].items()
               if not (ROOT / rel).is_file() or sha(ROOT / rel) != h}
    latest = json.loads((ROOT / 'reports/dual_lane_latest.json').read_text())
    evidence = ROOT / latest['evidence_dir']
    status = json.loads((evidence / 'status.json').read_text())
    chain = status['jobs']['full_chain']
    checks['chain_artifact_integrity'] = dict(state='PASS' if artifacts_valid(chain) else 'INVALID',
                                             scope='saved artifact hashes; no rerun')
    state = dict(schema=1, saved_utc=now(), work_state='STOPPED_AT_USER_REQUEST',
                 git_head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                 git_branch=subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip(),
                 git_status=subprocess.check_output(['git', 'status', '--porcelain=v1'], cwd=ROOT, text=True),
                 scheduler_lock_present=False, checks=checks,
                 intake_files=len(baseline['files']), intake_files_changed=changes,
                 update_manifest_sha256=sha(payload / 'update_manifest.json'),
                 saved_files={r['path']: sha(ROOT / r['path']) for r in rows},
                 latest_evidence=str(evidence.relative_to(ROOT)), overall_status=status['status'],
                 package_states={k: v['state'] for k, v in status['stages'].items()},
                 accepted_noc=0, accepted_pq=0, hardware_validated=False,
                 future_plan='docs/DUAL_LANE_CHECKPOINT_2026-10-08.md')
    # Derive totals rather than inferring acceptance from individual job results.
    for lane, field in [('NOC-', 'accepted_noc'), ('PQ-', 'accepted_pq')]:
        state[field] = sum(v['state'] in ('PASS_FRESH', 'PASS_REUSED')
                           for k, v in status['stages'].items() if k.startswith(lane))
    atomic(payload / 'checkpoint.json', state)
    print(f'CHECKPOINT_SAVED intake_changes={len(changes)} packages={state["accepted_noc"]}+{state["accepted_pq"]}', flush=True)
    return 0 if all(c.get('exit_code', 0) == 0 and c.get('state', 'PASS') == 'PASS'
                    for c in checks.values()) and not changes else 1


if __name__ == '__main__':
    sys.exit(main())
