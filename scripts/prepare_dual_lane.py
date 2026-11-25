"""Prepare pinned registry/payload; explicitly invoked during development, never by launcher."""
import json
from pathlib import Path
import shutil
from dual_lane import ROOT, atomic
from dual_lane_verify import sha
from prepare_n6_credit_window import generate as generate_credit_window, OUTPUT as CREDIT_WINDOW

S='NOC_PQATTEST.srcs/sources_1/new/'
T='NOC_PQATTEST.srcs/sim_1/new/'
NOC=[S+f for f in ['NOC_PKG.sv','NOC_FIFO.sv','NOC_CROSSBAR.sv','NOC_XY_ROUTING.sv','NOC_arbiter.sv','allocator.sv','noc_credit_counter.sv','NOC_DATAPTAH.sv','noc_router.sv','noc_mesh_3x2.sv','noc_network_interface.sv','noc_addr_decoder.sv']]
CRYPTO=[S+f for f in ['pq_keccak_pkg.sv','SHA3_PKG.sv','kmac_pkg.sv','pq_kdf_pkg.sv','pq_measurement_pkg.sv','pqattest_stg7_pkg.sv','pq_keccak_theta.sv','pq_keccak_rho.sv','pq_keccak_pi.sv','pq_keccak_chi.sv','pq_keccak_iota.sv','pq_keccak_round.sv','pq_keccak_f1600.sv','SHA3_PAD.sv','SHA3_ABSORB.sv','SHA3_256.sv','kmac_encode.sv','kmac_absorb.sv','kmac_128.sv','pq_kdf.sv','pq_measurement.sv','pqattest_stg7.sv','pq_attest_protocol.sv']]
# D-SYN-1 (docs/decisions/D-SYN-1-crypto-synth-fixes.md): synthesizable rtl/dual_lane variants replace two protected
# crypto originals in synthesis and D-SYN-1 regression lists. The originals are never written.
DSYN1_SUB={S+'pq_keccak_iota.sv':'rtl/dual_lane/pq_keccak_iota.sv',S+'SHA3_PAD.sv':'rtl/dual_lane/SHA3_PAD.sv'}
CRYPTO_SYN=[DSYN1_SUB.get(s,s) for s in CRYPTO]
DSYN1_BASIS='D-SYN-1 variant source list (frozen count unchanged from the production-list job)'
# D-SYN-2 (docs/decisions/D-SYN-2-measurement-architecture.md, Option 2): byte-serial pq_measurement variant on top of D-SYN-1.
DSYN2_SUB=dict(DSYN1_SUB); DSYN2_SUB[S+'pq_measurement.sv']='rtl/dual_lane/pq_measurement.sv'
CRYPTO_SYN2=[DSYN2_SUB.get(s,s) for s in CRYPTO]
DSYN2_BASIS='D-SYN-1+2 variant source list (frozen count unchanged from the production-list job)'
# Equivalence bench count (frozen from source before the first run): 65 config_len x 65 imem_len x 4 patterns, 2 checks per
# run (digest, exact latency), plus 9 protocol checks. tb_dsyn2_measurement_equiv.sv header gives the derivation.
DSYN2_EQ_CHECKS=65*65*4*2+9
DSYN2_EQ_BASIS='65 x 65 x 4 patterns x (digest + exact latency) + 9 protocol checks (D-SYN-2)'
def job(jid,top,sources,checks,**kw):
    return dict(id=jid,kind='simulation',top=top,sources=sources,checks=checks,defines=[],dependencies=[],independent=True,build_timeout=1200,sim_timeout=600,**kw)

# I-2 (PQ-1 V7-V10). Teammate reference modules that the V7 adapter imports
# (transitive closure of derive_tile_key / measure_tile / generate_attestation_tag /
# tile_respond / verifier_check). Replaces the demoted repo software/kmac128_ref.py.
TEAMMATE='software/pq_attest_final/PQ_Attest/software/'
ADAPTER_REF=[TEAMMATE+f for f in ['kmac128_ref.py','keccak_ref.py','sha3_256_ref.py','measurement_ref.py','attestation_ref.py','attestation_protocol.py']]
S8_ORACLE=['scripts/s8_golden.py']+ADAPTER_REF+['vectors/s8_golden.json','vectors/s8_golden.svh']
# Frozen V9 count of the CURRENT tb_stg_8_golden.sv (8x7 + 4x3 + 3x(2+7) = 95).
# If reports/i2_track_c/tb_stg_8_golden.proposed.sv is adopted, refreeze to 174
# and map key_length -> KEY before the first run.
S8_CHECKS=95
S8_MUTANTS=[('lost_measurement','MEASUREMENT'),('lost_tag','TAG'),('key_length','TAG'),('wrong_transcript','TAG'),('field_order','EPOCH'),('stale_nonce','NONCE'),('wrong_key','TAG')]
# post_format_compat: every production job that compiles NOC_PKG is re-run with
# the Q-C variant package substituted (never both packages in one list).
VARIANT_PKG='rtl/dual_lane/NOC_PKG.sv'
# Benches whose packet sets / check loops are derived from message_length() or
# message_payload_flits() and which drive an NI with attestation traffic: the
# challenge length change (5->7) can change their count, so no prior count exists.
PFC_FREEZE_REQUIRED=set()
# Frozen 2026-10-19 from TB source, before any pfc run (reports/I2_PFC_COUNT_DERIVATION_20261019.md):
# check() call counts depend only on W/MAC_FLITS/RUNS/WDE; the 5->7 challenge payload changes
# compared values only (tb_ni_n81 :353-366, :375-397, :636-657, :728-735), and ni_tb / tb_noc_n81
# never reference the challenge. Counts therefore equal the I-1 values.
PFC_DERIVED={'n81_ni_m0w16','n81_ni_m0w1','n81_ni_m1w16','n81_ni_m1w1','n81_nitb','n81_sys_m0w16','n81_sys_m0w64','n81_sys_m0n0','n81_sys_m1w16','n81_sys_m1n0'}
PFC_DEFERRED={'perf_m0','perf_m1'}  # production perf jobs not yet accepted; belongs with NOC-2 (I-3)
# I-3 / PQ-2 endpoint (Track Q2). Counts frozen 2026-10-19 from TB source BEFORE any run:
# reports/i3_q2/Q2_COUNT_DERIVATION.md (unit 275, system 37). Mutant anchors: mutation() ep_* kinds.
EP_UNIT_CHECKS=275
EP_SYS_CHECKS=37
EP_MUTANTS=[('tag_swap','^\\[FAIL\\] \\S+_TAG_WORDS$'), ('nonce_offset','^\\[FAIL\\] \\S+_EPOCH_NONCE_FIELDS$'), ('wrong_reply','^\\[FAIL\\] REPLY_TO_LATCHED$'), ('rx_stall','^\\[FAIL\\] RX_READY_ALWAYS$')]
EP_ORACLE=['scripts/endpoint_golden.py','scripts/s8_golden.py','scripts/full_chain_golden.py']+ADAPTER_REF+['vectors/endpoint_golden.json','vectors/endpoint_golden.svh','vectors/full_chain.json','vectors/full_chain.svh']

# ---------------------------------------------------------------------------
# NOC-2 (I-3). Counts and observations frozen 2026-10-19 from TB source before any run:
# reports/i3_n2/N2_COUNT_DERIVATION.md. Bench: tb_noc_perf.sv generated by
# scripts/prepare_perf_bench.py from scripts/perf_bench_body.sv.inc.
# ---------------------------------------------------------------------------
PERF_TB=T+'tb_noc_perf.sv'
PERF_TAGS=dict(transport='MF1-rev5',w=64,wde=1,seed='0x12345678',n_out=2,tool='xsim-2024.1')
PERF_PERIODS=[64,32,16,8,4,2,1]
N2_POINT_CHECKS=14
PERF_CHECKS=1+28*N2_POINT_CHECKS   # CFG_N_OUTSTANDING + 14 point checks x 28 points = 393
N2_ORACLE=['scripts/prepare_perf_bench.py','scripts/perf_bench_body.sv.inc','reports/i3_n2/N2_COUNT_DERIVATION.md','reports/i3_n2/N2_AMEND1_DERIVATION.md','docs/decisions/N-8-performance-plan-amend-1.md']
N2_BASIS='derived from TB source before first run (reports/i3_n2/N2_COUNT_DERIVATION.md; OD-6 amendment 1: reports/i3_n2/N2_AMEND1_DERIVATION.md)'
def perf_cfg(case,points,mac):
    return dict(TOP='tb_noc_perf',CASE=case,POINTS=points,MAC_FLITS=4*mac,SEED=305419896,CLOCK_NS=20,W=64,WDE=1,N_OUTSTANDING=2,
                TRANSPORT='MF1-rev5',TOOL='xsim-2024.1',WARMUP=128,MEASURE=2048,DRAIN=50000,CAP=256,LIVE_WINDOW=1024)
def clean_point(case,pattern,period,offered,queued,mem):
    """Fully accounted, idle, all credits returned: every queued record accepted, injected and delivered once."""
    return dict(case=case,pattern=pattern,period=period,max=dict(drain_cycles=50000),
                exact=dict(offered=offered,queued=queued,cap_drops=offered-queued,accepted=queued,injected=queued,delivered=queued,
                           responses=mem,mem_accepted=mem,missing=0,unsent=0,duplicate=0,mismatched=0,unknown=0,
                           credits_returned=1,idle_after_drain=1,verdict='OK'))
# OD-6 amendment 1 (docs/decisions/N-8-performance-plan-amend-1.md): hotspot (2) and transpose (1) sources whose
# destination is themselves stay idle (offered=0). Active sources: uniform 6, transpose 4 (0 and 5 idle), hotspot 5
# (2 idle), neighbor 6. Derivation: reports/i3_n2/N2_AMEND1_DERIVATION.md.
PERF_ACTIVE_SOURCES={0:6,1:4,2:5,3:6}
def perf_matrix_points():
    pts=[]
    for pattern in range(4):
        for period in PERF_PERIODS:
            n=PERF_ACTIVE_SOURCES[pattern]; per_src=2176//period; queued=n*min(per_src,256)
            pts.append(clean_point('perf',pattern,period,n*per_src,queued,queued))
    return pts
N2_CONTROLS=['perf_ctrl_corrupt','perf_ctrl_drop','perf_ctrl_stall']
N2_N75=['n75_sat_vc2_m0','n75_sat_vc2_m1','n75_reset_m0','n75_reset_m1','n75_second_challenge_m0','n75_second_challenge_m1']
# NOC-2 isolated hop probes (I-3 / Track HP; N-8 "isolated hop probes are a separate subgate").
# Counts and required lines frozen 2026-10-20 from TB source before any run:
# reports/i3_hp/HP_COUNT_DERIVATION.md. Standalone bench, production transport (M-F1 rev 5), no L2.
HOP_TB=T+'tb_noc_hop_probes.sv'
HOP_ORACLE=['reports/i3_hp/HP_COUNT_DERIVATION.md','reports/i3_hp/check_hop_bench_static.py']
HOP_BASIS='derived from TB source before first run (reports/i3_hp/HP_COUNT_DERIVATION.md)'
# (vc, msg_type code, payload flits) from NOC_PKG: MEM_WR_REQ, MEM_WR_RESP (answers the VC0 probe), ATTEST_CHALLENGE.
HOP_VCS=[(0,2,2),(1,3,0),(2,4,5)]
# Ordered pairs without local loopback: noc_router a_no_loopback_local_sync makes LOCAL->LOCAL an error.
HOP_PAIRS=[(a,b) for a in range(6) for b in range(6) if a!=b]
def hop_count(s,d): return abs(s%3-d%3)+abs(s//3-d//3)   # tile index = y*3+x
HOP_PROBES=len(HOP_PAIRS)*len(HOP_VCS)                    # 90
HOP_HOPS=sorted({hop_count(a,b) for a,b in HOP_PAIRS})    # [1,2,3]
HOP_CLASSES=len(HOP_VCS)*len(HOP_HOPS)                    # 9
HOP_CHECKS=2+6*HOP_PROBES+HOP_CLASSES+2*len(HOP_VCS)      # 2 global + 6/probe + 1/class + 2/VC = 557
def hop_cfg(mac):
    return dict(TOP='tb_noc_hop_probes',CASE='hop_probes',transport='MF1-rev5',l2='none',w=64,wde=1,n_out=2,tool='xsim-2024.1',
                MAC_FLITS=4*mac,CLOCK_NS=20,PAIRS=len(HOP_PAIRS),PROBES=HOP_PROBES,CLASSES=HOP_CLASSES,LOOPBACK=0)
def hop_required_lines(mac):
    lines=[]
    for a,b in HOP_PAIRS:
        for vc,msg,pay in HOP_VCS:
            s,d=(b,a) if vc==1 else (a,b)   # the VC1 probe answers the a->b request: b->a
            lines.append([rf'^HOP_PROBE id=\d+ src={s} dst={d} vc={vc} msg={msg} hops={hop_count(s,d)} flits={1+pay+4*mac} t_inj=\d+ t_del=\d+ latency=[1-9]\d* mac={mac} ok=1$',1])
    lines.append([r'^HOP_PROBE ',HOP_PROBES])
    for vc,_,_ in HOP_VCS:
        for h in HOP_HOPS:
            n=sum(1 for a,b in HOP_PAIRS if hop_count(a,b)==h)   # 14 / 12 / 4
            lines.append([rf'^HOP_CLASS vc={vc} mac={mac} hops={h} probes={n} latency=[1-9]\d* min=[1-9]\d* max=[1-9]\d* deterministic=1$',1])
    lines.append([r'^HOP_CLASS ',HOP_CLASSES])
    lines.append([rf'^HOP_SUMMARY mac={mac} loopback=0'+''.join(rf' vc{vc}_per_hop=[1-9]\d* vc{vc}_hop1=[1-9]\d* vc{vc}_zero_hop=NA' for vc,_,_ in HOP_VCS)+r' monotonic=1 const_increment=1$',1])
    lines.append([r'^HOP_CONTENTION ',0])
    return lines
HOP_JOBS=['hop_probes_m0','hop_probes_m1']
N2_I3=['perf_m0','perf_m1']+N2_CONTROLS+N2_N75+['perf_matrix']+HOP_JOBS

def noc2_jobs():
    """Control and N-7.5 jobs (added after the pfc block, so they get no post_format_compat variants)."""
    jobs=[]
    def sim(jid,defines,case,checks,mac,points,**kw):
        j=job(jid,'tb_noc_perf',NOC+[PERF_TB],checks,selection='I-3',config=perf_cfg(case,1,mac),tb_time_limit='200ms',oracle_files=N2_ORACLE)
        j.update(defines=defines,sim_timeout=1800,point_accounting=dict(mac=mac,tags=PERF_TAGS,points=points),checks_basis=N2_BASIS,**kw)
        jobs.append(j)
    def fail(name,case,pat,per): return r'^\[FAIL\] '+name+' case='+case+' pattern='+str(pat)+' period='+str(per)+r' mac=0$'
    # Control 1: data word bit 3 (sequence field) of record (1,5) flipped at the tile TX boundary.
    c=clean_point('ctrl_corrupt',0,16,816,816,816); c['exact'].update(mismatched=1,verdict='FAIL')
    sim('perf_ctrl_corrupt',['PERF_CTRL_CORRUPT'],'ctrl_corrupt',1+N2_POINT_CHECKS,0,[c],tb_control=dict(errors=2,
        oracle=[r'^CONTROL_APPLIED kind=corrupt_payload scope=tile_tx source=1 seq=5 word=1 bit=3 cycle=\d+$',
                r'^\[FAIL\] SCOREBOARD_PAYLOAD source=1 seq=5 dst=4 word=1 exp=140c0005 got=140c000d$',
                fail('PERF_NO_MISMATCH','ctrl_corrupt',0,16),r'^CONTROL_SUMMARY case=ctrl_corrupt applied=1$'],
        allowed_fail=[r'^\[FAIL\] SCOREBOARD_PAYLOAD source=1 seq=5 ',r'^\[FAIL\] PERF_NO_MISMATCH '],
        forbid=[r'^LIVENESS_FIRED',r'SCOREBOARD_(MISSING|DUPLICATE|UNKNOWN|ADDRESS|TYPE|LENGTH)',r'UNEXPECTED_CONTAINMENT']))
    # Control 2: generator record (3,9) removed between generator and NI (whole packet, no wormhole truncation).
    d=clean_point('ctrl_drop',0,16,816,816,815)
    d['exact'].update(accepted=815,injected=815,delivered=815,missing=1,verdict='FAIL')
    sim('perf_ctrl_drop',['PERF_CTRL_DROP'],'ctrl_drop',1+N2_POINT_CHECKS,0,[d],tb_control=dict(errors=3,
        oracle=[r'^CONTROL_APPLIED kind=drop_packet scope=generator_to_ni source=3 seq=9 cycle=\d+$',
                r'^\[FAIL\] SCOREBOARD_MISSING source=3 seq=9 dst=0 kind=2$',
                fail('PERF_ACCEPTED','ctrl_drop',0,16),fail('PERF_NO_MISSING','ctrl_drop',0,16),r'^CONTROL_SUMMARY case=ctrl_drop applied=1$'],
        allowed_fail=[r'^\[FAIL\] SCOREBOARD_MISSING source=3 seq=9 ',r'^\[FAIL\] PERF_ACCEPTED ',r'^\[FAIL\] PERF_NO_MISSING '],
        forbid=[r'^LIVENESS_FIRED',r'SCOREBOARD_(MISSING_MORE|PAYLOAD|DUPLICATE|UNKNOWN|ADDRESS|TYPE|LENGTH)',r'UNEXPECTED_CONTAINMENT']))
    # Control 3: memory stand-in of tile 2 stops consuming (issues no responses) from cycle 512, hotspot 1/16.
    st=dict(case='ctrl_stall',pattern=2,period=16,min=dict(unsent=1),
            exact=dict(offered=680,queued=680,cap_drops=0,missing=0,duplicate=0,mismatched=0,unknown=0,  # amend-1: 5 sources x 136
                       credits_returned=1,idle_after_drain=0,drain_cycles=0,verdict='FAIL'))
    sim('perf_ctrl_stall',['PERF_CTRL_STALL'],'ctrl_stall',1+N2_POINT_CHECKS,0,[st],tb_control=dict(errors=6,
        oracle=[r'^CONTROL_APPLIED kind=stall_consumption scope=memory_service tile=2 cycle=512$',
                r'^LIVENESS_FIRED case=ctrl_stall pattern=2 period=16 mac=0 cycle=\d+ reason=no_progress window=1024 first_pending_tile=0 ds_mask=3b queue_mask=3b resp_backlog_mask=04 slot_mask=3b inflight=0$',
                fail('PERF_ACCEPTED','ctrl_stall',2,16),fail('PERF_RESPONSES','ctrl_stall',2,16),fail('PERF_IDLE_AFTER_DRAIN','ctrl_stall',2,16),
                fail('PERF_BOUNDED_DRAIN','ctrl_stall',2,16),fail('PERF_NO_LIVENESS','ctrl_stall',2,16),r'^CONTROL_SUMMARY case=ctrl_stall applied=1$'],
        allowed_fail=[r'^\[FAIL\] PERF_(ACCEPTED|RESPONSES|IDLE_AFTER_DRAIN|BOUNDED_DRAIN|NO_LIVENESS) case=ctrl_stall '],
        forbid=[r'reason=drain_bound',r'SCOREBOARD_',r'UNEXPECTED_CONTAINMENT']))
    # N-7.5 finite-liveness cases, both MAC framings.
    for mac in (0,1):
        md=['PQ_MAC_ON'] if mac else []
        sim(f'n75_sat_vc2_m{mac}',md+['N75_SAT_VC2'],'n75_sat_vc2',1+N2_POINT_CHECKS+3,mac,[clean_point('n75_sat_vc2',4,1,13056,1536,640)],
            required_lines=[[rf'^N75_SAT_VC2 mac={mac} att_queued=896 att_delivered=896 mem_queued=640 mem_delivered=640 vc2_credit_zero_port_cycles=[1-9]\d*$',1]])
        sim(f'n75_reset_m{mac}',md+['N75_RESET'],'n75_reset',1+4+N2_POINT_CHECKS,mac,[clean_point('n75_reset',0,4,3264,1536,1536)],
            required_lines=[[rf'^N75_RESET phase=A pattern=0 period=4 mac={mac} reset_at=1000 reset_len=5 had_traffic=1 accepted=\d+ delivered=\d+ inflight=\d+ routers_idle=1 links_idle=1 ni_idle=1$',1]])
        sim(f'n75_second_challenge_m{mac}',md+['N75_SECOND_CHALLENGE'],'n75_second_challenge',1+N2_POINT_CHECKS+5,mac,[clean_point('n75_second_challenge',0,16,821,821,816)],
            required_lines=[[rf'^N75_SECOND_CHALLENGE mac={mac} rot_issued=2 rot_responses=2 rot_max_outstanding=1 ep_served=2 ep_drained=1 ep_drained_src=5 responses_to_spoof=0$',1]])
    deps=['perf_m0','perf_m1']+N2_CONTROLS+N2_N75
    jobs.append(dict(id='perf_matrix',kind='python',script='scripts/perf_report.py',output_argument=True,positive_marker=r'^PERF_MATRIX: PASS$',
        sources=['scripts/perf_report.py',PERF_TB]+NOC,dependencies=deps,independent=False,selection='I-3',sim_timeout=600,
        perf_inputs=dict(points=['perf_m0','perf_m1'],controls=N2_CONTROLS,n75=N2_N75),
        scope='56-point matrix + effective controls + N-7.5 cases; Verilator cross-check BLOCKED (not installed)'))
    # N-8 isolated hop probes: one packet per probe in an idle mesh, every ordered non-loopback pair x 3 VCs, both MAC framings.
    for mac in (0,1):
        j=job(f'hop_probes_m{mac}','tb_noc_hop_probes',NOC+[HOP_TB],HOP_CHECKS,selection='I-3-hop',config=hop_cfg(mac),tb_time_limit='10ms',oracle_files=HOP_ORACLE)
        j.update(defines=['PQ_MAC_ON'] if mac else [],sim_timeout=900,required_lines=hop_required_lines(mac),checks_basis=HOP_BASIS)
        jobs.append(j)
    return jobs

def variant_pkg_job(j):
    v=json.loads(json.dumps(j)); pkg=S+'NOC_PKG.sv'
    if v['sources'].count(pkg)!=1 or VARIANT_PKG in v['sources']: raise ValueError('post_format_compat source swap '+j['id'])
    v['sources']=[VARIANT_PKG if p==pkg else p for p in v['sources']]
    v.update(id='pfc_'+j['id'],variant_of=j['id'],selection='pfc'); v.pop('historical_evidence',None)
    if v['kind']=='reuse':
        v.pop('evidence',None); v.update(kind='simulation',build_timeout=1200,sim_timeout=600)
    v['dependencies']=['pfc_'+d for d in v.get('dependencies',[])]
    if j['id'] in PFC_FREEZE_REQUIRED:
        v.update(checks='FREEZE_REQUIRED',unimplemented='post_format_compat: expected count FREEZE_REQUIRED before first run (variant Q-C challenge 5->7 flits)')
    elif j['id'] in PFC_DERIVED:
        v['checks_basis']='derived from TB source 2026-10-19 before first run (reports/I2_PFC_COUNT_DERIVATION_20261019.md); equals frozen '+j['id']
    elif 'checks' in v:
        v['checks_basis']='carried from frozen '+j['id']+'; bench does not reference ATTEST_CHALLENGE_WIDTH or the challenge length'
    if v['kind'] in ('ooc','implementation'):
        # Kalash 2026-10-19 low-memory flow: run last, alone (own selection), one Vivado thread.
        base='scripts/dual_lane_impl.tcl' if v['kind']=='implementation' else 'scripts/dual_lane_export.tcl'
        wrapper='scripts/dual_lane_lowmem_impl.tcl' if v['kind']=='implementation' else 'scripts/dual_lane_lowmem_export.tcl'
        v.update(selection='pfc_synth',child_script=wrapper,max_threads=1,min_free_ram_gb=2.0,min_pagefile_gb=8,ram_gate_basis='Kalash 2026-10-19 (57b7031): mesh impl peaks 2,452-2,499 MB')
        v['oracle_files']=[f for f in v.get('oracle_files',[]) if f!=base]+[base,wrapper]
    return v

def build_registry(check_files=True):
    jobs=[]
    n81=[('ni_m0w16','tb_ni_n81',[],115,dict(W=16,MAC_FLITS=0)),
         ('ni_m0w1','tb_ni_n81',['N81_W=1'],114,dict(W=1,MAC_FLITS=0)),
         ('ni_m1w16','tb_ni_n81',['PQ_MAC_ON'],113,dict(W=16,MAC_FLITS=4)),
         ('ni_m1w1','tb_ni_n81',['PQ_MAC_ON','N81_W=1'],112,dict(W=1,MAC_FLITS=4)),
         ('nitb','tb_noc_ni',[],161,{}),('n6','tb_n6_two_tile_stress',[],126,{}),
         ('sys_m0w16','tb_noc_n81',[],97,dict(W=16,WDE=1,RUNS=7,MAC_FLITS=0)),
         ('sys_m0w64','tb_noc_n81',['N81_W=64','N81_RUNS=1'],43,dict(W=64,WDE=1,RUNS=1,MAC_FLITS=0)),
         ('sys_m0n0','tb_noc_n81',['N81_WDE=0','N81_RUNS=8'],19,dict(W=16,WDE=0,RUNS=8,MAC_FLITS=0)),
         ('sys_m1w16','tb_noc_n81',['PQ_MAC_ON','N81_RUNS=1'],43,dict(W=16,WDE=1,RUNS=1,MAC_FLITS=4)),
         ('sys_m1n0','tb_noc_n81',['PQ_MAC_ON','N81_WDE=0','N81_RUNS=8'],19,dict(W=16,WDE=0,RUNS=8,MAC_FLITS=4))]
    for tag,top,defs,count,cfg in n81:
        tb=T+'tb_ni_n81.sv' if tag.startswith('ni_') else T+'ni_tb.sv' if tag=='nitb' else S+'tb6_1.sv' if tag=='n6' else T+'tb_noc_n81.sv'
        sources=NOC+[tb]
        if tag=='nitb':
            j=job('n81_nitb',top,sources,count,selection='i1');jobs.append(j)
        else:
            jobs.append(dict(id='n81_'+tag,kind='reuse',top=top,sources=sources,defines=defs,checks=count,config=cfg,negative='n0' in tag,dependencies=[],independent=True,evidence='logs/wp0_n81_20261002_000837_37400_2455a286/n81_'+tag))
    for suffix,kind,oracle in [('control_before',None,None),('mut_a','a',r'^\[FAIL\] T11 (head flit held stable|no R1 LOCAL dequeue while ready=0)'),('mut_b_t5','b_t5',r'^\[FAIL\] T5 (credit propagates back to R0 EAST|R0 EAST has credit again)'),('mut_c','c',r'^\[FAIL\] T13 (in_ready_local=0|13th flit NOT taken while full)'),('control_after',None,None)]:
        j=job('wp0_n6_'+suffix,'tb_n6_two_tile_stress',NOC+[CREDIT_WINDOW],126,selection='i1',oracle_files=['scripts/wp0_common.tcl',S+'tb6_1.sv','scripts/prepare_n6_credit_window.py','sim/dual_lane/n6_credit_window/source_delta.json'])
        j['mutation_scope']='credit-loss mutant active only in original T4/T5; all 126 checks retained'
        if kind:
            j.update(mutant='n6_'+kind,oracle=oracle,dependencies=['wp0_n6_control_before'],independent=False)
        if suffix=='control_after':j.update(dependencies=['wp0_n6_control_before','wp0_n6_mut_a','wp0_n6_mut_b_t5','wp0_n6_mut_c'],independent=False)
        jobs.append(j)
    for tag,top,tb,count,defs,pipe in [('n7_pipe1','tb_noc_mesh_n7',S+'tb_noc_mesh.sv',1756,[],1),('n7_pipe0','tb_noc_mesh_n7',S+'tb_noc_mesh.sv',1762,['N7_PIPE0'],0),('m8','tb_noc_router_m9_credit',S+'tb_noc_router_m9_credit.sv',47,[],None),('n6','tb_n6_two_tile_stress',S+'tb6_1.sv',126,[],None),('tb1','tb_noc_stage2',T+'TB1.sv',0,[],None)]:
        j=job('d7_'+tag,top,NOC+[tb],count,selection='d7'); j['defines']=defs
        if pipe is not None: j.update(config={'TB_LINK_PIPE':pipe},config_pattern=r'^\s*(N-7 CONFIG:[^\r\n]+)$',extra_counts=dict(GuardChecks=111,ProtocolErrors=0,InjBlocked=0))
        if tag=='tb1': j.update(judge='tb1')
        jobs.append(j)
    # V8 profile split: teammate 16-byte examples unchanged, and the 32-byte system profile; never mixed.
    jobs.append(dict(id='py_teammate_examples',kind='python',script='scripts/py_teammate_examples.py',output_argument=True,positive_marker=r'^PY_TEAMMATE_EXAMPLES: PASS',sources=['scripts/py_teammate_examples.py','scripts/s8_golden.py']+ADAPTER_REF+[TEAMMATE+'kdf_vectors.py',TEAMMATE+'attestation_vectors.py'],dependencies=[],independent=True,selection='golden',sim_timeout=300,profile='teammate_examples_unchanged'))
    jobs.append(dict(id='py_rtl_profile_32',kind='python',script='scripts/py_rtl_profile_32.py',output_argument=True,positive_marker=r'^PY_RTL_PROFILE_32: PASS',sources=['scripts/py_rtl_profile_32.py','scripts/s8_golden.py']+ADAPTER_REF+['vectors/s8_golden.json','vectors/s8_golden.svh'],dependencies=[],independent=True,selection='golden',sim_timeout=300,tile_key_bytes=32))
    jobs.append(dict(id='s8_python',kind='python',script='scripts/s8_golden.py',positive_marker=r'^ORACLE: PASS',sources=['scripts/s8_golden.py']+ADAPTER_REF+['vectors/s8_golden.json','vectors/s8_golden.svh',T+'pq_kdf_tb.sv',T+'pq_measurement_tb.sv',T+'pqattest_tb.sv'],dependencies=[],independent=True,selection='golden',tile_key_bytes=32))
    g=job('s8_golden','tb_stg_8_golden',CRYPTO+[T+'tb_stg_8_golden.sv'],S8_CHECKS,selection='golden',config=dict(TOP='tb_stg_8_golden',VECTORS=8,RESPONSE_BITS=776,DEMO=1),include_dirs=['vectors'],oracle_files=S8_ORACLE); g['dependencies']=['s8_python']; g['independent']=False; jobs.append(g)
    for m,oracle in S8_MUTANTS:
        j=dict(g,id='s8_mut_'+m,mutant=m,oracle=r'^\[FAIL\] G\d\d_'+oracle); j['dependencies']=['s8_golden']; jobs.append(j)
    after=dict(g,id='s8_control_after'); after['dependencies']=['s8_golden']+['s8_mut_'+m for m,_ in S8_MUTANTS]; jobs.append(after)
    # V10 system-policy layer (outside the immutable reference): both verdicts recorded.
    jobs.append(dict(id='policy_layer',kind='python',script='scripts/policy_layer.py',output_argument=True,positive_marker=r'^POLICY_LAYER: PASS',sources=['scripts/policy_layer.py','scripts/s8_golden.py']+ADAPTER_REF,dependencies=[],independent=True,selection='golden',sim_timeout=300,tile_key_bytes=32))
    jobs.append(dict(id='ni_ooc',kind='ooc',top='noc_network_interface',sources=NOC[:1]+[S+'noc_network_interface.sv'],generics=['-generic','LOCAL_TILE_ID=0 WD_LIMIT=16'],dependencies=[],independent=True,selection='ooc',build_timeout=1800))
    jobs.append(dict(id='mesh_gate',kind='implementation',top='noc_mesh_synth_top',sources=NOC[:10]+['synth/noc_mesh_synth_top.sv'],defines=[],constraints='synth/n25_mesh.xdc',gate_script='scripts/n25_gate.tcl',child_script='scripts/dual_lane_impl.tcl',oracle_files=['synth/n25_mesh.xdc','scripts/n25_gate.tcl','scripts/dual_lane_impl.tcl'],dependencies=[],independent=True,selection='i1',build_timeout=7200,historical_evidence='reports/n25_run3pe_2026-10-02'))
    reference=json.loads((ROOT/'docs/decisions/dual_lane_config.json').read_text())['python_reference']
    jobs.append(dict(id='python_ref',kind='python',script='scripts/python_reference_audit.py',output_argument=True,positive_marker=r'^PYTHON_REFERENCE_AUDIT: PASS$',sources=['scripts/python_reference_audit.py','software/kmac128_ref.py','Pq_Attest_final.zip']+['software/pq_attest_final/'+p for p in reference['members']]+['docs/decisions/PYTHON_REFERENCE_BASELINE.md','docs/verification/PYTHON_RTL_CONTRACT_MATRIX.md'],dependencies=[],independent=True,selection='python_ref',sim_timeout=1200,tile_key_bytes=32))
    for top in ['pq_kdf','pq_measurement','pq_attestation_tag','pq_attestation_controller']:
        # P2 option B: dedicated child script; XDC and child are hashed via oracle_files.
        jobs.append(dict(id='ooc_'+top,kind='ooc',top=top,sources=CRYPTO_SYN2,dependencies=[],independent=True,selection='ooc_meas' if top=='pq_measurement' else 'ooc',dsyn1=True,dsyn2=True,
                         build_timeout=7200 if top=='pq_attestation_controller' else 3600,child_script='scripts/d4_crypto_ooc_child.tcl',
                         constraints='scripts/d4_crypto_ooc.xdc',oracle_files=['scripts/d4_crypto_ooc.xdc','scripts/d4_crypto_ooc_child.tcl']))
    secure_noc=['rtl/dual_lane/NOC_PKG.sv']+[p for p in NOC[1:] if not p.endswith('noc_network_interface.sv')]+['rtl/dual_lane/noc_network_interface.sv']
    # B-3 D: the verifier (edited in place) instantiates the shared-kmac engines, so every list with it carries them.
    KS_FILES=['rtl/dual_lane/pq_kmac_share.sv','rtl/dual_lane/pq_kdf_xk.sv','rtl/dual_lane/pq_attestation_tag_xk.sv']
    secure=secure_noc+CRYPTO+KS_FILES+['rtl/dual_lane/'+f+'.sv' for f in ['noc_l2_auth','pq_attest_endpoint','noc_attest_gate','noc_fault_status','pq_rot_verifier','pq_noc_subsystem']]
    jobs.append(dict(id='chain_python',kind='python',script='scripts/full_chain_golden.py',sources=['scripts/full_chain_golden.py','scripts/s8_golden.py','software/kmac128_ref.py','vectors/full_chain.json','vectors/full_chain.svh'],dependencies=[],independent=True,selection='chain'))
    chain=job('full_chain','tb_pq_full_chain',secure+[T+'tb_pq_full_chain.sv'],16,selection='chain',config=dict(TOP='tb_pq_full_chain',DEMO=1,CLOCK_NS=20),include_dirs=['vectors'],oracle_files=['scripts/full_chain_golden.py','scripts/s8_golden.py','software/kmac128_ref.py','vectors/full_chain.json','vectors/full_chain.svh'])
    chain['defines']=['PQ_MAC_ON'];chain['dependencies']=['chain_python'];chain['independent']=False;jobs.append(chain)
    # I-4: same D4 child as the four crypto tops (P2), now that PQ-2 froze the endpoint (instance `controller`).
    jobs.append(dict(id='endpoint_ooc',kind='ooc',top='pq_attest_endpoint',sources=secure_noc[:1]+CRYPTO_SYN2+['rtl/dual_lane/pq_attest_endpoint.sv'],dependencies=[],independent=True,selection='ooc',build_timeout=7200,dsyn1=True,dsyn2=True,
                     child_script='scripts/d4_crypto_ooc_child.tcl',constraints='scripts/d4_crypto_ooc.xdc',oracle_files=['scripts/d4_crypto_ooc.xdc','scripts/d4_crypto_ooc_child.tcl']))
    # B-1 area budget (Kalash 2026-10-20, before the L2 area redesign): measure, no RTL change. Pass criteria frozen before
    # the first run = the existing OOC gate (latches 0, WNS >= 0, WHS >= 0, cells > 0) plus the child-engine check.
    B1=[dict(id='b1_ooc_kmac128_l2',top='kmac128',sources=CRYPTO_SYN2,generics=['-generic','KEY_BYTES=32','-generic','CUSTOM_BYTES=14','-generic','MSG_BYTES=88']),
        dict(id='b1_ooc_noc_l2_auth',top='noc_l2_auth',sources=secure_noc+CRYPTO_SYN2+['rtl/dual_lane/noc_l2_auth.sv'],generics=[],defines=['PQ_MAC_ON'])]   # P6-S: MAC_ENABLE=1 required (noc_l2_auth.sv:258)
    for b in B1:
        b.update(kind='ooc',dependencies=[],independent=True,selection='b1_ooc',build_timeout=7200,dsyn1=True,dsyn2=True,
                 child_script='scripts/d4_crypto_ooc_child.tcl',constraints='scripts/d4_crypto_ooc.xdc',oracle_files=['scripts/d4_crypto_ooc.xdc','scripts/d4_crypto_ooc_child.tcl'])
        jobs.append(b)
    # I-3 PQ-2: endpoint oracle, unit bench (P6 PKG + crypto + endpoint variant only), system bench
    # (P6 secure list, PQ_MAC_ON), 4 targeted mutants on the unit bench, control after the mutants.
    jobs.append(dict(id='endpoint_python',kind='python',script='scripts/endpoint_golden.py',positive_marker=r'^ENDPOINT_ORACLE: PASS',sources=EP_ORACLE,dependencies=[],independent=True,selection='I-3',sim_timeout=300,tile_key_bytes=32))
    ep_unit=job('pq_endpoint_unit','tb_pq_endpoint_unit',secure_noc[:1]+CRYPTO+['rtl/dual_lane/pq_attest_endpoint.sv',T+'tb_pq_endpoint_unit.sv'],EP_UNIT_CHECKS,selection='I-3',
                config=dict(TOP='tb_pq_endpoint_unit',MAC_FLITS=0,CHALLENGE_LEN=8,VECTORS=6,TILE_KEY_BYTES=32),include_dirs=['vectors'],oracle_files=EP_ORACLE,
                checks_basis='derived from TB source 2026-10-19 before first run (reports/i3_q2/Q2_COUNT_DERIVATION.md)')
    ep_unit['dependencies']=['endpoint_python']; ep_unit['independent']=False; jobs.append(ep_unit)
    ep_sys=job('pq_endpoint_sys','tb_pq_endpoint_sys',secure+[T+'tb_pq_endpoint_sys.sv'],EP_SYS_CHECKS,selection='I-3',
               config=dict(TOP='tb_pq_endpoint_sys',MAC_FLITS=4,CHALLENGE_WIRE_LEN=17,CLOCK_NS=20,TILE_KEY_BYTES=32),include_dirs=['vectors'],oracle_files=EP_ORACLE,
               checks_basis='derived from TB source 2026-10-19 before first run (reports/i3_q2/Q2_COUNT_DERIVATION.md)')
    ep_sys['defines']=['PQ_MAC_ON']; ep_sys['sim_timeout']=1800; ep_sys['dependencies']=['endpoint_python']; ep_sys['independent']=False; jobs.append(ep_sys)
    for m,oracle in EP_MUTANTS:
        j=dict(ep_unit,id='pq_endpoint_mut_'+m,mutant='ep_'+m,oracle=oracle); j['dependencies']=['pq_endpoint_unit']; jobs.append(j)
    ep_after=dict(ep_unit,id='pq_endpoint_control_after'); ep_after['dependencies']=['pq_endpoint_unit']+['pq_endpoint_mut_'+m for m,_ in EP_MUTANTS]; jobs.append(ep_after)
    ep_jobs=['endpoint_python','pq_endpoint_unit','pq_endpoint_sys']+['pq_endpoint_mut_'+m for m,_ in EP_MUTANTS]+['pq_endpoint_control_after']
    for mac in [0,1]:
        j=job('perf_m'+str(mac),'tb_noc_perf',NOC+[PERF_TB],PERF_CHECKS,selection='I-3',config=perf_cfg('perf',28,mac),tb_time_limit='200ms',oracle_files=N2_ORACLE)
        j.update(defines=['PQ_MAC_ON'] if mac else [],sim_timeout=3600,point_accounting=dict(mac=mac,tags=PERF_TAGS,points=perf_matrix_points()),checks_basis=N2_BASIS)
        jobs.append(j)
    # post_format_compat (PQ-1): variant-package re-run of every job compiling the production NOC_PKG.
    pfc=[variant_pkg_job(j) for j in list(jobs) if S+'NOC_PKG.sv' in j.get('sources',[])]
    jobs.extend(pfc)
    pfc_i2=[j['id'] for j in pfc if j['variant_of'] not in PFC_DEFERRED]
    jobs.extend(noc2_jobs())
    # D-SYN-1 equivalence (frozen from source before the first run) and regression on the variant lists.
    D1='sim/dual_lane/dsyn1/'
    jobs.append(dict(id='dsyn1_variants',kind='python',script='scripts/check_dsyn1_variants.py',positive_marker=r'^DSYN1_VARIANTS: PASS',
                     sources=['scripts/check_dsyn1_variants.py','scripts/prepare_dsyn1_variants.py','rtl/dual_lane/variant_provenance.json'],
                     # read (diffed), not compiled together: hashed into the identity via oracle_files, not one HDL source list
                     oracle_files=['rtl/dual_lane/pq_keccak_iota.sv','rtl/dual_lane/SHA3_PAD.sv',S+'pq_keccak_iota.sv',S+'SHA3_PAD.sv',
                                   D1+'sha3_pad_orig_dsyn1.sv',D1+'keccak_iota_orig_dsyn1.sv'],dependencies=[],independent=True,selection='dsyn1',sim_timeout=120))
    jobs.append(job('dsyn1_sha3_pad_equiv','tb_dsyn1_sha3_pad_equiv',[S+'SHA3_PKG.sv',D1+'sha3_pad_orig_dsyn1.sv','rtl/dual_lane/SHA3_PAD.sv',T+'tb_dsyn1_sha3_pad_equiv.sv'],
                    256*2*66,selection='dsyn1',checks_basis='256 valid_bytes x 2 is_final x 66 blocks (D-SYN-1)'))
    jobs.append(job('dsyn1_iota_equiv','tb_dsyn1_iota_equiv',[S+'pq_keccak_pkg.sv',D1+'keccak_iota_orig_dsyn1.sv','rtl/dual_lane/pq_keccak_iota.sv',T+'tb_dsyn1_iota_equiv.sv'],
                    24*64,selection='dsyn1',checks_basis='24 legal rounds x 64 random states (D-SYN-1)'))
    by_id={j['id']:j for j in jobs}
    dsyn1_base=['s8_golden']+['s8_mut_'+m for m,_ in S8_MUTANTS]+['s8_control_after','pq_endpoint_unit','pq_endpoint_sys']
    for b in dsyn1_base:
        v=json.loads(json.dumps(by_id[b])); src=[DSYN1_SUB.get(s,s) for s in v['sources']]
        if src==v['sources'] or any(x in src for x in DSYN1_SUB): raise ValueError('D-SYN-1 substitution failed for '+b)
        # dependencies outside I-4 (s8_python, endpoint_python) are replaced by the D-SYN-1 variant check
        deps=sorted({('dsyn1_'+d) if d in dsyn1_base else 'dsyn1_variants' for d in v.get('dependencies',[])},key=lambda d:(d!='dsyn1_variants',d)) or []
        v.update(id='dsyn1_'+b,variant_of=b,selection='dsyn1',sources=src,dependencies=deps,checks_basis=DSYN1_BASIS)
        if deps: v['independent']=False
        jobs.append(v)
    DSYN1_I4=['dsyn1_variants','dsyn1_sha3_pad_equiv','dsyn1_iota_equiv']+['dsyn1_'+b for b in dsyn1_base]
    # D-SYN-2: variant check, exhaustive digest equivalence (frozen before the first run), regression on the D-SYN-1+2 list.
    D2='sim/dual_lane/dsyn2/'
    jobs.append(dict(id='dsyn2_variant',kind='python',script='scripts/check_dsyn2.py',positive_marker=r'^DSYN2_VARIANT: PASS',
                     sources=['scripts/check_dsyn2.py','scripts/prepare_dsyn2.py','rtl/dual_lane/variant_provenance.json'],
                     oracle_files=['rtl/dual_lane/pq_measurement.sv',S+'pq_measurement.sv',D2+'pq_measurement_orig_dsyn2.sv'],
                     dependencies=[],independent=True,selection='dsyn2',sim_timeout=120))   # same selection as its dependents (as dsyn1_variants)
    eq=job('dsyn2_measurement_equiv','tb_dsyn2_measurement_equiv',CRYPTO_SYN2+[D2+'pq_measurement_orig_dsyn2.sv',T+'tb_dsyn2_measurement_equiv.sv'],
           DSYN2_EQ_CHECKS,selection='dsyn2eq',tb_time_limit='400ms',checks_basis=DSYN2_EQ_BASIS)
    eq['sim_timeout']=2400; jobs.append(eq)
    # Kalash's mutant: off-by-one in the imem source (imem[k-7-config_len+1]); must be killed by the equivalence bench.
    mu=dict(eq,id='dsyn2_mut_imem_off_by_one',mutant='dsyn2_imem_off_by_one',oracle=r'^\[FAIL\] MEAS_EQUIV_DIGEST ',dependencies=['dsyn2_measurement_equiv'],independent=False)
    jobs.append(mu)
    for b in dsyn1_base:
        v=json.loads(json.dumps(by_id[b])); src=[DSYN2_SUB.get(s,s) for s in v['sources']]
        if any(x in src for x in DSYN2_SUB): raise ValueError('D-SYN-2 substitution failed for '+b)
        deps=sorted({('dsyn2_'+d) if d in dsyn1_base else 'dsyn2_variant' for d in v.get('dependencies',[])},key=lambda d:(d!='dsyn2_variant',d))
        v.update(id='dsyn2_'+b,variant_of=b,selection='dsyn2',sources=src,dependencies=deps,checks_basis=DSYN2_BASIS)
        if deps: v['independent']=False
        if b.startswith('s8_') or b.startswith('pq_endpoint'): v['sim_timeout']=max(v.get('sim_timeout',600),1200)
        jobs.append(v)
    DSYN2_I4=['dsyn2_variant','dsyn2_measurement_equiv','dsyn2_mut_imem_off_by_one']+['dsyn2_'+b for b in dsyn1_base]
    # Missing required subgates stay explicit until prepared and executed.
    blockers={'l2_auth':'independent transcript and all targeted security controls required','l3_enforce':'trusted gate controls and fault-register cases required','security_sec_1_4':'SEC-1 to SEC-4 new contract; positive cases and effective targeted bypasses required','N-11':'consume matching PQ-4 security matrix','N-12':'final integrated/reset/stress regression required','N-13':'integrated synthesis/route required'}
    for jid,reason in blockers.items(): jobs.append(dict(id=jid,kind='gate',sources=[],dependencies=[],unimplemented=reason))
    stages=[('NOC-1',[],[j['id'] for j in jobs if j['id'].startswith(('n81_','wp0_','d7_'))]+['ni_ooc','mesh_gate']),
            ('PQ-1',['NOC-1'],['python_ref','py_teammate_examples','py_rtl_profile_32']+[j['id'] for j in jobs if j['id'].startswith('s8_')]+['policy_layer']+pfc_i2),
            ('NOC-2',['NOC-1','PQ-1'],N2_I3),('PQ-2',['NOC-1','PQ-1'],ep_jobs),
            ('PQ-3',['PQ-2'],DSYN1_I4+DSYN2_I4+[j['id'] for j in jobs if j['id'].startswith('ooc_')]+['endpoint_ooc']),
            ('NOC-3',['NOC-2','PQ-1','PQ-2'],['l2_auth']),('NOC-4',['NOC-3','PQ-2'],['l3_enforce']),
            ('PQ-4',['NOC-4','PQ-2'],['security_sec_1_4']),('PQ-5',['PQ-1','PQ-2','PQ-3','PQ-4','NOC-4'],['full_chain']),
            ('NOC-5',['NOC-2','NOC-3','NOC-4','PQ-3','PQ-4','PQ-5'],['N-11','N-12','N-13'])]
    if check_files:
        for j in jobs:
            for p in j.get('sources',[]):
                if not (ROOT/p).is_file(): raise FileNotFoundError(p)
    i1=stages[0][2]+['python_ref']
    if len(i1)!=24 or len(set(i1))!=24:raise ValueError('I-1 requires 23 NOC-1 jobs plus python_ref')
    i2=['py_teammate_examples','py_rtl_profile_32','s8_python','s8_golden']+['s8_mut_'+m for m,_ in S8_MUTANTS]+['s8_control_after']+pfc_i2+['policy_layer']
    ids=[j['id'] for j in jobs]
    if len(ids)!=len(set(ids)) or len(i2)!=len(set(i2)) or any(i not in ids for i in i2):raise ValueError('I-2 job list inconsistent')
    # I-3 = NOC-2 (N2_I3) || PQ-2 (ep_jobs). active_increment is switched together with dual_lane_config.json.
    if len(set(N2_I3))!=14 or any(i not in ids for i in N2_I3):raise ValueError('I-3 NOC-2 job list inconsistent')
    if HOP_CHECKS!=557 or HOP_PROBES!=90 or HOP_CLASSES!=9:raise ValueError('hop-probe frozen counts drifted from HP_COUNT_DERIVATION.md')
    i3=list(N2_I3)+list(ep_jobs)
    if len(i3)!=len(set(i3)) or any(i not in ids for i in i3):raise ValueError('I-3 job list inconsistent')
    for j in jobs:
        if j['id'] in i3 and j.get('sources') and VARIANT_PKG in j['sources'] and S+'NOC_PKG.sv' in j['sources']:raise ValueError('variant and production NOC_PKG in one list '+j['id'])
    # I-4 = PQ-3 (D4 crypto OOC): four crypto tops + endpoint, judged by the existing OOC gate (latches 0, WNS/WHS >= 0, cells > 0).
    i4=DSYN1_I4+DSYN2_I4+['ooc_pq_kdf','ooc_pq_measurement','ooc_pq_attestation_tag','ooc_pq_attestation_controller','endpoint_ooc']
    if any(i not in ids for i in i4) or [s for s in stages if s[0]=='PQ-3'][0][2]!=i4: raise ValueError('I-4 job list inconsistent with PQ-3 stage')
    for j in jobs:   # proposal A guard: expected_diag only on mutant jobs, only ^...$ anchored regexes
        if j.get('expected_diag') and (not j.get('mutant') or any(not (x.startswith('^') and x.endswith('$')) for x in j['expected_diag'])):
            raise ValueError('invalid expected_diag on '+j['id'])
    b1=['b1_ooc_kmac128_l2','b1_ooc_noc_l2_auth']   # B-1: area-budget measurement, not a package stage
    # B-2 step a (M-F1 rev 7 R7.8.1): L2 trims T1+T2 in rtl/dual_lane/noc_l2_auth.sv, function unchanged.
    # Counts frozen from the TB source before the first run: tb_l2trim_equiv header (300000 per-cycle + 8 coverage checks).
    L2T='sim/dual_lane/l2trim/'
    jobs.append(dict(id='l2trim_variant',kind='python',script='scripts/check_l2trim.py',positive_marker=r'^L2TRIM_VARIANT: PASS',
                     sources=['scripts/check_l2trim.py','scripts/prepare_l2trim.py','rtl/dual_lane/variant_provenance.json'],
                     oracle_files=['rtl/dual_lane/noc_l2_auth.sv',L2T+'noc_l2_auth_orig_l2trim.sv'],dependencies=[],independent=True,selection='b2',sim_timeout=120))
    l2eq=job('l2trim_equiv','tb_l2trim_equiv',secure_noc+CRYPTO+['rtl/dual_lane/noc_l2_auth.sv',L2T+'noc_l2_auth_orig_l2trim.sv',T+'tb_l2trim_equiv.sv'],
             300000+8,selection='b2',tb_time_limit='20ms',checks_basis='tb_l2trim_equiv header: N_CYC 300000 per-cycle compares + 8 coverage checks (B-2, frozen before first run)')
    l2eq['defines']=['PQ_MAC_ON']; l2eq['sim_timeout']=3600; jobs.append(l2eq)
    jobs.append(dict(l2eq,id='l2trim_mut_tag_off_by_one',mutant='l2trim_tag_off_by_one',oracle=r'^\[FAIL\] L2TRIM_EQUIV_CYCLE ',
                     dependencies=['l2trim_equiv'],independent=False))
    # Memory-request coverage (Kalash 21:19): separate bench, count frozen from its header before the first run.
    l2m=job('l2trim_equiv_mem','tb_l2trim_equiv_mem',secure_noc+CRYPTO+['rtl/dual_lane/noc_l2_auth.sv',L2T+'noc_l2_auth_orig_l2trim.sv',T+'tb_l2trim_equiv_mem.sv'],
            100000+4,selection='b2',tb_time_limit='20ms',checks_basis='tb_l2trim_equiv_mem header: 100000 per-cycle compares + 4 coverage checks (B-2, frozen before first run)')
    l2m['defines']=['PQ_MAC_ON']; l2m['sim_timeout']=3600; jobs.append(l2m)
    b2_epy=dict(by_id['endpoint_python'],id='b2_endpoint_python',selection='b2'); jobs.append(b2_epy)
    b2_sys=json.loads(json.dumps(by_id['pq_endpoint_sys'])); b2_sys.update(id='b2_pq_endpoint_sys',variant_of='pq_endpoint_sys',selection='b2',dependencies=['b2_endpoint_python'],
                                                                        checks_basis='pq_endpoint_sys count unchanged (37); runs the trimmed noc_l2_auth'); jobs.append(b2_sys)
    jobs.append(dict(by_id['b1_ooc_noc_l2_auth'] if 'b1_ooc_noc_l2_auth' in by_id else [j for j in jobs if j['id']=='b1_ooc_noc_l2_auth'][0],id='b2_ooc_noc_l2_auth',selection='b2_ooc'))
    b2=['l2trim_variant','l2trim_equiv','l2trim_mut_tag_off_by_one','l2trim_equiv_mem','b2_endpoint_python','b2_pq_endpoint_sys','b2_ooc_noc_l2_auth']
    ids=[j['id'] for j in jobs]
    if any(i not in ids for i in b2): raise ValueError('B-2 job list inconsistent')
    # B-3 (M-F1 rev 7 R7.6a / C3): exhaustive arbiter model, registered before any arbiter RTL; step b jobs join later.
    jobs.append(dict(id='arbiter_model',kind='python',script='scripts/arbiter_model.py',positive_marker=r'^ARBITER_MODEL: PASS',
                     sources=['scripts/arbiter_model.py'],dependencies=[],independent=True,selection='b3',sim_timeout=1800))
    b3=['arbiter_model']
    # B-3 step b (D, M-F1 rev 7 R7.8.2): KDF + tag on ONE kmac in the endpoint controller and in the verifier.
    # Regression on the D-SYN-1+2 lists with the controller variant substituted; every count unchanged (frozen basis).
    by_id2={j['id']:j for j in jobs}
    KSV='rtl/dual_lane/pq_attest_protocol.sv'
    def ks_list(src):
        out=[KSV if x==S+'pq_attest_protocol.sv' else x for x in src]
        if KSV in out and not all(f in out for f in KS_FILES): out=out[:out.index(KSV)+1]+[f for f in KS_FILES if f not in out]+out[out.index(KSV)+1:]
        return out
    jobs.append(dict(id='kshare_variant',kind='python',script='scripts/check_kshare.py',positive_marker=r'^KSHARE_VARIANT: PASS',
                     sources=['scripts/check_kshare.py','scripts/prepare_kshare.py','rtl/dual_lane/variant_provenance.json'],
                     oracle_files=[KSV,'rtl/dual_lane/pq_kdf_xk.sv','rtl/dual_lane/pq_attestation_tag_xk.sv','rtl/dual_lane/pq_rot_verifier.sv',
                                   S+'pq_attest_protocol.sv',S+'pq_kdf.sv',S+'pqattest_stg7.sv'],dependencies=[],independent=True,selection='b3',sim_timeout=120))
    for b in dsyn1_base:
        v=json.loads(json.dumps(by_id2['dsyn2_'+b])); src=ks_list(v['sources'])
        if KSV not in src: raise ValueError('D substitution failed for '+b)
        deps=sorted({('ks_'+d[len('dsyn2_'):]) if d.startswith('dsyn2_') and d!='dsyn2_variant' else 'kshare_variant' for d in v.get('dependencies',[])},key=lambda d:(d!='kshare_variant',d))
        v.update(id='ks_'+b,variant_of=b,selection='b3',sources=src,dependencies=deps,checks_basis='count unchanged from '+b+' (D: KDF/tag share one kmac; frozen basis)')
        if deps: v['independent']=False
        jobs.append(v)
    mo=dict(json.loads(json.dumps([j for j in jobs if j['id']=='ks_s8_golden'][0])),id='ks_mut_wrong_owner',mutant='kshare_wrong_owner',
            oracle=r'^\[FAIL\] G\d\d_TAG',dependencies=['ks_s8_golden'],independent=False); jobs.append(mo)
    # Exclusivity contract made bench-visible (ks_mut_tag_during_kdf survived s8_golden: digests stay correct).
    kx_src=[x for x in [j for j in jobs if j['id']=='ks_s8_golden'][0]['sources'] if not x.endswith('tb_stg_8_golden.sv')]+[T+'tb_kshare_excl.sv']
    kx=job('ks_excl','tb_kshare_excl',kx_src,40+2,selection='b3',checks_basis='tb_kshare_excl header: 40 done checks + exclusivity + completion (frozen before first run)')
    kx['dependencies']=['kshare_variant']; kx['independent']=False; jobs.append(kx)
    jobs.append(dict(json.loads(json.dumps(kx)),id='ks_excl_mut_tag_during_kdf',mutant='ksx_tag_during_kdf',oracle=r'^\[FAIL\] KSHARE_EXCLUSIVE ',dependencies=['ks_excl'],
                     # proposal A (approved 2026-10-21): the RTL's own checks necessarily fire under this mutant
                     expected_diag=[r'^Error: pq_kmac_share: start while the shared kmac128 is busy$',r'^Error: pq_attestation_tag: kmac start asserted while kmac128 busy$']))
    ep=json.loads(json.dumps(by_id2['endpoint_ooc'])); ep.update(id='ks_endpoint_ooc',selection='b3_ooc',sources=ks_list(ep['sources']))
    if KSV not in ep['sources']: ep['sources']=[KSV if x==S+'pq_attest_protocol.sv' else x for x in ep['sources']]
    jobs.append(ep)
    ver=dict(ep,id='ks_ooc_verifier',top='pq_rot_verifier',sources=secure_noc+CRYPTO_SYN2+KS_FILES+['rtl/dual_lane/pq_rot_verifier.sv'])
    jobs.append(ver)
    # Step c arbiter (M-F1 R7.6/R7.6a, A0; docs/decisions/STEP_C_DESIGN_P7_L2_SHARED.md sec.2). Counts frozen from the bench
    # sources (tb_arbiter_trace header 10001; tb_l2_arbiter header 4004) before any registered run; no scratch run set them.
    ARB='sim/dual_lane/arbiter/'
    jobs.append(dict(id='arbiter_traces_check',kind='python',script='scripts/check_arbiter_traces.py',
                     positive_marker=r'^ARB_TRACES_CHECK: PASS',sources=['scripts/check_arbiter_traces.py','scripts/gen_arbiter_traces.py','scripts/arbiter_model.py',ARB+'arb_trace.mem',ARB+'arb_trace_hdr.mem'],
                     dependencies=[],independent=True,selection='b3c',sim_timeout=300))
    at=job('arb_trace_equiv','tb_arbiter_trace',['rtl/dual_lane/l2_arbiter.sv',T+'tb_arbiter_trace.sv'],10000+1,selection='b3c',tb_time_limit='40ms',
           include_dirs=[ARB],oracle_files=[ARB+'arb_trace.mem',ARB+'arb_trace_hdr.mem','scripts/gen_arbiter_traces.py','scripts/arbiter_model.py'],
           checks_basis='tb_arbiter_trace header: 10000 per-trace cycle-exact compares + total grants (frozen before first run)')
    at['dependencies']=['arbiter_traces_check']; at['independent']=False; at['sim_timeout']=2400; jobs.append(at)
    jobs.append(dict(json.loads(json.dumps(at)),id='arb_trace_mut_a0_pointer',mutant='arb_a0_pointer',oracle=r'^\[FAIL\] ARB_TRACE_\d+ ',dependencies=['arb_trace_equiv'],
                     # proposal A: out-of-model grants make the model-driven requests hit a busy owner, so the RTL A1 check fires
                     expected_diag=[r'^Error: l2_arbiter: A1 violated, requester [0-3] requests while its own job is in flight$']))
    ab=job('arb_bounds','tb_l2_arbiter',['rtl/dual_lane/l2_arbiter.sv',T+'tb_l2_arbiter.sv'],4000+1+3,selection='b3c',tb_time_limit='40ms',
           checks_basis='tb_l2_arbiter header: 4000 per-grant bound checks + starvation + 3 coverage (frozen before first run)')
    ab['sim_timeout']=2400; jobs.append(ab)
    jobs.append(dict(json.loads(json.dumps(ab)),id='arb_mut_a0_pointer',mutant='arb_a0_pointer',oracle=r'^\[FAIL\] ARB_P_BOUND ',dependencies=['arb_bounds'],independent=False))
    jobs.append(dict(json.loads(json.dumps(ab)),id='arb_mut_no_aging',mutant='arb_no_aging',oracle=r'^\[FAIL\] ARB_(Q_BOUND|NO_STARVATION) ',dependencies=['arb_bounds'],independent=False))
    b3+=['arbiter_traces_check','arb_trace_equiv','arb_trace_mut_a0_pointer','arb_bounds','arb_mut_a0_pointer','arb_mut_no_aging']
    b3+=['kshare_variant']+['ks_'+b for b in dsyn1_base]+['ks_mut_wrong_owner','ks_excl','ks_excl_mut_tag_during_kdf','ks_endpoint_ooc','ks_ooc_verifier']
    # Codex F2-F4 (Kalash addendum B, 2026-10-21): focused reproducers, run first on the current RTL (expected FAIL, kept as
    # evidence), then on the fixed RTL; one mutant per fix restores the old behaviour. Counts frozen from the TB header.
    fsys=json.loads(json.dumps([j for j in jobs if j['id']=='ks_pq_endpoint_sys'][0]))
    fsys.update(id='f234_repro',top='tb_sys_f234',sources=[x for x in fsys['sources'] if not x.endswith('tb_pq_endpoint_sys.sv')]+[T+'tb_sys_f234.sv'],
                checks=26,selection='f234',dependencies=[],independent=True,sim_timeout=5400,tb_time_limit='60ms',variant_of=None,
                include_dirs=['vectors','sim/dual_lane/f234'],
                config=dict(TOP='tb_sys_f234',CHECKS_F2=12,CHECKS_F3=5,CHECKS_F4=9),
                checks_basis='tb_sys_f234 header: F2 12 + F3 3 + F3B 2 + F4 9 = 26 (frozen before the first run)')
    fsys.pop('variant_of',None); jobs.append(fsys)
    for m,kind,oracle in [('f2','f2_revoke_idle_only',r'^\[FAIL\] F2_NO_GRANT_'),('f3','f3_live_owner',r'^\[FAIL\] F3B?_'),
                          ('f4','f4_head_auth_only',r'^\[FAIL\] F4_NO_COMMIT_AFTER_REVOKE_')]:
        jobs.append(dict(json.loads(json.dumps(fsys)),id='f234_mut_'+m,mutant=kind,oracle=oracle,dependencies=['f234_repro'],independent=False))
    f234=['f234_repro','f234_mut_f2','f234_mut_f3','f234_mut_f4']
    for j in jobs:
        if j['id']=='f234_mut_f2': j['kill_scope']=r'^\[FAIL\] F2_'   # the old behaviour also leaves the tile authorized
    # ---------------- B-4 step c / step d (docs/decisions/STEP_C_DESIGN_P7_L2_SHARED.md; M-F1 R7.5a, R7.7a, R7.10).
    # Counts frozen from each TB header before its first registered run. The rev-6 f234 jobs stay registered as history
    # (runs 110813 FAIL 26/20 before the fixes, 113307 FAIL 26/3 after: the 3 are F2_DEAUTH on the rev-6 single-slot L2,
    # i.e. SF-1, which P7/D2 fixes); B-4 accepts F2-F4 on the P7 subsystem (f234_p7*).
    D2V='rtl/dual_lane/'
    P7CORE=[D2V+f for f in ['noc_network_interface_p7.sv','l2_arbiter.sv','l2_kmac_engine.sv','noc_l2_auth_p7.sv','noc_l2_p7_pair.sv']]
    base=[x for x in fsys['sources'] if not x.endswith(('tb_sys_f234.sv','noc_l2_auth.sv','pq_noc_subsystem.sv','noc_network_interface.sv'))]
    k=base.index(D2V+'NOC_PKG.sv')+1; base=base[:k]+[D2V+'noc_p7_pkg.sv']+base[k:]
    k=base.index(D2V+'pq_attest_endpoint.sv'); P7SRC=base[:k]+P7CORE+[D2V+'noc_ingress_quarantine.sv',D2V+'noc_ingress_parser.sv']+base[k:]+[D2V+'rst_bridge.sv',D2V+'pq_noc_subsystem_p7.sv']
    KM=[x for x in base if any(s in x for s in ['keccak','SHA3','kmac'])]   # includes the D-SYN-1 iota / SHA3_PAD variants
    PAIRSRC=[x for x in base if x not in (D2V+'pq_attest_endpoint.sv',D2V+'noc_fault_status.sv',D2V+'pq_rot_verifier.sv')]
    k=PAIRSRC.index(D2V+'noc_attest_gate.sv'); PAIRSRC=PAIRSRC[:k]+[D2V+'noc_network_interface.sv',D2V+'noc_l2_auth.sv']+P7CORE+PAIRSRC[k:]
    L2E='sim/dual_lane/l2engine/'
    jobs.append(dict(id='l2e_vectors_check',kind='python',script='scripts/check_l2e_vectors.py',positive_marker=r'^L2E_VECTORS_CHECK: PASS',
                     sources=['scripts/check_l2e_vectors.py','scripts/gen_l2e_vectors.py','scripts/s8_golden.py']+ADAPTER_REF+[L2E+'l2e_keys.mem',L2E+'l2e_vec.mem'],
                     dependencies=[],independent=True,selection='b4c',sim_timeout=900))
    eng=job('l2e_engine','tb_l2_kmac_engine',[D2V+'NOC_PKG.sv']+sorted(set(KM),key=KM.index)+[D2V+'l2_arbiter.sv',D2V+'l2_kmac_engine.sv',T+'tb_l2_kmac_engine.sv'],
            8020,selection='b4c',tb_time_limit='60ms',include_dirs=[L2E],oracle_files=[L2E+'l2e_keys.mem',L2E+'l2e_vec.mem','scripts/gen_l2e_vectors.py','scripts/l2_golden.py'],
            checks_basis='tb_l2_kmac_engine header: 4 x 2000 per-job checks (bound, digest, job length, owner) + A1 + A2 + 4 coverage + 7 x 2 reset = 8020 (rederived from source 2026-10-21 23:55, before the first run)')
    eng.update(dependencies=['l2e_vectors_check'],independent=False,sim_timeout=3600); jobs.append(eng)
    jobs.append(dict(json.loads(json.dumps(eng)),id='l2e_mut_a2_ovh',mutant='arb_a2_ovh',oracle=r'^\[FAIL\] L2E_A2 ',kill_scope=r'^\[FAIL\] L2E_(A2|P_BOUND|Q_BOUND) ',
                     dependencies=['l2e_engine'],expected_diag=[r'^Error: l2_kmac_engine: A2 violated, [5-9] idle cycles with a request pending before the grant$']))
    jobs.append(dict(json.loads(json.dumps(eng)),id='l2e_mut_a3_long_job',mutant='l2e_a3_long_job',oracle=r'^\[FAIL\] L2E_JOB_LEN ',kill_scope=r'^\[FAIL\] L2E_(JOB_LEN|P_BOUND|Q_BOUND|COVER_[A-Z_]+) ',
                     dependencies=['l2e_engine'],expected_diag=[r'^Error: l2_kmac_engine: A3 violated, job of \d+ cycles exceeds J_MAX 128$']))
    eq=job('l2p7_equiv','tb_l2p7_equiv',PAIRSRC+[T+'tb_l2p7_equiv.sv'],2425,selection='b4c',tb_time_limit='60ms',
           checks_basis='tb_l2p7_equiv header: 500 TX + 2 x 810 RX + 200 data RX + 100 data TX + A1 + 4 coverage = 2425 (frozen before first run)')
    eq.update(defines=['PQ_MAC_ON'],sim_timeout=5400); jobs.append(eq)
    jobs.append(dict(json.loads(json.dumps(eq)),id='l2p7_mut_a1',mutant='l2p7_a1_hold_req',oracle=r'^\[FAIL\] L2P7_A1 ',dependencies=['l2p7_equiv'],independent=False,
                     expected_diag=[r'^Error: l2_arbiter: A1 violated, requester [0-3] requests while its own job is in flight$']))
    sf=job('sf1_flood','tb_sf1_flood',PAIRSRC+[T+'tb_sf1_flood.sv'],487,selection='b4c',tb_time_limit='60ms',
           checks_basis='tb_sf1_flood header: 60 + 22 (D2) + 2 + 400 + 3 = 487 (frozen before first run)')
    sf.update(defines=['PQ_MAC_ON'],sim_timeout=5400); jobs.append(sf)
    D2DIAG=[r'^Error: noc_l2_auth_p7: D2 violated, tile [34] dropped a peer packet for occupancy$']
    jobs.append(dict(json.loads(json.dumps(sf)),id='sf1_mut_peer_drop',mutant='l2p7_peer_drop',oracle=r'^\[FAIL\] SF1_(B2B|HELD|DURING)_',kill_scope=r'^\[FAIL\] SF1_',
                     dependencies=['sf1_flood'],independent=False,expected_diag=D2DIAG))
    # Kalash 2026-10-22: phase-isolated (the single-slot mutant makes phase 1b's setup GRANT fail, a setup TB_TIMEOUT), with
    # the unmutated control sf1_p1 on the same phase-select
    jobs.append(dict(json.loads(json.dumps(sf)),id='sf1_p1',defines=['PQ_MAC_ON','SF1_ONLY_P1'],checks=60,config=dict(PHASES='P1',CHECKS=60),
                     checks_basis='tb_sf1_flood header, SF1_ONLY_P1: phase 1 alone, 20 rounds x 3 = 60 (frozen 2026-10-22 before its first run)'))
    jobs.append(dict(json.loads(json.dumps(sf)),id='sf1_mut_single_slot',mutant='l2p7_single_slot',oracle=r'^\[FAIL\] SF1_(REVOKE|GRANT)_',kill_scope=r'^\[FAIL\] SF1_',
                     dependencies=['sf1_p1'],independent=False,expected_diag=D2DIAG,defines=['PQ_MAC_ON','SF1_ONLY_P1'],checks=60,
                     config=dict(PHASES='P1',CHECKS=60),
                     checks_basis='tb_sf1_flood header, SF1_ONLY_P1: phase 1 alone, 20 rounds x 3 = 60 (frozen 2026-10-22 before its first run)'))
    # contract sec. 4 accounting: the full SF-1 run plus SF1_ACCT_T3/T4 (accepted == replayed + rejected at quiescence) and
    # SF1_HOLD_MAX (peer_hold_max <= H_MAX 512, measured value printed)
    jobs.append(dict(json.loads(json.dumps(sf)),id='sf1_acct',defines=['PQ_MAC_ON','SF1_ACCT'],checks=490,config=dict(ACCT=1,CHECKS=490),
                     checks_basis='tb_sf1_flood header, SF1_ACCT: 487 + 3 = 490 (frozen 2026-10-22 before its first run)'))
    OOCKW=dict(kind='ooc',dependencies=[],independent=True,build_timeout=7200,dsyn1=True,dsyn2=True,defines=['PQ_MAC_ON'],generics=[],
               child_script='scripts/d4_crypto_ooc_child.tcl',constraints='scripts/d4_crypto_ooc.xdc',oracle_files=['scripts/d4_crypto_ooc.xdc','scripts/d4_crypto_ooc_child.tcl'])
    jobs.append(dict(OOCKW,id='l2e_ooc',top='noc_l2_p7_pair',sources=[x for x in PAIRSRC if not x.endswith(('/noc_l2_auth.sv','/noc_network_interface.sv','noc_attest_gate.sv'))],selection='b4c_ooc'))
    fp7=dict(json.loads(json.dumps(fsys)),id='f234_p7',sources=P7SRC+[T+'tb_sys_f234_p7.sv'],defines=['PQ_MAC_ON'],selection='b4d',include_dirs=['vectors','sim/dual_lane/f234'],
             config=dict(TOP='tb_sys_f234',DUT='P7',CHECKS_F2=12,CHECKS_F3=5,CHECKS_F4=9),
             checks_basis='tb_sys_f234 header, F234_P7 mode: 26 (counts unchanged)')
    jobs.append(fp7)
    for m,kind,oracle,scope in [('f2','f2_revoke_idle_only',r'^\[FAIL\] F2_NO_GRANT_',r'^\[FAIL\] F2_'),('f3','f3p7_live_owner',r'^\[FAIL\] F3B?_',None),
                                ('f4','f4_head_auth_only',r'^\[FAIL\] F4_NO_COMMIT_AFTER_REVOKE_',None)]:
        x=dict(json.loads(json.dumps(fp7)),id='f234_p7_mut_'+m,mutant=kind,oracle=oracle,dependencies=['f234_p7'],independent=False)
        if scope: x['kill_scope']=scope
        # Kalash 2026-10-22: phase-isolated mutants, each with an unmutated control on the same phase-select (must pass).
        # F2: the mutant leaves F4's calibration without a REVOKE head. F3: the live-owner stall becomes the targeted bounded
        # checks F3_APP_HEADER_ACCEPTED / F3B_READ_HEADER_ACCEPTED (N = 20,000 cycles) instead of a TB_TIMEOUT.
        ph={'f2':('F234_ONLY_F2','F2',12,'the F2 phase alone, 6 states x 2 = 12'),
            'f3':('F234_ONLY_F3','F3',7,'F3 + F3B alone: F3_APP_HEADER_ACCEPTED + 3 F3 + F3B_READ_HEADER_ACCEPTED + 2 F3B = 7')}.get(m)
        if ph:
            d,tag,n,basis=ph
            ctl=dict(json.loads(json.dumps(fp7)),id='f234_p7_'+tag.lower()+'only',defines=fp7['defines']+[d],checks=n,
                     config=dict(fp7['config'],PHASES=tag,CHECKS=n),checks_basis=f'tb_sys_f234 header, {d}: {basis} (frozen 2026-10-22 before its first run)')
            jobs.append(ctl)
            x.update(defines=ctl['defines'],checks=n,config=ctl['config'],checks_basis=ctl['checks_basis'],dependencies=[ctl['id']])
            if m=='f3': x['kill_scope']=r'^\[FAIL\] F3B?_'
        jobs.append(x)
    rg=job('p7_refuse_grant','tb_p7_refuse_grant',P7SRC+[T+'tb_p7_refuse_grant.sv'],12,selection='b4d',tb_time_limit='5ms',
           checks_basis='tb_p7_refuse_grant header: 8 refuse + 4 TX refused = 12 (frozen before first run)')
    rg.update(defines=['PQ_MAC_ON'],sim_timeout=1800); jobs.append(rg)
    jobs.append(dict(json.loads(json.dumps(rg)),id='p7_mut_control_allowed',mutant='p7s_control_allowed',oracle=r'^\[FAIL\] P7R_REFUSE_',kill_scope=r'^\[FAIL\] P7R_',
                     dependencies=['p7_refuse_grant'],independent=False))
    # contract sec. 2: verifier revocation rules (unit bench, bypassed crypto); its mutants register next session
    vr=job('verifier_revoke','tb_verifier_revoke',[x for x in P7SRC if x.startswith(S) and any(s in x for s in ['keccak','SHA3','kmac','pq_kdf_pkg','pq_measurement_pkg','pqattest_stg7_pkg'])]
           +[D2V+'NOC_PKG.sv',D2V+'pq_keccak_iota.sv',D2V+'SHA3_PAD.sv']+KS_FILES+[D2V+'pq_rot_verifier.sv',T+'tb_verifier_revoke.sv'],48,selection='b4d',tb_time_limit='20ms',
           checks_basis='tb_verifier_revoke header: 11 x 3 + 4 x 2 + 1 + 3 + 2 + 1 = 48 (rederived from source 2026-10-21 23:55, before the first run)')
    vr['sim_timeout']=1800; jobs.append(vr)
    # contract sec. 1d (ingress) and sec. 7 (C4 <= 1500) on the P7 subsystem; counts frozen from the TB headers 2026-10-22
    # (written 2026-10-21, compile + elaborate checked before this registration); their mutants register in the next group
    ig=job('p7_ingress','tb_p7_ingress',P7SRC+[T+'tb_p7_ingress.sv'],39,selection='b4e',tb_time_limit='60ms',include_dirs=['vectors'],
           checks_basis='tb_p7_ingress header: 3 + 3 + 14 + 3 + 2 + 4 + 8 + 2 = 39 (frozen from source before the first run)')
    ig.update(defines=['PQ_MAC_ON'],sim_timeout=5400); jobs.append(ig)
    c4=job('p7_c4','tb_p7_c4',P7SRC+[T+'tb_p7_c4.sv'],18,selection='b4e',tb_time_limit='70ms',include_dirs=['vectors'],
           checks_basis='tb_p7_c4 header: IDLE + 9 verifier states + SAT_DATA + 3 raw faults + PEER_OCCUPIED + Q_CONTENTION + HELD + C4_MAX = 18 (frozen from source before the first run)')
    c4.update(defines=['PQ_MAC_ON'],sim_timeout=5400); jobs.append(c4)
    # contract sec. 1/2/5 mutants (registered 2026-10-22, Kalash approval of the group). Oracle = the targeted check;
    # kill_scope = the related family; expected_diag only where a scratch probe (launcher path, not evidence) showed the
    # RTL's own assertion lines, each required to occur at least once (proposal A).
    S125=[('l2e_mut_owner_select','l2e_engine','l2e_owner_select',r'^\[FAIL\] L2E_OWNER ',r'^\[FAIL\] L2E_'),
          ('l2e_mut_done_route','l2e_engine','l2e_done_route',r'^\[FAIL\] L2E_OWNER ',r'^\[FAIL\] L2E_'),
          ('l2e_mut_word_off','l2e_engine','l2e_word_off',r'^\[FAIL\] L2E_DIGEST ',r'^\[FAIL\] L2E_'),
          ('l2e_mut_key_live','l2e_engine','l2e_key_live',r'^\[FAIL\] L2E_DIGEST ',r'^\[FAIL\] L2E_'),
          ('vrev_mut_req_cancel','verifier_revoke','vrev_req_cancel',r'^\[FAIL\] VREV_NO_WITHDRAWAL',r'^\[FAIL\] VREV_'),
          ('vrev_mut_level','verifier_revoke','vrev_level',r'^\[FAIL\] VREV_HELD_ONE',r'^\[FAIL\] VREV_'),
          ('vrev_mut_check_success','verifier_revoke','vrev_check_success',r'^\[FAIL\] VREV_CHECK_',r'^\[FAIL\] VREV_'),
          ('ig_mut_q_src_off','p7_ingress','p7s_q_src_off',r'^\[FAIL\] Q9_',r'^\[FAIL\] Q'),
          # nested HEAD cases stay reason 11 through the length check (defense in depth); the nested HEAD_TAIL case
          # (Q11_MID_HEAD_TAIL) isolates the nested check (run 180620: reason 10 instead of 11)
          ('ig_mut_q_nested_off','p7_ingress','p7s_q_nested_off',r'^\[FAIL\] Q11_(NESTED_|MID_HEAD_TAIL)',r'^\[FAIL\] Q'),
          ('ig_mut_q_no_cap','p7_ingress_c','p7s_q_no_cap',r'^\[FAIL\] (Q11_(OVERLONG|ENDLESS_BODY)|QC_RAW_PORT_LIVE)',r'^\[FAIL\] Q'),
          ('ig_mut_q_partial','p7_ingress','p7s_q_partial',r'^\[FAIL\] (QW_NO_ROUTE_HOLD|QE_NO_COMMIT)',r'^\[FAIL\] Q'),
          ('ig_mut_gap_any','p7_ingress','ingq_gap_any',r'^\[FAIL\] QGAP_V[01]R0 ',r'^\[FAIL\] QGAP_'),
          ('ig_mut_parser_src_off','p7_ingress','ingp_src_off',r'^\[FAIL\] QP_FORGED ',r'^\[FAIL\] QP_')]
    # q_src_off: the forged packets now reach tile 3; its wrapper NI's concurrent p_no_deliver_and_drop fires (probe: 2 lines)
    # while the clocked twin stays silent - the XSim evaluation class of S1_NOTES sec. 5a, deterministic under this mutant
    S125_DIAG={'ig_mut_q_src_off':[r'^Error: M10: packet simultaneously delivered and rejected$'],
               # partial forwarding puts incomplete packets into the mesh: the protected router/allocator assertions report the
               # corrupted framing (run 180620), the NI line is the sec. 5a evaluation class (clocked twin silent)
               'ig_mut_q_partial':[r'^Error: NOC_ALLOCATOR: output \d+ owner VC \d+ presents flit_type \d+ mid-packet \(expect BODY=1 or TAIL=2\)$',
                                   r'^Error: noc_router: synchronous (EAST->EAST|NORTH->NORTH|WEST->WEST) loopback$',
                                   r'^Error: noc_router_datapath: flit arrived on LOCAL with an illegal vc_id$',
                                   r'^Error: M10: packet simultaneously delivered and rejected$']}
    # section-C phase job (Kalash 2026-10-22 rule: a liveness symptom is a bounded targeted check): unmutated control
    igc=dict(json.loads(json.dumps(ig)),id='p7_ingress_c',defines=ig['defines']+['ING_ONLY_C'],checks=15,config=dict(PHASES='C',CHECKS=15),
             checks_basis='tb_p7_ingress header, ING_ONLY_C: section C 7 x 2 + QC_RAW_PORT_LIVE = 15 (frozen 2026-10-22 before its first run)')
    jobs.append(igc)
    base_of={j['id']:j for j in jobs}
    for jid,base,kind,oracle,scope in S125:
        x=dict(json.loads(json.dumps(base_of[base])),id=jid,mutant=kind,oracle=oracle,kill_scope=scope,dependencies=[base],independent=False)
        if jid in S125_DIAG: x['expected_diag']=S125_DIAG[jid]
        jobs.append(x)
    # contract sec. 6 integrated P&R checkpoint: the full P7 subsystem, OOC implementation (HD.CLK_SRC model approved by
    # Kalash 2026-10-22), runs alone; the judge's pnr_gate enforces WNS/WHS/WPWS >= 0, TNS/THS 0, route errors 0, DRC 0,
    # 0 unconstrained endpoints; the synthesis gates (max_lut, RAM inference, hierarchy) apply unchanged
    jobs.append(dict(OOCKW,id='p7_subsystem_pnr',top='pq_noc_subsystem_p7',sources=P7SRC,selection='b4_pnr',max_lut=47550,build_timeout=7200,
                     lutram_instances=[r'W\[0\]\.l2\b',r'W\[1\]\.l2\b',r'\bquarantine\b'],pnr=True))
    # full-subsystem OOC (contract sec. 6): all real logic, judge enforces max_lut and DRC 0; RAM inference: the slot-P stores,
    # TX payload buffers and the quarantine FIFO must report LUTRAM in util_hier (lutram_instances)
    jobs.append(dict(OOCKW,id='p7_subsystem_ooc',top='pq_noc_subsystem_p7',sources=P7SRC,selection='b4d_ooc',max_lut=47550,build_timeout=7200,
                     lutram_instances=[r'W\[0\]\.l2\b',r'W\[1\]\.l2\b',r'\bquarantine\b']))
    b4=['l2e_vectors_check','l2e_engine','l2e_mut_a2_ovh','l2e_mut_a3_long_job','l2p7_equiv','l2p7_mut_a1','sf1_flood','sf1_mut_peer_drop',
        'sf1_mut_single_slot','l2e_ooc','f234_p7','f234_p7_mut_f2','f234_p7_mut_f3','f234_p7_mut_f4','p7_refuse_grant','p7_mut_control_allowed',
        'verifier_revoke','p7_subsystem_ooc','p7_ingress','p7_c4','sf1_acct','sf1_p1','f234_p7_f2only','f234_p7_f3only','p7_ingress_c']+[s[0] for s in S125]+['p7_subsystem_pnr']
    if any(i not in ids for i in b1): raise ValueError('B-1 job list inconsistent')
    # ---------------- I-5 / S2 (contract sec. 8; docs/decisions/S2_MATRIX_PLAN.md): the attack matrix at the L2 boundary,
    # one negative control per row (each makes its row's attack succeed observably). Counts frozen from the TB header and
    # scripts/gen_s2_vectors.py before the first run; expected_diag only where a scratch run showed RTL lines.
    S2D='sim/dual_lane/s2/'
    jobs.append(dict(id='s2_vectors_check',kind='python',script='scripts/gen_s2_vectors.py',positive_marker=r'^S2_VECTORS_CHECK: PASS',
                     sources=['scripts/gen_s2_vectors.py','scripts/l2_golden.py','scripts/full_chain_golden.py','scripts/s8_golden.py']+ADAPTER_REF+
                             [S2D+f for f in ('s2_keys.mem','s2_vec.mem','s2_meta.json','s2_names.svh')],
                     dependencies=[],independent=True,selection='i5',sim_timeout=900))
    s2=job('s2_attacks','tb_s2_attacks',PAIRSRC+[T+'tb_s2_attacks.sv'],30,selection='i5',tb_time_limit='40ms',include_dirs=[S2D],
           oracle_files=[S2D+'s2_keys.mem',S2D+'s2_vec.mem','scripts/gen_s2_vectors.py','scripts/l2_golden.py'],
           checks_basis='tb_s2_attacks header: S2_NV (25 vectors, scripts/gen_s2_vectors.py) + S2_T4_ACCEPTED + S2_T4_REJECTED + S2_ACCT_T3/T4 + S2_HOLD_MAX = 30 (frozen 2026-10-23 before the first run)')
    s2.update(defines=['PQ_MAC_ON'],sim_timeout=3600,dependencies=['s2_vectors_check'],independent=False,config=dict(VECTORS=25,CHECKS=30)); jobs.append(s2)
    S2M=[('s2_mut_mac_off','s2p_mac_off','M'),('s2_mut_bind_ctl','s2w_bind_ctl','B'),('s2_mut_id_off','s2w_id_off','I'),
         ('s2_mut_st_dest','s2w_st_dest','S'),('s2_mut_st_vc','s2w_st_vc','S'),('s2_mut_seq_off','s2p_seq_off','R'),
         ('s2_mut_epoch_off','s2p_epoch_off','E'),('s2_mut_seq_wrap','s2w_seq_wrap','W'),('s2_mut_len_off','s2w_len_off','L')]
    S2M_ORACLE={'s2_mut_st_dest':r'^\[FAIL\] S2_S_DEST0 ','s2_mut_st_vc':r'^\[FAIL\] S2_S_VC0 ','s2_mut_seq_wrap':r'^\[FAIL\] S2_W_GRANT1_AFTER_MAX ',
                's2_mut_bind_ctl':r'^\[FAIL\] S2_B_CTL_UNBOUND '}
    S2M_DIAG={}
    for jid,kind,row in S2M:
        x=dict(json.loads(json.dumps(s2)),id=jid,mutant=kind,oracle=S2M_ORACLE.get(jid,r'^\[FAIL\] S2_'+row+'_'),kill_scope=r'^\[FAIL\] S2_',
               dependencies=['s2_attacks'],independent=False)
        if jid in S2M_DIAG: x['expected_diag']=S2M_DIAG[jid]
        jobs.append(x)
    # flood / rate-limit row: the SF-1 bench is its attack (SF1_RL_VERDICT); control copy in this selection, mutant rl_off
    jobs.append(dict(json.loads(json.dumps(sf)),id='s2_sf1_flood',selection='i5'))
    jobs.append(dict(json.loads(json.dumps(sf)),id='s2_mut_rl_off',selection='i5',mutant='l2p7_rl_off',oracle=r'^\[FAIL\] SF1_RL_VERDICT ',
                     kill_scope=r'^\[FAIL\] SF1_',dependencies=['s2_sf1_flood'],independent=False))
    i5=['s2_vectors_check','s2_attacks']+[m[0] for m in S2M]+['s2_sf1_flood','s2_mut_rl_off']
    # ---------------- I-5 / sec. 9 re-earn on P7 (DECISION_REGISTER S2-REEARN, S2-N81-P7, S2-N2P7; docs/decisions/
    # S2_REEARN_ADAPTATION.md). One registration group (Kalash 2026-10-28). Counts frozen from the TB headers before the
    # first registered run; scratch runs (diagnostic) matched them. DUT (A) = mesh + 6 noc_network_interface_p7.
    P7MESH=[D2V+'NOC_PKG.sv',D2V+'noc_p7_pkg.sv']+[S+f for f in ('NOC_FIFO.sv','NOC_CROSSBAR.sv','NOC_XY_ROUTING.sv','NOC_arbiter.sv',
            'allocator.sv','noc_credit_counter.sv','NOC_DATAPTAH.sv','noc_router.sv','noc_mesh_3x2.sv')]+[D2V+'noc_network_interface_p7.sv',S+'noc_addr_decoder.sv']
    P7NI=[D2V+'NOC_PKG.sv',D2V+'noc_p7_pkg.sv',D2V+'noc_network_interface_p7.sv']
    GEN_P7=['scripts/prepare_p7_benches.py']; CF='sim/dual_lane/n81p7_long/'
    S9=[]
    def s9(j): jobs.append(j); S9.append(j['id']); return j
    # N-8.1 system (tb_noc_n81_p7 header): default 23, N0 2, LONG 2 (counterfactual packages, test-only), LONG watchdog off
    n81=dict(selection='i5',tb_time_limit='5ms')
    s9(dict(job('n81p7_sys','tb_noc_n81_p7',P7MESH+[T+'tb_noc_n81_p7.sv'],24,**n81),defines=['PQ_MAC_ON'],config=dict(TOP='tb_noc_n81_p7',W=16,WDE=1,P7_PACKET_BOUND_OK=1),
            checks_basis='tb_noc_n81_p7 header: STRUCT 1 + EJECT 14 + NONINT 4 + BK 5 = 24 (re-frozen 2026-10-29 before its next registered run: shared-router case added per Kalash)'))
    s9(dict(job('n81p7_n0','tb_noc_n81_p7',P7MESH+[T+'tb_noc_n81_p7.sv'],2,**n81),defines=['PQ_MAC_ON','N81_WDE=0'],
            config=dict(TOP='tb_noc_n81_p7',W=16,WDE=0,P7_PACKET_BOUND_OK=1),required_lines=[[r'^N0 EXPECTED-FAIL CONFIRMED \(receive interface stalled without containment\)$',1]],
            checks_basis='tb_noc_n81_p7 header, N0 (WDE=0): STRUCT 1 + N0 1 = 2'))
    LONGSRC=[CF+'NOC_PKG_cf.sv',CF+'noc_p7_pkg_cf.sv']+P7MESH[2:]+[T+'tb_noc_n81_p7.sv']
    lg=s9(dict(job('n81p7_long','tb_noc_n81_p7',LONGSRC,2,**n81),defines=['PQ_MAC_ON','N81P7_LONG'],oracle_files=['scripts/prepare_n81p7_long.py'],
               config=dict(TOP='tb_noc_n81_p7',W=16,WDE=1,P7_PACKET_BOUND_OK=0),
               required_lines=[[r'^STATS LONG WDE=1 upstream_cycles=[1-9]\d* upstream_locked=0 aborts=1 contained=1 payload=\d+$',1]],
               checks_basis='tb_noc_n81_p7 header, LONG: LONG_PROFILE 1 + LONG 1 = 2 (counterfactual 17-flit WR_REQ, not P7 traffic)'))
    s9(dict(json.loads(json.dumps(lg)),id='n81p7_long_n0',defines=['PQ_MAC_ON','N81P7_LONG','N81_WDE=0'],config=dict(TOP='tb_noc_n81_p7',W=16,WDE=0,P7_PACKET_BOUND_OK=0),
            required_lines=[],dependencies=['n81p7_long'],independent=False,
            tb_control=dict(errors=1,oracle=[r'^\[FAIL\] LONG : long data packet held upstream',
                                             r'^STATS LONG WDE=0 upstream_cycles=[1-9]\d* upstream_locked=1 aborts=0 contained=0 payload=\d+$'],
                            allowed_fail=[r'^\[FAIL\] LONG : '],forbid=[r'^\[FAIL\] LONG_PROFILE']),
            checks_basis='tb_noc_n81_p7 header, LONG with the watchdog off: 2 checks, exactly the LONG recovery check fails (control)'))
    # N-8.1 NI unit (tb_ni_n81_p7 header CHECK COUNT): tile 0 (CONTROL_ALLOWED = 0) and tile 3 (CONTROL_ALLOWED = 1), W 16 / 1
    for tag,defs,n,cfg in [('t0w16',[],126,dict(TILE=0,CONTROL_ALLOWED=0,W=16)),('t0w1',['N81_W=1'],126,dict(TILE=0,CONTROL_ALLOWED=0,W=1)),
                           ('t3w16',['N81P7_TILE3'],123,dict(TILE=3,CONTROL_ALLOWED=1,W=16)),('t3w1',['N81P7_TILE3','N81_W=1'],122,dict(TILE=3,CONTROL_ALLOWED=1,W=1))]:
        s9(dict(job('n81p7_ni_'+tag,'tb_ni_n81_p7',P7NI+[T+'tb_ni_n81_p7.sv'],n,selection='i5',tb_time_limit='5ms'),defines=['PQ_MAC_ON']+defs,config=cfg,
                checks_basis=f'tb_ni_n81_p7 header CHECK COUNT table: {n} (frozen before the first registered run)'))
    # N-7.5 finite liveness on P7 (tb_noc_perf_p7, generated); P7 only with PQ_MAC_ON (no MAC axis)
    PT7=dict(PERF_TAGS,transport='MF1-rev7-P7')
    def perf7(case,points): return dict(perf_cfg(case,points,1),TOP='tb_noc_perf_p7',TRANSPORT='MF1-rev7-P7')
    def sim7(jid,defines,case,checks,points,npoints=1,**kw):
        j=job(jid,'tb_noc_perf_p7',P7MESH+[T+'tb_noc_perf_p7.sv'],checks,selection='i5',config=perf7(case,npoints),tb_time_limit='200ms',oracle_files=GEN_P7)
        j.update(defines=['PQ_MAC_ON']+defines,sim_timeout=3600,point_accounting=dict(mac=1,tags=PT7,points=points),**kw); return s9(j)
    sim7('n75p7_sat_vc2',['N75_SAT_VC2'],'n75_sat_vc2',1+N2_POINT_CHECKS+3,[clean_point('n75_sat_vc2',4,1,13056,1536,1152)],
         required_lines=[[r'^N75_SAT_VC2 mac=1 att_queued=384 att_delivered=384 mem_queued=1152 mem_delivered=1152 vc2_credit_zero_port_cycles=[1-9]\d*$',1]],
         checks_basis='tb_noc_perf_p7: CFG 1 + 14 point + 3 = 18; records: RoT 256 CHALLENGE, tile 3 128 RESPONSE + 128 WR, 4 x 256 WR')
    sim7('n75p7_reset',['N75_RESET'],'n75_reset',1+4+N2_POINT_CHECKS,[clean_point('n75_reset',4,4,3264,1536,1152)],
         required_lines=[[r'^N75_RESET phase=A pattern=4 period=4 mac=1 reset_at=1000 reset_len=5 had_traffic=1 accepted=\d+ delivered=\d+ inflight=\d+ routers_idle=1 links_idle=1 ni_idle=1$',1]],
         checks_basis='tb_noc_perf_p7: CFG 1 + 4 reset + 14 point = 19')
    sim7('n75p7_second_challenge',['N75_SECOND_CHALLENGE'],'n75_second_challenge',1+N2_POINT_CHECKS+5,[clean_point('n75_second_challenge',0,16,821,821,816)],
         required_lines=[[r'^N75_SECOND_CHALLENGE mac=1 rot_issued=2 rot_responses=2 rot_max_outstanding=1 ep_served=2 ep_drained=1 ep_drained_src=4 responses_to_extra=0$',1]],
         checks_basis='tb_noc_perf_p7: CFG 1 + 14 point + 5 = 20; 6 x 136 data + 2 challenges + 1 extra + 2 responses = 821')
    # NOC-2 subset, transport part (S2-N2P7): 7 points, outcome fields exact (volumes include the DUT-paced control loop)
    def n2pt(pat,per): return dict(case='n2p7',pattern=pat,period=per,max=dict(drain_cycles=50000),
                                   exact=dict(missing=0,unsent=0,duplicate=0,mismatched=0,unknown=0,credits_returned=1,idle_after_drain=1,verdict='OK'))
    N2P=[(5,64),(0,64),(0,8),(0,1),(2,64),(2,8),(2,1)]
    sim7('n2p7_matrix',['N2P7_MATRIX'],'n2p7',1+7*(N2_POINT_CHECKS+1),[n2pt(a,b) for a,b in N2P],npoints=7,
         required_lines=[[rf'^N2P7_CTRL pattern={a} period={b} loops=[1-9]\d* started=[1-9]\d* rtt_min=[1-9]\d* rtt_max=[1-9]\d* rtt_mean=[1-9]\d*$',1] for a,b in N2P],
         checks_basis='tb_noc_perf_p7 N2P7_MATRIX: CFG 1 + 7 x (14 point + N2P7_CTRL_LOOP) = 106 (frozen before the first registered run)')
    # NOC-2 subset, subsystem part: control round trip on pq_noc_subsystem_p7 with / without load
    s9(dict(job('n2p7_rtt','tb_n2p7_rtt',P7SRC+[T+'tb_n2p7_rtt.sv'],11,selection='i5',tb_time_limit='70ms',include_dirs=['vectors']),
            defines=['PQ_MAC_ON'],sim_timeout=3600,config=dict(TOP='tb_n2p7_rtt',CHECKS=11,K=4),
            required_lines=[[rf'^N2P7_RTT load={l} k={k} row={1 if k%2==0 else 0} rtt=[1-9]\d* to_challenge=\d+ challenge_to_response=[1-9]\d* response_to_grant=[1-9]\d* grant_to_delivered=[1-9]\d*$',1]
                            for l in ('NONE','LOADED') for k in range(4)],
            checks_basis='tb_n2p7_rtt header: 2 x 4 round trips + 3 load checks = 11 (frozen before the first registered run)'))
    # hop probes on P7 (tb_noc_hop_probes_p7, generated): VC0 / VC1 all pairs, VC2 only 3 <-> 4, 28 VC2 refusals
    hp7=[]
    for a,b in HOP_PAIRS:
        for vc,msg,flits in [(0,2,3),(1,3,1),(2,4,12)]:
            if vc==2 and {a,b}!={3,4}: continue
            s,d=(b,a) if vc==1 else (a,b)
            hp7.append([rf'^HOP_PROBE id=\d+ src={s} dst={d} vc={vc} msg={msg} hops={hop_count(s,d)} flits={flits} t_inj=\d+ t_del=\d+ latency=[1-9]\d* mac=1 ok=1$',1])
        if {a,b}!={3,4}:
            at='source' if a not in (3,4) else 'destination'
            hp7.append([rf'^HOP_VC2_REFUSED src={a} dst={b} at={at} flits=12 .* ok=1$',1])
    hp7+=[[r'^HOP_PROBE ',62],[r'^HOP_VC2_REFUSED ',28],[r'^HOP_CLASS ',7],[r'^HOP_CONTENTION ',0],
          [r'^HOP_SUMMARY mac=1 loopback=0 vc0_per_hop=[1-9]\d* vc0_hop1=[1-9]\d* vc0_zero_hop=NA vc1_per_hop=[1-9]\d* vc1_hop1=[1-9]\d* vc1_zero_hop=NA vc2_per_hop=-1 vc2_hop1=[1-9]\d* vc2_zero_hop=NA monotonic=1 const_increment=1$',1]]
    s9(dict(job('hop_probes_p7','tb_noc_hop_probes_p7',P7MESH+[T+'tb_noc_hop_probes_p7.sv'],414,selection='i5',tb_time_limit='10ms',oracle_files=GEN_P7),
            defines=['PQ_MAC_ON'],sim_timeout=900,required_lines=hp7,
            config=dict(TOP='tb_noc_hop_probes_p7',CASE='hop_probes',transport='MF1-rev7-P7',MAC_FLITS=4,PAIRS=30,PROBES=62,CLASSES=7,LOOPBACK=0),
            checks_basis='tb_noc_hop_probes_p7 header: 2 + 6 x 62 + 28 + 7 + 3 + 2 = 414 (frozen before the first registered run)'))
    # authorization mapping, 7th row (S2-N2P7): plain-tile gates refuse data; two negative controls
    gd=s9(dict(job('p7_gate_data','tb_p7_gate_data',P7SRC+[T+'tb_p7_gate_data.sv'],4,selection='i5',tb_time_limit='5ms'),defines=['PQ_MAC_ON'],sim_timeout=1800,
               checks_basis='tb_p7_gate_data header: GATE_DATA_REFUSED x 4 tiles = 4 (frozen before the first registered run)'))
    for jid,kind in [('p7_gate_mut_control_allowed','p7s_control_allowed'),('p7_gate_mut_bypass','p7s_gate_bypass')]:
        s9(dict(json.loads(json.dumps(gd)),id=jid,mutant=kind,oracle=r'^\[FAIL\] GATE_DATA_REFUSED_',kill_scope=r'^\[FAIL\] GATE_DATA_',
                dependencies=['p7_gate_data'],independent=False))
    i5+=S9
    # ---------------- S3 (DECISION_REGISTER S3-T1, S3-A1; docs/decisions/S3_T1_A1_CONTRACT.md): T1 Keccak select replicated
    # per lane in all four engines (cycle-identical) + A1 one Keccak shared at tile 3 by the KDF/tag kmac and the measurement
    # SHA3. Every count is frozen in the contract before the first run; copies keep their base count (benches unchanged).
    by3={j['id']:j for j in jobs}
    XP=[D2V+'SHA3_256_xp.sv',D2V+'kmac_128_xp.sv',D2V+'pq_kmac_share_xp.sv',D2V+'pq_measurement_xp.sv']
    def s3_list(src):
        out=[D2V+'pq_keccak_f1600.sv' if x==S+'pq_keccak_f1600.sv' else x for x in src]   # T1 (A5 withdrawn, contract sec. 6)
        if D2V+'pq_attest_protocol.sv' in out:
            i=out.index(D2V+'pq_attest_protocol.sv'); out[i:i+1]=XP+[D2V+'pq_attest_protocol_s3.sv']
        if D2V+'pq_keccak_f1600.sv' not in out: raise ValueError('S3 substitution found no keccak core')
        return out
    s3=[]
    def s3j(j): jobs.append(j); s3.append(j['id']); return j
    S3V=[D2V+f for f in ('pq_keccak_f1600.sv','kmac_128_xp.sv','SHA3_256_xp.sv','pq_kmac_share_xp.sv','pq_measurement_xp.sv','pq_attest_protocol_s3.sv')]+[T+'tb_s3_meas_equiv.sv']
    s3j(dict(id='s3_variant',kind='python',script='scripts/check_s3.py',positive_marker=r'^S3_VARIANT: PASS',
             sources=['scripts/check_s3.py','scripts/prepare_s3.py',D2V+'s3_provenance.json'],
             oracle_files=S3V+[S+'pq_keccak_f1600.sv',S+'kmac_128.sv',S+'SHA3_256.sv',D2V+'pq_kmac_share.sv',D2V+'pq_measurement.sv',D2V+'pq_attest_protocol.sv',T+'tb_dsyn2_measurement_equiv.sv'],
             dependencies=[],independent=True,selection='s3',sim_timeout=120))
    def s3copy(base,new,**kw):
        v=json.loads(json.dumps(by3[base])); v.pop('mutant',None)
        v.update(id=new,variant_of=base,selection='s3',sources=s3_list(v['sources']),dependencies=['s3_variant'],independent=False,
                 checks_basis='count unchanged from '+base+' (S3: cycle-identical T1 + shared tile-3 Keccak; frozen in docs/decisions/S3_T1_A1_CONTRACT.md)')
        v.update(kw); return s3j(v)
    g3=s3copy('ks_s8_golden','s3_s8_golden')
    s3copy('ks_pq_endpoint_unit','s3_pq_endpoint_unit')
    s3copy('ks_excl','s3_ks_excl')
    ps=s3copy('ks_excl','s3_perm_share',top='tb_s3_perm_share',checks=45,
              checks_basis='tb_s3_perm_share header: 40 done + 4 rules + completion (frozen in the S3 contract before the first run)')
    ps['sources']=[x for x in ps['sources'] if not x.endswith('tb_kshare_excl.sv')]+[T+'tb_s3_perm_share.sv']
    for base in ['l2e_engine','l2p7_equiv','verifier_revoke','n2p7_rtt','p7_c4','f234_p7','s2_attacks']: s3copy(base,'s3_'+base)
    # A6 exhaustive equivalence: same reference, checks and count as dsyn2_measurement_equiv; the variant is pq_measurement_xp
    # (single-block SHA3) on its own keccak_f1600 (bench generated by scripts/prepare_s3.py).
    me=s3copy('dsyn2_measurement_equiv','s3_meas_equiv',top='tb_s3_meas_equiv',
              checks_basis='count unchanged from dsyn2_measurement_equiv: 65 x 65 x 4 x (digest + exact latency) + 9 (A6, frozen in the S3 contract)')
    me['sources']=[x for x in me['sources'] if not x.endswith('tb_dsyn2_measurement_equiv.sv')]+[D2V+'SHA3_256_xp.sv',D2V+'pq_measurement_xp.sv',T+'tb_s3_meas_equiv.sv']
    def s3mut(par,jid,kind,oracle):
        return s3j(dict(json.loads(json.dumps(par)),id=jid,mutant=kind,oracle=oracle,dependencies=[par['id']],independent=False))
    s3mut(ps,'s3_mut_done_both','s3p_done_both',r'^\[FAIL\] PERM_DONE_ISOLATION ')
    # s3_mut_state_in: INVALID in run 20261102_183915 (scope error, contract sec. 5); kept in the registry, not in the increment.
    jobs.append(dict(json.loads(json.dumps(g3)),id='s3_mut_state_in',mutant='s3p_state_in_kmac',oracle=r'^\[FAIL\] G\d\d_MEASUREMENT',dependencies=['s3_s8_golden'],independent=False))
    sr=s3mut(g3,'s3_mut_state_in_r2','s3p_state_in_kmac',r'^\[FAIL\] G\d\d_MEASUREMENT')
    sr['kill_scope']=r'^\[FAIL\] G\d\d_(MEASUREMENT|TAG|FULL_RESPONSE)$'   # the tag is computed over the measurement
    s3mut(g3,'s3_mut_lane_stuck','s3k_lane_stuck',r'^\[FAIL\] G\d\d_')
    s3mut(me,'s3_mut_pad_135','s3m_pad_135',r'^\[FAIL\] MEAS_EQUIV_DIGEST ')
    # A5 withdrawn (contract sec. 6): its mutant keeps its KILLED record of run 20261102_190244 but leaves the increment.
    jobs.append(dict(json.loads(json.dumps(g3)),id='s3_mut_absorb_zero',mutant='s3a_absorb_zero',oracle=r'^\[FAIL\] G\d\d_',dependencies=['s3_s8_golden'],independent=False))
    pn=json.loads(json.dumps(by3['p7_subsystem_pnr']))
    # Same as p7_subsystem_pnr: no cross-selection dependency (test_dual_lane SelectionDependencyTests); the P&R job hashes
    # its own exact source list, and s3_variant is checked in the s3 selection.
    pn.update(id='s3_p7_pnr',variant_of='p7_subsystem_pnr',selection='s3_pnr',sources=s3_list(pn['sources']),dependencies=[],independent=True)
    s3j(pn)
    # ---------------- I-6 (NOC-4; docs/decisions/I6_CONTRACT.md, DECISION_REGISTER I6-*): verifier busy retry, K-3 in the
    # endpoint, gate fault events, trusted inputs, fault status, C-5 window; edited in place (I6-INPLACE). Counts frozen in
    # the contract before the first run; regression copies keep their base count. Every list is the S3 list.
    by6={j['id']:j for j in jobs}
    i6=[]
    def i6j(j): jobs.append(j); i6.append(j['id']); return j
    I6_COPIES=[('tb_n2p7_rtt.sv','tb_n2p7_rtt_i6.sv'),('tb_p7_c4.sv','tb_p7_c4_i6.sv'),('tb_p7_gate_data.sv','tb_p7_gate_data_i6.sv'),
               ('tb_p7_ingress.sv','tb_p7_ingress_i6.sv'),('tb_p7_refuse_grant.sv','tb_p7_refuse_grant_i6.sv'),('tb_sys_f234_p7.sv','tb_sys_f234_p7_i6.sv'),
               ('tb_pq_endpoint_unit.sv','tb_pq_endpoint_unit_i6.sv')]
    I6_GEN=[T+b for a,b in I6_COPIES]+['sim/dual_lane/f234/tb_sys_f234_body_i6.svh']
    i6j(dict(id='i6_benches',kind='python',script='scripts/prepare_i6.py',positive_marker=r'^I6_BENCHES: PASS',
             sources=['scripts/prepare_i6.py','sim/dual_lane/i6/i6_provenance.json'],
             # hashed into the identity, never compiled together (original and copy share a module name)
             oracle_files=[T+a for a,b in I6_COPIES]+['sim/dual_lane/f234/tb_sys_f234_body.svh']+I6_GEN,
             dependencies=[],independent=True,selection='i6',sim_timeout=120))
    pl=json.loads(json.dumps(by6['policy_layer'])); pl.update(id='i6_policy_layer',variant_of='policy_layer',selection='i6'); i6j(pl)
    i6j(dict(id='i6_retry_vectors',kind='python',script='scripts/gen_i6_vectors.py',positive_marker=r'^I6_VECTORS: PASS',
             sources=['scripts/gen_i6_vectors.py','vectors/i6_retry.svh']+pl['sources'],dependencies=[],independent=True,selection='i6',sim_timeout=300))
    def i6copy(base,new,swap=None,**kw):
        v=json.loads(json.dumps(by6[base])); v.pop('mutant',None); v.pop('oracle',None); v.pop('kill_scope',None)
        src=s3_list(v['sources'])
        if swap: src=[T+swap[1] if x==T+swap[0] else x for x in src]
        v.update(id=new,variant_of=base,selection='i6',sources=src,dependencies=['i6_benches'] if swap else [],independent=not swap,
                 checks_basis='count unchanged from '+base+' (I-6 RTL'+(', C-5 0x2 copy from scripts/prepare_i6.py' if swap else '')+'; frozen in docs/decisions/I6_CONTRACT.md)')
        v.update(kw); return i6j(v)
    for base in ['s3_verifier_revoke','s3_s2_attacks']: i6copy(base,'i6_'+base[3:])
    i6copy('s3_pq_endpoint_unit','i6_pq_endpoint_unit',('tb_pq_endpoint_unit.sv','tb_pq_endpoint_unit_i6.sv'))
    i6copy('s3_n2p7_rtt','i6_n2p7_rtt',('tb_n2p7_rtt.sv','tb_n2p7_rtt_i6.sv'))
    i6copy('s3_p7_c4','i6_p7_c4',('tb_p7_c4.sv','tb_p7_c4_i6.sv'))
    i6copy('s3_f234_p7','i6_f234_p7',('tb_sys_f234_p7.sv','tb_sys_f234_p7_i6.sv'))
    for b in ['p7_gate_data','p7_ingress','p7_refuse_grant']: i6copy(b,'i6_'+b,(f'tb_{b}.sv',f'tb_{b}_i6.sv'))
    rt=i6copy('s3_verifier_revoke','i6_retry',top='tb_i6_retry',checks=24,include_dirs=['vectors'],tb_time_limit='50ms',sim_timeout=1800,
              config=dict(TOP='tb_i6_retry',CHECKS=24,TIMEOUT_CYCLES=3000),
              dependencies=['i6_retry_vectors'],independent=False,checks_basis='tb_i6_retry header: 12 + 6 + 2 + 2 + 1 + 1 = 24 (frozen in the I-6 contract before the first run)')
    rt['sources']=[x for x in rt['sources'] if not x.endswith('tb_verifier_revoke.sv')]+[T+'tb_i6_retry.sv']
    rt['oracle_files']=['vectors/i6_retry.svh','scripts/gen_i6_vectors.py','scripts/policy_layer.py']
    gt=i6copy('s3_n2p7_rtt','i6_gate',top='tb_i6_gate',checks=25,tb_time_limit='70ms',sim_timeout=3600,
              config=dict(TOP='tb_i6_gate',CHECKS=25,VERIFIER_TIMEOUT=3000),
              checks_basis='tb_i6_gate header: 25 named checks (frozen in the I-6 contract before the first run)')
    gt['sources']=[x for x in gt['sources'] if not x.endswith('tb_n2p7_rtt.sv')]+[T+'tb_i6_gate.sv']
    for j6 in (rt,gt):   # new benches: keep nothing bench-specific from the copied base job
        j6.pop('required_lines',None); j6.pop('variant_of',None)
    def i6mut(par,jid,kind,oracle,scope):
        return i6j(dict(json.loads(json.dumps(par)),id=jid,mutant=kind,oracle=oracle,kill_scope=scope,dependencies=[par['id']],independent=False))
    i6mut(rt,'i6_mut_retry_unbounded','i6v_retry_unbounded',r'^\[FAIL\] RETRY_PY_N[45]_',r'^\[FAIL\] RETRY_')
    i6mut(rt,'i6_mut_no_retry','i6v_no_retry',r'^\[FAIL\] RETRY_PY_N[123]_',r'^\[FAIL\] RETRY_')
    for jid,kind,oracle in [('i6_mut_gate_bypass','i6s_gate_bypass',r'^\[FAIL\] I6G_RESET_BLOCKED'),
                            ('i6_mut_issuer_off','i6s_issuer_off',r'^\[FAIL\] I6G_ISSUER_'),
                            ('i6_mut_revoke_ignored','i6s_revoke_ignored',r'^\[FAIL\] I6G_REVOKE_BLOCKS'),
                            ('i6_mut_trusted_off','i6s_trusted_off',r'^\[FAIL\] I6G_(K3_FAIL|TIMEOUT)_BLOCKS_LOCAL'),
                            ('i6_mut_fs_off','i6s_fs_off',r'^\[FAIL\] I6G_\w+_RECORD'),
                            ('i6_mut_k3_off','i6s_k3_off',r'^\[FAIL\] I6G_K3_RECORD'),
                            ('i6_mut_window_old','i6s_window_old',r'^\[FAIL\] I6G_(GRANT_WRITE_COMMITS|WINDOW_)')]:
        i6mut(gt,jid,kind,oracle,r'^\[FAIL\] I6G_')
    p6=json.loads(json.dumps(by6['s3_p7_pnr']))
    p6.update(id='i6_p7_pnr',variant_of='s3_p7_pnr',selection='i6_pnr',dependencies=[],independent=True); i6j(p6)
    # ---------------- I-7 (PQ-4 SEC-1..4 matrix, PQ-5 offline full chain on P7; docs/decisions/I7_SEC_MATRIX.md). New benches
    # are built with job() on the I-6 subsystem list (nothing bench-specific inherited); counts frozen in the contract.
    by7={j['id']:j for j in jobs}
    i7=[]
    def i7j(j): jobs.append(j); i7.append(j['id']); return j
    I7_REF=['scripts/gen_i7_vectors.py','scripts/policy_layer.py','scripts/s8_golden.py','scripts/full_chain_golden.py','scripts/l2_golden.py']+ADAPTER_REF
    i7j(dict(id='i7_vectors',kind='python',script='scripts/gen_i7_vectors.py',positive_marker=r'^I7_VECTORS: PASS',
             sources=I7_REF+['vectors/i7_sec.svh','vectors/full_chain.json'],dependencies=[],independent=True,selection='i7',sim_timeout=600))
    SUB7=[x for x in by7['i6_gate']['sources'] if not x.endswith('tb_i6_gate.sv')]
    sec=i7j(job('i7_sec','tb_i7_sec',SUB7+[T+'tb_i7_sec.sv'],30,selection='i7',include_dirs=['vectors'],
                tb_time_limit='90ms',config=dict(TOP='tb_i7_sec',CHECKS=30,ROWS=10),
                oracle_files=['vectors/i7_sec.svh','vectors/full_chain.svh']+I7_REF,
                checks_basis='tb_i7_sec header: 2 + 9 x 2 + 3 + 6 x 1 + 1 = 30 (frozen in docs/decisions/I7_SEC_MATRIX.md before the first run)'))
    sec.update(dependencies=['i7_vectors'],independent=False,defines=['PQ_MAC_ON'],sim_timeout=5400)
    fc=i7j(job('i7_full_chain','tb_pq_full_chain_p7',SUB7+[T+'tb_pq_full_chain_p7.sv'],21,selection='i7',include_dirs=['vectors'],
               tb_time_limit='100ms',config=dict(TOP='tb_pq_full_chain_p7',CHECKS=21,MODE='NON_DEMO'),
               oracle_files=['vectors/full_chain.svh','vectors/full_chain.json','scripts/full_chain_golden.py','scripts/s8_golden.py']+ADAPTER_REF,
               checks_basis='tb_pq_full_chain_p7 header: 3 x 4 + 1 + 5 + 1 + 1 + 1 = 21 (frozen in docs/decisions/I7_SEC_MATRIX.md before the first run)'))
    fc.update(defines=['PQ_MAC_ON'],sim_timeout=5400)
    gr=json.loads(json.dumps(by7['i6_gate'])); gr.update(id='i7_gate_regress',selection='i7',dependencies=[],independent=True,
        checks_basis='count unchanged from i6_gate (I-7 subsystem with the bench hooks)'); i7j(gr)
    def i7mut(par,jid,kind,oracle,scope):
        return i7j(dict(json.loads(json.dumps(par)),id=jid,mutant=kind,oracle=oracle,kill_scope=scope,dependencies=[par['id']],independent=False))
    for jid,kind,oracle in [('i7_mut_corrupt_response','ep_tag_swap',r'^\[FAIL\] SEC1_GENUINE_GRANT'),
                            ('i7_mut_tag_off','i7s_tag_off',r'^\[FAIL\] SEC_(WRONG_TAG|WRONG_KEY|WRONG_IDENTITY|STALE_EPOCH|ATTEST_REPLAY|NONCE_SUBST)_'),
                            ('i7_mut_meas_off','i7s_meas_off',r'^\[FAIL\] SEC(_WRONG_MEAS|4_SUBST)_'),
                            ('i7_mut_nonce_stale','i7v_nonce_stale',r'^\[FAIL\] SEC_ATTEST_REPLAY_'),
                            ('i7_mut_error_accepted','i7v_error_accepted',r'^\[FAIL\] SEC_ERROR_RESPONSE_'),
                            ('i7_mut_l2_seq_off','i7s_l2_seq_off',r'^\[FAIL\] SEC3_L2_REPLAY'),
                            ('i7_mut_l2_epoch_off','i7s_l2_epoch_off',r'^\[FAIL\] SEC3_RESET_REPLAY'),
                            ('i7_mut_peer_src_off','i7l_peer_src_off',r'^\[FAIL\] SEC2_SPOOF_RESPONSE')]:
        i7mut(sec,jid,kind,oracle,r'^\[FAIL\] SEC')
    i7mut(fc,'i7_fc_mut_tag_swap','ep_tag_swap',r'^\[FAIL\] FC_TXN\d_GRANT',r'^\[FAIL\] FC_')   # wire words swapped: the verifier refuses
    # ---------------- I-8 (NOC-5; docs/decisions/I8_RELEASE_PLAN.md): N-12 one-identity regression `rel` of every P7 job of
    # I-5, S3, I-6, I-7 (positives and controls) on the release list, plus the release P&R and the two N-13 implementations.
    by8={j['id']:j for j in jobs}
    i8=[]
    I6MAP={T+a:T+b for a,b in I6_COPIES}
    def rel_sources(src):
        out=s3_list(src) if S+'pq_keccak_f1600.sv' in src or D2V+'pq_keccak_f1600.sv' in src else list(src)
        return [I6MAP.get(x,x) for x in out]
    seen={}; relmap={}
    for jid in i5+s3+i6+i7:
        j=by8[jid]
        if j.get('kind')=='ooc' or jid=='s3_mut_state_in': continue
        v=json.loads(json.dumps(j))
        if v.get('kind')=='simulation': v['sources']=rel_sources(v['sources'])
        key=json.dumps([v.get('kind'),v.get('top'),v.get('script'),sorted(v.get('sources',[])),v.get('mutant'),v.get('defines'),v.get('include_dirs')])
        if key in seen: relmap[jid]=seen[key]; continue
        rid='rel_'+jid; seen[key]=rid; relmap[jid]=rid
        v.update(id=rid,selection='rel',release_of=jid)
        jobs.append(v); i8.append(rid)
    for rid in i8:
        v=next(j for j in jobs if j['id']==rid)
        v['dependencies']=sorted({relmap[d] for d in v.get('dependencies',[]) if d in relmap})
        v['independent']=not v['dependencies']
    rp=json.loads(json.dumps(by8['i6_p7_pnr'])); rp.update(id='rel_p7_pnr',selection='rel_pnr',release_of='i6_p7_pnr'); jobs.append(rp); i8.append(rp['id'])
    REL=by8['i6_p7_pnr']['sources']
    N13=dict(kind='implementation',defines=['PQ_MAC_ON'],constraints='synth/n13/pq_p7_n13.xdc',gate_script='scripts/n13_gate.tcl',
             child_script='scripts/n13_impl.tcl',oracle_files=['synth/n13/pq_p7_n13.xdc','scripts/n13_gate.tcl','scripts/n13_impl.tcl'],
             dependencies=[],independent=True,build_timeout=7200)
    jobs.append(dict(N13,id='n13_secure',top='pq_p7_n13_top',selection='n13_secure',
                     sources=REL+['synth/n13/n13_observe.sv','synth/n13/pq_p7_n13_top.sv'],
                     gate_label='N-13 secure implementation',scope='N-13 full P7 subsystem in the shift-chain + MISR real-pin top'))
    INSEC=[x for x in REL if not any(x.endswith(n) for n in ('noc_ingress_quarantine.sv','noc_ingress_parser.sv','noc_fault_status.sv'))
           and (x.startswith(S+'NOC') or x.startswith(S+'noc') or x.startswith(S+'allocator') or x.endswith(('NOC_PKG.sv','noc_p7_pkg.sv','noc_network_interface_p7.sv','rst_bridge.sv')))]
    jobs.append(dict(N13,id='n13_insecure',top='pq_p7_n13_insecure_top',selection='n13_insecure',
                     sources=INSEC+['synth/n13/n13_observe.sv','synth/n13/pq_p7_n13_insecure_top.sv'],
                     gate_label='N-13 insecure implementation',scope='N-13 insecure profile: mesh + 6 plain P7 NIs in the same top'))
    i8+=['n13_secure','n13_insecure']
    # ---------------- S4 (area package; docs/decisions/S4_AREA_CONTRACT.md, DECISION_REGISTER S4-*): A5 variants on the release
    # list, every release job they touch re-run (counts unchanged) with its Python dependencies, two A5 controls, and the
    # implementation jobs with -flatten_hierarchy rebuilt -directive AreaOptimized_high (job fields).
    by4={j['id']:j for j in jobs}
    s4=[]
    A5MAP={S+'kmac_128.sv':D2V+'kmac_128_a5.sv',D2V+'kmac_128_xp.sv':D2V+'kmac_128_xp_a5.sv'}
    def s4_list(src): return [A5MAP.get(x,x) for x in src]
    s4j=lambda j:(jobs.append(j),s4.append(j['id']),j)[2]
    s4j(dict(id='s4_variant',kind='python',script='scripts/check_s4.py',positive_marker=r'^S4_VARIANT: PASS',
             sources=['scripts/check_s4.py','scripts/prepare_s4.py','scripts/prepare_s3.py',D2V+'s4_provenance.json'],
             oracle_files=[D2V+'kmac_128_a5.sv',D2V+'kmac_128_xp_a5.sv',S+'kmac_128.sv'],dependencies=[],independent=True,selection='s4',sim_timeout=120))
    rel_ids=[i for i in i8 if by4[i].get('selection')=='rel']
    touched=[i for i in rel_ids if any(x in A5MAP for x in by4[i].get('sources',[]))]
    needed=set(touched)
    for i in list(touched): needed.update(by4[i].get('dependencies',[]))
    s4map={i:'s4_'+i[4:] for i in rel_ids if i in needed}
    for rid in [i for i in rel_ids if i in needed]:
        v=json.loads(json.dumps(by4[rid])); v.pop('release_of',None)
        v.update(id=s4map[rid],selection='s4',s4_of=rid,sources=s4_list(v.get('sources',[])))
        v['dependencies']=sorted({s4map[d] for d in v.get('dependencies',[]) if d in s4map}|({'s4_variant'} if rid in touched else set()))
        v['independent']=not v['dependencies']
        s4j(v)
    def s4mut(par,jid,kind,oracle,scope):
        return s4j(dict(json.loads(json.dumps(next(j for j in jobs if j['id']==par))),id=jid,mutant=kind,oracle=oracle,kill_scope=scope,dependencies=[par],independent=False))
    s4mut('s4_s3_s8_golden','s4_mut_absorb_zero_xp','s4x_absorb_zero',r'^\[FAIL\] G\d\d_',r'^\[FAIL\] G\d\d_')
    s4mut('s4_s3_l2e_engine','s4_mut_absorb_zero_core','s4a_absorb_zero',r'^\[FAIL\] L2E_DIGEST',r'^\[FAIL\] L2E_(DIGEST|RST_\w+_FRESH_OK)')
    FLOW=dict(synth_flatten='rebuilt',synth_directive='AreaOptimized_high')
    pn=json.loads(json.dumps(by4['rel_p7_pnr'])); pn.pop('release_of',None)
    pn.update(id='s4_p7_pnr',selection='s4_pnr',sources=s4_list(pn['sources']),dependencies=[],independent=True,**FLOW); s4j(pn)
    sc=json.loads(json.dumps(pn)); sc.update(id='s4_soc_pnr',selection='s4_soc_pnr',top='pq_p7_soc_core',
        sources=pn['sources']+['synth/p7_soc/pq_p7_soc_core.sv']); s4j(sc)
    for n in ('n13_secure','n13_insecure'):
        v=json.loads(json.dumps(by4[n])); v.update(id='s4_'+n,selection='s4_'+n,sources=s4_list(v['sources']),**FLOW); s4j(v)
    # S4 revision 1 (S4_AREA_CONTRACT.md sec. 6, S4-F3): the four implementation jobs again with the mesh split. They replace
    # s4_p7_pnr / s4_soc_pnr / s4_n13_* in the S4 increment; those stay registered with their FAIL / INVALID / PASS history.
    byid={j['id']:j for j in jobs}
    SPLIT=['scripts/s4_mesh_split.tcl','synth/s4/noc_mesh_3x2_bb.sv']
    for old,new,sel in [('s4_p7_pnr','s4r_p7_pnr','s4r_pnr'),('s4_soc_pnr','s4r_soc_pnr','s4r_soc_pnr'),
                        ('s4_n13_secure','s4r_n13_secure','s4r_n13_secure'),('s4_n13_insecure','s4r_n13_insecure','s4r_n13_insecure')]:
        v=json.loads(json.dumps(byid[old])); v.update(id=new,selection=sel,synth_mesh_split=True,
            oracle_files=list(v.get('oracle_files',[]))+SPLIT); jobs.append(v)
        s4[s4.index(old)]=new
    # ---------------- I-9 (integration; M-F1 rev 8, signed 2026-11-05; docs/decisions/M-F1-rev8-INTEGRATION-DRAFT.md sec. 11).
    # Same-module variants (scripts/prepare_i9.py) swapped into the current list (S4 where it exists, else release); every
    # current simulation job that compiles one of them re-run on the I-9 list with its frozen count (positives and controls);
    # the new integration bench tb_i9_integ (13 checks, frozen here before its first run) and five controls.
    import prepare_i9
    I9MAP=prepare_i9.I9MAP
    by9={j['id']:j for j in jobs}
    i9=[]
    def i9j(j): jobs.append(j); i9.append(j['id']); return j
    i9j(dict(id='i9_variant',kind='python',script='scripts/check_i9.py',positive_marker=r'^I9_VARIANT: PASS',
             sources=['scripts/check_i9.py','scripts/prepare_i9.py','scripts/prepare_s3.py',D2V+'i9_provenance.json'],
             oracle_files=sorted(set(I9MAP)|set(I9MAP.values())),dependencies=[],independent=True,selection='i9',sim_timeout=120))
    superseded={by9[i].get('s4_of') for i in s4 if by9[i].get('s4_of')}
    current=[i for i in s4 if by9[i].get('kind')=='simulation']+[i for i in i8 if by9[i].get('kind')=='simulation' and i not in superseded]
    hit=[i for i in current if any(x in I9MAP for x in by9[i].get('sources',[]))]
    i9map={i:'i9r_'+i.split('_',1)[1] for i in hit}
    for oid in hit:
        v=json.loads(json.dumps(by9[oid])); v.pop('s4_of',None); v.pop('release_of',None)
        v.update(id=i9map[oid],selection='i9',i9_of=oid,sources=[I9MAP.get(x,x) for x in v['sources']])
        v['dependencies']=sorted({i9map[d] for d in v.get('dependencies',[]) if d in i9map}|{'i9_variant'})
        v['independent']=False
        i9j(v)
    SUB9=[I9MAP.get(x,x) for x in by9['s4_i6_gate']['sources'] if not x.endswith('tb_i6_gate.sv')]
    it=i9j(job('i9_integ','tb_i9_integ',SUB9+[T+'tb_i9_integ.sv'],13,selection='i9',include_dirs=['vectors'],
               tb_time_limit='40ms',
               config=dict(TOP='tb_i9_integ',CHECKS=13,VERIFIER_TIMEOUT=3000,NI_SLOT_TIMEOUT=600,MEM_ADDR_BITS=14),
               oracle_files=['vectors/full_chain.svh','vectors/full_chain.json','scripts/full_chain_golden.py','scripts/s8_golden.py']+ADAPTER_REF,
               checks_basis='tb_i9_integ header: 13 named checks (frozen in the I-9 registry before the first run; M-F1 rev 8 sec. 11)'))
    it.update(dependencies=['i9_variant'],independent=False,defines=['PQ_MAC_ON'],sim_timeout=5400)
    for jid,kind,oracle in [('i9_mut_no_timeout','i9n_no_timeout',r'^\[FAIL\] I9_SLOT_RECOVER'),
                            ('i9_mut_stale_deliver','i9n_stale_deliver',r'^\[FAIL\] I9_STALE_DROPPED'),
                            ('i9_mut_rx_all','i9s_rx_all',r'^\[FAIL\] I9_RX_ACCOUNTED'),
                            ('i9_mut_bram_lanes','i9s_bram_lanes',r'^\[FAIL\] I9_BYTE_LANES'),
                            ('i9_mut_window_1k','i9s_window_1k',r'^\[FAIL\] I9_WINDOW_TOP_OK')]:
        i9j(dict(json.loads(json.dumps(it)),id=jid,mutant=kind,oracle=oracle,kill_scope=r'^\[FAIL\] I9_',dependencies=['i9_integ'],independent=False))
    # ---------------- I-10 (I9-D2 qualification, Kalash 2026-11-05 "Yes, run I-10"): K-3 re-provisioned to config 16 / IMEM 64
    # in the P7 subsystem (I-9 list, K3_IMEM_LEN = 64 by bench parameter; RTL unchanged). Oracle: scripts/d2_golden.py over the
    # pinned teammate reference + hashlib cross-check; bench tb_i10_d2 (12 checks, frozen here before its first registered run;
    # a bench-only fix of the k3_fault pulse sampling was made in scratch before this freeze); two endpoint controls.
    i10=[]
    def i10j(j): jobs.append(j); i10.append(j['id']); return j
    i10j(dict(json.loads(json.dumps(next(j for j in jobs if j['id']=='i9_variant'))),id='i10_variant',selection='i10'))
    D2_ORACLE=['scripts/d2_golden.py','scripts/s8_golden.py','vectors/d2_k3_64.json','vectors/d2_k3_64.svh']+ADAPTER_REF
    i10j(dict(id='i10_oracle',kind='python',script='scripts/d2_golden.py',positive_marker=r'^D2_ORACLE: PASS',
              sources=['scripts/d2_golden.py','scripts/s8_golden.py'],oracle_files=D2_ORACLE,dependencies=[],independent=True,
              selection='i10',sim_timeout=300))
    SUB10=[I9MAP.get(x,x) for x in by9['s4_i6_gate']['sources'] if not x.endswith('tb_i6_gate.sv')]
    d2=i10j(job('i10_d2','tb_i10_d2',SUB10+[T+'tb_i10_d2.sv'],12,selection='i10',include_dirs=['vectors'],tb_time_limit='60ms',
               config=dict(TOP='tb_i10_d2',CHECKS=12,K3_CONFIG_LEN=16,K3_IMEM_LEN=64,VECTORS='d2_k3_64'),
               oracle_files=D2_ORACLE+['vectors/full_chain.svh'],
               checks_basis='tb_i10_d2 header: 12 named checks (frozen in the I-10 registry before the first registered run; I9-D2)'))
    d2.update(dependencies=['i10_variant','i10_oracle'],independent=False,defines=['PQ_MAC_ON'],sim_timeout=5400)
    # Engineer 4 verification suite (vendored verification/, intake reports/E4_PACKAGE_INTAKE_20261105.md; Kalash "Yes, import it"):
    # Python model checks re-run on the live sources in a staged copy; frozen 224 pytest / 15 stages (scripts/e4_verification.py).
    E4V=sorted(str(p.relative_to(ROOT)).replace(chr(92),'/') for p in (ROOT/'verification').rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    i10j(dict(id='e4_verification',kind='python',script='scripts/e4_verification.py',
              positive_marker=r'^E4_VERIFICATION: PASS \(pytest 224 passed; regression 15/15\)$',
              sources=['scripts/e4_verification.py']+E4V,oracle_files=sorted(str(p.relative_to(ROOT)).replace(chr(92),'/') for d in ('rtl','NOC_PQATTEST.srcs/sources_1','NOC_PQATTEST.srcs/sim_1','docs/handoff/E4_P7_XSIM_20261103') for p in (ROOT/d).rglob('*') if p.is_file())+['software/kmac128_ref.py','software/gen_stage7_vectors.py',
              'logs/s3_kmac_2026-09-23.log'],dependencies=[],independent=True,selection='i10',sim_timeout=1200))
    for jid,kind,oracle in [('i10_mut_k3_imem_unchecked','i10e_k3_imem_unchecked',r'^\[FAIL\] D2_IMEM16_REFUSED'),
                            ('i10_mut_window16','i10e_window16',r'^\[FAIL\] D2_BYTE16_BOUND')]:
        i10j(dict(json.loads(json.dumps(d2)),id=jid,mutant=kind,oracle=oracle,kill_scope=r'^\[FAIL\] D2_',dependencies=['i10_d2'],independent=False))
    # ---------------- I-11 (Kalash 2026-11-06: "Import + new job", "Triage + implement gaps"; reports/E4_FINAL_INTAKE_20261106.md).
    # Engineer 4 final suite (frozen 387 / 15) and the real RTL controls from triaging E4's Step 18 proposals: two oracle gaps
    # closed by the spec-literal bench tb_i11_noc_spec (44 checks, frozen here before its first registered run) and one
    # window-overshoot control on the unchanged tb_i9_integ (13 checks). RTL is unchanged.
    i11=[]
    def i11j(j): jobs.append(j); i11.append(j['id']); return j
    i11j(dict(json.loads(json.dumps(next(j for j in jobs if j['id']=='i9_variant'))),id='i11_variant',selection='i11'))
    E4V2=sorted(str(p.relative_to(ROOT)).replace(chr(92),'/') for p in (ROOT/'verification').rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    E4V2_IN=sorted(str(p.relative_to(ROOT)).replace(chr(92),'/') for d in ('rtl','NOC_PQATTEST.srcs/sources_1','NOC_PQATTEST.srcs/sim_1','docs/handoff/E4_P7_XSIM_20261103') for p in (ROOT/d).rglob('*') if p.is_file())
    i11j(dict(id='e4_verification_v2',kind='python',script='scripts/e4_verification_v2.py',
              positive_marker=r'^E4_VERIFICATION_V2: PASS \(pytest 387 passed; regression 15/15\)$',
              sources=['scripts/e4_verification_v2.py','scripts/e4_verification.py']+E4V2,
              oracle_files=E4V2_IN+['software/kmac128_ref.py','software/gen_stage7_vectors.py','logs/s3_kmac_2026-09-23.log',
                                    'reports/n25_2026-09-23/paths_lt3ns.csv','_export/PQ_Attest_S4_Evidence_20261105.zip'],
              dependencies=[],independent=True,selection='i11',sim_timeout=1800))
    sp=i11j(job('i11_noc_spec','tb_i11_noc_spec',['rtl/dual_lane/NOC_PKG.sv','NOC_PQATTEST.srcs/sources_1/new/NOC_XY_ROUTING.sv',T+'tb_i11_noc_spec.sv'],44,
                selection='i11',tb_time_limit='1ms',config=dict(TOP='tb_i11_noc_spec',CHECKS=44,SPEC='M-F1-literal'),
                checks_basis='tb_i11_noc_spec header: 36 XY routes + 8 VC map rows, literals from M-F1 (frozen in the I-11 registry before the first run)'))
    sp.update(dependencies=['i11_variant'],independent=False)
    for jid,kind,oracle in [('i11_mut_yfirst','i11r_yfirst',r'^\[FAIL\] SPEC_XY_'),('i11_mut_attest_vc0','i11p_attest_vc0',r'^\[FAIL\] SPEC_VC_ATTEST_')]:
        i11j(dict(json.loads(json.dumps(sp)),id=jid,mutant=kind,oracle=oracle,kill_scope=r'^\[FAIL\] SPEC_',dependencies=['i11_noc_spec'],independent=False))
    ig=i11j(dict(json.loads(json.dumps(next(j for j in jobs if j['id']=='i9_integ'))),id='i11_i9_integ',selection='i11',dependencies=['i11_variant']))
    i11j(dict(json.loads(json.dumps(ig)),id='i11_mut_window_over',mutant='i11s_window_over',oracle=r'^\[FAIL\] I9_WINDOW_OUT_ERR',
              kill_scope=r'^\[FAIL\] I9_',dependencies=['i11_i9_integ'],independent=False))
    # ---------------- I-12 (Kalash 2026-11-06 "final zip from eng 4 check nd integrate"; reports/E4_CORRECTED_INTAKE_20261106.md).
    # Engineer 4 corrected suite (Step 12 / 13 rebuilt from registered evidence, Step 18 reconciled, D2 files renamed):
    # e4_verification_v3 frozen 389 / 15. Python model checking only; RTL unchanged.
    i12=[]
    E4V3=sorted(str(p.relative_to(ROOT)).replace(chr(92),'/') for p in (ROOT/'verification').rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    E4V3_IN=sorted(str(p.relative_to(ROOT)).replace(chr(92),'/') for d in ('rtl/dual_lane','NOC_PQATTEST.srcs/sources_1','NOC_PQATTEST.srcs/sim_1','docs/handoff/E4_P7_XSIM_20261103') for p in (ROOT/d).rglob('*') if p.is_file())
    jobs.append(dict(id='e4_verification_v3',kind='python',script='scripts/e4_verification_v3.py',
              positive_marker=r'^E4_VERIFICATION_V3: PASS \(pytest 389 passed; regression 15/15\)$',
              sources=['scripts/e4_verification_v3.py','scripts/e4_verification_v2.py','scripts/e4_verification.py']+E4V3,
              oracle_files=E4V3_IN+['vectors/d2_k3_64.json','vectors/d2_k3_64.svh','software/kmac128_ref.py','software/gen_stage7_vectors.py',
                                    'logs/s3_kmac_2026-09-23.log','reports/n25_2026-09-23/paths_lt3ns.csv','_export/PQ_Attest_S4_Evidence_20261105.zip'],
              dependencies=[],independent=True,selection='i12',sim_timeout=1800))
    i12.append('e4_verification_v3')
    # ---------------- I-13 (RISC-V takeover R-1 / R-2 unit and tile benches; Kalash 2026-11-06 "work autonmsly taskwise",
    # decisions by VLSI review; docs/riscv_lane/R1_BATCH_SCRATCH_20261106.txt, B2_SCRATCH_20261106.txt, B1_NOTES.md, B3_NOTES.md).
    # Counts are the bench-header counts, frozen before each bench's first run and before this registration. Positive jobs only:
    # the scratch mutants (A1 no-guard, A3 no-poison, B2 sideband, B1 5/5, B3 3/3) need new harness mutant kinds (later, with
    # negative tests). The imported legacy benches without CHECKS/ERRORS/RESULT lines and the two hex-file benches
    # (tb_tile_top, tb_two_tiles) are not registered here.
    i13=[]
    def i13j(j): jobs.append(j); i13.append(j['id']); return j
    RV='rtl/riscv/'; SR='sim_riscv/'
    TILE=['rtl/dual_lane/NOC_PKG.sv']+[RV+f for f in ['picorv32.v','picorv32_adapter.sv','addr_decode.sv','uart_tx.sv','uart_mmio.sv',
          'gpio.sv','tile_status.sv','tile_top.sv','mem_bram.sv','tile_mem_wrapper.sv','reset_sync.sv','tmem_app_bridge.sv',
          'meas_window_reader.sv','cpu_tile_noc.sv']]
    for jid,top,srcs,n,lim,extra in [
        ('r1_mem_bram_dp','tb_mem_bram_dp',[RV+'mem_bram.sv'],6,'1ms',{}),
        ('r1_tile_status','tb_tile_status',[RV+'tile_status.sv'],14,'1ms',{}),
        ('r1_addr_decode_v2','tb_addr_decode_v2',[RV+'addr_decode.sv'],12,'1ms',{}),
        ('r1_gpio','tb_gpio',[RV+'gpio.sv'],4,'1ms',{'noconfig':True}),
        ('r1_adapter_a3','tb_adapter_a3',[RV+'picorv32_adapter.sv'],8,'1ms',{}),
        ('r2_tmem_app_bridge','tb_tmem_app_bridge',['rtl/dual_lane/NOC_PKG.sv',RV+'tmem_app_bridge.sv'],19,'60ms',{}),
        ('r2_meas_window_reader','tb_meas_window_reader',[RV+'meas_window_reader.sv'],10,'3ms',{'include_dirs':['vectors'],
            'oracle_files':['vectors/d2_k3_64.json','vectors/d2_k3_64.svh']}),
        ('r2_cpu_tile_noc','tb_cpu_tile_noc',TILE,12,'3ms',{})]:
        kw=dict(selection='i13',tb_time_limit=lim,checks_basis=top+' header: '+str(n)+' named checks (frozen before its first run; I-13 registry)')
        if not extra.pop('noconfig',False): kw['config']=dict(TOP=top,CHECKS=n)
        kw.update(extra)
        i13j(job(jid,top,srcs+[SR+top+'.sv'],n,**kw))
    # ---------------- I-14 (RISC-V takeover: tile-level benches, demo firmware, B5 checker and harness mutant controls;
    # Lane 1 2026-11-07, autonomous under Kalash's instruction, VLSI review). Counts = bench headers, frozen before each first
    # run. Mutant kinds rva_ / rvc_ / rvb_ / rvm_ (dual_lane.mutation, negative tests RVMutationTests); every kill was checked
    # in scratch with the harness judge rules before this registration (reports/OVERNIGHT_20261107.md).
    i14=[]
    def i14j(j): jobs.append(j); i14.append(j['id']); return j
    def i13copy(jid,new): return dict(json.loads(json.dumps(next(j for j in jobs if j['id']==jid))),id=new,selection='i14')
    TILE14=[s for s in TILE if not s.endswith('reset_sync.sv')]   # cpu_tile_noc no longer instantiates reset_sync (B7 DRC fix)
    TWO=[RV+f for f in ['picorv32.v','picorv32_adapter.sv','addr_decode.sv','uart_tx.sv','uart_mmio.sv','gpio.sv','tile_status.sv',
         'tile_top.sv','mem_bram.sv','tile_mem_wrapper.sv','memory_tile.sv']]
    tt=i14j(job('i14_two_tiles','tb_two_tiles',TWO+[SR+'tb_two_tiles.sv'],8,selection='i14',include_dirs=['sim_riscv/include'],
                tb_time_limit='80ms',oracle_files=['sw/riscv/hello_words.hex','scripts/hex_to_svh.py'],
                checks_basis='tb_two_tiles header: 8 named checks (frozen before its first run; I-14 registry)'))
    ct=i14j(job('i14_cpu_tile_noc','tb_cpu_tile_noc',TILE14+[SR+'tb_cpu_tile_noc.sv'],12,selection='i14',tb_time_limit='3ms',
                config=dict(TOP='tb_cpu_tile_noc',CHECKS=12),checks_basis='tb_cpu_tile_noc header: 12 named checks (I-13 count; re-run after the reset change)'))
    i14j(job('i14_demo_fw','tb_demo_fw',TILE14+[SR+'tb_cpu_tile_noc.sv',SR+'tb_demo_fw.sv'],9,selection='i14',include_dirs=['sim_riscv/include'],
             tb_time_limit='25ms',config=dict(TOP='tb_demo_fw',CHECKS=9,FW='demo_fw'),
             oracle_files=['sw/riscv/demo_fw.S','sw/riscv/demo_fw.hex','scripts/rv32_asm.py','scripts/hex_to_svh.py'],
             checks_basis='tb_demo_fw header: 9 named checks (frozen before its first run; I-14 registry)'))
    b5=i14j(job('i14_app_port_checker','tb_app_port_checker',['rtl/dual_lane/NOC_PKG.sv',RV+'tmem_app_bridge.sv',SR+'app_port_checker.sv',
                SR+'tb_app_port_checker.sv'],10,selection='i14',tb_time_limit='60ms',config=dict(TOP='tb_app_port_checker',CHECKS=10),
                checks_basis='tb_app_port_checker header: 10 named checks (fork commit aced7452; frozen before its first run)'))
    for j in jobs:
        if j['id'] in ('i14_two_tiles','i14_demo_fw','i14_app_port_checker'): j['sim_timeout']=1800
    for jid,base,kind,oracle,scope in [
        ('i14_mut_no_poison',i13copy('r1_adapter_a3','x'),'rva_no_poison',r'^\[FAIL\] A3_REMOTE_ERR_POISON',r'^\[FAIL\] A3_'),
        ('i14_mut_no_guard',tt,'rva_no_guard',r'^\[FAIL\] T2_TILE0_COUNTS',r'^\[FAIL\] (T2_|A1_)'),
        ('i14_mut_sideband',ct,'rvc_sideband_zero',r'^\[FAIL\] CTN_UNAUTH_POISON',r'^\[FAIL\] CTN_'),
        ('i14_mut_auth_removed',i13copy('r2_tmem_app_bridge','x'),'rvb_auth_removed',r'^\[FAIL\] B1_REFUSED_UNAUTH',r'^\[FAIL\] B1_'),
        ('i14_mut_word_order',i13copy('r2_meas_window_reader','x'),'rvm_word_order',r'^\[FAIL\] B3_WINDOW_ROW0',r'^\[FAIL\] B3_'),
        ('i14_mut_b5_auth_removed',b5,'rvb_auth_removed',r'^\[FAIL\] B5_CLEAN_ZERO_VIOLATIONS',r'^\[FAIL\] (B5_|B1_SVA_)')]:
        dep=[base['id']] if base['id'] in i14 else []
        i14j(dict(json.loads(json.dumps(base)),id=jid,selection='i14',mutant=kind,oracle=oracle,kill_scope=scope,dependencies=dep,independent=not dep))
    # ---------------- I-15 (R-4 merge; Lane 1 2026-11-07, autonomous, VLSI review): the B6 co-simulation of the merged SoC with
    # the REAL cpu_tile_noc at tiles 3 and 0 running sw/riscv/demo_fw (tb_merged_real, 10 checks frozen before its first run),
    # on the merged list of scripts/make_merged_sources.py minus the board top (MMCM primitive), plus one control: the B3
    # word order reversed must break the measured window, the response and GRANT (kill pre-checked in scratch).
    import make_merged_sources
    i15=[]
    def i15j(j): jobs.append(j); i15.append(j['id']); return j
    MSRC=[s for s in make_merged_sources.build()[0] if not s.endswith('pq_merged_board_top.sv')]
    mr=i15j(job('i15_merged_real','tb_merged_real',MSRC+['rtl/dual_lane/merged/tb_merged_real.sv'],10,selection='i15',
                include_dirs=['vectors','sim_riscv/include'],tb_time_limit='80ms',
                config=dict(TOP='tb_merged_real',CHECKS=10,FW='demo_fw',CPU_TILE='cpu_tile_noc'),
                oracle_files=['scripts/make_merged_sources.py','scripts/merged_provision.py','sw/riscv/demo_fw.S','sw/riscv/demo_fw.hex',
                              'scripts/rv32_asm.py','vectors/d2_k3_64.json','vectors/d2_k3_64.svh','vectors/full_chain.svh'],
                checks_basis='tb_merged_real header: 10 named checks (frozen before its first run; I-15 registry)'))
    mr.update(defines=['PQ_MAC_ON','CPU_TILE_MODULE=cpu_tile_noc'],sim_timeout=3600)
    i15j(dict(json.loads(json.dumps(mr)),id='i15_mut_word_order',mutant='rvm_word_order',oracle=r'^\[FAIL\] MR_RESPONSE',
              kill_scope=r'^\[FAIL\] MR_',dependencies=['i15_merged_real'],independent=False))
    # ---------------- I-16 (RISC-V completion items; Lane 1 2026-11-07, autonomous, VLSI review): A6 decode table, A7 memtest,
    # A5 second program (tb_two_programs) and the A5 adapter assertions (A5_REQ_STABLE / A5_RESPONSE_WITHOUT_REQ, simulation
    # messages: any [FAIL] line makes a positive job INVALID). The benches that compile the adapter are re-run on the changed file.
    i16=[]
    def i16j(j): jobs.append(j); i16.append(j['id']); return j
    def cp16(jid,new): return dict(json.loads(json.dumps(next(j for j in jobs if j['id']==jid))),id=new,selection='i16',dependencies=[],independent=True)
    i16j(job('i16_bridge_decode_table','tb_bridge_decode_table',['rtl/dual_lane/NOC_PKG.sv',RV+'tmem_app_bridge.sv',SR+'tb_cpu_tile_noc.sv',
             SR+'tb_bridge_decode_table.sv'],18,selection='i16',tb_time_limit='5ms',config=dict(TOP='tb_bridge_decode_table',CHECKS=18),
             checks_basis='tb_bridge_decode_table header: 18 named checks (frozen before its first run)'))
    i16j(job('i16_memtest','tb_memtest',TILE14+[SR+'tb_memtest.sv'],4,selection='i16',include_dirs=['sim_riscv/include'],tb_time_limit='20ms',
             config=dict(TOP='tb_memtest',CHECKS=4,FW='memtest'),oracle_files=['sw/riscv/memtest.S','sw/riscv/memtest.hex','scripts/rv32_asm.py'],
             checks_basis='tb_memtest header: 4 named checks (frozen before its first run)'))
    tp=i16j(job('i16_two_programs','tb_two_programs',TWO+[SR+'tb_two_programs.sv'],9,selection='i16',include_dirs=['sim_riscv/include'],
             tb_time_limit='80ms',oracle_files=['sw/riscv/hello_words.hex','sw/riscv/memtest.S','sw/riscv/memtest.hex'],
             checks_basis='tb_two_programs header: 9 named checks (frozen before its first run)'))
    tp['sim_timeout']=1800
    for old,new in [('r1_adapter_a3','i16_adapter_a3'),('i14_cpu_tile_noc','i16_cpu_tile_noc'),('i14_demo_fw','i16_demo_fw'),
                    ('i14_two_tiles','i16_two_tiles'),('i15_merged_real','i16_merged_real'),('i14_mut_no_guard','i16_mut_no_guard')]:
        i16j(cp16(old,new))
    next(j for j in jobs if j['id']=='i16_mut_no_guard').update(dependencies=['i16_two_tiles'],independent=False,
        kill_scope=r'^\[FAIL\] (T2_|A1_|A5_)')   # the A5 adapter assertions may also report under the no-guard mutant
    # ---------------- I-17 (Lane 1 2026-11-07, Kalash "Yes, build the gate"): harness implementation gate for the MERGED board top
    # (pq_merged_board_top: NoC + PQ-Attest + two real RISC-V tiles + demo firmware). Child scripts/merged_impl.tcl = the steps
    # of the release flow that built the board image (merged_bitstream_flow.tcl); gate scripts/merged_board_gate.tcl = N-13
    # criteria + MMCM clock proof + firmware-in-netlist proof + LUT <= 47,550. Runs alone (synthesis / implementation rule).
    i17=[]
    MBOARD=make_merged_sources.build()[0]
    jobs.append(dict(id='i17_merged_board',kind='implementation',top='pq_merged_board_top',sources=MBOARD,
                     defines=['PQ_MAC_ON','CPU_TILE_MODULE=cpu_tile_noc','REAL_CPU_TILE'],constraints='synth/merged/pq_merged_board_arty.xdc',
                     gate_script='scripts/merged_board_gate.tcl',child_script='scripts/merged_impl.tcl',include_dirs=['sw/riscv'],
                     synth_mesh_split=True,
                     oracle_files=['synth/merged/pq_merged_board_arty.xdc','scripts/merged_board_gate.tcl','scripts/merged_impl.tcl',
                                   'scripts/s4_mesh_split.tcl','synth/s4/noc_mesh_3x2_bb.sv',
                                   'scripts/make_merged_sources.py','sw/riscv/demo_fw.S','sw/riscv/demo_fw.hex'],
                     dependencies=[],independent=True,selection='i17',build_timeout=7200,
                     gate_label='merged board implementation',scope='merged SoC board top (real pins, MMCM 100 -> 50 MHz), demo firmware'))
    i17.append('i17_merged_board')
    i18=[]
    irq=job('i18_cpu_irq','tb_cpu_irq_acceptance',TILE14+[SR+'tb_cpu_irq_acceptance.sv'],10,selection='i18',
            include_dirs=['sim_riscv/include'],tb_time_limit='1ms',config=dict(TOP='tb_cpu_irq_acceptance',CHECKS=10),
            oracle_files=['sw/riscv/irq_acceptance.S','scripts/rv32_asm.py','docs/decisions/M-F1-rev9-RTL-CLOSURE.md'],
            checks_basis='I-18 header: 3 real-core fault cases x handler/order/status plus bounded completion = 10; frozen before first run')
    irq.update(defines=['RISCV_FORMAL'],sim_timeout=900)
    jobs.append(irq);i18.append(irq['id'])
    jobs.append(dict(json.loads(json.dumps(irq)),id='i18_mut_irq_off',mutant='rvt_irq_off',
                     oracle=r'^\[FAIL\] IRQ_HANDLER_',kill_scope=r'^\[FAIL\] IRQ_',dependencies=['i18_cpu_irq'],independent=False))
    i18.append('i18_mut_irq_off')
    i19=[]
    ni=job('i19_ni','tb_closure_ni',TILE14+[SR+'tb_closure_ni.sv'],8,selection='i19',include_dirs=['sim_riscv/include'],
           tb_time_limit='1ms',config=dict(TOP='tb_closure_ni',CHECKS=8),oracle_files=['sw/riscv/ni_status_acceptance.S'],
           checks_basis='I-19 frozen: six NI MMIO semantics, debug-fetch stability, bounded parameter profile')
    jobs.append(ni);i19.append(ni['id'])
    for suffix,kind,oracle in [('ni_zero','rvt_ni_count_zero',r'^\[FAIL\] NI_REFUSED_COUNT'),('debug','rvt_debug_data',r'^\[FAIL\] NI_DEBUG_FETCH_HOLDS')]:
        j=dict(json.loads(json.dumps(ni)),id='i19_mut_'+suffix,mutant=kind,oracle=oracle,kill_scope=r'^\[FAIL\] NI_',dependencies=['i19_ni'],independent=False)
        jobs.append(j);i19.append(j['id'])
    j=job('i19_parameters','tb_closure_parameters',MSRC+[SR+'tb_closure_parameters.sv'],3,selection='i19',tb_time_limit='1ms',
          config=dict(TOP='tb_closure_parameters',CHECKS=3),checks_basis='3 frozen merged timeout parameter propagation checks')
    j['defines']=['PQ_MAC_ON','CPU_TILE_MODULE=cpu_tile_noc'];jobs.append(j);i19.append(j['id'])
    for old,new in [('i18_cpu_irq','i19_cpu_irq'),('i14_cpu_tile_noc','i19_cpu_tile'),('r1_addr_decode_v2','i19_decoder')]:
        j=dict(json.loads(json.dumps(next(j for j in jobs if j['id']==old))),id=new,selection='i19',dependencies=[],independent=True)
        jobs.append(j);i19.append(j['id'])
    i20=[]
    profile_files=['scripts/gen_closure_profile.py','scripts/rv32_asm.py','scripts/s8_golden.py','sw/riscv/demo_fw_v2.S',
                   'sw/riscv/demo_fw_v2.hex','sw/riscv/closure_profile.svh','sim_riscv/include/demo_fw_v2.svh',
                   'sim_riscv/include/closure_profile.svh','vectors/closure_profile_v9.json']+ADAPTER_REF
    j=dict(id='i20_profile',kind='python',script='scripts/check_closure_profile.py',sources=[],oracle_files=profile_files,
           dependencies=[],independent=True,selection='i20',sim_timeout=120,positive_marker=r'^CLOSURE_PROFILE_V9: PASS')
    jobs.append(j);i20.append(j['id'])
    v2=job('i20_firmware','tb_firmware_v2',TILE14+[SR+'tb_cpu_tile_noc.sv',SR+'tb_firmware_v2.sv'],12,
           selection='i20',include_dirs=['sim_riscv/include'],tb_time_limit='60ms',
           config=dict(TOP='tb_firmware_v2',CHECKS=12),oracle_files=profile_files,
           checks_basis='12 frozen v2 real-CPU checks: IRQ return, admission/refusal/revoke/recovery/accounting/measurement/UART')
    v2.update(sim_timeout=1800,dependencies=['i20_profile'],independent=False)
    jobs.append(v2);i20.append(v2['id'])
    j=dict(json.loads(json.dumps(v2)),id='i20_mut_irq_off',mutant='rvt_irq_off',oracle=r'^\[FAIL\] V2_REFUSED',
           kill_scope=r'^\[FAIL\] V2_',dependencies=['i20_firmware'])
    jobs.append(j);i20.append(j['id'])
    i21=[]
    for jid,top,n,kind,oracle in [
        ('i21_merged_closure','tb_merged_closure',14,'rvm_word_order',r'^\[FAIL\] MC_RESPONSE'),
        ('i21_merged_error','tb_merged_error',6,'rva_no_poison',r'^\[FAIL\] ME_REMOTE_POISON')]:
        j=job(jid,top,MSRC+['rtl/dual_lane/merged/'+top+'.sv'],n,selection='i21',
              include_dirs=['vectors','sim_riscv/include'],tb_time_limit='80ms',
              config=dict(TOP=top,CHECKS=n,FW='demo_fw_v2'),
              oracle_files=profile_files+['vectors/full_chain.svh','vectors/d2_k3_64.svh'],
              checks_basis='I-21 header: '+str(n)+' frozen merged real-core closure checks')
        j.update(defines=['PQ_MAC_ON','CPU_TILE_MODULE=cpu_tile_noc'],sim_timeout=3600)
        jobs.append(j);i21.append(jid)
        scope=r'^\[FAIL\] MC_(?!CPU_B_)' if n==14 else r'^\[FAIL\] ME_'
        m=dict(json.loads(json.dumps(j)),id=jid+'_control',mutant=kind,oracle=oracle,kill_scope=scope,dependencies=[jid],independent=False)
        jobs.append(m);i21.append(m['id'])
    i22=['i22_release_acceptance']
    jobs.append(dict(id='i22_release_acceptance',kind='python',script='scripts/test_merged_release.py',sources=[],
                     oracle_files=['scripts/merged_release.py'],dependencies=[],independent=True,selection='i22',sim_timeout=120,
                     positive_marker=r'^MERGED_RELEASE_TESTS: PASS checks=15$'))
    i23=[]
    for jid,top,n,kind,oracle,scope in [
        ('i23_inflight','tb_merged_inflight',6,'rvg_ignore_revoke',r'^\[FAIL\] IF_AUTH_BOUNDARY_BOUND',r'^\[FAIL\] IF_'),
        ('i23_contention','tb_merged_contention',8,'rvo_drop_busy',r'^\[FAIL\] CT_CPU_FINISHES',r'^\[FAIL\] CT_')]:
        j=job(jid,top,MSRC+['rtl/dual_lane/merged/'+top+'.sv'],n,selection='i23',
              include_dirs=['vectors','sim_riscv/include'],tb_time_limit='20ms',config=dict(TOP=top,CHECKS=n),
              oracle_files=profile_files+['sw/riscv/contention_fw.S','sw/riscv/contention_fw.hex','sim_riscv/include/contention_fw.svh',
                                         'vectors/full_chain.svh','vectors/d2_k3_64.svh'],checks_basis=str(n)+' frozen merged phase/boundary/accounting checks')
        j.update(defines=['PQ_MAC_ON','CPU_TILE_MODULE=cpu_tile_noc'],sim_timeout=3600)
        jobs.append(j);i23.append(jid)
        m=dict(json.loads(json.dumps(j)),id=jid+'_control',mutant=kind,oracle=oracle,kill_scope=scope,dependencies=[jid],independent=False)
        jobs.append(m);i23.append(m['id'])
    i24=[]
    for jid,script,marker,timeout,extra in [
        ('i24_seed_controls','scripts/test_seed_campaign.py',r'^SEED_CAMPAIGN_TESTS: PASS checks=12$',120,{}),
        ('i24_seed_campaign','scripts/seed_shards.py',r'^SEED_CAMPAIGN: PASS seeds=1000 independent_processes=1000 checks_per_seed=2$',7200,{'output_argument':True})]:
        j=dict(id=jid,kind='python',script=script,sources=[],oracle_files=['scripts/seed_campaign.py',RV+'picorv32_adapter.sv',SR+'tb_random_latency.sv'],
               dependencies=[],independent=True,selection='i24',sim_timeout=timeout,positive_marker=marker,**extra)
        if jid=='i24_seed_campaign':j.update(dependencies=['i24_seed_controls'],independent=False)
        jobs.append(j);i24.append(jid)
    for top,n in [('tb_conformance',7),('tb_random_latency',2)]:
        j=job('i24_'+top,top,[RV+'picorv32_adapter.sv',SR+top+'.sv'],n,selection='i24',tb_time_limit='50ms',
              checks_basis='Original conformance seven unchanged acceptance conditions; random two aggregate acceptance conditions, counted seeds',
              config=dict(TOP=top,CHECKS=n))
        j['sim_timeout']=1800;jobs.append(j);i24.append(j['id'])
    for old in ['r1_mem_bram_dp','r1_tile_status','r1_gpio','i19_decoder','i19_ni','i19_parameters','i19_cpu_irq','i19_cpu_tile',
                'r2_tmem_app_bridge','r2_meas_window_reader','i16_bridge_decode_table','i16_memtest','i16_two_programs',
                'i16_two_tiles','i20_profile','i20_firmware','i21_merged_closure','i21_merged_error','i23_inflight','i23_contention','i10_d2']:
        j=dict(json.loads(json.dumps(next(j for j in jobs if j['id']==old))),id='i24_'+old,selection='i24',dependencies=[],independent=True)
        jobs.append(j);i24.append(j['id'])
    seed_job=next(j for j in jobs if j['id']=='i24_seed_campaign')
    jobs.remove(seed_job)
    shard_files=['scripts/seed_campaign.py','scripts/seed_shards.py','scripts/run_seed_shard.py',RV+'picorv32_adapter.sv',SR+'tb_random_latency.sv']
    jobs.append(dict(id='i24_seed_shard_controls',kind='python',script='scripts/test_seed_shards.py',sources=[],oracle_files=shard_files,
                     dependencies=[],independent=True,selection='i24',sim_timeout=120,positive_marker=r'^SEED_SHARD_CONTROLS: PASS checks=19$'))
    i24.append('i24_seed_shard_controls')
    shard_ids=[]
    for index in range(10):
        jid=f'i24_seed_shard_{index:02d}';shard_ids.append(jid);i24.append(jid)
        jobs.append(dict(id=jid,kind='python',script='scripts/run_seed_shard.py',sources=[],oracle_files=shard_files,
                         dependencies=['i24_seed_controls','i24_seed_shard_controls'],independent=False,selection='i24',sim_timeout=1200,
                         output_argument=True,seed_first=index*100,seed_count=100,
                         positive_marker=rf'^SEED_SHARD: PASS first={index*100} seeds=100 independent_processes=100 checks_per_seed=2$'))
    seed_job.update(dependencies=shard_ids,independent=False,oracle_files=shard_files,seed_count=1000)
    jobs.append(seed_job)
    i25=[]
    for jid,script,marker,oracle in [
        ('i25_release_controls','scripts/test_merged_release_final.py',r'^MERGED_RELEASE_TESTS: PASS checks=22$',['scripts/merged_release.py']),
        ('i25_latency_controls','scripts/test_matched_latency.py',r'^MATCHED_LATENCY_TESTS: PASS checks=14$',['scripts/matched_latency.py'])]:
        jobs.append(dict(id=jid,kind='python',script=script,sources=[],oracle_files=oracle,dependencies=[],independent=True,
                         selection='i25',sim_timeout=120,positive_marker=marker));i25.append(jid)
    jobs.append(dict(id='i25_board_profile',kind='python',script='scripts/check_merged_board_profile.py',sources=[],
                     oracle_files=['synth/merged/pq_merged_board_top.sv']+profile_files,dependencies=[],independent=True,selection='i25',sim_timeout=120,
                     positive_marker=r'^MERGED_BOARD_PROFILE: PASS conditions=5 negative_controls=5$'));i25.append('i25_board_profile')
    jobs.append(dict(id='i25_project_controls',kind='python',script='scripts/run_merged_project_controls.py',sources=[],
                     oracle_files=['scripts/final_project_update.tcl','scripts/check_merged_board_profile.py','scripts/check_closure_profile.py','scripts/test_merged_project_update.tcl','scripts/merged_project_update.tcl','scripts/merged_bitstream_sources.tcl',
                                   'scripts/seed_campaign.py']+MBOARD+['sw/riscv/demo_fw_v2.hex'],dependencies=[],independent=True,
                     selection='i25',sim_timeout=400,output_argument=True,positive_marker=r'^MERGED_PROJECT_CONTROLS: PASS files=71 idempotent=YES$'))
    i25.append('i25_project_controls')
    baseline='synth/research/pq_noc_subsystem_fixed_admission.sv'
    bench='rtl/dual_lane/merged/tb_matched_memory.sv'
    research_files=['sw/riscv/matched_memory_fw.S','sw/riscv/matched_memory_fw.hex','sim_riscv/include/matched_memory_fw.svh',
                    'sim_riscv/app_port_checker.sv','scripts/matched_latency.py','docs/decisions/MATCHED_COMBINED_EXPERIMENT_20261109.md']
    mixed=job('i25_mixed_operations','tb_mixed_conformance',['rtl/riscv/picorv32_adapter.sv','sim_riscv/tb_mixed_conformance.sv'],9,
              selection='i25',tb_time_limit='50ms',config=dict(TOP='tb_mixed_conformance',CHECKS=9),
              checks_basis='Original seven conformance conditions for 1000 transfers plus eight operation classes x125 and both halfword offsets')
    mixed['sim_timeout']=1800;jobs.append(mixed);i25.append(mixed['id'])
    for old,new in [('i21_merged_closure','i25_final_lifecycle'),('i21_merged_error','i25_final_error')]:
        j=dict(json.loads(json.dumps(next(j for j in jobs if j['id']==old))),id=new,selection='i25',dependencies=[],independent=True)
        jobs.append(j);i25.append(j['id'])
    sweep=job('i25_phase_sweep','tb_merged_phase_sweep',MSRC+['rtl/dual_lane/merged/tb_merged_phase_sweep.sv'],56,selection='i25',
              include_dirs=['vectors','sim_riscv/include'],tb_time_limit='40ms',
              config=dict(TOP='tb_merged_phase_sweep',CHECKS=56),oracle_files=profile_files+research_files+['vectors/full_chain.svh','vectors/d2_k3_64.svh'],
              checks_basis='56 frozen checks: seven active read/write phases times revoke/reset times four acceptance conditions')
    sweep.update(defines=['PQ_MAC_ON','CPU_TILE_MODULE=cpu_tile_noc'],sim_timeout=3600)
    jobs.append(sweep);i25.append(sweep['id'])
    control=dict(json.loads(json.dumps(sweep)),id='i25_phase_control',mutant='rvg_ignore_revoke',
                 oracle=r'^\[FAIL\] PH_REVOKE_BOUND_',kill_scope=r'^\[FAIL\] PH_REVOKE_(BOUND|OUTCOME)_',dependencies=['i25_phase_sweep'],independent=False)
    jobs.append(control);i25.append(control['id'])
    for mode in ('secure','fixed','secure_contended','fixed_contended'):
        src=[baseline if mode.startswith('fixed') and s=='rtl/dual_lane/pq_noc_subsystem_p7_i9.sv' else s for s in MSRC]
        j=job('i25_matched_'+mode,'tb_matched_memory',src+['sim_riscv/app_port_checker.sv',bench],8,selection='i25',
              include_dirs=['vectors','sim_riscv/include'],tb_time_limit='20ms',config=dict(TOP='tb_matched_memory',CHECKS=8),
              oracle_files=profile_files+research_files+['vectors/full_chain.svh','vectors/d2_k3_64.svh'],
              checks_basis='8 frozen matched workload checks: boot/admission/setup/completion/exact transfers/commits/all words/protocol and no fault')
        j.update(defines=['PQ_MAC_ON','CPU_TILE_MODULE=cpu_tile_noc']+(['MATCHED_CONTENTION'] if mode.endswith('contended') else [])+(['FIXED_ADMISSION'] if mode.startswith('fixed') else []),sim_timeout=3600,dependencies=['i25_latency_controls'],independent=False)
        jobs.append(j);i25.append(j['id'])
    jobs.append(dict(id='i25_matched_data',kind='python',script='scripts/collect_matched_latency.py',sources=[],
                     oracle_files=['scripts/matched_latency.py'],dependencies=['i25_matched_secure','i25_matched_fixed','i25_matched_secure_contended','i25_matched_fixed_contended','i25_phase_sweep'],independent=False,
                     selection='i25',sim_timeout=120,output_argument=True,
                     positive_marker=r'^MATCHED_COMPARISON: PASS modes=4 transactions_per_mode=64$'));i25.append('i25_matched_data')
    for mode in ('secure','fixed'):
        j=dict(json.loads(json.dumps(next(j for j in jobs if j['id']=='i17_merged_board'))),id='i25_board_'+mode,selection='i25')
        j['sources']=[baseline if mode=='fixed' and s=='rtl/dual_lane/pq_noc_subsystem_p7_i9.sv' else s for s in MBOARD]
        j['oracle_files']+=profile_files+['scripts/merged_release.py','scripts/merged_project_update.tcl',
                           'scripts/merged_bitstream_flow.tcl','scripts/merged_bitstream_sources.tcl']+research_files
        j.update(dependencies=['i25_matched_data','i25_release_controls','i25_phase_control','i25_board_profile','i25_mixed_operations','i25_project_controls','i25_final_lifecycle','i25_final_error'],independent=False,
                 scope='Matched combined '+mode+' board implementation; fixed admission is a research ablation only')
        jobs.append(j);i25.append(j['id'])
    jobs.append(dict(id='i25_gate_negative',kind='python',script='scripts/run_merged_gate_controls.py',sources=[],
                     oracle_files=['scripts/test_merged_board_gate.tcl','scripts/merged_board_gate.tcl','scripts/seed_campaign.py'],
                     dependencies=['i25_board_secure'],independent=False,selection='i25',sim_timeout=1800,output_argument=True,
                     positive_marker=r'^MERGED_GATE_CONTROLS: PASS cases=6$'));i25.append('i25_gate_negative')
    i26=[]
    for old,new in [('i25_project_controls','i26_project_replay'),('i25_final_lifecycle','i26_lifecycle_replay'),('i25_board_secure','i26_board_replay')]:
        j=dict(json.loads(json.dumps(next(j for j in jobs if j['id']==old))),id=new,selection='i26',dependencies=[],independent=True)
        if new=='i26_board_replay':j.update(dependencies=['i26_project_replay','i26_lifecycle_replay'],independent=False)
        jobs.append(j);i26.append(j['id'])
    # Rev-10 phase 0: explicit fresh re-adjudication; historical jobs stay unchanged.
    r10p0=[]
    remap={old:'r10p0_'+old for old in ['i21_merged_closure','i23_inflight','i23_inflight_control','i23_contention','i23_contention_control']}
    for old,new in remap.items():
        j=json.loads(json.dumps(next(j for j in jobs if j['id']==old)))
        j.update(id=new,selection='r10p0')
        j['dependencies']=[remap.get(d,d) for d in j.get('dependencies',[])]
        jobs.append(j);r10p0.append(new)
    r10cov=[]
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
    # Historical job definitions are pinned; new board-source generation must not rewrite them.
    legacy=json.loads((ROOT/'scripts/dual_lane_pre_i27r2.json').read_text())
    jobs=legacy['jobs']
    i27=legacy['increments']['I-27']
    import register_i27r2
    i27r2=register_i27r2.append_jobs(jobs)
    return dict(schema=2,active_increment='I-27-R2',jobs=jobs,increments={'I-1':i1,'I-2':i2,'I-3':i3,'I-4':i4,'B-1':b1,'B-2':b2,'B-3':b3,'F234-REV6':f234,'B-4':b4,'I-5':i5,'S3':s3,'I-6':i6,'I-7':i7,'I-8':i8,'S4':s4,'I-9':i9,'I-10':i10,'I-11':i11,'I-12':i12,'I-13':i13,'I-14':i14,'I-15':i15,'I-16':i16,'I-17':i17,'I-18':i18,'I-19':i19,'I-20':i20,'I-21':i21,'I-22':i22,'I-23':i23,'I-24':i24,'I-25':i25,'I-26':i26,'R10-P0':r10p0,'R10-COV':r10cov,'I-27':i27,'I-27-R2':i27r2},stages=[dict(id=i,dependencies=d,jobs=j) for i,d,j in stages])

def main():
    generate_credit_window(ROOT)
    registry=build_registry()
    jobs=registry['jobs']
    atomic(ROOT/'scripts/dual_lane_jobs.json',registry)
    baseline=json.loads((ROOT/'automation/dual_lane_payload/baseline_before.json').read_text())
    payload=ROOT/'automation/dual_lane_payload'; rows=[]
    changed=[p for d in ['scripts','docs/decisions','vectors','rtl/dual_lane'] for p in (ROOT/d).rglob('*') if p.is_file() and '__pycache__' not in str(p) and p.suffix!='.pyc' and baseline['files'].get(p.relative_to(ROOT).as_posix())!=sha(p)]
    # Save unfinished benches too; packaging does not qualify them as executed.
    changed+=[ROOT/T/f for f in ['tb_stg_8_golden.sv','tb_pq_full_chain.sv','tb_noc_perf.sv','tb_noc_l2_auth.sv']]
    changed+=[ROOT/'docs/DUAL_LANE_CHECKPOINT_2026-10-08.md']
    changed+=[ROOT/T/'ni_tb.sv']
    changed+=[ROOT/'docs'/f for f in ['BASELINE_CURRENT.md','STATUS.md','STAGE_MAP.md','DECISION_REGISTER.md','I1_DELIVERY_2026-10-08.md','HANDOFF_2026-09-26.md','PQ_ATTEST_AI_HANDOFF_2026-10-01.md']]
    changed+=[p for p in (ROOT/'docs/verification').rglob('*') if p.is_file()]
    changed+=[p for p in (ROOT/'sim/dual_lane/n6_credit_window').rglob('*') if p.is_file()]
    for p in sorted(set(changed)):
        rel=p.relative_to(ROOT).as_posix(); dest=payload/'files'/rel; dest.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(p,dest)
        rows.append(dict(path=rel,payload='files/'+rel,before=baseline['files'].get(rel),after=sha(p)))
    atomic(payload/'update_manifest.json',dict(schema=1,intake_head=baseline['head'],files=rows))
    print('Prepared',len(jobs),'jobs and',len(rows),'guarded updates')

if __name__=='__main__': main()
