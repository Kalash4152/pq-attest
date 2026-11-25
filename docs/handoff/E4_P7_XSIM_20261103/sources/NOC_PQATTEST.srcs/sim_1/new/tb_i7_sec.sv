`timescale 1ns/1ps
// I-7 PQ-4 SEC-1..4 matrix (docs/decisions/I7_SEC_MATRIX.md) on the I-6 P7 subsystem (rtl/dual_lane/pq_noc_subsystem_p7.sv,
// S3 / I-6 list, PQ_MAC_ON), the real NOC-3 / NOC-4 modules; TB_INJECT = 1 for the bench-only hooks:
//  - TBI.ep_sub / ep_ctl / ep_words: a COMPROMISED tile 3 sends attacker-chosen RESPONSE status and words; its L2 still
//    authenticates them (the attacker holds tile 3's L2 key), so the attestation layer alone must refuse them;
//  - TBI.v / f[g]: flits presented at tile g's network input (L2 replay into tile 3);
//  - raw injector at tile 5 (the real SPOOF port, through the ingress quarantine).
// Expected verdicts: vectors/i7_sec.svh (scripts/gen_i7_vectors.py: teammate reference via s8_golden + policy layer; the
// L2 reasons from scripts/l2_golden.py rx_verdict), never from the RTL. Fault reasons are the I-6 map (I6_CONTRACT sec. 3).
// Checks (CHECKS = 30, frozen in the I-7 matrix before the first run):
//  SEC1_GENUINE_GRANT (row 0: grant, endpoint_response == teammate expected_response), SEC1_AUTH_WRITE (write commits)  2
//  per vector row R of i7_sec.svh except SUBST_IMEM (9 rows), starting authorized each time, tile 3 substitutes R:
//    SEC_<R>_VERDICT  expect 0: grant and authorized; else: no grant, a verifier record (3, RESPONSE, expect), not authorized
//    SEC_<R>_ISOLATED expect 0: a write commits; else: the write header is refused, no commit                         18
//  SEC4_SUBST_VERDICT (imem input substituted at re-attestation: record (3, RESPONSE, 11), no grant, not authorized),
//  SEC4_SUBST_ISOLATED (write refused), SEC4_RESTORED_GRANT (original imem: grants again)                              3
//  SEC3_L2_REPLAY (a captured genuine GRANT replayed into tile 3 after a revoke: tile-3 L2 rejects with 4, not authorized) 1
//  SEC3_RESET_REPLAY (the same GRANT replayed after a reset with a new boot epoch: rejected with 3, not authorized)       1
//  SEC2_SPOOF_RESPONSE (a well-formed RESPONSE from the raw port at tile 5 to tile 4: tile-4 L2 rejects with 5, the
//    verifier never sees it, no grant)                                                                                1
//  SEC_TRUNC_CHALLENGE (a 3-flit CHALLENGE from the raw port to tile 3: the tile-5 quarantine rejects it with 11 (M-F1
//    R7.5b: length != P7 message_length), nothing reaches tile 3's L2, the endpoint sends nothing)                        1
//  SEC_STATUS_CLEAR_MISUSE (after faults, application traffic on every tile and a GRANT leave fault_sticky / count set;
//    only trusted_clear clears them)                                                                                   1
//  SEC_CONCURRENT_SPOOF (a genuine attestation while the raw port floods tile 3: grant, flood forwarded, no spoof commit) 1
//  SEC_NO_UNAUTH_COMMIT (every commit decided with authorized[3] = 1)                                                    1
// Bounded waits feed checks; TB_TIMEOUT only for the global limit.
module tb_i7_sec;
  import noc_pkg::*;
  import noc_p7_pkg::*;
  logic clk = 0, rst = 1, start_attestation = 0, revoke = 0, trusted_clear = 0;
  always #10 clk = ~clk;
  logic [79:0] boot_epoch, attest_epoch;
  logic [127:0] nonce;
  logic [255:0] root_secret, approved_measurement;
  logic [9215:0] directed_keys;
  logic [111:0] context_in;
  logic [3:0] context_len;
  logic [511:0] config_data, imem;
  logic [6:0] config_len, imem_len;
  logic [5:0] app_valid, app_payload_valid, app_ready, app_payload_ready, app_tx_error;
  coord_t [5:0] app_destination;
  msg_type_e [5:0] app_message;
  logic [5:0][10:0] app_control;
  logic [5:0][31:0] app_payload;
  logic spoof_raw_valid = 0, spoof_raw_ready;
  flit_t spoof_raw_flit;
  logic [5:0] authorized;
  logic rot_busy, grant_done, attestation_failed;
  logic [775:0] endpoint_response, expected_response;
  logic [31:0] memory_commits, memory_last_data, endpoint_rejected, verifier_rejected, q_forwarded, q_rejected;
  logic [3:0] q_reason;
  logic [5:0][31:0] gate_faults, l2_rejected;
  logic [5:0][3:0] l2_reason;
  logic fault_sticky; logic [31:0] fault_count; logic [2:0] fault_source; logic [3:0] fault_operation, fault_reason;
  logic [79:0] fault_epoch;
  logic [511:0] keys_p7;
  assign keys_p7 = {directed_keys[(3*6+4)*256 +: 256], directed_keys[(4*6+3)*256 +: 256]};
  pq_noc_subsystem_p7 #(.TB_INJECT(1'b1), .VERIFIER_TIMEOUT(20000)) dut(.clk, .rst, .start_attestation, .revoke, .trusted_clear,
    .boot_epoch, .attest_epoch, .nonce, .root_secret,
    .approved_measurement, .directed_keys(keys_p7), .context_in, .context_len, .config_data, .imem, .config_len, .imem_len,
    .app_valid, .app_payload_valid, .app_ready, .app_payload_ready, .app_destination, .app_message, .app_control, .app_payload,
    .spoof_raw_valid, .spoof_raw_flit, .spoof_raw_ready, .authorized, .rot_busy, .grant_done, .attestation_failed,
    .endpoint_response, .memory_commits, .memory_last_data, .gate_faults, .l2_rejected, .l2_reason, .q_forwarded, .q_rejected, .q_reason,
    .app_tx_error, .endpoint_rejected, .verifier_rejected,
    .fault_sticky, .fault_count, .fault_source, .fault_operation, .fault_reason, .fault_epoch);
  `include "full_chain.svh"
  `include "i7_sec.svh"
  localparam logic [31:0] ADDR = 32'h2200_0100;
  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask

  // ---- monitors
  typedef struct { int src; int op; int reason; } rec_t;
  rec_t recs [$];
  int grants = 0, n_commit = 0, bad_commit = 0, hdr3_acc = 0, ep_tx = 0;
  logic [31:0] commits_q = 0, fc_q = 0;
  logic auth3_q = 0;
  // capture of the first GRANT delivered at tile 3's network input after arm_cap (for the L2 replays)
  flit_t cap [32]; int cap_n = 0; bit arm_cap = 0, capturing = 0;
  head_flit_t h3;
  assign h3 = head_flit_t'(dut.mesh_out[3].flit_data);
  always @(posedge clk) begin
    if (!rst) begin
      if (grant_done) grants++;
      if (app_valid[3] && app_ready[3]) hdr3_acc++;
      if (dut.ertv && dut.ertready) ep_tx++;
      if (memory_commits != commits_q) begin n_commit++; if (!auth3_q) bad_commit++; end
      if (fault_count != fc_q && fault_count != 0) recs.push_back('{int'(fault_source), int'(fault_operation), int'(fault_reason)});
      if (dut.mesh_ov[3] && dut.mesh_or[3]) begin
        if (arm_cap && !capturing && dut.mesh_out[3].flit_type == FLIT_HEAD && h3.msg_type == MSG_ATTEST_GRANT) begin
          capturing = 1; cap_n = 0; end
        if (capturing) begin cap[cap_n] = dut.mesh_out[3]; cap_n++;
          if (dut.mesh_out[3].flit_type == FLIT_TAIL) begin capturing = 0; arm_cap = 0; end end
      end
      commits_q = memory_commits; auth3_q = authorized[3]; fc_q = fault_count;
    end else begin commits_q = 0; auth3_q = 0; fc_q = 0; end
  end
  function automatic bit seen(input int from, input int src, input int op, input int reason);
    for (int i = from; i < recs.size(); i++) if (recs[i].src == src && recs[i].op == op && recs[i].reason == reason) return 1;
    return 0;
  endfunction

  // ---- helpers (bounded)
  task automatic do_reset();
    @(negedge clk); rst = 1; app_valid = 0; app_payload_valid = 0; revoke = 0; start_attestation = 0; spoof_raw_valid = 0;
    trusted_clear = 0; repeat (6) @(negedge clk); rst = 0; repeat (5) @(negedge clk);
  endtask
  task automatic pulse_start(); @(negedge clk); start_attestation = 1; @(negedge clk); start_attestation = 0; endtask
  task automatic wait_idle(); automatic int n = 0; while ((rot_busy || dut.verifier.vs != 0) && n < 60000) begin @(negedge clk); n++; end endtask
  task automatic attest(input int row, output bit ok);
    automatic int g0 = grants, n = 0;
    load_chain(row); pulse_start();
    while (!(grants == g0 + 1 && authorized[3]) && n < 60000) begin @(negedge clk); n++; end
    ok = grants == g0 + 1 && authorized[3];
    wait_idle(); repeat (20) @(negedge clk);
  endtask
  task automatic app_hdr(input int g, input coord_t d, input msg_type_e m, input logic [10:0] c, input int limit, output bit ok);
    automatic int n = 0;
    @(negedge clk); app_destination[g] = d; app_message[g] = m; app_control[g] = c; app_valid[g] = 1;
    do begin @(posedge clk); n++; end while (!app_ready[g] && n < limit);
    ok = app_ready[g]; @(negedge clk); app_valid[g] = 0;
  endtask
  task automatic app_words(input int g, input logic [31:0] w0, input logic [31:0] w1, input int nw, output bit ok);
    ok = 1;
    for (int i = 0; i < nw && ok; i++) begin
      automatic int n = 0;
      app_payload[g] = i == 0 ? w0 : w1; app_payload_valid[g] = 1;
      do begin @(posedge clk); n++; end while (!app_payload_ready[g] && n < 2000);
      ok = app_payload_ready[g]; @(negedge clk);
    end
    app_payload_valid[g] = 0;
  endtask
  // write attempt from tile 3; ok = header accepted and the data committed
  task automatic try_write(input logic [31:0] d, output bit committed, output bit hdr_ok);
    automatic bit ok2 = 0; automatic int c0 = memory_commits;
    app_hdr(3, tile_to_coord(TILE_MEMORY), MSG_MEM_WR_REQ, 11'h780, 300, hdr_ok);
    if (hdr_ok) app_words(3, ADDR, d, 2, ok2);
    repeat (400) @(negedge clk);
    committed = hdr_ok && ok2 && memory_commits == c0 + 1 && memory_last_data == d;
  endtask
  task automatic raw(input flit_t f);
    automatic int n = 0;
    @(negedge clk); spoof_raw_flit = f; spoof_raw_valid = 1;
    do begin @(posedge clk); n++; end while (!spoof_raw_ready && n < 2000);
    @(negedge clk); spoof_raw_valid = 0;
  endtask
  // a raw packet from tile 5: HEAD (type m, dest d, header length len) + len - 1 zero words, last one TAIL
  task automatic raw_packet(input int d, input msg_type_e m, input int len);
    automatic head_flit_t h; automatic flit_t f; automatic coord_t s, dc;
    h = '0; s = tile_to_coord(TILE_SPOOF); dc = tile_to_coord(tile_id_e'(d));
    h.src_x = s.x; h.src_y = s.y; h.dest_x = dc.x; h.dest_y = dc.y; h.msg_type = m; h.length = 5'(len);
    f.flit_data = h; f.flit_type = FLIT_HEAD; f.vc_id = 2'(message_to_vc(m)); raw(f);
    for (int k = 1; k < len; k++) begin f.flit_data = '0; f.flit_type = k == len - 1 ? FLIT_TAIL : FLIT_BODY; raw(f); end
  endtask
  task automatic present(input int g, input flit_t f);
    @(negedge clk); dut.TBI.f[g] = f; dut.TBI.v[g] = 1;
    do @(posedge clk); while (!dut.mesh_or[g]); @(negedge clk); dut.TBI.v[g] = 0;
  endtask

  bit flood = 0;
  initial forever begin
    @(negedge clk);
    if (flood) begin
      automatic head_flit_t h; automatic flit_t f; automatic coord_t s, d;
      h = '0; s = tile_to_coord(TILE_SPOOF); d = tile_to_coord(TILE_CRYPTO);
      h.src_x = s.x; h.src_y = s.y; h.dest_x = d.x; h.dest_y = d.y; h.msg_type = MSG_MEM_RD_REQ; h.length = 5'd2;
      f.flit_data = h; f.flit_type = FLIT_HEAD; f.vc_id = 2'(message_to_vc(MSG_MEM_RD_REQ)); spoof_raw_flit = f; spoof_raw_valid = 1;
      do @(posedge clk); while (!spoof_raw_ready); @(negedge clk);
      f.flit_data = ADDR; f.flit_type = FLIT_TAIL; spoof_raw_flit = f;
      do @(posedge clk); while (!spoof_raw_ready); @(negedge clk); spoof_raw_valid = 0;
    end
  end

  initial begin
    bit ok, ok_pre, com, hdr; int mark, g0, r0, e0, v0, q0;
    $display("CONFIG: TOP=tb_i7_sec CHECKS=30 ROWS=%0d", I7_ROWS);
    app_valid = 0; app_payload_valid = 0; app_destination = '0; app_message = '0; app_control = 0; app_payload = 0; spoof_raw_flit = '0;
    load_chain(0); boot_epoch = BOOT; directed_keys = KEYS;
    do_reset();
    // SEC-1 genuine
    attest(0, ok);
    check(ok && endpoint_response == expected_response, $sformatf("SEC1_GENUINE_GRANT granted=%0b response_match=%0b", ok, endpoint_response == expected_response));
    try_write(32'h5EC1_0001, com, hdr);
    check(com, $sformatf("SEC1_AUTH_WRITE committed=%0b", com));
    // compromised tile 3: each substitution row, from an authorized state (row 0), challenge row 1
    for (int r = 0; r < I7_ROWS; r++) begin
      if (r == I7_SUBST_ROW) continue;
      attest(0, ok_pre);
      mark = recs.size(); g0 = grants;
      @(negedge clk); dut.TBI.ep_ctl = {4'(I7_STATUS[r]), 7'b0}; dut.TBI.ep_words = I7_WORDS[r]; dut.TBI.ep_sub = 1;
      load_chain(1); pulse_start();
      begin automatic int n = 0; while (rot_busy && n < 60000) begin @(negedge clk); n++; end end
      wait_idle(); repeat (50) @(negedge clk); dut.TBI.ep_sub = 0;
      if (I7_EXPECT[r] == 0)
        check(ok_pre && grants == g0 + 1 && authorized[3], $sformatf("SEC_%s_VERDICT expect=grant grants=+%0d authorized3=%b", i7_name(r), grants - g0, authorized[3]));
      else
        check(ok_pre && grants == g0 && !authorized[3] && seen(mark, 3, MSG_ATTEST_RESPONSE, I7_EXPECT[r]),
              $sformatf("SEC_%s_VERDICT expect=%0d grants=+%0d authorized3=%b recorded=%0b", i7_name(r), I7_EXPECT[r], grants - g0, authorized[3], seen(mark, 3, MSG_ATTEST_RESPONSE, I7_EXPECT[r])));
      try_write(32'h5EC0_0000 + r, com, hdr);
      check(I7_EXPECT[r] == 0 ? com : (!hdr && !com), $sformatf("SEC_%s_ISOLATED committed=%0b header_accepted=%0b", i7_name(r), com, hdr));
    end
    // SEC-4: runtime imem substitution at re-attestation (the genuine endpoint measures the substituted image)
    attest(0, ok_pre);
    mark = recs.size(); g0 = grants;
    load_chain(1); imem = I7_SUBST_IMEM; pulse_start();
    begin automatic int n = 0; while (rot_busy && n < 60000) begin @(negedge clk); n++; end end
    wait_idle(); repeat (50) @(negedge clk);
    check(ok_pre && grants == g0 && !authorized[3] && seen(mark, 3, MSG_ATTEST_RESPONSE, 11),
          $sformatf("SEC4_SUBST_VERDICT grants=+%0d authorized3=%b", grants - g0, authorized[3]));
    try_write(32'h5EC4_0001, com, hdr);
    check(!hdr && !com, $sformatf("SEC4_SUBST_ISOLATED committed=%0b header_accepted=%0b", com, hdr));
    attest(0, ok);
    check(ok, $sformatf("SEC4_RESTORED_GRANT granted=%0b", ok));
    // SEC-3 L2 replay: capture the GRANT of a genuine attestation, revoke, replay it into tile 3
    @(negedge clk); revoke = 1; @(negedge clk); revoke = 0; wait_idle(); repeat (100) @(negedge clk);
    arm_cap = 1; attest(1, ok_pre); repeat (20) @(negedge clk);
    @(negedge clk); revoke = 1; @(negedge clk); revoke = 0; wait_idle(); repeat (200) @(negedge clk);
    r0 = l2_rejected[3];
    for (int k = 0; k < cap_n; k++) present(3, cap[k]);
    repeat (600) @(negedge clk);
    check(ok_pre && cap_n > 0 && !authorized[3] && l2_rejected[3] == r0 + 1 && l2_reason[3] == I7_L2_REPLAY_REASON,
          $sformatf("SEC3_L2_REPLAY flits=%0d authorized3=%b rejected=+%0d reason=%0d expect=%0d", cap_n, authorized[3], l2_rejected[3] - r0, l2_reason[3], I7_L2_REPLAY_REASON));
    // SEC-3 reset replay: reboot with a new boot epoch, replay the same GRANT
    boot_epoch = BOOT ^ 80'h1; do_reset();
    r0 = l2_rejected[3];
    for (int k = 0; k < cap_n; k++) present(3, cap[k]);
    repeat (600) @(negedge clk);
    check(cap_n > 0 && !authorized[3] && l2_rejected[3] == r0 + 1 && l2_reason[3] == I7_RESET_REPLAY_REASON,
          $sformatf("SEC3_RESET_REPLAY authorized3=%b rejected=+%0d reason=%0d expect=%0d", authorized[3], l2_rejected[3] - r0, l2_reason[3], I7_RESET_REPLAY_REASON));
    // SEC-2 forged RESPONSE from the raw port (well-formed P7 header, junk freshness / MAC)
    r0 = l2_rejected[4]; v0 = verifier_rejected; g0 = grants;
    raw_packet(4, MSG_ATTEST_RESPONSE, int'(p7_length(MSG_ATTEST_RESPONSE)) + 5); repeat (600) @(negedge clk);
    check(l2_rejected[4] == r0 + 1 && l2_reason[4] == I7_SPOOF_RESPONSE_REASON && verifier_rejected == v0 && grants == g0,
          $sformatf("SEC2_SPOOF_RESPONSE rejected=+%0d reason=%0d expect=%0d verifier_rejected=+%0d", l2_rejected[4] - r0, l2_reason[4], I7_SPOOF_RESPONSE_REASON, verifier_rejected - v0));
    // truncated CHALLENGE from the raw port to tile 3
    r0 = l2_rejected[3]; e0 = ep_tx; q0 = q_rejected;
    raw_packet(3, MSG_ATTEST_CHALLENGE, 3); repeat (600) @(negedge clk);
    check(q_rejected == q0 + 1 && q_reason == I7_TRUNC_QUARANTINE_REASON && l2_rejected[3] == r0 && ep_tx == e0,
          $sformatf("SEC_TRUNC_CHALLENGE quarantine_rejected=+%0d reason=%0d expect=%0d l2_rejected3=+%0d endpoint_tx=+%0d", q_rejected - q0, q_reason, I7_TRUNC_QUARANTINE_REASON, l2_rejected[3] - r0, ep_tx - e0));
    // status-clear misuse: faults present; application traffic everywhere and a fresh GRANT do not clear them
    begin
      automatic bit sticky0, still; automatic int c0;
      load_chain(0); approved_measurement[0] = ~approved_measurement[0]; pulse_start(); wait_idle(); repeat (50) @(negedge clk);
      sticky0 = fault_sticky; c0 = fault_count;
      for (int g = 0; g < 6; g++) begin app_hdr(g, tile_to_coord(TILE_MEMORY), MSG_MEM_WR_REQ, 11'h780, 50, ok); end
      attest(0, ok);
      still = fault_sticky && fault_count >= c0;
      @(negedge clk); trusted_clear = 1; @(negedge clk); trusted_clear = 0; repeat (2) @(negedge clk);
      check(sticky0 && still && ok && !fault_sticky && fault_count == 0,
            $sformatf("SEC_STATUS_CLEAR_MISUSE sticky_before=%0b kept=%0b granted=%0b cleared=%0b", sticky0, still, ok, !fault_sticky));
    end
    // concurrent SPOOF flood during a genuine attestation
    @(negedge clk); revoke = 1; @(negedge clk); revoke = 0; wait_idle();
    q0 = q_forwarded; flood = 1; repeat (100) @(negedge clk);
    attest(2, ok); repeat (200) @(negedge clk); flood = 0; repeat (200) @(negedge clk);
    check(ok && q_forwarded > q0 && endpoint_response == expected_response, $sformatf("SEC_CONCURRENT_SPOOF granted=%0b forwarded=+%0d", ok, q_forwarded - q0));
    check(bad_commit == 0 && n_commit > 0, $sformatf("SEC_NO_UNAUTH_COMMIT commits=%0d bad=%0d", n_commit, bad_commit));
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 30 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #80ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
