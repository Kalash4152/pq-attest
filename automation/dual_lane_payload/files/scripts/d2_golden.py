"""D2 (I9-D2) vectors: K-3 profile config 16 / IMEM 64 bytes, from the pinned teammate reference (via s8_golden).

Same adapter as full_chain_golden.py (teammate derive_tile_key / measure_tile / tile_respond / verifier_check,
TILE_KEY_BYTES = 32); only the IMEM window changes from 16 to 64 bytes. Each measurement is also cross-checked with
hashlib SHA3-256 over TILE_ID || CONFIG || IMEM (87 bytes, inside the single-block bound of 135).
New files only (vectors/d2_k3_64.*); no existing reference vector is touched. OFFLINE DEMO ONLY.
"""
import hashlib
import json
import sys
from s8_golden import ROOT, REFERENCE, compose

IMEM_LEN = 64
CONFIG_LEN = 16


def produce():
    rows = []
    for i in range(3):
        row = dict(tile=b'TILE_03', epoch=b'EPOCH_0001', nonce=bytes((j + i * 17) & 255 for j in range(16)),
                   root=bytes(range(32)), context=b'PQ-ATTEST-KDF', config=bytes(range(CONFIG_LEN)),
                   imem=bytes((16 + j + i * 64) & 255 for j in range(IMEM_LEN)))
        row.update({k: bytes.fromhex(v) for k, v in
                    compose(*(row[k] for k in ['tile', 'epoch', 'nonce', 'root', 'context', 'config', 'imem'])).items()})
        msg = row['tile'] + row['config'] + row['imem']
        assert len(msg) == 87 and len(msg) <= 135
        assert hashlib.sha3_256(msg).digest() == row['measurement'], 'teammate measure_tile != hashlib SHA3-256'
        rows.append(row)
    # Negative row: the same IMEM truncated to the old 16-byte window must give a different measurement.
    short = compose(rows[0]['tile'], rows[0]['epoch'], rows[0]['nonce'], rows[0]['root'], rows[0]['context'],
                    rows[0]['config'], rows[0]['imem'][:16])
    assert bytes.fromhex(short['measurement']) != rows[0]['measurement']
    lines = [f"// OFFLINE DEMO ONLY. D2 K-3 64-byte IMEM vectors, teammate-reference adapter ({REFERENCE['sha256'][:16]}).",
             "task automatic load_d2(input int idx);", 'case(idx)']
    for i, row in enumerate(rows):
        lines.append(f'{i}: begin')
        for sv, key, bits in [('root_secret', 'root', 256), ('attest_epoch', 'epoch', 80), ('nonce', 'nonce', 128),
                              ('context_in', 'context', 112), ('config_data', 'config', 512), ('imem', 'imem', 512),
                              ('approved_measurement', 'measurement', 256), ('expected_response', 'response', 776)]:
            val = int.from_bytes(row[key], 'little')
            lines.append(f"{sv}={bits}'h{val:0{bits // 4}x};")
        lines += [f'context_len=13;config_len={CONFIG_LEN};imem_len={IMEM_LEN};', 'end']
    lines += ['default: $fatal(1,"invalid d2 vector");', 'endcase', 'endtask',
              f"localparam logic [255:0] D2_MEAS_IMEM16_ROW0=256'h{int.from_bytes(bytes.fromhex(short['measurement']), 'little'):064x};",
              '']
    data = {'provisioning': 'OFFLINE DEMO ONLY', 'oracle': 'teammate-reference-adapter',
            'reference_sha256': REFERENCE['sha256'], 'tile_key_bytes': 32,
            'k3_profile': {'config_len': CONFIG_LEN, 'imem_len': IMEM_LEN}, 'cross_check': 'hashlib.sha3_256',
            'vectors': [{k: v.hex() for k, v in r.items()} for r in rows],
            'row0_imem16_measurement': short['measurement']}
    return data, '\n'.join(lines)


if __name__ == '__main__':
    data, sv = produce()
    for p, s in [(ROOT / 'vectors/d2_k3_64.json', json.dumps(data, indent=2) + '\n'), (ROOT / 'vectors/d2_k3_64.svh', sv)]:
        if '--write' in sys.argv:
            p.write_text(s, encoding='utf-8', newline='\n')
        else:
            assert p.read_text(encoding='utf-8') == s, 'stale D2 vectors'
    print('D2_ORACLE: PASS (3 transactions; config 16 / IMEM 64; teammate reference + hashlib cross-check)')
