`timescale 1ns/1ps
// S2 / I-5 attack matrix (contract sec. 8; docs/decisions/S2_MATRIX_PLAN.md) on rtl/dual_lane/noc_l2_p7_pair.sv plus the
// tile-3 attestation gate rtl/dual_lane/noc_attest_gate.sv fed by the tile-3 NI delivery. Compile with PQ_MAC_ON.
// Vectors: scripts/gen_s2_vectors.py (packets and tags from scripts/l2_golden.py, the pinned teammate kmac128; checked by
// job s2_vectors_check). Each vector is injected into tile 3's mesh input (honouring ready), one at a time, >= 150 idle
// cycles apart (above the T_RL = 64 rate limit). Per vector one check S2_<ROW>_<NAME>:
//   the L2 verdict equals the expected one (0 = accepted: accepted_count +1; else rejected_count +1 with that
//   reject_reason) within N = 3,000 cycles of the last flit (bounded: a missing verdict fails the check, never a timeout);
//   authorized[3] equals the expected value 100 cycles after the verdict;
//   rejected: zero trusted delivery (no control HEAD at the tile-3 NI output) and zero slot retirement (peer_replayed
//   unchanged); accepted: exactly one control HEAD delivered.
// Tile-4 peer load: tile 3's application sends N_T4 = 30 RESPONSEs to tile 4 (genuine, K[3->4]); each is captured from
// tile 3's wire and injected into tile 4's input, and after each one a forged RESPONSE claiming source 5 (junk freshness and
// MAC) follows. S2_T4_ACCEPTED: tile-4 accepted +30 and 30 RESPONSE HEADs delivered; S2_T4_REJECTED: tile-4 rejected +30,
// last reason 5.
// Accounting (contract sec. 4), after 600 quiet cycles: S2_ACCT_T3 / S2_ACCT_T4 (peer_accepted == peer_replayed +
// peer_rejected) and S2_HOLD_MAX (peer_hold_max <= H_MAX = 512 for both tiles; measured values in STATS).
// Latency per message type (last flit -> verdict) printed in STATS (contract sec. 8 "measure"; no bound asserted here).
// CHECKS = S2_NV (25) + 2 + 3 = 30, frozen from this source and the generator before the first run.
module tb_s2_attacks;
  import noc_pkg::*;
  import noc_p7_pkg::*;
  `include "s2_names.svh"
  localparam int N_T4 = 30, VERDICT_N = 3000, CHECKS_TOTAL = S2_NV + 5;
  logic clk = 0, rst = 1;
  always #10 clk = ~clk;
  logic [255:0] kk [3];
  logic [35:0] vec [S2_NV * 27];
  logic [79:0] epoch;
  logic [255:0] K43, K34;
  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  task automatic timeout(input string w); $display("TB_TIMEOUT %s", w); $finish; endtask

  logic [1:0] ptv, ptr, ppv, ppr, pnv, prv, prr, prh;
  coord_t [1:0] pdest, prs; msg_type_e [1:0] pmsg, prm; logic [1:0][10:0] pctl, prc; logic [1:0][31:0] ppd;
  flit_t [1:0] pnf, prf; logic [1:0][31:0] prej, pacc, pdrop; logic [1:0][3:0] pwhy;
  noc_l2_p7_pair dut (.clk, .rst, .boot_epoch(epoch), .key_43(K43), .key_34(K34),
    .tx_valid(ptv), .tx_ready(ptr), .tx_dest_coord(pdest), .tx_msg_type(pmsg), .tx_control(pctl),
    .tx_payload_data(ppd), .tx_payload_valid(ppv), .tx_payload_ready(ppr), .tx_error(),
    .noc_tx_flit(pnf), .noc_tx_valid(pnv), .noc_tx_ready(2'b11),
    .noc_rx_flit(prf), .noc_rx_valid(prv), .noc_rx_ready(prr),
    .rx_src_coord(prs), .rx_dest_coord(), .rx_msg_type(prm), .rx_control(prc), .rx_length(), .rx_head_valid(prh),
    .rx_payload_data(), .rx_payload_valid(), .rx_payload_last(), .rx_ready(2'b11), .rx_abort(),
    .rejected_count(prej), .accepted_count(pacc), .p_slot_drops(pdrop), .reject_reason(pwhy), .tx_busy(), .rx_busy());
  logic authorized; logic [31:0] gfaults; logic [3:0] greason;
  noc_attest_gate gate3 (.clk, .rst, .app_valid(1'b0), .app_msg(MSG_MEM_RD_REQ), .ni_ready(1'b1), .ni_valid(), .app_ready(),
    .authenticated_head(prh[0]), .source(prs[0]), .message_type(prm[0]), .control(prc[0]),
    .trusted_fail(1'b0), .trusted_timeout(1'b0), .trusted_clear(1'b0), .authorized, .fault_count(gfaults), .fault_reason(greason));

  // monitors: control HEADs delivered at each NI output; tile-3 TX wire -> queue for tile 4
  int deliv [2] = '{0, 0};
  always @(posedge clk) if (!rst) for (int t = 0; t < 2; t++) if (prh[t] && is_control(prm[t])) deliv[t]++;
  typedef flit_t pkt_t[$];
  pkt_t tq[$], tcur;
  always @(posedge clk) if (!rst && pnv[0]) begin
    tcur.push_back(pnf[0]);
    if (pnf[0].flit_type == FLIT_TAIL) begin tq.push_back(tcur); tcur = {}; end
  end
  longint cyc = 0; always @(posedge clk) cyc++;
  // one flit into tile t's input, honouring ready (bounded)
  task automatic put(input int t, input flit_t f);
    automatic int w;
    w = 0;
    @(negedge clk); prf[t] = f; prv[t] = 1;
    @(posedge clk); while (!prr[t]) begin @(posedge clk); if (++w > 5000) timeout("tile input held"); end
  endtask
  task automatic idle(input int t, input int n); repeat (n) begin @(negedge clk); prv[t] = 0; prf[t] = '0; end endtask
  int lat_max [8] = '{0, 0, 0, 0, 0, 0, 0, 0};

  task automatic run_vector(input int v);
    automatic logic [35:0] meta;
    automatic int n, exp_r, exp_a, got, w, d0, rp0;
    automatic logic [31:0] r0, a0;
    automatic longint t0;
    automatic head_flit_t h;
    meta = vec[v * 27]; n = int'(meta[29:25]); exp_r = int'(meta[33:30]); exp_a = int'(meta[34]);
    r0 = prej[0]; a0 = pacc[0]; d0 = deliv[0]; rp0 = int'(dut.peer_replayed[0]);
    h = head_flit_t'(vec[v * 27 + 1][35:4]);
    for (int k = 0; k < n; k++) put(0, flit_t'(vec[v * 27 + 1 + k]));
    t0 = cyc; idle(0, 1);
    w = 0; while (prej[0] == r0 && pacc[0] == a0 && w < VERDICT_N) begin @(negedge clk); w++; end
    got = pacc[0] != a0 ? 0 : prej[0] != r0 ? int'(pwhy[0]) : 15;     // 15 = no verdict within N
    if (got == 0 && int'(cyc - t0) > lat_max[h.msg_type[2:0]]) lat_max[h.msg_type[2:0]] = int'(cyc - t0);
    repeat (100) @(negedge clk);
    check(got == exp_r && authorized == exp_a[0] &&
          (exp_r == 0 ? deliv[0] == d0 + 1 : (deliv[0] == d0 && int'(dut.peer_replayed[0]) == rp0)),
          $sformatf("S2_%s verdict=%0d expected=%0d authorized=%b expected_auth=%0d delivered=+%0d replayed=+%0d",
                    s2_name(v), got, exp_r, authorized, exp_a, deliv[0] - d0, int'(dut.peer_replayed[0]) - rp0));
    idle(0, 150);
  endtask

  // tile 3 application sends one RESPONSE (16 payload words) to tile 4
  task automatic app3_response(input int k);
    automatic int w;
    w = 0;
    @(negedge clk); pdest[0] = '0; pdest[0].x = 3'd1; pdest[0].y = 3'd1; pmsg[0] = MSG_ATTEST_RESPONSE; pctl[0] = 11'h000; ptv[0] = 1;
    do begin @(posedge clk); if (++w > 5000) timeout("tile-3 tx_ready"); end while (!ptr[0]);
    @(negedge clk); ptv[0] = 0;
    for (int i = 0; i < 16; i++) begin
      ppd[0] = 32'hA5000000 + k * 16 + i; ppv[0] = 1; w = 0;
      do begin @(posedge clk); if (++w > 5000) timeout("tile-3 payload"); end while (!ppr[0]);
      @(negedge clk);
    end
    ppv[0] = 0;
  endtask
  function automatic pkt_t forged_response(input int k);   // claims source 5, junk freshness / MAC
    automatic pkt_t p; automatic head_flit_t h; automatic flit_t f; automatic coord_t s, d;
    h = '0; s = tile_to_coord(TILE_SPOOF); d = tile_to_coord(TILE_ROT);
    h.src_x = s.x; h.src_y = s.y; h.dest_x = d.x; h.dest_y = d.y; h.msg_type = MSG_ATTEST_RESPONSE; h.length = 5'(p7_length(MSG_ATTEST_RESPONSE) + 5);
    f.flit_data = h; f.flit_type = FLIT_HEAD; f.vc_id = message_to_vc(MSG_ATTEST_RESPONSE); p.push_back(f);
    for (int i = 1; i < int'(h.length); i++) begin
      f.flit_data = (i == 5) ? 32'h0 : 32'hF0F00000 + k * 64 + i; f.flit_type = i == int'(h.length) - 1 ? FLIT_TAIL : FLIT_BODY; p.push_back(f);
    end
    return p;
  endfunction

  initial begin
    $display("CONFIG: TOP=tb_s2_attacks VECTORS=%0d N_T4=%0d CHECKS=%0d PROFILE=P7", S2_NV, N_T4, CHECKS_TOTAL);
`ifdef S2_LOCAL
    $readmemh("s2_keys.mem", kk); $readmemh("s2_vec.mem", vec);
`else
    $readmemh("../../../../../snapshot/sim/dual_lane/s2/s2_keys.mem", kk);
    $readmemh("../../../../../snapshot/sim/dual_lane/s2/s2_vec.mem", vec);
`endif
    if (kk[2] === 'x || vec[S2_NV * 27 - 1] === 'x) timeout("S2 vectors not loaded");
    K43 = kk[0]; K34 = kk[1]; epoch = kk[2][79:0];
    ptv = 0; ppv = 0; prv = 0; prf = '0; pdest = '0; pmsg = '{MSG_ATTEST_GRANT, MSG_ATTEST_GRANT}; pctl = '0; ppd = '0;
    repeat (5) @(negedge clk); rst = 0; repeat (5) @(negedge clk);
    // ---- the vector stream into tile 3
    for (int v = 0; v < S2_NV; v++) run_vector(v);
    // ---- tile-4 peer load
    begin
      automatic logic [31:0] a0, r0; automatic int d0, w;
      a0 = pacc[1]; r0 = prej[1]; d0 = deliv[1];
      for (int k = 0; k < N_T4; k++) begin
        automatic pkt_t g, f; automatic longint t0; automatic logic [31:0] ak;
        app3_response(k);
        w = 0; while (tq.size() == 0 && w < 5000) begin @(negedge clk); w++; end
        if (tq.size() == 0) timeout("tile-3 RESPONSE never on the wire");
        g = tq.pop_front(); ak = pacc[1];
        foreach (g[i]) put(1, g[i]);
        t0 = cyc; idle(1, 1);
        w = 0; while (pacc[1] == ak && w < VERDICT_N) begin @(negedge clk); w++; end
        if (pacc[1] != ak && int'(cyc - t0) > lat_max[5]) lat_max[5] = int'(cyc - t0);
        idle(1, 100);
        f = forged_response(k);
        foreach (f[i]) put(1, f[i]);
        idle(1, 150);
      end
      repeat (600) @(negedge clk);
      check(pacc[1] == a0 + N_T4 && deliv[1] == d0 + N_T4,
            $sformatf("S2_T4_ACCEPTED accepted=+%0d delivered=+%0d (expected %0d)", pacc[1] - a0, deliv[1] - d0, N_T4));
      check(prej[1] == r0 + N_T4 && pwhy[1] == 4'd5,
            $sformatf("S2_T4_REJECTED rejected=+%0d last_reason=%0d (expected %0d, 5)", prej[1] - r0, pwhy[1], N_T4));
    end
    // ---- accounting (contract sec. 4)
    repeat (600) @(negedge clk);
    $display("STATS acct tile3 accepted=%0d replayed=%0d rejected=%0d hold_max=%0d | tile4 accepted=%0d replayed=%0d rejected=%0d hold_max=%0d (H_MAX 512)",
             dut.peer_accepted[0], dut.peer_replayed[0], dut.peer_rejected[0], dut.peer_hold_max[0],
             dut.peer_accepted[1], dut.peer_replayed[1], dut.peer_rejected[1], dut.peer_hold_max[1]);
    for (int k = 0; k < 2; k++)
      check(dut.peer_accepted[k] == dut.peer_replayed[k] + dut.peer_rejected[k],
            $sformatf("S2_ACCT_T%0d accepted=%0d replayed=%0d rejected=%0d", k + 3, dut.peer_accepted[k], dut.peer_replayed[k], dut.peer_rejected[k]));
    check(dut.peer_hold_max[0] <= 16'd512 && dut.peer_hold_max[1] <= 16'd512,
          $sformatf("S2_HOLD_MAX tile3=%0d tile4=%0d (H_MAX 512)", dut.peer_hold_max[0], dut.peer_hold_max[1]));
    $display("STATS latency (last flit -> verdict, cycles) CHALLENGE=%0d RESPONSE=%0d GRANT=%0d REVOKE=%0d", lat_max[4], lat_max[5], lat_max[6], lat_max[7]);
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #30ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
