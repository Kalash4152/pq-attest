`timescale 1ns/1ps
// Fourteen revision-9 merged lifecycle checks, frozen before registration.
module tb_merged_inflight_v10;
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
  `include "closure_profile_v10.svh"
  // python scripts/merged_provision.py --words sw/riscv/demo_fw.hex (2026-11-07)
  localparam int BIT_CLKS = 50_000_000 / 115200;

  pq_soc_merged_core #(.VERIFIER_TIMEOUT(20000), .CPU_BUILD_ID(CLOSURE_BUILD_ID), .WHOLE_IMEM_MEASUREMENT(1'b1)) dut(
    .clk, .rst, .start_attestation, .revoke, .trusted_clear(1'b0), .boot_epoch, .attest_epoch, .nonce, .root_secret,
    .approved_measurement, .directed_keys({KEYS[(3*6+4)*256 +: 256], KEYS[(4*6+3)*256 +: 256]}),
    .context_in, .context_len, .config_data, .authorized, .rot_busy, .grant_done, .attestation_failed, .memory_commits,
    .gate_faults, .fault_sticky, .fault_reason, .endpoint_response, .cpu_uart_tx(uart), .cpu_gpio(gpio));

  initial for (int k = 0; k < DEMO_FW_V3_N; k++) begin
    dut.u_cpu_a.u_mem.imem_inst.mem[k] = DEMO_FW_V3[k]; dut.u_cpu_b.u_mem.imem_inst.mem[k] = DEMO_FW_V3[k];
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
  int unsafe=0,responses=0;bit seen_grant=0,drop_seen=0;
  always @(posedge clk)if(!rst)begin
    if(authorized[3])seen_grant=1;
    if(seen_grant && !authorized[3])drop_seen=1;
    if(dut.mem_en && |dut.mem_we && !authorized[3])unsafe++;
    if(dut.u_cpu_a.tmem_rvalid)responses++;
  end
  initial begin
    int n;bit active;
    $display("CONFIG: TOP=tb_merged_inflight_v10 CHECKS=6");
    load_d2(0);boot_epoch=BOOT;config_data=CLOSURE_CONFIG;approved_measurement=CLOSURE_MEAS;
    repeat(8)@(negedge clk);rst=0; n=0;while(!dut.c_meas_valid[0] && n<25000)begin @(negedge clk);n++;end
    check(dut.c_meas[0]===CLOSURE_IMEM,"IF_BOOT_PROFILE");
    start_attestation=1;@(negedge clk);start_attestation=0;
    n=0;while(dut.u_cpu_a.u_bridge.st!=3'd3 && n<100000)begin @(negedge clk);n++;end
    active=dut.u_cpu_a.u_bridge.st==3'd3 && authorized[3];
    check(active,"IF_ACCEPTED_HEAD_AT_REVOKE");
    revoke=1;@(negedge clk);revoke=0;
    n=0;while(authorized[3] && n<1500)begin @(negedge clk);n++;end
    repeat(2)@(negedge clk); // let the edge-sampled boundary monitor observe authorization-low
    check(drop_seen && !authorized[3] && n<1500,"IF_AUTH_BOUNDARY_BOUND");
    if(!authorized[3])begin
      n=0;while(gpio[0][3:0]!==5 && gpio[0][3:0]!==8 && n<400000)begin @(negedge clk);n++;end
    end
    check(drop_seen && unsafe==0 && memory_commits<=1,"IF_NO_COMMIT_AFTER_BOUNDARY");
    check(drop_seen && dut.u_cpu_a.u_bridge.refused_count_o>=1,"IF_LATER_CPU_ACCESS_REFUSED");
    check(drop_seen && responses>=1 && (gpio[0][3:0]===5 || gpio[0][3:0]===8),"IF_BOUNDED_CPU_OUTCOME");
    $display("CHECKS : %0d",checks);$display("ERRORS : %0d",errors);$display("RESULT : %s",errors==0 && checks==6?"PASS":"FAIL");$finish;
  end
  initial begin #20ms;$display("TB_TIMEOUT IF");$display("RESULT : FAIL");$finish;end
endmodule
