`timescale 1ns / 1ps
// tb_mem_bram_dp (Lane 1, 2026-11-06, A7): mem_bram read port B.
// Checks (CHECKS = 6, frozen prev_b the first registered run):
//   DP_INIT_READ_B        port B returns the init-file word one cycle after rdb_en
//   DP_B_LATENCY_ONE      rdb_data_o changes exactly one cycle after rdb_en (not in the same cycle)
//   DP_B_HOLDS            with rdb_en low, rdb_data_o keeps its last value
//   DP_A_WRITE_B_READ     a port-A write is visible on port B on a later read
//   DP_CONCURRENT_A_B     port A and port B accesses in the same cycle both complete correctly
//   DP_SIXTEEN_WORDS      16 consecutive port-B reads (the measurement window) return words 0..15
module tb_mem_bram_dp;
  logic clk_i = 0, reset_i = 1;
  always #10 clk_i = ~clk_i;
  logic mem_valid_i = 0; logic [31:0] mem_addr_i = 0, mem_wdata_i = 0; logic [3:0] mem_wstrb_i = 0;
  logic mem_ready_o; logic [31:0] mem_rdata_o;
  logic rdb_en_i = 0; logic [31:0] rdb_addr_i = 0; logic [31:0] rdb_data_o;
  mem_bram #(.MEM_WORDS(64)) dut (.*);
  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++; if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  task automatic rd_b(input logic [31:0] a, output logic [31:0] d);
    @(negedge clk_i); rdb_en_i = 1; rdb_addr_i = a; @(negedge clk_i); rdb_en_i = 0; d = rdb_data_o;
  endtask
  initial begin
    logic [31:0] d, prev_b; bit ok16;
    $display("CONFIG: TOP=tb_mem_bram_dp CHECKS=6");
    for (int k = 0; k < 64; k++) dut.mem[k] = 32'hA000_0000 + k;
    repeat (3) @(negedge clk_i); reset_i = 0; @(negedge clk_i);
    rd_b(32'h0000_0014, d);
    check(d == 32'hA000_0005, $sformatf("DP_INIT_READ_B data=%h", d));
    // latency: present en at a negedge, sample just after the next posedge vs prev_b it
    @(negedge clk_i); prev_b = rdb_data_o; rdb_en_i = 1; rdb_addr_i = 32'h0000_0020; #5;
    check(rdb_data_o == prev_b, $sformatf("DP_B_LATENCY_ONE same_cycle=%h", rdb_data_o));
    @(negedge clk_i); rdb_en_i = 0;
    prev_b = rdb_data_o; repeat (3) @(negedge clk_i);
    check(rdb_data_o == prev_b && prev_b == 32'hA000_0008, $sformatf("DP_B_HOLDS data=%h", rdb_data_o));
    @(negedge clk_i); mem_valid_i = 1; mem_addr_i = 32'h0000_0030; mem_wdata_i = 32'h1234_5678; mem_wstrb_i = 4'hF;
    @(negedge clk_i); mem_valid_i = 0; mem_wstrb_i = 0;
    rd_b(32'h0000_0030, d);
    check(d == 32'h1234_5678, $sformatf("DP_A_WRITE_B_READ data=%h", d));
    @(negedge clk_i); mem_valid_i = 1; mem_addr_i = 32'h0000_0004; mem_wstrb_i = 0; rdb_en_i = 1; rdb_addr_i = 32'h0000_0008;
    @(negedge clk_i); mem_valid_i = 0; rdb_en_i = 0;
    check(mem_rdata_o == 32'hA000_0001 && rdb_data_o == 32'hA000_0002, $sformatf("DP_CONCURRENT_A_B a=%h b=%h", mem_rdata_o, rdb_data_o));
    ok16 = 1;
    for (int k = 0; k < 16; k++) begin rd_b(k * 4, d); if (d != (k == 12 ? 32'h1234_5678 : 32'hA000_0000 + k)) ok16 = 0; end
    check(ok16, "DP_SIXTEEN_WORDS");
    $display("CHECKS : %0d", checks); $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 6 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #100us; $display("TB_TIMEOUT"); $display("RESULT : FAIL"); $finish; end
endmodule
