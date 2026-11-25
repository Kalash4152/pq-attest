"""NOC-2 performance report: POINT-line accounting first, TRACE lines for latency.

Two modes:
  perf_report.py LOG_M0 LOG_M1 --out DIR     explicit simulate.log files
  perf_report.py --out <run>/<job>           scheduler gate mode (kind=python job): reads
      <run>/registry.json, finds this job (id = folder name) and its 'perf_inputs', then
      each dependency's <run>/<dep>/result.json; the simulate.log is taken from the
      record's artifact list and its recorded sha256 is re-verified.

The matrix is refused (exit 2, no CSV) unless all 56 points (4 patterns x 7 periods x
MAC 0/1) are present exactly once, each with verdict=OK, complete accounting, idle after
drain with all credits returned, consistent tags and a TRACE set matching 'delivered'.
The Verilator cross-check is BLOCKED (not installed) and is never reported as passed.
"""
import argparse,csv,hashlib,json,re,statistics
from pathlib import Path

PATTERNS={0:'uniform',1:'transpose',2:'hotspot',3:'neighbor'}
PERIODS=[64,32,16,8,4,2,1]
WARMUP,MEASURE,CLOCK_NS,TILES=128,2048,20,6
PERF_CHECKS=393   # 1 + 28 x 14, reports/i3_n2/N2_COUNT_DERIVATION.md
POINT_RE=re.compile(r'^POINT case=(?P<case>\w+) pattern=(?P<pattern>\d+) period=(?P<period>\d+) mac=(?P<mac>[01]) '
    r'offered=(?P<offered>\d+) queued=(?P<queued>\d+) cap_drops=(?P<cap_drops>\d+) accepted=(?P<accepted>\d+) '
    r'injected=(?P<injected>\d+) delivered=(?P<delivered>\d+) responses=(?P<responses>\d+) mem_accepted=(?P<mem_accepted>\d+) '
    r'missing=(?P<missing>\d+) unsent=(?P<unsent>\d+) duplicate=(?P<duplicate>\d+) mismatched=(?P<mismatched>\d+) '
    r'unknown=(?P<unknown>\d+) credits_returned=(?P<credits_returned>[01]) idle_after_drain=(?P<idle_after_drain>[01]) '
    r'drain_cycles=(?P<drain_cycles>\d+) verdict=(?P<verdict>OK|FAIL) transport=(?P<transport>\S+) w=(?P<w>\d+) '
    r'wde=(?P<wde>[01]) seed=(?P<seed>0x[0-9a-fA-F]{8}) n_out=(?P<n_out>\d+) tool=(?P<tool>\S+)\s*$',re.M)
TRACE_RE=re.compile(r'^TRACE pattern=(\d+) period=(\d+) mac=([01]) kind=(\d+) source=(\d+) seq=(\d+) dst=(\d+) '
    r'gen=(-?\d+) accept=(-?\d+) inj=(-?\d+) del=(-?\d+) ok=([01])\s*$',re.M)
CONFIG_RE=re.compile(r'^CONFIG: (.+)$',re.M)
TAGS=dict(transport='MF1-rev5',w='64',wde='1',seed='0x12345678',n_out='2',tool='xsim-2024.1')
INT_FIELDS=['pattern','period','mac','offered','queued','cap_drops','accepted','injected','delivered','responses','mem_accepted',
            'missing','unsent','duplicate','mismatched','unknown','credits_returned','idle_after_drain','drain_cycles']
MSG_MEM_WR_REQ=2

class Refused(ValueError): pass

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def one(pattern,text,label):
    v=re.findall(pattern,text,re.M)
    if len(v)!=1: raise Refused(f'{label}: expected exactly one, observed {len(v)}')
    return v[0]

# OD-6 amendment 1 (docs/decisions/N-8-performance-plan-amend-1.md): hotspot/transpose sources whose destination
# is themselves are idle. Active sources per pattern: uniform 6, transpose 4, hotspot 5, neighbor 6.
ACTIVE_SOURCES={0:6,1:4,2:5,3:6}
def expected_counts(pattern,period):
    gen=WARMUP+MEASURE
    if gen%period: raise Refused(f'period {period} does not divide {gen}')
    n=ACTIVE_SOURCES[pattern]; per_src=gen//period; queued=min(per_src,256)
    return dict(offered=n*per_src,queued=n*queued,cap_drops=n*(per_src-queued))

def parse_log(text,label):
    """Return (mac, points{(pattern,period):row}, traces) for one 28-point perf log; refuse on any defect."""
    cfg=one(r'^CONFIG: (.+)$',text,label+' CONFIG')
    kv=dict(re.findall(r'(\w+)=(\S+)',cfg))
    if kv.get('TOP')!='tb_noc_perf' or kv.get('CASE')!='perf' or kv.get('POINTS')!='28':
        raise Refused(f'{label}: not a 28-point perf build: {cfg}')
    mac={'0':0,'4':1}.get(kv.get('MAC_FLITS'))
    if mac is None: raise Refused(f'{label}: unexpected MAC_FLITS {kv.get("MAC_FLITS")}')
    for k,v in dict(SEED='305419896',W='64',WDE='1',N_OUTSTANDING='2',WARMUP='128',MEASURE='2048',DRAIN='50000',CAP='256').items():
        if kv.get(k)!=v: raise Refused(f'{label}: CONFIG {k}={kv.get(k)}, expected {v}')
    if one(r'^\s*RESULT\s*:\s*(\w+)\s*$',text,label+' RESULT')!='PASS': raise Refused(f'{label}: RESULT is not PASS')
    if int(one(r'^\s*ERRORS\s*:\s*(\d+)\s*$',text,label+' ERRORS'))!=0: raise Refused(f'{label}: ERRORS != 0')
    if int(one(r'^\s*CHECKS\s*:\s*(\d+)\s*$',text,label+' CHECKS'))!=PERF_CHECKS: raise Refused(f'{label}: CHECKS != {PERF_CHECKS}')
    if re.search(r'^(\[FAIL\]|LIVENESS_FIRED)|TB_TIMEOUT',text,re.M): raise Refused(f'{label}: failure or liveness line present')
    if len(re.findall(r'^POINT ',text,re.M))!=28 or len(POINT_RE.findall(text))!=28:
        raise Refused(f'{label}: malformed or wrong number of POINT lines')
    points={}
    for m in POINT_RE.finditer(text):
        r=m.groupdict()
        for k in INT_FIELDS: r[k]=int(r[k])
        key=(r['pattern'],r['period'])
        if r['case']!='perf' or r['mac']!=mac: raise Refused(f'{label}: point {key} case/mac mismatch')
        if key in points: raise Refused(f'{label}: duplicate point {key}')
        for k,v in TAGS.items():
            if r[k]!=v: raise Refused(f'{label}: point {key} tag {k}={r[k]}, expected {v}')
        exp=expected_counts(r['pattern'],r['period'])
        bad=[k for k,v in exp.items() if r[k]!=v]
        q=r['queued']
        if r['verdict']!='OK' or bad or not (q==r['accepted']==r['injected']==r['delivered']==r['responses']==r['mem_accepted']) \
           or any(r[k] for k in ['missing','unsent','duplicate','mismatched','unknown']) \
           or r['credits_returned']!=1 or r['idle_after_drain']!=1 or r['drain_cycles']>50000:
            raise Refused(f'{label}: incomplete accounting at point {key}: {bad or r}')
        points[key]=r
    want={(p,t) for p in PATTERNS for t in PERIODS}
    if set(points)!=want: raise Refused(f'{label}: point set incomplete: missing {sorted(want-set(points))}')
    traces=[tuple(int(x) for x in t) for t in TRACE_RE.findall(text)]
    return mac,points,traces

def rows_from(logs):
    by_mac={}
    for label,text in logs:
        mac,points,traces=parse_log(text,label)
        if mac in by_mac: raise Refused(f'two logs for MAC mode {mac}')
        by_mac[mac]=(points,traces)
    if set(by_mac)!={0,1}: raise Refused(f'matrix incomplete: MAC modes present {sorted(by_mac)}, need 0 and 1 (56 points)')
    rows=[]
    for mac,(points,traces) in sorted(by_mac.items()):
        for (pat,per),pt in sorted(points.items()):
            group=[t for t in traces if t[0]==pat and t[1]==per and t[2]==mac and t[3]==MSG_MEM_WR_REQ]
            if any(t[11]!=1 for t in group): raise Refused(f'mismatched TRACE at {pat}/{per}/mac{mac}')
            ids=[(t[4],t[5]) for t in group]
            if len(ids)!=len(set(ids)) or len(group)!=pt['delivered']:
                raise Refused(f'TRACE set != delivered at {pat}/{per}/mac{mac}: {len(group)} vs {pt["delivered"]}')
            if any(not (0<=t[7]<=t[8]<=t[9]<=t[10]) for t in group): raise Refused(f'timestamp order at {pat}/{per}/mac{mac}')
            net=[t[10]-t[9] for t in group]; queue=[t[8]-t[7] for t in group]; total=[t[10]-t[7] for t in group]
            dw=sum(WARMUP<=t[10]<WARMUP+MEASURE for t in group); aw=sum(WARMUP<=t[8]<WARMUP+MEASURE for t in group)
            na=ACTIVE_SOURCES[pat]; offered_rate=1/per; acc_rate=aw/(MEASURE*na)
            p95=lambda xs: sorted(xs)[max(0,-(-95*len(xs)//100)-1)]   # nearest-rank (ceil(0.95 n))
            rows.append(dict(pattern=PATTERNS[pat],pattern_id=pat,period=per,offered_packets_per_cycle_tile=offered_rate,mac_framing=mac,
                transport=pt['transport'],w=int(pt['w']),wde=int(pt['wde']),seed=pt['seed'],n_out=int(pt['n_out']),tool=pt['tool'],clock_ns=CLOCK_NS,
                offered=pt['offered'],queued=pt['queued'],cap_drops=pt['cap_drops'],accepted=pt['accepted'],injected=pt['injected'],
                delivered=pt['delivered'],responses=pt['responses'],drain_cycles=pt['drain_cycles'],
                accepted_packets_per_cycle_tile=acc_rate,delivered_packets_per_cycle_tile=dw/(MEASURE*na),active_sources=na,
                regime='offered_load_met' if acc_rate>=0.95*offered_rate else 'saturated',
                network_min=min(net),network_mean=statistics.mean(net),network_p95=p95(net),network_max=max(net),
                queue_mean=statistics.mean(queue),total_mean=statistics.mean(total),
                data_bytes_per_second=dw*4/(MEASURE*CLOCK_NS*1e-9)))
    if len(rows)!=56: raise Refused(f'{len(rows)}/56 points')
    return rows

def svg(rows,key,title,ylabel,path):
    colors=['#176b87','#e07a5f','#6a994e','#7b2cbf']
    W,H,L,B,T,R=900,520,80,450,60,860
    xs=sorted({r['period'] for r in rows},reverse=True)   # 64..1, log2 spaced
    xpos={p:L+(R-L)*i/(len(xs)-1) for i,p in enumerate(xs)}
    ymax=max(r[key] for r in rows) or 1
    out=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}"><rect width="{W}" height="{H}" fill="white"/>',
         f'<text x="{L}" y="30" font-family="sans-serif" font-size="17">{title}</text>',
         f'<path d="M{L} {T}V{B}H{R}" fill="none" stroke="#444"/>']
    for p in xs: out.append(f'<text x="{xpos[p]-12:.0f}" y="{B+20}" font-family="sans-serif" font-size="12">1/{p}</text>')
    for i in range(5):
        y=B-(B-T)*i/4; out.append(f'<text x="8" y="{y+4:.0f}" font-family="sans-serif" font-size="11">{ymax*i/4:.3g}</text>')
    for pat in range(4):
        for mac in (0,1):
            data=sorted((r for r in rows if r['pattern_id']==pat and r['mac_framing']==mac),key=lambda r:-r['period'])
            pts=' '.join(f"{xpos[r['period']]:.1f},{B-(B-T)*r[key]/ymax:.1f}" for r in data)
            dash=' stroke-dasharray="5 3"' if mac else ''
            out.append(f'<polyline points="{pts}" fill="none" stroke="{colors[pat]}" stroke-width="2"{dash}/>')
        out.append(f'<text x="{R-150}" y="{T+16*pat}" font-family="sans-serif" font-size="12" fill="{colors[pat]}">{PATTERNS[pat]}</text>')
    out+=[f'<text x="{R-150}" y="{T+70}" font-family="sans-serif" font-size="11">solid MAC off, dashed MAC on (framing only)</text>',
          f'<text x="380" y="{H-20}" font-family="sans-serif">offered packets/cycle/tile</text>',
          f'<text x="10" y="{T-12}" font-family="sans-serif" font-size="12">{ylabel}</text>','</svg>']
    Path(path).write_text(''.join(out),encoding='utf-8')

def write_outputs(rows,out,inputs):
    out.mkdir(parents=True,exist_ok=True)
    with (out/'performance.csv').open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
    svg(rows,'delivered_packets_per_cycle_tile','Measured NoC throughput (XSim, 20 ns clock)','delivered packets/cycle/tile',out/'throughput.svg')
    svg(rows,'network_mean','Mean network latency t_del - t_inj','cycles',out/'latency.svg')
    scope=dict(points=len(rows),expected_points=56,complete=True,inputs=inputs,
               window=dict(warmup=WARMUP,measure=MEASURE),p95_method='nearest-rank: sorted[ceil(0.95 n)-1]',
               mac_on='framing only (tag carried, no MAC computation)',
               regime_rule="saturated if accepted rate < 0.95 x offered; bottleneck attribution (NI N_OUTSTANDING=2 vs mesh) is not inferred by this tool",
               verilator_cross_check='BLOCKED (Verilator not installed on this host); NOT_RUN for uniform 1/16 and hotspot 1/4',
               cross_simulator_passed=False,isolated_hop_probes='NOT_IMPLEMENTED (separate subgate)')
    (out/'scope.json').write_text(json.dumps(scope,indent=2),encoding='utf-8')

def gate_inputs(out):
    run=out.parent; registry=json.loads((run/'registry.json').read_text(encoding='utf-8'))
    job=next((j for j in registry['jobs'] if j['id']==out.name),None)
    if not job or 'perf_inputs' not in job: raise Refused(f'gate job {out.name} has no perf_inputs in registry.json')
    spec=job['perf_inputs']; logs=[]; inputs={}
    for jid in spec['points']+spec.get('controls',[])+spec.get('n75',[]):
        rec=json.loads((run/jid/'result.json').read_text(encoding='utf-8'))
        if rec.get('state') not in ('PASS_FRESH','PASS_REUSED'): raise Refused(f'{jid}: state {rec.get("state")}')
        want='CONTROL_EFFECTIVE' if jid in spec.get('controls',[]) else 'PASS'
        if (rec.get('observed') or {}).get('result')!=want: raise Refused(f'{jid}: observed result {(rec.get("observed") or {}).get("result")}, expected {want}')
        sims=[p for p in rec.get('artifacts',{}) if Path(p).name=='simulate.log']
        if len(sims)!=1: raise Refused(f'{jid}: expected one simulate.log artifact, found {len(sims)}')
        p=sims[0]
        if not Path(p).is_file() or sha(p)!=rec['artifacts'][p]: raise Refused(f'{jid}: simulate.log hash mismatch')
        inputs[jid]=dict(log=p,sha256=rec['artifacts'][p],state=rec['state'])
        if jid in spec['points']: logs.append((jid,Path(p).read_text(errors='replace')))
    return logs,inputs

def main(argv=None):
    ap=argparse.ArgumentParser(); ap.add_argument('logs',nargs='*'); ap.add_argument('--out',required=True); a=ap.parse_args(argv)
    out=Path(a.out)
    try:
        if a.logs:
            logs=[(f,Path(f).read_text(errors='replace')) for f in a.logs]; inputs={f:dict(sha256=sha(f)) for f in a.logs}
        else:
            logs,inputs=gate_inputs(out)
        rows=rows_from(logs)
    except (Refused,OSError,KeyError,ValueError) as e:
        print(f'PERF_MATRIX: REFUSED {e}'); return 2
    write_outputs(rows,out,inputs)
    print(f'Parsed {sum(r["delivered"] for r in rows)} delivered packets, {len(rows)}/56 points')
    print('VERILATOR_CROSS_CHECK: BLOCKED (not installed)')
    print('PERF_MATRIX: PASS'); return 0

if __name__=='__main__': raise SystemExit(main())
