"""Validate raw matched memory transactions before deriving workload-specific latency."""
import argparse
import csv
import json
from pathlib import Path
import re
import statistics

ROW = re.compile(r'^BENCH_REQ index=(\d+) write=([01]) address=([0-9a-fA-F]{8}) accepted=(\d+) response=(\d+) latency=(\d+) data=([0-9a-fA-F]{8}) error=([01])$', re.M)

def parse_control_latencies(text):
    attest=[tuple(map(int,r)) for r in re.findall(r'^ATTEST_LATENCY start=(\d+) grant=(\d+) cycles=(\d+) ns=(\d+) granted=(\d+)$',text,re.M)]
    revoke=[tuple(map(int,r)) for r in re.findall(r'^REVOKE_LATENCY phase=(\d+) start=(\d+) effective=(\d+) cycles=(\d+) ns=(\d+) revoked=(\d+)$',text,re.M)]
    if len(attest)!=21 or any(stop-start!=cycles or cycles<=0 or ns!=20*cycles or ok!=1 for start,stop,cycles,ns,ok in attest):
        raise ValueError('invalid attestation measurements')
    if [r[0] for r in revoke]!=list(range(7)) or any(stop-start!=cycles or not 0<cycles<1500 or ns!=20*cycles or ok!=1 for _,start,stop,cycles,ns,ok in revoke):
        raise ValueError('invalid revocation measurements')
    return attest,revoke

def parse(text):
    if re.search(r'\[FAIL\]|ERROR:|TB_TIMEOUT|Fatal:', text, re.I):
        raise ValueError('simulation diagnostic')
    for pattern, expected in [(r'^RESULT\s*:\s*(\w+)\s*$', ['PASS']),
                              (r'^CHECKS\s*:\s*(\d+)\s*$', ['8']),
                              (r'^ERRORS\s*:\s*(\d+)\s*$', ['0'])]:
        if re.findall(pattern, text, re.M) != expected:
            raise ValueError('missing, duplicate or failed acceptance line')
    if '$finish called' not in text:
        raise ValueError('bench did not finish')
    rows=[]
    for index,write,address,accepted,response,latency,data,error in ROW.findall(text):
        rows.append(dict(index=int(index),write=int(write),address=int(address,16),accepted=int(accepted),
                         response=int(response),latency=int(latency),data=int(data,16),error=int(error)))
    if len(rows)!=64:
        raise ValueError('expected exactly 64 transactions')
    previous=-1
    for k,r in enumerate(rows):
        if r['index']!=k or r['write']!=1-k%2 or r['address']!=0x22000100+4*(k//2):
            raise ValueError('transaction sequence mismatch')
        if r['error'] or r['response']<=r['accepted'] or r['latency']!=r['response']-r['accepted'] or r['accepted']<previous:
            raise ValueError('invalid response, overlap or cycle record')
        if not r['write'] and r['data']!=k//2+1:
            raise ValueError('read data mismatch')
        previous=r['response']
    return rows

def main():
    ap=argparse.ArgumentParser();ap.add_argument('log',type=Path);ap.add_argument('out',type=Path);a=ap.parse_args()
    rows=parse(a.log.read_text(errors='replace'));a.out.mkdir(parents=True,exist_ok=True)
    with (a.out/'transactions.csv').open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    summary={}
    for label,write in [('read',0),('write',1)]:
        values=[r['latency'] for r in rows if r['write']==write]
        summary[label]=dict(count=len(values),minimum_cycles=min(values),maximum_cycles=max(values),mean_cycles=statistics.mean(values))
    (a.out/'latency_summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('MATCHED_LATENCY: PASS transactions=64')

if __name__=='__main__':main()
