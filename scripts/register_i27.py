"""I-27 counts frozen from versioned bench sources before first qualification."""
import copy
from pathlib import Path
import make_merged_sources
ROOT=Path(__file__).resolve().parents[1]
def append_jobs(jobs):
    old={j['id']:j for j in jobs};added=[]
    refs=['scripts/gen_closure_profile_v10.py','scripts/check_closure_profile_v10.py','scripts/rv32_asm.py','scripts/s8_golden.py','sw/riscv/demo_fw_v3.S','vectors/full_chain.svh','vectors/d2_k3_64.svh']
    for pat in ['sim_riscv/include/*v10*.svh','sim_riscv/include/demo_fw_v3*.svh','sw/riscv/*v10*.hex','sw/riscv/demo_fw_v3*.hex','sw/riscv/closure_profile_v10.svh','vectors/*v10*.json']:
        refs += [p.relative_to(ROOT).as_posix() for p in ROOT.glob(pat)]
    refs += [p for p in old['i21_merged_closure']['oracle_files'] if p.startswith('software/')]
    refs=sorted(set(refs))
    def add(j):
        j.update(selection='I-27');jobs.append(j);added.append(j['id']);return j
    def clone(src,name):
        j=copy.deepcopy(old[src]);j.update(id=name,dependencies=[],independent=True);return j
    def py(name,script,marker=None,deps=None,extra=None,out=False):
        j=dict(id=name,kind='python',script='scripts/'+script,sources=[],oracle_files=refs+(extra or []),dependencies=deps or [],independent=not deps,sim_timeout=1800,output_argument=out)
        if marker:j['positive_marker']=marker
        return add(j)
    py('i27_profile','check_closure_profile_v10.py',r'^CLOSURE_PROFILE_V10: PASS')
    py('i27_board_profile','check_merged_board_profile_v10.py',r'^MERGED_BOARD_PROFILE_V10: PASS conditions=10 negative_controls=11$',extra=make_merged_sources.build()[0]+['scripts/merged_bitstream_sources.tcl'])
    py('i27_release_controls','test_merged_release_final_v10.py',r'^MERGED_RELEASE_TESTS_V10: PASS checks=23$',extra=['scripts/merged_release.py'])
    py('i27_mutation_controls','test_r10_mutations.py')
    def sim(name,top,sources,n,config=None):
        return add(dict(id=name,kind='simulation',top=top,sources=sources,checks=n,defines=['PQ_MAC_ON','CPU_TILE_MODULE=cpu_tile_noc'],dependencies=[],independent=True,build_timeout=1200,sim_timeout=3600,include_dirs=['vectors','sim_riscv/include'],tb_time_limit='80ms',config=config or dict(TOP=top,CHECKS=n),oracle_files=refs,checks_basis=f'{n} named checks in versioned source, frozen before first I-27 execution'))
    crypto=[s for s in old['i21_merged_closure']['sources'] if any(x in Path(s).name.lower() for x in ['sha3','keccak'])]
    h=sim('i27_hasher','tb_meas_imem_hasher_v10',crypto+['rtl/riscv/meas_imem_hasher.sv','sim_riscv/tb_meas_imem_hasher_v10.sv'],9)
    d=sim('i27_decoder','tb_addr_decode_v10',['rtl/riscv/addr_decode.sv','sim_riscv/tb_addr_decode_v10.sv'],19)
    cpu=[s for s in old['i21_merged_closure']['sources'] if s.startswith('rtl/riscv/')]
    g=sim('i27_mmio_guard','tb_r10_mmio_guard',['rtl/dual_lane/NOC_PKG.sv']+cpu+['sim_riscv/tb_r10_mmio_guard.sv'],3)
    def mutant(base,name,kind,oracle,scope):
        j=copy.deepcopy(base);j.update(id=name,mutant=kind,oracle=oracle,kill_scope=scope,dependencies=[base['id']],independent=False);return add(j)
    mutant(h,'i27_hasher_control','rvh_skip_word',r'^\[FAIL\] HASH_DIGEST_0',r'^\[FAIL\] HASH_')
    mutant(d,'i27_decoder_control','rvd_fetch_guard_off',r'^\[FAIL\] DEC_FETCH_DMEM_FIRST_DENIED',r'^\[FAIL\] DEC_FETCH_')
    mutant(g,'i27_mmio_control','rvd_fetch_guard_off',r'^\[FAIL\] MMIO_GUARD_FAULT',r'^\[FAIL\] MMIO_GUARD_')
    def merged(src,name):
        j=clone(src,name);top=j['top']+'_v10';j['sources']=[s.replace('/'+j['top']+'.sv','/'+top+'.sv') for s in j['sources']]
        k=j['sources'].index('rtl/riscv/cpu_tile_noc.sv');j['sources'].insert(k,'rtl/riscv/meas_imem_hasher.sv')
        j['top']=top;j['config']['TOP']=top
        if 'FW' in j['config']:j['config']['FW']='demo_fw_v3'
        j['oracle_files']=refs;j['sim_timeout']=3600
        return add(j)
    c=merged('i21_merged_closure','i27_closure')
    merged('i25_final_lifecycle','i27_lifecycle')
    merged('i21_merged_error','i27_error')
    i=merged('i23_inflight','i27_inflight');t=merged('i23_contention','i27_contention');p=merged('i25_phase_sweep','i27_phase_sweep')
    mutant(i,'i27_inflight_control','rvg_ignore_revoke',r'^\[FAIL\] IF_AUTH_BOUNDARY_BOUND',r'^\[FAIL\] IF_')
    mutant(t,'i27_contention_control','rvo_drop_busy',r'^\[FAIL\] CT_CPU_FINISHES',r'^\[FAIL\] CT_')
    mutant(p,'i27_phase_control','rvg_ignore_revoke',r'^\[FAIL\] PH_REVOKE_BOUND_',r'^\[FAIL\] PH_REVOKE_(BOUND|OUTCOME)_')
    src=[s for s in c['sources'] if s!='rtl/dual_lane/merged/tb_merged_closure_v10.sv']
    for mode in ['reject_changed','approve_changed']:
        a=sim('i27_attack_'+mode,'tb_merged_attack_v10',src+['rtl/dual_lane/merged/tb_merged_attack_v10.sv'],6,dict(TOP='tb_merged_attack_v10',CHECKS=6,MODE=mode))
        if mode=='approve_changed':a['defines'].append('R10_APPROVE_ATTACK')
    j=clone('i9_integ','i27_i9_integ');add(j)
    py('i27_project_controls','run_merged_project_controls_v10.py',r'^MERGED_PROJECT_CONTROLS: PASS files=72 idempotent=YES$',extra=make_merged_sources.build()[0]+['scripts/test_merged_project_update_v10.tcl','scripts/final_project_update.tcl','scripts/merged_project_update.tcl','scripts/merged_bitstream_sources.tcl','scripts/seed_campaign.py','scripts/check_merged_board_profile_v10.py'],out=True)
    for mode in ['secure','fixed','secure_contended','fixed_contended']:
        merged('i25_matched_'+mode,'i27_matched_'+mode)
    py('i27_matched_data','collect_matched_latency_v10.py',r'^MATCHED_COMPARISON: PASS modes=4 transactions_per_mode=64$',deps=['i27_matched_'+m for m in ['secure','fixed','secure_contended','fixed_contended']]+['i27_phase_sweep'],extra=['scripts/matched_latency.py'],out=True)
    j=clone('i25_board_secure','i27_board_secure');j['sources']=make_merged_sources.build()[0];j['oracle_files']=sorted(set(j['oracle_files']+refs));j.update(dependencies=list(added),independent=False);add(j)
    py('i27_gate_negative','run_merged_gate_controls_v10.py',r'^MERGED_GATE_CONTROLS: PASS cases=6$',deps=['i27_board_secure'],extra=['scripts/test_merged_board_gate.tcl','scripts/merged_board_gate.tcl','scripts/seed_campaign.py'],out=True)
    return added
