"""Fail-closed campaign parser controls; no simulator invoked."""
from seed_campaign import judge_seed,judge_ledger,judge_version,windows_command,system_awake

def main():
    states=[]
    def set_state(flags):states.append(flags);return 1
    with system_awake(set_state):pass
    assert states==[0x80000001,0x80000000]
    states.clear()
    try:
        with system_awake(set_state):raise ValueError('simulated failure')
    except ValueError:pass
    assert states==[0x80000001,0x80000000]
    try:
        with system_awake(lambda flags:0):raise AssertionError('failed power request accepted')
    except RuntimeError:pass
    print('SEED_POWER_LIFETIME_TESTS: PASS checks=3')
    judge_version('Vivado Simulator v2024.1\n')
    for bad in ['Vivado Simulator v2023.2\n','Vivado Simulator v2024.10\n','',
                'Vivado Simulator v2024.1\nVivado Simulator v2024.1\n']:
        try:judge_version(bad)
        except ValueError:pass
        else:raise AssertionError('accepted unproven simulator version')
    print('SEED_TOOL_VERSION_TESTS: PASS checks=5')
    line=windows_command(['C:\\tool dir\\xsim.bat','-testplusarg','seed=0','C:\\run\\run.tcl'])
    assert '"seed=0"' in line and '"C:/run/run.tcl"' in line and '\\' not in line
    for arg in ['bad"quote','%EXPAND%','bad\nline','bad\rline']:
        try:windows_command([arg])
        except ValueError:pass
        else:raise AssertionError('accepted unsupported command argument')
    print('SEED_COMMAND_TESTS: PASS checks=5')
    good='RESULT : PASS\nCHECKS : 2\nErrors = 0\nSEED_RESULT seed=3 completed=1 errors=0\nSEED_LATENCY seed=3 grant=1 response=100\n$finish called\n'
    for bad in [good.replace('grant=1','grant=0'),good.replace('response=100','response=101'),
                good+'SEED_LATENCY seed=3 grant=1 response=100\n',good.replace('SEED_LATENCY seed=3 grant=1 response=100\n',''),
                good.replace('response=100','response=0')]:
        try:judge_seed(bad,3)
        except ValueError:pass
        else:raise AssertionError('invalid delay observations accepted')
    print('SEED_DELAY_CONTROLS: PASS checks=5')
    judge_seed(good,3);checks=1
    for text,seed in [(good,4),(good.replace('PASS','FAIL'),3),(good.replace('Errors = 0','Errors = 1'),3),
                      (good+'RESULT : PASS\n',3),(good.replace('$finish called',''),3),(good+'TB_TIMEOUT\n',3)]:
        try:judge_seed(text,seed)
        except ValueError:checks+=1
        else:raise AssertionError('accepted bad seed log')
    rows=[dict(seed=i,result='PASS') for i in range(1000)];judge_ledger(rows);checks+=1
    for bad in [rows[:-1],rows+[rows[0]],[dict(seed=0,result='PASS')]*1000,[dict(seed=i,result='FAIL') for i in range(1000)]]:
        try:judge_ledger(bad)
        except ValueError:checks+=1
        else:raise AssertionError('accepted incomplete or failed ledger')
    assert checks==12
    print('SEED_CAMPAIGN_TESTS: PASS checks=12')
if __name__=='__main__':main()
