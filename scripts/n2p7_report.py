"""NOC-2 subset on P7 (DECISION_REGISTER S2-N2P7): summarise a tb_noc_perf_p7 N2P7_MATRIX log and a tb_n2p7_rtt log.
Reads only the TB's own lines (TRACE / POINT / N2P7_CTRL / N2P7_RTT); prints a markdown table. Not an evidence judge.
Data latency = del - inj (network) and del - gen (including source queueing), data records (kind 2 = MEM_WR_REQ) only.
Throughput = delivered data packets per 1,000 cycles of the generation window (GEN_CYCLES = 2176).
Usage: python scripts/n2p7_report.py <matrix_log> [<rtt_log>]"""
import re, sys, statistics as st
from collections import defaultdict
GEN = 2176
PAT = {5: 'control only', 0: 'uniform', 2: 'hotspot'}

def matrix(path):
    t = open(path, errors='replace').read()
    tr = defaultdict(list)
    for m in re.finditer(r'^TRACE pattern=(\d+) period=(\d+) mac=\d+ kind=(\d+) source=\d+ seq=\d+ dst=\d+ gen=(-?\d+) accept=-?\d+ inj=(-?\d+) del=(-?\d+) ok=1$', t, re.M):
        p, q, k, g, i, d = map(int, m.groups())
        if k == 2 and i >= 0: tr[(p, q)].append((d - i, d - g))
    ctl = {(int(a), int(b)): m for a, b, *m in re.findall(r'^N2P7_CTRL pattern=(\d+) period=(\d+) loops=(\d+) started=\d+ rtt_min=(-?\d+) rtt_max=(-?\d+) rtt_mean=(-?\d+)$', t, re.M)}
    print('| Point | Load | Data delivered | per 1k cycles | net latency mean / max | incl. queue mean / max | Control loops | RTT min / mean / max |')
    print('|---|---|---|---|---|---|---|---|')
    for key in [(5, 64), (0, 64), (0, 8), (0, 1), (2, 64), (2, 8), (2, 1)]:
        v = tr.get(key, []); c = ctl.get(key)
        net = f'{st.mean(x for x, _ in v):.1f} / {max(x for x, _ in v)}' if v else '-'
        que = f'{st.mean(y for _, y in v):.1f} / {max(y for _, y in v)}' if v else '-'
        loops, mn, mx, me = c if c else ('-',) * 4
        print(f'| {PAT[key[0]]} | 1/{key[1]} | {len(v)} | {1000 * len(v) / GEN:.1f} | {net} | {que} | {loops} | {mn} / {me} / {mx} |')

def rtt(path):
    t = open(path, errors='replace').read()
    rows = re.findall(r'^N2P7_RTT load=(\w+) k=(\d+) row=\d+ rtt=(\d+) to_challenge=(\d+) challenge_to_response=(\d+) response_to_grant=(\d+) grant_to_delivered=(\d+)$', t, re.M)
    print('\n| Load | k | Round trip | start -> CHALLENGE | CHALLENGE -> RESPONSE | RESPONSE -> GRANT | GRANT -> delivered |')
    print('|---|---|---|---|---|---|---|')
    for r in rows: print('| ' + ' | '.join(r) + ' |')
    for load in ('NONE', 'LOADED'):
        v = [int(r[2]) for r in rows if r[0] == load]
        if v: print(f'\n{load}: round trip min {min(v)}, mean {st.mean(v):.1f}, max {max(v)} cycles ({len(v)} attestations)')

if __name__ == '__main__':
    matrix(sys.argv[1])
    if len(sys.argv) > 2: rtt(sys.argv[2])
