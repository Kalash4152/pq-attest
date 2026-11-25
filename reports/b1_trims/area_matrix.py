"""B-1 area matrix (Kalash 2026-10-20). ESTIMATE model built from measured OOC numbers; no new synthesis.
Every constant names its source. M = measured (OOC synthesis or routed), E = estimate (basis in the comment).
Output: area_matrix.md (table) next to this script."""
from itertools import product
from pathlib import Path

DEVICE = 63400
TARGET = 47550                      # 75 % (Kalash): routing + mesh-timing margin (mesh WNS +0.202 ns)
CELL_TO_LUT = 4156 / 4540           # M: util LUTs / LUT cells, noc_l2_auth top level (LUT6_2 packing)

MESH = 10114                        # M routed, dual_lane_10_20261019_180734_0c8800a9/pfc_mesh_gate
NI_ALONE = 402                      # M OOC, same run, pfc_ni_ooc (tile without an L2 wrapper)
L2_NI = 263                         # M in context, run 200142 b1_ooc_noc_l2_auth util_hier
L2_KMAC = (5912 + 5904) / 2         # M in context, rx_kmac / tx_kmac (constant key_len/custom trimmed)
L2_GLUE = 4156                      # M, noc_l2_auth top level outside kmac/ni
ENDPOINT = 19986                    # M, endpoint_ooc run 174533
VERIFIER = 5794 + 5284 + 300        # E: kdf + tag OOC (M) + FSM/collect (E 300; verifier never synthesized)
KECCAK = 3741                       # M, every keccak_f1600 instance in every OOC report
KECCAK_ROUND = 2119                 # M, keccak_round inside each keccak_f1600

# Trims of the L2 glue (E), from the netlist attribution (l2_lut_attribution.txt, l2_shared_split.txt), in LUT cells:
TRIM = {
    'T1 supplied_tag: capture MAC words during collect (4-position counter write) instead of rb[rn-4+i] read':
        (1156 - 72, 40),            # remove the runtime-indexed read cone, keep the 72-cell compare; +40 decoder (E)
    'T2 transcripts: wire kmac msg_in from tp[]/rb[] (kmac_encode.sv:408 masks i>=msg_len; kmac_128.sv:398 re-registers)':
        (1031, 0),                  # exclusive tx+rx transcript cones; also -1,408 FF
    'T3 key select from a per-tile key RAM (BRAM18) instead of 6:1 x 256 muxes on a 1,536-bit port':
        (1030, 30),                 # exclusive tx_key_q + rx_key_q cones; +1 RAMB18 per L2 tile
    'T4 quarantine rb[] in LUTRAM with HEAD/freshness captured at collect; replay by pointer':
        (294, 60),                  # rb[play] read cone; +60 control (E); -~700 FF
}
TRIM_SAVE = sum(round((s - c) * CELL_TO_LUT) for s, c in TRIM.values())
L2_GLUE_TRIMMED = L2_GLUE - TRIM_SAVE

# R1 shared L2 KMAC engine (E): one in-context kmac + 4:1 x 704-bit message mux + 4:1 x 256-bit key mux + arbiter.
SHARED_KMAC = round(L2_KMAC) + 704 + 256 + 150
# D: KDF and tag time-multiplexed on one KMAC, in the endpoint and in the verifier (E): -1 kmac (~5.1 k M) + ~0.7 k muxes.
D_SAVE = 2 * (5142 - 700)
# S: one shared Keccak permutation core (E). Users keep their 1600-bit state; each loses its round logic (M 2,119);
# the core adds an N:1 x 1600-bit state mux (1 LUT6 per bit up to 4:1, 2 per bit up to 16:1) + 100 control.
def shared_keccak_save(n):
    if n < 2: return 0
    mux = 1600 * (1 if n <= 4 else 2) + 100
    return (n - 1) * KECCAK_ROUND - mux

def row(l2_tiles, shared, d, trim, s):
    other = 6 - l2_tiles
    glue = L2_GLUE_TRIMMED if trim else L2_GLUE
    l2 = l2_tiles * (glue + L2_NI) + other * NI_ALONE
    kmacs = SHARED_KMAC if shared else l2_tiles * 2 * L2_KMAC
    crypto = ENDPOINT + VERIFIER - (D_SAVE if d else 0)
    n_keccak = (1 if shared else l2_tiles * 2) + (2 if d else 3) + (1 if d else 2)
    total = MESH + l2 + kmacs + crypto - (shared_keccak_save(n_keccak) if s else 0)
    bram = l2_tiles if trim else 0
    return round(total), n_keccak, bram

LOSS = {
    'min': 'data-plane link auth removed on all tiles (forged-source/replayed/tampered data packets, e.g. SPOOF raw '
           'injection claiming an authorized source reaching the memory commit); non-attested tiles must refuse GRANT',
    'all': 'none vs today (MAC kept on every message, all tiles)',
    'shared': 'availability coupling between MAC users (needs RoT strict priority + stated starvation bound)',
    'd': 'none (latency only, inside endpoint/verifier)',
    'trim': 'none (implementation only; needs an equivalence bench)',
    's': 'availability/timing coupling across ALL crypto users (attestation latency depends on L2 load)',
}

def main():
    out = ['| L2 tiles | L2 KMAC | D | Trim | Shared Keccak | Keccak cores | LUT (E) | % device | <= 75 % | BRAM18 | Threat-model loss vs today |',
           '|---|---|---|---|---|---|---|---|---|---|---|']
    for l2_tiles, shared, d, trim, s in product((2, 6), (False, True), (False, True), (False, True), (False, True)):
        if l2_tiles == 6 and (d or s): continue           # all-tile reference rows: KMAC x trim only
        total, nk, bram = row(l2_tiles, shared, d, trim, s)
        loss = [LOSS['min' if l2_tiles == 2 else 'all']] + [LOSS[k] for k, on in (('shared', shared), ('d', d), ('trim', trim), ('s', s)) if on]
        out.append(f"| {'3,4 (minimal)' if l2_tiles == 2 else 'all 6'} | {'1 shared' if shared else str(2*l2_tiles)+' per-tile'} | "
                   f"{'yes' if d else 'no'} | {'yes' if trim else 'no'} | {'yes' if s else 'no'} | {1 if s else nk} | {total:,} | "
                   f"{100*total/DEVICE:.0f} % | {'**yes**' if total <= TARGET else 'no'} | {bram} | {'; '.join(loss)} |")
    out += ['', f'Trimmed L2 glue: {L2_GLUE:,} -> {L2_GLUE_TRIMMED:,} LUT per L2 tile (E, saving {TRIM_SAVE:,}).',
            f'Shared L2 KMAC engine: {SHARED_KMAC:,} LUT (E). D saving: {D_SAVE:,} LUT (E). Target <= {TARGET:,} LUT (75 %).']
    (Path(__file__).with_name('area_matrix.md')).write_text('\n'.join(out) + '\n', encoding='utf-8', newline='\n')
    print('\n'.join(out))

if __name__ == '__main__':
    main()
