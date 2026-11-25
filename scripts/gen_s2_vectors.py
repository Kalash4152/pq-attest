"""S2 / I-5 attack vectors (contract sec. 8; docs/decisions/S2_MATRIX_PLAN.md) for tb_s2_attacks on noc_l2_p7_pair, tile 3
(CRYPTO, peer 4). Every packet and tag comes from scripts/l2_golden.py (packet(): R6.6 transcript, the pinned teammate
kmac128 via s8_golden; directed keys of the frozen chain). Each vector carries its expected L2 verdict (0 = accepted, else
reject reason) and the expected tile-3 authorization after it, derived here from the rule table below.

Rows (in stream order; the RX sequence state advances only on accepted packets):
  Z  seq 0 at reset                                   -> 4
  SETUP genuine GRANT seq 1, REVOKE seq 2              -> 0 (auth 1, then 0)
  M  tag bit / epoch bit / payload bit flipped, wrong key (K[5->3])          -> 2
  B  REVOKE retyped to GRANT after signing; GRANT whose control is signed unbound (control 0, wire 0x080) -> 2
  I  GRANT claiming src 5 / 0 (MAC valid under K[4->3]); src 2 under its own key K[2->3]                -> 5
  S  GRANT addressed to tile 0 / on VC 0 (both validly signed, field in the transcript)                  -> 1
  R  genuine GRANT seq 3, REVOKE seq 4, then the GRANT replayed; an old GRANT seq 2                       -> 0, 0, 4, 4
  E  GRANT seq 5 under the previous boot epoch                                                            -> 3
  L  GRANT length 11 (11 flits, MAC valid over the header); GRANT length 9 (9 flits)                     -> 1, 1
  W  genuine CHALLENGE seq 6, GRANT seq 7; REVOKE seq 2^64-1; GRANT seq 1 after the maximum (no wrap)    -> 0, 0, 0, 4
Files: sim/dual_lane/s2/s2_keys.mem (K43, K34, boot epoch), s2_vec.mem (27 lines per vector: meta, 26 flits),
       s2_meta.json (vector count and per-row names), s2_names.svh (S2_NV, check name per vector). Usage: gen_s2_vectors.py [--write] (default: check mode)."""
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import l2_golden as L

ROOT = Path(__file__).resolve().parents[1]; OUT = ROOT / 'sim/dual_lane/s2'
CH, RESP, GRANT, REVOKE = 4, 5, 6, 7
CTL = {CH: 0, RESP: 0, GRANT: 0x080, REVOKE: 0}
BOOT, OLD_BOOT = L.BOOT_B, b'BOOT_00001'
MAX64 = (1 << 64) - 1
ROWS = ['Z', 'SETUP', 'M', 'B', 'I', 'S', 'R', 'E', 'L', 'W']


def tagged(head, vc, boot, seq, payload, key):
    """Flits with an explicit head word (length field as given), MAC over the R6.6 transcript of that head."""
    tr = head.to_bytes(4, 'little') + bytes([vc, 1]) + boot + seq.to_bytes(8, 'little') + b''.join(x.to_bytes(4, 'little') for x in payload)
    tag = L.kmac128(key, tr, 16, b'NOC-L2-AUTH-v1')
    fresh = seq.to_bytes(8, 'little') + boot + b'\0\0'
    return [head] + [int.from_bytes(fresh[i:i + 4], 'little') for i in range(0, 20, 4)] + list(payload) + \
           [int.from_bytes(tag[i:i + 4], 'little') for i in range(0, 16, 4)]


def flits_of(words, vc):
    n = len(words)
    return [L.mk(w, 0 if i == 0 else 2 if i == n - 1 else 1, vc) for i, w in enumerate(words)]


def head_word(src, dst, msg, n, ctl):
    return ((dst % 3) << 29) | ((dst // 3) << 26) | ((src % 3) << 23) | ((src // 3) << 20) | (msg << 16) | (n << 11) | ctl


def build():
    keys = bytes.fromhex(L.produce()[0]['directed_keys'])
    K = lambda s, d: L.key_of(keys, s, d)
    k43, k34 = K(4, 3), K(3, 4)
    pk = lambda msg, seq, boot=BOOT, key=k43, src=4, dst=3, ctl=None, payload=None, vc=None: L.packet(
        src, dst, msg, CTL[msg] if ctl is None else ctl, seq, boot, [0x5A5A0000 + i for i in range(L.NPAY[msg])] if payload is None else payload,
        vc=vc, key=key)['flits']
    V = []                                   # (row, name, flits, expected reason, expected authorized after)
    auth = 0
    def add(row, name, flits, reason):
        nonlocal auth
        if reason == 0:                      # the gate: GRANT from the RoT with control[10:7] = 1 authorizes, REVOKE clears
            h = L.head_fields(L.fdata(flits[0]))
            auth = 1 if h['msg'] == GRANT and (h['ctl'] >> 7) & 15 == 1 else 0 if h['msg'] == REVOKE else auth
        V.append((row, name, flits, reason, auth))
    add('Z', 'SEQ0', pk(GRANT, 0), 4)
    add('SETUP', 'GRANT1', pk(GRANT, 1), 0)
    add('SETUP', 'REVOKE2', pk(REVOKE, 2), 0)
    add('M', 'TAG_BIT', L.flip(pk(GRANT, 3), 9, 5), 2)
    add('M', 'EPOCH_BIT', L.flip(pk(GRANT, 3), 3, 0), 2)
    add('M', 'WRONG_KEY', pk(GRANT, 3, key=K(5, 3)), 2)
    add('M', 'PAYLOAD_BIT', L.flip(pk(CH, 3), 6, 7), 2)
    add('B', 'REVOKE_AS_GRANT', L.set_head(pk(REVOKE, 3), msg=GRANT), 2)
    add('B', 'CTL_UNBOUND', L.set_head(pk(GRANT, 3, ctl=0), ctl=0x080), 2)
    add('I', 'SRC5_K43', pk(GRANT, 3, src=5), 5)
    add('I', 'SRC0_K43', pk(GRANT, 3, src=0), 5)
    add('I', 'SRC2_OWNKEY', pk(GRANT, 3, src=2, key=K(2, 3)), 5)
    add('S', 'DEST0', pk(GRANT, 3, dst=0), 1)
    add('S', 'VC0', pk(GRANT, 3, vc=0), 1)
    g3 = pk(GRANT, 3)
    add('R', 'GRANT3', g3, 0)
    add('R', 'REVOKE4', pk(REVOKE, 4), 0)
    add('R', 'REPLAY_GRANT3', list(g3), 4)
    add('R', 'OLD_GRANT2', pk(GRANT, 2), 4)
    add('E', 'OLD_EPOCH', pk(GRANT, 5, boot=OLD_BOOT), 3)
    add('L', 'LONG11', flits_of(tagged(head_word(4, 3, GRANT, 11, 0x080), 2, BOOT, 5, [], k43)[:6] + [0x0BAD0011] +
                                tagged(head_word(4, 3, GRANT, 11, 0x080), 2, BOOT, 5, [], k43)[6:], 2), 1)
    add('L', 'SHORT9', flits_of(tagged(head_word(4, 3, GRANT, 9, 0x080), 2, BOOT, 5, [], k43)[:9], 2), 1)
    add('W', 'CHALLENGE6', pk(CH, 6), 0)
    add('W', 'GRANT7', pk(GRANT, 7), 0)
    add('W', 'REVOKE_MAX', pk(REVOKE, MAX64), 0)
    add('W', 'GRANT1_AFTER_MAX', pk(GRANT, 1), 4)
    klines = [int.from_bytes(k, 'little').to_bytes(32, 'big').hex() for k in (k43, k34)] + [int.from_bytes(BOOT, 'little').to_bytes(10, 'big').hex()]
    vlines = []
    for idx, (row, name, fl, reason, a) in enumerate(V):
        assert 1 <= len(fl) <= 26
        meta = (a << 34) | (reason << 30) | (len(fl) << 25) | (ROWS.index(row) << 17) | idx
        vlines.append(f'{meta:09x}')
        vlines += [f'{f:09x}' for f in fl] + ['000000000'] * (26 - len(fl))
    meta = dict(vectors=len(V), names=[f'{r}_{n}' for r, n, *_ in V], rows=ROWS,
                expected=[dict(name=f'{r}_{n}', reason=x, auth=a) for r, n, _, x, a in V])
    return klines, vlines, meta


def main():
    klines, vlines, meta = build()
    files = {'s2_keys.mem': '\n'.join(klines) + '\n', 's2_vec.mem': '\n'.join(vlines) + '\n', 's2_meta.json': json.dumps(meta, indent=1) + '\n'}
    names = ''.join(f'    {i}: return "{n}";\n' for i, n in enumerate(meta['names']))
    files['s2_names.svh'] = ('// GENERATED by scripts/gen_s2_vectors.py: check name of each S2 vector (do not edit)\n'
                             f'localparam int S2_NV = {meta["vectors"]};\n'
                             'function automatic string s2_name(input int i);\n  case (i)\n' + names +
                             '    default: return "BAD";\n  endcase\nendfunction\n')
    if '--write' in sys.argv:
        OUT.mkdir(parents=True, exist_ok=True)
        for n, t in files.items(): (OUT / n).write_text(t, newline='\n')
        print(f'wrote {len(meta["names"])} S2 vectors to {OUT.relative_to(ROOT)}')
        return
    bad = [n for n, t in files.items() if not (OUT / n).is_file() or (OUT / n).read_text() != t]
    if bad: print('S2_VECTORS_CHECK: FAIL', bad); sys.exit(1)
    print(f'S2_VECTORS_CHECK: PASS ({meta["vectors"]} vectors)')


if __name__ == '__main__': main()
