"""Engineer 4 CORRECTED final suite (Python model checks) re-run on THIS repository's live sources (job e4_verification_v3).

Vendored from E4_P7_CORRECTED_HANDOFF_FINAL_20261106.zip (SHA-256 cf9d9256...dd1c; E4 HEAD 78ba9dc;
reports/E4_CORRECTED_INTAKE_20261106.md): verification/ unchanged (the six tests/sample_*.log inputs, absent from the zip,
are kept from the previous vendoring), E4 data in verification/e4_data/. Stage layout as v2, except the vectors: E4's suite
now reads OUR registered vectors/d2_k3_64.* (staged from vectors/, never written) and its own renamed
vectors/e4_d2_measurements.* (staged from verification/e4_data/vectors/). The repository is never written.
Frozen expectations (Kalash 2026-11-06 "check and integrate"): pytest verification = 389 passed, 0 failed / skipped;
p7_regression.py --full = 15 / 15 stages PASS. Classification: Python model checking only (no RTL simulation).
v1 (224 / 15) and v2 (387 / 15) stay as history.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import e4_verification as v1      # noqa: E402
import e4_verification_v2 as v2   # noqa: E402

ROOT = v1.ROOT
PYTEST_EXPECT = 389
STAGES_EXPECT = 15


def judge(pytest_rc, pytest_out, reg_rc, reg_out):
    """Same rules as v1 / v2, with the v3 frozen counts (no shared state)."""
    lines = pytest_out.strip().splitlines()
    tail = lines[-1].strip() if lines else ''
    m = v1.re.fullmatch(r'(\d+) passed in [\d.]+s', tail)
    out = v1.re.sub(r'\x1b\[[0-9;]*m', '', reg_out)
    s = v1.re.search(r'REGRESSION RESULT: PASS \(Passed: (\d+), Failed: 0, Skipped: 0\)', out)
    ok = bool(pytest_rc == 0 and m and int(m.group(1)) == PYTEST_EXPECT and reg_rc == 0 and s and int(s.group(1)) == STAGES_EXPECT)
    return ok, f'pytest tail={tail!r} rc={pytest_rc}; regression rc={reg_rc} stages={s.group(1) if s else None}'


def stage(t: Path) -> None:
    v2.stage(t)                                              # v1 layout + S4 evidence zip (hash-pinned) + teammate refs
    shutil.rmtree(t / 'vectors', ignore_errors=True)
    (t / 'vectors').mkdir()
    for n in ('json', 'svh'):
        shutil.copyfile(ROOT / f'vectors/d2_k3_64.{n}', t / f'vectors/d2_k3_64.{n}')                          # registered
        shutil.copyfile(ROOT / f'verification/e4_data/vectors/e4_d2_measurements.{n}', t / f'vectors/e4_d2_measurements.{n}')


def main() -> int:
    with tempfile.TemporaryDirectory(prefix='e4v3_') as d:
        t = Path(d)
        stage(t)
        p = subprocess.run([sys.executable, '-m', 'pytest', 'verification', '-q', '-p', 'no:cacheprovider'],
                           cwd=t, capture_output=True, text=True)
        print(p.stdout[-3000:]); print(p.stderr[-2000:], file=sys.stderr)
        r = subprocess.run([sys.executable, 'verification/p7_regression.py', '--full'], cwd=t, capture_output=True, text=True)
        print(v1.re.sub(r'\x1b\[[0-9;]*m', '', r.stdout)[-4000:]); print(r.stderr[-2000:], file=sys.stderr)
    ok, detail = judge(p.returncode, p.stdout, r.returncode, r.stdout)
    if not ok:
        print(f'E4_VERIFICATION_V3: FAIL ({detail})')
        return 1
    print(f'E4_VERIFICATION_V3: PASS (pytest {PYTEST_EXPECT} passed; regression {STAGES_EXPECT}/{STAGES_EXPECT})')
    return 0


if __name__ == '__main__':
    sys.exit(main())
