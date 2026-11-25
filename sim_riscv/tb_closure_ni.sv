`timescale 1ns/1ps
// I-19: 8 checks frozen before first execution; real CPU exercises read-only NI MMIO.
module tb_closure_ni;
  logic clk=0,rst=1;
  always #10 clk=~clk;
  `include "ni_status_acceptance.svh"
  cpu_tile_noc #(.TILE_ID(3),.BRIDGE_TIMEOUT(64),.NI_SLOT_TIMEOUT(128)) dut(
    .clk,.rst,.app_valid_o(),.app_ready_i(1'b1),.app_destination_o(),.app_message_o(),.app_control_o(),
    .app_payload_o(),.app_payload_valid_o(),.app_payload_ready_i(1'b1),.app_tx_error_i(1'b0),
    .app_rx_head_valid_i(1'b0),.app_rx_src_i(noc_pkg::coord_t'('0)),.app_rx_msg_i(noc_pkg::MSG_MEM_RD_RESP),
    .app_rx_control_i(11'b0),.app_rx_data_i(32'b0),.app_rx_data_valid_i(1'b0),.app_rx_last_i(1'b0),.app_rx_abort_i(1'b0),
    .authorized_i(1'b0),.grant_done_i(1'b0),.attest_failed_i(1'b0),.attest_req_o(),.meas_imem_o(),.meas_imem_len_o(),
    .meas_valid_o(),.uart_tx_o(),.gpio_o());
  int dbg_bad=0,fetches=0;logic [31:0] expected_debug=0;
  always @(posedge clk)begin
    if(dut.rst_s)expected_debug=0;
    else if(dut.u_tile.mem_valid && dut.u_tile.mem_ready && dut.u_tile.mem_instr)begin
      expected_debug=dut.u_tile.mem_addr;fetches++;
    end
    #1;if(!dut.rst_s && dut.u_tile.dbg_pc_o!==expected_debug)dbg_bad++;
  end
  int checks=0,errors=0;
  task automatic check(input bit ok,input string name);
    checks++;if(ok)$display("[PASS] %s",name);else begin errors++;$display("[FAIL] %s",name);end
  endtask
  initial begin
    int n;
    $display("CONFIG: TOP=tb_closure_ni CHECKS=8");
    for(int k=0;k<NI_STATUS_ACCEPTANCE_N;k++)dut.u_mem.imem_inst.mem[k]=NI_STATUS_ACCEPTANCE[k];
    repeat(8)@(negedge clk);rst=0;
    n=0;while(dut.u_mem.dmem_inst.mem[6]!==32'h600d0009 && n<20000)begin @(negedge clk);n++;end
    check(dut.u_mem.dmem_inst.mem[0]===32'd2,"NI_LAST_ERROR");
    check(dut.u_mem.dmem_inst.mem[1]===32'd0,"NI_TIMEOUT_COUNT");
    check(dut.u_mem.dmem_inst.mem[2]===32'd2,"NI_REFUSED_COUNT");
    check(dut.u_mem.dmem_inst.mem[3]===32'd9,"NI_PROFILE_VERSION");
    check(dut.u_mem.dmem_inst.mem[4]===32'd9,"NI_READ_ONLY");
    check(dut.u_mem.dmem_inst.mem[5]===32'hbadbe005,"NI_INVALID_ERROR");
    check(dbg_bad==0 && fetches>20,"NI_DEBUG_FETCH_HOLDS");
    check(n<20000 && dut.u_bridge.LATE_DRAIN_CYCLES==128,"NI_BOUNDED_PARAMETER_PROFILE");
    $display("CHECKS : %0d",checks);$display("ERRORS : %0d",errors);$display("RESULT : %s",errors==0 && checks==8?"PASS":"FAIL");$finish;
  end
  initial begin #1ms;$display("TB_TIMEOUT NI");$display("RESULT : FAIL");$finish;end
endmodule
