"""Create versioned rev-10 benches; retain every old check and all historical vectors."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
D=ROOT/'rtl/dual_lane/merged'

def replace_once(t,a,b):
    if t.count(a)!=1:raise ValueError('nonunique bench anchor: '+a[:100])
    return t.replace(a,b)

for old in ['tb_merged_closure','tb_merged_inflight','tb_merged_contention','tb_merged_error','tb_merged_phase_sweep','tb_matched_memory']:
    t=(D/(old+'.sv')).read_text();new=old+'_v10'
    t=t.replace(old,new).replace('demo_fw_v2.svh','demo_fw_v3.svh').replace('DEMO_FW_V2','DEMO_FW_V3')
    t=t.replace('FW=demo_fw_v2','FW=demo_fw_v3')
    t=replace_once(t,'.CPU_BUILD_ID(CLOSURE_BUILD_ID))','.CPU_BUILD_ID(CLOSURE_BUILD_ID), .WHOLE_IMEM_MEASUREMENT(1\'b1))')
    prof='closure_profile_v10.svh'
    if old=='tb_merged_error':prof='closure_error_v10.svh'
    if old=='tb_merged_contention':
        t=t.replace('contention_fw.svh','contention_fw_v10.svh');prof='closure_contention_v10.svh'
    if old in ['tb_matched_memory','tb_merged_phase_sweep']:
        t=t.replace('matched_memory_fw.svh','matched_memory_fw_v10.svh');prof='closure_matched_v10.svh'
    t=t.replace('"closure_profile.svh"','"'+prof+'"')
    for name in ['FW_APPROVED_MEAS','FW_EXPECTED_RESPONSE']:
        if t.count(name)==1:
            t='\n'.join(line for line in t.split('\n') if name not in line)
    t=t.replace('Revision-9 qualified config','Revision-10 qualified config')
    t=t.replace('Change only the unmeasured application address, not the measured boot stub.',
                'Select the independently approved error-workload image before full-IMEM measurement.')
    if old!='tb_merged_phase_sweep':
        t=replace_once(t,'rst=0;repeat(60)@(negedge clk);',
            'rst=0; n=0;while(!dut.c_meas_valid[0] && n<25000)begin @(negedge clk);n++;end')
    else:
        # Exclude measurement from the measured RoT start-to-grant interval, as the original collector promises.
        t=replace_once(t,'    start_cycle=cycle_count;start_attestation=1;',
            '    n=0;while(!dut.c_meas_valid[0] && n<25000)begin @(negedge clk);n++;end\n'
            '    start_cycle=cycle_count;start_attestation=1;')
    if old=='tb_merged_closure':
        a='    check(config_data[63:32]==dut.u_cpu_a.BUILD_ID && config_data[31:0]==3,"MC_CONFIG_BINDING");\n'
        t=replace_once(t,a,'')
        a='    check(endpoint_response===CLOSURE_RESPONSE,"MC_RESPONSE");'
        t=replace_once(t,a,'    // DUT-observed measurement binds the independently generated config/image preimage.\n'
            '    check(endpoint_response[519:264]===CLOSURE_MEAS,"MC_CONFIG_BINDING");\n'+a)
    (D/(new+'.sv')).write_text(t,encoding='utf-8',newline='\n')

# Decoder unit: original twelve unchanged conditions, plus seven instruction-fetch conditions.
t=(ROOT/'sim_riscv/tb_addr_decode_v2.sv').read_text().replace('tb_addr_decode_v2','tb_addr_decode_v10')
t=t.replace('CHECKS=12','CHECKS=19').replace('checks == 12','checks == 19')
at='    repeat (5) @(negedge clk_i);'
extra='''    local_is_fetch_i=1;
    access(32'h00000040,0,0,0,rd,err,rvg);
    check(!err && rd==32'h10000010,"DEC_FETCH_IMEM_ALLOWED");
    d0=dmem_acc;
    access(32'h00004000,0,0,0,rd,err,rvg);
    check(err && !rvg && dmem_acc==d0,"DEC_FETCH_DMEM_FIRST_DENIED");
    access(32'h00007ffc,0,0,0,rd,err,rvg);
    check(err && !rvg && dmem_acc==d0,"DEC_FETCH_DMEM_LAST_DENIED");
    access(32'h10000004,0,0,0,rd,err,rvg);
    check(err && !rvg,"DEC_FETCH_UART_DENIED");
    access(32'h10001004,0,0,0,rd,err,rvg);
    check(err && !rvg,"DEC_FETCH_GPIO_DENIED");
    access(32'h1000200c,0,0,0,rd,err,rvg);
    check(err && !rvg,"DEC_FETCH_STATUS_DENIED");
    access(32'h10003000,0,0,0,rd,err,rvg);
    check(err && !rvg,"DEC_FETCH_NI_DENIED");
    local_is_fetch_i=0;
'''
t=replace_once(t,at,extra+at)
(ROOT/'sim_riscv/tb_addr_decode_v10.sv').write_text(t,encoding='utf-8',newline='\n')

# Real CPU counterexample becomes a NEW acceptance bench. Historical GAP_CONFIRMED bench is untouched.
t=(ROOT/'sim_riscv/tb_r10_mmio_fetch.sv').read_text().replace('tb_r10_mmio_fetch','tb_r10_mmio_guard')
t=t.replace('bit fetched=0,data_seen=0,executed=0;','bit fetched=0,data_seen=0,executed=0,fault_seen=0;')
t=t.replace('  always @(posedge clk) if(!rst) begin',
    '  always @(posedge clk) if(!rst) begin\n'
    "    if(dut.u_tile.bus_fault && dut.u_tile.fault_addr==32'h1000200c)fault_seen=1;")
t=t.replace('check(fetched,"MMIO_INSTRUCTION_FETCH_ACCEPTED");','check(fetched && fault_seen,"MMIO_GUARD_FAULT");')
t=t.replace('check(data_seen,"MMIO_RETURNS_BUILD_ID");','check(!data_seen,"MMIO_GUARD_NO_DATA");')
t=t.replace('check(executed,"MMIO_COMPRESSED_INSTRUCTION_EXECUTED");','check(!executed,"MMIO_GUARD_NO_EXEC");')
(ROOT/'sim_riscv/tb_r10_mmio_guard.sv').write_text(t,encoding='utf-8',newline='\n')
print('R10_BENCH_PREPARED: lifecycle=14 inflight=6 contention=8 error=6 phase=56 matched=8 decoder=19 cpu_guard=3')
