"""V8 job py_teammate_examples: the teammate's OWN example profile (16-byte keys), unchanged.

Inputs and frozen expected values are read from the pinned teammate files themselves
(kdf_vectors.TEST_CASES / ROOT_SECRET, the expected dict literal inside
kdf_vectors.verify_expected_vectors, attestation_vectors constants). Nothing is re-typed here.
This job never touches the 32-byte RTL system profile (see py_rtl_profile_32.py).
"""
import ast
import contextlib
import importlib
import io
import sys

from s8_golden import REF_DIR, assert_inside_reference, derive_tile_key, PROTO

kdf_vectors = importlib.import_module('kdf_vectors')
attestation_vectors = importlib.import_module('attestation_vectors')
assert_inside_reference([kdf_vectors, attestation_vectors])


def frozen_kdf_expected():
    """The literal `expected = {...}` dict from kdf_vectors.verify_expected_vectors."""
    tree = ast.parse((REF_DIR / 'kdf_vectors.py').read_text(encoding='utf-8-sig'))
    for fn in ast.walk(tree):
        if isinstance(fn, ast.FunctionDef) and fn.name == 'verify_expected_vectors':
            for node in ast.walk(fn):
                if (isinstance(node, ast.Assign) and len(node.targets) == 1
                        and getattr(node.targets[0], 'id', None) == 'expected'):
                    return ast.literal_eval(node.value)
    raise RuntimeError('frozen expected dict not found in teammate kdf_vectors.py')


def main():
    checks = []
    expected = frozen_kdf_expected()
    cases = kdf_vectors.TEST_CASES
    if set(expected) != {c['name'] for c in cases} or len(cases) != 6:
        raise SystemExit('PY_TEAMMATE_EXAMPLES: FAIL teammate case/expected set mismatch')
    for c in cases:
        got = derive_tile_key(kdf_vectors.ROOT_SECRET, c['tile_id'], c['epoch'],
                              c['context'], c['key_bytes']).hex()
        checks.append((f"KDF {c['name']} key{c['key_bytes']}", got == expected[c['name']],
                       got, expected[c['name']]))
    # The teammate's own generate+verify routine (output suppressed, verdict kept).
    with contextlib.redirect_stdout(io.StringIO()):
        own = kdf_vectors.verify_expected_vectors(kdf_vectors.generate_vectors())
    checks.append(('kdf_vectors.verify_expected_vectors', own is True, own, True))
    # attestation_vectors.TILE_KEY is the teammate's frozen V01 16-byte key.
    tk = attestation_vectors.TILE_KEY.hex()
    checks.append(('attestation_vectors.TILE_KEY == V01_basic', tk == expected['V01_basic'],
                   tk, expected['V01_basic']))
    # Teammate protocol round trip at the teammate's 16-byte example key.
    req = PROTO.AttestationRequest(attestation_vectors.TILE_ID, attestation_vectors.EPOCH,
                                   attestation_vectors.NONCE)
    resp = PROTO.tile_respond(attestation_vectors.TILE_KEY, req, attestation_vectors.MEASUREMENT)
    verdict = PROTO.verifier_check(attestation_vectors.TILE_KEY, req, resp)
    checks.append(('protocol round trip key16 ACCEPT', verdict.accepted, verdict.reason, 'ACCEPT'))
    bad = [c for c in checks if not c[1]]
    for name, ok, got, exp in checks:
        print(f"{'PASS' if ok else 'FAIL'} {name}: {got}" + ('' if ok else f' expected {exp}'))
    print('PROFILE=teammate_examples KEY_BYTES=16,32(teammate V06) SYSTEM_PROFILE_NOT_USED')
    if bad:
        print(f'PY_TEAMMATE_EXAMPLES: FAIL n={len(bad)}/{len(checks)}')
        sys.exit(1)
    print(f'PY_TEAMMATE_EXAMPLES: PASS n={len(checks)}')


if __name__ == '__main__':
    main()
