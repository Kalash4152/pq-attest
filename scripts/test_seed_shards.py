"""Synthetic shard, log and bounded-retry controls; no native simulator is invoked."""
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import seed_campaign as campaign
from seed_shards import assemble,check_log

def good_log(seed):
    return f'RESULT : PASS\nCHECKS : 2\nErrors = 0\nSEED_RESULT seed={seed} completed=1 errors=0\nSEED_LATENCY seed={seed} grant=1 response=100\n$finish called\n'

def main():
    expected={'source.sv':'hash'}
    shards=[dict(tool='Vivado/XSim 2024.1',sources=expected.copy(),first_seed=i*100,seed_count=100,
                 seeds=[dict(seed=s,sv_seed=s+1,result='PASS',exit_code=0,grant_delay=s%100+1,response_delay=(s*7)%100+1)
                        for s in range(i*100,(i+1)*100)]) for i in range(10)]
    assert len(assemble(shards,expected))==1000;checks=1
    bad=[]
    bad.append(copy.deepcopy(shards[:-1]))
    s=copy.deepcopy(shards);s[1]=copy.deepcopy(s[0]);bad.append(s)
    s=copy.deepcopy(shards);s[2]['seeds'].pop();bad.append(s)
    s=copy.deepcopy(shards);s[3]['seeds'][0]['result']='FAIL';bad.append(s)
    s=copy.deepcopy(shards);s[4]['seeds'][0]['exit_code']=1;bad.append(s)
    s=copy.deepcopy(shards);s[5]['sources']={'other':'hash'};bad.append(s)
    s=copy.deepcopy(shards);s[6]['tool']='Vivado/XSim 2023.2';bad.append(s)
    s=copy.deepcopy(shards);s[7]['seeds'][0]['sv_seed']=0;bad.append(s)
    s=copy.deepcopy(shards)
    for shard in s:
        for row in shard['seeds']:row.update(grant_delay=1,response_delay=1)
    bad.append(s)
    for s in bad:
        try:assemble(s,expected)
        except ValueError:checks+=1
        else:raise AssertionError('invalid shard set accepted')
    with tempfile.TemporaryDirectory() as td:
        root=Path(td);p=root/'seed.log';p.write_text(good_log(0))
        row=dict(seed=0,grant_delay=1,response_delay=100,log='seed.log',sha256=hashlib.sha256(p.read_bytes()).hexdigest())
        assert check_log(root,row)==p;checks+=1
        for wrong in [dict(row,sha256='wrong'),dict(row,log='../escape.log'),dict(row,grant_delay=2)]:
            try:check_log(root,wrong)
            except ValueError:checks+=1
            else:raise AssertionError('bad raw log accepted')
        p.write_text(good_log(0).replace('RESULT : PASS','RESULT : FAIL'))
        wrong=dict(row,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
        try:check_log(root,wrong)
        except ValueError:checks+=1
        else:raise AssertionError('failed bench accepted')
    assert checks==15
    original=campaign.run
    try:
        for mode in ('shutdown_once','bench_fail','timeout','shutdown_twice'):
            with tempfile.TemporaryDirectory() as td:
                out=Path(td);calls=[]
                def fake_run(cmd,cwd,log,timeout):
                    if '-version' in cmd:log.write_text('Vivado Simulator v2024.1\n');return
                    if not str(cmd[0]).endswith('xsim.bat'):log.write_text('fake compilation');return
                    seed=int(cmd[cmd.index('-testplusarg')+1].split('=')[1]);calls.append(seed)
                    assert int(cmd[cmd.index('-sv_seed')+1])==seed+1
                    target=Path(cmd[cmd.index('-log')+1]);target.write_text(good_log(seed))
                    log.write_text('synthetic process output')
                    if mode=='timeout':raise RuntimeError('owned tool timeout')
                    if mode=='bench_fail':
                        target.write_text(good_log(seed).replace('RESULT : PASS','RESULT : FAIL'))
                        raise campaign.ToolFailure(1,log)
                    if seed==0 and (mode=='shutdown_twice' or calls.count(0)==1):raise campaign.ToolFailure(1,log)
                campaign.run=fake_run
                try:
                    with contextlib.redirect_stdout(io.StringIO()):campaign.execute_campaign(out,0,100)
                except (ValueError,RuntimeError):
                    assert mode!='shutdown_once'
                    assert len(calls)==(2 if mode=='shutdown_twice' else 1)
                    assert not (out/'seed_results.json').exists()
                else:
                    assert mode=='shutdown_once'
                    records=json.loads((out/'seed_results.json').read_text())
                    assert len(records['seeds'])==100 and records['seeds'][0]['attempt']==2
                    assert len(records['failed_attempts'])==1 and len(calls)==101
                checks+=1
    finally:campaign.run=original
    assert checks==19
    print('SEED_SHARD_CONTROLS: PASS checks=19')

if __name__=='__main__':main()
