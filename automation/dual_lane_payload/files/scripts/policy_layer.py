"""V10 system-policy RoT model, OUTSIDE the immutable teammate reference.

The teammate verifier_check is stateless and has no whitelist (L-2). This layer adds, on top of
an UNCHANGED call to verifier_check:
  * outstanding-challenge tracking and retirement (a challenge is consumed by its first
    reference-valid response),
  * duplicate / unsolicited response rejection, and nonce reuse refusal at issue time,
  * a per-tile digest whitelist with FIXED provisioned config_len / imem_len (K-3, L-1
    mitigation: a provisioning guarantee, not a cryptographic one),
  * the C-1/C-2 busy rule (I-6): a BUSY reply re-issues the SAME challenge at most
    MAX_BUSY_RETRIES times; the next BUSY, or any status other than 1 / 3, fails closed.
Every check records BOTH verdicts (reference and policy). System profile: TILE_KEY_BYTES=32.
OFFLINE DEMO data only.
"""
import argparse
import json
from pathlib import Path
import sys

from s8_golden import (ROOT, REFERENCE, TILE_KEY_BYTES, AttestationRequest, AttestationResponse,
                       derive_tile_key, measure_tile, tile_respond, verifier_check)

ACCEPT, REJECT = 'ACCEPT', 'REJECT'
MAX_BUSY_RETRIES = 3            # DECISION_REGISTER C-1/C-2 (Kalash Option A), I6-RETRY
ST_SUCCESS, ST_BUSY = 1, 3      # K-2 / OD-2 status codes


def busy_retry_outcome(statuses):
    """C-1/C-2 rule for one attestation start. `statuses` are the endpoint replies, in order, to the
    challenges sent (each retry re-sends the same challenge). Returns (challenges_sent, outcome) with
    outcome 'GRANT' (status 1 reached; the crypto checks follow) or 'FAIL' (fail closed, REVOKE)."""
    retries = 0
    for i, st in enumerate(statuses):
        if st == ST_SUCCESS:
            return i + 1, 'GRANT'
        if st == ST_BUSY and retries < MAX_BUSY_RETRIES:
            retries += 1
            continue
        return i + 1, 'FAIL'
    raise ValueError('reply sequence ended before a verdict')


def busy_rows(max_busy=5):
    """Rows (n_busy, challenges, outcome): n_busy BUSY replies, then SUCCESS if a challenge is still sent."""
    return [(n,) + busy_retry_outcome([ST_BUSY] * n + [ST_SUCCESS]) for n in range(max_busy + 1)]


class ProvisioningError(ValueError):
    pass


class RoTPolicy:
    def __init__(self):
        self.whitelist = {}      # tile_id -> dict(digest, config_len, imem_len)
        self.outstanding = {}    # (tile, epoch, nonce) -> request
        self.issued_nonces = set()
        self.records = []

    # -- provisioning (K-3: fixed split per tile, recorded next to the digest) --
    def provision(self, tile_id, config, imem):
        if tile_id in self.whitelist:
            raise ProvisioningError('tile already provisioned')
        entry = dict(digest=measure_tile(tile_id, config, imem),
                     config_len=len(config), imem_len=len(imem))
        self.whitelist[tile_id] = entry
        return entry

    def provisioned_measurement(self, tile_id, config, imem):
        """Measure an image only under the tile's fixed split; a re-split is refused."""
        e = self.whitelist.get(tile_id)
        if e is None:
            raise ProvisioningError('tile not provisioned')
        if (len(config), len(imem)) != (e['config_len'], e['imem_len']):
            raise ProvisioningError(f"split {len(config)}/{len(imem)} != provisioned "
                                    f"{e['config_len']}/{e['imem_len']}")
        return measure_tile(tile_id, config, imem)

    # -- challenge lifecycle --
    def issue(self, tile_id, epoch, nonce):
        if len(nonce) != 16:
            raise ValueError('nonce must be exactly 16 bytes')
        if nonce in self.issued_nonces:
            raise ValueError('nonce reuse refused')
        self.issued_nonces.add(nonce)
        req = AttestationRequest(tile_id=tile_id, epoch=epoch, nonce=nonce)
        self.outstanding[(tile_id, epoch, nonce)] = req
        return req

    def check(self, case, tile_key, request, response):
        ref = verifier_check(tile_key, request, response)   # immutable reference, unchanged
        ref_v = ACCEPT if ref.accepted else REJECT
        key = (response.tile_id, response.epoch, response.nonce)
        if not ref.accepted:
            pol, why = REJECT, 'reference rejected: ' + ref.reason
        elif self.outstanding.get(key) != request:
            pol, why = REJECT, 'no outstanding challenge (duplicate, retired or unsolicited)'
        else:
            del self.outstanding[key]   # retire on first reference-valid response
            e = self.whitelist.get(response.tile_id)
            if e is None:
                pol, why = REJECT, 'tile not provisioned'
            elif response.measurement != e['digest']:
                pol, why = REJECT, 'measurement not on whitelist'
            else:
                pol, why = ACCEPT, 'approved digest, challenge retired'
        rec = dict(case=case, tile=response.tile_id.decode('latin-1'), nonce=response.nonce.hex(),
                   measurement=response.measurement.hex(), reference_verdict=ref_v,
                   reference_reason=ref.reason, policy_verdict=pol, policy_reason=why)
        self.records.append(rec)
        return rec


def selftest():
    root = bytes(range(32)); tile = b'TILE_03'; epoch = b'EPOCH_0001'; ctx = b'PQ-ATTEST-KDF'
    config = bytes(range(16)); imem = bytes(range(16, 32))
    key = derive_tile_key(root, tile, epoch, ctx, key_bytes=TILE_KEY_BYTES)
    rot = RoTPolicy(); rot.provision(tile, config, imem)
    expect = {}

    # (genuine) approved image, fresh challenge -> both ACCEPT
    r1 = rot.issue(tile, epoch, bytes(range(16)))
    resp1 = tile_respond(key, r1, rot.provisioned_measurement(tile, config, imem))
    rot.check('genuine', key, r1, resp1); expect['genuine'] = (ACCEPT, ACCEPT)
    # (a) duplicate: the same valid response submitted again -> reference ACCEPT, policy REJECT
    rot.check('duplicate_response', key, r1, resp1); expect['duplicate_response'] = (ACCEPT, REJECT)
    # (b) unapproved measurement: genuine key/tag over a modified image -> ACCEPT / REJECT
    r2 = rot.issue(tile, epoch, bytes((j + 17) & 255 for j in range(16)))
    bad_imem = b'\xff' + imem[1:]
    resp2 = tile_respond(key, r2, rot.provisioned_measurement(tile, config, bad_imem))
    rot.check('unapproved_measurement', key, r2, resp2); expect['unapproved_measurement'] = (ACCEPT, REJECT)
    # unsolicited: response to a challenge the RoT never issued -> ACCEPT / REJECT
    r3 = AttestationRequest(tile_id=tile, epoch=epoch, nonce=b'\x5a' * 16)
    resp3 = tile_respond(key, r3, rot.whitelist[tile]['digest'])
    rot.check('unsolicited_challenge', key, r3, resp3); expect['unsolicited_challenge'] = (ACCEPT, REJECT)
    # forged tag: both layers REJECT (policy never overrides a reference REJECT)
    r4 = rot.issue(tile, epoch, bytes((j + 34) & 255 for j in range(16)))
    good4 = tile_respond(key, r4, rot.whitelist[tile]['digest'])
    resp4 = AttestationResponse(good4.tile_id, good4.epoch, good4.nonce, good4.measurement,
                                bytes([good4.tag[0] ^ 1]) + good4.tag[1:])
    rot.check('forged_tag', key, r4, resp4); expect['forged_tag'] = (REJECT, REJECT)
    # after a reference REJECT the challenge stays outstanding; the genuine reply still works once
    rot.check('genuine_after_forgery', key, r4, good4); expect['genuine_after_forgery'] = (ACCEPT, ACCEPT)

    fails = []
    for rec in rot.records:
        want = expect[rec['case']]
        if (rec['reference_verdict'], rec['policy_verdict']) != want:
            fails.append(f"{rec['case']}: got {rec['reference_verdict']}/{rec['policy_verdict']} want {want}")
    # nonce reuse refused at issue time
    try: rot.issue(tile, epoch, bytes(range(16)))
    except ValueError: pass
    else: fails.append('nonce reuse accepted')
    # L-1: same concatenated bytes under a different split are refused at provisioning
    joined = config + imem
    try: rot.provisioned_measurement(tile, joined[:15], joined[15:])
    except ProvisioningError: pass
    else: fails.append('re-split image accepted')
    if measure_tile(tile, joined[:15], joined[15:]) != rot.whitelist[tile]['digest']:
        fails.append('L-1 premise (split ambiguity of unencoded measurement) not reproduced')
    # C-1/C-2 busy rule (I-6): 0..3 BUSY then SUCCESS grants after n+1 challenges; a 4th BUSY fails closed
    # after exactly 1 + 3 challenges; any other non-1 status fails at once.
    want_rows = [(0, 1, 'GRANT'), (1, 2, 'GRANT'), (2, 3, 'GRANT'), (3, 4, 'GRANT'), (4, 4, 'FAIL'), (5, 4, 'FAIL')]
    if busy_rows() != want_rows:
        fails.append(f'busy rule rows {busy_rows()} != {want_rows}')
    for st in (2, 4, 5, 10):
        if busy_retry_outcome([st]) != (1, 'FAIL') or busy_retry_outcome([ST_BUSY, st]) != (2, 'FAIL'):
            fails.append(f'status {st} not failed closed')
    return rot, fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--record', help='write the verdict records as JSON (reports/i2_track_a/...)')
    ap.add_argument('--out', help='scheduler evidence directory; records go to <out>/policy_layer_records.json')
    args = ap.parse_args()
    if args.out and not args.record:
        args.record = str(Path(args.out) / 'policy_layer_records.json')
    rot, fails = selftest()
    for rec in rot.records:
        print(f"{rec['case']}: reference={rec['reference_verdict']} policy={rec['policy_verdict']}"
              f" ({rec['policy_reason']})")
    if args.record:
        out = Path(args.record)
        out = out if out.is_absolute() else ROOT / out
        out.parent.mkdir(parents=True, exist_ok=True)
        payload = dict(tile_key_bytes=TILE_KEY_BYTES, reference_sha256=REFERENCE['sha256'],
                       provisioning='OFFLINE DEMO ONLY',
                       whitelist={t.decode(): dict(digest=e['digest'].hex(), config_len=e['config_len'],
                                                   imem_len=e['imem_len']) for t, e in rot.whitelist.items()},
                       records=rot.records, extra_checks=['nonce_reuse_refused', 'resplit_refused_L1', 'busy_retry_rows', 'non_busy_fail_closed'],
                       busy_rows=[list(r) for r in busy_rows()],
                       result='FAIL' if fails else 'PASS')
        out.write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8', newline='\n')
    for f in fails:
        print('FAIL', f)
    if fails:
        print(f'POLICY_LAYER: FAIL n={len(fails)}')
        sys.exit(1)
    for n, ch, out in busy_rows():
        print(f'BUSY_RULE n_busy={n} challenges={ch} outcome={out}')
    print(f'POLICY_LAYER: PASS records={len(rot.records)} extra_checks=4')


if __name__ == '__main__':
    main()
