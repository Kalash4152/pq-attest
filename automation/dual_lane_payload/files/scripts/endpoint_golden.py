"""PQ-2 endpoint golden values: THIN ADAPTER over scripts/s8_golden.py (teammate reference).

Every cryptographic value comes from s8_golden.compose(), i.e. the pinned teammate
derive_tile_key / measure_tile / tile_respond / verifier_check (TILE_KEY_BYTES=32, K-1).
This file only
  * packs the Q-C challenge (7 words, epoch 0-79, nonce 80-207, padding 208-223 = 0, R6.1),
  * slices the R-B response (16 words = internal bytes 33..96, word k little-endian, R6.2),
  * declares the K-2 endpoint error-case table (expected status per stimulus, R6.3),
  * cross-checks the TILE_03 rows against vectors/full_chain.json (same adapter).
Usage: python scripts/endpoint_golden.py          (check committed vectors; exit != 0 on mismatch)
       python scripts/endpoint_golden.py --write  (regenerate vectors/endpoint_golden.json/.svh)
OFFLINE DEMO ONLY.
"""
from __future__ import annotations
import argparse
import json
import sys
from s8_golden import ROOT, REFERENCE, TILE_KEY_BYTES, compose

TILE = b'TILE_03'
FC_ROOT = bytes(range(32)); FC_CONTEXT = b'PQ-ATTEST-KDF'
FC_CONFIG = bytes(range(16)); FC_IMEM = bytes(range(16, 32))

ST_SUCCESS, ST_REJECT, ST_BUSY, ST_MALFORMED, ST_INTERNAL, ST_NONE = 1, 2, 3, 5, 10, 0
ENDPOINT_CODES = (ST_SUCCESS, ST_REJECT, ST_BUSY, ST_MALFORMED, ST_INTERNAL)


def pattern(n: int, salt: int) -> bytes:
    return bytes((j * 41 + salt) & 255 for j in range(n))


def rows():
    """(id, epoch, nonce, root, context, config, imem). V00..V02 equal full_chain rows 0..2."""
    r = []
    for i in range(3):
        r.append((f'V{i:02}', b'EPOCH_0001', bytes((j + i * 17) & 255 for j in range(16)),
                  FC_ROOT, FC_CONTEXT, FC_CONFIG, FC_IMEM))
    r.append(('V03', b'\xff' * 10, b'\xff' * 16, FC_ROOT, FC_CONTEXT, FC_CONFIG, FC_IMEM))
    r.append(('V04', pattern(10, 3), pattern(16, 5), pattern(32, 7), b'', pattern(64, 11), pattern(64, 13)))
    r.append(('V05', pattern(10, 17), pattern(16, 19), pattern(32, 23), pattern(14, 29), b'', b''))
    return r


def challenge_words(epoch: bytes, nonce: bytes, pad: int = 0):
    c = int.from_bytes(epoch, 'little') | (int.from_bytes(nonce, 'little') << 80) | (pad << 208)
    return [(c >> (32 * k)) & 0xffffffff for k in range(7)]


def rb_words(response: bytes):
    body = response[33:97]
    assert len(body) == 64
    return [int.from_bytes(body[4 * k:4 * k + 4], 'little') for k in range(16)]


# K-2 endpoint error-case table (design contract of rtl/dual_lane/pq_attest_endpoint.sv).
# status 0 = no reply. counted = rejected_count +1. start = controller_start occurs.
ERROR_CASES = [
    ('SHORT6',      'RoT challenge, correct length, 6 payload words',            ST_MALFORMED, True,  False),
    ('LONG8',       'RoT challenge, correct length, 8 payload words',            ST_MALFORMED, True,  False),
    ('LEN_PLUS1',   'RoT challenge, HEAD length message_length+1, 7 words',      ST_MALFORMED, True,  False),
    ('LEN_MINUS1',  'RoT challenge, HEAD length message_length-1, 7 words',      ST_MALFORMED, True,  False),
    ('ZERO_WORDS',  'RoT challenge HEAD_TAIL, no payload',                       ST_MALFORMED, True,  False),
    ('PAD_BIT223',  'RoT challenge, padding bit 223 set',                        ST_MALFORMED, True,  False),
    ('PAD_BIT208',  'RoT challenge, padding bit 208 set',                        ST_MALFORMED, True,  False),
    ('ABORT',       'RoT challenge aborted after k = 0..6 words',                ST_MALFORMED, True,  False),
    ('ISSUER',      'challenge from SPOOF / CPU0 / CRYPTO (any content)',        ST_NONE,      True,  False),
    ('TYPE',        'ATTEST_RESPONSE or reserved msg_type 9 from RoT',           ST_NONE,      True,  False),
    ('IGNORED',     'ATTEST_GRANT / ATTEST_REVOKE / MEM_* responses',            ST_NONE,      False, False),
    ('BUSY',        'RoT challenge while a transaction is in progress',          ST_BUSY,      True,  False),
    ('BUSY_EXTRA',  'second busy challenge while a busy reply is queued',        ST_NONE,      True,  False),
    ('BUSY_ABORT',  'busy RoT challenge that is aborted',                        ST_NONE,      True,  False),
    ('REJECT_CTX',  'valid challenge, provisioned context_len = 15 (code 1)',    ST_REJECT,    False, True),
    ('REJECT_LEN',  'valid challenge, config_len or imem_len = 65 (code 2)',     ST_REJECT,    False, True),
    ('INTERNAL',    'valid challenge, controller err with error_code 0',         ST_INTERNAL,  False, True),
]


def full_chain_fresh():
    """The system bench includes vectors/full_chain.svh: confirm both committed full-chain
    artifacts equal what scripts/full_chain_golden.py (same adapter) produces now."""
    import full_chain_golden
    fdata, fsvh = full_chain_golden.produce()
    assert (ROOT / 'vectors/full_chain.json').read_text(encoding='utf-8') == json.dumps(fdata, indent=2) + '\n', \
        'stale vectors/full_chain.json'
    assert (ROOT / 'vectors/full_chain.svh').read_text(encoding='utf-8') == fsvh, 'stale vectors/full_chain.svh'
    return fdata


def produce():
    fc = full_chain_fresh()
    vec = []
    for vid, epoch, nonce, root, context, config, imem in rows():
        g = compose(TILE, epoch, nonce, root, context, config, imem)
        response = bytes.fromhex(g['response'])
        words = rb_words(response)
        ch = challenge_words(epoch, nonce)
        nonce_int = int.from_bytes(nonce, 'little')
        c = sum(w << (32 * k) for k, w in enumerate(ch))
        # Mutant observability preconditions (reports/i3_q2/Q2_COUNT_DERIVATION.md):
        assert words[8:] != words[8:][::-1], f'{vid}: tag words palindromic (tag-swap mutant would survive)'
        assert ((c >> 88) & ((1 << 128) - 1)) != nonce_int, f'{vid}: nonce offset mutant would survive'
        assert (c >> 208) == 0
        vec.append(dict(id=vid, tile=TILE.hex(), epoch=epoch.hex(), nonce=nonce.hex(), root=root.hex(),
                        context=context.hex(), config=config.hex(), imem=imem.hex(),
                        challenge_words=[f'{w:08x}' for w in ch], response=g['response'],
                        measurement=g['measurement'], tag=g['tag'],
                        rb_words=[f'{w:08x}' for w in words], status=ST_SUCCESS))
    for i in range(3):
        assert vec[i]['response'] == fc['vectors'][i]['response'], f'V{i:02} != full_chain row {i}'
    assert len({v['response'] for v in vec}) == len(vec), 'vectors not distinct'
    errors = [dict(id=i, stimulus=s, expected_status=st, reply=st != ST_NONE, counted=cnt,
                   starts_crypto=start, payload_words=['00000000'] * 16 if st != ST_NONE else [])
              for i, s, st, cnt, start in ERROR_CASES]
    assert all(e['expected_status'] in ENDPOINT_CODES + (ST_NONE,) for e in errors)
    data = {'schema': 1, 'oracle': 'teammate-reference-adapter (via s8_golden)',
            'reference_zip': REFERENCE['zip'], 'reference_sha256': REFERENCE['sha256'],
            'tile_key_bytes': TILE_KEY_BYTES, 'tile': 'TILE_03', 'provisioning': 'OFFLINE DEMO ONLY',
            'status_codes': {'success': 1, 'reject': 2, 'busy': 3, 'malformed': 5, 'internal': 10},
            'vectors': vec, 'error_cases': errors}
    return data, sv_include(data)


def sv_include(data):
    out = ['// Generated by scripts/endpoint_golden.py (adapter over s8_golden / teammate reference '
           f"{data['reference_sha256'][:16]}); TILE_KEY_BYTES={data['tile_key_bytes']}. OFFLINE DEMO ONLY.",
           f"localparam int EP_VECTORS = {len(data['vectors'])};"]
    for name, code in data['status_codes'].items():
        out.append(f'localparam logic [3:0] EP_ST_{name.upper()} = 4\'d{code};')
    for e in data['error_cases']:
        out.append(f"localparam logic [3:0] EP_EXP_{e['id']} = 4'd{e['expected_status']}; // {e['stimulus']}")
    out += ['task automatic ep_provision(input int idx);', 'case (idx)']
    for i, v in enumerate(data['vectors']):
        out.append(f'{i}: begin')
        for sv, k, bits in [('root_secret', 'root', 256), ('context_in', 'context', 112),
                            ('config_data', 'config', 512), ('imem', 'imem', 512)]:
            out.append(f"  {sv} = {bits}'h{int.from_bytes(bytes.fromhex(v[k]), 'little'):0{bits // 4}x};")
        out.append(f"  context_len = {len(bytes.fromhex(v['context']))}; "
                   f"config_len = {len(bytes.fromhex(v['config']))}; imem_len = {len(bytes.fromhex(v['imem']))};")
        out.append('end')
    out += ['default: ;', 'endcase', 'endtask']
    for fn, bits, get in [('ep_epoch', 80, lambda v: int.from_bytes(bytes.fromhex(v['epoch']), 'little')),
                          ('ep_nonce', 128, lambda v: int.from_bytes(bytes.fromhex(v['nonce']), 'little')),
                          ('ep_payload', 512, lambda v: sum(int(w, 16) << (32 * k) for k, w in enumerate(v['rb_words']))),
                          ('ep_internal', 776, lambda v: int.from_bytes(bytes.fromhex(v['response']), 'little'))]:
        out += [f'function automatic logic [{bits - 1}:0] {fn}(input int idx);', 'case (idx)']
        out += [f"{i}: return {bits}'h{get(v):0{bits // 4}x};" for i, v in enumerate(data['vectors'])]
        out += [f"default: return {bits}'h0;", 'endcase', 'endfunction']
    return '\n'.join(out) + '\n'


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--write', action='store_true'); a = ap.parse_args()
    data, svh = produce()
    outputs = {ROOT / 'vectors/endpoint_golden.json': json.dumps(data, indent=2) + '\n',
               ROOT / 'vectors/endpoint_golden.svh': svh}
    for p, content in outputs.items():
        if a.write:
            p.write_text(content, encoding='utf-8', newline='\n')
        elif not p.is_file() or p.read_text(encoding='utf-8') != content:
            print(f'ENDPOINT_ORACLE: FAIL (stale or missing {p.name})'); return 1
    print(f'TILE_KEY_BYTES={TILE_KEY_BYTES} PYTHON_REFERENCE_SHA256={REFERENCE["sha256"]}')
    print(f'ENDPOINT_ORACLE: PASS ({len(data["vectors"])} R-B vectors; {len(data["error_cases"])} K-2 error cases; '
          'V00-V02 == full_chain rows 0-2; full_chain.json/.svh fresh)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
