"""L2 wire transcript vectors: thin adapter over the pinned teammate kmac128 (via s8_golden).

Output length is 128 bits with customization NOC-L2-AUTH-v1 (OD-1 L2 profile); the primitive
is the teammate kmac128, unchanged. Only flit/word packing, the directed case table and a
spec-level (M-F1 rev 6 R6.5-R6.8) receiver/transmitter model live here. Every expected value
used by tb_noc_l2_auth.sv comes from this file. OFFLINE DEMO ONLY.

Usage: python scripts/l2_golden.py            (check mode: committed vectors must match)
       python scripts/l2_golden.py --write    (regenerate vectors/l2_golden.{json,svh})
"""
import json
import sys
from full_chain_golden import produce
from s8_golden import ROOT, REFERENCE, kmac128

TILE = 3                      # DUT tile (CRYPTO, x=0 y=1); tb_noc_l2_auth uses L2_TILE
HEAD, BODY, TAIL = 0, 1, 2
MAX64 = (1 << 64) - 1
NPAY = {0: 1, 1: 1, 2: 2, 3: 0, 4: 7, 5: 16, 6: 0, 7: 0}   # message_payload_flits (P6)
MAC_FLITS = 4
BOOT_B = b'BOOT_00002'        # the NEW trusted boot epoch provisioned after reset (R6.8)
MODES = ['ENFORCE', 'NEG_MAC', 'NEG_SEQUENCE', 'NEG_EPOCH']
OP = dict(RESET=0, RX=1, BURST=2, TX=3, PROBE=4, INJECT=5)
# Checks the TB performs per op (see reports/i5_p3/P3_COUNT_DERIVATION.md); +1 final NI_NO_ABORT.
TB_CHECKS_PER_OP = {OP['RESET']: 1, OP['RX']: 4, OP['BURST']: 4, OP['TX']: 2, OP['PROBE']: 1, OP['INJECT']: 0}


def vc_of(msg):
    return 0 if msg in [0, 2] else 1 if msg in [1, 3] else 2


def packet(src, dst, msg, control, sequence, boot, payload, vc=None, keys=None, key=None):
    vc = vc_of(msg) if vc is None else vc
    n = 10+len(payload)
    head = ((dst % 3) << 29) | ((dst//3) << 26) | ((src % 3) << 23) | ((src//3) << 20) | (msg << 16) | (n << 11) | control
    if key is None:
        keys = bytes.fromhex(produce()[0]['directed_keys']) if keys is None else keys
        key = keys[(src*6+dst)*32:(src*6+dst+1)*32]
    transcript = head.to_bytes(4, 'little')+bytes([vc, 1])+boot+sequence.to_bytes(8, 'little')+b''.join(x.to_bytes(4, 'little') for x in payload)
    tag = kmac128(key, transcript, 16, b'NOC-L2-AUTH-v1')
    fresh = sequence.to_bytes(8, 'little')+boot+b'\0\0'
    words = [head]+[int.from_bytes(fresh[i:i+4], 'little') for i in range(0, 20, 4)]+payload+[int.from_bytes(tag[i:i+4], 'little') for i in range(0, 16, 4)]
    flits = [(w << 4) | ((0 if i == 0 else 2 if i == n-1 else 1) << 2) | vc for i, w in enumerate(words)]
    return dict(flits=flits, transcript=transcript.hex(), tag=tag.hex())


def directed_keys(boot):
    """Same derivation as full_chain_golden.produce() (C-8, OFFLINE DEMO, not frozen by rev 6)."""
    return b''.join(kmac128(bytes(range(32)), bytes([src, dst])+boot, 32, b'NOC-L2-KEY-v1') for src in range(6) for dst in range(6))


def key_of(keys, src, dst):
    return keys[(src*6+dst)*32:(src*6+dst+1)*32]


# ---- flit helpers (flit = data[35:4] | type[3:2] | vc[1:0]) ---------------------------------
def fdata(f): return f >> 4
def ftype(f): return (f >> 2) & 3
def fvc(f): return f & 3
def mk(word, typ, vc): return ((word & 0xffffffff) << 4) | (typ << 2) | vc
def peer(x, y): return y*3+x


def head_fields(w):
    return dict(dx=w >> 29 & 7, dy=w >> 26 & 7, sx=w >> 23 & 7, sy=w >> 20 & 7, msg=w >> 16 & 15, length=w >> 11 & 31, ctl=w & 0x7ff)


def flip(flits, idx, bit):
    out = list(flits); out[idx] ^= 1 << (4+bit); return out


def set_head(flits, **kw):
    out = list(flits); w = fdata(out[0])
    pos = dict(dx=(29, 7), dy=(26, 7), sx=(23, 7), sy=(20, 7), msg=(16, 15), length=(11, 31), ctl=(0, 0x7ff))
    for k, v in kw.items():
        s, m = pos[k]; w = (w & ~(m << s)) | ((v & m) << s)
    out[0] = mk(w, ftype(out[0]), fvc(out[0])); return out


def set_vc(flits, idx, vc):
    out = list(flits); out[idx] = (out[idx] & ~3) | vc; return out


def retype(f, typ): return (f & ~12) | (typ << 2)


# ---- spec receiver / NI / transmitter model (M-F1 rev 6 R6.5-R6.8, OD-4) --------------------
class State:
    def __init__(self, boot, keys, bypass):
        self.boot, self.keys, self.bypass = boot, keys, set(bypass)
        self.rx_seq = [0]*6; self.tx_seq = [0]*6; self.slots = [None, None]; self.reason = 0

    def slot_mask(self):
        return sum(1 << i for i, s in enumerate(self.slots) if s is not None)


def rx_verdict(st, flits):
    """Return (reason, info). reason 0 = authenticated. Local L2 reasons (R6.7.7, C-7):
    1 framing/header/drain, 2 MAC, 3 epoch, 4 sequence."""
    if ftype(flits[0]) != HEAD:
        raise ValueError('directed cases start with HEAD')
    h = fdata(flits[0]); F = head_fields(h); L = F['length']
    if L < 10 or L > 26 or len(flits) > 26 or len(flits) != L:
        return 1, None                                    # drained / early or late terminator
    vc0 = fvc(flits[0])
    for k in range(1, L):
        if fvc(flits[k]) != vc0 or ftype(flits[k]) != (TAIL if k == L-1 else BODY):
            return 1, None                                # framing (R6.7.2)
    msg = F['msg']
    if (msg > 7 or F['sx'] >= 3 or F['sy'] >= 2 or F['dx'] >= 3 or F['dy'] >= 2 or peer(F['dx'], F['dy']) != TILE
            or vc0 != vc_of(msg) or L != 1+NPAY[msg]+MAC_FLITS+5):
        return 1, None                                    # header (R6.7.3)
    words = [fdata(f) for f in flits]
    fresh = b''.join(w.to_bytes(4, 'little') for w in words[1:6])
    if fresh[18:20] != b'\0\0':
        return 1, None                                    # freshness padding (R6.5)
    seq = int.from_bytes(fresh[0:8], 'little'); epoch = fresh[8:18]
    n = NPAY[msg]; pay = words[6:6+n]; tag_words = words[6+n:10+n]; src = peer(F['sx'], F['sy'])
    if 'mac' not in st.bypass:
        transcript = h.to_bytes(4, 'little')+bytes([vc0, 1])+epoch+seq.to_bytes(8, 'little')+b''.join(x.to_bytes(4, 'little') for x in pay)
        tag = kmac128(key_of(st.keys, src, TILE), transcript, 16, b'NOC-L2-AUTH-v1')
        if tag != b''.join(w.to_bytes(4, 'little') for w in tag_words):
            return 2, None
    if 'epoch' not in st.bypass and epoch != st.boot:
        return 3, None
    if 'sequence' not in st.bypass and (seq == 0 or seq <= st.rx_seq[src]):
        return 4, None
    return 0, dict(src=src, seq=seq, msg=msg, ctl=F['ctl'], head=h, pay=pay)


def rx_commit(st, info):
    """Authenticated: commit sequence, then NI delivery (variant NI rules) after authentication."""
    st.rx_seq[info['src']] = info['seq']
    msg = info['msg']
    if msg in (1, 3):                                    # memory response must match an outstanding slot
        tag = info['ctl'] & 1; s = st.slots[tag]
        if s != (info['src'], msg):
            return [], []
        st.slots[tag] = None
    return [info['head'] - (5 << 11)], list(info['pay'])  # NI sees HEAD length-5 (R6.7.5)


def tx_ready(st, dest, msg):
    return int(msg <= 7 and dest < 6 and st.tx_seq[dest] != MAX64)


def tx_model(st, dest, msg, control, payload):
    assert tx_ready(st, dest, msg)
    ctl = control
    if msg in (0, 2):                                    # R6.9: preview control[0] = lowest free slot
        tag = next(i for i, s in enumerate(st.slots) if s is None)
        ctl = (control & ~1) | tag
        st.slots[tag] = (dest, 1 if msg == 0 else 3)
    seq = st.tx_seq[dest]+1; st.tx_seq[dest] = seq
    return packet(TILE, dest, msg, ctl, seq, st.boot, payload, key=key_of(st.keys, TILE, dest))


# ---- directed case table ---------------------------------------------------------------------
def build():
    full = produce()[0]
    boot_a = bytes.fromhex(full['boot']); keys_a = bytes.fromhex(full['directed_keys'])
    keys_b = directed_keys(BOOT_B)
    assert directed_keys(boot_a) == keys_a, 'L2 key derivation diverged from full_chain_golden'
    assert boot_a != BOOT_B and keys_a != keys_b
    p = [0x13579000+i for i in range(7)]; p4 = [0x2468a000+i for i in range(7)]; pmax = [0xfedc0000+i for i in range(7)]
    ka = lambda s, d: key_of(keys_a, s, d)
    kb = lambda s, d: key_of(keys_b, s, d)
    ch = lambda seq, pay=p, boot=boot_a, key=None, dst=TILE: packet(4, dst, 4, 0, seq, boot, pay, key=key or ka(4, dst))['flits']
    ch1 = ch(1); ch2 = ch(2)
    resp = lambda seq, boot=boot_a, key=None: packet(2, TILE, 3, 0, seq, boot, [], key=key or ka(2, TILE))['flits']
    grant = lambda seq: packet(4, TILE, 6, 0x080, seq, boot_a, [], key=ka(4, TILE))['flits']
    over = [retype(f, BODY) if i == len(ch2)-1 else f for i, f in enumerate(ch2)] + [mk(0xdead0000+i, BODY, 2) for i in range(12)] + [mk(0xdead00ff, TAIL, 2)]
    maxlen = set_head(ch2, length=27)[:-1] + [retype(ch2[-1], BODY)] + [mk(0xbeef0000+i, BODY, 2) for i in range(9)] + [mk(0xbeef00ff, TAIL, 2)]
    nihead = ((TILE % 3) << 29) | ((TILE//3) << 26) | (1 << 23) | (1 << 20) | (6 << 16) | (5 << 11) | 0x080
    undersize = [mk(nihead, HEAD, 2)] + [mk(0x0badf00d+i, BODY, 2) for i in range(3)] + [mk(0x0badf0ff, TAIL, 2)]
    P = {  # name: (flits, intended ENFORCE verdict: 0 accept or local reason)
        'ch1_genuine': ch1,
        'ch2_tamper_head_control': flip(ch2, 0, 7),
        'ch2_tamper_payload': flip(ch2, 6, 16),
        'ch2_tamper_tag': flip(ch2, len(ch2)-1, 16),
        'ch2_tamper_fresh_seq': flip(ch2, 1, 0),
        'ch2_tamper_fresh_epoch': flip(ch2, 3, 0),
        'ch2_fresh_padding_nonzero': flip(ch2, 5, 16),
        'ch2_wrong_src_claim': set_head(ch2, sx=2, sy=1),
        'ch2_wrong_key_spoof_signed': ch(2, key=ka(5, TILE)),
        'ch2_wrong_key_reverse_direction': ch(2, key=ka(TILE, 4)),
        'ch2_wrong_dest_tile5': ch(2, dst=5),
        'ch_seq_zero': ch(0),
        'ch2_wrong_vc_body': set_vc(ch2, 3, 3),
        'ch2_len_field_tamper': set_head(ch2, length=16),
        'ch2_truncated_8': ch2[:7] + [retype(ch2[7], TAIL)],
        'ch2_overlong_30_flits': over,
        'ch2_len_over_max_27': maxlen,
        'grant_undersize_unextended': undersize,
        'ch2_genuine': ch2,
        'resp1_bad_tag': flip(resp(1), 9, 18),
        'resp1_genuine': resp(1),
        'resp2_genuine': resp(2),
        'grant3_genuine': grant(3),
        'ch4_genuine': ch(4, p4),
        'grant5_genuine': grant(5),
        'ch_seq_max': ch(MAX64, pmax),
        'ch_seq_max_minus1': ch(MAX64-1, pmax),
        'ch1_epochA_keyB': ch(1, key=kb(4, TILE)),
        'ch1_genuine_bootB': ch(1, boot=BOOT_B, key=kb(4, TILE)),
        'resp1_genuine_bootB': resp(1, boot=BOOT_B, key=kb(2, TILE)),
    }
    W = [0x82000100, 0xcafe1234]
    R, X, B, T, PR, IN = 'RESET', 'RX', 'BURST', 'TX', 'PROBE', 'INJECT'
    enforce = [
        (R, 'A'), (T, (2, 2, 0x780, W)),
        (X, 'ch1_genuine', 0), (X, 'ch1_genuine', 4),
        (X, 'ch2_tamper_head_control', 2), (X, 'ch2_tamper_payload', 2), (X, 'ch2_tamper_tag', 2),
        (X, 'ch2_tamper_fresh_seq', 2), (X, 'ch2_tamper_fresh_epoch', 2), (X, 'ch2_fresh_padding_nonzero', 1),
        (X, 'ch2_wrong_src_claim', 2), (X, 'ch2_wrong_key_spoof_signed', 2), (X, 'ch2_wrong_key_reverse_direction', 2),
        (X, 'ch2_wrong_dest_tile5', 1), (X, 'ch_seq_zero', 4), (X, 'ch2_wrong_vc_body', 1),
        (X, 'ch2_len_field_tamper', 1), (X, 'ch2_truncated_8', 1), (X, 'ch2_overlong_30_flits', 1),
        (X, 'ch2_len_over_max_27', 1), (X, 'grant_undersize_unextended', 1),
        (X, 'ch2_genuine', 0),
        (X, 'resp1_bad_tag', 2), (X, 'resp1_genuine', 0),
        (T, (2, 2, 0x780, W)), (X, 'resp1_genuine', 4), (X, 'resp2_genuine', 0),
        (B, ['grant3_genuine', 'ch4_genuine', 'grant5_genuine'], 0),
        (X, 'ch4_genuine', 0),
        (X, 'ch_seq_max', 0), (X, 'ch_seq_max', 4), (X, 'ch_seq_max_minus1', 4),
        (R, 'B'),
        (X, 'ch1_genuine', 2),            # C-8: old-boot replay under rotated keys fails at MAC
        (X, 'ch1_epochA_keyB', 3),        # stale epoch under the CURRENT key reaches the epoch check
        (X, 'ch1_genuine_bootB', 0),      # reset cleared rx_seq: sequence restarts at 1
        (T, (2, 2, 0x780, W)), (X, 'resp1_genuine_bootB', 0),
        (IN, (2, MAX64-1)), (T, (2, 2, 0x780, W)),
        (PR, (2, 2, 1)),                  # tx_seq[2] == 2^64-1: request driven, must be refused
        (PR, (4, 2, 0)),                  # other peers unaffected (ready only, no request)
    ]
    neg = {
        'NEG_MAC': [(R, 'A'), (T, (2, 2, 0x780, W)), (X, 'ch1_genuine', 0),
                    (X, 'ch2_tamper_payload', 'attack'), (X, 'resp1_bad_tag', 'attack')],
        'NEG_SEQUENCE': [(R, 'A'), (T, (2, 2, 0x780, W)), (X, 'ch1_genuine', 0), (X, 'ch1_genuine', 'attack'),
                         (X, 'ch_seq_zero', 'attack'), (X, 'resp1_genuine', 0), (T, (2, 2, 0x780, W)),
                         (X, 'resp1_genuine', 'attack')],
        'NEG_EPOCH': [(R, 'B'), (X, 'ch1_epochA_keyB', 'attack'), (X, 'ch1_genuine', 2)],
    }
    scripts = dict(ENFORCE=enforce, **neg)
    bypass = dict(ENFORCE=[], NEG_MAC=['mac'], NEG_SEQUENCE=['sequence'], NEG_EPOCH=['epoch'])
    boots = dict(A=(boot_a, keys_a), B=(BOOT_B, keys_b))
    tx_table, steps_out = [], {}
    for mode in MODES:
        st = None; out = []
        for step in scripts[mode]:
            op = step[0]; e = dict(op=op, attack=0, acc=0, rej=0, rej_min=0, heads=[], pays=[], tx=-1, ready=0)
            if op == R:
                st = State(*boots[step[1]], bypass[mode]); e.update(arg=step[1], name='RESET_BOOT_'+step[1])
            elif op in (X, B):
                names = [step[1]] if op == X else step[1]
                reason, info = rx_verdict(st, P[names[0]])
                if step[2] == 'attack':
                    e['attack'] = 1
                    assert reason == 0, f'{mode} {names[0]}: bypass control does not open the targeted check'
                else:
                    assert reason == step[2], f'{mode} {names[0]}: model reason {reason} != intended {step[2]}'
                if reason:
                    st.reason = reason; e['rej'] = 1
                else:
                    e['acc'] = 1; e['heads'], e['pays'] = rx_commit(st, info)
                for _ in names[1:]:      # busy quarantine: consumed, dropped, counted (R6.7.6)
                    e['rej'] += 1; st.reason = 7
                e.update(rej_min=int(op == B), pkts=names, name=('BURST_' if op == B else '')+'+'.join(names))
            elif op == T:
                dest, msg, ctl, pay = step[1]
                pk = tx_model(st, dest, msg, ctl, pay)
                tx_table.append(dict(dest=dest, msg=msg, control_in=ctl, control=int(pk['flits'][0] >> 4 & 0x7ff), payload=pay, flits=pk['flits'], transcript=pk['transcript'], tag=pk['tag']))
                e.update(tx=len(tx_table)-1, name=f'TX_TO_TILE{dest}_SEQ{st.tx_seq[dest]}')
            elif op == PR:
                dest, msg, drive = step[1]
                e.update(dest=dest, msg=msg, drive=drive, ready=tx_ready(st, dest, msg),
                         name=('TX_REFUSE_' if drive else 'TX_READY_')+f'TILE{dest}')
            elif op == IN:
                st.tx_seq[step[1][0]] = step[1][1]
                e.update(peer=step[1][0], value=step[1][1], name=f'INJECT_TX_SEQ{step[1][0]}')
            e.update(reason=st.reason, slots=st.slot_mask())
            out.append(e)
        steps_out[mode] = out
    assert [e['ready'] for e in steps_out['ENFORCE'] if e['op'] == PR] == [0, 1]
    return dict(boot_a=boot_a, boot_b=BOOT_B, keys_a=keys_a, keys_b=keys_b, packets=P, tx=tx_table, steps=steps_out)


def tile_keys(keys, direction):
    """1536-bit tx_keys/rx_keys port value for TILE (R6.6: TX to p uses K[g->p], RX from p uses K[p->g])."""
    sel = [key_of(keys, TILE, p) if direction == 'tx' else key_of(keys, p, TILE) for p in range(6)]
    return int.from_bytes(b''.join(sel), 'little')


def kmac_kat():
    """NIST SP 800-185 KMAC128 sample 2 (customized, like every L2 call) through the same kmac128 import."""
    got = kmac128(bytes(range(0x40, 0x60)), bytes(range(4)), 32, b'My Tagged Application').hex()
    exp = '3b1fba963cd8b0b59e8c1a6d71888b7143651af8ba0a7070c0979e2811324aa5'
    if got != exp: raise AssertionError(f'L2 kmac128 NIST sample 2: got {got}')


def guard_packets(packets, genuine_rebuilt):
    """Oracle guard (2026-10-19): fail if two directed cases serialize to the same packet (the pre-724c96e
    aliasing defect), or if a *_genuine vector differs from an independent fresh rebuild of its base packet."""
    seen = {}
    for name, flits in packets.items():
        key = tuple(flits)
        if key in seen: raise AssertionError(f'L2 oracle guard: cases {seen[key]!r} and {name!r} are the same packet')
        seen[key] = name
    for name, flits in genuine_rebuilt.items():
        if packets[name] != flits: raise AssertionError(f'L2 oracle guard: {name} differs from its freshly rebuilt base packet')


def rebuild_genuine():
    """Rebuild the base packets from scratch, after build() has applied every mutation."""
    full = produce()[0]
    boot_a = bytes.fromhex(full['boot']); keys_a = bytes.fromhex(full['directed_keys'])
    p = [0x13579000+i for i in range(7)]
    k = lambda s, d: key_of(keys_a, s, d)
    return {'ch1_genuine': packet(4, TILE, 4, 0, 1, boot_a, p, key=k(4, TILE))['flits'],
            'ch2_genuine': packet(4, TILE, 4, 0, 2, boot_a, p, key=k(4, TILE))['flits'],
            'resp1_genuine': packet(2, TILE, 3, 0, 1, boot_a, [], key=k(2, TILE))['flits']}


def generate():
    kmac_kat()
    m = build()
    guard_packets(m['packets'], rebuild_genuine())
    names = list(m['packets'])
    pidx = {n: i for i, n in enumerate(names)}
    checks = {mode: sum(TB_CHECKS_PER_OP[OP[e['op']]] for e in steps)+1 for mode, steps in m['steps'].items()}
    L = [f"// Teammate-reference adapter L2 vectors ({REFERENCE['sha256'][:16]}); OFFLINE DEMO ONLY.",
         '// Generated by scripts/l2_golden.py --write. Every expected value of tb_noc_l2_auth.sv is here.',
         f'localparam int L2_TILE={TILE};',
         f'localparam string L2_ORACLE_ID="teammate-reference-adapter {REFERENCE["sha256"][:16]}";',
         f"localparam logic [79:0] L2_BOOT_A=80'h{int.from_bytes(m['boot_a'],'little'):020x};",
         f"localparam logic [79:0] L2_BOOT_B=80'h{int.from_bytes(m['boot_b'],'little'):020x};"]
    for nm, keys, d in [('TX_KEYS_A', m['keys_a'], 'tx'), ('RX_KEYS_A', m['keys_a'], 'rx'), ('TX_KEYS_B', m['keys_b'], 'tx'), ('RX_KEYS_B', m['keys_b'], 'rx')]:
        L.append(f"localparam logic [1535:0] L2_{nm}=1536'h{tile_keys(keys, d):0384x};")
    L.append('localparam int L2_EXP_ABORTS=0;')
    L.append('function automatic int l2_pkt_len(input int p);case(p)')
    L += [f'{i}: return {len(m["packets"][n])}; // {n}' for i, n in enumerate(names)]
    L += ['default:return 0;endcase endfunction', 'function automatic noc_pkg::flit_t l2_pkt_flit(input int p,input int w);case(p)']
    for i, n in enumerate(names):
        L.append(f'{i}: case(w)'); L += [f"{j}:return 36'h{v:09x};" for j, v in enumerate(m['packets'][n])]; L.append("default:return '0;endcase")
    L.append("default:return '0;endcase endfunction")
    T = m['tx']
    for fn, key in [('l2_tx_dest', 'dest'), ('l2_tx_msg', 'msg'), ('l2_tx_npay', None), ('l2_tx_len', 'flits')]:
        L.append(f'function automatic int {fn}(input int t);case(t)')
        L += [f'{i}: return {t[key] if key in ("dest", "msg") else len(t["payload"]) if key is None else len(t["flits"])};' for i, t in enumerate(T)]
        L.append('default:return 0;endcase endfunction')
    L.append('function automatic logic [10:0] l2_tx_ctl(input int t);case(t)')
    L += [f"{i}: return 11'h{t['control_in']:03x};" for i, t in enumerate(T)]
    L.append("default:return '0;endcase endfunction")
    L.append('function automatic logic [31:0] l2_tx_pay(input int t,input int i);case(t)')
    for i, t in enumerate(T):
        L.append(f'{i}: case(i)'); L += [f"{j}:return 32'h{v:08x};" for j, v in enumerate(t['payload'])]; L.append("default:return '0;endcase")
    L.append("default:return '0;endcase endfunction")
    L.append('function automatic noc_pkg::flit_t l2_tx_flit(input int t,input int w);case(t)')
    for i, t in enumerate(T):
        L.append(f'{i}: case(w)'); L += [f"{j}:return 36'h{v:09x};" for j, v in enumerate(t['flits'])]; L.append("default:return '0;endcase")
    L.append("default:return '0;endcase endfunction")
    S = m['steps']
    L.append('function automatic int l2_n_steps(input int m);case(m)')
    L += [f'{mi}: return {len(S[mode])}; // {mode}' for mi, mode in enumerate(MODES)]
    L.append('default:return 0;endcase endfunction')

    def stepfn(name, ret, val, default='0'):
        L.append(f'function automatic {ret} {name}(input int m,input int s);case(m*256+s)')
        for mi, mode in enumerate(MODES):
            for si, e in enumerate(S[mode]):
                v = val(e)
                if v is not None: L.append(f'{mi*256+si}: return {v};')
        L.append(f'default:return {default};endcase endfunction')
    stepfn('l2_step_op', 'int', lambda e: OP[e['op']])
    stepfn('l2_step_name', 'string', lambda e: f'"{e["name"]}"', '""')
    stepfn('l2_step_arg', 'int', lambda e: {'RESET': lambda: int(e['arg'] == 'B'), 'RX': lambda: pidx[e['pkts'][0]], 'BURST': lambda: pidx[e['pkts'][0]],
                                            'TX': lambda: e['tx'], 'PROBE': lambda: e['dest'], 'INJECT': lambda: e['peer']}[e['op']]())
    stepfn('l2_step_burst', 'int', lambda e: len(e['pkts']) if e['op'] == 'BURST' else None)
    L.append('function automatic int l2_step_burst_pkt(input int m,input int s,input int k);case(m*256+s)')
    for mi, mode in enumerate(MODES):
        for si, e in enumerate(S[mode]):
            if e['op'] == 'BURST':
                L.append(f'{mi*256+si}: case(k)'); L += [f'{k}:return {pidx[n]};' for k, n in enumerate(e['pkts'])]; L.append('default:return 0;endcase')
    L.append('default:return 0;endcase endfunction')
    stepfn('l2_step_msg', 'int', lambda e: e['msg'] if e['op'] == 'PROBE' else None)
    stepfn('l2_step_drive', 'bit', lambda e: e['drive'] if e['op'] == 'PROBE' else None)
    stepfn('l2_step_val', 'logic [63:0]', lambda e: f"64'h{e['value']:016x}" if e['op'] == 'INJECT' else None)
    stepfn('l2_step_attack', 'bit', lambda e: e['attack'] or None)
    stepfn('l2_exp_acc', 'int', lambda e: e['acc'] or None)
    stepfn('l2_exp_rej', 'int', lambda e: e['rej'] or None)
    stepfn('l2_exp_rej_min', 'bit', lambda e: e['rej_min'] or None)
    stepfn('l2_exp_reason', 'logic [3:0]', lambda e: f"4'd{e['reason']}")
    stepfn('l2_exp_heads', 'int', lambda e: len(e['heads']) or None)
    stepfn('l2_exp_pays', 'int', lambda e: len(e['pays']) or None)
    stepfn('l2_exp_slots', 'logic [1:0]', lambda e: f"2'b{e['slots']:02b}")
    stepfn('l2_exp_ready', 'bit', lambda e: e['ready'] if e['op'] == 'PROBE' else None)
    for fn, key in [('l2_exp_head', 'heads'), ('l2_exp_pay', 'pays')]:
        L.append(f'function automatic logic [31:0] {fn}(input int m,input int s,input int i);case(m*256+s)')
        for mi, mode in enumerate(MODES):
            for si, e in enumerate(S[mode]):
                if e[key]:
                    L.append(f'{mi*256+si}: case(i)'); L += [f"{j}:return 32'h{v:08x};" for j, v in enumerate(e[key])]; L.append("default:return '0;endcase")
        L.append("default:return '0;endcase endfunction")
    L.append('')
    data = dict(scope='OFFLINE DEMO', oracle='teammate-reference-adapter', reference_sha256=REFERENCE['sha256'], tile=TILE,
                boot_a=m['boot_a'].hex(), boot_b=m['boot_b'].hex(),
                packets=[dict(index=i, name=n, flits=m['packets'][n]) for i, n in enumerate(names)],
                tx=m['tx'], modes={mode: S[mode] for mode in MODES}, tb_checks=checks)
    return data, '\n'.join(L)


if __name__ == '__main__':
    data, sv = generate()
    for p, s in [(ROOT/'vectors/l2_golden.json', json.dumps(data, indent=2)+'\n'), (ROOT/'vectors/l2_golden.svh', sv)]:
        if '--write' in sys.argv: p.write_text(s, encoding='utf-8', newline='\n')
        else: assert p.read_text(encoding='utf-8') == s, 'stale L2 vectors'
    print(f"L2_ORACLE: PASS ({len(data['packets'])} directed packets, {len(data['tx'])} TX packets, "
          f"{sum(len(v) for v in data['modes'].values())} steps in {len(data['modes'])} modes; "
          f"TB checks {data['tb_checks']}; teammate kmac128)")
