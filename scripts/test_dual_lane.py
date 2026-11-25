"""Automation fault injection only; none of these tests proves RTL correctness."""
import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from dual_lane import install,atomic,report
from dual_lane_verify import *
from dual_lane_preflight import source_names, PreflightFailure
from python_reference_audit import judge_suite
from test_controlled_diagnostics import ControlledDiagnosticTests

class SelectionDependencyTests(unittest.TestCase):
    def test_dependencies_run_in_the_same_selection(self):
        # a dependent job is BLOCKED unless its dependencies are in the same --select run
        import json
        jobs = {j['id']: j for j in json.loads((Path(__file__).resolve().parent / 'dual_lane_jobs.json').read_text())['jobs']}
        bad = [(j['id'], d) for j in jobs.values() if not j.get('independent', True) and j.get('selection')
               for d in j.get('dependencies', []) if d in jobs and jobs[d].get('selection') not in (j['selection'], None)
               and jobs[d]['kind'] != 'reuse']
        self.assertEqual(bad, [])

class SecureBoundaryOocTests(unittest.TestCase):
    def test_l2_auth_ooc_builds_the_mac_on_profile(self):
        # noc_l2_auth.sv:258 $fatal()s without MAC_ENABLE; the B-1 OOC must synthesize the P6-S profile (PQ_MAC_ON)
        import json
        jobs = {j['id']: j for j in json.loads((Path(__file__).resolve().parent / 'dual_lane_jobs.json').read_text())['jobs']}
        for j in jobs.values():
            if j['kind'] == 'ooc' and 'rtl/dual_lane/noc_l2_auth.sv' in j.get('sources', []):
                self.assertIn('PQ_MAC_ON', j.get('defines', []), j['id'])

class MeshSplitFieldTests(unittest.TestCase):
    """S4-F3 job field synth_mesh_split (docs/decisions/S4_AREA_CONTRACT.md sec. 6): refused unless well-formed."""
    OK=dict(kind='ooc',synth_mesh_split=True,sources=['rtl/a.sv','NOC_PQATTEST.srcs/sources_1/new/noc_mesh_3x2.sv'],
            oracle_files=['scripts/s4_mesh_split.tcl','synth/s4/noc_mesh_3x2_bb.sv'])
    def chk(self,**kw):
        from dual_lane import check_mesh_split
        j=copy.deepcopy(self.OK); j.update(kw); check_mesh_split(j)
    def test_well_formed_passes(self):
        self.chk(); self.chk(kind='implementation')
        from dual_lane import check_mesh_split; check_mesh_split(dict(kind='simulation'))   # absent field: no-op
    def test_non_true_value_refused(self):
        for v in ('yes',1,False,'true'):
            with self.assertRaises(InvalidEvidence): self.chk(synth_mesh_split=v)
    def test_simulation_job_refused(self):
        with self.assertRaises(InvalidEvidence): self.chk(kind='simulation')
    def test_mesh_source_count_enforced(self):
        with self.assertRaises(InvalidEvidence): self.chk(sources=['rtl/a.sv'])
        with self.assertRaises(InvalidEvidence): self.chk(sources=['a/noc_mesh_3x2.sv','b/noc_mesh_3x2.sv'])
    def test_split_files_must_be_in_identity(self):
        with self.assertRaises(InvalidEvidence): self.chk(oracle_files=['scripts/s4_mesh_split.tcl'])
    def test_black_box_never_in_sources(self):
        with self.assertRaises(InvalidEvidence):
            self.chk(sources=['NOC_PQATTEST.srcs/sources_1/new/noc_mesh_3x2.sv','synth/s4/noc_mesh_3x2_bb.sv'])
    def test_registry_split_jobs_are_well_formed(self):
        from dual_lane import check_mesh_split
        jobs=json.loads((Path(__file__).resolve().parent/'dual_lane_jobs.json').read_text())['jobs']
        for j in jobs:
            if 'synth_mesh_split' in j: check_mesh_split(j)

class I9MutationTests(unittest.TestCase):
    """I-9 (M-F1 rev 8): every I-9 mutant anchor and every older control that the I-9 regression re-runs on a *_i9.sv file
    applies exactly once to the generated variant; a variant already mutated is refused."""
    ROOT=Path(__file__).resolve().parents[1]
    def text(self,name): return (self.ROOT/'rtl/dual_lane'/name).read_text(encoding='utf-8')
    def test_i9_kinds_apply_once(self):
        from dual_lane import mutation
        for kind,f in [('i9n_no_timeout','noc_network_interface_p7_i9.sv'),('i9n_stale_deliver','noc_network_interface_p7_i9.sv'),
                       ('i9s_rx_all','pq_noc_subsystem_p7_i9.sv'),('i9s_bram_lanes','pq_noc_subsystem_p7_i9.sv'),('i9s_window_1k','pq_noc_subsystem_p7_i9.sv')]:
            t=self.text(f); m=mutation(t,kind)
            self.assertNotEqual(t,m,kind); self.assertIn('MUT-I9',m,kind)
    def test_i9_already_mutated_refused(self):
        from dual_lane import mutation
        m=mutation(self.text('pq_noc_subsystem_p7_i9.sv'),'i9s_rx_all')
        with self.assertRaises(InvalidEvidence): mutation(m,'i9s_bram_lanes')
    def test_regression_controls_apply_to_variants(self):
        from dual_lane import mutation
        reg=json.loads((self.ROOT/'scripts/dual_lane_jobs.json').read_text())
        if 'I-9' not in reg.get('increments',{}): self.skipTest('I-9 not registered yet')
        by={j['id']:j for j in reg['jobs']}
        kinds=[by[i]['mutant'] for i in reg['increments']['I-9'] if by[i].get('mutant') and by[i].get('i9_of')]
        self.assertTrue(kinds)
        for k in kinds:
            name=('pq_noc_subsystem_p7_i9.sv' if k.startswith(('i6s_','i7s_','p7s_')) else 'noc_l2_p7_pair_i9.sv' if k.startswith('s2p_')
                  else 'noc_l2_auth_p7_i9.sv' if k.startswith(('s2w_','l2p7_','i7l_')) else None)
            if name: self.assertNotEqual(mutation(self.text(name),k),self.text(name),k)

class I10MutationTests(unittest.TestCase):
    """I-10 (I9-D2): each endpoint K-3 control applies exactly once; an already mutated endpoint is refused."""
    ROOT=Path(__file__).resolve().parents[1]
    def text(self): return (self.ROOT/'rtl/dual_lane/pq_attest_endpoint.sv').read_text(encoding='utf-8')
    def test_i10_kinds_apply_once(self):
        from dual_lane import mutation
        for kind in ('i10e_k3_imem_unchecked','i10e_window16'):
            t=self.text(); m=mutation(t,kind)
            self.assertNotEqual(t,m,kind); self.assertIn('MUT-I10',m,kind)
    def test_i10_already_mutated_refused(self):
        from dual_lane import mutation
        m=mutation(self.text(),'i10e_window16')
        with self.assertRaises(InvalidEvidence): mutation(m,'i10e_k3_imem_unchecked')

class E4VerificationJudgeTests(unittest.TestCase):
    """Vendored E4 suite judge (scripts/e4_verification.py): exact frozen counts, no failures / skips / count drift."""
    OKP='224 passed in 7.10s'; OKR='  REGRESSION RESULT: PASS (Passed: 15, Failed: 0, Skipped: 0)'
    def j(self,*a):
        from e4_verification import judge
        return judge(*a)[0]
    def test_pass(self): self.assertTrue(self.j(0,self.OKP,0,self.OKR))
    def test_fewer_tests(self): self.assertFalse(self.j(0,'223 passed in 7.1s',0,self.OKR))
    def test_failed_or_skipped(self):
        self.assertFalse(self.j(1,'3 failed, 221 passed in 7.8s',0,self.OKR))
        self.assertFalse(self.j(0,'194 passed, 30 skipped in 6.5s',0,self.OKR))
    def test_regression_stage_failed(self):
        self.assertFalse(self.j(0,self.OKP,1,'  REGRESSION RESULT: FAIL (Passed: 14, Failed: 1, Skipped: 0)'))
        self.assertFalse(self.j(0,self.OKP,0,'  REGRESSION RESULT: PASS (Passed: 13, Failed: 0, Skipped: 2)'))
    def test_regression_missing(self): self.assertFalse(self.j(0,self.OKP,0,''))

class E4VerificationV2JudgeTests(unittest.TestCase):
    """E4 final suite judge (scripts/e4_verification_v2.py): frozen 387 / 15; the v1 count (224) is no longer a PASS."""
    OKR='  REGRESSION RESULT: PASS (Passed: 15, Failed: 0, Skipped: 0)'
    def j(self,*a):
        from e4_verification_v2 import judge
        return judge(*a)[0]
    def test_pass(self): self.assertTrue(self.j(0,'387 passed in 8.7s',0,self.OKR))
    def test_old_count_rejected(self): self.assertFalse(self.j(0,'224 passed in 7.1s',0,self.OKR))
    def test_failed_or_skipped(self):
        self.assertFalse(self.j(1,'5 failed, 382 passed in 6.0s',0,self.OKR))
        self.assertFalse(self.j(0,'378 passed, 9 skipped in 6.0s',0,self.OKR))
    def test_regression_stage_failed(self):
        self.assertFalse(self.j(0,'387 passed in 8.7s',1,'  REGRESSION RESULT: FAIL (Passed: 14, Failed: 1, Skipped: 0)'))
    def test_v1_judge_unaffected(self):
        import e4_verification_v2, e4_verification as v1
        e4_verification_v2.judge(0,'387 passed in 1s',0,self.OKR)
        self.assertTrue(v1.judge(0,'224 passed in 7.1s',0,self.OKR)[0])

class I11MutationTests(unittest.TestCase):
    """I-11 (E4 Step 18 triage): each kind applies exactly once to its real file; an already mutated source is refused."""
    ROOT=Path(__file__).resolve().parents[1]
    CASES=[('i11r_yfirst','NOC_PQATTEST.srcs/sources_1/new/NOC_XY_ROUTING.sv'),('i11p_attest_vc0','rtl/dual_lane/NOC_PKG.sv'),
           ('i11s_window_over','rtl/dual_lane/pq_noc_subsystem_p7_i9.sv')]
    def test_i11_kinds_apply_once(self):
        from dual_lane import mutation
        for kind,f in self.CASES:
            t=(self.ROOT/f).read_text(encoding='utf-8'); m=mutation(t,kind)
            self.assertEqual(m.count('MUT-I11'),1,kind)
    def test_i11_already_mutated_refused(self):
        from dual_lane import mutation
        for kind,f in self.CASES:
            m=mutation((self.ROOT/f).read_text(encoding='utf-8'),kind)
            with self.assertRaises(InvalidEvidence): mutation(m,kind)

class RVMutationTests(unittest.TestCase):
    """I-14 RISC-V mutant kinds (Lane 1 2026-11-07): each applies exactly once to its real rtl/riscv file, the prefix picks
    that file, an already mutated source is refused, a kind on the wrong file or an unknown kind is refused."""
    ROOT=Path(__file__).resolve().parents[1]
    CASES=[('rva_no_poison','picorv32_adapter.sv'),('rva_no_guard','picorv32_adapter.sv'),('rvc_sideband_zero','cpu_tile_noc.sv'),
           ('rvb_auth_removed','tmem_app_bridge.sv'),('rvm_word_order','meas_window_reader.sv')]
    def src(self,f): return (self.ROOT/'rtl/riscv'/f).read_text(encoding='utf-8')
    def test_rv_kinds_apply_once(self):
        from dual_lane import mutation
        for kind,f in self.CASES:
            m=mutation(self.src(f),kind)
            self.assertEqual(m.count('MUT-RV'),1,kind); self.assertNotEqual(m,self.src(f).replace(chr(13)+chr(10),chr(10)),kind)
    def test_rv_prefix_selects_file(self):
        from dual_lane import RV_MUTANT_FILES
        for kind,f in self.CASES: self.assertEqual(RV_MUTANT_FILES[kind[:4]],f,kind)
    def test_rv_already_mutated_refused(self):
        from dual_lane import mutation
        for kind,f in self.CASES:
            m=mutation(self.src(f),kind)
            with self.assertRaises(InvalidEvidence): mutation(m,kind)
    def test_rv_wrong_file_refused(self):
        from dual_lane import mutation
        with self.assertRaises(InvalidEvidence): mutation(self.src('tile_status.sv'),'rva_no_poison')
        with self.assertRaises(InvalidEvidence): mutation(self.src('picorv32_adapter.sv'),'rvb_auth_removed')
    def test_rv_unknown_kind_refused(self):
        from dual_lane import mutation
        with self.assertRaises(InvalidEvidence): mutation(self.src('picorv32_adapter.sv'),'rva_bogus')
    def test_rv_auth_removed_all_gates(self):
        from dual_lane import mutation
        m=mutation(self.src('tmem_app_bridge.sv'),'rvb_auth_removed')
        self.assertNotIn('(!authorized_i) begin',m); self.assertIn('if (app_valid_o && !authorized_i)',m)

class I17MergedBoardJobTests(unittest.TestCase):
    """I-17 merged board implementation job (Lane 1 2026-11-07): well-formed for the harness, and the guards refuse broken variants."""
    def job(self):
        r=json.loads((Path(__file__).resolve().parents[1]/'scripts/dual_lane_jobs.json').read_text())
        return copy.deepcopy(next(j for j in r['jobs'] if j['id']=='i17_merged_board'))
    def test_fields(self):
        from dual_lane import check_mesh_split
        j=self.job(); check_mesh_split(j)
        self.assertEqual(j['kind'],'implementation')
        for f in (j['gate_script'],j['child_script'],j['constraints'],'sw/riscv/demo_fw.hex'): self.assertIn(f,j['oracle_files'])
        self.assertEqual(sum(s.endswith('pq_merged_board_top.sv') for s in j['sources']),1)
        self.assertIn('CPU_TILE_MODULE=cpu_tile_noc',j['defines'])
        # the harness copies only the gate script into the snapshot: the gate must not source other scripts
        g=(Path(__file__).resolve().parents[1]/j['gate_script']).read_text()
        self.assertNotRegex(g,r'(?m)^\s*source\s')
    def test_mesh_split_guard(self):
        from dual_lane import check_mesh_split
        j=self.job(); j['oracle_files']=[f for f in j['oracle_files'] if f!='scripts/s4_mesh_split.tcl']
        with self.assertRaises(InvalidEvidence): check_mesh_split(j)
        j=self.job(); j['sources']=j['sources']+['NOC_PQATTEST.srcs/sources_1/new/noc_mesh_3x2.sv']
        with self.assertRaises(InvalidEvidence): check_mesh_split(j)

class E4VerificationV3JudgeTests(unittest.TestCase):
    """E4 corrected suite judge (scripts/e4_verification_v3.py): frozen 389 / 15; the v2 count (387) is no longer a PASS."""
    OKR='  REGRESSION RESULT: PASS (Passed: 15, Failed: 0, Skipped: 0)'
    def j(self,*a):
        from e4_verification_v3 import judge
        return judge(*a)[0]
    def test_pass(self): self.assertTrue(self.j(0,'389 passed in 9.4s',0,self.OKR))
    def test_old_counts_rejected(self):
        self.assertFalse(self.j(0,'387 passed in 8.7s',0,self.OKR))
        self.assertFalse(self.j(0,'224 passed in 7.1s',0,self.OKR))
    def test_failed_or_skipped(self):
        self.assertFalse(self.j(1,'2 failed, 387 passed in 9.0s',0,self.OKR))
        self.assertFalse(self.j(0,'380 passed, 9 skipped in 9.0s',0,self.OKR))
    def test_regression_stage_failed(self):
        self.assertFalse(self.j(0,'389 passed in 9.4s',1,'  REGRESSION RESULT: FAIL (Passed: 14, Failed: 1, Skipped: 0)'))
    def test_colour_codes_stripped(self):
        self.assertTrue(self.j(0,'389 passed in 9.4s',0,'  REGRESSION RESULT: '+chr(27)+'[92mPASS'+chr(27)+'[0m (Passed: 15, Failed: 0, Skipped: 0)'))

class ExpectedDiagTests(unittest.TestCase):
    """Proposal A (docs/proposals/expected_diag.md, approved 2026-10-21)."""
    PAT=[r'^Error: pq_kmac_share: start while the shared kmac128 is busy$']
    def mk(self,*lines): return chr(10).join(lines)+chr(10)
    def test_only_expected_lines_pass_the_scan(self):
        from dual_lane_verify import strip_expected_diag, diagnostic_scan
        txt=self.mk('[FAIL] KSHARE_EXCLUSIVE violations=4','Error: pq_kmac_share: start while the shared kmac128 is busy','RESULT : FAIL')
        diagnostic_scan(strip_expected_diag(txt,self.PAT),dict(mutant='x'))
    def test_extra_unknown_error_is_invalid(self):
        from dual_lane_verify import strip_expected_diag, diagnostic_scan, InvalidEvidence
        txt=self.mk('Error: pq_kmac_share: start while the shared kmac128 is busy','Error: something else','RESULT : FAIL')
        with self.assertRaises(InvalidEvidence): diagnostic_scan(strip_expected_diag(txt,self.PAT),dict(mutant='x'))
    def test_missing_expected_line_is_invalid(self):
        from dual_lane_verify import strip_expected_diag, InvalidEvidence
        with self.assertRaises(InvalidEvidence): strip_expected_diag(self.mk('RESULT : FAIL'),self.PAT)
    def test_unanchored_regex_is_refused(self):
        from dual_lane_verify import strip_expected_diag, InvalidEvidence
        with self.assertRaises(InvalidEvidence): strip_expected_diag(self.mk('Error: x'),[r'Error: x'])
    def test_substring_line_is_not_stripped(self):
        from dual_lane_verify import strip_expected_diag, diagnostic_scan, InvalidEvidence
        txt=self.mk('Error: pq_kmac_share: start while the shared kmac128 is busy','Error: pq_kmac_share: start while the shared kmac128 is busy EXTRA')
        with self.assertRaises(InvalidEvidence): diagnostic_scan(strip_expected_diag(txt,self.PAT),dict(mutant='x'))
    def test_registry_refuses_expected_diag_on_non_mutant(self):
        import json
        jobs=json.loads((Path(__file__).resolve().parent/'dual_lane_jobs.json').read_text())['jobs']
        bad=[j['id'] for j in jobs if j.get('expected_diag') and (not j.get('mutant') or any(not (x.startswith('^') and x.endswith('$')) for x in j['expected_diag']))]
        self.assertEqual(bad,[])

class RuntimeOffsetLintTests(unittest.TestCase):
    """D-SYN-2 preflight lint: runtime-offset part-select writes inside for-loops."""
    def lint(self, body):
        from dual_lane_preflight import lint_runtime_offset_writes
        with tempfile.TemporaryDirectory() as td:
            f=Path(td)/'x.sv'; f.write_text(body); return lint_runtime_offset_writes([f])
    def test_runtime_offset_write_is_flagged(self):
        src=["always_comb begin"," for (int i = 0; i < N; i++) begin","  if (i < len_q) blk[(BASE + int'(off_q) + i)*8 +: 8] = d[i*8 +: 8];"," end","end",""]
        self.assertTrue(self.lint(chr(10).join(src)))
    def test_constant_index_write_passes(self):
        src=["always_ff @(posedge clk) begin"," for (int b = 0; b < RATE; b++)","  if (idx_q == b) blk[b*8 +: 8] <= byte_d;","end",""]
        self.assertEqual(self.lint(chr(10).join(src)),[])
    def test_runtime_read_outside_write_passes(self):
        self.assertEqual(self.lint("always_comb for (int i = 0; i < 4; i++) tag[i*32 +: 32] = rb[rn-4+i];"+chr(10)),[])
    def test_protected_original_is_flagged_and_variants_pass(self):
        from dual_lane_preflight import lint_runtime_offset_writes, lint_with_waivers
        root=Path(__file__).resolve().parents[1]
        self.assertTrue(lint_runtime_offset_writes([root/'NOC_PQATTEST.srcs/sources_1/new/pq_measurement.sv']))
        self.assertEqual(lint_with_waivers(sorted((root/'rtl/dual_lane').glob('*.sv')),root/'scripts/rtl_lint_waivers.json'),[])
    # B-1 extension: any statement, not only for-loops
    def test_runtime_write_outside_loop_is_flagged(self):
        self.assertTrue(self.lint("always_ff @(posedge clk) if (v) buf_q[cnt_q*32 +: 32] <= d;"+chr(10)))
        self.assertTrue(self.lint("assign w[sel*8 +: 8] = b;"+chr(10)))
    def test_sized_literal_is_not_an_identifier(self):
        f=self.lint("always_comb t[{cnt_q, 5'd0} +: 32] = d;"+chr(10))
        self.assertTrue(f); self.assertNotIn("'d0'",f[0])
        self.assertEqual(self.lint("always_comb t[{2'd1, 5'd0} +: 32] = d;"+chr(10)),[])
    def test_multiline_lhs_is_flagged_at_its_first_line(self):
        src=["always_comb begin","  blk[(len_q +","       2)*8 +: 8] = DOM;","end",""]
        f=self.lint(chr(10).join(src)); self.assertTrue(f); self.assertIn(':2:',f[0])
    def test_protected_kmac_runtime_write_is_found(self):
        from dual_lane_preflight import lint_runtime_offset_writes
        root=Path(__file__).resolve().parents[1]
        self.assertTrue(any(':194:' in f for f in lint_runtime_offset_writes([root/'NOC_PQATTEST.srcs/sources_1/new/kmac_128.sv'])))
    def test_noc_l2_auth_has_no_runtime_part_select_write(self):
        from dual_lane_preflight import lint_runtime_offset_writes
        root=Path(__file__).resolve().parents[1]
        self.assertEqual(lint_runtime_offset_writes([root/'rtl/dual_lane/noc_l2_auth.sv']),[])
    def test_waiver_is_line_hash_pinned_and_stale_waiver_fails(self):
        import hashlib, json
        from dual_lane_preflight import lint_with_waivers
        with tempfile.TemporaryDirectory() as td:
            (Path(td)/'scripts').mkdir(); f=Path(td)/'x.sv'; line="always_ff @(posedge clk) buf_q[cnt_q*32 +: 32] <= d;"
            f.write_text(line+chr(10)); wf=Path(td)/'scripts'/'w.json'
            self.assertTrue(lint_with_waivers([f],wf))                        # no waiver -> flagged
            w=dict(path='x.sv',line=1,line_sha256=hashlib.sha256(line.encode()).hexdigest(),reason='t')
            wf.write_text(json.dumps(dict(waivers=[w]))); self.assertEqual(lint_with_waivers([f],wf),[])
            f.write_text(line.replace('cnt_q','idx_q')+chr(10))                 # line changed -> waiver stale
            out=lint_with_waivers([f],wf); self.assertTrue(any('stale' in o for o in out)); self.assertTrue(len(out)==2)

class LutramGateTests(unittest.TestCase):
    RPT = ('| Instance | Module | Total LUTs | Logic LUTs | LUTRAMs | SRLs | FFs |\n'
           '| top | top | 100 | 80 | 20 | 0 | 50 |\n'
           '|   (l2/W[0].l2) | noc_l2_auth_p7 | 40 | 30 | 10 | 0 | 20 |\n'
           '|   quarantine | noc_ingress_quarantine | 30 | 30 | 0 | 0 | 10 |\n')
    def test_inferred_passes(self):
        from dual_lane_verify import lutram_gate
        self.assertIsNone(lutram_gate(self.RPT, [r'W\[0\]\.l2\b']))
    def test_not_inferred_fails(self):
        from dual_lane_verify import lutram_gate, GateFailure
        with self.assertRaises(GateFailure): lutram_gate(self.RPT, [r'\bquarantine\b'])
    def test_missing_instance_invalid(self):
        from dual_lane_verify import lutram_gate, InvalidEvidence
        with self.assertRaises(InvalidEvidence): lutram_gate(self.RPT, [r'W\[1\]\.l2\b'])

class StartStallRetryTests(unittest.TestCase):
    # Kalash 2026-10-21 23:42: one relaunch only for a launch that never started; never after output; second stall INVALID.
    HDR = '# xsim {tb_behav} -autoloadwcfg -tclbatch {tb.tcl}\n'
    def test_output_seen_never_retries(self):
        from dual_lane import stall_decision
        self.assertEqual(stall_decision(self.HDR + 'Time resolution is 1 ps\n', 999, 0.0, 1), 'ok')
        self.assertEqual(stall_decision(self.HDR + 'CONFIG: TOP=tb\n', 999, 0.0, 2), 'ok')
    def test_first_stall_retries_second_is_invalid(self):
        from dual_lane import stall_decision
        self.assertEqual(stall_decision(self.HDR, 181, 0.0, 1), 'retry')
        self.assertEqual(stall_decision(self.HDR, 181, None, 1), 'retry')
        self.assertEqual(stall_decision(self.HDR, 181, 0.0, 2), 'invalid')
    def test_no_retry_inside_window_or_while_kernel_computes(self):
        from dual_lane import stall_decision
        self.assertEqual(stall_decision(self.HDR, 120, 0.0, 1), 'wait')
        self.assertEqual(stall_decision(self.HDR, 400, 55.0, 1), 'wait')

class ValidReadyCombLintTests(unittest.TestCase):
    # S1 rule: a default-then-override always_comb that writes a valid/flit and reads a ready is flagged (it caused the
    # P7 zero-delay oscillation); the continuous single-assignment form is not.
    def test_feedback_block_flagged_and_continuous_form_passes(self):
        from dual_lane_preflight import lint_valid_ready_comb
        with tempfile.TemporaryDirectory() as td:
            bad=Path(td)/'bad.sv'; good=Path(td)/'good.sv'
            bad.write_text('module m;\n  always_comb begin\n    ni_rv=0; noc_rx_ready=1;\n    if(a) begin ni_rv=1; noc_rx_ready=ni_rr; end\n  end\nendmodule\n')
            good.write_text('module m;\n  assign ni_rv = a;\n  assign noc_rx_ready = a ? ni_rr : 1;\nendmodule\n')
            self.assertEqual(len(lint_valid_ready_comb([bad])),1)
            self.assertEqual(lint_valid_ready_comb([good]),[])

class ChainedCastInitLintTests(unittest.TestCase):
    # S1 bench rule (2026-10-22): XSim 2024.1 leaves a later declarator X when a chained automatic declaration has a cast
    # initializer; both measured failure forms are flagged, the statement form and cast-free chains are not.
    def test_measured_forms_flagged_statement_form_passes(self):
        from dual_lane_preflight import lint_chained_cast_init
        with tempfile.TemporaryDirectory() as td:
            bad=Path(td)/'bad.sv'; good=Path(td)/'good.sv'
            bad.write_text('\n'.join(['module m;', '  task automatic t(input int a, b);',
                "    automatic coord_t s = tile_to_coord(tile_id_e'(a)), d = tile_to_coord(tile_id_e'(b));",
                "    automatic bit ctl = is_control(msg_type_e'(h.msg_type)), from_peer = h.src_x < 3;",
                '  endtask', 'endmodule', '']))
            good.write_text('\n'.join(['module m;', '  task automatic t(input int a, b);', '    automatic coord_t s, d;',
                "    s = tile_to_coord(tile_id_e'(a)); d = tile_to_coord(tile_id_e'(b));",
                '    automatic logic [127:0] e = q1.pop_front(), x = q2.pop_front();',
                "    automatic head_flit_t h = head_flit_t'(p[0].flit_data);",
                '  endtask', 'endmodule', '']))
            self.assertEqual(len(lint_chained_cast_init([bad])),2)
            self.assertEqual(lint_chained_cast_init([good]),[])

class PythonRtlCompatibilityBannerTests(unittest.TestCase):
    def v(self,records):
        from dual_lane import python_rtl_compatibility
        return python_rtl_compatibility(records)
    def test_match_when_golden_and_control_pass(self):
        self.assertEqual(self.v({'s8_golden':dict(state='PASS_REUSED',observed=dict(checks=95,errors=0)),
                                 's8_control_after':dict(state='PASS_FRESH',observed=dict(checks=95,errors=0))}),'MATCH')
    def test_not_run_when_golden_absent_or_not_selected(self):
        self.assertEqual(self.v({}),'NOT_RUN')
        self.assertEqual(self.v({'s8_golden':dict(state='NOT_RUN',reason='not selected')}),'NOT_RUN')
        self.assertEqual(self.v({'s8_golden':dict(state='BLOCKED',reason='outside active I-3')}),'NOT_RUN')
    def test_mismatch_on_observed_errors(self):
        self.assertEqual(self.v({'s8_golden':dict(state='INVALID',reason='expected 95/0 PASS; observed 95/3 FAIL')}),'MISMATCH')
        self.assertEqual(self.v({'s8_golden':dict(state='PASS_FRESH',observed=dict(errors=0)),
                                 's8_control_after':dict(state='FAIL',reason='gate')}),'MISMATCH')
    def test_infrastructure_invalid_is_not_a_verdict(self):
        self.assertEqual(self.v({'s8_golden':dict(state='INVALID',reason='compile: failed, missing, interrupted or wall timeout')}),'NOT_RUN')
    def test_mutants_do_not_count_as_mismatch(self):
        self.assertEqual(self.v({'s8_golden':dict(state='PASS_FRESH',observed=dict(errors=0)),
                                 's8_mut_lost_tag':dict(state='PASS_FRESH',observed=dict(checks=95,errors=22))}),'MATCH')
    def test_banner_line_uses_computed_verdict(self):
        src=(Path(__file__).resolve().parent/'dual_lane.py').read_text(encoding='utf-8')
        self.assertIn('PYTHON_RTL_COMPATIBILITY={python_rtl_compatibility(records)}',src)
        self.assertNotIn('PYTHON_RTL_COMPATIBILITY=NOT_RUN',src)

class ReferenceAdjudicationTests(unittest.TestCase):
    def test_exit_zero_with_printed_fail_is_rejected(self):
        with self.assertRaisesRegex(InvalidEvidence,'printed failure'):
            judge_suite('measurement_ref.py','Status : FAIL\nMEASUREMENT REFERENCE COMPLETE\n',0)
    def test_reference_timeout_is_rejected(self):
        with self.assertRaisesRegex(InvalidEvidence,'timeout'):
            judge_suite('kmac128_ref.py','KMAC128 KAT: PASS\n',0,True)
    def test_partial_measurement_suite_is_rejected(self):
        with self.assertRaisesRegex(InvalidEvidence,'six parsed'):
            judge_suite('measurement_ref.py','Status : PASS\nMEASUREMENT REFERENCE COMPLETE\n',0)
    def test_positive_measurement_suite(self):
        self.assertEqual(judge_suite('measurement_ref.py','Status : PASS\n'*6+'MEASUREMENT REFERENCE COMPLETE\n',0)['result'],'PASS')
    def test_increment_acceptance_does_not_accept_release(self):
        with tempfile.TemporaryDirectory(prefix='increment report ',dir=str(Path(__file__).resolve().parents[1]/'reports')) as td:
            root=Path(td);out=root/'reports/run';out.mkdir(parents=True)
            registry=dict(active_increment='I-1',increments={'I-1':['baseline','python_ref']},jobs=[dict(id='baseline'),dict(id='python_ref')],stages=[dict(id='NOC-1',jobs=['baseline'],dependencies=[])])
            records={j:dict(state='PASS_FRESH') for j in ['baseline','python_ref']}
            with patch('dual_lane.ROOT',root):status=report(out,records,registry)
            self.assertEqual(status['increment_status'],'PASS')
            self.assertNotEqual(status['status'],'PASS')

class SourcePreflightTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='HDL preflight ',dir=str(Path(__file__).resolve().parents[1]/'reports'))
        self.root=Path(self.tmp.name)
    def tearDown(self):self.tmp.cleanup()
    def check(self, texts, **extra):
        files=[]
        for i,t in enumerate(texts):
            name=f'{i}.sv';(self.root/name).write_text(t);files.append(name)
        return source_names(self.root,dict(kind='simulation',top='tb',sources=files,**extra))
    def test_duplicate_module_rejected(self):
        with self.assertRaisesRegex(PreflightFailure,'duplicate module:tb'):
            self.check(['module tb; endmodule','module tb; endmodule'])
    def test_duplicate_package_rejected(self):
        with self.assertRaisesRegex(PreflightFailure,'duplicate package:p'):
            self.check(['package p; endpackage\nmodule tb; endmodule','package p; endpackage'])
    def test_comments_and_strings_are_not_declarations(self):
        self.assertEqual(len(self.check(['// module tb;\nmodule tb; initial $display("module tb;"); endmodule'])['declarations']),1)
    def test_mutually_exclusive_declarations(self):
        text='`ifdef N7_PIPE0\nmodule tb; endmodule\n`else\nmodule tb; endmodule\n`endif\n'
        for defs in ([],['N7_PIPE0']):self.assertEqual(len(self.check([text],defines=defs)['declarations']),1)
    def test_original_and_variant_collision(self):
        with self.assertRaisesRegex(PreflightFailure,'duplicate package:noc_pkg'):
            self.check(['package noc_pkg; endpackage\nmodule tb; endmodule','package noc_pkg; endpackage'])
    def test_missing_top_rejected(self):
        with self.assertRaisesRegex(PreflightFailure,'selected top'):
            self.check(['module other; endmodule'])

class AdjudicationTests(unittest.TestCase):
    def setUp(self):
        self.job=dict(checks=1,config=dict(TOP='tb',W=16),defines=['N7_PIPE0'])
        self.raw='CONFIG: TOP=tb W=16\nCHECKS : 1\nERRORS : 0\nRESULT : PASS\n'
        self.proc={s:dict(exitCode=0,timedOut=False) for s in ['compile','elaborate','simulate']}
    def reject(self,raw=None,job=None,proc=None,**kw):
        with self.assertRaises(InvalidEvidence):judge(self.raw if raw is None else raw,self.job if job is None else job,self.proc if proc is None else proc,{'source':'a'},{'source':'a'},**kw)
    def test_missing_empty(self):self.reject(raw='')
    def test_wrong_top(self):self.reject(raw=self.raw.replace('TOP=tb','TOP=other'))
    def test_wrong_define_configuration(self):self.reject(raw=self.raw.replace('W=16','W=64'))
    def test_wrong_count(self):self.reject(raw=self.raw.replace('CHECKS : 1','CHECKS : 2'))
    def test_duplicate_pass(self):self.reject(raw=self.raw+'RESULT : PASS\n')
    def test_compile_failure(self):
        p=copy.deepcopy(self.proc);p['compile']['exitCode']=1;self.reject(proc=p)
    def test_xelab_failure(self):
        p=copy.deepcopy(self.proc);p['elaborate']['exitCode']=1;self.reject(proc=p)
    def test_simulator_crash(self):
        p=copy.deepcopy(self.proc);p['simulate']['exitCode']=-1073741819;self.reject(proc=p)
    def test_wall_timeout(self):
        p=copy.deepcopy(self.proc);p['simulate']['timedOut']=True;self.reject(proc=p)
    def test_interrupted(self):
        p=copy.deepcopy(self.proc);p['simulate']['interrupted']=True;self.reject(proc=p)
    def test_missing_process(self):
        p=copy.deepcopy(self.proc);p.pop('compile');self.reject(proc=p)
    def test_tb_assertion(self):self.reject(raw=self.raw+'Error: assertion failed\n')
    def test_missing_n0_marker(self):self.reject(job=dict(self.job,negative=True))
    def test_tb_timeout(self):self.reject(raw=self.raw+'TB_TIMEOUT global\n')
    def test_source_changes(self):
        with self.assertRaises(InvalidEvidence):judge(self.raw,self.job,self.proc,{'source':'a'},{'source':'b'})
    def test_cleanup_failure(self):self.reject(cleanup=False)
    def test_surviving_mutant(self):self.reject(job=dict(self.job,mutant='lost_tag',oracle=r'^\[FAIL\] TARGET'))
    def test_untargeted_mutant(self):self.reject(raw=self.raw.replace('ERRORS : 0','ERRORS : 1').replace('RESULT : PASS','RESULT : FAIL')+'[FAIL] OTHER\n',job=dict(self.job,mutant='lost_tag',oracle=r'^\[FAIL\] TARGET'))
    def test_missing_dependency(self):self.assertFalse(dependencies_ok(dict(dependencies=['a']),{}))
    def test_running_dependency(self):self.assertFalse(dependencies_ok(dict(dependencies=['a']),{'a':dict(state='RUNNING')}))
    def test_incomplete_matrix(self):self.assertFalse(complete({str(i):dict(state='PASS_FRESH') for i in range(9)}))
    def test_valid_positive_control(self):self.assertEqual(judge(self.raw,self.job,self.proc,{}, {})['result'],'PASS')
    def test_effective_targeted_control(self):
        raw=self.raw.replace('ERRORS : 0','ERRORS : 1').replace('RESULT : PASS','RESULT : FAIL')+'[FAIL] TARGET\n'
        self.assertEqual(judge(raw,dict(self.job,mutant='lost_tag',oracle=r'^\[FAIL\] TARGET'),self.proc,{}, {})['result'],'KILLED')
    # Hardening (Codex F8): negative automation tests
    def mut_raw(self,fails,checks=1):
        return self.raw.replace('CHECKS : 1',f'CHECKS : {checks}').replace('ERRORS : 0','ERRORS : 1').replace('RESULT : PASS','RESULT : FAIL')+''.join(f'[FAIL] {f}\n' for f in fails)
    def test_incomplete_mutant_rejected(self):
        self.reject(raw=self.mut_raw(['TARGET']),job=dict(self.job,checks=2,mutant='lost_tag',oracle=r'^\[FAIL\] TARGET'))
    def test_unrelated_failure_with_target_rejected(self):
        self.reject(raw=self.mut_raw(['TARGET','OTHER']),job=dict(self.job,mutant='lost_tag',oracle=r'^\[FAIL\] TARGET'))
    def test_kill_scope_admits_related_failures(self):
        j=dict(self.job,mutant='lost_tag',oracle=r'^\[FAIL\] TARGET',kill_scope=r'^\[FAIL\] (TARGET|RELATED)')
        self.assertEqual(judge(self.mut_raw(['TARGET','RELATED']),j,self.proc,{},{})['result'],'KILLED')
    def test_unexpected_diag_in_mutant_rejected(self):
        self.reject(raw=self.mut_raw(['TARGET'])+'Error: something else\n',job=dict(self.job,mutant='lost_tag',oracle=r'^\[FAIL\] TARGET',expected_diag=[r'^Error: expected only$']))
    def ooc_m(self,**kw):
        m=dict(LATCHES='0',WNS='1.0',WHS='0.1',WPWS='9.5',TNS='0.000',THS='0.000',CELLS='10',DRC_ERRORS='0',UNCONSTRAINED_ENDPOINTS='0',LUT='100'); m.update(kw); return m
    def test_ooc_valid(self): self.assertIsNone(ooc_gate(self.ooc_m(),dict(child_script='x',max_lut=100)))
    def test_ooc_drc_errors_fail(self):
        with self.assertRaises(GateFailure): ooc_gate(self.ooc_m(DRC_ERRORS='1'),dict(child_script='x'))
    def test_ooc_over_budget_fail(self):
        with self.assertRaises(GateFailure): ooc_gate(self.ooc_m(LUT='47551'),dict(child_script='x',max_lut=47550))
    def test_ooc_missing_drc_invalid(self):
        m=self.ooc_m(); m.pop('DRC_ERRORS')
        with self.assertRaises(InvalidEvidence): ooc_gate(m,dict(child_script='x'))
    def test_ooc_unconstrained_fail(self):
        with self.assertRaises(GateFailure): ooc_gate(self.ooc_m(UNCONSTRAINED_ENDPOINTS='3'),dict(child_script='x'))
    def test_ooc_tns_fail(self):
        with self.assertRaises(GateFailure): ooc_gate(self.ooc_m(TNS='-0.1'),dict(child_script='x'))
    # contract sec. 6 P&R checkpoint gate: every bound, a missing metric and a foreign clock-source model
    def pnr_m(self,**kw):
        m=dict(PNR_WNS='0.4',PNR_TNS='0.000',PNR_WHS='0.05',PNR_THS='0.000',PNR_WPWS='8.75',PNR_ROUTE_ERRORS='0',PNR_DRC_ERRORS='0',
               PNR_UNCONSTRAINED_ENDPOINTS='0',PNR_LUT='44000',PNR_LUTRAM='2448',PNR_CONTROL_SETS='900',PNR_CLK_SRC='BUFGCTRL_X0Y0'); m.update(kw); return m
    def test_pnr_valid(self): self.assertIsNone(pnr_gate(self.pnr_m()))
    def test_pnr_each_bound_fails(self):
        for k,v in (('PNR_WNS','-0.01'),('PNR_WHS','-0.01'),('PNR_WPWS','-1'),('PNR_TNS','-0.5'),('PNR_THS','-0.2'),
                    ('PNR_ROUTE_ERRORS','2'),('PNR_DRC_ERRORS','1'),('PNR_UNCONSTRAINED_ENDPOINTS','4')):
            with self.subTest(k=k):
                with self.assertRaises(GateFailure): pnr_gate(self.pnr_m(**{k:v}))
    def test_pnr_missing_or_na_invalid(self):
        m=self.pnr_m(); m.pop('PNR_ROUTE_ERRORS')
        with self.assertRaises(InvalidEvidence): pnr_gate(m)
        with self.assertRaises(InvalidEvidence): pnr_gate(self.pnr_m(PNR_DRC_ERRORS='NA'))
    def test_pnr_foreign_clock_model_invalid(self):
        with self.assertRaises(InvalidEvidence): pnr_gate(self.pnr_m(PNR_CLK_SRC='BUFGCTRL_X0Y5'))
    def test_package_pass_requires_accepted_upstream(self):
        with tempfile.TemporaryDirectory(prefix='dual lane report ',dir=str(Path(__file__).resolve().parents[1]/'reports')) as td:
            root=Path(td); out=root/'reports'/'checkpoint';out.mkdir(parents=True)
            records={'baseline':dict(state='INVALID'),'chain':dict(state='PASS_FRESH')}
            registry=dict(jobs=[dict(id='baseline'),dict(id='chain')],stages=[
                dict(id='NOC-1',jobs=['baseline'],dependencies=[]),
                dict(id='PQ-5',jobs=['chain'],dependencies=['NOC-1'])])
            with patch('dual_lane.ROOT',root): status=report(out,records,registry)
            self.assertEqual(status['stages']['PQ-5']['state'],'BLOCKED')
            self.assertEqual(status['status'],'FAIL')
            self.assertEqual(records['chain']['state'],'PASS_FRESH')

class InstallationTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='dual lane test ',dir=str(Path(__file__).resolve().parents[1]/'reports'))
        self.root=Path(self.tmp.name);self.pkg=self.root/'payload';self.pkg.mkdir()
        self.old=self.root/'old.txt';self.old.write_text('user original')
        self.new=self.pkg/'new.txt';self.new.write_text('prepared update')
        self.man=self.pkg/'manifest.json';atomic(self.man,dict(files=[dict(path='old.txt',payload='new.txt',before=sha(self.old),after=sha(self.new))]))
    def tearDown(self):self.tmp.cleanup()
    def test_stale_pass_artifact(self):
        r=dict(artifacts={str(self.old):sha(self.old)});self.old.write_text('changed');self.assertFalse(artifacts_valid(r))
    def test_atomic_transient_windows_lock(self):
        original=os.replace; calls=[]
        def rename(a,b):
            calls.append((a,b))
            if len(calls)==1:raise PermissionError('injected transient reader lock')
            return original(a,b)
        with patch('dual_lane.os.name','nt'),patch('dual_lane.os.replace',side_effect=rename),patch('dual_lane.time.sleep'):
            atomic(self.old,'replacement')
        self.assertEqual(self.old.read_text(),'replacement');self.assertEqual(len(calls),2)
        self.assertEqual(calls[0],calls[1])
    def test_atomic_permanent_denial_preserves_destination(self):
        with patch('dual_lane.os.name','nt'),patch('dual_lane.os.replace',side_effect=PermissionError('injected permanent denial')) as replace,patch('dual_lane.time.sleep'):
            with self.assertRaises(PermissionError):atomic(self.old,'replacement')
        self.assertEqual(replace.call_count,6);self.assertEqual(self.old.read_text(),'user original')
    def test_path_with_spaces_and_atomic_install(self):
        install(self.root,self.man);self.assertEqual(self.old.read_text(),'prepared update');install(self.root,self.man)
        self.assertEqual(len(json.loads((self.pkg/'install_journal.json').read_text())['written']),1)
    def test_dirty_file_conflict(self):
        self.old.write_text('later user edit')
        with self.assertRaises(InvalidEvidence):install(self.root,self.man)
        self.assertEqual(self.old.read_text(),'later user edit')
    def test_full_preflight_before_first_write(self):
        m=json.loads(self.man.read_text());m['files'].append(dict(path='new.txt',payload='new.txt',before='unknown',after='wrong'));atomic(self.man,m)
        with self.assertRaises(InvalidEvidence):install(self.root,self.man)
        self.assertEqual(self.old.read_text(),'user original')
    def test_rollback_protects_later_edit(self):
        install(self.root,self.man);self.old.write_text('user changed after install')
        with self.assertRaises(InvalidEvidence):install(self.root,self.man,rollback=True)
        self.assertEqual(self.old.read_text(),'user changed after install')
    def test_rollback_exact_written_file(self):
        install(self.root,self.man);install(self.root,self.man,rollback=True);self.assertEqual(self.old.read_text(),'user original')
    def test_escape(self):
        m=json.loads(self.man.read_text());m['files'][0]['path']='../outside';atomic(self.man,m)
        with self.assertRaises(InvalidEvidence):install(self.root,self.man)
    def test_interrupted_install_resume(self):
        row=json.loads(self.man.read_text())['files'][0]
        backup=self.pkg/'backup.txt';backup.write_text(self.old.read_text())
        atomic(self.pkg/'install_journal.json',dict(state='INSTALLING',written=[],pending=dict(path='old.txt',after=row['after'],backup='backup.txt')))
        self.old.write_text(self.new.read_text())
        install(self.root,self.man)
        journal=json.loads((self.pkg/'install_journal.json').read_text())
        self.assertEqual(len(journal['written']),1)
        install(self.root,self.man,rollback=True)
        self.assertEqual(self.old.read_text(),'user original')

class IRQClosureMutationTests(unittest.TestCase):
    def test_merged_coverage_controls(self):
        from dual_lane import mutation
        root=Path(__file__).resolve().parents[1]
        for rel,kind in [('rtl/dual_lane/merged/pq_soc_merged_core.sv','rvo_drop_busy'),('rtl/dual_lane/noc_attest_gate.sv','rvg_ignore_revoke')]:
            text=(root/rel).read_text()
            self.assertNotEqual(text,mutation(text,kind))
            with self.assertRaises(InvalidEvidence):mutation('',kind)
    def test_ni_and_debug_mutations_are_effective(self):
        from dual_lane import mutation
        original=(Path(__file__).resolve().parents[1]/'rtl/riscv/tile_top.sv').read_text()
        for k in ('rvt_ni_count_zero','rvt_debug_data'):
            self.assertNotEqual(original,mutation(original,k))
            with self.assertRaises(InvalidEvidence):mutation('',k)

    def test_irq_mutation_changes_only_the_wiring(self):
        from dual_lane import mutation
        p=Path(__file__).resolve().parents[1]/'rtl/riscv/tile_top.sv'
        original=p.read_text()
        mutated=mutation(original,'rvt_irq_off')
        self.assertIn(".irq       (32'b0)",mutated)
        self.assertNotEqual(original,mutated)

    def test_irq_mutation_refuses_missing_anchor(self):
        from dual_lane import mutation
        with self.assertRaises(InvalidEvidence): mutation('module empty; endmodule','rvt_irq_off')

class ReleasePythonEnvironmentTests(unittest.TestCase):
    def test_foreign_python_path_is_ignored(self):
        import subprocess
        from merged_release import python_child
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);foreign=root/'foreign';foreign.mkdir();clean=root/'clean';clean.mkdir()
            (foreign/'re.py').write_text('raise RuntimeError("FOREIGN_PYTHON_LIBRARY")\n')
            script=clean/'probe.py';script.write_text('import re, argparse\nprint("CHILD_IMPORT_PASS")\n')
            env=os.environ.copy();env['PYTHONPATH']=str(foreign)
            isolated=subprocess.run(python_child(script),env=env,capture_output=True,text=True,timeout=30)
            self.assertEqual(isolated.returncode,0,isolated.stderr)
            self.assertIn('CHILD_IMPORT_PASS',isolated.stdout)
            import sys
            unsafe=subprocess.run([sys.executable,str(script)],env=env,capture_output=True,text=True,timeout=30)
            self.assertNotEqual(unsafe.returncode,0)
            self.assertIn('FOREIGN_PYTHON_LIBRARY',unsafe.stderr)

    def test_isolated_child_failure_is_not_suppressed(self):
        import subprocess
        from merged_release import python_child
        with tempfile.TemporaryDirectory() as t:
            script=Path(t)/'failure.py';script.write_text('raise SystemExit(7)\n')
            child=subprocess.run(python_child(script),capture_output=True,text=True,timeout=30)
            self.assertEqual(child.returncode,7)

if __name__=='__main__':unittest.main(verbosity=2)
