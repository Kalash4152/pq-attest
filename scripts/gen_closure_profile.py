"""Qualified revision-9 firmware/config profile; historical vectors remain immutable."""
import argparse
import hashlib
import json
from pathlib import Path
from rv32_asm import assemble
from s8_golden import compose

ROOT=Path(__file__).resolve().parents[1]
BUILD_ID=0x20261108

def products():
    src=ROOT/'sw/riscv/demo_fw_v2.S'
    words,_=assemble(src.read_text(encoding='utf-8'))
    image='@00000000\n'+''.join(f'{w:08X}\n' for w in words)
    imem=b''.join(w.to_bytes(4,'little') for w in words[:16])
    config=b''.join(w.to_bytes(4,'little') for w in (3,BUILD_ID,9,0))
    args=(b'TILE_03',b'EPOCH_0001',bytes(range(16)),bytes(range(32)),b'PQ-ATTEST-KDF',config,imem)
    ref={k:bytes.fromhex(v) for k,v in compose(*args).items()}
    if ref['measurement']!=hashlib.sha3_256(args[0]+config+imem).digest():raise ValueError('independent measurement mismatch')
    def sv(name,b):return f"localparam logic [{len(b)*8-1}:0] {name} = {len(b)*8}'h{int.from_bytes(b,'little'):0{len(b)*2}x};\n"
    include=f'localparam int DEMO_FW_V2_N = {len(words)};\nlocalparam logic [31:0] DEMO_FW_V2 [0:DEMO_FW_V2_N-1] = \'{{'+','.join(f"32'h{w:08x}" for w in words)+'};\n'
    profile=sv('CLOSURE_CONFIG',config+b'\0'*48)+sv('CLOSURE_IMEM',imem)+sv('CLOSURE_MEAS',ref['measurement'])+sv('CLOSURE_RESPONSE',ref['response'])+f"localparam logic [31:0] CLOSURE_BUILD_ID = 32'h{BUILD_ID:08x};\n"
    record={'profile':9,'tile':3,'build_id':f'{BUILD_ID:08x}','measurement_bytes':64,'config':config.hex(),'imem':imem.hex(),
            'measurement':ref['measurement'].hex(),'response':ref['response'].hex(),'firmware_sha256':hashlib.sha256(image.encode()).hexdigest(),
            'scope':'64-byte boot stub only; fixed demo keys and nonce; no full-firmware integrity claim'}
    return {'sw/riscv/demo_fw_v2.hex':image,'sim_riscv/include/demo_fw_v2.svh':include,
            'sw/riscv/closure_profile.svh':profile,'sim_riscv/include/closure_profile.svh':profile,
            'vectors/closure_profile_v9.json':json.dumps(record,indent=2)+'\n'}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true');a=ap.parse_args()
    for rel,text in products().items():
        p=ROOT/rel
        if a.check:
            if not p.is_file() or p.read_text(encoding='utf-8')!=text:raise SystemExit('profile drift: '+rel)
        else:p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text,encoding='utf-8',newline='\n')
    print('CLOSURE_PROFILE_V9: PASS (assembler, pinned reference, independent SHA3, exact generated files)')
if __name__=='__main__':main()
