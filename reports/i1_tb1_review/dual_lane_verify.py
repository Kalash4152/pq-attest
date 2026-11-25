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
            if re.search(r'global timeout|TB_TIMEOUT|FATAL:|\[FATAL\]|STRESS TIMEOUT',text,re.I): raise InvalidEvidence('timeout/crash is not a mutation kill')
        elif res.upper()!='PASS' or errors or checks!=job['checks']:
            raise InvalidEvidence(f'expected {job["checks"]}/0 PASS; observed {checks}/{errors} {res}')
        for key,val in job.get('extra_counts',{}).items():
            got=int(unique(text,r'^\s*'+re.escape(key)+r'\s*[:=]\s*(\d+)\s*$',key))
            if got!=val: raise InvalidEvidence(f'{key}: expected {val}, observed {got}')
    cleaned=text; diagnostic_observations={}
    try:
        if job.get('judge')=='tb1':
            cleaned,diagnostic_observations=adjudicate_tb1(text)
        elif job.get('mutant') in ('n6_a','n6_b_t5','n6_c'):
            if checks!=job['checks']:raise InvalidEvidence('N-6 mutant incomplete check count')
            cleaned,diagnostic_observations=adjudicate_n6_mutant(text,job['mutant'],job['checks'],errors)
    except DiagnosticEvidenceError as exc:
        raise InvalidEvidence(str(exc)) from exc
    diag=r'^\s*(ERROR:|Error:|FATAL:|Fatal:)|assertion[^\r\n]*(failed|failure)|TB_TIMEOUT|global timeout|\[FATAL\]|STRESS TIMEOUT'
    if not job.get('mutant'): diag += r'|^\[FAIL\]'
    if re.search(diag,cleaned,re.M|re.I): raise InvalidEvidence('unexpected assertion/fatal/error/timeout')
    return {'checks':None if job.get('judge')=='tb1' else checks,
            'errors':0 if job.get('judge')=='tb1' else errors,
            'result':'KILLED' if job.get('mutant') else 'PASS','config':cfg,**diagnostic_observations}

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
