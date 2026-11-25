`timescale 1ns/1ps
// Fourteen revision-9 merged lifecycle checks, frozen before registration.
module tb_merged_contention_v10;
  import noc_pkg::*;
  logic clk = 0, rst = 1, start_attestation = 0, revoke = 0;
  always #10 clk = ~clk;
  logic [79:0] boot_epoch, attest_epoch; logic [127:0] nonce; logic [255:0] root_secret, approved_measurement;
  logic [111:0] context_in; logic [3:0] context_len; logic [511:0] config_data, imem; logic [6:0] config_len, imem_len;
  logic [775:0] expected_response, endpoint_response;
  logic [5:0] authorized; logic rot_busy, grant_done, attestation_failed, fault_sticky; logic [3:0] fault_reason;
  logic [31:0] memory_commits; logic [5:0][31:0] gate_faults; logic [1:0] uart; logic [1:0][7:0] gpio;
  `include "full_chain.svh"
  `include "d2_k3_64.svh"
  `include "demo_fw_v3.svh"
  `include "contention_fw_v10.svh"
  `include "closure_contention_v10.svh"
  // python scripts/merged_provision.py --words sw/riscv/demo_fw.hex (2026-11-07)
  localparam int BIT_CLKS = 50_000_000 / 115200;

  pq_soc_merged_core #(.VERIFIER_TIMEOUT(20000), .CPU_BUILD_ID(CLOSURE_BUILD_ID), .WHOLE_IMEM_MEASUREMENT(1'b1)) dut(
    .clk, .rst, .start_attestation, .revoke, .trusted_clear(1'b0), .boot_epoch, .attest_epoch, .nonce, .root_secret,
    .approved_measurement, .directed_keys({KEYS[(3*6+4)*256 +: 256], KEYS[(4*6+3)*256 +: 256]}),
    .context_in, .context_len, .config_data, .authorized, .rot_busy, .grant_done, .attestation_failed, .memory_commits,
    .gate_faults, .fault_sticky, .fault_reason, .endpoint_response, .cpu_uart_tx(uart), .cpu_gpio(gpio));

  initial begin
    dut.u_cpu_a.u_mem.dmem_inst.mem[0]=0;
    dut.u_cpu_a.u_mem.dmem_inst.mem[1]=0;
    for(int k=0;k<CONTENTION_FW_N;k++)dut.u_cpu_a.u_mem.imem_inst.mem[k]=CONTENTION_FW[k];
    for(int k=0;k<DEMO_FW_V3_N;k++)dut.u_cpu_b.u_mem.imem_inst.mem[k]=DEMO_FW_V3[k];
  end

  logic [7:0] rxb [2][0:255]; int rxn [2] = '{0, 0};
  for (genvar g = 0; g < 2; g++) begin : ur
    initial begin
      wait (!rst);
      forever begin
        logic [7:0] ch;
        @(negedge uart[g]);
        repeat (BIT_CLKS + BIT_CLKS / 2) @(posedge clk);
        for (int b = 0; b < 8; b++) begin ch[b] = uart[g]; repeat (BIT_CLKS) @(posedge clk); end
        if (rxn[g] < 256) rxb[g][rxn[g]] = ch;
        rxn[g]++;
      end
    end
  end
  function automatic bit rx_is(input int g, input string exp);
    if (rxn[g] != exp.len()) return 0;
    for (int i = 0; i < exp.len(); i++) if (rxb[g][i] !== exp.getc(i)) return 0;
    return 1;
  endfunction
  function automatic string rx_hex(input int g);
    string o = ""; for (int i = 0; i < rxn[g] && i < 256; i++) o = {o, $sformatf("%02h", rxb[g][i])}; return o;
  endfunction

  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++; if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask

  function automatic bit rx_contains(input int g,input string exp);
    for(int i=0;i+exp.len()<=rxn[g] && i+exp.len()<=256;i++)begin
      bit ok;ok=1;
      for(int k=0;k<exp.len();k++)if(rxb[g][i+k]!==exp.getc(k))ok=0;
      if(ok)return 1;
    end
    return 0;
  endfunction
  int reqs=0,resps=0,overlap=0;bit phase2=0,failed_seen=0;
  always @(posedge clk) if(!rst) begin
    if(dut.u_cpu_a.tmem_req && dut.u_cpu_a.tmem_gnt)reqs++;
    if(dut.u_cpu_a.tmem_rvalid)resps++;
    if(phase2 && rot_busy && dut.c_valid[0] && dut.app_ready[3])overlap++;
    if(attestation_failed)failed_seen=1;
  end
  initial begin
    int n,c0,rounds;bit second_done;
    $display("CONFIG: TOP=tb_merged_contention_v10 CHECKS=8");
    load_d2(0);boot_epoch=BOOT;config_data=CLOSURE_CONFIG;approved_measurement=CLOSURE_MEAS;
    repeat(8)@(negedge clk);rst=0; n=0;while(!dut.c_meas_valid[0] && n<25000)begin @(negedge clk);n++;end
    check(dut.c_meas[0]===CLOSURE_IMEM,"CT_BOOT_PROFILE");
    start_attestation=1;@(negedge clk);start_attestation=0;
    n=0;while(!authorized[3] && n<100000)begin @(negedge clk);n++;end
    check(authorized[3],"CT_FIRST_GRANT");
    n=0;while(memory_commits<2 && n<100000)begin @(negedge clk);n++;end
    c0=memory_commits;phase2=1;start_attestation=1;@(negedge clk);start_attestation=0;
    second_done=0;n=0;while(!second_done && n<100000)begin @(negedge clk);if(grant_done)second_done=1;n++;end
    check(second_done && !failed_seen && endpoint_response===CLOSURE_RESPONSE,"CT_SECOND_ATTESTATION");
    check(overlap>0,"CT_CPU_AND_ATTESTATION_OVERLAP");
    check(memory_commits>c0,"CT_TRAFFIC_PROGRESS_WHILE_BUSY");
    dut.u_cpu_a.u_mem.dmem_inst.mem[1]=1;
    n=0;while(gpio[0][3:0]!==1 && gpio[0][3:0]!==8 && n<100000)begin @(negedge clk);n++;end
    rounds=dut.u_cpu_a.u_mem.dmem_inst.mem[0];
    check(gpio[0][3:0]===1 && rounds>=2,"CT_CPU_FINISHES");
    check(reqs==2*rounds && resps==reqs && memory_commits==rounds,"CT_EXACT_ACCOUNTING");
    check(dut.u_bram.mem[64]===32'(rounds) && !dut.u_cpu_a.u_tile.tile_status_inst.bus_fault_q,"CT_DATA_AND_NO_FAULT");
    $display("CHECKS : %0d",checks);$display("ERRORS : %0d",errors);$display("RESULT : %s",errors==0 && checks==8?"PASS":"FAIL");$finish;
  end
  initial begin #20ms;$display("TB_TIMEOUT CT");$display("RESULT : FAIL");$finish;end
endmodule
