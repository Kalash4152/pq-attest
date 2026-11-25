"""Pure-Python static checks for the I-3 / NOC-2 isolated hop-probe bench (Track HP).

NOT a compile, elaboration or simulation: no simulator is started. It checks
  1. tb_noc_hop_probes.sv: begin/end, case/endcase, function/task, module, fork/join and
     ()/{}/[] balance after stripping comments and strings;
  2. the mesh + six-NI scaffold (per-instance NI port binding = XSim assertion-sampling
     workaround) is a verbatim copy of tb_noc_perf.sv lines 13-213;
  3. check() call sites per region equal HP_COUNT_DERIVATION.md (global 2, probe 6,
     class 1, per-VC 2; 11 sites) and the pair loop calls probe() 3 times;
  4. the frozen CHECKS arithmetic (557 registered, 668 loopback diagnostic) from tile geometry,
     and the message codes / payload lengths used by the registry patch, re-derived from NOC_PKG;
  5. the registry patch applies to scripts/prepare_dual_lane.py, the patched build_registry()
     passes its own consistency checks, the duplicate-name preflight accepts the source list,
     and the existing judge (dual_lane_verify.judge + judge_lines) accepts a SYNTHETIC log built
     from the bench's own $display formats and rejects targeted corruptions of it.
     The synthetic log is invented text to test judge plumbing; it is not simulation evidence.
Exit 0 and print STATIC_HOP_BENCH: PASS on success."""
import importlib.util, re, sys, tempfile
from pathlib import Path

R = Path(__file__).resolve().parents[2]
TB = R / 'NOC_PQATTEST.srcs/sim_1/new/tb_noc_hop_probes.sv'
PERF = R / 'NOC_PQATTEST.srcs/sim_1/new/tb_noc_perf.sv'
PKG = R / 'NOC_PQATTEST.srcs/sources_1/new/NOC_PKG.sv'
PATCH = R / 'reports/i3_hp/prepare_dual_lane.i3_hp.patch'
DERIV = R / 'reports/i3_hp/HP_COUNT_DERIVATION.md'
FROZEN = dict(checks_m=557, checks_loopback=668, probes=90, classes=9, sites=dict(global_=2, probe=6, cls=1, vc=2, total=11))
fails = []
judge_cases = 0

def fail(msg): fails.append(msg)
def strip(t):
    return re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/', lambda m: '""' if m[0].startswith('"') else ' ', t)
def region(t, a, b, start=0):
    i = t.index(a, start); return t[i:t.index(b, i + len(a))]
def sites(t): return len(re.findall(r'\bcheck\(', t))

# ---------------------------------------------------------------- 1. balance
src = TB.read_text(encoding='utf-8'); t = strip(src)
words = re.findall(r'\b(begin|end|case|endcase|function|endfunction|task|endtask|fork|join|join_any|join_none|module|endmodule)\b', t)
for o, c in [('begin', 'end'), ('case', 'endcase'), ('function', 'endfunction'), ('task', 'endtask'), ('module', 'endmodule')]:
    if words.count(o) != words.count(c): fail(f'{o}/{c} {words.count(o)}/{words.count(c)}')
if words.count('fork') != words.count('join') + words.count('join_any') + words.count('join_none'): fail('fork/join')
depth = 0
for w in words:
    depth += (w == 'begin') - (w == 'end')
    if depth < 0: fail('end before begin'); break
for o, c in ['()', '{}', '[]']:
    if t.count(o) != t.count(c): fail(f'{o}{c} {t.count(o)}/{t.count(c)}')
if words.count('module') != 1: fail('exactly one module expected')
if not re.search(r'\bmodule\s+tb_noc_hop_probes\b', t): fail('module name')

# ---------------------------------------------------------------- 2. scaffold copy
tb_lines = src.split('\n'); perf_lines = PERF.read_text(encoding='utf-8').split('\n')
if tb_lines[12:213] != perf_lines[12:213]: fail('scaffold lines 13-213 differ from tb_noc_perf.sv')
body = strip('\n'.join(tb_lines[213:]))

# ---------------------------------------------------------------- 3. check() sites
init = body[body.index('initial begin'):]
got = dict(global_=sites(init[:init.index('for (int a = 0')]),
           probe=sites(region(body, 'task automatic probe(', 'endtask')),
           cls=sites(init[init.index('for (int v = 0; v < NVC; v++)'):init.index('all_mono = 1')]),
           vc=sites(init[init.index('all_mono = 1'):init.index('$finish')]),
           total=sites(body) - 1)   # -1: the task definition itself
if got != FROZEN['sites']: fail(f'check() sites {got} != {FROZEN["sites"]}')
pair_loop = init[init.index('for (int a = 0'):init.index('for (int v = 0; v < NVC; v++)')]
if len(re.findall(r'\bprobe\(', pair_loop)) != 3: fail('pair loop must call probe() exactly 3 times')
if 'if (a == b && !LOOPBACK) continue;' not in pair_loop: fail('loopback exclusion guard missing')
if '$fatal' in body: fail('$fatal in bench body (checks must not be fatal)')
if src.count('TB_TIMEOUT') < 1 or not re.search(r'#8ms;\s*\$display\("TB_TIMEOUT', src): fail('TB_TIMEOUT watchdog')
probe_task = region(body, 'task automatic probe(', 'endtask')
if re.search(r'\bif\b[^;]*\bcheck\(', probe_task): fail('conditional check() in probe task')

# ---------------------------------------------------------------- 4. arithmetic and NOC_PKG facts
def hop(s, d): return abs(s % 3 - d % 3) + abs(s // 3 - d // 3)
def counts(loopback):
    pairs = [(a, b) for a in range(6) for b in range(6) if loopback or a != b]
    hops = sorted({hop(a, b) for a, b in pairs})
    probes = 3 * len(pairs)
    return probes, 3 * len(hops), 2 + 6 * probes + 3 * len(hops) + 2 * 3, pairs
p0, c0, k0, pairs0 = counts(False); p1, c1, k1, _ = counts(True)
if (p0, c0, k0, k1) != (FROZEN['probes'], FROZEN['classes'], FROZEN['checks_m'], FROZEN['checks_loopback']):
    fail(f'arithmetic {(p0, c0, k0, k1)}')
hist = {h: sum(1 for a, b in pairs0 if hop(a, b) == h) for h in (1, 2, 3)}
if hist != {1: 14, 2: 12, 3: 4}: fail(f'hop histogram {hist}')
deriv = DERIV.read_text(encoding='utf-8')
for n in ('**557**', '**668**'):
    if n not in deriv: fail('derivation does not state ' + n)
pkg = PKG.read_text(encoding='utf-8')
code = {m: int(v) for m, v in re.findall(r"(MSG_\w+)\s*=\s*4'd(\d+)", pkg)}
pay = {m: int(v) for m, v in re.findall(r"(MSG_\w+):\s*return 5'd(\d+);", pkg)}
want_vcs = [(0, code['MSG_MEM_WR_REQ'], pay['MSG_MEM_WR_REQ']), (1, code['MSG_MEM_WR_RESP'], pay['MSG_MEM_WR_RESP']),
            (2, code['MSG_ATTEST_CHALLENGE'], pay['MSG_ATTEST_CHALLENGE'])]
if not re.search(r'MAC_TAG_BITS\s*=\s*128;', pkg) or not re.search(r'FLIT_WIDTH\s*=\s*32;', pkg): fail('MAC_FLITS basis (128/32=4)')

# ---------------------------------------------------------------- 5. patch + registry + judge
def apply_patch(text, patch):
    """Minimal exact unified-diff applier (one file). Context and '-' lines must match exactly."""
    out = text.split('\n'); off = 0
    for h in re.finditer(r'^@@ -(\d+)(?:,(\d+))? \+\d+(?:,\d+)? @@[^\n]*\n((?:[ +\-][^\n]*\n|\\[^\n]*\n)*)', patch, re.M):
        start = int(h[1]) - 1 + off; old = []; new = []
        for ln in h[3].split('\n')[:-1]:
            if ln.startswith('\\'): continue
            k, v = ln[0], ln[1:]
            if k in ' -': old.append(v)
            if k in ' +': new.append(v)
        if out[start:start + len(old)] != old: raise ValueError(f'hunk at line {h[1]} does not match')
        out[start:start + len(old)] = new; off += len(new) - len(old)
    return '\n'.join(out)

try:
    patched = apply_patch((R / 'scripts/prepare_dual_lane.py').read_text(encoding='utf-8'), PATCH.read_text(encoding='utf-8'))
except Exception as exc:
    fail(f'patch does not apply: {exc}'); patched = None

if patched is not None:
    sys.path.insert(0, str(R / 'scripts'))
    with tempfile.TemporaryDirectory() as td:
        mp = Path(td) / 'prepare_dual_lane_i3_hp.py'; mp.write_text(patched, encoding='utf-8')
        spec = importlib.util.spec_from_file_location('prepare_dual_lane_i3_hp', mp)
        mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
        reg = mod.build_registry(check_files=True)
    import dual_lane_verify as V
    from dual_lane_preflight import source_names
    jobs = {j['id']: j for j in reg['jobs']}
    if mod.HOP_VCS != want_vcs: fail(f'patch HOP_VCS {mod.HOP_VCS} != NOC_PKG {want_vcs}')
    if 'perf_hop_probes' in jobs: fail('perf_hop_probes gate still present')
    noc2 = next(s for s in reg['stages'] if s['id'] == 'NOC-2')['jobs']
    for jid in ('hop_probes_m0', 'hop_probes_m1'):
        if jid not in jobs: fail('missing ' + jid); continue
        if jid not in noc2 or jid not in reg['increments']['I-3']: fail(jid + ' not in NOC-2 / I-3')
        j = jobs[jid]
        if j['kind'] != 'simulation' or j['selection'] != 'I-3' or j['checks'] != FROZEN['checks_m']: fail(jid + ' fields')
        if j['sources'] != mod.NOC + [mod.HOP_TB]: fail(jid + ' source list')
        if any('rtl/dual_lane' in p for p in j['sources']): fail(jid + ' variant source in production list')
        try: source_names(R, j)
        except Exception as exc: fail(f'{jid} preflight: {exc}')
    if 'perf_hop_probes' in noc2: fail('NOC-2 still lists perf_hop_probes')

    # Synthetic log from the bench's own $display format strings (judge plumbing only).
    def fmt(f): return f.replace('%0d', '%d').replace('%08h', '%08x')
    f_cfg = re.search(r'\$display\("(CONFIG: [^"]+)"', src)[1]
    f_probe = re.search(r'\$display\("(HOP_PROBE [^"]+)"', src)[1]
    f_class = re.search(r'\$display\("(HOP_CLASS [^"]+)"', src)[1]
    f_sum = re.search(r'\$display\("(HOP_SUMMARY [^"]+)"', src)[1]
    f_vc = re.search(r'\$sformatf\("( vc%0d_per_hop=[^"]+)"', src)[1]
    def synth(mac, base=(9, 6, 12), inc=3):
        L = ['CONFIG' + fmt(f_cfg)[6:] % ('MF1-rev5', 64, 1, 2, 'xsim-2024.1', 4 * mac, 30, 90, 9, 0)]
        pid = 0; lat = {}
        for a, b in pairs0:
            for vc, s, d in ((0, a, b), (1, b, a), (2, a, b)):
                h = hop(s, d); n = 1 + want_vcs[vc][2] + 4 * mac; la = base[vc] + 4 * mac + inc * h
                L.append(fmt(f_probe) % (pid, s, d, vc, want_vcs[vc][1], h, n, 100 + pid, 100 + pid + la, la, mac, 1))
                lat[(vc, h)] = la; pid += 1
        for vc in range(3):
            for h in (1, 2, 3):
                L.append(fmt(f_class) % (vc, mac, h, hist[h], lat[(vc, h)], lat[(vc, h)], lat[(vc, h)], 1))
        tail = ''.join(fmt(f_vc) % (vc, inc, vc, lat[(vc, 1)], vc, 'NA') for vc in range(3))
        L.append(fmt(f_sum) % (mac, 0, tail, 1, 1))
        L += ['CHECKS : %d' % FROZEN['checks_m'], 'ERRORS : 0', 'RESULT : PASS']
        return '\n'.join(L) + '\n'
    proc = {s: dict(exitCode=0, timedOut=False) for s in ('compile', 'elaborate', 'simulate')}
    def judged(text, j):
        global judge_cases
        judge_cases += 1
        try: V.judge(text, j, proc, {}, {}); return True
        except V.InvalidEvidence: return False
    for mac in (0, 1):
        j = jobs.get(f'hop_probes_m{mac}')
        if not j: continue
        good = synth(mac)
        if not judged(good, j): fail(f'm{mac}: judge rejects the well-formed synthetic log')
        first = next(l for l in good.splitlines() if l.startswith('HOP_PROBE '))
        bad = {
            'missing probe': good.replace(first + '\n', ''),
            'probe ok=0': good.replace(first, first[:-1] + '0'),
            'duplicate probe': good.replace(first, first + '\n' + first),
            'wrong hops': good.replace(first, re.sub(r'hops=\d+', 'hops=0', first)),
            'zero latency': good.replace(first, re.sub(r'latency=\d+', 'latency=0', first)),
            'class not deterministic': good.replace('deterministic=1', 'deterministic=0', 1),
            'summary const_increment=0': good.replace('const_increment=1', 'const_increment=0'),
            'contention line': good + 'HOP_CONTENTION id=0 fifo_full_port_cycles=1 credit_stall_port_cycles=0 inj_stall=0 ej_stall=0\n',
            'wrong CHECKS': good.replace('CHECKS : %d' % FROZEN['checks_m'], 'CHECKS : %d' % (FROZEN['checks_m'] - 6)),
            'wrong MAC config': good.replace('MAC_FLITS=%d' % (4 * mac), 'MAC_FLITS=%d' % (4 - 4 * mac), 1),
            'l2 not none': good.replace('l2=none', 'l2=rev6', 1),
            'tb timeout': good + 'TB_TIMEOUT hop probe bench (watchdog 8 ms)\n',
            'router SVA error': good + 'Error: noc_router: synchronous LOCAL->LOCAL loopback\n',
            'fail line': good + '[FAIL] HOP_PAYLOAD src=0 dst=1 vc=0 mac=%d\n' % mac,
        }
        for name, text in bad.items():
            if judged(text, j): fail(f'm{mac}: judge accepts corrupted synthetic log: {name}')

for f in fails: print('FAIL', f)
if judge_cases != 2 * 15: fail(f'judge cases run {judge_cases} != 30')
for f in fails[len(fails) - 1:] if judge_cases != 30 else []: print('FAIL', f)
print('STATIC_HOP_BENCH:', 'FAIL' if fails else 'PASS', got, 'judge_cases=%d' % judge_cases)
raise SystemExit(1 if fails else 0)
