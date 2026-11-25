"""Synthetic parser controls only; no hardware or simulation claims."""
from matched_latency import parse,parse_control_latencies

def main():
    rows=[]
    for k in range(64):
        start=k*20+10
        rows.append(f'BENCH_REQ index={k} write={1-k%2} address={0x22000100+4*(k//2):08x} accepted={start} response={start+5} latency=5 data={k//2+1:08x} error=0')
    good='\n'.join(rows+['CHECKS : 8','ERRORS : 0','RESULT : PASS','$finish called'])
    assert len(parse(good))==64
    bad=[good.replace('RESULT : PASS','RESULT : FAIL'),good+'\nRESULT : PASS',
         good.replace(rows[3],'').strip(),good+'\n'+rows[3],
         good.replace('index=3 ','index=2 '),good.replace('write=1 ','write=0 ',1),
         good.replace('address=22000100','address=22000104',1),
         good.replace('latency=5','latency=6',1),good.replace('error=0','error=1',1),
         good.replace('data=00000001','data=ffffffff'),good.replace('$finish called',''),
         good+'\n[FAIL] sample',good.replace('accepted=30 response=35','accepted=11 response=16')]
    for text in bad:
        try:parse(text)
        except ValueError:pass
        else:raise AssertionError('invalid log accepted')
    print(f'MATCHED_LATENCY_TESTS: PASS checks={len(bad)+1}')
    a='ATTEST_LATENCY start=10 grant=20 cycles=10 ns=200 granted=1\n'
    rev=''.join(f'REVOKE_LATENCY phase={i} start=30 effective=40 cycles=10 ns=200 revoked=1\n' for i in range(7))
    control=21*a+rev
    parse_control_latencies(control)
    invalid=[rev,20*a+rev,control.replace('phase=1','phase=0'),control.replace('cycles=10','cycles=1500'),
             control.replace('ns=200','ns=201'),control.replace('effective=40','effective=41'),
             control.replace('revoked=1','revoked=0'),control.replace('granted=1','granted=0')]
    for text in invalid:
        try:parse_control_latencies(text)
        except ValueError:pass
        else:raise AssertionError('invalid control latency accepted')
    print('CONTROL_LATENCY_TESTS: PASS checks=9')

if __name__=='__main__':main()
