"""B-3 D variant check (job kshare_variant): protected originals unchanged, generated variants equal the generator's
output from them, provenance hashes current. Prints KSHARE_VARIANT: PASS or exits non-zero."""
import hashlib, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import prepare_kshare as P
def main():
    f = []
    try: exp = P.expected()
    except SystemExit as e: exp = {}; f.append(str(e))
    prov = json.loads((P.D / 'variant_provenance.json').read_text())
    for dst, (src, text) in exp.items():
        if (P.D / dst).read_text(encoding='utf-8') != text: f.append(f'{dst} differs from the generator output')
        if prov.get(dst, {}).get('variant') != P.sha(P.D / dst): f.append(f'{dst} provenance mismatch')
    if prov.get('pq_rot_verifier.sv', {}).get('variant') != P.sha(P.D / 'pq_rot_verifier.sv'): f.append('verifier provenance mismatch')
    for x in f: print('FAIL', x)
    if f: print('KSHARE_VARIANT: FAIL'); sys.exit(1)
    print('KSHARE_VARIANT: PASS (' + ', '.join(f'{d} {P.sha(P.D / d)[:12]}' for d in exp) + ')')
if __name__ == '__main__': main()
