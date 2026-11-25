"""Pure-Python checks for the I-3 / PQ-2 endpoint mutants (Track Q2). No simulator is run.

Single source of truth: the anchors are parsed from reports/i3_q2/mutation.i3_q2.patch (the
'+' lines that add them to scripts/dual_lane.py mutation()). The test proves, for each mutant:
  1. the anchor occurs exactly once in rtl/dual_lane/pq_attest_endpoint.sv (and not in comments elsewhere),
  2. the replacement differs, is absent from the clean file, and the mutated text contains it once,
  3. the mutated file still carries every other anchor exactly once (mutants are independent),
  4. the targeted check name is emitted by tb_pq_endpoint_unit.sv and the oracle regex
     frozen in prepare_dual_lane.i3_q2.patch matches the [FAIL] line that check prints.
Run: python reports/i3_q2/test_q2_mutants.py   (exit 0 = all pass)
"""
from __future__ import annotations
import ast
import re
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ENDPOINT = ROOT / 'rtl/dual_lane/pq_attest_endpoint.sv'
UNIT_TB = ROOT / 'NOC_PQATTEST.srcs/sim_1/new/tb_pq_endpoint_unit.sv'
MUT_PATCH = HERE / 'mutation.i3_q2.patch'
PREP_PATCH = HERE / 'prepare_dual_lane.i3_q2.patch'

# kind -> (example [FAIL] line printed by the targeted check, TB source fragment that names it)
TARGETED = {
    'ep_tag_swap': ('[FAIL] V00_TAG_WORDS', '"_TAG_WORDS"'),
    'ep_nonce_offset': ('[FAIL] V00_EPOCH_NONCE_FIELDS', '"_EPOCH_NONCE_FIELDS"'),
    'ep_wrong_reply': ('[FAIL] REPLY_TO_LATCHED', '"REPLY_TO_LATCHED"'),
    'ep_rx_stall': ('[FAIL] RX_READY_ALWAYS', '"RX_READY_ALWAYS"'),
}


def patch_anchors() -> dict:
    added = [l[1:] for l in MUT_PATCH.read_text(encoding='utf-8').splitlines()
             if l.startswith('+') and not l.startswith('+++')]
    text = '\n'.join(added)
    m = re.search(r"anchors=(\{.*?\})\n", text, re.S)
    assert m, 'anchor dict not found in mutation patch'
    return ast.literal_eval(m.group(1))


def prep_oracles() -> dict:
    text = PREP_PATCH.read_text(encoding='utf-8')
    m = re.search(r"^\+EP_MUTANTS=(\[.*?\])$", text, re.M)
    assert m, 'EP_MUTANTS not found in prepare patch'
    return {'ep_' + k: o for k, o in ast.literal_eval(m.group(1))}   # job mutant = 'ep_'+name


class Q2Mutants(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.src = ENDPOINT.read_text(encoding='utf-8')
        cls.anchors = patch_anchors()
        cls.oracles = prep_oracles()

    def test_four_mutants(self):
        self.assertEqual(set(self.anchors), set(TARGETED))
        self.assertEqual(set(self.oracles), set(TARGETED))

    def test_anchor_unique_and_replacement(self):
        for kind, (a, b) in self.anchors.items():
            with self.subTest(kind=kind):
                self.assertEqual(self.src.count(a), 1, f'{kind}: anchor not unique')
                self.assertNotEqual(a, b)
                self.assertEqual(self.src.count(b), 0)
                mutated = self.src.replace(a, b)
                self.assertEqual(mutated.count(b), 1)
                self.assertEqual(mutated.count(a), 0)
                self.assertIn('MUT-EP', b)
                self.assertNotIn('MUT-EP', self.src)
                for other, (oa, _) in self.anchors.items():
                    if other != kind:
                        self.assertEqual(mutated.count(oa), 1, f'{kind} disturbs {other}')

    def test_anchor_is_code_not_comment(self):
        lines = self.src.splitlines()
        for kind, (a, _) in self.anchors.items():
            with self.subTest(kind=kind):
                line = next(l for l in lines if a in l)
                self.assertFalse(line.lstrip().startswith('//'))

    def test_targeted_checks_and_oracles(self):
        tb = UNIT_TB.read_text(encoding='utf-8')
        for kind, (fail_line, fragment) in TARGETED.items():
            with self.subTest(kind=kind):
                self.assertIn(fragment, tb)
                self.assertRegex(fail_line, re.compile(self.oracles[kind], re.M))
        # No oracle matches the PASS form or another mutant's targeted line.
        for kind, oracle in self.oracles.items():
            for other, (fail_line, _) in TARGETED.items():
                hit = re.search(oracle, fail_line, re.M) is not None
                self.assertEqual(hit, other == kind, f'oracle {kind} vs {other}')
            self.assertIsNone(re.search(oracle, TARGETED[kind][0].replace('[FAIL]', '[PASS]'), re.M))

    def test_patches_on_temp_copy(self):
        """Apply both patches to a TEMP copy of scripts/ (the repo is never modified), then
        exercise the patched mutation() and build_registry() and the duplicate-name preflight."""
        import importlib, shutil, subprocess, tempfile
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            shutil.copytree(ROOT / 'scripts', tmp / 'scripts', ignore=shutil.ignore_patterns('__pycache__'))
            (tmp / 'docs/decisions').mkdir(parents=True)
            shutil.copyfile(ROOT / 'docs/decisions/dual_lane_config.json', tmp / 'docs/decisions/dual_lane_config.json')
            for patch in (MUT_PATCH, PREP_PATCH):
                p = subprocess.run(['git', 'apply', '--check', str(patch)], cwd=tmp, capture_output=True, text=True)
                self.assertEqual(p.returncode, 0, p.stderr)
                subprocess.run(['git', 'apply', str(patch)], cwd=tmp, check=True)
            sys.path.insert(0, str(tmp / 'scripts'))
            saved = {m: sys.modules.pop(m) for m in list(sys.modules)
                     if m in ('dual_lane', 'dual_lane_verify', 'dual_lane_preflight', 'controlled_diagnostics',
                              'prepare_dual_lane', 'prepare_n6_credit_window')}
            try:
                sys.dont_write_bytecode = True
                dl = importlib.import_module('dual_lane')
                for kind, (a, b) in self.anchors.items():
                    self.assertEqual(dl.mutation(self.src, kind), self.src.replace(a, b))
                    with self.assertRaises(dl.InvalidEvidence):
                        dl.mutation(self.src.replace(a, b), kind)
                prep = importlib.import_module('prepare_dual_lane')
                reg = prep.build_registry(check_files=False)
                jobs = {j['id']: j for j in reg['jobs']}
                ep = ['endpoint_python', 'pq_endpoint_unit', 'pq_endpoint_sys', 'pq_endpoint_mut_tag_swap',
                      'pq_endpoint_mut_nonce_offset', 'pq_endpoint_mut_wrong_reply', 'pq_endpoint_mut_rx_stall',
                      'pq_endpoint_control_after']
                self.assertEqual(reg['increments']['I-3'], ep)
                self.assertEqual(reg['active_increment'], 'I-2')
                self.assertNotIn('pq_endpoint', jobs)
                self.assertEqual(next(s for s in reg['stages'] if s['id'] == 'PQ-2')['jobs'], ep)
                self.assertEqual(jobs['pq_endpoint_unit']['checks'], 275)
                self.assertEqual(jobs['pq_endpoint_sys']['checks'], 37)
                self.assertEqual(jobs['pq_endpoint_control_after']['checks'], 275)
                prod_pkg = 'NOC_PQATTEST.srcs/sources_1/new/NOC_PKG.sv'
                prod_ni = 'NOC_PQATTEST.srcs/sources_1/new/noc_network_interface.sv'
                pre = importlib.import_module('dual_lane_preflight')
                for jid in ep:
                    j = jobs[jid]
                    self.assertEqual(j['selection'], 'I-3')
                    for s in j['sources']:
                        self.assertTrue((ROOT / s).is_file(), s)
                    self.assertNotIn(prod_pkg, j['sources']); self.assertNotIn(prod_ni, j['sources'])
                    if j['kind'] == 'simulation':
                        self.assertEqual(pre.source_names(ROOT, j)['state'], 'PASS')
                for m in ep[3:7]:
                    self.assertEqual(jobs[m]['mutant'], 'ep_' + m.split('pq_endpoint_mut_')[1])
                    self.assertEqual(jobs[m]['dependencies'], ['pq_endpoint_unit'])
            finally:
                sys.path.remove(str(tmp / 'scripts'))
                for m in ('dual_lane', 'dual_lane_verify', 'dual_lane_preflight', 'controlled_diagnostics',
                          'prepare_dual_lane', 'prepare_n6_credit_window'):
                    sys.modules.pop(m, None)
                sys.modules.update(saved)

    def test_no_fatal_in_benches(self):
        for tb in (UNIT_TB, UNIT_TB.with_name('tb_pq_endpoint_sys.sv')):
            with self.subTest(tb=tb.name):
                text = tb.read_text(encoding='utf-8')
                self.assertIsNone(re.search(r'\$fatal\s*\(', text), 'a $fatal call in a bench')
                self.assertRegex(text, r'\$display\("CONFIG: TOP=' + tb.stem)
                for marker in ('"CHECKS : %0d"', '"ERRORS : %0d"', '"RESULT : %s"'):
                    self.assertEqual(text.count(marker), 1)


if __name__ == '__main__':
    r = unittest.main(exit=False, verbosity=2).result
    print('Q2_MUTANT_TESTS:', 'PASS' if r.wasSuccessful() else 'FAIL', f'({r.testsRun} tests)')
    sys.exit(0 if r.wasSuccessful() else 1)
