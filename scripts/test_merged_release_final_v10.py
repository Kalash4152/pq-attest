"""Negative tests for final result acceptance. No Vivado or board action."""
import copy
import hashlib
import tempfile
from pathlib import Path
import merged_release as m

def main():
    checks=0
    m.expected_source_paths=lambda: {'source.sv'}
    with tempfile.TemporaryDirectory() as t:
        root=Path(t);m.ROOT=root;m.RUNS=root/'runs';m.OUT=m.RUNS/'merged_board';m.OUT.mkdir(parents=True)
        m.LOCK=m.RUNS/'merged_release.lock'
        src=root/'source.sv';src.write_text('module top;endmodule')
        bit=m.OUT/'pq_merged_board_top.bit';bit.write_bytes(b'test image')
        good=dict(exit_code=0,gate='PASS',wns=0.1,whs=0.01,lut=35000,
                  bitstream_sha256=hashlib.sha256(bit.read_bytes()).hexdigest(),
                  source_manifest={'source.sv':hashlib.sha256(src.read_bytes()).hexdigest()})
        assert m.validate(good,m.OUT);checks+=1
        for field,value in [('exit_code',1),('gate','FAIL'),('wns',-1),('whs',-1),('wns',float('nan')),
                            ('wns',float('inf')),('wns','0.1'),('lut',47551),('lut',True),('source_manifest',{}),('source_manifest',{'other.sv':'hash'}),('source_manifest',{'source.sv':'hash','other.sv':'hash'}),
                            ('bitstream_sha256','wrong')]:
            rec=copy.deepcopy(good);rec[field]=value
            try:m.validate(rec,m.OUT)
            except ValueError:checks+=1
            else:raise AssertionError('accepted invalid '+field)
        bit.rename(bit.with_suffix('.saved'))
        try:m.validate(good,m.OUT)
        except ValueError:checks+=1
        else:raise AssertionError('accepted missing bitstream')
        bit.with_suffix('.saved').rename(bit)
        src.write_text('changed')
        try:m.validate(good,m.OUT)
        except ValueError:checks+=1
        else:raise AssertionError('accepted source drift')
        m.LOCK.write_text('{"pid": 0}')
        try:m.start()
        except SystemExit:checks+=1
        else:raise AssertionError('accepted lock overlap')
    src=['rtl/dual_lane/pq_noc_subsystem_p7_i9.sv','rtl/riscv/picorv32.v','rtl/riscv/cpu_tile_noc.sv','rtl/riscv/meas_imem_hasher.sv',
         'rtl/dual_lane/merged/pq_soc_merged_core.sv','synth/merged/pq_merged_board_top.sv']
    defs=['PQ_MAC_ON','CPU_TILE_MODULE=cpu_tile_noc','REAL_CPU_TILE'];mem=['sw/riscv/demo_fw_v3.hex']
    m.check_source_policy(src,src,defs,mem);checks+=1
    for use,canon,d,h in [(src[1:],src,defs,mem),(src+['synth/research/fixed.sv'],src+['synth/research/fixed.sv'],defs,mem),
                          (src,src,['PQ_MAC_ON','CPU_TILE_MODULE=cpu_tile_noc_stub','REAL_CPU_TILE'],mem),
                          (src,src,defs,['sw/riscv/demo_fw.hex'])]:
        try:m.check_source_policy(use,canon,d,h)
        except ValueError:checks+=1
        else:raise AssertionError('insecure source policy accepted')
    no_hasher=[s for s in src if not s.endswith('meas_imem_hasher.sv')]
    try:m.check_source_policy(no_hasher,no_hasher,defs,mem)
    except ValueError:checks+=1
    else:raise AssertionError('missing hasher was accepted')
    assert checks==23
    print('MERGED_RELEASE_TESTS_V10: PASS checks=23')
if __name__=='__main__':main()
