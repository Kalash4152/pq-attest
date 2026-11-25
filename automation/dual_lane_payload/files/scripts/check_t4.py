"""Registered job t4_variant (T4): the T4 router variants and their equivalence copies are byte-exact regenerations of their pinned sources.
Fails if a source changed since the provenance was written, if an on-disk variant was hand-edited, or if the
generator no longer reproduces it. Prints T4_VARIANT: PASS only when every check holds."""
import hashlib, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import prepare_t4 as g

def main():
    prov = json.loads((g.ROOT / g.D / 't4_provenance.json').read_text(encoding='utf-8'))['files']
    out, now = g.build(); bad = []
    if set(prov) != set(out): bad.append(f'provenance lists {sorted(prov)} but the generator makes {sorted(out)}')
    for dst, text in out.items():
        p = prov.get(dst, {})
        if p.get('source_sha256') != now[dst]['source_sha256']: bad.append(f'{dst}: source {now[dst]["source"]} changed since provenance')
        disk = (g.ROOT / dst).read_bytes()
        if disk != text.encode('utf-8'): bad.append(f'{dst}: on-disk file differs from the generator output')
        if p.get('output_sha256') != hashlib.sha256(disk).hexdigest(): bad.append(f'{dst}: on-disk hash differs from provenance')
        print(f'T4_FILE {dst} sha256={hashlib.sha256(disk).hexdigest()} from {now[dst]["source"]}')
    for b in bad: print('T4_VARIANT_FAIL', b)
    print('T4_VARIANT:', 'PASS' if not bad else 'FAIL')
    return 0 if not bad else 1

if __name__ == '__main__': sys.exit(main())
