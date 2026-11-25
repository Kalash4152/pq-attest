`timescale 1ns/1ps
// Trace equivalence: rtl/dual_lane/l2_arbiter.sv (OVH = 4) against the signed model scripts/arbiter_model.py.
// Vectors: sim/dual_lane/arbiter/arb_trace{_hdr}.mem from scripts/gen_arbiter_traces.py (10,000 traces, 827,200 cycles,
// 79,514 model grants; regenerate-and-compare is job arbiter_traces_check). Per cycle the bench drives
// req = still-pending | newly asserted (the model only asserts idle requesters), compares the RTL grant with the model's
// (none, or requester 0..3) before the clock edge, and retires the granted request. Engine stub: done in the job's last
// cycle (grant cycle + J - 1). Reset between traces (the model starts every trace from its reset state).
// Checks (frozen from this source before the first run): one ARB_TRACE_<n> per trace (all cycles of the trace equal)
// for N_TRACES = 10000, plus ARB_TRACE_TOTAL_GRANTS (RTL grants == 79514). CHECKS = 10001.
module tb_arbiter_trace;
  localparam int N_TRACES = 10000, N_CYCLES = 827200, N_GRANTS = 79514;
  logic clk = 0, rst = 1; always #10 clk = ~clk;
  logic [3:0] req = '0; logic done, grant, busy; logic [1:0] grant_id;
  l2_arbiter #(.OVH(4)) dut (.clk, .rst, .req, .done, .grant, .grant_id, .busy);
  logic [23:0] hdr [N_TRACES];
  logic [7:0]  body [N_CYCLES];
  int jl = 0, J = 2, checks = 0, errors = 0, shown = 0, rtl_grants = 0;
  assign done = busy && jl == 0;
  always @(posedge clk) begin
    if (rst) jl <= 0;
    else if (grant) jl <= J - 2;
    else if (busy && jl > 0) jl <= jl - 1;
  end
  task automatic check(input bit ok, input string name);
    checks++; if (!ok) begin errors++; if (shown < 20) begin shown++; $display("[FAIL] %s", name); end end
  endtask
  initial begin
    int idx; logic [3:0] pend;
    // The registered job lists sim/dual_lane/arbiter as an include dir, which the flow snapshots into <job>/snapshot;
    // XSim runs in <job>/workspace/dual_job.sim/sim_1/behav/xsim. A missing file is TB_TIMEOUT (INVALID), never a pass.
`ifdef ARB_TRACE_LOCAL
    $readmemh("arb_trace_hdr.mem", hdr); $readmemh("arb_trace.mem", body);
`else
    $readmemh("../../../../../snapshot/sim/dual_lane/arbiter/arb_trace_hdr.mem", hdr);
    $readmemh("../../../../../snapshot/sim/dual_lane/arbiter/arb_trace.mem", body);
`endif
    if (hdr[N_TRACES-1] === 'x || body[N_CYCLES-1] === 'x) begin $display("TB_TIMEOUT trace vectors not loaded"); $finish; end
    $display("CONFIG: TOP=tb_arbiter_trace N_TRACES=%0d N_CYCLES=%0d N_GRANTS=%0d OVH=4", N_TRACES, N_CYCLES, N_GRANTS);
    idx = 0;
    for (int t = 0; t < N_TRACES; t++) begin
      automatic int n = hdr[t][15:0]; automatic bit ok = 1; automatic string why = "";
      J = hdr[t][23:16];
      // reset at once (fix 2026-10-21): the first run waited one extra cycle with the previous trace's requests still
      // driven, so the RTL granted a job the model never saw and its owner's request tripped the A1 check
      rst = 1; req = '0; pend = '0; @(negedge clk); rst = 0;
      for (int k = 0; k < n; k++) begin
        automatic logic [3:0] exp_g = body[idx][7:4], asr = body[idx][3:0];
        req = pend | asr; #1;
        if (exp_g == 4'hF ? grant : !(grant && grant_id == exp_g[1:0])) begin
          if (ok) why = $sformatf("cycle %0d req=%b exp=%h rtl=%0d/%0d", k, req, exp_g, grant, grant_id);
          ok = 0;
        end
        pend = req;
        if (grant) begin pend[grant_id] = 1'b0; rtl_grants++; end
        @(negedge clk); idx++;
      end
      check(ok, $sformatf("ARB_TRACE_%0d J=%0d %s", t, J, why));
    end
    check(rtl_grants == N_GRANTS, $sformatf("ARB_TRACE_TOTAL_GRANTS rtl=%0d model=%0d", rtl_grants, N_GRANTS));
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
