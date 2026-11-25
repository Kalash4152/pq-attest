"""Scratch-only preparation. Never copies design files back to the production repository."""
import hashlib,json,random,sys
from pathlib import Path
R=Path(__file__).resolve().parent
sys.path.insert(0,str(R/'scripts'))
from rv32_asm import assemble

p=R/'sw/riscv/demo_fw_v2.S';t=p.read_text()
t=t.replace('# Revision 9 qualified demo, separate from historical demo_fw.S.','# Revision 10 scratch demo; whole-IMEM measurement.')
t=t.replace('# IRQ3 handler returns through PicoRV32 retirq; all polling loops are bounded.','# IRQ3 returns through retirq; grant wait bounded, button waits unbounded.')
t=t.replace('        li s4,0x0FFFFFFF\n','')
for label in ['wait_revoke','wait_again']:
    a='        addi s4,s4,-1\n        bnez s4,'+label+'\n        j failed'
    assert t.count(a)==1
    t=t.replace(a,'        j '+label)
(R/'sw/riscv/demo_fw_v3.S').write_text(t)
words,_=assemble(t);assert len(words)<=4096
words+= [0]*(4096-len(words))
(R/'sw/riscv/demo_fw_v3.hex').write_text('@00000000\n'+''.join(f'{w:08X}\n' for w in words))
rng=random.Random(0x523130)
images=[words,[0]*4096,[rng.getrandbits(32) for _ in range(4096)]]
out=R/'trial_unit';out.mkdir(exist_ok=False)
expected=[]
for i,image in enumerate(images):
    (out/f'image{i}.hex').write_text(''.join(f'{w:08x}\n' for w in image))
    digest=hashlib.sha3_256(b''.join(w.to_bytes(4,'little') for w in image)).digest()
    expected.append(int.from_bytes(digest,'little'))
(out/'digests.svh').write_text('localparam logic [255:0] EXPECTED [0:2]=\'{'+
    ','.join(f"256'h{n:064x}" for n in expected)+'};\n')
(out/'reference.json').write_text(json.dumps(dict(hash='hashlib.sha3_256',bytes=16384,
    images=['padded firmware v3','all zero','seeded random'],digest_sv_le=[f'{x:064x}' for x in expected]),indent=2)+'\n')
p=R/'rtl/riscv/cpu_tile_noc.sv';t=p.read_text()
a='    parameter integer      IMEM_WORDS       = 4096,'
assert t.count(a)==1
t=t.replace(a,"    parameter bit          WHOLE_IMEM_MEASUREMENT = (TILE_ID==3),\n"+a)
a='    meas_window_reader #(.MEAS_BASE(MEAS_BASE)) u_meas ('
assert t.count(a)==1
pos=t.index(a);tail=t[pos:t.index('\nendmodule',pos)]
new=tail.replace(a,'      meas_imem_hasher #(.MEAS_BASE(MEAS_BASE)) u_meas (')
t=t[:pos]+"    generate if(WHOLE_IMEM_MEASUREMENT)begin:g_full\n"+new+"\n    end else begin:g_window\n"+tail+"\n    end endgenerate\nendmodule\n"
p.write_text(t)
p=R/'scripts/make_merged_sources.py';t=p.read_text()
t=t.replace("'meas_window_reader.sv', 'cpu_tile_noc.sv'","'meas_window_reader.sv', 'meas_imem_hasher.sv', 'cpu_tile_noc.sv'")
t=t.replace("MEM_INIT_FILES = ['sw/riscv/demo_fw_v2.hex']","MEM_INIT_FILES = ['sw/riscv/demo_fw_v3.hex']")
p.write_text(t)
p=R/'synth/merged/pq_merged_board_top.sv';t=p.read_text();assert 'demo_fw_v2.hex' in t
p.write_text(t.replace('demo_fw_v2.hex','demo_fw_v3.hex'))
print('SCRATCH_PREPARED images=3 bytes_per_image=16384; trial CPU3 whole-IMEM, CPU0 legacy reader')
