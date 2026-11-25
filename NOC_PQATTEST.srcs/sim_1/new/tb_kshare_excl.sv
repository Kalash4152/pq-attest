`timescale 1ns/1ps
// B-3 D (M-F1 rev 7 R7.8.2): the shared-kmac EXCLUSIVITY contract of rtl/dual_lane/pq_kmac_share.sv, made bench-visible.
// s8_golden cannot see a premature tag start: the shared kmac128 ignores a start while busy and the tag engine re-runs
// at the real S_TAG_START, so every digest stays correct (mutant ks_mut_tag_during_kdf survived s8_golden on
// 2026-10-21, run dual_lane_10_20261021_005757_bb00acde; only the procedural $error checks fired).
// This bench runs N_ATT attestations through the D controller variant with random inputs and monitors, every cycle:
//   no cycle with both requesters starting, and no start into a busy shared kmac128.
// Checks (frozen before the first run): N_ATT "done within bound" + KSHARE_EXCLUSIVE (violations == 0)
//   + KSHARE_ATTESTATIONS (all N_ATT completed) = 40 + 2 = 42. A bound hit is TB_TIMEOUT (INVALID), never a pass.
module tb_kshare_excl;
  localparam int N_ATT = 40;
  logic clk = 0, rst_n = 0, start = 0;
  always #10 clk = ~clk;
  logic [55:0] tile_id; logic [79:0] epoch; logic [127:0] nonce; logic [255:0] root_secret;
  logic [111:0] context_in; logic [3:0] context_len; logic [511:0] config_data, imem; logic [6:0] config_len, imem_len;
  logic [775:0] response; logic busy, done, err; logic [2:0] status; logic [3:0] error_code;
  pq_attestation_controller dut(.*);
  int checks = 0, errors = 0, viol = 0, completed = 0;
  logic [31:0] lcg = 32'h5EED_0D01;
  function automatic logic [31:0] rnd(); lcg = lcg * 32'd1664525 + 32'd1013904223; return lcg; endfunction
  task automatic check(input bit ok, input string name);
    checks++; if (!ok) begin errors++; $display("[FAIL] %s", name); end
  endtask
  always @(posedge clk) if (rst_n) begin
    if (dut.u_pq_kmac_share.a_start && dut.u_pq_kmac_share.b_start) viol++;
    if (dut.u_pq_kmac_share.k_start && dut.u_pq_kmac_share.busy) viol++;
  end
  initial begin
    $display("CONFIG: TOP=tb_kshare_excl N_ATT=%0d", N_ATT);
    repeat (5) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
    for (int a = 0; a < N_ATT; a++) begin
      int n;
      for (int w = 0; w < 7; w++) tile_id[w*8 +: 8] = rnd();
      for (int w = 0; w < 10; w++) epoch[w*8 +: 8] = rnd();
      for (int w = 0; w < 4; w++) nonce[w*32 +: 32] = rnd();
      for (int w = 0; w < 8; w++) root_secret[w*32 +: 32] = rnd();
      for (int w = 0; w < 14; w++) context_in[w*8 +: 8] = rnd();
      for (int w = 0; w < 16; w++) begin config_data[w*32 +: 32] = rnd(); imem[w*32 +: 32] = rnd(); end
      context_len = rnd() % 15; config_len = rnd() % 65; imem_len = rnd() % 65;
      n = 0; while (busy) begin @(negedge clk); if (++n > 5000) begin $display("TB_TIMEOUT idle a=%0d", a); $finish; end end
      start = 1; @(negedge clk); start = 0;
      n = 0; while (!done) begin @(negedge clk); if (++n > 5000) begin $display("TB_TIMEOUT done a=%0d", a); $finish; end end
      completed++;
      check(n <= 5000, $sformatf("KSHARE_DONE_%0d cycles=%0d", a, n));
      repeat (2) @(negedge clk);
    end
    check(viol == 0, $sformatf("KSHARE_EXCLUSIVE violations=%0d", viol));
    check(completed == N_ATT, $sformatf("KSHARE_ATTESTATIONS completed=%0d", completed));
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
