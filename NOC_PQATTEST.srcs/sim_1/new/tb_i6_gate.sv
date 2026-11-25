`timescale 1ns/1ps
// I-6 integrated gate bench (docs/decisions/I6_CONTRACT.md sec. 4) on rtl/dual_lane/pq_noc_subsystem_p7.sv (S3 / I-6
// list, PQ_MAC_ON, chain rows of vectors/full_chain.svh), TB_INJECT = 1 (bench-only hooks: TBI.gv/gsrc/gmsg/gctl present
// an authenticated HEAD at a gate's inputs, TBI.drop4 hides tile 4's RX from the verifier), VERIFIER_TIMEOUT = 3,000.
// Fault-status records are logged whenever fault_count changes (source, operation, reason, epoch); a *_RECORD check finds
// the stated record among those logged since its case began, with epoch == attest_epoch.
// Cases, in order (one run, tile 3 is the attested tile, memory window 0x2200_0100):
//  RESET   I6G_RESET_BLOCKED (after reset tile 3's write header is never accepted, no commit, nothing authorized),
//          I6G_RESET_RECORD (3, MEM_WR_REQ, 1)
//  GRANT   I6G_GRANT_AUTHORIZED (row 0 attestation grants), I6G_GRANT_WRITE_COMMITS (write to 0x2200_0100 commits its
//          data), I6G_MEM_READ_AUTHORIZED (read returns it)
//  WINDOW  I6G_WINDOW_OLD_REFUSED (write to 0x8200_0100: no commit, error reply bit 10), I6G_WINDOW_RECORD (3, WR, 13)
//  SPOOF   I6G_MEM_UNAUTH_NO_COMMIT (raw own-source write from tile 5: no commit), I6G_MEM_UNAUTH_RECORD (5, WR, 6)
//  REVOKE  I6G_REVOKE_BLOCKS (revoke pulse: authorized[3] falls within 1,500 cycles; the next write header is refused)
//  ISSUER  I6G_ISSUER_REJECTED (authenticated GRANT, status 1, source tile 0, at gate 3: not authorized),
//          I6G_ISSUER_RECORD (0, GRANT, 2)
//  STATUS  I6G_GRANT_STATUS_REJECTED (GRANT from the RoT with status 2: not authorized), I6G_GRANT_STATUS_RECORD (4, GRANT, 3)
//  K3      (authorized first) re-attestation with config_len = 15: I6G_K3_FAIL_BLOCKS_LOCAL (failed, no grant,
//          authorized[3] falls <= 2 cycles after the failed pulse), I6G_K3_RECORD (3, CHALLENGE, 7),
//          I6G_FAIL_RECORD (3, RESPONSE, 9)
//  MEAS    wrong approved measurement: I6G_WRONG_MEAS_NO_GRANT, I6G_WRONG_MEAS_RECORD (3, RESPONSE, 11)
//  TIMEOUT (authorized first) re-attestation with drop4: I6G_TIMEOUT_BLOCKS_LOCAL (failed >= 3,000 cycles after start,
//          authorized[3] falls <= 2 cycles after it), I6G_TIMEOUT_RECORD (3, CHALLENGE, 8)
//  CLEAR   I6G_TRUSTED_CLEAR (sticky / count / gate faults set before, all 0 after one trusted_clear pulse)
//  RETRY   I6G_RETRY_AFTER_FAIL_GRANT (a new attestation grants again; no fault recorded by it)
//  RESET2  I6G_RESET_DURING_CHALLENGE (reset while the verifier waits for the response: nothing authorized, no grant
//          for 3,000 cycles)
//  GLOBAL  I6G_NO_UNAUTH_COMMIT (every commit was decided in a cycle with authorized[3] = 1; at least one commit)
// CHECKS = 25, frozen in the contract before the first run. Every wait is bounded and feeds a check (never a pass);
// TB_TIMEOUT only for the global limit.
module tb_i6_gate;
  import noc_pkg::*;
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
  logic [31:0] memory_commits, memory_last_data, endpoint_rejected, verifier_rejected;
  logic [5:0][31:0] gate_faults;
  logic fault_sticky; logic [31:0] fault_count; logic [2:0] fault_source; logic [3:0] fault_operation, fault_reason;
  logic [79:0] fault_epoch;
  logic [511:0] keys_p7;
  assign keys_p7 = {directed_keys[(3*6+4)*256 +: 256], directed_keys[(4*6+3)*256 +: 256]};
  pq_noc_subsystem_p7 #(.TB_INJECT(1'b1), .VERIFIER_TIMEOUT(3000)) dut(.clk, .rst, .start_attestation, .revoke, .trusted_clear,
    .boot_epoch, .attest_epoch, .nonce, .root_secret,
    .approved_measurement, .directed_keys(keys_p7), .context_in, .context_len, .config_data, .imem, .config_len, .imem_len,
    .app_valid, .app_payload_valid, .app_ready, .app_payload_ready, .app_destination, .app_message, .app_control, .app_payload,
    .spoof_raw_valid, .spoof_raw_flit, .spoof_raw_ready, .authorized, .rot_busy, .grant_done, .attestation_failed,
    .endpoint_response, .memory_commits, .memory_last_data, .gate_faults, .app_tx_error, .endpoint_rejected, .verifier_rejected,
    .fault_sticky, .fault_count, .fault_source, .fault_operation, .fault_reason, .fault_epoch);
  `include "full_chain.svh"
  localparam logic [31:0] ADDR = 32'h2200_0100, OLD_ADDR = 32'h8200_0100;
  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask

  // ---- monitors
  typedef struct { int src; int op; int reason; logic [79:0] epoch; } rec_t;
  rec_t recs [$];
  longint cyc = 0, t_fail = -1, t_fall = -1;
  int grants = 0, fails = 0, rd_n = 0, wr_resp_n = 0, bad_commit = 0, n_commit = 0, hdr3_acc = 0;
  bit watch_fall = 0, rd_open = 0;
  logic [31:0] rd_data = 0, commits_q = 0, fc_q = 0;
  logic [10:0] wr_resp_ctl = 0;
  logic auth3_q = 0;
  always @(posedge clk) begin
    cyc++;
    if (!rst) begin
      if (grant_done) grants++;
      if (attestation_failed) begin fails++; if (t_fail < 0) t_fail = cyc; end
      if (watch_fall && !authorized[3] && t_fall < 0) t_fall = cyc;
      if (app_valid[3] && app_ready[3]) hdr3_acc++;
      if (dut.rhv[3] && dut.rxmsg[3] == MSG_MEM_RD_RESP) rd_open = 1;
      else if (rd_open && dut.rpv[3]) begin rd_data = dut.rxdata[3]; rd_n++; rd_open = 0; end
      if (dut.rhv[3] && dut.rxmsg[3] == MSG_MEM_WR_RESP) begin wr_resp_n++; wr_resp_ctl = dut.rxctl[3]; end
      if (memory_commits != commits_q) begin n_commit++; if (!auth3_q) bad_commit++; end   // decided one cycle back (F4 boundary)
      if (fault_count != fc_q && fault_count != 0) recs.push_back('{int'(fault_source), int'(fault_operation), int'(fault_reason), fault_epoch});
      commits_q = memory_commits; auth3_q = authorized[3]; fc_q = fault_count;
    end else begin commits_q = 0; auth3_q = 0; fc_q = 0; end
  end
  function automatic bit seen(input int from, input int src, input int op, input int reason);
    for (int i = from; i < recs.size(); i++)
      if (recs[i].src == src && recs[i].op == op && recs[i].reason == reason && recs[i].epoch == attest_epoch) return 1;
    return 0;
  endfunction
  function automatic string rec_str(input int from);
    string s = "";
    for (int i = from; i < recs.size() && i < from + 6; i++) s = {s, $sformatf(" (%0d,%0d,%0d)", recs[i].src, recs[i].op, recs[i].reason)};
    return s;
  endfunction

  // ---- stimulus helpers (bounded)
  task automatic do_reset();
    @(negedge clk); rst = 1; app_valid = 0; app_payload_valid = 0; revoke = 0; start_attestation = 0; spoof_raw_valid = 0;
    trusted_clear = 0; repeat (6) @(negedge clk); rst = 0; repeat (5) @(negedge clk);
  endtask
  task automatic pulse_start(); @(negedge clk); start_attestation = 1; @(negedge clk); start_attestation = 0; endtask
  task automatic wait_idle(); automatic int n = 0; while ((rot_busy || dut.verifier.vs != 0) && n < 60000) begin @(negedge clk); n++; end endtask
  // full attestation of a row; ok = granted and tile 3 authorized
  task automatic attest(input int row, output bit ok);
    automatic int g0 = grants, n = 0;
    load_chain(row); pulse_start();
    while (!(grants == g0 + 1 && authorized[3]) && n < 60000) begin @(negedge clk); n++; end
    ok = grants == g0 + 1 && authorized[3];
    wait_idle(); repeat (20) @(negedge clk);
  endtask
  task automatic app_hdr(input coord_t d, input msg_type_e m, input logic [10:0] c, input int limit, output bit ok);
    automatic int n = 0;
    @(negedge clk); app_destination[3] = d; app_message[3] = m; app_control[3] = c; app_valid[3] = 1;
    do begin @(posedge clk); n++; end while (!app_ready[3] && n < limit);
    ok = app_ready[3]; @(negedge clk); app_valid[3] = 0;
  endtask
  task automatic app_words(input logic [31:0] w0, input logic [31:0] w1, input int nw, output bit ok);
    ok = 1;
    for (int i = 0; i < nw && ok; i++) begin
      automatic int n = 0;
      app_payload[3] = i == 0 ? w0 : w1; app_payload_valid[3] = 1;
      do begin @(posedge clk); n++; end while (!app_payload_ready[3] && n < 2000);
      ok = app_payload_ready[3]; @(negedge clk);
    end
    app_payload_valid[3] = 0;
  endtask
  task automatic mem_write(input logic [31:0] a, input logic [31:0] d, output bit ok);
    automatic bit ok2;
    app_hdr(tile_to_coord(TILE_MEMORY), MSG_MEM_WR_REQ, 11'h780, 2000, ok);
    if (ok) app_words(a, d, 2, ok2);
    ok = ok && ok2; repeat (400) @(negedge clk);
  endtask
  task automatic raw(input flit_t f);
    automatic int n = 0;
    @(negedge clk); spoof_raw_flit = f; spoof_raw_valid = 1;
    do begin @(posedge clk); n++; end while (!spoof_raw_ready && n < 2000);
    @(negedge clk); spoof_raw_valid = 0;
  endtask
  task automatic inject_gate3(input coord_t s, input msg_type_e m, input logic [10:0] c);
    @(negedge clk); dut.TBI.gsrc[3] = s; dut.TBI.gmsg[3] = m; dut.TBI.gctl[3] = c; dut.TBI.gv[3] = 1;
    @(negedge clk); dut.TBI.gv[3] = 0; repeat (20) @(negedge clk);
  endtask

  initial begin
    bit ok, ok_pre; int mark, c0, g0; longint t_start;
    $display("CONFIG: TOP=tb_i6_gate CHECKS=25 VERIFIER_TIMEOUT=3000 ADDR=%h", ADDR);
    app_valid = 0; app_payload_valid = 0; app_destination = '0; app_message = '0; app_control = 0; app_payload = 0;
    spoof_raw_flit = '0;
    load_chain(0); boot_epoch = BOOT; directed_keys = KEYS;
    do_reset();
    // RESET: nothing authorized; tile 3's write header held for 300 cycles is never accepted
    mark = recs.size(); c0 = memory_commits; hdr3_acc = 0;
    app_hdr(tile_to_coord(TILE_MEMORY), MSG_MEM_WR_REQ, 11'h780, 300, ok);
    repeat (50) @(negedge clk);
    check(!ok && hdr3_acc == 0 && memory_commits == c0 && authorized == 0,
          $sformatf("I6G_RESET_BLOCKED accepted=%0d commits=+%0d authorized=%b", hdr3_acc, memory_commits - c0, authorized));
    check(seen(mark, 3, MSG_MEM_WR_REQ, 1), {"I6G_RESET_RECORD", rec_str(mark)});
    // GRANT, authorized write and read in the 0x2 window
    attest(0, ok);
    check(ok, $sformatf("I6G_GRANT_AUTHORIZED authorized=%b", authorized));
    c0 = memory_commits; mem_write(ADDR, 32'h1600_0001, ok);
    check(ok && memory_commits == c0 + 1 && memory_last_data == 32'h1600_0001,
          $sformatf("I6G_GRANT_WRITE_COMMITS commits=+%0d data=%h", memory_commits - c0, memory_last_data));
    g0 = rd_n;
    app_hdr(tile_to_coord(TILE_MEMORY), MSG_MEM_RD_REQ, 11'h000, 2000, ok);
    if (ok) app_words(ADDR, 0, 1, ok);
    repeat (400) @(negedge clk);
    check(ok && rd_n == g0 + 1 && rd_data == 32'h1600_0001, $sformatf("I6G_MEM_READ_AUTHORIZED reads=+%0d data=%h", rd_n - g0, rd_data));
    // WINDOW: the old 0x8 address is refused with the error reply
    mark = recs.size(); c0 = memory_commits; g0 = wr_resp_n;
    mem_write(OLD_ADDR, 32'h1600_0002, ok);
    check(ok && memory_commits == c0 && wr_resp_n == g0 + 1 && wr_resp_ctl[10],
          $sformatf("I6G_WINDOW_OLD_REFUSED commits=+%0d replies=+%0d ctl=%h", memory_commits - c0, wr_resp_n - g0, wr_resp_ctl));
    check(seen(mark, 3, MSG_MEM_WR_REQ, 13), {"I6G_WINDOW_RECORD", rec_str(mark)});
    // SPOOF: raw own-source write from tile 5 (not authorized)
    begin
      automatic head_flit_t h; automatic flit_t f; automatic coord_t s, d;   // set by statements (XSim chained-cast X)
      mark = recs.size(); c0 = memory_commits;
      h = '0; s = tile_to_coord(TILE_SPOOF); d = tile_to_coord(TILE_MEMORY);
      h.src_x = s.x; h.src_y = s.y; h.dest_x = d.x; h.dest_y = d.y; h.msg_type = MSG_MEM_WR_REQ; h.length = 5'd3;
      f.flit_data = h; f.flit_type = FLIT_HEAD; f.vc_id = 2'(message_to_vc(MSG_MEM_WR_REQ)); raw(f);
      f.flit_data = ADDR; f.flit_type = FLIT_BODY; raw(f);
      f.flit_data = 32'h5B00_F000; f.flit_type = FLIT_TAIL; raw(f);
      repeat (600) @(negedge clk);
      check(memory_commits == c0 && memory_last_data != 32'h5B00_F000, $sformatf("I6G_MEM_UNAUTH_NO_COMMIT commits=+%0d", memory_commits - c0));
      check(seen(mark, 5, MSG_MEM_WR_REQ, 6), {"I6G_MEM_UNAUTH_RECORD", rec_str(mark)});
    end
    // REVOKE
    begin
      automatic int n = 0;
      @(negedge clk); revoke = 1; @(negedge clk); revoke = 0;
      while (authorized[3] && n < 1500) begin @(negedge clk); n++; end
      ok_pre = !authorized[3]; wait_idle(); hdr3_acc = 0; c0 = memory_commits;
      app_hdr(tile_to_coord(TILE_MEMORY), MSG_MEM_WR_REQ, 11'h780, 200, ok);
      check(ok_pre && !ok && hdr3_acc == 0 && memory_commits == c0, $sformatf("I6G_REVOKE_BLOCKS fell_after=%0d header_accepted=%0d", n, hdr3_acc));
    end
    // ISSUER: authenticated GRANT (status 1) from tile 0 presented at gate 3
    mark = recs.size(); inject_gate3(tile_to_coord(TILE_CPU0), MSG_ATTEST_GRANT, 11'h080);
    check(authorized[3] == 0, $sformatf("I6G_ISSUER_REJECTED authorized3=%b", authorized[3]));
    check(seen(mark, 0, MSG_ATTEST_GRANT, 2), {"I6G_ISSUER_RECORD", rec_str(mark)});
    // STATUS: GRANT from the RoT with status 2
    mark = recs.size(); inject_gate3(tile_to_coord(TILE_ROT), MSG_ATTEST_GRANT, 11'h100);
    check(authorized[3] == 0, $sformatf("I6G_GRANT_STATUS_REJECTED authorized3=%b", authorized[3]));
    check(seen(mark, 4, MSG_ATTEST_GRANT, 3), {"I6G_GRANT_STATUS_RECORD", rec_str(mark)});
    // K3: authorized, then a re-attestation with config_len = 15 (not the provisioned 16)
    attest(0, ok_pre);
    mark = recs.size(); g0 = grants; t_fail = -1; t_fall = -1; watch_fall = 1;
    load_chain(1); config_len = 7'd15; pulse_start();
    begin automatic int n = 0; while (t_fail < 0 && n < 60000) begin @(negedge clk); n++; end end
    wait_idle(); repeat (50) @(negedge clk); watch_fall = 0; config_len = 7'd16;
    check(ok_pre && t_fail >= 0 && grants == g0 && t_fall >= t_fail && t_fall - t_fail <= 2 && !authorized[3],
          $sformatf("I6G_K3_FAIL_BLOCKS_LOCAL authorized_before=%0b failed_at=%0d fell_at=%0d grants=+%0d", ok_pre, t_fail, t_fall, grants - g0));
    check(seen(mark, 3, MSG_ATTEST_CHALLENGE, 7), {"I6G_K3_RECORD", rec_str(mark)});
    check(seen(mark, 3, MSG_ATTEST_RESPONSE, 9), {"I6G_FAIL_RECORD", rec_str(mark)});
    // MEAS: wrong approved measurement
    mark = recs.size(); g0 = grants; t_fail = -1;
    load_chain(0); approved_measurement[0] = ~approved_measurement[0]; pulse_start();
    begin automatic int n = 0; while (t_fail < 0 && n < 60000) begin @(negedge clk); n++; end end
    wait_idle(); repeat (50) @(negedge clk);
    check(t_fail >= 0 && grants == g0 && !authorized[3], $sformatf("I6G_WRONG_MEAS_NO_GRANT failed=%0b grants=+%0d", t_fail >= 0, grants - g0));
    check(seen(mark, 3, MSG_ATTEST_RESPONSE, 11), {"I6G_WRONG_MEAS_RECORD", rec_str(mark)});
    // TIMEOUT: authorized, then a re-attestation whose response never reaches the verifier
    attest(0, ok_pre);
    mark = recs.size(); g0 = grants; t_fail = -1; t_fall = -1; watch_fall = 1;
    load_chain(1); @(negedge clk); dut.TBI.drop4 = 1; t_start = cyc; pulse_start();
    begin automatic int n = 0; while (t_fail < 0 && n < 20000) begin @(negedge clk); n++; end end
    wait_idle(); repeat (50) @(negedge clk); watch_fall = 0; dut.TBI.drop4 = 0;
    check(ok_pre && t_fail >= 0 && t_fail - t_start >= 3000 && grants == g0 && t_fall >= t_fail && t_fall - t_fail <= 2 && !authorized[3],
          $sformatf("I6G_TIMEOUT_BLOCKS_LOCAL authorized_before=%0b after_start=%0d failed_at=%0d fell_at=%0d", ok_pre, t_fail - t_start, t_fail, t_fall));
    check(seen(mark, 3, MSG_ATTEST_CHALLENGE, 8), {"I6G_TIMEOUT_RECORD", rec_str(mark)});
    // CLEAR: trusted clear of the fault status and the gate counters
    repeat (200) @(negedge clk);
    begin
      automatic bit set_before = fault_sticky && fault_count > 0 && gate_faults[3] > 0;
      @(negedge clk); trusted_clear = 1; @(negedge clk); trusted_clear = 0; repeat (2) @(negedge clk);
      check(set_before && !fault_sticky && fault_count == 0 && gate_faults == '0,
            $sformatf("I6G_TRUSTED_CLEAR before=%0b sticky=%0b count=%0d gate3=%0d", set_before, fault_sticky, fault_count, gate_faults[3]));
    end
    // RETRY: a new trusted attestation grants again and records no fault
    attest(0, ok);
    check(ok && !fault_sticky && fault_count == 0, $sformatf("I6G_RETRY_AFTER_FAIL_GRANT granted=%0b sticky=%0b count=%0d", ok, fault_sticky, fault_count));
    // RESET2: reset while the verifier waits for the response
    begin
      automatic int n = 0;
      load_chain(1); pulse_start();
      while (dut.verifier.vs != 5 && n < 60000) begin @(negedge clk); n++; end
      ok_pre = dut.verifier.vs == 5;
      do_reset(); g0 = grants; repeat (3000) @(negedge clk);
      check(ok_pre && authorized == 0 && grants == g0, $sformatf("I6G_RESET_DURING_CHALLENGE reached_wait=%0b authorized=%b grants=+%0d", ok_pre, authorized, grants - g0));
    end
    check(bad_commit == 0 && n_commit > 0, $sformatf("I6G_NO_UNAUTH_COMMIT commits=%0d bad=%0d", n_commit, bad_commit));
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 25 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #60ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
