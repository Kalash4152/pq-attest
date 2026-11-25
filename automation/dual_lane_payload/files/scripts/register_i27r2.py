"""Fresh I-27 requalification; original run and all frozen counts remain unchanged."""
import copy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def append_jobs(jobs):
    base={j['id']:j for j in jobs};ids=[j['id'] for j in jobs if j.get('selection')=='I-27']
    remap={n:n.replace('i27_','i27r2_',1) for n in ids};new=[]
    for n in ids:
        j=copy.deepcopy(base[n]);j.update(id=remap[n],selection='I-27-R2')
        j['dependencies']=[remap.get(d,d) for d in j.get('dependencies',[])]
        if n=='i27_attack_approve_changed':
            j['top']='tb_merged_attack_v10_v2';j['config']['TOP']=j['top']
            j['sources']=[p.replace('tb_merged_attack_v10.sv','tb_merged_attack_v10_v2.sv') for p in j['sources']]
        if n=='i27_mutation_controls':j['script']='scripts/test_r10_mutations_v2.py'
        if n=='i27_matched_data':j['script']='scripts/collect_matched_latency_i27r2.py'
        if n=='i27_gate_negative':j['script']='scripts/run_merged_gate_controls_i27r2.py'
        if j['kind']=='python':j['oracle_files']=sorted(set(j['oracle_files']+[j['script'],'scripts/seed_campaign.py']))
        new.append(j)
    positive=next(j for j in new if j['id']=='i27r2_attack_approve_changed');new.remove(positive)
    control=copy.deepcopy(positive);control.update(id='i27r2_attack_control_drop_grant',mutant='rvg_drop_grant',oracle=r'^\[FAIL\] AT_CONTROL_GRANTED',kill_scope=r'^\[FAIL\] AT_CONTROL_',dependencies=[positive['id']],independent=False)
    new=[positive,control]+new
    next(j for j in new if j['id']=='i27r2_board_secure')['dependencies'].append(control['id'])
    assert len(new)==31
    for j in new:jobs.append(j)
    return [j['id'] for j in new]
