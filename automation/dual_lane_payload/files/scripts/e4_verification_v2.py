"""Engineer 4 FINAL verification suite (Python model checks) re-run on THIS repository's live sources (job e4_verification_v2).

Vendored from finalpqattest.zip (SHA-256 176b162f...7d55, E4 HEAD b62b78d + uncommitted work; reports/E4_FINAL_INTAKE_20261106.md):
verification/ unchanged, plus the E4 data in verification/e4_data/. E4's D2 measurement vectors keep E4's format and are
stored as verification/e4_data/vectors/e4_d2_k3_64.* (our registered vectors/d2_k3_64.* are never overwritten); they are
placed at vectors/d2_k3_64.* only inside the temporary stage, where E4's tests look for them. The E4 S4-evidence tests read
PQ_Attest_S4_Evidence/, which is our own S4 export: staged from _export/PQ_Attest_S4_Evidence_20261105.zip, pinned by
SHA-256 below (binary input on disk with a recorded hash; not committed). The repository is never written.
Frozen expectations (Kalash 2026-11-06 "Import + new job"): pytest verification = 387 passed, 0 failed / skipped;
p7_regression.py --full = 15 / 15 stages PASS. Classification: Python model checking only (no RTL simulation).
The v1 job (scripts/e4_verification.py, 224 / 15) is kept as history.
"""
import hashlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import e4_verification as v1   # noqa: E402  (same judge rules, new frozen counts)

ROOT = v1.ROOT
PYTEST_EXPECT = 387
STAGES_EXPECT = 15
S4_ZIP = ROOT / '_export/PQ_Attest_S4_Evidence_20261105.zip'
S4_ZIP_SHA256 = '3aa52a6bd59a351325d7b6e3a1f2ed0911cfcdb1c78505196e4673b8387da085'


def judge(pytest_rc, pytest_out, reg_rc, reg_out):
    """Same rules as the v1 judge, with the v2 frozen counts (no shared state with v1)."""
    lines = pytest_out.strip().splitlines()
    tail = lines[-1].strip() if lines else ''
    m = v1.re.fullmatch(r'(\d+) passed in [\d.]+s', tail)
    out = v1.re.sub(r'\x1b\[[0-9;]*m', '', reg_out)
    s = v1.re.search(r'REGRESSION RESULT: PASS \(Passed: (\d+), Failed: 0, Skipped: 0\)', out)
    ok = bool(pytest_rc == 0 and m and int(m.group(1)) == PYTEST_EXPECT and reg_rc == 0 and s and int(s.group(1)) == STAGES_EXPECT)
    return ok, f'pytest tail={tail!r} rc={pytest_rc}; regression rc={reg_rc} stages={s.group(1) if s else None}'


def extract_long(zpath: Path, dst: Path) -> None:
    bs = chr(92)
    with zipfile.ZipFile(zpath) as z:
        for i in z.infolist():
            parts = i.filename.split('/')
            if i.filename.startswith(('/', bs)) or '..' in parts or ':' in i.filename:
                raise SystemExit('unsafe path in ' + zpath.name + ': ' + i.filename)
            p = bs + bs + '?' + bs + str(dst.joinpath(*parts)).replace('/', bs)
            if i.is_dir():
                Path(p).mkdir(parents=True, exist_ok=True); continue
            Path(p).parent.mkdir(parents=True, exist_ok=True)
            Path(p).write_bytes(z.read(i))


def stage(t: Path) -> None:
    v1.stage(t)                                                      # verification/, rtl, srcs, XSim bundle, e4_data, refs
    shutil.rmtree(t / 'vectors', ignore_errors=True)
    (t / 'vectors').mkdir()
    for n in ('json', 'svh'):
        shutil.copyfile(ROOT / f'verification/e4_data/vectors/e4_d2_k3_64.{n}', t / f'vectors/d2_k3_64.{n}')
    shutil.rmtree(t / 'software/pq_attest_final', ignore_errors=True)
    shutil.copytree(ROOT / 'software/pq_attest_final', t / 'software/pq_attest_final')
    (t / 'reports/n25_2026-09-23').mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'reports/n25_2026-09-23/paths_lt3ns.csv', t / 'reports/n25_2026-09-23/paths_lt3ns.csv')
    h = hashlib.sha256(S4_ZIP.read_bytes()).hexdigest()
    if h != S4_ZIP_SHA256:
        raise SystemExit(f'S4 evidence zip hash mismatch: {h}')
    extract_long(S4_ZIP, t)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix='e4v2_') as d:
        t = Path(d)
        stage(t)
        p = subprocess.run([sys.executable, '-m', 'pytest', 'verification', '-q', '-p', 'no:cacheprovider'],
                           cwd=t, capture_output=True, text=True)
        print(p.stdout[-3000:]); print(p.stderr[-2000:], file=sys.stderr)
        r = subprocess.run([sys.executable, 'verification/p7_regression.py', '--full'], cwd=t, capture_output=True, text=True)
        print(v1.re.sub(r'\x1b\[[0-9;]*m', '', r.stdout)[-4000:]); print(r.stderr[-2000:], file=sys.stderr)
    ok, detail = judge(p.returncode, p.stdout, r.returncode, r.stdout)
    if not ok:
        print(f'E4_VERIFICATION_V2: FAIL ({detail})')
        return 1
    print(f'E4_VERIFICATION_V2: PASS (pytest {PYTEST_EXPECT} passed; regression {STAGES_EXPECT}/{STAGES_EXPECT})')
    return 0


if __name__ == '__main__':
    sys.exit(main())
