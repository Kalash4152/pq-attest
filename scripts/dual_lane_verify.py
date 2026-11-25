"""Fail-closed raw evidence adjudication, shared by fresh jobs and reuse audits."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re
from controlled_diagnostics import adjudicate_tb1, adjudicate_n6_mutant, DiagnosticEvidenceError

PASS = {'PASS_FRESH', 'PASS_REUSED'}
class InvalidEvidence(ValueError): pass
class GateFailure(ValueError): pass

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def unique(text, pattern, label):
    values=re.findall(pattern,text,re.M|re.I)
    if len(values)!=1: raise InvalidEvidence(f'{label}: expected exactly one, observed {len(values)}')
    return values[0]

# NOC-2 (I-3): POINT-line accounting and expected-FAIL TB controls (no source mutation).
POINT_RE=re.compile(r'^POINT case=(?P<case>\w+) pattern=(?P<pattern>\d+) period=(?P<period>\d+) mac=(?P<mac>[01]) '
    r'offered=(?P<offered>\d+) queued=(?P<queued>\d+) cap_drops=(?P<cap_drops>\d+) accepted=(?P<accepted>\d+) '
    r'injected=(?P<injected>\d+) delivered=(?P<delivered>\d+) responses=(?P<responses>\d+) mem_accepted=(?P<mem_accepted>\d+) '
    r'missing=(?P<missing>\d+) unsent=(?P<unsent>\d+) duplicate=(?P<duplicate>\d+) mismatched=(?P<mismatched>\d+) '
    r'unknown=(?P<unknown>\d+) credits_returned=(?P<credits_returned>[01]) idle_after_drain=(?P<idle_after_drain>[01]) '
    r'drain_cycles=(?P<drain_cycles>\d+) verdict=(?P<verdict>OK|FAIL) transport=(?P<transport>\S+) w=(?P<w>\d+) '
    r'wde=(?P<wde>[01]) seed=(?P<seed>0x[0-9a-fA-F]{8}) n_out=(?P<n_out>\d+) tool=(?P<tool>\S+)\s*$')
POINT_TEXT=('case','verdict','transport','seed','tool')

def parse_points(text):
    rows=[]
    for line in text.splitlines():
        if not line.startswith('POINT '): continue
        m=POINT_RE.match(line)
        if not m: raise InvalidEvidence('malformed POINT line: '+line[:200])
        rows.append({k:(v if k in POINT_TEXT else int(v)) for k,v in m.groupdict().items()})
    return rows

def judge_points(text, spec):
    """spec: {mac, tags:{field:value}, points:[{case,pattern,period,exact:{},max:{}}]}. Every listed point must
    appear exactly once, no other POINT line may appear, and every exact/max field must hold."""
    rows=parse_points(text); seen={}
    for r in rows:
        key=(r['case'],r['pattern'],r['period'])
        if key in seen: raise InvalidEvidence(f'duplicate POINT {key}')
        seen[key]=r
    want={(p['case'],p['pattern'],p['period']):p for p in spec['points']}
    if set(seen)!=set(want):
        raise InvalidEvidence(f'POINT set mismatch: missing {sorted(set(want)-set(seen))}, unexpected {sorted(set(seen)-set(want))}')
    for key,p in want.items():
        r=seen[key]
        if r['mac']!=spec['mac']: raise InvalidEvidence(f'POINT {key}: mac={r["mac"]}, expected {spec["mac"]}')
        for k,v in {**spec.get('tags',{}),**p.get('exact',{})}.items():
            if str(r[k])!=str(v): raise InvalidEvidence(f'POINT {key}: {k}={r[k]}, expected {v}')
        for k,v in p.get('max',{}).items():
            if r[k]>v: raise InvalidEvidence(f'POINT {key}: {k}={r[k]} exceeds {v}')
        for k,v in p.get('min',{}).items():
            if r[k]<v: raise InvalidEvidence(f'POINT {key}: {k}={r[k]} below {v}')
    return dict(points=len(rows),verdicts=sorted({r['verdict'] for r in rows}))

def judge_lines(text, required):
    for pattern,count in required:
        got=len(re.findall(pattern,text,re.M))
        if got!=count: raise InvalidEvidence(f'required line {pattern!r}: expected {count}, observed {got}')

def judge_control(text, job, res, errors, checks):
    """Expected-FAIL TB control (no RTL mutation): complete check set, exact ERRORS, every targeted oracle
    line exactly once, every [FAIL] line allow-listed, forbidden lines absent, no timeout/fatal."""
    c=job['tb_control']
    if res.upper()!='FAIL' or errors==0: raise InvalidEvidence('ineffective control (RESULT not FAIL)')
    if checks!=job['checks']: raise InvalidEvidence(f'control incomplete: CHECKS {checks}, expected {job["checks"]}')
    if errors!=c['errors']: raise InvalidEvidence(f'control ERRORS {errors}, expected {c["errors"]}')
    for pattern in c['oracle']:
        got=len(re.findall(pattern,text,re.M))
        if got!=1: raise InvalidEvidence(f'untargeted control: oracle {pattern!r} observed {got} times')
    for line in re.findall(r'^\[FAIL\][^\r\n]*',text,re.M):
        if not any(re.match(a,line) for a in c['allowed_fail']): raise InvalidEvidence('unexpected control failure line: '+line[:200])
    for pattern in c.get('forbid',[]):
        if re.search(pattern,text,re.M): raise InvalidEvidence(f'forbidden control observation {pattern!r}')
    if re.search(r'global timeout|TB_TIMEOUT|FATAL:|\[FATAL\]|STRESS TIMEOUT',text,re.I): raise InvalidEvidence('timeout/crash is not an effective control')

def judge(text, job, process, before, after, *, fresh=True, cleanup=True):
    if before != after: raise InvalidEvidence('source identity changed during job')
    if not cleanup: raise InvalidEvidence('cleanup failed')
    if not text.strip(): raise InvalidEvidence('missing/empty simulation result')
    for step in ['compile','elaborate','simulate']:
        p=process.get(step)
        if not p or p.get('exitCode') != 0 or p.get('timedOut') or p.get('interrupted'):
            raise InvalidEvidence(f'{step}: failed, missing, interrupted or wall timeout')
        if fresh and p.get('stale'): raise InvalidEvidence(f'{step}: stale result')
    cfg=job.get('config',{})
    if cfg:
        line=unique(text,job.get('config_pattern',r'^CONFIG\s*:\s*([^\r\n]+)$'),'CONFIG')
        for key,val in cfg.items():
            if not re.search(r'\b'+re.escape(key)+r'\s*=\s*'+re.escape(str(val))+r'(?:\s|$|\))',line):
                raise InvalidEvidence(f'wrong configuration {key}={val}: {line}')
    marker='N0 EXPECTED-FAIL CONFIRMED (deterministic: locks held, competitors blocked)'
    if text.count(marker) != int(job.get('negative',False)):
        raise InvalidEvidence('missing/unexpected/duplicate N0 marker')
    if job.get('judge')=='tb1':
        unique(text,r'^\s*OVERALL\s*:\s*(PASS\s*\(0 failures\))\s*$','TB1 result')
    else:
        res=unique(text,r'^\s*RESULT\s*[:=]\s*(PASS|FAIL)\s*$','RESULT')
        errors=int(unique(text,r'^\s*ERRORS\s*[:=]\s*(\d+)\s*$','ERRORS'))
        checks=int(unique(text,r'^\s*CHECKS\s*[:=]\s*(\d+)\s*$','CHECKS'))
        if job.get('mutant'):
            if res.upper()!='FAIL' or errors==0: raise InvalidEvidence('surviving mutant')
            if not re.search(job['oracle'],text,re.M): raise InvalidEvidence('untargeted mutant failure')
            # Hardening (Codex F8, Kalash 2026-10-21): a kill needs the complete frozen check count, and every [FAIL] line
            # must belong to the targeted scope (kill_scope, default: the oracle); an unrelated failure is not a kill.
            if checks!=job['checks']: raise InvalidEvidence(f'incomplete mutant run: {checks} of {job["checks"]} checks')
            scope=job.get('kill_scope',job['oracle'])
            stray=[l for l in text.splitlines() if re.match(r'^\s*\[FAIL\]',l) and not re.search(scope,l)]
            if stray: raise InvalidEvidence('unrelated failure in mutant run: '+stray[0][:160])
            if re.search(r'global timeout|TB_TIMEOUT|FATAL:|\[FATAL\]|STRESS TIMEOUT',text,re.I): raise InvalidEvidence('timeout/crash is not a mutation kill')
        elif job.get('tb_control'):
            judge_control(text,job,res,errors,checks)
        elif res.upper()!='PASS' or errors or checks!=job['checks']:
            raise InvalidEvidence(f'expected {job["checks"]}/0 PASS; observed {checks}/{errors} {res}')
        for key,val in job.get('extra_counts',{}).items():
            got=int(unique(text,r'^\s*'+re.escape(key)+r'\s*[:=]\s*(\d+)\s*$',key))
            if got!=val: raise InvalidEvidence(f'{key}: expected {val}, observed {got}')
    if job.get('point_accounting'):
        if not job.get('tb_control') and re.search(r'^LIVENESS_FIRED',text,re.M): raise InvalidEvidence('liveness monitor fired')
        point_summary=judge_points(text,job['point_accounting'])
    if job.get('required_lines'): judge_lines(text,job['required_lines'])
    cleaned=text; diagnostic_observations={}
    try:
        if job.get('judge')=='tb1':
            cleaned,diagnostic_observations=adjudicate_tb1(text)
        elif job.get('mutant') in ('n6_a','n6_b_t5','n6_c'):
            if checks!=job['checks']:raise InvalidEvidence('N-6 mutant incomplete check count')
            cleaned,diagnostic_observations=adjudicate_n6_mutant(text,job['mutant'],job['checks'],errors)
    except DiagnosticEvidenceError as exc:
        raise InvalidEvidence(str(exc)) from exc
    if job.get('expected_diag'):
        if not job.get('mutant'): raise InvalidEvidence('expected_diag is allowed only on mutant jobs')
        cleaned=strip_expected_diag(cleaned,job['expected_diag'])
    diagnostic_scan(cleaned,job)
    return {'checks':None if job.get('judge')=='tb1' else checks,
            'errors':0 if job.get('judge')=='tb1' else errors,
            'result':'KILLED' if job.get('mutant') else 'CONTROL_EFFECTIVE' if job.get('tb_control') else 'PASS','config':cfg,
            **({'point_accounting':point_summary} if job.get('point_accounting') else {}),**diagnostic_observations}

def ooc_gate(m, job):
    """OOC acceptance (hardened, Codex F8): latches 0, WNS/WHS/WPWS >= 0, TNS/THS = 0, cells > 0; DRC_ERRORS = 0 and
    UNCONSTRAINED_ENDPOINTS = 0 where the child reports them (required for child-script jobs); LUT <= job['max_lut'].
    Returns None, or raises GateFailure / InvalidEvidence."""
    if m.get('LATCHES')!='0' or float(m['WNS'])<0 or float(m['WHS'])<0: raise GateFailure(f'OOC timing/latch gate failed: {m}')
    if int(m['CELLS'])==0: raise InvalidEvidence('OOC hierarchy trimmed')
    if job.get('child_script'):
        for k in ('DRC_ERRORS','UNCONSTRAINED_ENDPOINTS','WPWS','TNS','THS','LUT'):
            if k not in m: raise InvalidEvidence(f'OOC metric {k} missing')
    for k in ('DRC_ERRORS','UNCONSTRAINED_ENDPOINTS'):
        if k in m and m[k]!='0': raise GateFailure(f'OOC {k}={m[k]}')
    for k in ('TNS','THS'):
        if k in m and float(m[k])!=0: raise GateFailure(f'OOC {k}={m[k]}')
    if 'WPWS' in m and float(m['WPWS'])<0: raise GateFailure(f'OOC WPWS={m["WPWS"]}')
    if 'max_lut' in job and int(m['LUT'])>int(job['max_lut']): raise GateFailure(f'OOC LUT {m["LUT"]} > ceiling {job["max_lut"]}')

def pnr_gate(m):
    """Contract sec. 6 integrated P&R checkpoint: WNS/WHS/WPWS >= 0, TNS/THS = 0, 0 nets with routing errors, 0 blocking
    (Error) DRCs, 0 unconstrained endpoints, and the approved OOC clock-source model only. A missing or non-numeric
    metric is INVALID; a violated bound is a GateFailure (HARD STOP per contract sec. 12)."""
    keys = ('PNR_WNS', 'PNR_TNS', 'PNR_WHS', 'PNR_THS', 'PNR_WPWS', 'PNR_ROUTE_ERRORS', 'PNR_DRC_ERRORS',
            'PNR_UNCONSTRAINED_ENDPOINTS', 'PNR_LUT', 'PNR_LUTRAM', 'PNR_CONTROL_SETS', 'PNR_CLK_SRC')
    for k in keys:
        if k not in m or m[k] in ('', 'NA'): raise InvalidEvidence(f'P&R metric {k} missing')
    if m['PNR_CLK_SRC'] != 'BUFGCTRL_X0Y0': raise InvalidEvidence(f'P&R clock-source model not the approved one: {m["PNR_CLK_SRC"]}')
    try: v = {k: float(m[k]) for k in keys[:8]}
    except ValueError: raise InvalidEvidence(f'P&R metric not numeric: {m}')
    bad = [k for k in ('PNR_WNS', 'PNR_WHS', 'PNR_WPWS') if v[k] < 0] + \
          [k for k in ('PNR_TNS', 'PNR_THS', 'PNR_ROUTE_ERRORS', 'PNR_DRC_ERRORS', 'PNR_UNCONSTRAINED_ENDPOINTS') if v[k] != 0]
    if bad: raise GateFailure('P&R checkpoint failed: ' + ', '.join(f'{k}={m[k]}' for k in bad))

def lutram_gate(util_hier, patterns):
    """RAM-inference check (contract sec. 6): every instance matching a pattern must report LUTRAMs > 0 in the hierarchical
    utilization report; a missing instance is INVALID, zero LUTRAM is a GateFailure ('RAM not inferred')."""
    rows = [r for r in util_hier.splitlines() if r.startswith('|')]
    hdr = next((r for r in rows if 'Instance' in r and 'LUTRAM' in r), None)
    if hdr is None: raise InvalidEvidence('util_hier.rpt has no LUTRAM column')
    cols = [c.strip() for c in hdr.strip('|').split('|')]; li = next(i for i, c in enumerate(cols) if 'LUTRAM' in c)
    for pat in patterns:
        hit = [r for r in rows if r is not hdr and re.search(pat, r.strip('|').split('|')[0])]
        if not hit: raise InvalidEvidence(f'RAM-inference check: no instance matches {pat}')
        for r in hit:
            val = r.strip('|').split('|')[li].strip()
            if not val.isdigit() or int(val) == 0: raise GateFailure(f'RAM not inferred in {r.split("|")[1].strip()} (LUTRAMs={val})')

DIAG=r'^\s*(ERROR:|Error:|FATAL:|Fatal:)|assertion[^\r\n]*(failed|failure)|TB_TIMEOUT|global timeout|\[FATAL\]|STRESS TIMEOUT'

def diagnostic_scan(cleaned, job):
    diag=DIAG
    if not job.get('mutant') and not job.get('tb_control'): diag += r'|^\[FAIL\]'
    if re.search(diag,cleaned,re.M|re.I): raise InvalidEvidence('unexpected assertion/fatal/error/timeout')

def strip_expected_diag(text, patterns):
    """Proposal A (docs/proposals/expected_diag.md, approved by Kalash 2026-10-21): remove the lines that FULLY match one
    of the job's ^...$ anchored regexes; every regex must match at least once. Every other line stays for
    diagnostic_scan, so an unexpected Error/fatal/timeout still makes the job INVALID."""
    if not patterns or any(not (p.startswith('^') and p.endswith('$')) for p in patterns):
        raise InvalidEvidence('expected_diag needs a non-empty list of ^...$ anchored regexes')
    regs=[re.compile(p) for p in patterns]; hits=[0]*len(regs); keep=[]
    for line in text.splitlines():
        s=line.rstrip('\r'); m=[i for i,r in enumerate(regs) if r.fullmatch(s)]
        if m:
            for i in m: hits[i]+=1
        else: keep.append(line)
    missing=[patterns[i] for i,h in enumerate(hits) if h==0]
    if missing: raise InvalidEvidence('expected diagnostic line missing: '+'; '.join(missing))
    return '\n'.join(keep)

def dependencies_ok(job, records):
    return all(records.get(d,{}).get('state') in PASS for d in job.get('dependencies',[]))

def complete(stages):
    return len(stages)==10 and all(s['state'] in PASS for s in stages.values())

def artifacts_valid(record):
    return bool(record.get('artifacts')) and all(Path(p).is_file() and sha(p)==h for p,h in record['artifacts'].items())

def reuse_wp0(root, folder, job):
    root=Path(root); folder=Path(folder)
    a=(folder/'sources_before.tsv').read_bytes(); b=(folder/'sources_after.tsv').read_bytes()
    if a!=b: raise InvalidEvidence('archived before/after manifest mismatch')
    source_rows=0; manifest={}
    for line in a.decode('utf-8-sig').splitlines():
        h,size,path=line.split('\t',2); p=Path(path)
        if not p.exists() and 'NOC_PQATTEST.sim' in path:
            p=folder/'generated'/Path(path).name
        if not p.is_file() or p.stat().st_size!=int(size) or sha(p)!=h:
            raise InvalidEvidence(f'archived build/source mismatch: {path}')
        manifest[str(Path(path))]=h
        if p.suffix.lower() in ['.sv','.v'] and '.srcs' in str(p): source_rows+=1
    generated=folder/'generated'
    processes={s:json.loads((generated/f'process_{s}.status.json').read_text()) for s in ['compile','elaborate','simulate']}
    cfg=dict(line.split('=',1) for line in (folder/'config.txt').read_text().splitlines() if '=' in line)
    if cfg.get('TOP')!=job['top']: raise InvalidEvidence('archived wrong top')
    for key in ['DEFINES_REQUESTED','DEFINES_APPLIED']:
        if cfg.get(key,'').split()!=job.get('defines',[]): raise InvalidEvidence(f'wrong archived {key}')
    compile_text=(generated/'compile.bat').read_text()
    if 'Vivado (TM) v2024.1' not in compile_text: raise InvalidEvidence('unproven tool version')
    defs=re.findall(r'\s-d\s+"([^"]+)"',unique(compile_text,r'^(call xvlog[^\r\n]*)$','compiler command'))
    if sorted(defs)!=sorted(job.get('defines',[])): raise InvalidEvidence('archived compiler define mismatch')
    prjs=list(generated.glob('*_vlog.prj'))
    compiled=[]
    for prj in prjs:
        for path in re.findall(r'"([^"]+)"',prj.read_text()):
            if Path(path).suffix.lower() in ['.sv','.v']: compiled.append(str(Path(path)))
    if not compiled or any(p not in manifest for p in compiled): raise InvalidEvidence('compiled sources absent from manifest')
    text=(generated/'simulate.log').read_text(errors='replace')
    if (folder/'verdict.txt').read_text().count('SIM_ATTEMPTS=1')!=1: raise InvalidEvidence('archived retry needs explicit adjudication')
    observed=judge(text,job,processes,a,b,fresh=False)
    return dict(state='PASS_REUSED',original_run=folder.parent.name,source_rows=source_rows,
                observed=observed,process=processes,source_manifest=manifest)
