"""Generate NEW revision-10 artifacts; never rewrite historical revision-9 vectors."""
import argparse
import hashlib
import json
from pathlib import Path
import random
from rv32_asm import assemble
from s8_golden import compose

ROOT=Path(__file__).resolve().parents[1]
BUILD_ID=0x20261114
PINNED_ZIP='047bb5a981050f11a572a60e850f7c7511ff5d636f7903c6a8d239891003c6a0'

def sv(name,data):
    return f"localparam logic [{len(data)*8-1}:0] {name} = {len(data)*8}'h{int.from_bytes(data,'little'):0{len(data)*2}x};\n"

def padded(words):
    if not 0<len(words)<=4096:raise ValueError('firmware must fit the signed 4096-word IMEM')
    return list(words)+[0]*(4096-len(words))

def image_bytes(words):
    if len(words)!=4096:raise ValueError('whole IMEM must contain exactly 4096 defined words')
    return b''.join(w.to_bytes(4,'little') for w in words)

def field_for(words):
    return hashlib.sha3_256(image_bytes(words)).digest()+(16384).to_bytes(4,'little')+bytes(4)+bytes(24)

def profile(words):
    field=field_for(words)
    config=b''.join(w.to_bytes(4,'little') for w in (3,BUILD_ID,10,0))
    args=(b'TILE_03',b'EPOCH_0001',bytes(range(16)),bytes(range(32)),b'PQ-ATTEST-KDF',config,field)
    ref={k:bytes.fromhex(v) for k,v in compose(*args).items()}
    if ref['measurement']!=hashlib.sha3_256(args[0]+config+field).digest():
        raise ValueError('independent outer measurement mismatch')
    text=sv('CLOSURE_CONFIG',config+bytes(48))+sv('CLOSURE_IMEM',field)+sv('CLOSURE_MEAS',ref['measurement'])
    text+=sv('CLOSURE_RESPONSE',ref['response'])+f"localparam logic [31:0] CLOSURE_BUILD_ID = 32'h{BUILD_ID:08x};\n"
    record=dict(profile=10,tile=3,build_id=f'{BUILD_ID:08x}',measured_imem_bytes=16384,endpoint_field_bytes=64,
        inner_imem_sha3_256=field[:32].hex(),config=config.hex(),imem=field.hex(),
        measurement=ref['measurement'].hex(),response=ref['response'].hex(),
        image_sha256=hashlib.sha256(image_bytes(words)).hexdigest(),
        scope='Whole immutable IMEM at boot/request; successful local instruction fetches restricted to IMEM; demo keys/nonce')
    return text,record

def array(name,words):
    return (f'localparam int {name}_N = {len(words)};\n'
        f"localparam logic [31:0] {name} [0:{name}_N-1] = '{{"+
        ','.join(f"32'h{w:08x}" for w in words)+'};\n')

def products():
    if hashlib.sha256((ROOT/'Pq_Attest_final.zip').read_bytes()).hexdigest()!=PINNED_ZIP:
        raise ValueError('pinned reference ZIP mismatch')
    base,labels=assemble((ROOT/'sw/riscv/demo_fw_v3.S').read_text(encoding='utf-8-sig'))
    main=padded(base)
    # Change one executed instruction beyond the old 64-byte window. Its only functional effect
    # is adding 4096 to the still-bounded grant-loop budget; normal behavior remains possible.
    attack=list(main);index=labels['cpu_a']//4
    if index<16 or (attack[index]&0x7f)!=0x37 or ((attack[index]>>7)&31)!=20:
        raise ValueError('attack anchor is not the expected LUI s4 beyond 0x40')
    attack[index]^=0x1000
    error=list(main);error[22]=0x220049b7;error[23]=0x00098993
    workloads=[('demo_fw_v3','DEMO_FW_V3',main,'closure_profile_v10'),
        ('contention_fw_v10','CONTENTION_FW',padded(assemble((ROOT/'sw/riscv/contention_fw.S').read_text())[0]),'closure_contention_v10'),
        ('matched_memory_fw_v10','MATCHED_MEMORY_FW',padded(assemble((ROOT/'sw/riscv/matched_memory_fw.S').read_text())[0]),'closure_matched_v10'),
        ('demo_fw_v3_attack','DEMO_FW_V3_ATTACK',attack,'closure_attack_v10'),
        ('demo_fw_v3_error','DEMO_FW_V3_ERROR',error,'closure_error_v10')]
    result={}
    for stem,name,words,prof in workloads:
        hextext='@00000000\n'+''.join(f'{w:08X}\n' for w in words)
        result['sw/riscv/'+stem+'.hex']=hextext
        result['sim_riscv/include/'+stem+'.svh']=array(name,words)
        header,record=profile(words)
        record['firmware_sha256']=hashlib.sha256(hextext.encode()).hexdigest()
        if words is attack:record.update(changed_instruction_byte_address=index*4,
            original_word=f'{main[index]:08x}',changed_word=f'{attack[index]:08x}')
        result['sim_riscv/include/'+prof+'.svh']=header
        result['vectors/'+prof+'.json']=json.dumps(record,indent=2)+'\n'
        if prof=='closure_profile_v10':result['sw/riscv/closure_profile_v10.svh']=header
    rng=random.Random(0x523130);rand=[rng.getrandbits(32) for _ in range(4096)]
    digests=[hashlib.sha3_256(image_bytes(w)).digest() for w in (main,[0]*4096,rand)]
    result['sim_riscv/include/imem_hasher_v10_vectors.svh']=(
        "localparam logic [255:0] EXPECTED [0:2] = '{"+
        ','.join(f"256'h{int.from_bytes(d,'little'):064x}" for d in digests)+'};\n'+array('HASHER_RANDOM',rand))
    return result

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true');a=ap.parse_args()
    for rel,text in products().items():
        p=ROOT/rel
        if a.check:
            if not p.is_file() or p.read_text(encoding='utf-8')!=text:raise SystemExit('profile-10 drift: '+rel)
        else:
            p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text,encoding='utf-8',newline='\n')
    print('CLOSURE_PROFILE_V10: PASS (assembler, pinned reference, independent SHA3, exact generated files)')

if __name__=='__main__':main()
