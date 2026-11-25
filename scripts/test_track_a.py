"""Unit tests for I-2 Track A (PQ-1 V7/V8/V10 adapters). stdlib unittest only."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
import s8_golden as A  # noqa: E402

REPO_KMAC = A.ROOT / 'software/kmac128_ref.py'
TB = A.ROOT / 'NOC_PQATTEST.srcs/sim_1/new'


def good():
    return dict(tile=b'TILE_01', epoch=b'EPOCH_0001', nonce=bytes(16), root=bytes(range(32)),
                context=b'PQ-ATTEST-KDF', config=bytes(16), imem=bytes(16))


def call(**over):
    a = good(); a.update(over)
    return A.compose(a['tile'], a['epoch'], a['nonce'], a['root'], a['context'], a['config'], a['imem'])


class ImportGuard(unittest.TestCase):
    def test_reference_modules_resolve_inside_pinned_tree(self):
        base = (A.ROOT / 'software/pq_attest_final').resolve()
        for m in (A.KMAC, A.MEAS, A.ATT, A.PROTO, A._keccak, A._sha3):
            self.assertIn(base, Path(m.__file__).resolve().parents, m.__name__)
        self.assertNotEqual(Path(A.KMAC.__file__).resolve(), REPO_KMAC.resolve())

    def test_guard_rejects_repo_kmac_module(self):
        spec = importlib.util.spec_from_file_location('kmac128_ref', REPO_KMAC)
        mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
        with self.assertRaises(A.ReferenceIdentityError):
            A.assert_inside_reference([mod])

    def test_import_fails_loudly_when_repo_kmac_shadows(self):
        code = ('import sys,importlib.util;sys.dont_write_bytecode=True;'
                f'sys.path.insert(0,{str(SCRIPTS)!r});'
                f"s=importlib.util.spec_from_file_location('kmac128_ref',{str(REPO_KMAC)!r});"
                'm=importlib.util.module_from_spec(s);s.loader.exec_module(m);'
                "sys.modules['kmac128_ref']=m\n"
                'try:\n import s8_golden\nexcept Exception as e:\n'
                ' print(type(e).__name__);sys.exit(3)\nsys.exit(0)')
        r = subprocess.run([sys.executable, '-B', '-c', code], capture_output=True, text=True,
                           timeout=60, cwd=str(A.ROOT))
        self.assertEqual(r.returncode, 3, r.stdout + r.stderr)
        self.assertIn('ReferenceIdentityError', r.stdout)

    def test_hash_mismatch_fails_loudly(self):
        cfg = json.loads(A.CONFIG.read_text(encoding='utf-8'))
        name = 'PQ_Attest/software/kmac128_ref.py'
        cfg['python_reference']['members'][name] = '0' * 64
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'cfg.json'; p.write_text(json.dumps(cfg), encoding='utf-8')
            old = A.CONFIG; A.CONFIG = p
            try:
                with self.assertRaises(A.ReferenceIdentityError):
                    A.verify_reference_hashes()
            finally:
                A.CONFIG = old
        self.assertEqual(A.verify_reference_hashes()['sha256'], A.REFERENCE['sha256'])


class ProfileValidation(unittest.TestCase):
    def test_rejects_bad_lengths(self):
        for over in [dict(nonce=bytes(15)), dict(nonce=bytes(17)), dict(tile=b'TILE_001'),
                     dict(tile=b'TILE1'), dict(epoch=bytes(9)), dict(epoch=bytes(11)),
                     dict(root=bytes(31)), dict(context=bytes(15)), dict(config=bytes(65)),
                     dict(imem=bytes(65))]:
            with self.subTest(over={k: len(v) for k, v in over.items()}):
                with self.assertRaises(ValueError):
                    call(**over)

    def test_rejects_non_bytes(self):
        with self.assertRaises(TypeError):
            call(nonce='0' * 16)

    def test_accepts_boundaries(self):
        for over in [dict(context=b''), dict(context=bytes(14)), dict(config=b'', imem=b''),
                     dict(config=bytes(64), imem=bytes(64)), dict(config=bytes(64), imem=b''),
                     dict(config=b'', imem=bytes(64))]:
            r = call(**over)
            self.assertEqual(len(bytes.fromhex(r['key'])), 32)
            self.assertEqual(len(bytes.fromhex(r['response'])), 97)


class CommittedLiterals(unittest.TestCase):
    def test_kdf_literals(self):
        for i, (t, e, c, n) in enumerate(A.KDF_CASES, 1):
            k = A.derive_tile_key(bytes(range(32)), t, e, c, key_bytes=n)
            self.assertEqual(A.literal(TB / 'pq_kdf_tb.sv', f'V0{i}', 32), k.ljust(32, b'\0'))

    def test_measurement_literals(self):
        for i, (t, c, m) in enumerate(A.MEAS_CASES, 1):
            self.assertEqual(A.literal(TB / 'pq_measurement_tb.sv', f'M0{i}', 32), A.measure_tile(t, c, m))

    def test_tag_literals(self):
        for i, args in enumerate(A.tag_cases(), 1):
            name = 'V08_EMPTY_CUSTOM' if i == 8 else f'V0{i}'
            self.assertEqual(A.literal(TB / 'pqattest_tb.sv', name, 32), A.tag_value(*args).ljust(32, b'\0'))

    def test_committed_s8_vectors(self):
        data = json.loads((A.ROOT / 'vectors/s8_golden.json').read_text(encoding='utf-8'))
        self.assertEqual(data, A.vectors())
        self.assertEqual(len(data['vectors']), 8)

    def test_committed_chain_and_l2(self):
        import full_chain_golden, l2_golden
        self.assertEqual(json.loads((A.ROOT / 'vectors/full_chain.json').read_text(encoding='utf-8')),
                         full_chain_golden.produce()[0])
        self.assertEqual(json.loads((A.ROOT / 'vectors/l2_golden.json').read_text(encoding='utf-8')),
                         json.loads(json.dumps(l2_golden.generate()[0])))


class Policy(unittest.TestCase):
    def test_both_verdicts_recorded(self):
        import policy_layer
        rot, fails = policy_layer.selftest()
        self.assertEqual(fails, [])
        v = {r['case']: (r['reference_verdict'], r['policy_verdict']) for r in rot.records}
        self.assertEqual(v['genuine'], ('ACCEPT', 'ACCEPT'))
        self.assertEqual(v['duplicate_response'], ('ACCEPT', 'REJECT'))
        self.assertEqual(v['unapproved_measurement'], ('ACCEPT', 'REJECT'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
