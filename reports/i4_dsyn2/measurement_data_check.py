"""D-SYN-2 data check: every (tile_id, config_len, imem_len) the frozen golden vectors and the teammate ZIP examples
feed to the measurement. The ZIP runs in a disposable copy with measure_tile instrumented (the ZIP is never modified)."""
import json, runpy, shutil, sys, tempfile, io, contextlib, collections
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
rows = []
def add(src, tile, c, m): rows.append(dict(source=src, tile=tile.hex() if isinstance(tile, bytes) else tile, config_len=c, imem_len=m))
h = bytes.fromhex
for v in json.loads((ROOT / 'vectors/s8_golden.json').read_text())['vectors']:
    add('s8_golden (also py_rtl_profile_32)', h(v['tile']), len(h(v['config'])), len(h(v['imem'])))
fc = json.loads((ROOT / 'vectors/full_chain.json').read_text())
for k, v in (fc.items() if isinstance(fc, dict) else []):
    pass
def walk(o, src):
    if isinstance(o, dict):
        cfg = next((o[k] for k in ('config', 'config_data', 'config_hex') if k in o and isinstance(o[k], str)), None)
        im = next((o[k] for k in ('imem', 'imem_data', 'imem_hex') if k in o and isinstance(o[k], str)), None)
        if cfg is not None and im is not None:
            add(src, o.get('tile', o.get('tile_id', '?')), len(h(cfg)), len(h(im)))
        for x in o.values(): walk(x, src)
    elif isinstance(o, list):
        for x in o: walk(x, src)
walk(fc, 'full_chain')
walk(json.loads((ROOT / 'vectors/endpoint_golden.json').read_text()), 'endpoint_golden')
cm = bytes(range(16)); im = bytes(range(16, 32))   # legacy pq_measurement_tb M01..M06 (s8_golden.compatibility)
for t, c, m in [(b'TILE_01', 16, 16), (b'TILE_02', 16, 16), (b'TILE_01', 16, 16), (b'TILE_01', 16, 16), (b'TILE_01', 0, 0), (b'TILE_01', 64, 64)]:
    add('legacy pq_measurement_tb', t, c, m)
src = ROOT / 'software/pq_attest_final/PQ_Attest/software'
with tempfile.TemporaryDirectory() as td:
    d = Path(td) / 'sw'; shutil.copytree(src, d); sys.path.insert(0, str(d))
    import measurement_ref as M
    orig = M.measure_tile; cur = ['?']
    def rec(tile_id, config, imem): add('ZIP ' + cur[0], tile_id, len(config), len(imem)); return orig(tile_id, config, imem)
    M.measure_tile = rec
    for f in sorted(p.name for p in d.glob('*.py')):
        if f in ('measurement_ref.py',) or not f.endswith('.py'): continue
        cur[0] = f
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                runpy.run_path(str(d / f), run_name='__main__')
        except SystemExit: pass
        except Exception as e: add('ZIP ' + f + ' (error ' + type(e).__name__ + ')', '-', -1, -1)
    cur[0] = 'measurement_ref.py'
    with contextlib.redirect_stdout(io.StringIO()): M.run_test_vectors()
by = collections.defaultdict(set)
for r in rows:
    if r['config_len'] >= 0: by[r['tile']].add((r['config_len'], r['imem_len']))
layouts = {(r['config_len'], r['imem_len']) for r in rows if r['config_len'] >= 0}
out = dict(rows=rows, distinct_layouts=sorted(layouts), tiles_with_multiple_layouts={t: sorted(v) for t, v in by.items() if len(v) > 1},
           single_fixed_layout=len(layouts) == 1, per_tile_fixed=all(len(v) == 1 for v in by.values()))
(ROOT / 'reports/i4_dsyn2/measurement_data_check.json').write_text(json.dumps(out, indent=1) + '\n', encoding='utf-8', newline='\n')
print('rows', len(rows)); print('distinct layouts', sorted(layouts)); print('single fixed layout', out['single_fixed_layout'], '| per-tile fixed', out['per_tile_fixed'])
print('sources', collections.Counter(r['source'] for r in rows))
print('tiles with >1 layout', {t: sorted(v) for t, v in by.items() if len(v) > 1})
