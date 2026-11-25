"""B-2 trim variant check (job l2trim_variant): pre-trim blob hash, TB-only copy equals the renamed pre-trim wrapper,
provenance names the current trimmed file. Prints L2TRIM_VARIANT: PASS or exits non-zero."""
import hashlib, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import prepare_l2trim as P
def main():
    f = []
    try: exp = P.expected_copy()
    except SystemExit as e: exp = None; f.append(str(e))
    if exp is not None and (P.E / 'noc_l2_auth_orig_l2trim.sv').read_text(encoding='utf-8') != exp:
        f.append('TB-only copy differs from the renamed pre-trim wrapper')
    prov = json.loads((P.D / 'variant_provenance.json').read_text()).get('noc_l2_auth.sv', {})
    cur = hashlib.sha256((P.D / 'noc_l2_auth.sv').read_bytes()).hexdigest()
    if prov.get('base') != P.BASE_SHA or prov.get('variant') != cur: f.append('provenance mismatch')
    if cur == P.BASE_SHA: f.append('trimmed file equals the pre-trim file (no trim applied)')
    for x in f: print('FAIL', x)
    if f: print('L2TRIM_VARIANT: FAIL'); sys.exit(1)
    print(f'L2TRIM_VARIANT: PASS (base {P.BASE_SHA[:12]} variant {cur[:12]})')
if __name__ == '__main__': main()
