"""Freeze phase-0 measurements after its five registered baseline jobs passed."""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
e=ROOT/'reports/dual_lane_10_20261113_201237_72e458c9/status.json'
s=json.loads(e.read_text())
reg=json.loads((ROOT/'scripts/dual_lane_jobs.json').read_text())
assert reg['active_increment']=='R10-P0'
assert all(s['jobs'][j]['state']=='PASS_FRESH' for j in reg['increments']['R10-P0'])
p=ROOT/'scripts/prepare_dual_lane.py';t=p.read_text()
anchor="    return dict(schema=2,active_increment='R10-P0',jobs=jobs,increments="
assert t.count(anchor)==1
block='''    r10cov=[]
    # Diagnostic gap confirmation is NOT implementation acceptance.
    fetch_sources=['rtl/dual_lane/NOC_PKG.sv']+[
        'rtl/riscv/'+f for f in ['picorv32.v','picorv32_adapter.sv','addr_decode.sv','uart_tx.sv',
        'uart_mmio.sv','gpio.sv','tile_status.sv','tile_top.sv','mem_bram.sv','tile_mem_wrapper.sv',
        'tmem_app_bridge.sv','meas_window_reader.sv','cpu_tile_noc.sv']]+['sim_riscv/tb_r10_mmio_fetch.sv']
    jobs.append(dict(id='r10_fetch_scope',kind='python',script='scripts/run_r10_fetch_scope.py',
        sources=[],oracle_files=fetch_sources+['scripts/run_r10_coverage.py','scripts/seed_campaign.py',
        'scripts/make_merged_sources.py'],dependencies=[],independent=True,selection='r10cov',
        checks=6,checks_basis='Two diagnostic variants, three observations each; not a release acceptance gate',
        sim_timeout=1200,output_argument=True,positive_marker=r'^R10_FETCH_SCOPE: GAP_CONFIRMED cases=2 checks_per_case=3$'))
    r10cov.append('r10_fetch_scope')
    cov_inputs=set()
    for jid in ['i21_merged_closure','i23_inflight','i23_contention']:
        j=next(j for j in jobs if j['id']==jid)
        cov_inputs.update(j['sources']+j.get('oracle_files',[]))
    cov_inputs.update(['scripts/seed_campaign.py','scripts/run_r10_coverage.py','scripts/test_r10_coverage.py'])
    jobs.append(dict(id='r10_code_coverage',kind='python',script='scripts/run_r10_coverage.py',
        sources=[],oracle_files=sorted(cov_inputs),dependencies=[],independent=True,selection='r10cov',
        checks=28,checks_basis='Unchanged 14+6+8 behavioral checks; coverage measurement has no percentage target',
        sim_timeout=14400,output_argument=True,positive_marker=r'^R10_COVERAGE: PASS benches=3 target=measurement_only$'))
    r10cov.append('r10_code_coverage')
'''
t=t.replace(anchor,block+anchor.replace("'R10-P0'","'R10-COV'"))
assert t.count("'R10-P0':r10p0}")==1
t=t.replace("'R10-P0':r10p0}","'R10-P0':r10p0,'R10-COV':r10cov}")
p.write_text(t,encoding='utf-8',newline='\n')
p=ROOT/'docs/decisions/dual_lane_config.json';c=json.loads(p.read_text())
assert c['active_increment']=='R10-P0';c['active_increment']='R10-COV'
p.write_text(json.dumps(c,indent=2)+'\n',encoding='utf-8',newline='\n')
print('R10-COV configured after baseline PASS; regenerate once before first execution')
