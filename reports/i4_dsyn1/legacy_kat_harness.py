"""D-SYN-1 step 5 (legacy-format known-answer benches) on the variant crypto list. SUPPORTING evidence only: a harness
run outside scripts/dual_lane.py; the I-4 gate cites the registered dsyn1_* jobs.
Compiles P.CRYPTO_SYN (rtl/dual_lane SHA3_PAD.sv and pq_keccak_iota.sv instead of the originals) + one legacy TB outside
the repo and runs xsim -R with stdin closed. A stalled launch is relaunched once (stall budget spans invocations via
--prior-stall=top:n); a second stall makes the bench INVALID and it is never counted. Logs are copied to
reports/i4_dsyn1/legacy/. The PASS/FAIL line set is compared with the historical stage log where one exists; otherwise
the bench must show its own overall PASS and no FAIL line. --reuse=top judges an already completed log without
rerunning."""
import json, re, subprocess, sys, hashlib
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]; sys.path.insert(0, str(ROOT / 'scripts'))
import prepare_dual_lane as P
VIV = Path(r'C:\xilinx_vivado\Vivado\2024.1\bin'); WORK = Path(sys.argv[1]); OUT = ROOT / 'reports/i4_dsyn1/legacy'
T = ROOT / 'NOC_PQATTEST.srcs/sim_1/new'
REUSE = {a.split('=', 1)[1] for a in sys.argv[2:] if a.startswith('--reuse=')}
PRIOR = {k: int(v) for a in sys.argv[2:] if a.startswith('--prior-stall=') for k, v in [a.split('=', 1)[1].split(':')]}
BENCHES = [  # tb file, top, historical log or None, own overall-pass regex or None
    ('SHA3_TB.sv', 'tb_sha3_256', None, None),
    ('pq_keccak_tb.sv', 'tb_keccak_f1600', None, r'^\s*OVERALL\s*:\s*PASS'),
    ('kmac_tb.sv', 'KMAC_TB', 'logs/s3_kmac_2026-09-23.log', None),
    ('pq_kdf_tb.sv', 'pq_kdf_tb', 'logs/s5_kdf_2026-09-23.log', None),
    ('pq_measurement_tb.sv', 'pq_measurement_tb', 'logs/s6_meas_2026-09-23.log', None),
    ('pqattest_tb.sv', 'pq_attestation_tag_tb', 'logs/s7_runA_2026-09-23.log', None)]
PF = re.compile(r'(\[PASS\]|\[FAIL\]|\bPASS\b|\bFAIL\b|ZERO TEST ERRORS|CHECKS|ERRORS)')
norm = lambda s: re.sub(r'\s+', ' ', re.sub(r'@ *\d+.*$|time\s*[:=]?\s*\d+\s*\w*|\d+\s*ns\b', '', s)).strip()
def pf_lines(text): return sorted(norm(l) for l in text.splitlines() if PF.search(l) and not l.startswith(('#', 'INFO', 'WARNING', '$finish', 'Time:')))
def leftovers(cwd):
    """Processes still running out of (or naming) this bench's work dir: e.g. an xsimk.exe orphaned when its xsim parent
    was killed. Scoped to the harness's own bench directory only."""
    q = ('Get-CimInstance Win32_Process | Select-Object ProcessId,ExecutablePath,CommandLine | ConvertTo-Json -Compress')
    out = subprocess.run(['powershell', '-NoProfile', '-NonInteractive', '-Command', q], capture_output=True, text=True).stdout
    norm = lambda s: s.replace('/', chr(92)).lower()
    key = norm(str(Path(cwd).resolve()))
    procs = json.loads(out) if out.strip() else []
    return [x['ProcessId'] for x in (procs if isinstance(procs, list) else [procs])
            if key in norm((x.get('ExecutablePath') or '') + ' ' + (x.get('CommandLine') or ''))]
def run(cmd, cwd, timeout):
    # stdout/stderr go to files, never pipes: an orphaned grandchild holding a pipe once blocked communicate() forever
    # (2026-10-20, tag bench, xsimk PID 8320). On timeout the tree is killed, then any leftover under cwd.
    with open(Path(cwd) / '_harness_stdout.txt', 'w') as fo:
        pr = subprocess.Popen(cmd, cwd=cwd, stdin=subprocess.DEVNULL, stdout=fo, stderr=subprocess.STDOUT)
        try: rc = pr.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill', '/PID', str(pr.pid), '/T', '/F'], capture_output=True)  # this harness's own tree
            rc = 'TIMEOUT'
            try: pr.wait(timeout=30)
            except subprocess.TimeoutExpired: pass
    for pid in leftovers(cwd):
        subprocess.run(['taskkill', '/PID', str(pid), '/T', '/F'], capture_output=True)
    return rc
def main():
    OUT.mkdir(parents=True, exist_ok=True); WORK.mkdir(parents=True, exist_ok=True); res = []
    glbl = VIV.parent / 'data/verilog/src/glbl.v'
    variants = [s for s in P.CRYPTO_SYN if s.startswith('rtl/dual_lane/')]
    replaced = [s for s in P.CRYPTO if s not in P.CRYPTO_SYN]
    for tb, top, hist, own in BENCHES:
        d = WORK / top; d.mkdir(exist_ok=True)
        r = dict(tb=tb, top=top, stalls=PRIOR.get(top, 0), compiled_variants=variants, originals_not_compiled=replaced,
                 variant_sha256={s: hashlib.sha256((ROOT / s).read_bytes()).hexdigest() for s in variants})
        if top in REUSE:
            text = (OUT / f'{top}.log').read_text(errors='replace'); r['reused_completed_log'] = True
            prj = (d / 'p.prj').read_text()
            if any(Path(s).name in prj and 'rtl/dual_lane' not in s for s in replaced if f'"{(ROOT / s).as_posix()}"' in prj): r['result'] = 'ORIGINAL_COMPILED'; res.append(r); continue
        else:
            (d / 'p.prj').write_text(''.join(f'sv xil_defaultlib "{(ROOT / s).as_posix()}"\n' for s in P.CRYPTO_SYN)
                                     + f'sv xil_defaultlib "{(T / tb).as_posix()}"\n' + f'verilog xil_defaultlib "{glbl.as_posix()}"\n')
            rc = run([str(VIV / 'xvlog.bat'), '--relax', '-prj', 'p.prj', '-i', str(T), '-log', 'xvlog.log'], d, 900)
            rc2 = run([str(VIV / 'xelab.bat'), '--debug', 'typical', '--relax', '--mt', 'off', '-L', 'xil_defaultlib', '-L', 'unisims_ver',
                       '--snapshot', 'h', 'xil_defaultlib.' + top, 'xil_defaultlib.glbl', '-log', 'elab.log'], d, 900) if rc == 0 else 'SKIP'
            if rc != 0 or rc2 != 0: r.update(result='BUILD_FAIL', xvlog=rc, xelab=rc2); res.append(r); continue
            text = ''
            while r['stalls'] < 2:
                log = d / f'sim_a{r["stalls"]}.log'   # fresh name per attempt: a killed xsim can keep the old log locked
                rc3 = run([str(VIV / 'xsim.bat'), 'h', '-R', '-log', log.name], d, 600)
                if rc3 != 'TIMEOUT' and log.exists() and log.stat().st_size > 2000: text = log.read_text(errors='replace'); break
                r['stalls'] += 1
            if not text:
                r.update(result='INVALID', reason=f'xsim launch stalled {r["stalls"]} times (one relaunch allowed); never counted')
                res.append(r); print(json.dumps(r)[:300], flush=True); continue
            (OUT / f'{top}.log').write_text(text, encoding='utf-8', newline='\n')
        prj = (d / 'p.prj').read_text()
        r['prj_has_originals'] = [s for s in replaced if f'"{(ROOT / s).as_posix()}"' in prj]
        r['log_sha256'] = hashlib.sha256(text.encode()).hexdigest()
        got = pf_lines(text)
        if hist:
            want = pf_lines((ROOT / hist).read_text(errors='replace'))
            r.update(history=hist, only_new=sorted(set(got) - set(want))[:8], only_hist=sorted(set(want) - set(got))[:8])
            r['result'] = 'MATCH_HISTORY' if got == want else 'DIFFERS_FROM_HISTORY'
        else:
            fails = [l for l in got if 'FAIL' in l and 'PASS' not in l]
            ok = (re.search(own, text, re.M) is not None) if own else any('PASS' in l for l in got)
            r.update(fail_lines=fails[:8], own_pass=ok, result='PASS' if ok and not fails else 'FAIL')
        if r['prj_has_originals']: r['result'] = 'ORIGINAL_COMPILED'
        res.append(r); print(json.dumps({k: r[k] for k in ('top', 'result', 'stalls')}), flush=True)
    (OUT / 'summary.json').write_text(json.dumps(res, indent=1) + '\n', encoding='utf-8', newline='\n')
if __name__ == '__main__': main()
