"""S-8 golden vectors: THIN ADAPTER over the pinned teammate reference (Revision 4 K-5, V7).

Authority: Pq_Attest_final.zip (sha256 047bb5a9...), extracted read-only at
software/pq_attest_final/PQ_Attest/software/. Every algorithm, customization string,
truncation and length comes from that reference; this file only
  * byte <-> SV-word packing (byte i at [i*8 +: 8]),
  * selects key_bytes=32 (K-1, TILE_KEY_BYTES=32 system profile),
  * validates the hardware profile (tile 7, epoch 10, nonce 16, root 32,
    context <= 14, config <= 64, imem <= 64).
The repo copy software/kmac128_ref.py is a SUPPLEMENTARY KAT only and is never imported here.
All keys/nonces are OFFLINE DEMO data.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
REF_BASE = ROOT / 'software/pq_attest_final'
REF_DIR = REF_BASE / 'PQ_Attest/software'
CONFIG = ROOT / 'docs/decisions/dual_lane_config.json'
TILE_KEY_BYTES = 32  # K-1 system profile
REF_MODULES = ('keccak_ref', 'sha3_256_ref', 'kmac128_ref', 'measurement_ref',
               'attestation_ref', 'attestation_protocol')


class ReferenceIdentityError(RuntimeError):
    """The imported reference is not the pinned teammate reference."""


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_reference_hashes() -> dict:
    """Check every extracted member against dual_lane_config.json python_reference."""
    ref = json.loads(CONFIG.read_text(encoding='utf-8'))['python_reference']
    members = ref['members']
    if not members:
        raise ReferenceIdentityError('python_reference.members is empty')
    for name, expected in members.items():
        path = REF_BASE / name
        if not path.is_file():
            raise ReferenceIdentityError(f'missing reference member {name}')
        got = _sha(path)
        if got != expected:
            raise ReferenceIdentityError(f'reference hash mismatch {name}: {got} != {expected}')
    return dict(zip=ref['zip'], sha256=ref['sha256'], members=members)


def assert_inside_reference(modules) -> None:
    """Fail loudly unless every module __file__ resolves inside software/pq_attest_final/."""
    base = REF_BASE.resolve()
    for mod in modules:
        f = getattr(mod, '__file__', None)
        if f is None:
            raise ReferenceIdentityError(f'{mod.__name__} has no __file__')
        p = Path(f).resolve()
        if base not in p.parents:
            raise ReferenceIdentityError(
                f'reference module {mod.__name__} resolved to {p}, outside {base} '
                '(name collision with the repo software/ copy?)')
        rel = p.relative_to(base).as_posix()
        if rel not in REFERENCE['members']:
            raise ReferenceIdentityError(f'{mod.__name__} at {rel} is not a pinned member')


def _load_reference():
    import importlib
    sys.dont_write_bytecode = True  # never write __pycache__ under the immutable tree
    ref_dir = str(REF_DIR)
    if ref_dir in sys.path:
        sys.path.remove(ref_dir)
    sys.path.insert(0, ref_dir)
    mods = [importlib.import_module(n) for n in REF_MODULES]
    assert_inside_reference(mods)
    return mods


REFERENCE = verify_reference_hashes()
_keccak, _sha3, KMAC, MEAS, ATT, PROTO = _load_reference()
kmac128 = KMAC.kmac128
derive_tile_key = KMAC.derive_tile_key
measure_tile = MEAS.measure_tile
generate_attestation_tag = ATT.generate_attestation_tag
verify_attestation = ATT.verify_attestation
AttestationRequest = PROTO.AttestationRequest
AttestationResponse = PROTO.AttestationResponse
tile_respond = PROTO.tile_respond
verifier_check = PROTO.verifier_check


def validate_profile(tile: bytes, epoch: bytes, nonce: bytes, root: bytes,
                     context: bytes, config: bytes, imem: bytes) -> None:
    for name, v in (('tile', tile), ('epoch', epoch), ('nonce', nonce), ('root', root),
                    ('context', context), ('config', config), ('imem', imem)):
        if not isinstance(v, bytes):
            raise TypeError(f'{name} must be bytes')
    if (len(tile), len(epoch), len(nonce), len(root)) != (7, 10, 16, 32):
        raise ValueError('fixed field width (tile 7, epoch 10, nonce 16, root 32)')
    if len(context) > 14 or len(config) > 64 or len(imem) > 64:
        raise ValueError('length outside controller contract (context<=14, config/imem<=64)')


def compose(tile: bytes, epoch: bytes, nonce: bytes, root: bytes,
            context: bytes, config: bytes, imem: bytes) -> dict:
    validate_profile(tile, epoch, nonce, root, context, config, imem)
    key = derive_tile_key(root, tile, epoch, context, key_bytes=TILE_KEY_BYTES)
    meas = measure_tile(tile, config, imem)
    request = AttestationRequest(tile_id=tile, epoch=epoch, nonce=nonce)
    resp = tile_respond(key, request, meas)
    verdict = verifier_check(key, request, resp)
    if not verdict.accepted:
        raise AssertionError('teammate verifier rejected its own response: ' + verdict.reason)
    response = resp.tile_id + resp.epoch + resp.nonce + resp.measurement + resp.tag
    assert len(response) == 97
    assert int.from_bytes(response, 'little').to_bytes(97, 'little') == response
    return dict(key=key.hex(), measurement=meas.hex(), tag=resp.tag.hex(), response=response.hex())


def literal(path, name, size):
    text = path.read_text()
    found = re.findall(r'\b' + name + r"\s*=\s*\d+'h([0-9a-fA-F_]+)", text)
    if len(found) != 1:
        raise ValueError(f'expected one {name} in {path}')
    return int(found[0].replace('_', ''), 16).to_bytes(size, 'little')


# RTL testbench literal cases (pq_kdf_tb / pq_measurement_tb / pqattest_tb).
KDF_CASES = [(b'TILE_01', b'EPOCH_0001', b'PQ-ATTEST-KDF', 16),
             (b'TILE_02', b'EPOCH_0001', b'PQ-ATTEST-KDF', 16),
             (b'TILE_01', b'EPOCH_0002', b'PQ-ATTEST-KDF', 16),
             (b'TILE_01', b'EPOCH_0001', b'PQ-ATTEST-AUTH', 16),
             (b'TILE_01', b'EPOCH_0001', b'', 16),
             (b'TILE_01', b'EPOCH_0001', b'PQ-ATTEST-KDF', 32)]
_CM = bytes(range(16)); _IM = bytes(range(16, 32))
MEAS_CASES = [(b'TILE_01', _CM, _IM), (b'TILE_02', _CM, _IM),
              (b'TILE_01', b'\xff' + bytes(range(15)), _IM),
              (b'TILE_01', _CM, b'\xff' + bytes(range(17, 32))),
              (b'TILE_01', b'', b''), (b'TILE_01', bytes(range(64)), bytes(range(64, 128)))]


def tag_cases():
    key = bytes(range(32)); tile = b'TILE_01'; epoch = b'EPOCH_0001'; nonce = bytes(range(16))
    meas = measure_tile(tile, _CM, _IM)
    return [(key, tile, epoch, nonce, meas, 32, b'PQ-ATTEST-AUTH'),
            (key, b'UILE_01', epoch, nonce, meas, 32, b'PQ-ATTEST-AUTH'),
            (key, tile, b'EPOCH_0000', nonce, meas, 32, b'PQ-ATTEST-AUTH'),
            (key, tile, epoch, bytes(range(15)) + b'\x0e', meas, 32, b'PQ-ATTEST-AUTH'),
            (key, tile, epoch, nonce, b'\x94' + meas[1:], 32, b'PQ-ATTEST-AUTH'),
            (key[:31] + b'\x1e', tile, epoch, nonce, meas, 32, b'PQ-ATTEST-AUTH'),
            (key, tile, epoch, nonce, meas, 16, b'PQ-ATTEST-AUTH'),
            (key, tile, epoch, nonce, meas, 32, b'')]


def tag_value(k, t, e, n, m, length, custom):
    """Protocol tags via generate_attestation_tag; the two RTL KMAC-core parameter
    cases (L=16, empty customization) are not protocol tags and use the teammate kmac128."""
    if (length, custom) == (32, b'PQ-ATTEST-AUTH'):
        return generate_attestation_tag(k, t, e, n, m)
    return kmac128(k, t + e + n + m, length, custom)


def compatibility():
    # NIST SP 800-185 KMAC128 sample 1 (also the teammate's own __main__ KAT).
    nist = kmac128(bytes(range(0x40, 0x60)), bytes.fromhex('00010203'), 32, b'')
    assert nist.hex() == ('e5780b0d3ea6f7d3a429c5706aa43a00'
                          'fadbd7d49628839e3187243f456ee14e'), 'teammate KMAC128 NIST sample 1'
    tb = ROOT / 'NOC_PQATTEST.srcs/sim_1/new'
    for i, (t, e, c, n) in enumerate(KDF_CASES, 1):
        k = derive_tile_key(bytes(range(32)), t, e, c, key_bytes=n)
        assert literal(tb/'pq_kdf_tb.sv', f'V0{i}', 32) == k.ljust(32, b'\0'), f'KDF V0{i}'
    for i, (t, c, m) in enumerate(MEAS_CASES, 1):
        assert literal(tb/'pq_measurement_tb.sv', f'M0{i}', 32) == measure_tile(t, c, m), f'M0{i}'
    # Compare actual RTL literals, rather than a second hardcoded copy of them.
    for i, args in enumerate(tag_cases(), 1):
        got = tag_value(*args)
        name = 'V08_EMPTY_CUSTOM' if i == 8 else f'V0{i}'
        assert literal(tb/'pqattest_tb.sv', name, 32) == got.ljust(32, b'\0'), f'TAG V0{i}'
    for args in [(b'x'*8, b'e'*10, b'n'*16, b'k'*32, b'', b'', b''),
                 (b't'*7, b'e'*10, b'n'*16, b'k'*32, b'x'*15, b'', b''),
                 (b't'*7, b'e'*10, b'n'*16, b'k'*32, b'', b'c'*65, b'')]:
        try: compose(*args)
        except ValueError: pass
        else: raise AssertionError('invalid input accepted')
    print('COMPATIBILITY: Stage5=6 Stage6=6 Stage7=8; widths/round-trips/invalid inputs PASS')


def vectors():
    result = []
    for i, (cl, il, xl) in enumerate([(0,0,0),(64,64,14),(64,0,7),(0,64,1),
                                      (16,16,13),(33,17,5),(1,1,14),(64,64,0)]):
        pattern = lambda n, salt: bytes((j*37+i*19+salt) & 255 for j in range(n))
        v = dict(id=f'G{i:02}', tile=pattern(7,11).hex(), epoch=pattern(10,29).hex(),
                 nonce=pattern(16,47).hex(), root=pattern(32,61).hex(),
                 context=pattern(xl,73).hex(), config=pattern(cl,89).hex(), imem=pattern(il,101).hex())
        v.update(compose(*(bytes.fromhex(v[k]) for k in ['tile','epoch','nonce','root','context','config','imem'])))
        result.append(v)
    return {'schema': 1, 'oracle': 'teammate-reference-adapter',
            'reference_zip': REFERENCE['zip'], 'reference_sha256': REFERENCE['sha256'],
            'tile_key_bytes': TILE_KEY_BYTES,
            'provisioning': 'OFFLINE DEMO ONLY', 'vectors': result}


def sv_include(data):
    rows = ['// Generated by scripts/s8_golden.py (adapter over teammate reference '
            f"{data['reference_sha256'][:16]}); immutable specification vectors.",
            'task automatic load_vector(input int idx);', 'case (idx)']
    fields = [('tile_id','tile',56),('epoch','epoch',80),('nonce','nonce',128),
              ('root_secret','root',256),('context_in','context',112),
              ('config_data','config',512),('imem','imem',512),('expected','response',776)]
    for i, v in enumerate(data['vectors']):
        rows.append(f'{i}: begin')
        for sv, k, bits in fields:
            val = int.from_bytes(bytes.fromhex(v[k]), 'little')
            rows.append(f"  {sv} = {bits}'h{val:0{bits//4}x};")
        rows.extend([f"  context_len = {len(bytes.fromhex(v['context']))};",
                     f"  config_len = {len(bytes.fromhex(v['config']))};",
                     f"  imem_len = {len(bytes.fromhex(v['imem']))};", 'end'])
    rows += ['default: $fatal(1,"invalid golden vector index");', 'endcase', 'endtask', '']
    return '\n'.join(rows)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--write', action='store_true'); args = ap.parse_args()
    compatibility(); data = vectors()
    outputs = {ROOT/'vectors/s8_golden.json': json.dumps(data, indent=2)+'\n',
               ROOT/'vectors/s8_golden.svh': sv_include(data)}
    for p, content in outputs.items():
        if args.write:
            p.parent.mkdir(parents=True, exist_ok=True); p.write_text(content, encoding='utf-8', newline='\n')
        else:
            assert p.read_text(encoding='utf-8') == content, f'stale vector artifact {p}'
    print(f'TILE_KEY_BYTES={TILE_KEY_BYTES} PYTHON_REFERENCE_SHA256={REFERENCE["sha256"]}')
    print('ORACLE: PASS (8 full 776-bit teammate-reference adapter vectors)')


if __name__ == '__main__': main()
