`timescale 1ns/1ps
// R7.6a bounds on the RTL arbiter rtl/dual_lane/l2_arbiter.sv (step c, docs/decisions/STEP_C_DESIGN_P7_L2_SHARED.md).
// Engine stub: a job lasts L cycles counting its grant cycle (L = J_MAX = 128 in adversarial phases, random 2..128
// otherwise; L = 1 is not representable because done cannot come in the grant cycle);
// OVH = 4 (the A2 worst case). Requesters hold req until granted and re-request only after their own job's done (A1).
// Phases alternate every 500 grants: random arrivals (1/16 per idle cycle) / adversarial (all four re-request the
// cycle after their own done, every job 128 cycles).
// Checks (frozen before the first run): one per grant, ARB_P_BOUND (wait <= 269) or ARB_Q_BOUND (wait <= 792), for
// N_GRANTS = 4000; ARB_NO_STARVATION (no pending request ever older than its bound); coverage ARB_COVER_P_MAX
// (max P wait >= 250), ARB_COVER_Q_MAX (max Q wait >= 600), ARB_COVER_FORCED_Q (>= 100 Q grants while P pending).
// CHECKS = 4000 + 1 + 3 = 4004. Bounded run; a missing grant for 20000 cycles is TB_TIMEOUT (INVALID).
module tb_l2_arbiter;
  localparam int N_GRANTS = 4000, J_MAX = 128, OVH = 4, PB = 269, QB = 792;
  logic clk = 0, rst = 1; always #10 clk = ~clk;
  logic [3:0] req; logic done, grant, busy; logic [1:0] grant_id;
  l2_arbiter #(.OVH(OVH)) dut (.clk, .rst, .req, .done, .grant, .grant_id, .busy);
  int checks = 0, errors = 0, shown = 0, grants = 0, maxp = 0, maxq = 0, forced = 0, starve = 0;
  longint cyc = 0; longint t_req[4]; int job_left = 0; bit in_job[4]; int phase = 0;
  logic [31:0] lcg = 32'hA4B1_7E01;
  function automatic logic [31:0] rnd(); lcg = lcg * 32'd1664525 + 32'd1013904223; return lcg; endfunction
  task automatic check(input bit ok, input string name);
    checks++; if (!ok) begin errors++; if (shown < 20) begin shown++; $display("[FAIL] %s", name); end end
  endtask
  // engine stub: done pulses on the last cycle of the job
  assign done = busy && job_left == 1;
  always @(posedge clk) begin
    cyc++;
    if (rst) begin req <= '0; job_left <= 0; for (int r = 0; r < 4; r++) in_job[r] <= 0; end
    else begin
      if (grant) begin
        automatic int w = int'(cyc - t_req[grant_id]) + 1;
        automatic bit isp = grant_id < 2;
        grants++;
        if (isp) begin if (w > maxp) maxp = w; end else begin if (w > maxq) maxq = w; if (req[0] | req[1]) forced++; end
        if (grants <= N_GRANTS) check(w <= (isp ? PB : QB), $sformatf("%s wait=%0d grant=%0d r%0d", isp ? "ARB_P_BOUND" : "ARB_Q_BOUND", w, grants, grant_id));
        req[grant_id] <= 1'b0; in_job[grant_id] <= 1;
        // a job of L cycles counts the grant cycle (model semantics): done in cycle grant+L-1, so job_left starts at L-1
        // (fix 2026-10-21: the first run loaded L, i.e. jobs of L+1 = 129 cycles > J_MAX, which produced waits of 270)
        job_left <= ((phase == 1) ? J_MAX : 2 + int'(rnd() % (J_MAX - 1))) - 1;
      end else if (job_left > 0) job_left <= job_left - 1;
      if (done) for (int r = 0; r < 4; r++) in_job[r] <= 0;
      for (int r = 0; r < 4; r++) begin
        if (req[r] && int'(cyc - t_req[r]) + 1 > (r < 2 ? PB : QB)) starve++;
        if (!req[r] && !in_job[r] && !(grant && grant_id == r) && !(done && dut.owner == r)) begin
          if (phase == 1 || rnd() % 16 == 0) begin req[r] <= 1'b1; t_req[r] = cyc + 1; end
        end
      end
      phase = ((grants / 500) % 2);
    end
  end
  initial begin
    int last, n;
    $display("CONFIG: TOP=tb_l2_arbiter N_GRANTS=%0d J_MAX=%0d OVH=%0d P_BOUND=%0d Q_BOUND=%0d", N_GRANTS, J_MAX, OVH, PB, QB);
    repeat (4) @(negedge clk); rst = 0;
    last = 0; n = 0;
    while (grants < N_GRANTS) begin
      @(negedge clk); n++;
      if (grants != last) begin last = grants; n = 0; end
      if (n > 20000) begin $display("TB_TIMEOUT no grant for 20000 cycles (grants=%0d)", grants); $finish; end
    end
    check(starve == 0, $sformatf("ARB_NO_STARVATION over-bound pending cycles=%0d", starve));
    check(maxp >= 250, $sformatf("ARB_COVER_P_MAX %0d", maxp));
    check(maxq >= 600, $sformatf("ARB_COVER_Q_MAX %0d", maxq));
    check(forced >= 100, $sformatf("ARB_COVER_FORCED_Q %0d", forced));
    $display("STATS grants=%0d maxP=%0d maxQ=%0d forcedQ=%0d", grants, maxp, maxq, forced);
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
