"""Self-test for legacy_kat_harness.run(): a timed-out command whose grandchild has escaped the process tree (its
parent exited) and holds the inherited stdout must (1) not block the harness, (2) return 'TIMEOUT', and (3) leave
no process behind. Reproduces the 2026-10-20 orphan-xsimk hang with python stand-ins; no Vivado/XSim involved."""
import sys, time, tempfile, subprocess, json
from pathlib import Path
work = Path(tempfile.mkdtemp(prefix='npqc_harness_selftest_'))
sys.argv = ['harness', str(work)]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import legacy_kat_harness as H
py = sys.executable
marker = str(work / 'orphan_marker')
(work / 'mid.py').write_text(  # starts the grandchild and exits at once -> the grandchild leaves the tree
    'import subprocess,sys\n'
    f'subprocess.Popen([sys.executable, "-c", "import time; time.sleep(300)", {marker!r}], creationflags=0x00000008)\n')
(work / 'child.py').write_text(  # runs mid synchronously, then hangs like a stalled xsim launch
    'import subprocess,sys,time\n'
    f'subprocess.run([sys.executable, {str(work / "mid.py")!r}])\n'
    'print("child started", flush=True); time.sleep(300)\n')
def alive():
    return [p for p in H.leftovers(work)]
# control: with the sweep disabled, taskkill /T alone must leave the escaped grandchild alive (proves the scenario)
real = H.leftovers; H.leftovers = lambda cwd: []
# The deadlock of 2026-10-20 (xsim front-end killed, xsimk kernel kept the stdout pipe, communicate() never returned):
# with NO sweep the run must still return promptly, because output goes to a file, not a pipe.
t_c = time.time()
rc0 = H.run([py, str(work / 'child.py')], work, 5); H.leftovers = real
dt0 = time.time() - t_c
escaped = alive()
for pid in escaped: subprocess.run(['taskkill', '/PID', str(pid), '/T', '/F'], capture_output=True)
t0 = time.time()
rc = H.run([py, str(work / 'child.py')], work, 5)
dt = time.time() - t0
left = alive()
ok = rc0 == 'TIMEOUT' and dt0 < 60 and len(escaped) >= 1 and rc == 'TIMEOUT' and dt < 90 and not left
print(json.dumps(dict(control_escaped=len(escaped), control_return_s=round(dt0, 1), rc=rc, seconds=round(dt, 1), leftovers=left)))
print('LEGACY_HARNESS_SELFTEST:', 'PASS' if ok else 'FAIL')
sys.exit(0 if ok else 1)
