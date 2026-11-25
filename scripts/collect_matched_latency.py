"""Collect accepted dependency logs, retaining exact source-run provenance."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import statistics
from matched_latency import parse,parse_control_latencies

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve()
    summary={}
    for mode in ('secure','fixed','secure_contended','fixed_contended'):
        jid='i25_matched_'+mode
        result=json.loads((out.parent/jid/'result.json').read_text())
        if result['state'] not in ('PASS_FRESH','PASS_REUSED'):
            raise ValueError('unaccepted dependency '+jid)
        origin=out.parent.parent/result['fresh_run']/jid
        logs=list((origin/'workspace').rglob('simulate.log'))
        if len(logs)!=1:raise ValueError('ambiguous raw simulation log')
        raw=logs[0].read_bytes();rows=parse(raw.decode(errors='replace'))
        with (out/(mode+'_transactions.csv')).open('w',newline='') as f:
            w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
        stats={}
        for label,write in [('read',0),('write',1)]:
            values=[r['latency'] for r in rows if r['write']==write]
            stats[label]=dict(count=len(values),minimum_cycles=min(values),maximum_cycles=max(values),mean_cycles=statistics.mean(values))
        summary[mode]=dict(workload_cycles=rows[-1]['response']-rows[0]['accepted'],transactions_per_cycle=64/(rows[-1]['response']-rows[0]['accepted']),raw_log=str(logs[0]),raw_sha256=hashlib.sha256(raw).hexdigest(),source_run=result['fresh_run'],latency=stats)
    phase_rec=json.loads((out.parent/'i25_phase_sweep/result.json').read_text())
    if phase_rec['state'] not in ('PASS_FRESH','PASS_REUSED'):raise ValueError('unaccepted phase sweep')
    origin=out.parent.parent/phase_rec['fresh_run']/'i25_phase_sweep'
    logs=list((origin/'workspace').rglob('simulate.log'))
    if len(logs)!=1:raise ValueError('ambiguous phase sweep log')
    phase_raw=logs[0].read_bytes();phase_text=phase_raw.decode(errors='replace')
    attest,revoke=parse_control_latencies(phase_text)
    for name,header,rows in [('attestation', ['start','grant','cycles','ns','granted'],attest),
                             ('revocation',['phase','start','effective','cycles','ns','revoked'],revoke)]:
        with (out/(name+'_cycles.csv')).open('w',newline='') as f:
            w=csv.writer(f);w.writerow(header);w.writerows(rows)
    summary['control_latency']=dict(raw_log=str(logs[0]),raw_sha256=hashlib.sha256(phase_raw).hexdigest(),
                                   attestation_samples=len(attest),revoke_samples=len(revoke),
                                   start_event='core start_attestation or revoke asserted after measurement valid; excludes button debounce and MMCM startup',stop_events='authorization first high or low at negedge observation')
    (out/'matched_latency.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('MATCHED_COMPARISON: PASS modes=4 transactions_per_mode=64')

if __name__=='__main__':main()
