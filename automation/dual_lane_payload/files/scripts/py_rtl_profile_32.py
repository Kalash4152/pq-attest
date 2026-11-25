"""V8 job py_rtl_profile_32: the 32-byte RTL system profile (K-1, TILE_KEY_BYTES=32).

Recomputes every vector in vectors/s8_golden.json from its stored inputs with a fresh
teammate-reference adapter call (s8_golden.compose) and compares key, measurement, tag and the
97-byte response; also checks the stored profile metadata. Never uses the 16-byte examples.
"""
import json
import sys

from s8_golden import ROOT, REFERENCE, TILE_KEY_BYTES, compose

FIELDS = ('key', 'measurement', 'tag', 'response')
INPUTS = ('tile', 'epoch', 'nonce', 'root', 'context', 'config', 'imem')


def main():
    data = json.loads((ROOT / 'vectors/s8_golden.json').read_text(encoding='utf-8'))
    fails = []
    n = 0
    meta = {'oracle': 'teammate-reference-adapter', 'reference_sha256': REFERENCE['sha256'],
            'tile_key_bytes': 32}
    for k, v in meta.items():
        n += 1
        if data.get(k) != v:
            fails.append(f'metadata {k}={data.get(k)!r} expected {v!r}')
    if TILE_KEY_BYTES != 32:
        fails.append('adapter TILE_KEY_BYTES is not 32')
    vecs = data['vectors']
    if [v['id'] for v in vecs] != [f'G{i:02}' for i in range(8)]:
        fails.append('vector id set changed')
    for v in vecs:
        fresh = compose(*(bytes.fromhex(v[k]) for k in INPUTS))
        if len(bytes.fromhex(fresh['key'])) != 32:
            fails.append(f"{v['id']} key length")
        for f in FIELDS:
            n += 1
            if fresh[f] != v[f]:
                fails.append(f"{v['id']} {f}: stored {v[f]} fresh {fresh[f]}")
    for line in fails:
        print('FAIL', line)
    print(f'PROFILE=rtl_system TILE_KEY_BYTES={TILE_KEY_BYTES} vectors={len(vecs)}')
    if fails:
        print(f'PY_RTL_PROFILE_32: FAIL n={len(fails)}/{n}')
        sys.exit(1)
    print(f'PY_RTL_PROFILE_32: PASS n={n}')


if __name__ == '__main__':
    main()
