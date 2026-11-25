"""Full-chain vectors: thin adapter over the pinned teammate reference (via s8_golden).

Attestation rows use s8_golden.compose (teammate derive_tile_key/measure_tile/tile_respond,
TILE_KEY_BYTES=32). The 36 directed L2 demo keys use the teammate kmac128 primitive unchanged.
OFFLINE DEMO ONLY.
"""
import json
import sys
from s8_golden import ROOT, REFERENCE, compose, kmac128


def produce():
    rows = []
    for i in range(3):
        row = dict(tile=b'TILE_03', epoch=b'EPOCH_0001', nonce=bytes((j+i*17) & 255 for j in range(16)),
                   root=bytes(range(32)), context=b'PQ-ATTEST-KDF', config=bytes(range(16)), imem=bytes(range(16, 32)))
        row.update({k: bytes.fromhex(v) for k, v in compose(*(row[k] for k in ['tile','epoch','nonce','root','context','config','imem'])).items()})
        rows.append(row)
    boot = b'BOOT_00001'
    keys = b''.join(kmac128(bytes(range(32)), bytes([src, dst])+boot, 32, b'NOC-L2-KEY-v1') for src in range(6) for dst in range(6))
    lines = [f"// OFFLINE DEMO ONLY. Teammate-reference adapter expected values ({REFERENCE['sha256'][:16]}).",
             "task automatic load_chain(input int idx);", 'case(idx)']
    for i, row in enumerate(rows):
        lines.append(f'{i}: begin')
        for sv, key, bits in [('root_secret','root',256),('attest_epoch','epoch',80),('nonce','nonce',128),('context_in','context',112),('config_data','config',512),('imem','imem',512),('approved_measurement','measurement',256),('expected_response','response',776)]:
            val = int.from_bytes(row[key], 'little'); lines.append(f"{sv}={bits}'h{val:0{bits//4}x};")
        lines += ['context_len=13;config_len=16;imem_len=16;', 'end']
    lines += ['default: $fatal(1,"invalid chain vector");', 'endcase', 'endtask',
              f"localparam logic [79:0] BOOT=80'h{int.from_bytes(boot,'little'):020x};",
              f"localparam logic [9215:0] KEYS=9216'h{int.from_bytes(keys,'little'):02304x};", '']
    data = {'provisioning': 'OFFLINE DEMO ONLY', 'oracle': 'teammate-reference-adapter',
            'reference_sha256': REFERENCE['sha256'], 'tile_key_bytes': 32,
            'vectors': [{k: v.hex() for k, v in r.items()} for r in rows],
            'boot': boot.hex(), 'directed_keys': keys.hex()}
    return data, '\n'.join(lines)


if __name__ == '__main__':
    data, sv = produce()
    for p, s in [(ROOT/'vectors/full_chain.json', json.dumps(data, indent=2)+'\n'), (ROOT/'vectors/full_chain.svh', sv)]:
        if '--write' in sys.argv: p.write_text(s, encoding='utf-8', newline='\n')
        else: assert p.read_text(encoding='utf-8') == s, 'stale full-chain vectors'
    print('FULL_CHAIN_ORACLE: PASS (3 transactions; 36 directed demo keys; teammate reference)')
