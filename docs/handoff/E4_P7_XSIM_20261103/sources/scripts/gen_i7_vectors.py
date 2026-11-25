"""I-7 PQ-4 SEC matrix vectors (docs/decisions/I7_SEC_MATRIX.md): attacker responses and expected verdicts from the
frozen teammate reference (via s8_golden) and scripts/policy_layer.py -- never from the RTL.

The P7 RESPONSE carries only measurement (W0..W7) and tag (W8..W15); the RTL verifier recomputes the tag over ITS
outstanding tile / epoch / nonce. Each row is therefore judged the way the wire allows: the reference verifier_check is
called with the outstanding request and a response object holding that request's fields plus the attacker's
measurement and tag (wire verdict), and the policy layer adds the whitelist. Mapping to the I-6 fault map:
reference 'KMAC128 tag verification failed' -> 12, policy 'measurement not on whitelist' -> 11, status != 1 -> 9.
Default: compare with the committed vectors/i7_sec.svh (job i7_vectors, marker I7_VECTORS: PASS); --write writes it.
"""
import argparse, hashlib, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from s8_golden import (REFERENCE, TILE_KEY_BYTES, AttestationRequest, AttestationResponse, derive_tile_key,   # noqa: E402
                       measure_tile, tile_respond, verifier_check)
from policy_layer import RoTPolicy, busy_retry_outcome   # noqa: E402
from full_chain_golden import produce   # noqa: E402
import l2_golden as L2   # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'vectors/i7_sec.svh'
TILE, EPOCH, ROOTK, CTX = b'TILE_03', b'EPOCH_0001', bytes(range(32)), b'PQ-ATTEST-KDF'
CONFIG, IMEM = bytes(range(16)), bytes(range(16, 32))
NONCE = [bytes((j + i * 17) & 255 for j in range(16)) for i in range(3)]   # full_chain rows 0..2


def words(meas, tag):
    b = meas + tag
    return [int.from_bytes(b[4 * i:4 * i + 4], 'little') for i in range(16)]


def rows():
    key = derive_tile_key(ROOTK, TILE, EPOCH, CTX, key_bytes=TILE_KEY_BYTES)
    rot = RoTPolicy(); rot.provision(TILE, CONFIG, IMEM); good = rot.whitelist[TILE]['digest']
    out = []

    def judge(name, sec, req, meas, tag, status=1, note=''):
        if status != 1:
            n, verdict = busy_retry_outcome([status])
            exp = 9 if verdict == 'FAIL' else 0
            ref = 'status %d: C-1/C-2 fail closed' % status
        else:
            wire = AttestationResponse(tile_id=req.tile_id, epoch=req.epoch, nonce=req.nonce, measurement=meas, tag=tag)
            v = verifier_check(key, req, wire)
            if not v.accepted:
                exp, ref = (12 if 'KMAC128' in v.reason else 99), v.reason
            elif meas != good:
                exp, ref = 11, 'reference ACCEPT; policy: measurement not on whitelist'
            else:
                exp, ref = 0, 'reference ACCEPT; policy ACCEPT'
        out.append(dict(name=name, sec=sec, status=status, words=words(meas, tag) if status == 1 else [0] * 16,
                        expect=exp, reason=ref, note=note))

    r1 = AttestationRequest(tile_id=TILE, epoch=EPOCH, nonce=NONCE[1])        # the outstanding challenge (row 1)
    g1 = tile_respond(key, r1, good)
    judge('GENUINE_SUB', 'SEC-1', r1, g1.measurement, g1.tag, note='genuine words through the substitution hook')
    judge('WRONG_TAG', 'OPEN-1', r1, g1.measurement, bytes([g1.tag[0] ^ 1]) + g1.tag[1:])
    bad = measure_tile(TILE, CONFIG, b'\xff' + IMEM[1:])
    b1 = tile_respond(key, r1, bad)
    judge('WRONG_MEAS', 'OPEN-2', r1, b1.measurement, b1.tag, note='genuine key, unapproved image')
    r0 = AttestationRequest(tile_id=TILE, epoch=EPOCH, nonce=NONCE[0])
    old = tile_respond(key, r0, good)
    judge('ATTEST_REPLAY', 'OPEN-3', r1, old.measurement, old.tag, note='response to row 0 replayed to row 1')
    rx = AttestationRequest(tile_id=TILE, epoch=EPOCH, nonce=bytes([0x5a] * 16))
    sub = tile_respond(key, rx, good)
    judge('NONCE_SUBST', 'OPEN-4', r1, sub.measurement, sub.tag, note='tag over an attacker nonce')
    judge('ERROR_RESPONSE', 'OPEN-6', r1, b'', b'', status=2)
    wk = derive_tile_key(bytes([0xa5]) + ROOTK[1:], TILE, EPOCH, CTX, key_bytes=TILE_KEY_BYTES)
    w1 = tile_respond(wk, r1, good)
    judge('WRONG_KEY', 'SEC-2', r1, w1.measurement, w1.tag, note='other root secret')
    ik = derive_tile_key(ROOTK, b'TILE_04', EPOCH, CTX, key_bytes=TILE_KEY_BYTES)
    i1 = tile_respond(ik, AttestationRequest(tile_id=b'TILE_04', epoch=EPOCH, nonce=NONCE[1]), good)
    judge('WRONG_IDENTITY', 'SEC-2', r1, i1.measurement, i1.tag, note='key and tag of identity TILE_04')
    sk = derive_tile_key(ROOTK, TILE, b'EPOCH_0000', CTX, key_bytes=TILE_KEY_BYTES)
    s1 = tile_respond(sk, AttestationRequest(tile_id=TILE, epoch=b'EPOCH_0000', nonce=NONCE[1]), good)
    judge('STALE_EPOCH', 'SEC-3', r1, s1.measurement, s1.tag, note='key and tag of the previous epoch')
    # SEC-4: the genuine tile measures a substituted imem at re-attestation (no hook; the endpoint computes it)
    subst = measure_tile(TILE, CONFIG, IMEM[:15] + b'\xee')
    t1 = tile_respond(key, r1, subst)
    judge('SUBST_IMEM', 'OPEN-5/SEC-4', r1, t1.measurement, t1.tag, note='endpoint computes it; words for reference only')
    return out, bytes(IMEM[:15] + b'\xee')


def l2_reasons():
    """L2 verdicts from the spec receiver model (scripts/l2_golden.py rx_verdict) for the bench's replays; the
    non-peer control reason 5 is M-F1 R7.2 (P7 header pre-check, not in the rev-6 model). The truncated raw CHALLENGE
    never reaches an L2: the tile-5 quarantine rejects a HEAD whose length != P7 message_length (M-F1 R7.5b, reason 11)."""
    data = produce()[0]
    keys, boot = bytes.fromhex(data['directed_keys']), bytes.fromhex(data['boot'])
    grant = L2.packet(4, 3, 6, 0x080, 5, boot, [], keys=keys)['flits']        # a genuine GRANT, sequence 5
    st = L2.State(boot, keys, []); st.rx_seq[4] = 5                            # tile 3 has already accepted it
    replay, _ = L2.rx_verdict(st, grant)
    new_boot = bytes([boot[0] ^ 1]) + boot[1:]                                 # bench: boot_epoch = BOOT ^ 80'h1
    reset, _ = L2.rx_verdict(L2.State(new_boot, keys, []), grant)              # after reset: rx_seq 0, new epoch
    head = (0 << 29) | (1 << 26) | (2 << 23) | (1 << 20) | (4 << 16) | (3 << 11)   # CHALLENGE 5 -> 3, length 3
    trunc = [(head << 4) | (0 << 2) | 2, (0 << 4) | (1 << 2) | 2, (0 << 4) | (2 << 2) | 2]
    trunc_r, _ = L2.rx_verdict(L2.State(boot, keys, []), trunc)
    assert trunc_r == 1   # the L2 model would refuse it too (framing), but the quarantine is the first layer
    return dict(I7_L2_REPLAY_REASON=replay, I7_RESET_REPLAY_REASON=reset, I7_SPOOF_RESPONSE_REASON=5,
                I7_TRUNC_QUARANTINE_REASON=11)


def render():
    rs, subst_imem = rows()
    if any(r['expect'] == 99 for r in rs):
        raise SystemExit('I7_VECTORS: FAIL unmapped reference reason')
    L = ['// GENERATED by scripts/gen_i7_vectors.py from the teammate reference (s8_golden) and scripts/policy_layer.py;',
         f"// reference sha256 {REFERENCE['sha256']}; do not edit.", f'localparam int I7_ROWS = {len(rs)};']
    for i, r in enumerate(rs):
        L.append(f"// {i} {r['name']} ({r['sec']}): expect {r['expect']} ({r['reason']}) {r['note']}")
    # names by a case function, not a localparam string array (XSim 2024.1 prints / compares those elements wrongly)
    L.append('function automatic string i7_name(input int r);')
    L.append('  case (r) ' + ' '.join(f'{i}: return "{r["name"]}";' for i, r in enumerate(rs)) + ' default: return "BAD"; endcase')
    L.append('endfunction')
    L.append(f"localparam int I7_SUBST_ROW = {[r['name'] for r in rs].index('SUBST_IMEM')};")
    L.append('localparam int I7_STATUS [I7_ROWS] = \'{' + ', '.join(str(r['status']) for r in rs) + '};')
    L.append('localparam int I7_EXPECT [I7_ROWS] = \'{' + ', '.join(str(r['expect']) for r in rs) + '};')
    L.append('localparam logic [511:0] I7_WORDS [I7_ROWS] = \'{' + ', '.join(
        "512'h" + ''.join(f'{w:08x}' for w in reversed(r['words'])) for r in rs) + '};')
    for k, v in l2_reasons().items():
        L.append(f'localparam int {k} = {v};')
    L.append(f"localparam logic [511:0] I7_SUBST_IMEM = 512'h{int.from_bytes(subst_imem, 'little'):0128x};")
    return '\n'.join(L) + '\n'


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--write', action='store_true'); ap.add_argument('--out')
    a = ap.parse_args(); text = render()
    if a.write:
        OUT.write_text(text, encoding='utf-8', newline='\n'); print('wrote', OUT); return
    have = OUT.read_text(encoding='utf-8') if OUT.exists() else ''
    if have != text:
        print('I7_VECTORS: FAIL stale vectors/i7_sec.svh'); sys.exit(1)
    print(f'I7_VECTORS: PASS rows={len(rows()[0])} sha256={hashlib.sha256(text.encode()).hexdigest()}')


if __name__ == '__main__':
    main()
