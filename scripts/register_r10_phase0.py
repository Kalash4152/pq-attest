"""One-time registry preparation for the approved rev-10 baseline replay."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = ROOT / 'scripts/prepare_dual_lane.py'
t = p.read_text(encoding='utf-8-sig')
anchor = "    return dict(schema=2,active_increment='I-26',jobs=jobs,increments="
assert t.count(anchor) == 1, 'registry generator is not the expected I-26 baseline'
block = '''    # Rev-10 phase 0: explicit fresh re-adjudication; historical jobs stay unchanged.
    r10p0=[]
    remap={old:'r10p0_'+old for old in ['i21_merged_closure','i23_inflight','i23_inflight_control','i23_contention','i23_contention_control']}
    for old,new in remap.items():
        j=json.loads(json.dumps(next(j for j in jobs if j['id']==old)))
        j.update(id=new,selection='r10p0')
        j['dependencies']=[remap.get(d,d) for d in j.get('dependencies',[])]
        jobs.append(j);r10p0.append(new)
'''
t = t.replace(anchor, block + anchor.replace("'I-26'", "'R10-P0'"))
assert t.count("'I-26':i26}") == 1
t = t.replace("'I-26':i26}", "'I-26':i26,'R10-P0':r10p0}")
p.write_text(t, encoding='utf-8', newline='\n')
p=ROOT/'docs/decisions/dual_lane_config.json'
c=json.loads(p.read_text()); assert c['active_increment']=='I-26'
c['active_increment']='R10-P0'
p.write_text(json.dumps(c,indent=2)+'\n',encoding='utf-8',newline='\n')
print('R10-P0 configured; run prepare_dual_lane.py once before the first execution')
