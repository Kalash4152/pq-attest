"""Fail-closed detached merged build worker and result reader. No GUI child channels."""
import argparse
import ctypes
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
RUNS=ROOT/'NOC_PQATTEST.runs_merged'
OUT=RUNS/'merged_board'
LOCK=RUNS/'merged_release.lock'

def python_child(script,*args):
    # Vivado supplies its own Python 3.8 environment; ignore it in Python 3.13 children.
    return [sys.executable,'-E',str(script),*[str(arg) for arg in args]]

def check_source_policy(sources,canonical,defines,mem_init):
    required=['rtl/dual_lane/pq_noc_subsystem_p7_i9.sv','rtl/riscv/picorv32.v','rtl/riscv/cpu_tile_noc.sv','rtl/riscv/meas_imem_hasher.sv',
              'rtl/dual_lane/merged/pq_soc_merged_core.sv','synth/merged/pq_merged_board_top.sv']
    if sources!=canonical or any(sources.count(p)!=1 for p in required):raise ValueError('noncanonical combined secure source list')
    if any(p.startswith('synth/research/') or p.endswith('_stub.sv') for p in sources):raise ValueError('research or stub source in secure release')
    if set(defines)!={'PQ_MAC_ON','CPU_TILE_MODULE=cpu_tile_noc','REAL_CPU_TILE'}:raise ValueError('wrong secure release defines')
    if mem_init!=['sw/riscv/demo_fw_v3.hex']:raise ValueError('wrong secure release firmware')

def expected_source_paths():
    ref_zip=ROOT/'Pq_Attest_final.zip'
    if hashlib.sha256(ref_zip.read_bytes()).hexdigest()!='047bb5a981050f11a572a60e850f7c7511ff5d636f7903c6a8d239891003c6a0':
        raise ValueError('pinned reference ZIP identity mismatch')
    table=(ROOT/'scripts/merged_bitstream_sources.tcl').read_text()
    match=re.search(r'sources \{([^}]*)\}',table)
    if not match:raise ValueError('source table missing explicit closure')
    import make_merged_sources
    canonical,_=make_merged_sources.build()
    defs=re.search(r'defines \{([^}]*)\}',table)
    mem=re.search(r'mem_init \{([^}]*)\}',table)
    if not defs or not mem:raise ValueError('source table missing defines or firmware')
    check_source_policy(match.group(1).split(),canonical,defs.group(1).split(),mem.group(1).split())
    refs=['software/pq_attest_final/PQ_Attest/software/'+name+'.py' for name in
          ('keccak_ref','sha3_256_ref','kmac128_ref','measurement_ref','attestation_ref','attestation_protocol')]
    return set(match.group(1).split()+refs+['Pq_Attest_final.zip','scripts/merged_release.py','scripts/merged_bitstream_sources.tcl',
        'scripts/merged_bitstream_flow.tcl','scripts/merged_board_gate.tcl','scripts/s4_mesh_split.tcl',
        'scripts/check_closure_profile_v10.py','scripts/check_merged_board_profile_v10.py','scripts/gen_closure_profile_v10.py',
        'scripts/rv32_asm.py','scripts/s8_golden.py','sw/riscv/demo_fw_v3.S',
        'scripts/seed_campaign.py',
        'scripts/make_merged_sources.py','scripts/p7_bitstream_sources.tcl','scripts/prepare_i9.py',
        'sim_riscv/include/demo_fw_v3.svh','sim_riscv/include/closure_profile_v10.svh',
        'synth/s4/noc_mesh_3x2_bb.sv','synth/merged/pq_merged_board_arty.xdc',
        'sw/riscv/demo_fw_v3.hex','sw/riscv/closure_profile_v10.svh','vectors/closure_profile_v10.json'])

def atomic(p,obj):
    temp=p.with_suffix(p.suffix+'.tmp');temp.write_text(json.dumps(obj,indent=2)+'\n',encoding='utf-8');os.replace(temp,p)

def alive(pid):
    if not isinstance(pid,int) or pid<1:return False
    if os.name=='nt':
        kernel=ctypes.windll.kernel32
        kernel.OpenProcess.restype=ctypes.c_void_p
        h=kernel.OpenProcess(0x100000,False,pid)
        if not h:return False
        try:return kernel.WaitForSingleObject(ctypes.c_void_p(h),0)==258
        finally:kernel.CloseHandle(ctypes.c_void_p(h))
    try:os.kill(pid,0);return True
    except ProcessLookupError:return False

def validate(record,base):
    if record.get('exit_code')!=0:raise ValueError('build child did not exit successfully')
    if record.get('gate')!='PASS':raise ValueError('full implementation gate did not pass')
    for k in ('wns','whs'):
        v=record.get(k)
        if isinstance(v,bool) or not isinstance(v,(float,int)) or not math.isfinite(v) or v<0:raise ValueError('invalid '+k)
    lut=record.get('lut')
    if isinstance(lut,bool) or not isinstance(lut,int) or not 0<lut<=47550:raise ValueError('invalid or over-gate LUT count')
    p=base/'pq_merged_board_top.bit'
    if not p.is_file() or not p.stat().st_size:raise ValueError('bitstream missing or empty')
    if hashlib.sha256(p.read_bytes()).hexdigest()!=record.get('bitstream_sha256'):raise ValueError('bitstream hash mismatch')
    if not record.get('source_manifest'):raise ValueError('source manifest missing')
    if set(record['source_manifest'])!=expected_source_paths():raise ValueError('incomplete or unexpected source closure')
    for rel,h in record['source_manifest'].items():
        p=ROOT/rel
        if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=h:raise ValueError('source drift: '+rel)
    return True

def start():
    RUNS.mkdir(exist_ok=True)
    if (ROOT/'automation/dual_lane.lock').exists():raise SystemExit('REFUSED: harness run lock exists; finish/adjudicate it first')
    if LOCK.exists():
        raise SystemExit('REFUSED: build lock exists; inspect the current or interrupted build before retrying')
    with LOCK.open('x') as f:json.dump({'pid':os.getpid(),'state':'starting'},f)
    try:
        log=(RUNS/'merged_worker.log').open('ab')
        p=subprocess.Popen(python_child(Path(__file__).resolve(),'worker'),cwd=ROOT,
                           stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,
                           creationflags=0x08000000 if os.name=='nt' else 0)
        log.close()
        # Worker owns the lock before launching Vivado; parent never overwrites its PID.
        print(f'MERGED BUILD STARTED worker={p.pid}; use merged_result for the gated outcome')
    except BaseException:
        LOCK.unlink(missing_ok=True);raise

def worker():
    atomic(LOCK,{'pid':os.getpid(),'state':'building'})
    record={'exit_code':None,'gate':'FAIL'}
    try:
        if OUT.exists():OUT.rename(RUNS/('merged_board_prev_'+dt.datetime.now().strftime('%Y%m%d_%H%M%S')))
        OUT.mkdir()
        for checker in ('check_closure_profile_v10.py','check_merged_board_profile_v10.py'):
            subprocess.run(python_child(ROOT/'scripts'/checker),cwd=ROOT,check=True,timeout=120)
        deps=sorted(expected_source_paths())
        manifest={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in deps}
        atomic(OUT/'source_manifest.json',manifest)
        from seed_campaign import run
        run(['C:/xilinx_vivado/Vivado/2024.1/bin/vivado.bat','-mode','batch','-nojournal',
             '-log',str(OUT/'vivado.log'),'-source',str(ROOT/'scripts/merged_bitstream_flow.tcl'),
             '-tclargs','merged_board'],OUT,OUT/'stdout.txt',7200)
        code=0
        record={'exit_code':code,'gate':'FAIL','source_manifest':manifest}
        if code==0:
            if re.search(r'^CRITICAL WARNING:',(OUT/'vivado.log').read_text(errors='replace'),re.M):raise ValueError('critical warning in final build')
            g=(OUT/'gate_summary.txt').read_text()
            if not re.search(r'^VERDICT PASS(?: |$)',g,re.M):raise ValueError('gate missing PASS')
            bit=OUT/'pq_merged_board_top.bit'
            record.update(gate='PASS',lut=int(re.search(r'^MG_LUT=(\d+)$',g,re.M).group(1)),
                          wns=float(re.search(r'^MG_WNS=(\S+)$',g,re.M).group(1)),
                          whs=float(re.search(r'^MG_WHS=(\S+)$',g,re.M).group(1)),
                          bitstream_sha256=hashlib.sha256(bit.read_bytes()).hexdigest())
            validate(record,OUT)
        atomic(OUT/'release_result.json',record)
    except BaseException as e:
        record.update(gate='FAIL',error=str(e));OUT.mkdir(exist_ok=True);atomic(OUT/'release_result.json',record)
    finally:
        (OUT/'done.txt').write_text('exit '+str(record.get('exit_code'))+'\n')
        LOCK.unlink(missing_ok=True)

def result():
    if LOCK.exists():
        owner=json.loads(LOCK.read_text())
        if alive(owner.get('pid')):print('MERGED BUILD RUNNING: '+str(OUT/'stdout.txt'));return
        raise SystemExit('FAILED: stale worker lock; inspect worker/build logs')
    p=OUT/'release_result.json'
    if not p.is_file():raise SystemExit('NOT VERIFIED: no gated release result; existing legacy images are not reclassified')
    rec=json.loads(p.read_text())
    try:validate(rec,OUT)
    except (ValueError,OSError) as e:raise SystemExit('FAILED: '+str(e))
    print(f"MERGED RELEASE PASS: LUT {rec['lut']}, WNS {rec['wns']}, WHS {rec['whs']}; SHA256 {rec['bitstream_sha256']}")

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['start','worker','result']);a=ap.parse_args()
    {'start':start,'worker':worker,'result':result}[a.action]()
