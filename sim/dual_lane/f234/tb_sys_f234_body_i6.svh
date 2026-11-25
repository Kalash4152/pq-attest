// Body of tb_sys_f234 (module/endmodule are in the wrappers NOC_PQATTEST.srcs/sim_1/new/tb_sys_f234{,_p7}.sv).
// Focused reproducers for the Codex audit findings F2, F3, F4 (Kalash addendum B, 2026-10-21) on pq_noc_subsystem
// (rtl/dual_lane, PQ_MAC_ON). Written to run FIRST on the current RTL (expected to FAIL there; the failing run is
// kept as evidence), then on the fixed RTL, and under one mutant per fix that restores the old behaviour.
//
// F2 (pq_rot_verifier: revoke handled only in V_IDLE). Per trial: reset, attestation of chain row 0 (tile 3
//   authorized), then a second attestation (row 1) with a one-cycle revoke pulse while the verifier is in state S,
//   S in {V_KWAIT, V_FILL, V_WAIT, V_TWAIT, V_GRANT} plus "TDONE" (the pulse in the cycle the tag check completes,
//   simultaneous with a valid completion). Rule (fixed design): revoke wins; no GRANT after the pulse; the RoT sends
//   REVOKE and tile 3 ends de-authorized.
//   Checks per trial: F2_NO_GRANT_<S> (no verifier grant after the pulse; in V_GRANT at most the GRANT already offered,
//   contract sec. 2), F2_DEAUTH_<S> (authorized[3] == 0 after
//   the settle window). 6 trials, 12 checks.
// F3 (pq_noc_subsystem TX mux switches owner on endpoint_busy / memory reply mid-packet).
//   F3: tile 3 authorized; its application's MEM_WR_REQ to tile 2 is accepted, its payload is withheld, a new
//   attestation makes the endpoint busy, then the payload is offered. Checks F3_APP_WRITE_COMMITTED (one commit, the
//   offered data), F3_ATTESTATION_GRANTED (the second attestation grants, no failure), F3_ENDPOINT_RESPONSE_SENT
//   (the endpoint's RESPONSE left tile 3: one more endpoint TX). 3 checks.
//   F3B: tile 2's application CHALLENGE to tile 0 is accepted with its payload withheld; tile 3 (authorized) issues
//   a MEM_RD_REQ, so the memory stand-in must reply from tile 2; then the payload is offered. Checks
//   F3B_MEM_REPLY_DELIVERED (tile 3 receives the RD_RESP), F3B_APP_PACKET_SENT (tile 0's L2 accepts the CHALLENGE).
//   2 checks.
// F4 (memory stand-in samples authorization at the HEAD, writes at the last payload). Revocation boundary (contract
//   sec. 3): the commit is decided with authorized[src] of the final-data cycle; no commit in a cycle with
//   authorized[3] = 0 (the gate drops authorized one cycle after the REVOKE head).
//   Calibration: one trial measures H (write start -> HEAD at tile 2) and C (-> commit) with a late revoke, one trial
//   measures L (revoke pulse -> REVOKE head at tile 3's gate). Sweep d = -3..+3: revoke pulsed so that the REVOKE head
//   lands at H + 1 + d. Checks: F4_CALIB_COMMIT (calibration write committed once, right data), F4_NO_COMMIT_AFTER_
//   REVOKE_<d> (no commit decided in a cycle with authorized[3] = 0) x 7, F4_COVER_WINDOW (>= 1 sweep trial has authorized
//   fall after the write HEAD and no later than the final-data cycle). 9 checks.
// F234_P7 (define): the same bench on the P7 subsystem rtl/dual_lane/pq_noc_subsystem_p7.sv (D2 peer path, the SF-1 fix the
//   rev-6 L2 lacks: run 113307 showed F2_DEAUTH failing on rev 6 because tile 3's single-slot L2 drops the REVOKE, reason 1).
//   Keys: K[4->3], K[3->4] from the chain's directed keys. F3B under P7: tile 2's application can send nothing (control
//   refused, R7.4; never authorized), so F3B_APP_PACKET_SENT becomes F3B_APP_REFUSED (its CHALLENGE header is refused:
//   tx_error seen, tile 2 sends nothing into the mesh); F3B_MEM_REPLY_DELIVERED is unchanged. Counts unchanged.
// CHECKS = 12 + 3 + 2 + 9 = 26, frozen before the first run. Setup failures (an attestation that does not grant in the
// setup phase, a bounded wait in a setup step) print TB_TIMEOUT (INVALID, never a pass).
// F234_ONLY_F2 (define, mutant job f234_p7_mut_f2 only; Kalash 2026-10-22): runs the F2 phase alone, CHECKS = 12, because
//   the F2 mutant (revoke ignored outside V_IDLE) leaves F4's calibration without a REVOKE head (a setup TB_TIMEOUT).
// F234_ONLY_F3 (define, F234_P7 only; job f234_p7_f3only and mutant f234_p7_mut_f3; Kalash 2026-10-22): F3 + F3B alone. The
//   live-owner mutant desynchronizes tile 3's TX (a stall), so both header waits become targeted bounded checks:
//   F3_APP_HEADER_ACCEPTED and F3B_READ_HEADER_ACCEPTED (accepted within N = 20,000 cycles, the app_hdr bound; tile 3's
//   TX is idle in this setup, so correct RTL accepts a data header within a few cycles). CHECKS = 1 + 3 + 1 + 2 = 7.
  import noc_pkg::*;
  logic clk = 0, rst = 1, start_attestation = 0, revoke = 0;
  always #10 clk = ~clk;
  logic [79:0] boot_epoch, attest_epoch;
  logic [127:0] nonce;
  logic [255:0] root_secret, approved_measurement;
  logic [9215:0] directed_keys;
  logic [111:0] context_in;
  logic [3:0] context_len;
  logic [511:0] config_data, imem;
  logic [6:0] config_len, imem_len;
  logic [5:0] app_valid, app_payload_valid, app_ready, app_payload_ready;
  coord_t [5:0] app_destination;
  msg_type_e [5:0] app_message;
  logic [5:0][10:0] app_control;
  logic [5:0][31:0] app_payload;
  logic spoof_raw_valid = 0, spoof_raw_ready;
  flit_t spoof_raw_flit;
  logic [5:0] authorized;
  logic rot_busy, grant_done, attestation_failed;
  logic [775:0] endpoint_response, expected_response;
  logic [31:0] memory_commits, memory_last_data, endpoint_rejected, verifier_rejected;
  logic [5:0][31:0] l2_rejected, l2_accepted, gate_faults;
  logic [5:0][3:0] l2_reason;
`ifdef F234_P7
  logic [5:0][31:0] ingress_rejected; logic [5:0][3:0] ingress_reason; logic [1:0][31:0] p_slot_drops; logic [5:0] app_tx_error;
  logic [511:0] keys_p7;
  assign keys_p7 = {directed_keys[(3*6+4)*256 +: 256], directed_keys[(4*6+3)*256 +: 256]};   // {K[3->4], K[4->3]}
  pq_noc_subsystem_p7 dut(.clk, .rst, .start_attestation, .revoke, .boot_epoch, .attest_epoch, .nonce, .root_secret,
    .approved_measurement, .directed_keys(keys_p7), .context_in, .context_len, .config_data, .imem, .config_len, .imem_len,
    .trusted_clear(1'b0), .app_valid, .app_payload_valid, .app_ready, .app_payload_ready, .app_destination, .app_message, .app_control, .app_payload,
    .spoof_raw_valid, .spoof_raw_flit, .spoof_raw_ready, .authorized, .rot_busy, .grant_done, .attestation_failed,
    .endpoint_response, .memory_commits, .memory_last_data, .l2_rejected, .l2_accepted, .gate_faults, .ingress_rejected,
    .l2_reason, .ingress_reason, .p_slot_drops, .app_tx_error, .endpoint_rejected, .verifier_rejected);
  localparam string DUT = "P7";
`else
  pq_noc_subsystem dut(.*);
  localparam string DUT = "REV6";
`endif
  `include "full_chain.svh"
  localparam logic [31:0] ADDR = 32'h2200_0100;    // C-5 window (I-6)

  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  task automatic timeout(input string w); $display("TB_TIMEOUT %s", w); $finish; endtask

  longint cyc = 0; int grants = 0, fails = 0, ep_tx = 0, rd_resp3 = 0;
  longint t_grant_last = -1, t_revhead = -1, t_head2 = -1, t_commit_dec = -1;
  int bad_commit = 0;
  logic [31:0] commits_q = 0;
  logic auth3_q = 0, revhead_q = 0;
  always @(posedge clk) begin
    cyc++;
    if (!rst) begin
      if (grant_done) begin grants++; t_grant_last = cyc; end
      if (attestation_failed) fails++;
      if (dut.ertv && dut.ertready && dut.endpoint_busy) ep_tx++;
      if (dut.rhv[3] && dut.rxmsg[3] == MSG_MEM_RD_RESP) rd_resp3++;
      if (dut.rhv[3] && dut.rxmsg[3] == MSG_ATTEST_REVOKE && t_revhead < 0) t_revhead = cyc;
      if (dut.rhv[2] && dut.rxmsg[2] == MSG_MEM_WR_REQ && t_head2 < 0) t_head2 = cyc;
      // a commit becomes visible one cycle after its decision; judge the decision cycle (values one cycle back)
      if (memory_commits != commits_q) begin
        t_commit_dec = cyc - 1;
        if (!auth3_q) bad_commit++;   // contract sec. 3: the boundary is the first cycle with authorized[src] = 0
      end
      commits_q = memory_commits; auth3_q = authorized[3];
      revhead_q = dut.rhv[3] && dut.rxmsg[3] == MSG_ATTEST_REVOKE;
    end else begin commits_q = 0; auth3_q = 0; revhead_q = 0; end
  end

  task automatic do_reset();
    @(negedge clk); rst = 1; app_valid = 0; app_payload_valid = 0; revoke = 0; start_attestation = 0;
    repeat (6) @(negedge clk); rst = 0; repeat (5) @(negedge clk);
    t_revhead = -1; t_head2 = -1; t_commit_dec = -1; bad_commit = 0;
  endtask
  task automatic pulse_start(); @(negedge clk); start_attestation = 1; @(negedge clk); start_attestation = 0; endtask
  task automatic pulse_revoke(); @(negedge clk); revoke = 1; @(negedge clk); revoke = 0; endtask
  // setup attestation: must grant and authorize tile 3
  task automatic attest_ok(input int row);
    automatic int g0 = grants, n = 0;
    load_chain(row); pulse_start();
    while (!(grants == g0 + 1 && authorized[3]) && n < 60000) begin @(negedge clk); n++; end
    if (!(grants == g0 + 1 && authorized[3])) timeout($sformatf("setup attestation row %0d", row));
    repeat (20) @(negedge clk);
  endtask
  task automatic wait_cyc(input int n); repeat (n) @(negedge clk); endtask
  // application TX at tile g: header handshake, then payload words (bounded); returns 1 if all words were taken
  task automatic app_hdr(input int g, input coord_t d, input msg_type_e m, input logic [10:0] c, output bit ok);
    automatic int n = 0;
    @(negedge clk); app_destination[g] = d; app_message[g] = m; app_control[g] = c; app_valid[g] = 1;
    do begin @(posedge clk); n++; end while (!app_ready[g] && n < 20000);
    ok = app_ready[g]; @(negedge clk); app_valid[g] = 0;
  endtask
  task automatic app_words(input int g, input logic [31:0] w [4], input int nw, input int limit, output bit ok);
    ok = 1;
    for (int i = 0; i < nw && ok; i++) begin
      automatic int n = 0;
      app_payload[g] = w[i]; app_payload_valid[g] = 1;
      do begin @(posedge clk); n++; end while (!app_payload_ready[g] && n < limit);
      ok = app_payload_ready[g]; @(negedge clk);
    end
    app_payload_valid[g] = 0;
  endtask

  // ---------------- F2
  task automatic f2_trial(input int st, input string name);
    automatic int g0, n = 0;
    do_reset(); attest_ok(0);
    load_chain(1); pulse_start();
    if (st == 100) begin   // TDONE: the cycle the tag check completes
      while (!(dut.verifier.vs == 8 && dut.verifier.td) && n < 60000) begin @(negedge clk); n++; end
    end else while (dut.verifier.vs != st && n < 60000) begin @(negedge clk); n++; end
    if (n >= 60000) timeout({"F2 state wait ", name});
    revoke = 1; g0 = grants; @(negedge clk); revoke = 0;
    n = 0; while ((rot_busy || dut.verifier.vs != 0) && n < 60000) begin @(negedge clk); n++; end
    wait_cyc(4000);
    // contract sec. 2 (Q5): a GRANT already offered in V_GRANT is held to its handshake and then followed by REVOKE, so the
    // GRANT-state trial allows that one in-flight grant; every other state allows none. F2_DEAUTH stays strict.
    check(grants - g0 <= (st == 9 ? 1 : 0), $sformatf("F2_NO_GRANT_%s grants_after_revoke=%0d", name, grants - g0));
    check(authorized[3] == 0, $sformatf("F2_DEAUTH_%s authorized3=%b", name, authorized[3]));
  endtask

  initial begin
    bit ok, ok2; logic [31:0] w [4];
`ifdef F234_ONLY_F2
    $display("CONFIG: TOP=tb_sys_f234 DUT=%s CHECKS_F2=12 CHECKS_F3=5 CHECKS_F4=9 ADDR=%h PHASES=F2 CHECKS=12", DUT, ADDR);
`elsif F234_ONLY_F3
    $display("CONFIG: TOP=tb_sys_f234 DUT=%s CHECKS_F2=12 CHECKS_F3=5 CHECKS_F4=9 ADDR=%h PHASES=F3 CHECKS=7", DUT, ADDR);
`else
    $display("CONFIG: TOP=tb_sys_f234 DUT=%s CHECKS_F2=12 CHECKS_F3=5 CHECKS_F4=9 ADDR=%h PHASES=ALL CHECKS=26", DUT, ADDR);
`endif
    app_valid = 0; app_payload_valid = 0; app_destination = '0; app_message = '0; app_control = 0; app_payload = 0;
    spoof_raw_flit = '0;
    load_chain(0); boot_epoch = BOOT; directed_keys = KEYS;
    repeat (6) @(negedge clk); rst = 0; repeat (5) @(negedge clk);
    // ---- F2: states V_KWAIT 2, V_FILL 4, V_WAIT 5, V_TWAIT 8, V_GRANT 9, TDONE
`ifndef F234_ONLY_F3
    f2_trial(2, "KWAIT"); f2_trial(4, "FILL"); f2_trial(5, "WAIT"); f2_trial(8, "TWAIT"); f2_trial(9, "GRANT"); f2_trial(100, "TDONE");
`endif
`ifndef F234_ONLY_F2
    // ---- F3
    begin
      automatic int c0, g0, f0, t0, n = 0; automatic coord_t mem = tile_to_coord(TILE_MEMORY);
      do_reset(); attest_ok(0);
      c0 = memory_commits; t0 = ep_tx;
      app_hdr(3, mem, MSG_MEM_WR_REQ, 11'h780, ok);
`ifdef F234_ONLY_F3
      check(ok, $sformatf("F3_APP_HEADER_ACCEPTED within 20000 cycles accepted=%b", ok));
`else
      if (!ok) timeout("F3 application header not accepted");
`endif
      load_chain(1); g0 = grants; f0 = fails; pulse_start();
      while (!dut.endpoint_busy && n < 60000) begin @(negedge clk); n++; end
      if (!dut.endpoint_busy) timeout("F3 endpoint never busy");
      wait_cyc(100);
      w[0] = ADDR; w[1] = 32'hF3F3_0001; app_words(3, w, 2, 20000, ok);
      n = 0; while (!(memory_commits == c0 + 1 && grants == g0 + 1) && n < 60000) begin @(negedge clk); n++; end
      check(memory_commits == c0 + 1 && memory_last_data == 32'hF3F3_0001, $sformatf("F3_APP_WRITE_COMMITTED commits=%0d payload_taken=%b", memory_commits - c0, ok));
      check(grants == g0 + 1 && fails == f0, $sformatf("F3_ATTESTATION_GRANTED grants=%0d fails=%0d", grants - g0, fails - f0));
      check(ep_tx == t0 + 1, $sformatf("F3_ENDPOINT_RESPONSE_SENT ep_tx=%0d", ep_tx - t0));
    end
    // ---- F3B
`ifdef F234_P7
    begin
      automatic int r0, n = 0; automatic bit refused = 0, sent2 = 0; automatic coord_t mem = tile_to_coord(TILE_MEMORY), t0c = tile_to_coord(TILE_CPU0);
      do_reset(); attest_ok(0);
      r0 = rd_resp3;
      @(negedge clk); app_destination[2] = t0c; app_message[2] = MSG_ATTEST_CHALLENGE; app_control[2] = 0; app_valid[2] = 1;
      app_hdr(3, mem, MSG_MEM_RD_REQ, 11'h000, ok2);
`ifdef F234_ONLY_F3
      check(ok2, $sformatf("F3B_READ_HEADER_ACCEPTED within 20000 cycles accepted=%b", ok2));
`else
      if (!ok2) timeout("F3B tile-3 read header not accepted");
`endif
      w[0] = ADDR; app_words(3, w, 1, 20000, ok2);
      n = 0; while (rd_resp3 != r0 + 1 && n < 40000) begin @(negedge clk); n++; if (app_tx_error[2]) refused = 1;
        begin automatic head_flit_t h2 = head_flit_t'(dut.tile_out[2].flit_data);
          if (dut.tile_ov[2] && dut.tile_out[2].flit_type inside {FLIT_HEAD, FLIT_HEAD_TAIL} && h2.msg_type[3:2] == 2'b01) sent2 = 1; end
        end   // the memory reply also leaves tile 2; only a control HEAD counts
      check(rd_resp3 == r0 + 1, $sformatf("F3B_MEM_REPLY_DELIVERED rd_resp=%0d", rd_resp3 - r0));
      check(refused && !sent2, $sformatf("F3B_APP_REFUSED tx_error_seen=%b tile2_sent=%b", refused, sent2));
      @(negedge clk); app_valid[2] = 0;
    end
`else
    begin
      automatic int r0, a0, n = 0; automatic coord_t mem = tile_to_coord(TILE_MEMORY), t0c = tile_to_coord(TILE_CPU0);
      do_reset(); attest_ok(0);
      r0 = rd_resp3; a0 = l2_accepted[0];
      app_hdr(2, t0c, MSG_ATTEST_CHALLENGE, 11'h000, ok);
      if (!ok) timeout("F3B tile-2 application header not accepted");
      app_hdr(3, mem, MSG_MEM_RD_REQ, 11'h000, ok2);
      if (!ok2) timeout("F3B tile-3 read header not accepted");
      w[0] = ADDR; app_words(3, w, 1, 20000, ok2);
      n = 0; while (!dut.mtv && n < 20000) begin @(negedge clk); n++; end
      wait_cyc(50);
      begin automatic logic [31:0] cw [4]; cw[0] = 1; cw[1] = 2; cw[2] = 3; cw[3] = 4;
        for (int k = 0; k < 2 && ok; k++) app_words(2, cw, (k == 0) ? 4 : 3, 20000, ok); end
      n = 0; while (!(rd_resp3 == r0 + 1 && l2_accepted[0] == a0 + 1) && n < 40000) begin @(negedge clk); n++; end
      check(rd_resp3 == r0 + 1, $sformatf("F3B_MEM_REPLY_DELIVERED rd_resp=%0d", rd_resp3 - r0));
      check(l2_accepted[0] == a0 + 1 && ok, $sformatf("F3B_APP_PACKET_SENT tile0_accepted=%0d payload_taken=%b", l2_accepted[0] - a0, ok));
    end
`endif
`ifndef F234_ONLY_F3
    // ---- F4
    begin
      automatic longint H, C, L, T0; automatic int window = 0; automatic coord_t mem = tile_to_coord(TILE_MEMORY);
      // calibration 1: write with no revoke
      do_reset(); attest_ok(0);
      T0 = cyc; begin automatic int c0 = memory_commits;
        app_hdr(3, mem, MSG_MEM_WR_REQ, 11'h780, ok); w[0] = ADDR; w[1] = 32'hF4F4_0000; app_words(3, w, 2, 20000, ok2);
        wait_cyc(3000);
        check(memory_commits == c0 + 1 && memory_last_data == 32'hF4F4_0000 && bad_commit == 0, $sformatf("F4_CALIB_COMMIT commits=%0d", memory_commits - c0));
      end
      if (t_head2 < 0 || t_commit_dec < 0) timeout("F4 calibration: no HEAD/commit");
      H = t_head2 - T0; C = t_commit_dec - T0;
      // calibration 2: revoke alone
      do_reset(); attest_ok(0);
      T0 = cyc; pulse_revoke(); wait_cyc(4000);
      if (t_revhead < 0) timeout("F4 calibration: no REVOKE head");
      L = t_revhead - T0;
      $display("F4 calibration H=%0d C=%0d L=%0d", H, C, L);
      for (int d = -3; d <= 3; d++) begin
        automatic longint R = H + 1 + d - L;
        do_reset(); attest_ok(0);
        T0 = cyc;
        fork
          // whichever path is slower starts first (P7: plain data is far faster than the REVOKE path)
          begin if (R < 0) wait_cyc(int'(-R)); app_hdr(3, mem, MSG_MEM_WR_REQ, 11'h780, ok); w[0] = ADDR; w[1] = 32'hF4F4_0000 + d + 3; app_words(3, w, 2, 20000, ok2); end
          begin if (R > 0) wait_cyc(int'(R)); pulse_revoke(); end
        join
        wait_cyc(4000);
        if (R < 0) T0 = T0 - R;   // offsets below are reported relative to the write start
        // window: authorized falls (REVOKE head + 1) after the write HEAD and no later than the final-data cycle
        if (t_head2 >= 0 && t_revhead >= 0 && t_revhead + 1 > t_head2 && (t_commit_dec < 0 || t_revhead + 1 <= t_commit_dec)) window++;
        check(bad_commit == 0, $sformatf("F4_NO_COMMIT_AFTER_REVOKE_%0d head=%0d revhead=%0d commit_dec=%0d", d, t_head2 - T0, t_revhead - T0, t_commit_dec < 0 ? -1 : t_commit_dec - T0));
      end
      check(window >= 1, $sformatf("F4_COVER_WINDOW trials_in_window=%0d", window));
    end
`endif
`endif
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #60ms; $display("TB_TIMEOUT global"); $finish; end
`ifdef P7_HEARTBEAT
  initial forever begin #10us; $display("HEARTBEAT %0t", $time); end   // scratch hang probe only
  initial for (int k = 0; k < 100; k++) begin #20ns; $display("HB %0t rst=%b", $time, rst); end
`endif
