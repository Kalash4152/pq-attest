"""Step c engine vectors (tb_l2_kmac_engine), contract sec. 5 (Q4): real P7 transcripts and tags from scripts/l2_golden.py
(packet(): R6.6 transcript, kmac128 of the pinned teammate ZIP via s8_golden; directed keys of the frozen chain), both
directions:
  r0 = tile-4 TX and r1 = tile-3 RX verify : 4 -> 3, CHALLENGE (52 B) / GRANT / REVOKE (24 B), K[4->3]
  r2 = tile-3 TX and r3 = tile-4 RX verify : 3 -> 4, RESPONSE (88 B), K[3->4]
Random control, sequence (non-zero), boot epoch and payload; the 22 words past the transcript length are random (they
must be masked by msg_len). Expected tags come only from Python.
Files: sim/dual_lane/l2engine/l2e_keys.mem (K43, K34 as 64 hex digits each)
       sim/dual_lane/l2engine/l2e_vec.mem  (4 * N_VEC lines, requester-major: {tag[127:0], len[7:0], word21 .. word0})
Usage: gen_l2e_vectors.py [--check]."""
import random, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import l2_golden as L

ROOT = Path(__file__).resolve().parents[1]; OUT = ROOT / 'sim/dual_lane/l2engine'
SEED, N_VEC = 0x12E0_0C, 1000

def build():
    rng = random.Random(SEED)
    keys = bytes.fromhex(L.produce()[0]['directed_keys'])
    k43 = keys[(4*6+3)*32:(4*6+4)*32]; k34 = keys[(3*6+4)*32:(3*6+5)*32]
    klines = [int.from_bytes(k, 'little').to_bytes(32, 'big').hex() for k in (k43, k34)]
    vlines = []
    for r in range(4):
        src, dst, key = (4, 3, k43) if r < 2 else (3, 4, k34)
        for _ in range(N_VEC):
            msg = rng.choice([4, 6, 7]) if r < 2 else 5
            pn = {4: 7, 5: 16, 6: 0, 7: 0}[msg]
            pkt = L.packet(src, dst, msg, rng.getrandbits(11), rng.getrandbits(63) + 1, bytes(rng.getrandbits(8) for _ in range(10)),
                           [rng.getrandbits(32) for _ in range(pn)], key=key)
            tr = bytes.fromhex(pkt['transcript']); n = len(tr)
            assert n == 24 + 4 * pn
            pad = tr + bytes(rng.getrandbits(8) for _ in range(88 - n))
            words = [int.from_bytes(pad[4*i:4*i+4], 'little') for i in range(22)]
            tag = int.from_bytes(bytes.fromhex(pkt['tag']), 'little')
            v = (tag << (8 + 704)) | (n << 704) | sum(w << (32 * i) for i, w in enumerate(words))
            vlines.append(f'{v:0210x}')
    return '\n'.join(klines) + '\n', '\n'.join(vlines) + '\n'

def main():
    k, v = build()
    if '--check' in sys.argv:
        ok = (OUT / 'l2e_keys.mem').read_text() == k and (OUT / 'l2e_vec.mem').read_text() == v
        print('L2E_VECTORS_CHECK: ' + ('PASS' if ok else 'FAIL') + f' ({4 * N_VEC} P7 transcripts via l2_golden.packet, ZIP kmac128)')
        sys.exit(0 if ok else 1)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'l2e_keys.mem').write_text(k, newline='\n'); (OUT / 'l2e_vec.mem').write_text(v, newline='\n')
    print('wrote', 4 * N_VEC, 'vectors')

if __name__ == '__main__': main()
