`timescale 1ns/1ps
// Diagnostic, NOT a release acceptance test. Frozen: three observations.
// Proves whether the real CPU executes a compressed instruction read from STATUS.
module tb_r10_mmio_fetch;
  import noc_pkg::*;
  logic clk=0,rst=1;
  always #10 clk=~clk;
  logic valid,pvalid,txerr;
  coord_t destination;
  msg_type_e message;
  logic [10:0] ctl;
  logic [31:0] payload;
  logic [511:0] measured;
  logic [6:0] measured_len;
  logic measured_valid,attest_req,uart;
  logic [7:0] gpio;
  cpu_tile_noc #(.BUILD_ID(32'h20261108)) dut(
    .clk,.rst,
    .app_valid_o(valid),.app_ready_i(1'b0),.app_destination_o(destination),
    .app_message_o(message),.app_control_o(ctl),.app_payload_o(payload),
    .app_payload_valid_o(pvalid),.app_payload_ready_i(1'b0),.app_tx_error_i(1'b0),
    .app_rx_head_valid_i(1'b0),.app_rx_src_i('0),.app_rx_msg_i(MSG_MEM_RD_RESP),
    .app_rx_control_i('0),.app_rx_data_i('0),.app_rx_data_valid_i(1'b0),
    .app_rx_last_i(1'b0),.app_rx_abort_i(1'b0),.authorized_i(1'b0),
    .grant_done_i(1'b0),.attest_failed_i(1'b0),.attest_req_o(attest_req),
    .meas_imem_o(measured),.meas_imem_len_o(measured_len),.meas_valid_o(measured_valid),
    .uart_tx_o(uart),.gpio_o(gpio));
  bit fetched=0,data_seen=0,executed=0;
  int checks=0,errors=0;
  always @(posedge clk) if(!rst) begin
    if(dut.u_tile.mem_valid && dut.u_tile.mem_instr && dut.u_tile.mem_ready &&
       dut.u_tile.mem_addr==32'h1000200c) begin
      fetched=1;
      if(dut.u_tile.mem_rdata===32'h20261108)data_seen=1;
    end
    // 0x1108 = C.ADDI4SPN a0,sp,160. SP is explicitly set to 0x8000 in IMEM.
    if(fetched && dut.u_tile.cpu.cpuregs[10]===32'h000080a0)executed=1;
  end
  task automatic check(input bit ok,input string name);
    checks++;
    if(ok)$display("[PASS] %s",name);
    else begin errors++;$display("[FAIL] %s",name);end
  endtask
  initial begin
    $display("CONFIG: TOP=tb_r10_mmio_fetch CHECKS=3");
    for(int i=0;i<4096;i++)dut.u_mem.imem_inst.mem[i]=0;
    dut.u_mem.imem_inst.mem[0]=32'h00008137; // lui sp,8
    dut.u_mem.imem_inst.mem[1]=32'h00010113; // addi sp,sp,0
    dut.u_mem.imem_inst.mem[2]=32'h100022b7; // lui t0,0x10002
    dut.u_mem.imem_inst.mem[3]=32'h00c28293; // addi t0,t0,12
    dut.u_mem.imem_inst.mem[4]=32'h00028067; // jalr zero,t0,0
    dut.u_mem.imem_inst.mem[5]=32'h0000006f;
    repeat(8)@(negedge clk);rst=0;
    for(int i=0;i<2000 && !executed;i++)@(negedge clk);
    check(fetched,"MMIO_INSTRUCTION_FETCH_ACCEPTED");
    check(data_seen,"MMIO_RETURNS_BUILD_ID");
    check(executed,"MMIO_COMPRESSED_INSTRUCTION_EXECUTED");
    $display("MMIO_DIAGNOSTIC fetch=%0d data=%0d executed=%0d a0=%08h",fetched,data_seen,executed,dut.u_tile.cpu.cpuregs[10]);
    $display("CHECKS : %0d",checks);$display("ERRORS : %0d",errors);
    $display("RESULT : %s",errors==0 && checks==3?"PASS":"FAIL");$finish;
  end
  initial begin #100us;$display("TB_TIMEOUT MMIO_DIAGNOSTIC");$finish;end
endmodule
