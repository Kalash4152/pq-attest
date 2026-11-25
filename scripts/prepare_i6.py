"""I-6 bench copies (docs/decisions/I6_CONTRACT.md sec. 4): exact-anchor edits of the P7 subsystem benches.

Each copy keeps its module name and check count; it differs from its original only by
  * the C-5 window: 32'h8200_0100 -> 32'h2200_0100 (every occurrence; the stand-in now accepts A[31:28] == 4'h2),
  * the new trusted input tied off: `.trusted_clear(1'b0), ` before the subsystem's `.app_valid` connection,
  * the f234 wrapper's include file name,
  * tb_pq_endpoint_unit (implicit .* connection): a declaration for the endpoint's new k3_fault output.
The originals stay as history (never edited). Default: regenerate in memory and compare with the files on disk
(job i6_benches, marker I6_BENCHES: PASS); --write writes the copies and sim/dual_lane/i6/i6_provenance.json.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
T = 'NOC_PQATTEST.srcs/sim_1/new/'
F = 'sim/dual_lane/f234/'
OLD_ADDR, NEW_ADDR = "32'h8200_0100", "32'h2200_0100"
TIE = ('.app_valid, .app_payload_valid,', ".trusted_clear(1'b0), .app_valid, .app_payload_valid,")
# (original, copy, edits); an edit is (old, new, expected count or None for "at least one")
COPIES = [
    (T + 'tb_n2p7_rtt.sv', T + 'tb_n2p7_rtt_i6.sv', [(OLD_ADDR, NEW_ADDR, 1), TIE + (1,)]),
    (T + 'tb_p7_c4.sv', T + 'tb_p7_c4_i6.sv', [(OLD_ADDR, NEW_ADDR, 1), TIE + (1,)]),
    (T + 'tb_p7_gate_data.sv', T + 'tb_p7_gate_data_i6.sv', [(OLD_ADDR, NEW_ADDR, 1), TIE + (1,)]),
    (T + 'tb_p7_ingress.sv', T + 'tb_p7_ingress_i6.sv', [(OLD_ADDR, NEW_ADDR, 1), TIE + (1,)]),
    (T + 'tb_p7_refuse_grant.sv', T + 'tb_p7_refuse_grant_i6.sv', [TIE + (1,)]),
    (F + 'tb_sys_f234_body.svh', F + 'tb_sys_f234_body_i6.svh', [(OLD_ADDR, NEW_ADDR, 1), TIE + (1,),
        ("// the stand-in's current legal window (C-5 conformance pending)", "// C-5 window (I-6)", 1)]),
    (T + 'tb_sys_f234_p7.sv', T + 'tb_sys_f234_p7_i6.sv', [('`include "tb_sys_f234_body.svh"', '`include "tb_sys_f234_body_i6.svh"', 1)]),
    # implicit .* connection: the endpoint's new K-3 output needs a bench signal (unconnected in use, K3_ENFORCE = 0)
    (T + 'tb_pq_endpoint_unit.sv', T + 'tb_pq_endpoint_unit_i6.sv', [('  logic         busy, controller_start;',
        '  logic         busy, controller_start, k3_fault;   // I-6: K-3 output (K3_ENFORCE = 0 here)', 1)]),
]
PROV = ROOT / 'sim/dual_lane/i6/i6_provenance.json'


def sha(b):
    return hashlib.sha256(b).hexdigest()


def build():
    out = {}
    for src, dst, edits in COPIES:
        text = (ROOT / src).read_text(encoding='utf-8')
        for old, new, n in edits:
            c = text.count(old)
            if c != n:
                raise SystemExit(f'I6_BENCHES: FAIL {src}: anchor {old[:40]!r} found {c} times, expected {n}')
            text = text.replace(old, new)
        out[dst] = (src, text)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--write', action='store_true')
    ap.add_argument('--out', help='unused')
    a = ap.parse_args()
    gen = build()
    prov = dict(schema=1, tool='scripts/prepare_i6.py', copies=[
        dict(original=src, copy=dst, original_sha256=sha((ROOT / src).read_bytes()), copy_sha256=sha(text.encode()))
        for dst, (src, text) in gen.items()])
    if a.write:
        for dst, (_, text) in gen.items():
            (ROOT / dst).write_text(text, encoding='utf-8', newline='\n')
        PROV.parent.mkdir(parents=True, exist_ok=True)
        PROV.write_text(json.dumps(prov, indent=2) + '\n', encoding='utf-8', newline='\n')
        print('wrote', len(gen), 'copies')
        return
    bad = [dst for dst, (_, text) in gen.items() if not (ROOT / dst).exists() or (ROOT / dst).read_bytes() != text.encode()]
    if not PROV.exists() or json.loads(PROV.read_text(encoding='utf-8')) != prov:
        bad.append(str(PROV.relative_to(ROOT)))
    if bad:
        print('I6_BENCHES: FAIL', ', '.join(bad))
        sys.exit(1)
    print(f'I6_BENCHES: PASS copies={len(gen)}')


if __name__ == '__main__':
    main()
