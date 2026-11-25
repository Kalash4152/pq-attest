"""I-2 Track C: validate the proposed registry patch WITHOUT writing the registry.

What it does (no Vivado, no XSim, no write to scripts/dual_lane_jobs.json):
  1. Applies reports/i2_track_c/prepare_dual_lane.i2.patch to a temporary copy of
     scripts/prepare_dual_lane.py (pure-Python unified-diff applier, exact context).
  2. Imports the patched module from the temp dir and calls build_registry(check_files=False),
     i.e. the registry the patched prepare WOULD emit. main() is never called.
  3. Loads reports/i2_track_c/i2_jobs_patch.json, merges it in memory with the current
     scripts/dual_lane_jobs.json, and requires the merge == the patched-builder output.
  4. Requires every job not named by the patch to be byte-identical (JSON) to the current
     registry (the patched builder reproduces the I-1 registry).
  5. Runs dual_lane_preflight.source_names on every new/changed job, plus a negative
     self-test (production + variant NOC_PKG in one list must FAIL).
  6. Checks mutant anchors are unique in the patched file and that file is in the source list.
  7. Lists sources that do not exist yet (python scripts owed by other tracks).
Exit 0 only if every check passes (missing not-yet-written python sources are reported, not fatal).
"""
from __future__ import annotations
import copy
import importlib.util
import json
from pathlib import Path
import re
import shutil
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from dual_lane_preflight import source_names, PreflightFailure  # noqa: E402
import dual_lane  # noqa: E402

PATCH_JSON = HERE / 'i2_jobs_patch.json'
PREP_PATCH = HERE / 'prepare_dual_lane.i2.patch'
REGISTRY = ROOT / 'scripts/dual_lane_jobs.json'
PREPARE = ROOT / 'scripts/prepare_dual_lane.py'


def apply_unified(text: str, diff: str) -> str:
    """Apply a single-file unified diff; every context/removed line must match exactly."""
    src = text.splitlines(True)
    out, pos = [], 0
    lines = diff.splitlines(True)
    i = 0
    while i < len(lines) and not lines[i].startswith('@@'):
        i += 1
    while i < len(lines):
        m = re.match(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', lines[i])
        if not m:
            raise ValueError(f'bad hunk header: {lines[i]!r}')
        start = int(m[1]) - 1 if (m[2] or '1') != '0' else int(m[1])
        out += src[pos:start]; pos = start; i += 1
        while i < len(lines) and not lines[i].startswith('@@'):
            tag, body = lines[i][:1], lines[i][1:]
            if tag == ' ' or tag == '-':
                if pos >= len(src) or src[pos] != body:
                    raise ValueError(f'context mismatch at source line {pos + 1}')
                if tag == ' ':
                    out.append(body)
                pos += 1
            elif tag == '+':
                out.append(body)
            elif tag == '\\':
                pass
            else:
                raise ValueError(f'bad diff line {lines[i]!r}')
            i += 1
    out += src[pos:]
    return ''.join(out)


def patched_registry() -> dict:
    tmp = Path(tempfile.mkdtemp(prefix='i2_prep_'))
    try:
        patched = apply_unified(PREPARE.read_text(encoding='utf-8'), PREP_PATCH.read_text(encoding='utf-8'))
        (tmp / 'prepare_dual_lane_i2.py').write_text(patched, encoding='utf-8', newline='\n')
        spec = importlib.util.spec_from_file_location('prepare_dual_lane_i2', tmp / 'prepare_dual_lane_i2.py')
        mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
        reg = mod.build_registry(check_files=False)
        return json.loads(json.dumps(reg)), patched
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def merge(current: dict, patch: dict) -> dict:
    reg = copy.deepcopy(current)
    by_id = {j['id']: j for j in reg['jobs']}
    for jid in patch['jobs_remove']:
        reg['jobs'] = [j for j in reg['jobs'] if j['id'] != jid]
    for jid, job in patch['jobs_replace'].items():
        if jid not in by_id:
            raise ValueError(f'replace of unknown job {jid}')
        reg['jobs'] = [job if j['id'] == jid else j for j in reg['jobs']]
    order = patch['job_order']
    pool = {j['id']: j for j in reg['jobs']}
    for job in patch['jobs_add']:
        if job['id'] in pool:
            raise ValueError(f'add of existing job {job["id"]}')
        pool[job['id']] = job
    if sorted(order) != sorted(pool):
        raise ValueError('job_order does not cover exactly the merged job set')
    reg['jobs'] = [pool[i] for i in order]
    for k, v in patch['increments_add'].items():
        if k in reg['increments']:
            raise ValueError(f'increment {k} already exists')
        reg['increments'][k] = v
    for st in reg['stages']:
        if st['id'] in patch['stages_replace_jobs']:
            st['jobs'] = patch['stages_replace_jobs'][st['id']]
    if patch.get('active_increment', reg['active_increment']) != reg['active_increment']:
        raise ValueError('patch must not change active_increment')
    return reg


def main() -> int:
    fails = []
    def need(cond, msg):
        print(('PASS ' if cond else 'FAIL ') + msg)
        if not cond:
            fails.append(msg)

    current = json.loads(REGISTRY.read_text(encoding='utf-8'))
    before_bytes = REGISTRY.read_bytes()
    patch = json.loads(PATCH_JSON.read_text(encoding='utf-8'))
    built, patched_text = patched_registry()
    merged = merge(current, patch)

    need(merged == built, 'i2_jobs_patch.json merged into dual_lane_jobs.json == patched prepare build_registry() output')
    need(built['active_increment'] == 'I-1', 'active_increment unchanged (I-1)')
    need(built['increments']['I-1'] == current['increments']['I-1'], 'I-1 increment list unchanged')
    touched = set(patch['jobs_replace']) | {j['id'] for j in patch['jobs_add']} | set(patch['jobs_remove'])
    cur = {j['id']: j for j in current['jobs']}
    new = {j['id']: j for j in built['jobs']}
    untouched_same = all(new[i] == cur[i] for i in cur if i not in touched)
    need(untouched_same, f'{len([i for i in cur if i not in touched])} untouched jobs identical to current registry')
    i2 = built['increments']['I-2']
    need(len(i2) == len(set(i2)) and all(i in new for i in i2), f'I-2 list ({len(i2)} jobs) unique and defined')
    need('post_format_compat' not in new, 'post_format_compat blocker gate replaced by explicit pfc_* jobs')

    print('\n-- source_names preflight on new/changed jobs --')
    missing = []
    for jid in sorted(touched - set(patch['jobs_remove'])):
        job = new[jid]
        for p in job.get('sources', []) + job.get('oracle_files', []):
            if not (ROOT / p).is_file():
                missing.append((jid, p))
        try:
            r = source_names(ROOT, job)
            loc = next((v for k, v in r['declarations'].items() if k.lower() == 'package:noc_pkg'), 'not compiled')
            print(f'PASS {jid}: {len(r["declarations"])} declarations; NOC_PKG from {loc}')
        except PreflightFailure as e:
            print(f'FAIL {jid}: {e}'); fails.append(jid)
        both = {'NOC_PQATTEST.srcs/sources_1/new/NOC_PKG.sv', 'rtl/dual_lane/NOC_PKG.sv'} <= set(job.get('sources', []))
        if both:
            fails.append(jid + ' carries both NOC_PKG files'); print(f'FAIL {jid}: both NOC_PKG files')
        if jid.startswith('pfc_') and 'rtl/dual_lane/NOC_PKG.sv' not in job['sources']:
            fails.append(jid + ' lacks variant pkg'); print(f'FAIL {jid}: no variant NOC_PKG')

    print('\n-- negative self-test --')
    probe = copy.deepcopy(new['pfc_n81_nitb']); probe['sources'] = ['NOC_PQATTEST.srcs/sources_1/new/NOC_PKG.sv'] + probe['sources']
    try:
        source_names(ROOT, probe); need(False, 'production+variant NOC_PKG in one list rejected')
    except PreflightFailure as e:
        need('duplicate package:noc_pkg' in str(e).lower(), f'production+variant NOC_PKG in one list rejected ({e})')

    print('\n-- controller mutants --')
    prot = (ROOT / 'NOC_PQATTEST.srcs/sources_1/new/pq_attest_protocol.sv').read_text(encoding='utf-8')
    for jid in [i for i in i2 if i.startswith('s8_mut_')]:
        job = new[jid]
        in_src = sum(Path(p).name == 'pq_attest_protocol.sv' for p in job['sources']) == 1
        try:
            mutated = dual_lane.mutation(prot, job['mutant']); ok = mutated != prot
        except Exception as e:  # noqa: BLE001
            ok = False; print('   ', e)
        need(in_src and ok and bool(job.get('oracle')), f'{jid}: anchor unique, target file in sources, oracle {job.get("oracle")}')

    print('\n-- FREEZE_REQUIRED / blocked pfc jobs --')
    for jid in i2:
        j = new[jid]
        if j.get('checks') == 'FREEZE_REQUIRED':
            need(bool(j.get('unimplemented')), f'{jid}: FREEZE_REQUIRED and blocked before first run')

    print('\n-- sources not yet present (owed by other tracks) --')
    for jid, p in missing:
        print(f'MISSING {jid}: {p}')
    need(REGISTRY.read_bytes() == before_bytes, 'scripts/dual_lane_jobs.json not modified')
    print(f'\nVALIDATE_PATCH: {"PASS" if not fails else "FAIL"} ({len(fails)} failures; {len(missing)} missing-not-yet-written sources)')
    return 0 if not fails else 1


if __name__ == '__main__':
    sys.exit(main())
