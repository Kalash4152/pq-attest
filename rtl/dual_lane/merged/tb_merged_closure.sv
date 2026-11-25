`timescale 1ns/1ps
// Fourteen revision-9 merged lifecycle checks, frozen before registration.
module tb_merged_closure;
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
  `include "demo_fw_v2.svh"
  `include "closure_profile.svh"
  // python scripts/merged_provision.py --words sw/riscv/demo_fw.hex (2026-11-07)
  localparam logic [255:0] FW_APPROVED_MEAS = 256'h9ef8549424ebdaca3d4b8c193d49c67d9f095abca8ec6abeb186095d4a399a89;
  localparam logic [775:0] FW_EXPECTED_RESPONSE = 776'hcd746c32ab3de6017a852e86e6b98bd33d19bd3bb8734e484d7d2c633b23bdca9ef8549424ebdaca3d4b8c193d49c67d9f095abca8ec6abeb186095d4a399a890f0e0d0c0b0a09080706050403020100313030305f48434f504533305f454c4954;
  localparam int BIT_CLKS = 50_000_000 / 115200;

  pq_soc_merged_core #(.VERIFIER_TIMEOUT(20000), .CPU_BUILD_ID(CLOSURE_BUILD_ID)) dut(
    .clk, .rst, .start_attestation, .revoke, .trusted_clear(1'b0), .boot_epoch, .attest_epoch, .nonce, .root_secret,
    .approved_measurement, .directed_keys({KEYS[(3*6+4)*256 +: 256], KEYS[(4*6+3)*256 +: 256]}),
    .context_in, .context_len, .config_data, .authorized, .rot_busy, .grant_done, .attestation_failed, .memory_commits,
    .gate_faults, .fault_sticky, .fault_reason, .endpoint_response, .cpu_uart_tx(uart), .cpu_gpio(gpio));

  initial for (int k = 0; k < DEMO_FW_V2_N; k++) begin
    dut.u_cpu_a.u_mem.imem_inst.mem[k] = DEMO_FW_V2[k]; dut.u_cpu_b.u_mem.imem_inst.mem[k] = DEMO_FW_V2[k];
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
  bit terminal_fail=0;
  always @(posedge clk) if(!rst && attestation_failed)terminal_fail=1;
  int unsafe_writes=0;
  always @(posedge clk) if(!rst && dut.mem_en && |dut.mem_we && !authorized[3])unsafe_writes++;
  initial begin
    int n;
    $display("CONFIG: TOP=tb_merged_closure CHECKS=14 FW=demo_fw_v2");
    load_d2(0);boot_epoch=BOOT;config_data=CLOSURE_CONFIG;approved_measurement=CLOSURE_MEAS;
    repeat(8)@(negedge clk);rst=0;repeat(60)@(negedge clk);
    check(dut.c_meas_valid[0] && dut.c_meas[0]===CLOSURE_IMEM,"MC_MEASURED_BOOT");
    check(config_data[63:32]==dut.u_cpu_a.BUILD_ID && config_data[31:0]==3,"MC_CONFIG_BINDING");
    start_attestation=1;@(negedge clk);start_attestation=0;
    n=0;while(!authorized[3] && n<200000 && !terminal_fail)begin @(negedge clk);n++;end
    check(endpoint_response===CLOSURE_RESPONSE,"MC_RESPONSE");
    check(authorized[3],"MC_GRANT");
    n=0;while((gpio[0][3:0]!==1 || gpio[1][3:0]!==2) && n<600000 && !terminal_fail)begin @(negedge clk);n++;end
    // Keep the independent never-authorized CPU observable even if attestation fails.
    if(terminal_fail)begin
      n=0;while(!rx_contains(1,"PASS T0 REFUSED OK\n") && n<200000)begin repeat(100)@(negedge clk);n+=100;end
    end
    check(gpio[0][3:0]===1,"MC_CPU_A_SUCCESS");
    check(!authorized[0] && gpio[1][3:0]===2,"MC_CPU_B_REFUSED");
    check(memory_commits==1,"MC_INITIAL_COMMITS");
    check(dut.u_bram.mem[64]===32'hc0de5a5a,"MC_MEMORY_VALUE");
    revoke=1;@(negedge clk);revoke=0;
    n=0;while(gpio[0][3:0]!==5 && n<600000 && !terminal_fail)begin @(negedge clk);n++;end
    check(!authorized[3] && gpio[0][3:0]===5,"MC_REAL_CPU_POST_REVOKE");
    check(memory_commits==1 && unsafe_writes==0 && dut.u_cpu_a.u_bridge.refused_count_o==2,"MC_NO_REVOKED_SIDE_EFFECT");
    start_attestation=1;@(negedge clk);start_attestation=0;
    n=0;while(gpio[0][3:0]!==7 && n<600000 && !terminal_fail)begin @(negedge clk);n++;end
    check(authorized[3] && gpio[0][3:0]===7,"MC_REATTEST_RECOVERY");
    check(memory_commits==2 && unsafe_writes==0,"MC_RECOVERY_COMMITS");
    n=0;while(!rx_contains(0,"PASS T3 RECOVERED\n") && n<300000 && !terminal_fail)begin repeat(100)@(negedge clk);n+=100;end
    $display("MC_UART_HEX A=%s B=%s",rx_hex(0),rx_hex(1));
    check(rx_contains(0,"PASS T3 cycles=") && rx_contains(0,"PASS T3 REVOKED\n") && rx_contains(0,"PASS T3 RECOVERED\n"),"MC_CPU_A_UART");
    check(rx_contains(1,"PASS T0 REFUSED OK\n"),"MC_CPU_B_UART");
    $display("CHECKS : %0d",checks);$display("ERRORS : %0d",errors);$display("RESULT : %s",errors==0 && checks==14?"PASS":"FAIL");$finish;
  end
  initial begin #80ms;$display("TB_TIMEOUT MC");$display("RESULT : FAIL");$finish;end
endmodule
