`timescale 1ns/1ps
// Three checks: merged nondefault timeout reaches both CPU bridges and subsystem.
module tb_closure_parameters;
  logic clk=0,rst=1;always #10 clk=~clk;
  pq_soc_merged_core #(.BRIDGE_TIMEOUT(64),.NI_SLOT_TIMEOUT(256)) dut(
    .clk,.rst,.start_attestation(1'b0),.revoke(1'b0),.trusted_clear(1'b0),
    .boot_epoch(80'b0),.attest_epoch(80'b0),.nonce(128'b0),.root_secret(256'b0),.approved_measurement(256'b0),
    .directed_keys(512'b0),.context_in(112'b0),.context_len(4'b0),.config_data(512'b0),
    .authorized(),.rot_busy(),.grant_done(),.attestation_failed(),.memory_commits(),.gate_faults(),
    .fault_sticky(),.fault_reason(),.endpoint_response(),.cpu_uart_tx(),.cpu_gpio());
  int checks=0,errors=0;
  task automatic check(input bit ok,input string name);
    checks++;if(ok)$display("[PASS] %s",name);else begin errors++;$display("[FAIL] %s",name);end
  endtask
  initial begin
    $display("CONFIG: TOP=tb_closure_parameters CHECKS=3");repeat(8)@(negedge clk);
    check(dut.u_cpu_a.u_bridge.LATE_DRAIN_CYCLES==256,"PARAM_CPU_A_DRAIN");
    check(dut.u_cpu_b.u_bridge.LATE_DRAIN_CYCLES==256,"PARAM_CPU_B_DRAIN");
    check(dut.u_p7.NI_SLOT_TIMEOUT==256,"PARAM_SUBSYSTEM_TIMEOUT");
    $display("CHECKS : %0d",checks);$display("ERRORS : %0d",errors);$display("RESULT : %s",errors==0?"PASS":"FAIL");$finish;
  end
endmodule
