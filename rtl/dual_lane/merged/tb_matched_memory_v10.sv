`timescale 1ns/1ps
// Eight matched-workload checks; optional concurrent attestation; both CPU app ports checked.
module tb_matched_memory_v10;
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

  for(genvar g=0;g<2;g++)begin: protocol
    app_port_checker #(.SELF_TILE(g==0?3:0)) checker_inst(
      .clk,.rst,.authorized(authorized[g==0?3:0]),
      .app_valid(dut.c_valid[g]),.app_ready(dut.app_ready[g==0?3:0]),
      .app_destination(dut.c_dest[g]),.app_message(dut.c_msg[g]),.app_control(dut.c_ctl[g]),
      .app_payload(dut.c_payload[g]),.app_payload_valid(dut.c_pvalid[g]),.app_payload_ready(dut.app_payload_ready[g==0?3:0]),
      .app_tx_error(dut.app_tx_error[g==0?3:0]),.app_rx_head_valid(dut.rx_hv[g==0?3:0]),
      .app_rx_last(dut.rx_last[g==0?3:0]),.app_rx_abort(dut.rx_abort[g==0?3:0]));
  end
  int checks=0,errors=0,cycles=0,reqs=0,resps=0,attest_overlap=0;
  wire control_ok;
`ifdef FIXED_ADMISSION
  assign control_ok=!rot_busy && !attestation_failed;
`else
  assign control_ok=!rot_busy && !attestation_failed && endpoint_response===CLOSURE_RESPONSE
`ifdef MATCHED_CONTENTION
    && attest_overlap>0
`endif
    ;
`endif
  int accepted_cycle=0;logic [31:0] accepted_addr;bit accepted_write,pending=0;
  always @(posedge clk) if(!rst)begin
    cycles++;
    if(dut.u_cpu_a.tmem_req && dut.u_cpu_a.tmem_gnt)begin
      if(pending)begin errors++;$display("[FAIL] BENCH_OVERLAP");end
      if(rot_busy)attest_overlap++;
      pending=1;accepted_cycle=cycles;accepted_addr=dut.u_cpu_a.tmem_addr;accepted_write=dut.u_cpu_a.tmem_we;reqs++;
    end
    if(dut.u_cpu_a.tmem_rvalid)begin
      if(!pending || dut.u_cpu_a.tmem_err)begin errors++;$display("[FAIL] BENCH_RESPONSE");end
      $display("BENCH_REQ index=%0d write=%0d address=%08h accepted=%0d response=%0d latency=%0d data=%08h error=%0d",
        resps,accepted_write,accepted_addr,accepted_cycle,cycles,cycles-accepted_cycle,dut.u_cpu_a.tmem_rdata,dut.u_cpu_a.tmem_err);
      pending=0;resps++;
    end
  end
  task automatic check(input bit ok,input string name);
    checks++;if(ok)$display("[PASS] %s",name);else begin errors++;$display("[FAIL] %s",name);end
  endtask
  initial begin
    int n;bit data_ok;
    $display("CONFIG: TOP=tb_matched_memory_v10 CHECKS=8");
    load_d2(0);boot_epoch=BOOT;config_data=CLOSURE_CONFIG;approved_measurement=CLOSURE_MEAS;
    repeat(8)@(negedge clk);rst=0; n=0;while(!dut.c_meas_valid[0] && n<25000)begin @(negedge clk);n++;end
    check(dut.c_meas[0]===CLOSURE_IMEM,"BENCH_BOOT");
    start_attestation=1;@(negedge clk);start_attestation=0;
    n=0;while(!authorized[3] && n<100000)begin @(negedge clk);n++;end
    check(authorized[3] && !authorized[0],"BENCH_ADMISSION");
    n=0;while(rot_busy && n<100000)begin @(negedge clk);n++;end
    repeat(1000)@(negedge clk);
    check(!rot_busy && !attestation_failed,"BENCH_SETUP_DRAINED");
`ifdef MATCHED_CONTENTION
    fork begin
      wait(reqs>0);@(negedge clk);start_attestation=1;@(negedge clk);start_attestation=0;
    end join_none
`endif
    dut.u_cpu_a.u_mem.dmem_inst.mem[1]=1;
    n=0;while(gpio[0][3:0]!==1 && gpio[0][3:0]!==8 && n<200000)begin @(negedge clk);n++;end
    check(gpio[0][3:0]===1 && dut.u_cpu_a.u_mem.dmem_inst.mem[0]===32,"BENCH_CPU_COMPLETED");
    check(reqs==64 && resps==64 && !pending,"BENCH_EXACT_TRANSFERS");
    check(memory_commits==32,"BENCH_EXACT_COMMITS");
    data_ok=1;for(int k=0;k<32;k++)if(dut.u_bram.mem[64+k]!==32'(k+1))data_ok=0;
    check(data_ok,"BENCH_ALL_DATA");
    check(!dut.u_cpu_a.u_tile.tile_status_inst.bus_fault_q && gpio[0][3:0]!==8 && protocol[0].checker_inst.total()==0 && protocol[1].checker_inst.total()==0 && control_ok,"BENCH_NO_FAULT");
    $display("CHECKS : %0d",checks);$display("ERRORS : %0d",errors);$display("RESULT : %s",errors==0 && checks==8?"PASS":"FAIL");$finish;
  end
  initial begin #20ms;$display("TB_TIMEOUT MATCHED");$display("RESULT : FAIL");$finish;end
endmodule
