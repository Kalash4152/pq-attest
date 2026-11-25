`timescale 1ns/1ps
// tb_pq_endpoint_sys : PQ-2 system bench. pq_noc_subsystem (3x2 mesh, 6 NIs, noc_l2_auth at every
// tile, endpoint, verifier, gates) with PQ_MAC_ON. RoT challenge -> endpoint -> R-B response -> grant;
// SPOOF stalling and attacking through the raw spoof port. Expected values: vectors/full_chain.svh
// (thin adapter over the teammate reference; rows 0..2 == endpoint_golden V00..V02).
// Track Q2 2026-10-19: prepared, NOT compiled or simulated by Track Q2. Frozen count:
// reports/i3_q2/Q2_COUNT_DERIVATION.md. No $fatal for any check.
module tb_pq_endpoint_sys;
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
  pq_noc_subsystem dut(.*);
  `include "full_chain.svh"

  int checks = 0, errors = 0;
  int grants = 0, fails = 0, ep_starts = 0, ep_tx = 0, ep_err_tx = 0, rx_ready_viol = 0, commits_seen = 0;
  flit_t saved[17]; int saved_n = 0; bit save_on = 0;
  logic [511:0] cap_words, last_words; int cap_n = 0; bit cap_on = 0;
  logic [10:0] last_ctl; coord_t last_dest; int resp_seen = 0;

  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name);
    else begin errors++; $display("[FAIL] %s", name); end
  endtask

  // Endpoint TX monitor at the subsystem mux (port 3 while endpoint_busy).
  always @(posedge clk) begin
    if (rst) begin cap_on = 0; cap_n = 0; end
    else begin
      if (grant_done) grants++;
      if (attestation_failed) fails++;
      if (dut.controller_start) ep_starts++;
      if (dut.endpoint.rx_ready !== 1'b1) rx_ready_viol++;
      if (memory_commits != 0) commits_seen++;
      if (save_on && saved_n < 17 && dut.mesh_iv[4] && dut.mesh_ir[4]) begin saved[saved_n] = dut.mesh_in[4]; saved_n++; end
      if (dut.ertv && dut.ertready && dut.endpoint_busy) begin
        cap_on = 1; cap_n = 0; cap_words = '0; last_ctl = dut.ertctl; last_dest = dut.ertdest; ep_tx++;
        if (dut.ertctl[10:7] != 4'd1) ep_err_tx++;
      end else if (cap_on && dut.ertpv && dut.ertpready && dut.endpoint_busy) begin
        cap_words[32*cap_n +: 32] = dut.ertdata; cap_n++;
        if (cap_n == 16) begin cap_on = 0; last_words = cap_words; resp_seen++; end
      end
    end
  end

  task automatic pulse_start();
    @(negedge clk); start_attestation = 1; @(negedge clk); start_attestation = 0;
  endtask

  // Wait for a verifier verdict (grant or failure). Bounded beyond the verifier timeout.
  task automatic await_verdict(input int g0, input int f0, input string name);
    int n; n = 0;
    while (grants == g0 && fails == f0 && n < 150000) begin @(negedge clk); n++; end
    if (grants == g0 && fails == f0) begin errors++; $display("TB_TIMEOUT verdict %s", name); end
    repeat (50) @(negedge clk);
  endtask

  // A verifier grant only authorizes tile 3 once the GRANT packet has crossed the NoC and the tile-3 L2.
  // Wait for that delivery (authorized[3] rising), bounded; a timeout counts as an error (no extra check).
  // Kalash 2026-10-20: the original 50-cycle settle let S2's SPOOF traffic collide with the in-flight GRANT
  // (SF-1, docs/decisions/SF-1-l2-busy-drop.md). This bench therefore no longer exercises that collision.
  task automatic await_grant_delivery(input int g0, input string name);
    int n; n = 0;
    if (grants == g0) return;                       // no verifier grant: the GRANT check fails on its own
    while (!authorized[3] && n < 20000) begin @(negedge clk); n++; end
    if (!authorized[3]) begin errors++; $display("GRANT_DELIVERY_TIMEOUT %s", name); end
  endtask

  // One attestation of chain row idx: 5 checks.
  task automatic attest(input string p, input int idx);
    int g0, f0, r0;
    load_chain(idx); g0 = grants; f0 = fails; r0 = resp_seen;
    pulse_start(); await_verdict(g0, f0, p); await_grant_delivery(g0, p);
    check(resp_seen == r0 + 1 && last_ctl[10:7] == 4'd1 && last_ctl[6:0] == 0, {p, "_STATUS"});
    check(last_dest == tile_to_coord(TILE_ROT), {p, "_DEST"});
    check(last_words[255:0] === expected_response[264 +: 256], {p, "_MEAS_WORDS"});
    check(last_words[511:256] === expected_response[520 +: 256], {p, "_TAG_WORDS"});
    check(grants == g0 + 1 && fails == f0 && authorized[3], {p, "_GRANT"});
  endtask

  // Raw SPOOF packet toward CRYPTO, claiming source src. kind: 0 forged challenge (bad MAC),
  // 1 replay of the saved RoT challenge, 2 forged challenge on the wrong VC.
  // stall_after >= 0 stops injecting for stall_cycles after that many flits.
  task automatic spoof(input int kind, input int stall_after = -1, input int stall_cycles = 0);
    head_flit_t h; flit_t f; logic [159:0] fresh;
    fresh = {16'b0, BOOT, 64'd1000};
    for (int i = 0; i < 17; i++) begin
      if (i == stall_after) begin @(negedge clk); spoof_raw_valid = 0; repeat (stall_cycles) @(negedge clk); end
      @(negedge clk);
      if (kind == 1) f = saved[i];
      else begin
        f = '0; f.vc_id = (kind == 2) ? VC_REQUEST : VC_ATTESTATION;
        f.flit_type = (i == 0) ? FLIT_HEAD : (i == 16) ? FLIT_TAIL : FLIT_BODY;
        if (i == 0) begin
          h = '0; h.src_x = 1; h.src_y = 1; h.dest_x = 0; h.dest_y = 1;
          h.msg_type = MSG_ATTEST_CHALLENGE; h.length = 17; h.control.raw = 11'h0; f.flit_data = h;
        end
        else if (i <= 5) f.flit_data = fresh[(i-1)*32 +: 32];
        else if (i <= 12) f.flit_data = (i == 6) ? 32'h0000_0001 : 32'h5a5a_0000 + i;
        else f.flit_data = 32'hdead_0000 + i;      // garbage MAC
      end
      spoof_raw_flit = f; spoof_raw_valid = 1;
      do begin @(posedge clk); end while (!spoof_raw_ready);
    end
    @(negedge clk); spoof_raw_valid = 0;
  endtask

  // Endpoint untouched by a SPOOF action: 1 check.
  task automatic untouched(input string p, input int s0, input int t0, input int rj0);
    check(ep_starts == s0 && ep_tx == t0 && endpoint_rejected == rj0, {p, "_ENDPOINT_UNTOUCHED"});
  endtask

  initial begin
    $display("CONFIG: TOP=tb_pq_endpoint_sys MAC_FLITS=%0d CHALLENGE_WIRE_LEN=17 CLOCK_NS=20 TILE_KEY_BYTES=32", MAC_FLITS);
    app_valid = 0; app_payload_valid = 0; app_destination = '0; app_message = '0; app_control = 0; app_payload = 0;
    spoof_raw_flit = '0;
    load_chain(0); boot_epoch = BOOT; directed_keys = KEYS;
    repeat (6) @(negedge clk); rst = 0; repeat (5) @(negedge clk);
    check(!dut.endpoint_busy && endpoint_rejected == 0 && !dut.ertv && authorized == '0, "S0_RESET_IDLE");

    // S1 RoT challenge -> endpoint -> verifier grant (row 0), challenge wire recorded for replay.
    save_on = 1;
    attest("S1", 0);
    save_on = 0;
    check(endpoint_response === expected_response, "S1_INTERNAL_776");
    check(dut.endpoint.epoch === attest_epoch && dut.endpoint.nonce === nonce, "S1_EPOCH_NONCE_FIELDS");
    check(saved_n == 17 && endpoint_rejected == 0 && ep_starts == 1, "S1_ONE_CHALLENGE_NO_REJECT");

    // S2 forged challenge from SPOOF (claims RoT, VC2, bad MAC): dropped by L2 before the endpoint.
    begin : blk_s1 int s0, t0, rj0, l0; s0 = ep_starts; t0 = ep_tx; rj0 = endpoint_rejected; l0 = l2_rejected[3];
      spoof(0); repeat (600) @(negedge clk);
      check(l2_rejected[3] == l0 + 1 && l2_reason[3] == 4'd2, "S2_L2_MAC_REJECTED");
      untouched("S2", s0, t0, rj0);
      check(authorized[3] && fails == 0, "S2_NO_REVOKE");
    end
    // S3 replay of the recorded RoT challenge from SPOOF: L2 sequence rejection, no second crypto.
    begin : blk_s2 int s0, t0, rj0, a0; s0 = ep_starts; t0 = ep_tx; rj0 = endpoint_rejected; a0 = l2_accepted[3];
      spoof(1); repeat (600) @(negedge clk);
      check(l2_accepted[3] == a0 && l2_reason[3] == 4'd4, "S3_L2_REPLAY_REJECTED");
      untouched("S3", s0, t0, rj0);
      check(authorized[3] && fails == 0, "S3_NO_REVOKE");
    end
    // S4 forged challenge on the wrong VC (VC_REQUEST): L2 framing/header rejection.
    begin : blk_s3 int s0, t0, rj0, l0; s0 = ep_starts; t0 = ep_tx; rj0 = endpoint_rejected; l0 = l2_rejected[3];
      spoof(2); repeat (600) @(negedge clk);
      check(l2_rejected[3] == l0 + 1 && l2_reason[3] == 4'd1, "S4_L2_VC_REJECTED");
      untouched("S4", s0, t0, rj0);
    end
    // S5 SPOOF stalls mid-packet for 400 cycles (no attestation in flight), then completes.
    begin : blk_s4 int s0, t0, rj0, l0; s0 = ep_starts; t0 = ep_tx; rj0 = endpoint_rejected; l0 = l2_rejected[3];
      spoof(0, 4, 400); repeat (600) @(negedge clk);
      check(l2_rejected[3] == l0 + 1, "S5_L2_REJECTED_AFTER_STALL");
      untouched("S5", s0, t0, rj0);
      attest("S5", 1);
    end
    // S6 SPOOF stall concurrent with an outstanding RoT challenge: the stall may delay or drop the
    // challenge (L2 overload policy); at most one trusted retry must end in a correct grant.
    begin : blk_s5 int g0, f0, rj0, tries;
      rj0 = endpoint_rejected; load_chain(2); g0 = grants; f0 = fails; tries = 0;
      fork pulse_start(); spoof(0, 3, 300); join
      await_verdict(g0, f0, "S6");
      while (grants == g0 && tries < 1) begin
        tries++; f0 = fails; pulse_start(); await_verdict(g0, f0, "S6_RETRY");
      end
      await_grant_delivery(g0, "S6");
      check(grants == g0 + 1 && authorized[3], "S6_EVENTUALLY_GRANTED");
      check(last_ctl[10:7] == 4'd1 && last_words === expected_response[264 +: 512], "S6_RESPONSE_WORDS");
      check(endpoint_rejected == rj0, "S6_NO_SPOOF_IN_ENDPOINT");
    end
    // S7 reset while the endpoint computes cancels everything; trusted retry after reset.
    begin : blk_s6 int t0, n;
      load_chain(1); t0 = ep_tx; pulse_start();
      n = 0; while (dut.endpoint.es != 3 && n < 20000) begin @(negedge clk); n++; end
      if (dut.endpoint.es != 3) begin errors++; $display("TB_TIMEOUT S7 endpoint wait"); end
      repeat (10) @(negedge clk);
      rst = 1; boot_epoch = BOOT + 1; repeat (6) @(negedge clk);
      check(!dut.endpoint_busy && !dut.ertv && endpoint_rejected == 0 && authorized == '0 && !rot_busy &&
            endpoint_response == '0, "S7_RESET_CLEARS");
      rst = 0; t0 = ep_tx; n = grants;
      repeat (2000) @(negedge clk);
      check(ep_tx == t0 && grants == n && !dut.endpoint_busy, "S7_NO_STALE_RESPONSE");
      attest("S7R", 1);
    end

    check(rx_ready_viol == 0, "SYS_ENDPOINT_RX_READY_ALWAYS");
    check(ep_err_tx == 0, "SYS_ONLY_SUCCESS_REPLIES");
    check(commits_seen == 0, "SYS_NO_MEMORY_COMMIT");
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #24ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
