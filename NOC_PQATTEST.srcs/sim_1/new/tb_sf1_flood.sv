`timescale 1ns/1ps
// SF-1 under P7 at unit level (docs/decisions/SF-1-l2-busy-drop.md sec. Design (P7) "Tests"; M-F1 rev 7 R7.7; step-c
// jobs sf1_flood_revoke / sf1_mut_single_slot): rtl/dual_lane/noc_l2_p7_pair.sv plus the tile-3 attestation gate
// rtl/dual_lane/noc_attest_gate.sv fed by the tile-3 NI delivery. Compile with PQ_MAC_ON.
// Flood: back-to-back control packets into tile 3's mesh input at line rate (zero gap), GRANT/REVOKE-shaped (10 flits)
// or CHALLENGE-shaped (17 flits) with junk freshness and MAC, stamped sources cycling over the non-peer tiles 5, 0, 1, 2
// (a forged src = 4 is the ingress check's case, step d). The genuine tile-4 packets (P7 tile 4 TX, K[4->3]) are merged
// packet-atomically: a waiting genuine packet goes right behind the flood packet on the wire, and the flood resumes behind it.
// Phase 1, N_ROUNDS = 20 rounds, each: tile 4 sends GRANT (control[10:7] = 1) under the flood, then REVOKE under the flood.
//   SF1_GRANT_<r>:   authorized[3] == 1 within LAT_BOUND cycles of the GRANT TAIL entering tile 3
//   SF1_REVOKE_<r>:  authorized[3] == 0 within LAT_BOUND cycles of the REVOKE TAIL (the targeted check)
//   SF1_REVOKE_LATENCY_<r>: that latency <= LAT_BOUND = 2 (pre-check) + 269 (R7.6a P wait) + 128 (J_MAX) + 12 (replay
//                    start and NI delivery) = 411 cycles (C4 at unit level)
//   SF1_P_SLOT_DROPS: p_slot_drops[tile 3] == 0;  SF1_FLOOD_REJECTED: tile-3 rejected_count == flood packets sent
// Phase 2, rate limit (reason 6), no genuine traffic: N_RL1 = 200 back-to-back 10-flit packets from source 5 only, then
//   N_RL2 = 200 cycling over sources 5, 0, 1, 2. Per packet SF1_RL_VERDICT: the verdict equals the model (admitted, so
//   reason 5, iff its HEAD enters >= T_RL = 64 cycles after the previous admitted HEAD of the same source; else reason 6).
// Phase 1b, D2 (M-F1 R7.7a: the peer path holds, never drops), each case starting from tile 3 authorized:
//   SF1_B2B_<r> (r < 10): GRANT and REVOKE sent back to back under the flood; authorized[3] == 0 within LAT_BOUND of the
//     REVOKE TAIL.  SF1_HELD_ACCEPTED / SF1_HELD_DEAUTH: a held revoke, 8 REVOKEs back to back under the flood after a
//     GRANT: tile-3 accepted_count rises by exactly 9 and authorized[3] == 0.  SF1_DURING_VERIFY_<r> (r < 5): a GRANT, and
//     the REVOKE released into tile 3 while slot P verifies the GRANT (P_WAIT), under the flood; authorized[3] == 0.
//     SF1_DURING_REPLAY_<r> (r < 5): a CHALLENGE, and the REVOKE released while slot P replays it (P_PLAY), flood paused;
//     authorized[3] == 0.
// Coverage: SF1_COVER_FLOOD (>= 1000 flood packets in phase 1), SF1_COVER_OVERLAP (>= 15 REVOKEs placed directly behind a
//   flood packet), SF1_COVER_HELD (>= 20 cycles with a peer HEAD held by D2 in phase 1b).
// CHECKS = 20 * 3 + (10 + 2 + 5 + 5) + 2 + 400 + 3 = 487, frozen before the first run; defines (Kalash 2026-10-22):
//   SF1_ONLY_P1 (mutant job sf1_mut_single_slot only): phase 1 alone, CHECKS = 60 (the single-slot mutant makes phase 1b's
//     setup GRANT fail, a setup TB_TIMEOUT);
//   SF1_ACCT (job sf1_acct, contract sec. 4): after the full run and 600 quiet cycles, SF1_ACCT_T3 / SF1_ACCT_T4
//     (peer_accepted == peer_replayed + peer_rejected per tile) and SF1_HOLD_MAX (peer_hold_max <= H_MAX = 512 for both
//     tiles, measured value printed): CHECKS = 487 + 3 = 490.
// Bounded waits: a bound hit is TB_TIMEOUT (INVALID).
module tb_sf1_flood;
  import noc_pkg::*;
  import noc_p7_pkg::*;
  localparam int N_ROUNDS = 20, N_RL1 = 200, N_RL2 = 200, T_RL = 64, LAT_BOUND = 2 + 269 + 128 + 12;
  logic clk = 0, rst = 1;
  always #10 clk = ~clk;
  logic [79:0] epoch = 80'h0BAD_C0DE_1234_5678_9ABC;
  logic [31:0] lcg = 32'h5F1F_0001;
  function automatic logic [31:0] rnd(); lcg = lcg * 32'd1664525 + 32'd1013904223; return lcg; endfunction
  int checks = 0, errors = 0, shown = 0;
  task automatic check(input bit ok, input string name);
    checks++; if (!ok) begin errors++; if (shown < 25) begin shown++; $display("[FAIL] %s", name); end end
  endtask
  task automatic timeout(input string w); $display("TB_TIMEOUT %s", w); $finish; endtask
  logic [255:0] K43 = {8{32'hA1B2_C3D4}} ^ 256'h0F0E_0D0C_0B0A_0908_0706_0504_0302_0100, K34 = {8{32'h1357_9BDF}};

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

  // tile-4 wire output -> genuine packet queue
  typedef flit_t pkt_t[$];
  pkt_t gq[$], gcur;
  always @(posedge clk) if (!rst && pnv[1]) begin
    gcur.push_back(pnf[1]);
    if (pnf[1].flit_type == FLIT_TAIL) begin gq.push_back(gcur); gcur = {}; end
  end
  function automatic pkt_t flood_pkt(input int src);
    automatic pkt_t p; automatic head_flit_t h = '0; automatic flit_t f;
    automatic msg_type_e m = (rnd() % 4 == 0) ? MSG_ATTEST_CHALLENGE : (rnd() % 2) ? MSG_ATTEST_GRANT : MSG_ATTEST_REVOKE;
    automatic int n = p7_length(m) + 5;
    h.dest_x = 3'd0; h.dest_y = 3'd1; h.src_x = 3'(src % 3); h.src_y = 3'(src / 3); h.msg_type = m; h.length = 5'(n);
    h.control.raw = 11'h080;
    f.flit_data = h; f.flit_type = FLIT_HEAD; f.vc_id = message_to_vc(m); p.push_back(f);
    for (int i = 1; i < n; i++) begin
      f.flit_data = (i == 5) ? {16'h0, 16'(rnd())} : rnd(); f.flit_type = i == n - 1 ? FLIT_TAIL : FLIT_BODY; p.push_back(f);
    end
    return p;
  endfunction
  function automatic pkt_t rl_pkt(input int src);   // always 10 flits (GRANT-shaped)
    automatic pkt_t p; automatic head_flit_t h = '0; automatic flit_t f;
    h.dest_x = 3'd0; h.dest_y = 3'd1; h.src_x = 3'(src % 3); h.src_y = 3'(src / 3); h.msg_type = MSG_ATTEST_GRANT; h.length = 5'd10;
    f.flit_data = h; f.flit_type = FLIT_HEAD; f.vc_id = message_to_vc(MSG_ATTEST_GRANT); p.push_back(f);
    for (int i = 1; i < 10; i++) begin f.flit_data = (i == 5) ? 32'h0 : rnd(); f.flit_type = i == 9 ? FLIT_TAIL : FLIT_BODY; p.push_back(f); end
    return p;
  endfunction
  // the flit driver: one flit per cycle, packet-atomic; tile 3 never holds a control flit
  longint cyc = 0; always @(posedge clk) cyc++;
  task automatic put(input flit_t f);
    automatic int w = 0;
    @(negedge clk); prf[0] = f; prv[0] = 1;
    @(posedge clk); while (!prr[0]) begin @(posedge clk); if (++w > 2000) timeout("tile-3 input held"); end
  endtask
  task automatic put_pkt(input pkt_t p); foreach (p[i]) put(p[i]); endtask
  task automatic idle(); @(negedge clk); prv[0] = 0; prf[0] = '0; endtask

  bit flooding = 0, flooding_on = 1; int flood_sent = 0, overlap = 0; longint genuine_tail = 0; bit genuine_was_revoke = 0, revoke_overlap = 0;
  int fsrc = 0, gate_ps = -1, d2_held = 0;
  wire [2:0] ps3 = dut.W[0].l2.ps;
  always @(posedge clk) if (!rst && dut.W[0].l2.p_hold) d2_held++;
  localparam int SRCS [4] = '{5, 0, 1, 2};
  function automatic bit is_revoke(input pkt_t p); automatic head_flit_t h; h = head_flit_t'(p[0].flit_data); return h.msg_type == MSG_ATTEST_REVOKE; endfunction
  task automatic flood_loop();
    automatic bit after_flood = 0;
    while (flooding || gq.size() > 0) begin
      // the gate holds back only the REVOKE (the GRANT / CHALLENGE ahead of it must reach slot P first)
      if (gq.size() > 0 && (gate_ps < 0 || ps3 == gate_ps || !is_revoke(gq[0]))) begin
        automatic pkt_t g = gq.pop_front(); automatic head_flit_t h = head_flit_t'(g[0].flit_data);
        put_pkt(g); genuine_tail = cyc;
        if (h.msg_type == MSG_ATTEST_REVOKE && after_flood) overlap++;
        after_flood = 0;
      end else if (flooding_on) begin
        put_pkt(flood_pkt(SRCS[fsrc])); fsrc = (fsrc + 1) % 4; flood_sent++; after_flood = 1;
      end else idle();
    end
    idle();
  endtask
  task automatic app4(input msg_type_e m, input logic [10:0] c);
    automatic int w = 0;
    @(negedge clk); pdest[1] = '0; pdest[1].x = 3'd0; pdest[1].y = 3'd1; pmsg[1] = m; pctl[1] = c; ptv[1] = 1;
    do begin @(posedge clk); if (++w > 5000) timeout("tile-4 tx_ready"); end while (!ptr[1]);
    @(negedge clk); ptv[1] = 0;
  endtask
  task automatic app4p(input msg_type_e m, input logic [10:0] c);
    automatic int n = message_payload_flits(m), w = 0;
    app4(m, c);
    for (int i = 0; i < n; i++) begin
      ppd[1] = rnd(); ppv[1] = 1; w = 0;
      do begin @(posedge clk); if (++w > 5000) timeout("tile-4 payload"); end while (!ppr[1]);
      @(negedge clk);
    end
    ppv[1] = 0;
  endtask
  task automatic settle_genuine(); automatic int w = 0;
    while (gq.size() > 0 || gcur.size() > 0 || dut.W[1].l2.ts != 0) begin @(negedge clk); if (++w > 20000) timeout("genuine traffic not drained"); end
  endtask
  task automatic setup_auth();   // setup step, not a check: tile 3 must become authorized, else TB_TIMEOUT
    automatic int w = 0;
    while (gq.size() > 0 || gcur.size() > 0 || genuine_tail == 0) begin @(negedge clk); if (++w > 5000) timeout("setup GRANT not sent"); end
    w = 0; while (authorized !== 1'b1 && w <= LAT_BOUND) begin @(negedge clk); w++; end
    if (authorized !== 1'b1) timeout("setup GRANT did not authorize");
  endtask
  task automatic wait_auth(input bit want, input int r, input string what);
    automatic longint t0; automatic int w = 0;
    while (gq.size() > 0 || gcur.size() > 0 || genuine_tail == 0) begin @(negedge clk); if (++w > 5000) timeout("genuine packet not sent"); end
    t0 = genuine_tail; w = int'(cyc - t0);
    // explicit per-cycle counter (the wait must end at LAT_BOUND even when authorized never changes)
    while (authorized !== want && w <= LAT_BOUND) begin @(negedge clk); w++; end
    check(authorized === want, $sformatf("SF1_%s_%0d authorized=%b after %0d cycles", what, r, authorized, int'(cyc - t0)));
    if (what == "REVOKE") check(int'(cyc - t0) <= LAT_BOUND, $sformatf("SF1_REVOKE_LATENCY_%0d %0d cycles (bound %0d)", r, int'(cyc - t0), LAT_BOUND));
  endtask

  initial begin #50ms; $display("TB_TIMEOUT global"); $finish; end   // inside the 60 ms run limit: a hang is INVALID, never silent
  initial begin
`ifdef SF1_ONLY_P1
    $display("CONFIG: TOP=tb_sf1_flood N_ROUNDS=%0d N_RL1=%0d N_RL2=%0d T_RL=%0d LAT_BOUND=%0d PROFILE=P7 PHASES=P1 CHECKS=60", N_ROUNDS, N_RL1, N_RL2, T_RL, LAT_BOUND);
`elsif SF1_ACCT
    $display("CONFIG: TOP=tb_sf1_flood N_ROUNDS=%0d N_RL1=%0d N_RL2=%0d T_RL=%0d LAT_BOUND=%0d PROFILE=P7 PHASES=ALL ACCT=1 CHECKS=490", N_ROUNDS, N_RL1, N_RL2, T_RL, LAT_BOUND);
`else
    $display("CONFIG: TOP=tb_sf1_flood N_ROUNDS=%0d N_RL1=%0d N_RL2=%0d T_RL=%0d LAT_BOUND=%0d PROFILE=P7 PHASES=ALL CHECKS=487", N_ROUNDS, N_RL1, N_RL2, T_RL, LAT_BOUND);
`endif
    ptv = 0; ppv = 0; prv = 0; prf = '0; pdest = '0; pmsg[0] = MSG_ATTEST_GRANT; pmsg[1] = MSG_ATTEST_GRANT; pctl = '0; ppd = '0;
    repeat (5) @(negedge clk); rst = 0; repeat (5) @(negedge clk);
    // ---- phase 1
    flooding = 1;
    fork
      flood_loop();
      begin
        for (int r = 0; r < N_ROUNDS; r++) begin
          repeat (50 + rnd() % 200) @(negedge clk);
          genuine_tail = 0; app4(MSG_ATTEST_GRANT, 11'h080); wait_auth(1, r, "GRANT");
          repeat (50 + rnd() % 200) @(negedge clk);
          genuine_tail = 0; app4(MSG_ATTEST_REVOKE, 11'h000); wait_auth(0, r, "REVOKE");
        end
`ifndef SF1_ONLY_P1
        // ---- phase 1b (D2)
        for (int r = 0; r < 10; r++) begin
          genuine_tail = 0; app4(MSG_ATTEST_GRANT, 11'h080); setup_auth();
          genuine_tail = 0; app4(MSG_ATTEST_GRANT, 11'h080); app4(MSG_ATTEST_REVOKE, 11'h000);
          settle_genuine(); repeat (LAT_BOUND) @(negedge clk);
          check(authorized === 1'b0, $sformatf("SF1_B2B_%0d authorized=%b", r, authorized));
        end
        begin automatic logic [31:0] a0;
          genuine_tail = 0; app4(MSG_ATTEST_GRANT, 11'h080); setup_auth();
          a0 = pacc[0];
          app4(MSG_ATTEST_GRANT, 11'h080); for (int k = 0; k < 8; k++) app4(MSG_ATTEST_REVOKE, 11'h000);
          settle_genuine(); repeat (LAT_BOUND) @(negedge clk);
          check(pacc[0] == a0 + 9, $sformatf("SF1_HELD_ACCEPTED accepted=+%0d (expected +9)", pacc[0] - a0));
          check(authorized === 1'b0, $sformatf("SF1_HELD_DEAUTH authorized=%b", authorized));
        end
        for (int r = 0; r < 10; r++) begin
          automatic bit replay = r >= 5;
          genuine_tail = 0; app4(MSG_ATTEST_GRANT, 11'h080); setup_auth();
          flooding_on = !replay;
          if (replay) app4p(MSG_ATTEST_CHALLENGE, 11'h000); else app4(MSG_ATTEST_GRANT, 11'h080);
          gate_ps = replay ? 6 : 4;                      // the REVOKE waits until slot P replays / verifies
          app4(MSG_ATTEST_REVOKE, 11'h000);
          settle_genuine(); gate_ps = -1; flooding_on = 1; repeat (LAT_BOUND) @(negedge clk);
          check(authorized === 1'b0, $sformatf("SF1_DURING_%s_%0d authorized=%b", replay ? "REPLAY" : "VERIFY", r % 5, authorized));
        end
`endif
        flooding = 0;
      end
    join
`ifndef SF1_ONLY_P1
    repeat (600) @(negedge clk);
    check(pdrop[0] == 0, $sformatf("SF1_P_SLOT_DROPS %0d", pdrop[0]));
    check(prej[0] == flood_sent, $sformatf("SF1_FLOOD_REJECTED rejected=%0d flood=%0d", prej[0], flood_sent));
    $display("STATS phase1 flood=%0d overlap=%0d accepted=%0d rejected=%0d p_slot_drops=%0d", flood_sent, overlap, pacc[0], prej[0], pdrop[0]);
    // ---- phase 2: per-packet rate-limit model
    begin
      automatic longint last_adm [6]; automatic int n6 = 0, n5 = 0;
      for (int s = 0; s < 6; s++) last_adm[s] = -1000;
      for (int i = 0; i < N_RL1 + N_RL2; i++) begin
        automatic int src = i < N_RL1 ? 5 : SRCS[i % 4]; automatic pkt_t p = rl_pkt(src);
        automatic logic [31:0] r0 = prej[0]; automatic longint th; automatic int exp_r, got_r, w = 0;
        @(negedge clk); prf[0] = p[0]; prv[0] = 1; @(posedge clk); th = cyc;
        for (int k = 1; k < 10; k++) put(p[k]);
        exp_r = (th - last_adm[src] >= T_RL) ? 5 : 6;
        if (exp_r == 5) last_adm[src] = th;
        @(negedge clk); prv[0] = 0;
        while (prej[0] == r0) begin @(negedge clk); if (++w > 50) timeout("rate-limit verdict"); end
        got_r = pwhy[0]; if (got_r == 6) n6++; else if (got_r == 5) n5++;
        check(got_r == exp_r && prej[0] == r0 + 1, $sformatf("SF1_RL_VERDICT pkt=%0d src=%0d got=%0d expected=%0d", i, src, got_r, exp_r));
        // back-to-back: the next HEAD follows directly (the verdict is visible one cycle after the TAIL)
      end
      $display("STATS phase2 reason5=%0d reason6=%0d", n5, n6);
    end
    check(flood_sent >= 1000, $sformatf("SF1_COVER_FLOOD %0d", flood_sent));
    check(overlap >= 15, $sformatf("SF1_COVER_OVERLAP %0d", overlap));
    check(d2_held >= 20, $sformatf("SF1_COVER_HELD %0d", d2_held));
`ifdef SF1_ACCT
    repeat (600) @(negedge clk);   // quiescence: no peer packet in flight
    $display("STATS acct tile3 accepted=%0d replayed=%0d rejected=%0d hold_max=%0d | tile4 accepted=%0d replayed=%0d rejected=%0d hold_max=%0d (H_MAX 512)",
             dut.peer_accepted[0], dut.peer_replayed[0], dut.peer_rejected[0], dut.peer_hold_max[0],
             dut.peer_accepted[1], dut.peer_replayed[1], dut.peer_rejected[1], dut.peer_hold_max[1]);
    for (int k = 0; k < 2; k++)
      check(dut.peer_accepted[k] == dut.peer_replayed[k] + dut.peer_rejected[k],
            $sformatf("SF1_ACCT_T%0d accepted=%0d replayed=%0d rejected=%0d", k + 3, dut.peer_accepted[k], dut.peer_replayed[k], dut.peer_rejected[k]));
    check(dut.peer_hold_max[0] <= 16'd512 && dut.peer_hold_max[1] <= 16'd512,
          $sformatf("SF1_HOLD_MAX tile3=%0d tile4=%0d (H_MAX 512)", dut.peer_hold_max[0], dut.peer_hold_max[1]));
`endif
`endif
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
