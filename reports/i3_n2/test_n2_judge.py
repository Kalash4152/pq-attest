"""N2 (I-3 / NOC-2) unit tests: run WITHOUT applying the patches to the repository.

The two patches in this folder are applied to a temporary copy of scripts/ (git apply), and the
patched registry builder and judge are imported from that copy. Synthetic logs are built from the
frozen registry specs; nothing here runs a simulator or proves RTL behaviour.

    python reports/i3_n2/test_n2_judge.py
"""
import copy,importlib,importlib.util,json,shutil,subprocess,sys,tempfile,unittest
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
TMP=Path(tempfile.mkdtemp(prefix='n2_judge_'))
shutil.copytree(ROOT/'scripts',TMP/'scripts',ignore=shutil.ignore_patterns('__pycache__'))
(TMP/'docs/decisions').mkdir(parents=True)
shutil.copyfile(ROOT/'docs/decisions/dual_lane_config.json',TMP/'docs/decisions/dual_lane_config.json')
for patch in ['prepare_dual_lane.i3_n2.patch','dual_lane_verify.i3_n2.patch']:
    subprocess.run(['git','apply',str(HERE/patch)],cwd=TMP,check=True)
sys.path.insert(0,str(TMP/'scripts'))
verify=importlib.import_module('dual_lane_verify')
prep=importlib.import_module('prepare_dual_lane')
assert Path(verify.__file__).resolve().is_relative_to(TMP) and Path(prep.__file__).resolve().is_relative_to(TMP)
sys.path.insert(0,str(ROOT/'scripts'))
spec_report=importlib.util.spec_from_file_location('perf_report',ROOT/'scripts/perf_report.py')
perf_report=importlib.util.module_from_spec(spec_report); spec_report.loader.exec_module(perf_report)
REG=prep.build_registry(check_files=False)
JOBS={j['id']:j for j in REG['jobs']}
PROC={s:dict(exitCode=0,timedOut=False) for s in ['compile','elaborate','simulate']}
FIELDS=['offered','queued','cap_drops','accepted','injected','delivered','responses','mem_accepted','missing','unsent',
        'duplicate','mismatched','unknown','credits_returned','idle_after_drain','drain_cycles','verdict']

def point_line(case,pattern,period,mac,values,tags=None):
    t=dict(prep.PERF_TAGS,**(tags or {}))
    v=dict(dict(drain_cycles=17,unsent=0),**values)
    return (f'POINT case={case} pattern={pattern} period={period} mac={mac} '+' '.join(f'{k}={v[k]}' for k in FIELDS)+
            f" transport={t['transport']} w={t['w']} wde={t['wde']} seed={t['seed']} n_out={t['n_out']} tool={t['tool']}")

def synth(job,result=None,errors=None,extra=(),traces=False,drop_point=None):
    """A log consistent with the job's frozen spec (the 'expected' run)."""
    cfg='CONFIG: '+' '.join(f'{k}={v}' for k,v in job['config'].items())
    lines=[cfg]
    pa=job['point_accounting']
    for i,p in enumerate(pa['points']):
        if i==drop_point: continue
        vals=dict(p['exact']); vals.setdefault('accepted',100); vals.setdefault('injected',vals['accepted']); vals.setdefault('delivered',vals['accepted'])
        vals.setdefault('responses',vals['accepted']-2); vals.setdefault('mem_accepted',vals['accepted']); vals.setdefault('unsent',p.get('min',{}).get('unsent',0)+5)
        vals.setdefault('drain_cycles',17)
        lines.append(point_line(p['case'],p['pattern'],p['period'],pa['mac'],vals))
        if traces:
            for q in range(vals['delivered']):
                s=q%6
                lines.append(f"TRACE pattern={p['pattern']} period={p['period']} mac={pa['mac']} kind=2 source={s} seq={q//6} dst={(s+1)%6} gen={q} accept={q+3} inj={q+5} del={q+40} ok=1")
    for pat,count in job.get('required_lines',[]):
        sample=pat.strip('^$').replace(r'\d+','7').replace('[1-9]\\d*','12').replace(r'\d','0')
        lines.append(sample)
    lines+=list(extra)
    c=job.get('tb_control')
    lines+=[f"CHECKS : {job['checks']}",f"ERRORS : {errors if errors is not None else (c['errors'] if c else 0)}",
            f"RESULT : {result or ('FAIL' if c else 'PASS')}"]
    return '\n'.join(lines)+'\n'

def control_lines(job):
    """Instantiate each oracle regex as a concrete line."""
    out=[]
    for pat in job['tb_control']['oracle']:
        out.append(pat.strip('^$').replace(r'\[','[').replace(r'\]',']').replace(r'\d+','1234'))
    return out

def judge(text,job): return verify.judge(text,job,PROC,{},{})

class RegistryTests(unittest.TestCase):
    def test_i3_list_and_stage(self):
        self.assertEqual(REG['increments']['I-3'],prep.N2_I3)
        self.assertEqual(len(REG['increments']['I-3']),13)
        self.assertEqual(REG['active_increment'],'I-2')
        st={s['id']:s for s in REG['stages']}['NOC-2']
        self.assertEqual(st['jobs'],prep.N2_I3)
    def test_frozen_counts(self):
        want=dict(perf_m0=393,perf_m1=393,perf_ctrl_corrupt=15,perf_ctrl_drop=15,perf_ctrl_stall=15,
                  n75_sat_vc2_m0=18,n75_sat_vc2_m1=18,n75_reset_m0=19,n75_reset_m1=19,n75_second_challenge_m0=20,n75_second_challenge_m1=20)
        self.assertEqual({k:JOBS[k]['checks'] for k in want},want)
        self.assertEqual({k:JOBS[k]['selection'] for k in want},{k:'I-3' for k in want})
    def test_defines(self):
        self.assertEqual(JOBS['perf_m0']['defines'],[]); self.assertEqual(JOBS['perf_m1']['defines'],['PQ_MAC_ON'])
        self.assertEqual(JOBS['n75_reset_m1']['defines'],['PQ_MAC_ON','N75_RESET'])
        self.assertEqual(JOBS['perf_ctrl_stall']['defines'],['PERF_CTRL_STALL'])
    def test_matrix_expectations(self):
        pts={(p['pattern'],p['period']):p['exact'] for p in JOBS['perf_m0']['point_accounting']['points']}
        self.assertEqual(len(pts),28)
        self.assertEqual((pts[(0,64)]['offered'],pts[(0,64)]['queued'],pts[(0,64)]['cap_drops']),(204,204,0))
        self.assertEqual((pts[(2,8)]['offered'],pts[(2,8)]['queued'],pts[(2,8)]['cap_drops']),(1632,1536,96))
        self.assertEqual((pts[(3,1)]['offered'],pts[(3,1)]['queued'],pts[(3,1)]['cap_drops']),(13056,1536,11520))
    def test_no_pfc_variants_for_controls_and_gate(self):
        ids=set(JOBS)
        for j in prep.N2_CONTROLS+prep.N2_N75+['perf_matrix']: self.assertNotIn('pfc_'+j,ids)
        self.assertIn('pfc_perf_m0',ids); self.assertEqual(JOBS['pfc_perf_m0']['checks'],393)
    def test_gate_job(self):
        g=JOBS['perf_matrix']
        self.assertEqual(g['kind'],'python'); self.assertFalse(g['independent'])
        self.assertEqual(set(g['dependencies']),{'perf_m0','perf_m1',*prep.N2_CONTROLS,*prep.N2_N75})
        self.assertNotIn('unimplemented',g); self.assertNotIn('perf_hop_probes',JOBS); self.assertTrue(all(JOBS[h]['checks']==557 for h in ('hop_probes_m0','hop_probes_m1')))  # HP subgate implemented (I-3, Kalash 2026-10-20)
    def test_registry_serialisable(self): json.dumps(REG)

class PointJudgeTests(unittest.TestCase):
    def test_clean_matrix_passes(self):
        r=judge(synth(JOBS['perf_m0']),JOBS['perf_m0'])
        self.assertEqual(r['result'],'PASS'); self.assertEqual(r['point_accounting']['points'],28)
    def test_missing_point(self):
        with self.assertRaisesRegex(verify.InvalidEvidence,'POINT set mismatch'): judge(synth(JOBS['perf_m0'],drop_point=5),JOBS['perf_m0'])
    def test_extra_point(self):
        t=synth(JOBS['perf_m0']).replace('CHECKS',point_line('perf',0,3,0,dict(JOBS['perf_m0']['point_accounting']['points'][0]['exact']))+'\nCHECKS')
        with self.assertRaisesRegex(verify.InvalidEvidence,'unexpected'): judge(t,JOBS['perf_m0'])
    def test_duplicate_point(self):
        t=synth(JOBS['perf_m0']); first=[l for l in t.splitlines() if l.startswith('POINT')][0]
        with self.assertRaisesRegex(verify.InvalidEvidence,'duplicate POINT'): judge(t.replace(first,first+'\n'+first),JOBS['perf_m0'])
    def test_off_by_one_delivered(self):
        t=synth(JOBS['perf_m0']).replace('delivered=204 ','delivered=203 ',1)
        with self.assertRaisesRegex(verify.InvalidEvidence,'delivered=203'): judge(t,JOBS['perf_m0'])
    def test_credits_not_returned(self):
        t=synth(JOBS['perf_m0']).replace('credits_returned=1','credits_returned=0',1)
        with self.assertRaises(verify.InvalidEvidence): judge(t,JOBS['perf_m0'])
    def test_wrong_tag(self):
        t=synth(JOBS['perf_m0']).replace('n_out=2','n_out=4',1)
        with self.assertRaisesRegex(verify.InvalidEvidence,'n_out'): judge(t,JOBS['perf_m0'])
    def test_wrong_mac(self):
        with self.assertRaisesRegex(verify.InvalidEvidence,'mac'): judge(synth(JOBS['perf_m0']),dict(JOBS['perf_m0'],point_accounting=dict(JOBS['perf_m0']['point_accounting'],mac=1)))
    def test_drain_over_bound(self):
        t=synth(JOBS['perf_m0']).replace('drain_cycles=17','drain_cycles=50001',1)
        with self.assertRaisesRegex(verify.InvalidEvidence,'exceeds'): judge(t,JOBS['perf_m0'])
    def test_malformed_point(self):
        t=synth(JOBS['perf_m0']).replace(' tool=xsim-2024.1','',1)
        with self.assertRaisesRegex(verify.InvalidEvidence,'malformed POINT'): judge(t,JOBS['perf_m0'])
    def test_liveness_in_positive_job(self):
        t=synth(JOBS['perf_m0'],extra=['LIVENESS_FIRED case=perf pattern=0 period=1 mac=0 cycle=9 reason=no_progress'])
        with self.assertRaisesRegex(verify.InvalidEvidence,'liveness'): judge(t,JOBS['perf_m0'])
    def test_config_case_checked(self):
        t=synth(JOBS['perf_m0']).replace('CASE=perf','CASE=ctrl_drop')
        with self.assertRaisesRegex(verify.InvalidEvidence,'CASE'): judge(t,JOBS['perf_m0'])

class N75Tests(unittest.TestCase):
    def test_all_n75_pass(self):
        for jid in prep.N2_N75: self.assertEqual(judge(synth(JOBS[jid]),JOBS[jid])['result'],'PASS',jid)
    def test_summary_line_required(self):
        j=JOBS['n75_second_challenge_m0']; t=synth(j).replace('ep_drained=1','ep_drained=2')
        with self.assertRaisesRegex(verify.InvalidEvidence,'required line'): judge(t,j)
    def test_sat_requires_saturation(self):
        j=JOBS['n75_sat_vc2_m1']; t=synth(j).replace('vc2_credit_zero_port_cycles=12','vc2_credit_zero_port_cycles=0')
        with self.assertRaisesRegex(verify.InvalidEvidence,'required line'): judge(t,j)
    def test_reset_phase_line(self):
        j=JOBS['n75_reset_m0']; t=synth(j).replace('ni_idle=1','ni_idle=0')
        with self.assertRaises(verify.InvalidEvidence): judge(t,j)

class ControlTests(unittest.TestCase):
    def ok(self,jid): return synth(JOBS[jid],extra=control_lines(JOBS[jid]))
    def test_effective_controls(self):
        for jid in prep.N2_CONTROLS:
            self.assertEqual(judge(self.ok(jid),JOBS[jid])['result'],'CONTROL_EFFECTIVE',jid)
    def test_control_that_passes_is_rejected(self):
        j=JOBS['perf_ctrl_corrupt']
        with self.assertRaisesRegex(verify.InvalidEvidence,'ineffective'): judge(synth(j,result='PASS',errors=0),j)
    def test_missing_targeted_line(self):
        j=JOBS['perf_ctrl_corrupt']; t='\n'.join(l for l in self.ok('perf_ctrl_corrupt').splitlines() if 'SCOREBOARD_PAYLOAD' not in l)
        with self.assertRaisesRegex(verify.InvalidEvidence,'untargeted'): judge(t,j)
    def test_wrong_target_seq(self):
        j=JOBS['perf_ctrl_drop']; t=self.ok('perf_ctrl_drop').replace('SCOREBOARD_MISSING source=3 seq=9','SCOREBOARD_MISSING source=3 seq=10')
        with self.assertRaises(verify.InvalidEvidence): judge(t,j)
    def test_unlisted_fail_line(self):
        j=JOBS['perf_ctrl_corrupt']; t=self.ok('perf_ctrl_corrupt').replace('CHECKS','[FAIL] PERF_DELIVERED case=ctrl_corrupt pattern=0 period=16 mac=0\nCHECKS')
        with self.assertRaisesRegex(verify.InvalidEvidence,'unexpected control failure'): judge(t,j)
    def test_secondary_symptom_forbidden(self):
        j=JOBS['perf_ctrl_drop']; t=self.ok('perf_ctrl_drop').replace('CHECKS','LIVENESS_FIRED case=ctrl_drop reason=no_progress\nCHECKS')
        with self.assertRaisesRegex(verify.InvalidEvidence,'forbidden'): judge(t,j)
    def test_timeout_is_not_a_control(self):
        j=JOBS['perf_ctrl_stall']; t=self.ok('perf_ctrl_stall').replace('CHECKS','TB_TIMEOUT perf bench\nCHECKS')
        with self.assertRaises(verify.InvalidEvidence): judge(t,j)
    def test_drain_bound_is_not_the_stall_observation(self):
        j=JOBS['perf_ctrl_stall']; t=self.ok('perf_ctrl_stall').replace('reason=no_progress','reason=drain_bound')
        with self.assertRaises(verify.InvalidEvidence): judge(t,j)
    def test_incomplete_checks(self):
        j=JOBS['perf_ctrl_drop']; t=self.ok('perf_ctrl_drop').replace('CHECKS : 15','CHECKS : 14')
        with self.assertRaisesRegex(verify.InvalidEvidence,'incomplete'): judge(t,j)
    def test_wrong_error_count(self):
        j=JOBS['perf_ctrl_drop']; t=self.ok('perf_ctrl_drop').replace('ERRORS : 3','ERRORS : 4')
        with self.assertRaisesRegex(verify.InvalidEvidence,'ERRORS'): judge(t,j)
    def test_duplicate_oracle(self):
        j=JOBS['perf_ctrl_corrupt']; extra=control_lines(j); t=synth(j,extra=extra+[extra[1]],errors=2)
        with self.assertRaises(verify.InvalidEvidence): judge(t,j)
    def test_control_point_accounting(self):
        j=JOBS['perf_ctrl_corrupt']; t=self.ok('perf_ctrl_corrupt').replace('mismatched=1','mismatched=2')
        with self.assertRaisesRegex(verify.InvalidEvidence,'mismatched'): judge(t,j)
    def test_mutant_path_unchanged(self):
        job=dict(checks=1,mutant='lost_tag',oracle=r'^\[FAIL\] TARGET')
        raw='CHECKS : 1\nERRORS : 1\nRESULT : FAIL\n[FAIL] TARGET\n'
        self.assertEqual(verify.judge(raw,job,PROC,{},{})['result'],'KILLED')

class PerfReportTests(unittest.TestCase):
    def logs(self):
        return [(f'm{m}',synth(dict(JOBS[f'perf_m{m}']),traces=True)) for m in (0,1)]
    def test_complete_matrix(self):
        rows=perf_report.rows_from(self.logs()); self.assertEqual(len(rows),56)
        with tempfile.TemporaryDirectory() as d:
            perf_report.write_outputs(rows,Path(d),{})
            scope=json.loads((Path(d)/'scope.json').read_text())
            self.assertFalse(scope['cross_simulator_passed']); self.assertIn('BLOCKED',scope['verilator_cross_check'])
            self.assertTrue((Path(d)/'performance.csv').is_file() and (Path(d)/'throughput.svg').is_file() and (Path(d)/'latency.svg').is_file())
    def test_single_mac_refused(self):
        with self.assertRaisesRegex(perf_report.Refused,'MAC modes'): perf_report.rows_from(self.logs()[:1])
    def test_missing_point_refused(self):
        logs=self.logs(); logs[0]=(logs[0][0],synth(JOBS['perf_m0'],traces=True,drop_point=3))
        with self.assertRaises(perf_report.Refused): perf_report.rows_from(logs)
    def test_trace_count_mismatch_refused(self):
        logs=self.logs(); text=logs[1][1]; first=[l for l in text.splitlines() if l.startswith('TRACE')][0]
        logs[1]=(logs[1][0],text.replace(first+'\n','',1))
        with self.assertRaisesRegex(perf_report.Refused,'TRACE set'): perf_report.rows_from(logs)
    def test_failed_run_refused(self):
        logs=self.logs(); logs[0]=(logs[0][0],logs[0][1].replace('RESULT : PASS','RESULT : FAIL'))
        with self.assertRaises(perf_report.Refused): perf_report.rows_from(logs)
    def test_gate_mode(self):
        with tempfile.TemporaryDirectory() as d:
            run=Path(d); registry=dict(jobs=[JOBS['perf_matrix']]); (run/'registry.json').write_text(json.dumps(registry))
            spec=JOBS['perf_matrix']['perf_inputs']
            for jid in spec['points']+spec['controls']+spec['n75']:
                (run/jid/'w').mkdir(parents=True); log=run/jid/'w'/'simulate.log'
                log.write_text(synth(JOBS[jid],traces=jid in spec['points']) if jid in spec['points'] else 'x\n')
                res='CONTROL_EFFECTIVE' if jid in spec['controls'] else 'PASS'
                (run/jid/'result.json').write_text(json.dumps(dict(state='PASS_FRESH',observed=dict(result=res),artifacts={str(log):perf_report.sha(log)})))
            out=run/'perf_matrix'; out.mkdir()
            self.assertEqual(perf_report.main(['--out',str(out)]),0)
            self.assertTrue((out/'performance.csv').is_file())
            # tampered log -> refused
            log=run/'perf_m1'/'w'/'simulate.log'; log.write_text(log.read_text()+'\n')
            self.assertEqual(perf_report.main(['--out',str(out)]),2)
            log.write_text(log.read_text()[:-1])
            # a control not effective -> refused
            r=json.loads((run/'perf_ctrl_stall'/'result.json').read_text()); r['observed']['result']='PASS'
            (run/'perf_ctrl_stall'/'result.json').write_text(json.dumps(r))
            self.assertEqual(perf_report.main(['--out',str(out)]),2)

class BenchSourceTests(unittest.TestCase):
    def test_generated_bench_up_to_date_and_static(self):
        p=subprocess.run([sys.executable,str(HERE/'check_perf_bench_static.py')],capture_output=True,text=True)
        self.assertEqual(p.returncode,0,p.stdout+p.stderr)
    def test_per_instance_binding_kept(self):
        tb=(ROOT/'NOC_PQATTEST.srcs/sim_1/new/tb_noc_perf.sv').read_text()
        self.assertIn('XSim workaround (2026-10-01)',tb); self.assertEqual(tb.count('noc_network_interface #('),1)
        self.assertIn('assign l_tx_valid = tx_valid[g];',tb)
    def test_control_targets_match_registry(self):
        body=(ROOT/'scripts/perf_bench_body.sv.inc').read_text()
        for frag in ['CORRUPT_SRC=1, CORRUPT_SEQ=5, CORRUPT_WORD=1, CORRUPT_BIT=3','DROP_SRC=3, DROP_SEQ=9','STALL_TILE=2, STALL_AT=512',
                     'LIVE_WINDOW=1024','RESET_AT=1000, RESET_LEN=5','CH1_AT=300, CRYPTO_LAT=512']:
            self.assertIn(frag,body)
    def test_lcg_targets(self):
        # dst of records (1,5) and (3,9) and the corrupted word, recomputed from the TB's LCG and data_of().
        def dest(t,q):
            r=(0x12345678+t)&0xffffffff
            for _ in range(q+1): r=(r*1664525+1013904223)&0xffffffff
            d=r%5; return d+1 if d>=t else d
        data=lambda s,q:(s<<28)|(((q*193+71)&0xfff)<<16)|q
        self.assertEqual((dest(1,5),dest(3,9)),(4,0))
        self.assertEqual((f'{data(1,5):08x}',f'{data(1,5)^8:08x}'),('140c0005','140c000d'))

if __name__=='__main__':
    try: unittest.main(verbosity=2)
    finally: shutil.rmtree(TMP,ignore_errors=True)
