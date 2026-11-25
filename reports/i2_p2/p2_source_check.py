"""P2 static source-list check for the PQ-3 OOC jobs. No tool launch.

Usage: python reports/i2_p2/p2_source_check.py <repo_root> <out.json>

For each OOC job (a deep COPY of the registry entry; dual_lane_jobs.json is
only read) and for each proposed trimmed job:
  * dual_lane_preflight.source_names(): every file exists, every active
    module/package name is declared exactly once, the top is declared;
  * instantiation walk from the top: every instantiated module type is
    declared in the list (UNRESOLVED otherwise), plus the modules and
    packages the top never reaches (harmless extras);
  * package closure: every `pkg::` reference reachable from the top is a
    package declared in the list.
"""
import copy
import json
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(ROOT / 'scripts'))
from dual_lane_preflight import source_names  # noqa: E402

JOBS = ['ooc_pq_kdf', 'ooc_pq_measurement', 'ooc_pq_attestation_tag',
        'ooc_pq_attestation_controller', 'endpoint_ooc', 'ni_ooc']
KW = set('if for case casez casex assign always always_ff always_comb always_latch begin end '
         'function task return else while module input output inout logic wire reg unique '
         'priority generate genvar localparam parameter typedef int bit integer automatic '
         'foreach repeat forever fork initial final import export assert property sequence '
         'cover default disable wait endcase endfunction'.split())
INST = re.compile(r'(?m)^\s*(\w+)\b\s*(?:#\s*\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\))?\s*(\w+)\b\s*(?:\[[^\]]*\]\s*)?\(')


def strip(t):
    return re.sub(r'//[^\n]*|/\*[\s\S]*?\*/', '', t)


def analyse(job):
    pre = source_names(ROOT, copy.deepcopy(job))
    decl = pre['declarations']
    mods = {k.split(':', 1)[1] for k in decl if k.startswith('module:')}
    pkgs = {k.split(':', 1)[1] for k in decl if k.startswith('package:')}
    bodies, pbodies = {}, {}
    for rel in job['sources']:
        t = strip((ROOT / rel).read_text(encoding='utf-8-sig'))
        for m in re.finditer(r'\bmodule\s+(\w+)([\s\S]*?)\bendmodule\b', t):
            bodies[m[1]] = m[2]
        for m in re.finditer(r'\bpackage\s+(\w+)([\s\S]*?)\bendpackage\b', t):
            pbodies[m[1]] = m[2]
    used, edges, unresolved = set(), [], []

    def walk(mod, path):
        used.add(mod)
        for typ, inst in INST.findall(bodies.get(mod, '')):
            if typ in KW or inst in KW:
                continue
            if typ in mods:
                edges.append(f'{path}{inst}:{typ}')
                walk(typ, f'{path}{inst}/')
            elif typ not in pkgs and inst not in KW:
                # a two-identifier statement followed by '(' that is not a
                # declared module: a missing source unless it is a call/type
                unresolved.append(f'{path}{inst}:{typ}')
    walk(job['top'], '')
    refs = set()
    for m in used:
        refs |= set(re.findall(r'\b(\w+)::', bodies[m]))
    stack = list(refs)
    while stack:
        for q in set(re.findall(r'\b(\w+)::', pbodies.get(stack.pop(), ''))):
            if q not in refs:
                refs.add(q)
                stack.append(q)
    files_used = sorted({decl['module:' + m].rsplit(':', 1)[0] for m in used} |
                        {decl['package:' + p].rsplit(':', 1)[0] for p in refs if 'package:' + p in decl})
    return dict(preflight=pre['state'], files=len(job['sources']),
                modules_declared=len(mods), packages_declared=len(pkgs),
                hierarchy=edges, unresolved_instantiations=unresolved,
                modules_reached=sorted(used), modules_not_reached=sorted(mods - used),
                packages_referenced=sorted(refs), packages_missing=sorted(refs - pkgs),
                packages_not_referenced=sorted(pkgs - refs), files_needed=files_used)


def main():
    reg = json.loads((ROOT / 'scripts/dual_lane_jobs.json').read_text())
    jobs = {j['id']: j for j in reg['jobs']}
    out = dict(scope='static source-list check; no Vivado/XSim launched', registry_jobs={}, proposed_jobs={})
    for jid in JOBS:
        out['registry_jobs'][jid] = analyse(jobs[jid])
    # Proposed trimmed lists: the registry order, restricted to files needed.
    for jid in JOBS[:4]:
        need = set(out['registry_jobs'][jid]['files_needed'])
        job = copy.deepcopy(jobs[jid])
        job['sources'] = [s for s in job['sources'] if s in need]
        res = analyse(job)
        res['sources'] = job['sources']
        out['proposed_jobs'][jid] = res
    Path(sys.argv[2]).write_text(json.dumps(out, indent=2) + '\n', encoding='utf-8', newline='\n')
    bad = [j for sect in ('registry_jobs', 'proposed_jobs') for j, r in out[sect].items()
           if r['preflight'] != 'PASS' or r['unresolved_instantiations'] or r['packages_missing']]
    for sect in ('registry_jobs', 'proposed_jobs'):
        for j, r in out[sect].items():
            print(f"{sect}:{j}: preflight={r['preflight']} files={r['files']} mods={r['modules_declared']} "
                  f"pkgs={r['packages_declared']} reached={len(r['modules_reached'])} "
                  f"not_reached={r['modules_not_reached']} pkg_unref={r['packages_not_referenced']} "
                  f"unresolved={r['unresolved_instantiations']} pkg_missing={r['packages_missing']}")
    print('P2_SOURCE_CHECK=' + ('FAIL ' + ','.join(bad) if bad else 'PASS'))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
