`timescale 1ns / 1ps
// tb_memtest (Lane 1, 2026-11-07; brief v2 A7 "memtest at every size and alignment"): one cpu_tile_noc runs sw/riscv/memtest.S
// (sim_riscv/include/memtest.svh, preloaded into IMEM). The program checks bytes at offsets 0..3, halfwords at 0 and 2, words,
// sign extension, byte-lane composition, and walks every DMEM word 0x4004..0x7FFC; it writes its verdict to DMEM 0x4000.
// Checks (CHECKS = 4, frozen before the first run):
//   MT_RESULT_PASS   DMEM word 0x4000 = 0x600D0011 (all 17 tests passed; 0xBAD000nn names the failing test)
//   MT_LED           LEDs = 0001
//   MT_NO_FAULT      STATUS BUS_FAULT never set (every access was a legal, aligned DMEM access)
//   MT_WALK_EDGES    the bench reads the first and last walked words back from the RAM array (0x4004, 0x7FFC)
module tb_memtest;
  import noc_pkg::*;
  logic clk = 0, rst = 1;
  always #10 clk = ~clk;
  `include "memtest.svh"
  logic av, apv, areq, mvalid, utx; coord_t adst; msg_type_e amsg; logic [10:0] actl; logic [31:0] apay;
  logic [511:0] meas; logic [6:0] mlen; logic [7:0] gpio;
  cpu_tile_noc #(.TILE_ID(3), .MEM_TILE(2)) dut (
    .clk, .rst,
    .app_valid_o(av), .app_ready_i(1'b1), .app_destination_o(adst), .app_message_o(amsg), .app_control_o(actl),
    .app_payload_o(apay), .app_payload_valid_o(apv), .app_payload_ready_i(1'b1), .app_tx_error_i(1'b0),
    .app_rx_head_valid_i(1'b0), .app_rx_src_i('0), .app_rx_msg_i(MSG_MEM_RD_RESP), .app_rx_control_i('0), .app_rx_data_i('0),
    .app_rx_data_valid_i(1'b0), .app_rx_last_i(1'b0), .app_rx_abort_i(1'b0),
    .authorized_i(1'b1), .grant_done_i(1'b0), .attest_failed_i(1'b0),
    .attest_req_o(areq), .meas_imem_o(meas), .meas_imem_len_o(mlen), .meas_valid_o(mvalid), .uart_tx_o(utx), .gpio_o(gpio));

  initial for (int k = 0; k < MEMTEST_N; k++) dut.u_mem.imem_inst.mem[k] = MEMTEST[k];
  bit fault_seen = 0;
  always @(posedge clk) if (!rst && dut.u_tile.tile_status_inst.bus_fault_q) fault_seen = 1;

  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++; if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask

  initial begin
    automatic int n = 0; logic [31:0] res, w_first, w_last;
    $display("CONFIG: TOP=tb_memtest CHECKS=4 FW=memtest");
    repeat (5) @(negedge clk); rst = 0;
    while (dut.u_mem.dmem_inst.mem[0] === 32'h0 || $isunknown(dut.u_mem.dmem_inst.mem[0])) begin
      if (n >= 400000) break;
      @(negedge clk); n++;
    end
    repeat (200) @(negedge clk);   // the LED store follows the result store by two instructions (~20 cycles); first scratch
                                   // run waited only 20 cycles and read LED 0000 (bench fix; checks and count unchanged)
    res = dut.u_mem.dmem_inst.mem[0];
    w_first = dut.u_mem.dmem_inst.mem[1]; w_last = dut.u_mem.dmem_inst.mem[4095];
    check(res == 32'h600D_0011, $sformatf("MT_RESULT_PASS result=%h cycles=%0d", res, n));
    check(gpio[3:0] == 4'b0001, $sformatf("MT_LED %b", gpio[3:0]));
    check(!fault_seen, $sformatf("MT_NO_FAULT fault_seen=%0b", fault_seen));
    check(w_first == (32'h0000_4004 ^ 32'h5A5A_5A5A) && w_last == (32'h0000_7FFC ^ 32'h5A5A_5A5A),
          $sformatf("MT_WALK_EDGES first=%h last=%h", w_first, w_last));
    $display("CHECKS : %0d", checks); $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 4 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #20ms; $display("TB_TIMEOUT"); $display("RESULT : FAIL"); $finish; end
endmodule
