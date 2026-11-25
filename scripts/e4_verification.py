"""Engineer 4 verification suite (Python model checks), re-run on THIS repository's live sources.

Vendored from pqattestfinal.zip (SHA-256 4bd4cb4f...6218, E4 HEAD b62b78d; reports/E4_PACKAGE_INTAKE_20261105.md):
verification/ unchanged, plus the E4 data it reads in verification/e4_data/. The E4 suite assumes the E4 working-copy
layout, and its regression runner writes verification/generated/ and runs `pytest .` at the root, so it runs in a staged
temporary copy; this repository is never written. Staged layout:
  verification/                         <- verification/ (repo, vendored)
  rtl/, NOC_PQATTEST.srcs/{sources_1,sim_1}/ <- live repository sources (release + I-9 variants)
  E4_P7_XSIM_20261103/                  <- docs/handoff/E4_P7_XSIM_20261103/ (the XSim bundle given to E4)
  reports/E4_P7_STEP*.md, software/*.json <- verification/e4_data/
  software/kmac128_ref.py, gen_stage7_vectors.py, logs/s3_kmac_2026-09-23.log <- repo
Frozen expectations (Kalash 2026-11-05 "Yes, import it"): pytest verification = 224 passed, 0 failed / skipped;
p7_regression.py --full = 15 / 15 stages PASS. Classification: Python model checking only (no RTL simulation).
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PYTEST_EXPECT = 224
STAGES_EXPECT = 15


def stage(t: Path) -> None:
    cp = lambda s, d: (d.parent.mkdir(parents=True, exist_ok=True), shutil.copytree(s, d) if s.is_dir() else shutil.copyfile(s, d))
    cp(ROOT / 'verification', t / 'verification')
    shutil.rmtree(t / 'verification' / 'e4_data')
    cp(ROOT / 'rtl', t / 'rtl')
    for s in ('sources_1', 'sim_1'):
        cp(ROOT / 'NOC_PQATTEST.srcs' / s, t / 'NOC_PQATTEST.srcs' / s)
    cp(ROOT / 'docs/handoff/E4_P7_XSIM_20261103', t / 'E4_P7_XSIM_20261103')
    for p in (ROOT / 'verification/e4_data').rglob('*'):
        if p.is_file():
            cp(p, t / p.relative_to(ROOT / 'verification/e4_data'))
    for rel in ('software/kmac128_ref.py', 'software/gen_stage7_vectors.py', 'logs/s3_kmac_2026-09-23.log'):
        cp(ROOT / rel, t / rel)
    subprocess.run(['git', 'init', '-q'], cwd=t, check=True)


def judge(pytest_rc: int, pytest_out: str, reg_rc: int, reg_out: str):
    """Return (ok, detail). Exact frozen counts; any failure, skip, error or count change is not a PASS."""
    lines = pytest_out.strip().splitlines()
    tail = lines[-1].strip() if lines else ''
    m = re.fullmatch(r'(\d+) passed in [\d.]+s', tail)
    out = re.sub(r'\[[0-9;]*m', '', reg_out)
    s = re.search(r'REGRESSION RESULT: PASS \(Passed: (\d+), Failed: 0, Skipped: 0\)', out)
    ok = bool(pytest_rc == 0 and m and int(m.group(1)) == PYTEST_EXPECT and reg_rc == 0 and s and int(s.group(1)) == STAGES_EXPECT)
    return ok, f'pytest tail={tail!r} rc={pytest_rc}; regression rc={reg_rc} stages={s.group(1) if s else None}'


def main() -> int:
    with tempfile.TemporaryDirectory(prefix='e4v_') as d:
        t = Path(d)
        stage(t)
        p = subprocess.run([sys.executable, '-m', 'pytest', 'verification', '-q', '-p', 'no:cacheprovider'],
                           cwd=t, capture_output=True, text=True)
        print(p.stdout[-3000:]); print(p.stderr[-2000:], file=sys.stderr)
        r = subprocess.run([sys.executable, 'verification/p7_regression.py', '--full'], cwd=t, capture_output=True, text=True)
        print(re.sub(r'\[[0-9;]*m', '', r.stdout)[-4000:]); print(r.stderr[-2000:], file=sys.stderr)
    ok, detail = judge(p.returncode, p.stdout, r.returncode, r.stdout)
    if not ok:
        print(f'E4_VERIFICATION: FAIL ({detail})')
        return 1
    print(f'E4_VERIFICATION: PASS (pytest {PYTEST_EXPECT} passed; regression {STAGES_EXPECT}/{STAGES_EXPECT})')
    return 0


if __name__ == '__main__':
    sys.exit(main())
