"""Merged-SoC demo provisioning (NOT evidence): approved measurement for CPU A's real first 64 IMEM bytes.

The measurement covers TILE_ID || CONFIG (16) || IMEM (64) (I9-D2). With the real cpu_tile_noc, the IMEM bytes are the
first 64 bytes of the firmware at MEAS_BASE, so APPROVED_MEAS in synth/merged/pq_merged_board_top.sv must be recomputed
from the firmware image. Uses the pinned teammate reference through s8_golden.compose (same adapter as vectors/d2_k3_64),
and cross-checks the measurement with hashlib SHA3-256.

  python scripts/merged_provision.py --words fw_imem.hex      # $readmemh-style: one 32-bit word per line, word 0 first
  python scripts/merged_provision.py --bytes <128 hex chars>  # byte 0 first
  python scripts/merged_provision.py --self-check             # stub image: must reproduce vectors/d2_k3_64 row 0
Prints SV localparams (CPU_A_IMAGE, APPROVED_MEAS, EXPECTED_RESPONSE) packed byte i at [i*8 +: 8].
"""
import argparse
import hashlib
import json
import sys
from s8_golden import ROOT, compose

TILE, EPOCH, CONTEXT = b'TILE_03', b'EPOCH_0001', b'PQ-ATTEST-KDF'
NONCE, ROOT_SECRET, CONFIG = bytes(range(16)), bytes(range(32)), bytes(range(16))


def from_words(path):
    words = [l.split('//')[0].strip() for l in open(path, encoding='utf-8')]
    words = [w for w in words if w and not w.startswith('@')][:16]
    if len(words) != 16:
        raise SystemExit('need at least 16 words in ' + path)
    return b''.join(int(w, 16).to_bytes(4, 'little') for w in words)   # RV32 little-endian words


def sv(name, bits, b):
    return f"localparam logic [{bits - 1}:0] {name} = {bits}'h{int.from_bytes(b, 'little'):0{bits // 4}x};"


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--words'); g.add_argument('--bytes'); g.add_argument('--self-check', action='store_true')
    a = ap.parse_args()
    if a.self_check:
        imem = bytes((16 + j) & 255 for j in range(64))
    elif a.words:
        imem = from_words(a.words)
    else:
        imem = bytes.fromhex(a.bytes)
    if len(imem) != 64:
        raise SystemExit('IMEM window must be exactly 64 bytes (K3_IMEM_LEN = 64)')
    r = {k: bytes.fromhex(v) for k, v in compose(TILE, EPOCH, NONCE, ROOT_SECRET, CONTEXT, CONFIG, imem).items()}
    assert hashlib.sha3_256(TILE + CONFIG + imem).digest() == r['measurement'], 'reference != hashlib'
    if a.self_check:
        row = json.loads((ROOT / 'vectors/d2_k3_64.json').read_text())['vectors'][0]
        assert row['imem'] == imem.hex() and row['measurement'] == r['measurement'].hex() and row['response'] == r['response'].hex()
        print('// SELF-CHECK: PASS (reproduces vectors/d2_k3_64 row 0)')
    print(sv('CPU_A_IMAGE', 512, imem))
    print(sv('APPROVED_MEAS', 256, r['measurement']))
    print(sv('EXPECTED_RESPONSE', 776, r['response']))
    return 0


if __name__ == '__main__':
    sys.exit(main())
