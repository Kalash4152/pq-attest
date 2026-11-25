`timescale 1ns/1ps
// Six checks, both reject-original-approval and approve-changed-image control.
module tb_merged_attack_v10;
  import noc_pkg::*;
  logic clk=0,rst=1,start_attestation=0,revoke=0;
  always #10 clk=~clk;
  logic [79:0] boot_epoch,attest_epoch;logic [127:0] nonce;logic [255:0] root_secret,approved_measurement;
  logic [111:0] context_in;logic [3:0] context_len;logic [511:0] config_data,imem;
  logic [6:0] config_len,imem_len;logic [775:0] expected_response,endpoint_response;
  logic [5:0] authorized;logic rot_busy,grant_done,attestation_failed,fault_sticky;
  logic [3:0] fault_reason;logic [31:0] memory_commits;logic [5:0][31:0] gate_faults;
  logic [1:0] uart;logic [1:0][7:0] gpio;
  `include "full_chain.svh"
  `include "d2_k3_64.svh"
  `include "demo_fw_v3.svh"
  `include "demo_fw_v3_attack.svh"
  generate if(1)begin:REF_MAIN
    `include "closure_profile_v10.svh"
  end if(1)begin:REF_ATTACK
    `include "closure_attack_v10.svh"
  end endgenerate
  pq_soc_merged_core #(.VERIFIER_TIMEOUT(20000),.CPU_BUILD_ID(32'h20261114),.WHOLE_IMEM_MEASUREMENT(1'b1)) dut(
    .clk,.rst,.start_attestation,.revoke,.trusted_clear(1'b0),.boot_epoch,.attest_epoch,.nonce,.root_secret,
    .approved_measurement,.directed_keys({KEYS[(3*6+4)*256 +: 256],KEYS[(4*6+3)*256 +: 256]}),
    .context_in,.context_len,.config_data,.authorized,.rot_busy,.grant_done,.attestation_failed,
    .memory_commits,.gate_faults,.fault_sticky,.fault_reason,.endpoint_response,
    .cpu_uart_tx(uart),.cpu_gpio(gpio));
  initial begin
    for(int k=0;k<4096;k++)begin
      dut.u_cpu_a.u_mem.imem_inst.mem[k]=DEMO_FW_V3_ATTACK[k];
      dut.u_cpu_b.u_mem.imem_inst.mem[k]=DEMO_FW_V3[k];
    end
  end
  bit failed_seen=0,granted_seen=0;int unsafe_writes=0,checks=0,errors=0;
  always @(posedge clk)if(!rst)begin
    if(attestation_failed)failed_seen=1;
    if(grant_done || authorized[3])granted_seen=1;
    if(dut.mem_en && |dut.mem_we && !authorized[3])unsafe_writes++;
  end
  task automatic check(input bit ok,input string name);
    checks++;if(ok)$display("[PASS] %s",name);else begin errors++;$display("[FAIL] %s",name);end
  endtask
  initial begin
    int n;
`ifdef R10_APPROVE_ATTACK
    $display("CONFIG: TOP=tb_merged_attack_v10 CHECKS=6 MODE=approve_changed");
`else
    $display("CONFIG: TOP=tb_merged_attack_v10 CHECKS=6 MODE=reject_changed");
`endif
    load_d2(0);boot_epoch=BOOT;config_data=REF_MAIN.CLOSURE_CONFIG;
`ifdef R10_APPROVE_ATTACK
    approved_measurement=REF_ATTACK.CLOSURE_MEAS;
`else
    approved_measurement=REF_MAIN.CLOSURE_MEAS;
`endif
    repeat(8)@(negedge clk);rst=0;
    n=0;while(!dut.c_meas_valid[0] && n<25000)begin @(negedge clk);n++;end
    check(dut.c_meas_valid[0] && dut.c_meas[0]===REF_ATTACK.CLOSURE_IMEM,"AT_MEASURE_CHANGED_IMAGE");
    check(dut.c_meas[0][255:0]!==REF_MAIN.CLOSURE_IMEM[255:0],"AT_CODE_BEYOND_64_BYTES_CHANGES_DIGEST");
    start_attestation=1;@(negedge clk);start_attestation=0;
    n=0;while(!failed_seen && !granted_seen && n<100000)begin @(negedge clk);n++;end
    check(endpoint_response===REF_ATTACK.CLOSURE_RESPONSE,"AT_INDEPENDENT_RESPONSE");
`ifdef R10_APPROVE_ATTACK
    check(granted_seen && authorized[3] && !failed_seen,"AT_CONTROL_GRANTED");
    n=0;while(memory_commits<1 && n<50000 && !failed_seen)begin @(negedge clk);n++;end
    check(memory_commits==1,"AT_CONTROL_MEMORY_COMMIT");
`else
    repeat(3000)@(negedge clk);
    check(failed_seen && !authorized[3] && !granted_seen,"AT_CHANGED_CODE_REJECTED");
    check(memory_commits==0,"AT_NO_UNAPPROVED_COMMIT");
`endif
    check(unsafe_writes==0 && !authorized[0],"AT_AUTHORIZATION_ENFORCED");
    $display("CHECKS : %0d",checks);$display("ERRORS : %0d",errors);
    $display("RESULT : %s",errors==0 && checks==6?"PASS":"FAIL");$finish;
  end
  initial begin #10ms;$display("TB_TIMEOUT ATTACK");$display("RESULT : FAIL");$finish;end
endmodule
