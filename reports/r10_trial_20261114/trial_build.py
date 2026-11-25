"""Scratch full implementation trial; uses the release recipe, never a releasable image."""
import hashlib,json,sys,time
from pathlib import Path
R=Path(__file__).resolve().parent
sys.path.insert(0,str(R/'scripts'))
from seed_campaign import BIN,run,system_awake
paths=['rtl/riscv/meas_imem_hasher.sv','rtl/riscv/cpu_tile_noc.sv','rtl/riscv/addr_decode.sv',
    'sw/riscv/demo_fw_v3.S','sw/riscv/demo_fw_v3.hex','scripts/make_merged_sources.py',
    'scripts/merged_bitstream_sources.tcl','scripts/merged_bitstream_flow.tcl',
    'synth/merged/pq_merged_board_top.sv','synth/merged/pq_merged_board_arty.xdc']
(R/'trial_build_sources.json').write_text(json.dumps({p:hashlib.sha256((R/p).read_bytes()).hexdigest() for p in paths},indent=2)+'\n')
start=time.time()
try:
    with system_awake():
        run([BIN/'vivado.bat','-mode','batch','-nojournal','-source',R/'scripts/merged_bitstream_flow.tcl',
            '-log',R/'trial_vivado.log','-tclargs','merged_board'],R,R/'trial_build_stdout.txt',7200)
except Exception as e:
    (R/'trial_build_result.json').write_text(json.dumps(dict(state='FAILED',error=str(e),seconds=time.time()-start),indent=2)+'\n')
    raise
summary=R/'NOC_PQATTEST.runs_merged/merged_board/gate_summary.txt'
text=summary.read_text()
if 'VERDICT PASS' not in text:raise RuntimeError('scratch gate did not pass')
(R/'trial_build_result.json').write_text(json.dumps(dict(state='SCRATCH_GATE_PASS',seconds=time.time()-start,
    gate_summary=text,scope='Trial only, old provisioned measurement constants; no bitstream written'),indent=2)+'\n')
print('SCRATCH_TRIAL: area/timing gate PASS; not a qualified release image')
