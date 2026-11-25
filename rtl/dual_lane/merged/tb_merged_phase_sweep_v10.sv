`timescale 1ns/1ps
// Fifty-six frozen checks: seven write/read phases under revoke and active reset.
module tb_merged_phase_sweep_v10;
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
  `include "matched_memory_fw_v10.svh"
  `include "closure_matched_v10.svh"
  // Revision-10 qualified config and measured boot constants are included above.
  localparam int BIT_CLKS = 50_000_000 / 115200;

  pq_soc_merged_core #(.VERIFIER_TIMEOUT(20000), .CPU_BUILD_ID(CLOSURE_BUILD_ID), .WHOLE_IMEM_MEASUREMENT(1'b1)) dut(
    .clk, .rst, .start_attestation, .revoke, .trusted_clear(1'b0), .boot_epoch, .attest_epoch, .nonce, .root_secret,
    .approved_measurement, .directed_keys({KEYS[(3*6+4)*256 +: 256], KEYS[(4*6+3)*256 +: 256]}),
    .context_in, .context_len, .config_data, .authorized, .rot_busy, .grant_done, .attestation_failed, .memory_commits,
    .gate_faults, .fault_sticky, .fault_reason, .endpoint_response, .cpu_uart_tx(uart), .cpu_gpio(gpio));

  initial begin
    dut.u_cpu_a.u_mem.dmem_inst.mem[0]=0;
    dut.u_cpu_a.u_mem.dmem_inst.mem[1]=0;
    for(int k=0;k<MATCHED_MEMORY_FW_N;k++)dut.u_cpu_a.u_mem.imem_inst.mem[k]=MATCHED_MEMORY_FW[k];
    for(int k=0;k<DEMO_FW_V3_N;k++)dut.u_cpu_b.u_mem.imem_inst.mem[k]=DEMO_FW_V3[k];
  end

  int checks=0,errors=0,unsafe_writes=0,unsafe_heads=0,responses=0,cycle_count=0;
  always @(posedge clk)cycle_count++;
  always @(posedge clk)if(!rst)begin
    if(dut.mem_en && |dut.mem_we && !authorized[3])unsafe_writes++;
    if(!authorized[3] && dut.u_p7.mtv && dut.u_p7.mmsg==MSG_MEM_RD_RESP && !dut.u_p7.offered)unsafe_heads++;
    if(dut.u_cpu_a.tmem_rvalid)responses++;
  end
  task automatic check(input bit ok,input string name);
    checks++;if(ok)$display("[PASS] %s",name);else begin errors++;$display("[FAIL] %s",name);end
  endtask
  task automatic reset_case;
    rst=1;start_attestation=0;revoke=0;repeat(10)@(negedge clk);
    dut.u_cpu_a.u_mem.dmem_inst.mem[0]=0;dut.u_cpu_a.u_mem.dmem_inst.mem[1]=0;
    rst=0;repeat(100)@(negedge clk);
  endtask
  task automatic grant_case;
    int n,start_cycle;
    n=0;while(!dut.c_meas_valid[0] && n<25000)begin @(negedge clk);n++;end
    start_cycle=cycle_count;start_attestation=1;@(negedge clk);start_attestation=0;
    n=0;while(!authorized[3] && n<100000)begin @(negedge clk);n++;end
    $display("ATTEST_LATENCY start=%0d grant=%0d cycles=%0d ns=%0d granted=%0d",start_cycle,cycle_count,cycle_count-start_cycle,20*(cycle_count-start_cycle),authorized[3]);
  endtask
  initial begin
    int n,target,r0,w0,h0,c0,revoke_cycle;bit is_write,hit;
    $display("CONFIG: TOP=tb_merged_phase_sweep_v10 CHECKS=56");
    load_d2(0);boot_epoch=BOOT;config_data=CLOSURE_CONFIG;approved_measurement=CLOSURE_MEAS;
    repeat(8)@(negedge clk);
    for(int action=0;action<2;action++)for(int phase=0;phase<7;phase++)begin
      reset_case();grant_case();
      check(authorized[3] && dut.c_meas[0]===CLOSURE_IMEM,$sformatf("PH_GRANT_%0d_%0d",action,phase));
      target=phase<4?phase+2:(phase==6?5:phase-2);is_write=phase<4;
      dut.u_cpu_a.u_mem.dmem_inst.mem[1]=1;
      n=0;while(!(dut.u_cpu_a.u_bridge.st==target && dut.u_cpu_a.u_bridge.we_q==is_write) && n<100000)begin @(negedge clk);n++;end
      hit=dut.u_cpu_a.u_bridge.st==target && dut.u_cpu_a.u_bridge.we_q==is_write;
      check(hit,$sformatf("PH_ACTIVE_%0d_%0d state=%0d write=%0d",action,phase,target,is_write));
      r0=responses;w0=unsafe_writes;h0=unsafe_heads;
      if(action==0)begin
        revoke_cycle=cycle_count;revoke=1;@(negedge clk);revoke=0;
        n=0;while(authorized[3] && n<1500)begin @(negedge clk);n++;end
        $display("REVOKE_LATENCY phase=%0d start=%0d effective=%0d cycles=%0d ns=%0d revoked=%0d",phase,revoke_cycle,cycle_count,cycle_count-revoke_cycle,20*(cycle_count-revoke_cycle),!authorized[3]);
        check(!authorized[3] && n<1500,$sformatf("PH_REVOKE_BOUND_%0d",phase));
        c0=memory_commits;repeat(14000)@(negedge clk);
        check(hit && !authorized[3] && responses>r0 && unsafe_writes==w0 && unsafe_heads==h0 && memory_commits==c0,
          $sformatf("PH_REVOKE_OUTCOME_%0d",phase));
      end else begin
        rst=1;repeat(10)@(negedge clk);
        check(!authorized[3] && !dut.mem_en && !dut.u_cpu_a.tmem_req && !dut.u_cpu_a.tmem_rvalid,
          $sformatf("PH_RESET_CLEAN_%0d",phase));
        dut.u_cpu_a.u_mem.dmem_inst.mem[0]=0;dut.u_cpu_a.u_mem.dmem_inst.mem[1]=0;
        rst=0;repeat(100)@(negedge clk);grant_case();dut.u_cpu_a.u_mem.dmem_inst.mem[1]=1;
        n=0;while(memory_commits<2 && n<100000)begin @(negedge clk);n++;end
        check(authorized[3] && memory_commits>=2 && unsafe_writes==w0 && unsafe_heads==h0,
          $sformatf("PH_RESET_RECOVERY_%0d",phase));
      end
    end
    $display("CHECKS : %0d",checks);$display("ERRORS : %0d",errors);$display("RESULT : %s",errors==0 && checks==56?"PASS":"FAIL");$finish;
  end
  initial begin #40ms;$display("TB_TIMEOUT PHASE");$display("RESULT : FAIL");$finish;end
endmodule
