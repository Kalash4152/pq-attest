import json,os,sys,subprocess
from pathlib import Path
R=Path(__file__).resolve().parent
sys.path.insert(0,str(R/'scripts'))
from seed_campaign import BIN,run,system_awake
from dual_lane_verify import judge

S='NOC_PQATTEST.srcs/sources_1/new/'
files=[S+'pq_keccak_pkg.sv',S+'SHA3_PKG.sv']+[S+'pq_keccak_'+s+'.sv' for s in ['theta','rho','pi','chi']]+[
    'rtl/dual_lane/pq_keccak_iota.sv',S+'pq_keccak_round.sv','rtl/dual_lane/pq_keccak_f1600.sv',
    'rtl/dual_lane/SHA3_PAD.sv',S+'SHA3_ABSORB.sv',S+'SHA3_256.sv',
    'rtl/riscv/meas_imem_hasher.sv','trial_unit_tb.sv']
out=R/'trial_unit'
(out/'compile.prj').write_text(''.join('sv xil_defaultlib "'+(R/f).as_posix()+'"\n' for f in files))
with system_awake():
    run([BIN/'xvlog.bat','--relax','-i',str(out),'-prj',out/'compile.prj'],out,out/'compile.log',180)
    run([BIN/'xelab.bat','--relax','--mt','2','--standalone','--debug','typical',
        'xil_defaultlib.tb_meas_imem_trial','-s','trial'],out,out/'elaborate.log',300)
    env=os.environ.copy();v=BIN.parent
    env['PATH']=os.pathsep.join([str(v/'lib/win64.o'),str(v/'lib/win64.o/Default'),
        str(v/'tps/mingw/6.2.0/win64.o/nt/x86_64-w64-mingw32/lib'),env.get('PATH','')])
    with (out/'simulate.log').open('wb') as f:
        p=subprocess.Popen([str(out/'xsim.dir/trial/axsim.exe')],cwd=out,env=env,
            stdin=subprocess.DEVNULL,stdout=f,stderr=subprocess.STDOUT,creationflags=0x08000000)
        try:code=p.wait(timeout=600)
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill.exe','/PID',str(p.pid),'/T','/F'],capture_output=True)
            raise RuntimeError('unit timeout; never a pass')
    if code:raise RuntimeError('unit simulator exit '+str(code))
    result=judge((out/'simulate.log').read_text(errors='replace'),
        dict(checks=9,config=dict(TOP='tb_meas_imem_trial',CHECKS=9)),
        {s:dict(exitCode=0,timedOut=False,interrupted=False) for s in ['compile','elaborate','simulate']},{},{})
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print('SCRATCH_UNIT: PASS images=3 checks=9 (not registered release evidence)',flush=True)
