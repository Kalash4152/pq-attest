`timescale 1ns/1ps
// S3-A1 (docs/decisions/S3_T1_A1_CONTRACT.md sec. 2): the shared tile-3 keccak_f1600 contract made bench-visible.
// The digests alone cannot show isolation: a done delivered to the idle non-owner is ignored by its FSM, so every
// response stays correct. This bench runs N_ATT attestations with random inputs through the S3 controller
// (rtl/dual_lane/pq_attest_protocol_s3.sv) and monitors, every cycle after reset:
//   PERM_NO_DOUBLE_START  never kp_start and mp_start in the same cycle               (R5)
//   PERM_NO_START_BUSY    never a start while the shared core is not idle            (R5)
//   PERM_OWNER_STABLE     owner_meas_q changes only right after a start in an idle cycle (R2)
//   PERM_DONE_ISOLATION   kp_done only while the owner is KMAC, mp_done only while it is MEAS (R3)
// Checks (frozen before the first run): N_ATT "done within bound" + 4 rules + PERM_ATTESTATIONS = 40 + 4 + 1 = 45.
// A bound hit is TB_TIMEOUT (INVALID), never a pass.
module tb_s3_perm_share;
  localparam int N_ATT = 40;
  logic clk = 0, rst_n = 0, start = 0;
  always #10 clk = ~clk;
  logic [55:0] tile_id; logic [79:0] epoch; logic [127:0] nonce; logic [255:0] root_secret;
  logic [111:0] context_in; logic [3:0] context_len; logic [511:0] config_data, imem; logic [6:0] config_len, imem_len;
  logic [775:0] response; logic busy, done, err; logic [2:0] status; logic [3:0] error_code;
  pq_attestation_controller dut(.*);
  int checks = 0, errors = 0, completed = 0;
  int v_double = 0, v_busy = 0, v_owner = 0, v_iso = 0, kp_starts = 0, mp_starts = 0;
  logic [31:0] lcg = 32'h5EED_0D53;
  function automatic logic [31:0] rnd(); lcg = lcg * 32'd1664525 + 32'd1013904223; return lcg; endfunction
  task automatic check(input bit ok, input string name);
    checks++; if (!ok) begin errors++; $display("[FAIL] %s", name); end
  endtask
  logic owner_prev, start_idle_prev;
  always @(posedge clk) begin
    if (rst_n) begin
      if (dut.kp_start && dut.mp_start) v_double++;
      if ((dut.kp_start || dut.mp_start) && !dut.sp_idle) v_busy++;
      if (dut.owner_meas_q !== owner_prev && !start_idle_prev) v_owner++;
      if ((dut.kp_done && dut.owner_meas_q) || (dut.mp_done && !dut.owner_meas_q)) v_iso++;
      if (dut.kp_start) kp_starts++;
      if (dut.mp_start) mp_starts++;
    end
    owner_prev      <= dut.owner_meas_q;
    start_idle_prev <= rst_n && dut.sp_idle && (dut.kp_start || dut.mp_start);
  end
  initial begin
    $display("CONFIG: TOP=tb_s3_perm_share N_ATT=%0d CHECKS=45", N_ATT);
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
      check(n <= 5000, $sformatf("PERM_DONE_%0d cycles=%0d", a, n));
      repeat (2) @(negedge clk);
    end
    $display("STATS PERM kmac_starts=%0d meas_starts=%0d", kp_starts, mp_starts);
    check(v_double == 0, $sformatf("PERM_NO_DOUBLE_START violations=%0d", v_double));
    check(v_busy == 0,   $sformatf("PERM_NO_START_BUSY violations=%0d", v_busy));
    check(v_owner == 0,  $sformatf("PERM_OWNER_STABLE violations=%0d", v_owner));
    check(v_iso == 0 && mp_starts > 0 && kp_starts > 0, $sformatf("PERM_DONE_ISOLATION violations=%0d", v_iso));
    check(completed == N_ATT, $sformatf("PERM_ATTESTATIONS completed=%0d", completed));
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
