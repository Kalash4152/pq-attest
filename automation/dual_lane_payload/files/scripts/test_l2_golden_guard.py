"""L2 oracle guard self-test (2026-10-19): the guard must reject the pre-724c96e aliasing defect,
accept the fixed generator, and the KMAC128 known-answer check must run through l2_golden's kmac128."""
import copy
import json
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import l2_golden as L  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


class L2OracleGuardTests(unittest.TestCase):
    def test_fixed_generator_passes_guard(self):
        m = L.build()
        L.guard_packets(m['packets'], L.rebuild_genuine())

    def test_synthetic_aliasing_is_rejected(self):
        # Old generate(): a list holding one shared base object, deep-copied, then mutated per case.
        base = [0x1, 0x2, 0x3]
        cases = copy.deepcopy([base, base, base])   # deepcopy keeps the three references shared
        cases[1][0] ^= 0x80                         # "tamper" case 1 ...
        self.assertIs(cases[0], cases[1])           # ... which also mutates case 0 (the genuine one)
        with self.assertRaisesRegex(AssertionError, 'same packet'):
            L.guard_packets({'genuine': cases[0], 'tamper': cases[1]}, {})
        with self.assertRaisesRegex(AssertionError, 'freshly rebuilt'):
            L.guard_packets({'ch1_genuine': cases[0]}, {'ch1_genuine': base[:1] + [0x2, 0x3]})

    def test_pre_724c96e_vectors_are_rejected(self):
        old = subprocess.run(['git', 'show', '57b7031:vectors/l2_golden.json'], cwd=ROOT,
                             capture_output=True, text=True, check=True).stdout
        cases = json.loads(old)['cases']
        packets = {f'case{i}': [json.dumps(c.get('flits', c), sort_keys=True)] for i, c in enumerate(cases)}
        with self.assertRaisesRegex(AssertionError, 'same packet'):
            L.guard_packets(packets, {})

    def test_mutated_genuine_is_rejected(self):
        m = L.build()
        bad = dict(m['packets']); bad['ch1_genuine'] = list(bad['ch1_genuine']); bad['ch1_genuine'][0] ^= 1 << 10
        with self.assertRaisesRegex(AssertionError, 'freshly rebuilt'):
            L.guard_packets(bad, L.rebuild_genuine())

    def test_kmac_kat_through_l2_call_path(self):
        L.kmac_kat()
        with unittest.mock.patch.object(L, 'kmac128', lambda *a, **k: b'\0' * 32):
            with self.assertRaisesRegex(AssertionError, 'NIST sample 2'):
                L.kmac_kat()


if __name__ == '__main__':
    import unittest.mock  # noqa: F401
    unittest.main()
