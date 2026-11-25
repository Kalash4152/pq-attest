"""Revision 4 V1-V5 audit. Immutable teammate sources; bounded disposable suites."""
import argparse
import ast
import difflib
import importlib
import importlib.util
import itertools
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import time
import zipfile
from dual_lane import ROOT, atomic, now, safe
from dual_lane_verify import InvalidEvidence, sha

PIN = '047bb5a981050f11a572a60e850f7c7511ff5d636f7903c6a8d239891003c6a0'
BASE = ROOT / 'software/pq_attest_final'
CONFIG = ROOT / 'docs/decisions/dual_lane_config.json'
NIST = 'https://csrc.nist.gov/csrc/media/projects/cryptographic-standards-and-guidelines/documents/examples/kmac_samples.pdf'
TERMINALS = {
    'kmac128_ref.py': r'^KMAC128 KAT: PASS$',
    'measurement_ref.py': r'^MEASUREMENT REFERENCE COMPLETE$',
    'kdf_vectors.py': r'^ALL KDF GOLDEN VECTORS PASS$',
    'kdf_verification.py': r'^STAGE 5 PYTHON KDF VERIFICATION: PASS$',
    'attestation_vectors.py': r'^ATTESTATION VERIFICATION PASSED$',
    'attestation_protocol.py': r'^Verdict\s*:\s*ACCEPT$',
    'security_regression.py': r'^SECURITY-PROPERTY REGRESSION PASSED$',
    'cross_module_regression.py': r'^CROSS-MODULE REGRESSION PASSED$',
}


def reference_members():
    archive = ROOT / 'Pq_Attest_final.zip'
    if sha(archive) != PIN: raise InvalidEvidence('BLOCKED_ZIP_MISMATCH')
    with zipfile.ZipFile(archive) as z:
        members = {}
        for member in z.infolist():
            if not member.filename.endswith('.py') or '__pycache__' in member.filename: continue
            if not member.filename.startswith('PQ_Attest/'):
                raise InvalidEvidence('unexpected reference root')
            path = safe(BASE, member.filename)
            members[member.filename] = (path, z.read(member))
        if len(members) != 15: raise InvalidEvidence('unexpected Python member count')
        return members


def pin_and_extract():
    members = reference_members()
    for name, (path, body) in members.items():
        if path.exists() and path.read_bytes() != body:
            raise InvalidEvidence('immutable reference conflict: ' + name)
    for name, (path, body) in members.items():
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(body)
            path.chmod(stat.S_IREAD)
    config = json.loads(CONFIG.read_text())
    config['python_reference'] = dict(zip='Pq_Attest_final.zip', sha256=PIN,
        root=BASE.relative_to(ROOT).as_posix(),
        members={name: sha(path) for name, (path, body) in members.items()},
        historical_zips={n: sha(ROOT/n) for n in ['PQ_Attest (2).zip', 'PQ_Attest (3).zip']},
        suite_timeout_s=120, system_tile_key_bytes=32, immutable=True)
    config['active_increment'] = 'I-1'
    config['tile_key_bytes'] = 32
    atomic(CONFIG, config)
    print('PINNED_REFERENCE: 15 immutable Python files', flush=True)


def verify_reference():
    config = json.loads(CONFIG.read_text())['python_reference']
    members = reference_members()
    if config['sha256'] != PIN or set(config['members']) != set(members):
        raise InvalidEvidence('reference manifest mismatch')
    for name, (path, body) in members.items():
        if not path.is_file() or path.read_bytes() != body or sha(path) != config['members'][name]:
            raise InvalidEvidence('immutable reference mismatch: ' + name)
        if os.name=='nt' and not path.stat().st_file_attributes & stat.FILE_ATTRIBUTE_READONLY:
            raise InvalidEvidence('reference lost read-only attribute: '+name)
    extra = set(p.relative_to(BASE).as_posix() for p in BASE.rglob('*.py')) - set(members)
    if extra: raise InvalidEvidence('unmanifested Python source: ' + str(extra))
    return config


def judge_suite(name, stdout, exit_code, timed_out=False):
    if timed_out or exit_code != 0: raise InvalidEvidence('suite timeout/process failure')
    if re.search(r'\bFAIL\b|^.*\bFAILED(?: TESTS)?\s*:\s*[1-9]\d*|^.*(?:REGRESSION|VERIFICATION) FAILED\s*$', stdout, re.M):
        raise InvalidEvidence('printed failure despite process status')
    if not re.search(TERMINALS[name], stdout, re.M):
        raise InvalidEvidence('missing positive terminal result')
    passed = [line for line in stdout.splitlines() if re.search(r'\bPASS\b|\[PASS\]', line)]
    if name == 'measurement_ref.py':
        passed = re.findall(r'^Status\s*:\s*(PASS|FAIL)\s*$', stdout, re.M)
        if passed != ['PASS']*6: raise InvalidEvidence('measurement requires six parsed PASS results')
    elif name == 'attestation_protocol.py':
        passed = ['Verdict: ACCEPT']
    if not passed: raise InvalidEvidence('no parsed per-test results')
    return dict(result='PASS', parsed_pass_results=passed, fail_lines=[])


def run_suites(out):
    node = ast.parse((BASE/'PQ_Attest/software/run_all_tests.py').read_text(encoding='utf-8-sig'))
    suites = next(ast.literal_eval(n.value) for n in node.body if isinstance(n, ast.Assign)
                  and any(isinstance(t, ast.Name) and t.id == 'TEST_SUITES' for t in n.targets))
    if len(suites) != 8 or {Path(s['script']).name for s in suites} != set(TERMINALS):
        raise InvalidEvidence('suite definition differs from frozen eight suites')
    results = []
    for index, suite in enumerate(suites):
        dest = out/f'suite_{index+1}'
        dest.mkdir(); disposable = dest/'disposable/PQ_Attest'
        # Source bytes remain identical; only this writable copy may create vectors.
        shutil.copytree(BASE/'PQ_Attest', disposable)
        for p in disposable.rglob('*.py'): p.chmod(stat.S_IREAD | stat.S_IWRITE)
        started = now(); timer = time.monotonic(); timed_out = False
        env = os.environ.copy(); env['PYTHONDONTWRITEBYTECODE'] = '1'; env['PYTHONIOENCODING'] = 'utf-8'
        try:
            process = subprocess.run([sys.executable, suite['script']], cwd=disposable,
                capture_output=True, text=True, encoding='utf-8', timeout=120, env=env)
            stdout, stderr, code = process.stdout, process.stderr, process.returncode
        except subprocess.TimeoutExpired as e:
            timed_out = True; code = None
            stdout = e.stdout or b''; stderr = e.stderr or b''
            if isinstance(stdout, bytes): stdout = stdout.decode('utf-8', errors='replace')
            if isinstance(stderr, bytes): stderr = stderr.decode('utf-8', errors='replace')
        atomic(dest/'stdout.log', stdout); atomic(dest/'stderr.log', stderr)
        record = dict(name=suite['name'], script=suite['script'], started=started,
                      ended=now(), wall_seconds=time.monotonic()-timer,
                      exit_code=code, timed_out=timed_out, timeout_seconds=120)
        try: record.update(judge_suite(Path(suite['script']).name, stdout, code, timed_out))
        except InvalidEvidence as e: record.update(result='FAIL', reason=str(e))
        atomic(dest/'process.json', record); results.append(record)
        print(f'PYTHON_SUITE {index+1}/8: {record["result"]}', flush=True)
    result = dict(suites=results, passed=sum(r['result']=='PASS' for r in results), total=8)
    atomic(out/'suite.json', result)
    return result


def load_zip_api():
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(BASE/'PQ_Attest/software'))
    modules = {n: importlib.import_module(n) for n in
               ['kmac128_ref', 'measurement_ref', 'attestation_ref', 'attestation_protocol']}
    for m in modules.values():
        if not Path(m.__file__).resolve().is_relative_to(BASE):
            raise InvalidEvidence('reference import shadowed: ' + m.__name__)
    return modules


def kats_and_diff(out):
    import hashlib
    modules = load_zip_api(); kmac = modules['kmac128_ref'].kmac128
    spec = importlib.util.spec_from_file_location('supplementary_repo_kmac', ROOT/'software/kmac128_ref.py')
    repo = importlib.util.module_from_spec(spec); spec.loader.exec_module(repo)
    key = bytes(range(0x40, 0x60))
    samples = [(bytes(range(4)), b'', 'e5780b0d3ea6f7d3a429c5706aa43a00fadbd7d49628839e3187243f456ee14e'),
        (bytes(range(4)), b'My Tagged Application', '3b1fba963cd8b0b59e8c1a6d71888b7143651af8ba0a7070c0979e2811324aa5'),
        (bytes(range(200)), b'My Tagged Application', '1f5b4e6cca02209e0dcb5ca635b89a15e271ecc760071dfd805faa38f9729230')]
    krows = [dict(sample=i+1, expected=expected, zip_actual=kmac(key, msg, 32, custom).hex(),
                  repo_actual=repo.kmac128(key, msg, 32, custom).hex())
             for i, (msg, custom, expected) in enumerate(samples)]
    for r in krows: r['match'] = r['expected'] == r['zip_actual'] == r['repo_actual']
    srows = []
    for length in [0,3,135,136,137,271,272,273,512]:
        msg = bytes((i*37+11)&255 for i in range(length))
        expected = hashlib.sha3_256(msg).hexdigest()
        actual = modules['measurement_ref'].sha3_256_reference(msg).hex()
        srows.append(dict(length=length, expected=expected, actual=actual, match=expected==actual))
    kats = dict(source=NIST, kmac=krows, sha3=srows,
                result='PASS' if all(r['match'] for r in krows+srows) else 'FAIL')
    atomic(out/'python_kats.json', kats)
    repo_path=ROOT/'software/kmac128_ref.py'; zip_path=BASE/'PQ_Attest/software/kmac128_ref.py'
    diff=''.join(difflib.unified_diff(repo_path.read_text(encoding='utf-8-sig').splitlines(True), zip_path.read_text(encoding='utf-8-sig').splitlines(True),
                                   fromfile='repo/kmac128_ref.py', tofile='pinned_zip/kmac128_ref.py'))
    atomic(out/'kmac_source.diff', diff)
    rows = []
    for length, ml, custom in itertools.product([16,32],[0,4,167,168,169,400],[b'',b'PQ-ATTEST-AUTH']):
        msg=bytes((i*29+7)&255 for i in range(ml))
        a=kmac(key,msg,length,custom).hex();b=repo.kmac128(key,msg,length,custom).hex()
        rows.append(dict(output_bytes=length,message_bytes=ml,customization=custom.decode(),zip=a,repo=b,match=a==b))
    result=dict(repo_sha256=sha(repo_path),zip_sha256=sha(zip_path),cases=rows,
                result='PASS' if all(r['match'] for r in rows) else 'DISCREPANCY_ZIP_GOVERNS')
    atomic(out/'kmac_comparison.json', result)
    return kats, result


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--pin',action='store_true');parser.add_argument('--out',type=Path)
    args=parser.parse_args()
    if args.pin: pin_and_extract();return 0
    if not args.out: parser.error('--out is required for audit evidence')
    out=args.out.resolve()
    if not out.is_relative_to(ROOT/'reports'): raise InvalidEvidence('audit output must stay in reports')
    out.mkdir(parents=True,exist_ok=True)
    config=verify_reference();atomic(out/'reference_manifest.json',config)
    suites=run_suites(out);kats,comparison=kats_and_diff(out)
    verify_reference()
    result=dict(schema=1,reference_sha256=PIN,tile_key_bytes=32,
                V1='PASS',V2='PASS',V3='PASS' if suites['passed']==8 else 'FAIL',
                V4=kats['result'],V5=comparison['result'],V6='DOCUMENTED_SEPARATELY',
                PYTHON_RTL_COMPATIBILITY='NOT_RUN',hardware_validated=False)
    result['result']='PASS' if all(result[v]=='PASS' for v in ['V1','V2','V3','V4','V5']) else 'FAIL'
    atomic(out/'audit.json',result);print('PYTHON_REFERENCE_AUDIT: '+result['result'],flush=True)
    return 0 if result['result']=='PASS' else 1

if __name__=='__main__':sys.exit(main())
