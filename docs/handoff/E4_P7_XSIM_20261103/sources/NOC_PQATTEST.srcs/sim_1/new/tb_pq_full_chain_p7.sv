`timescale 1ns/1ps
// I-7 PQ-5 offline full chain on P7 (docs/decisions/I7_SEC_MATRIX.md sec. 4), NON-DEMO bench mode: the real I-6 P7 subsystem
// (rtl/dual_lane/pq_noc_subsystem_p7.sv, S3 / I-6 list, PQ_MAC_ON); expected responses from the teammate-reference adapter
// (vectors/full_chain.svh = V7 oracle); nonce source = deterministic demo issuer (the chain rows); no TRNG claim.
// Chain per transaction: challenge -> L2-authenticated transport -> endpoint (KDF, measurement, tag) -> response -> RoT
// verifier -> GRANT -> authorized write and read in the 0x2 window -> revoke -> blocked.
// The raw port at tile 5 floods tile 3 for the whole run; tile 3's application payload is offered with gaps (backpressure).
// TB_INJECT = 1 only for TBI.drop4 (a lost response, timeout row); VERIFIER_TIMEOUT = 20,000.
// Checks: FC_TXN<r>_RESPONSE (endpoint_response == expected_response), FC_TXN<r>_GRANT, FC_TXN<r>_DATA (write committed and
//   read back), FC_TXN<r>_REVOKE_BLOCKS (revoke: not authorized, next write header refused), r = 0, 1, 2            12
//   FC_SUBST_BLOCKED (config_data substituted at re-attestation: no grant, not authorized, write refused)               1
//   FC_RESET_<S>_CLEAN (reset while the verifier is in S = KWAIT, FILL, WAIT, TWAIT, GRANT: nothing authorized after
//   the reset, the next attestation grants with the expected response)                                               5
//   FC_TIMEOUT_THEN_RETRY (lost response: failed, not authorized; the retry grants)                                    1
//   FC_SPOOF_COEXIST (the raw flood toward tile 3 was forwarded throughout)                                             1
//   FC_NO_UNAUTH_COMMIT (every commit decided with authorized[3] = 1)                                                  1
// CHECKS = 21, frozen before the first run. Bounded waits feed checks; TB_TIMEOUT only for the global limit.
module tb_pq_full_chain_p7;
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
  logic [31:0] memory_commits, memory_last_data, endpoint_rejected, verifier_rejected, q_forwarded;
  logic [511:0] keys_p7;
  assign keys_p7 = {directed_keys[(3*6+4)*256 +: 256], directed_keys[(4*6+3)*256 +: 256]};
  pq_noc_subsystem_p7 #(.TB_INJECT(1'b1), .VERIFIER_TIMEOUT(20000)) dut(.clk, .rst, .start_attestation, .revoke, .trusted_clear,
    .boot_epoch, .attest_epoch, .nonce, .root_secret,
    .approved_measurement, .directed_keys(keys_p7), .context_in, .context_len, .config_data, .imem, .config_len, .imem_len,
    .app_valid, .app_payload_valid, .app_ready, .app_payload_ready, .app_destination, .app_message, .app_control, .app_payload,
    .spoof_raw_valid, .spoof_raw_flit, .spoof_raw_ready, .authorized, .rot_busy, .grant_done, .attestation_failed,
    .endpoint_response, .memory_commits, .memory_last_data, .q_forwarded, .app_tx_error, .endpoint_rejected, .verifier_rejected);
  `include "full_chain.svh"
  localparam logic [31:0] ADDR = 32'h2200_0100;
  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  int grants = 0, fails = 0, n_commit = 0, bad_commit = 0, rd_n = 0;
  bit rd_open = 0;
  logic [31:0] rd_data = 0, commits_q = 0;
  logic auth3_q = 0;
  always @(posedge clk) begin
    if (!rst) begin
      if (grant_done) grants++;
      if (attestation_failed) fails++;
      if (dut.rhv[3] && dut.rxmsg[3] == MSG_MEM_RD_RESP) rd_open = 1;
      else if (rd_open && dut.rpv[3]) begin rd_data = dut.rxdata[3]; rd_n++; rd_open = 0; end
      if (memory_commits != commits_q) begin n_commit++; if (!auth3_q) bad_commit++; end
      commits_q = memory_commits; auth3_q = authorized[3];
    end else begin commits_q = 0; auth3_q = 0; end
  end
  bit flood = 0;
  initial forever begin
    @(negedge clk);
    if (flood && !rst) begin
      automatic head_flit_t h; automatic flit_t f; automatic coord_t s, d;
      h = '0; s = tile_to_coord(TILE_SPOOF); d = tile_to_coord(TILE_CRYPTO);
      h.src_x = s.x; h.src_y = s.y; h.dest_x = d.x; h.dest_y = d.y; h.msg_type = MSG_MEM_RD_REQ; h.length = 5'd2;
      f.flit_data = h; f.flit_type = FLIT_HEAD; f.vc_id = 2'(message_to_vc(MSG_MEM_RD_REQ)); spoof_raw_flit = f; spoof_raw_valid = 1;
      do @(posedge clk); while (!spoof_raw_ready && !rst); @(negedge clk);
      f.flit_data = ADDR; f.flit_type = FLIT_TAIL; spoof_raw_flit = f;
      do @(posedge clk); while (!spoof_raw_ready && !rst); @(negedge clk); spoof_raw_valid = 0;
    end
  end
  task automatic do_reset();
    @(negedge clk); rst = 1; app_valid = 0; app_payload_valid = 0; revoke = 0; start_attestation = 0;
    repeat (6) @(negedge clk); rst = 0; repeat (5) @(negedge clk);
  endtask
  task automatic pulse_start(); @(negedge clk); start_attestation = 1; @(negedge clk); start_attestation = 0; endtask
  task automatic wait_idle(); automatic int n = 0; while ((rot_busy || dut.verifier.vs != 0) && n < 60000) begin @(negedge clk); n++; end endtask
  task automatic attest(input int row, output bit ok, output bit resp_ok);
    automatic int g0 = grants, n = 0;
    load_chain(row); pulse_start();
    while (!(grants == g0 + 1 && authorized[3]) && n < 60000) begin @(negedge clk); n++; end
    ok = grants == g0 + 1 && authorized[3]; resp_ok = endpoint_response == expected_response;
    wait_idle(); repeat (20) @(negedge clk);
  endtask
  task automatic app_hdr(input msg_type_e m, input logic [10:0] c, input int limit, output bit ok);
    automatic int n = 0;
    @(negedge clk); app_destination[3] = tile_to_coord(TILE_MEMORY); app_message[3] = m; app_control[3] = c; app_valid[3] = 1;
    do begin @(posedge clk); n++; end while (!app_ready[3] && n < limit);
    ok = app_ready[3]; @(negedge clk); app_valid[3] = 0;
  endtask
  // payload words with a 3-cycle gap before each word (source-side backpressure)
  task automatic app_words(input logic [31:0] w0, input logic [31:0] w1, input int nw, output bit ok);
    ok = 1;
    for (int i = 0; i < nw && ok; i++) begin
      automatic int n = 0;
      repeat (3) @(negedge clk);
      app_payload[3] = i == 0 ? w0 : w1; app_payload_valid[3] = 1;
      do begin @(posedge clk); n++; end while (!app_payload_ready[3] && n < 2000);
      ok = app_payload_ready[3]; @(negedge clk); app_payload_valid[3] = 0;
    end
  endtask
  task automatic write_read(input logic [31:0] d, output bit ok);
    automatic bit h, w, h2, w2; automatic int c0 = memory_commits, r0 = rd_n;
    app_hdr(MSG_MEM_WR_REQ, 11'h780, 2000, h); w = 0; if (h) app_words(ADDR, d, 2, w);
    repeat (400) @(negedge clk);
    app_hdr(MSG_MEM_RD_REQ, 11'h000, 2000, h2); w2 = 0; if (h2) app_words(ADDR, 0, 1, w2);
    repeat (400) @(negedge clk);
    ok = h && w && h2 && w2 && memory_commits == c0 + 1 && memory_last_data == d && rd_n == r0 + 1 && rd_data == d;
  endtask
  task automatic revoke_blocks(output bit ok);
    automatic int n = 0; automatic bit h;
    @(negedge clk); revoke = 1; @(negedge clk); revoke = 0;
    while (authorized[3] && n < 1500) begin @(negedge clk); n++; end
    wait_idle();
    app_hdr(MSG_MEM_WR_REQ, 11'h780, 200, h);
    ok = !authorized[3] && !h;
  endtask
  function automatic string sname(input int s);
    case (s) 2: return "KWAIT"; 4: return "FILL"; 5: return "WAIT"; 8: return "TWAIT"; 9: return "GRANT"; default: return "BAD"; endcase
  endfunction

  initial begin
    bit ok, rok, dok, bok; int q0, g0;
    int st [5] = '{2, 4, 5, 8, 9};
    $display("CONFIG: TOP=tb_pq_full_chain_p7 CHECKS=21 MODE=NON_DEMO NONCE=deterministic_demo_issuer");
    app_valid = 0; app_payload_valid = 0; app_destination = '0; app_message = '0; app_control = 0; app_payload = 0; spoof_raw_flit = '0;
    load_chain(0); boot_epoch = BOOT; directed_keys = KEYS;
    do_reset();
    flood = 1; q0 = q_forwarded;
    for (int r = 0; r < 3; r++) begin
      attest(r, ok, rok);
      check(rok, $sformatf("FC_TXN%0d_RESPONSE match=%0b", r, rok));
      check(ok, $sformatf("FC_TXN%0d_GRANT granted=%0b", r, ok));
      write_read(32'hFC00_0000 + r, dok);
      check(dok, $sformatf("FC_TXN%0d_DATA ok=%0b data=%h read=%h", r, dok, memory_last_data, rd_data));
      revoke_blocks(bok);
      check(bok, $sformatf("FC_TXN%0d_REVOKE_BLOCKS ok=%0b", r, bok));
    end
    // substitution at re-attestation
    attest(0, ok, rok);
    begin
      automatic bit h; g0 = grants;
      load_chain(1); config_data[0] = ~config_data[0]; pulse_start(); wait_idle(); repeat (50) @(negedge clk);
      app_hdr(MSG_MEM_WR_REQ, 11'h780, 200, h);
      check(ok && grants == g0 && !authorized[3] && !h, $sformatf("FC_SUBST_BLOCKED grants=+%0d authorized3=%b header=%0b", grants - g0, authorized[3], h));
    end
    // reset at each verifier boundary
    foreach (st[k]) begin
      automatic int n = 0; automatic bit reached;
      attest(0, ok, rok);
      load_chain(1); pulse_start();
      while (dut.verifier.vs != st[k] && n < 60000) begin @(negedge clk); n++; end
      reached = dut.verifier.vs == st[k];
      do_reset();
      repeat (50) @(negedge clk);
      begin
        automatic bit clean = authorized == 0;
        attest(2, ok, rok);
        check(reached && clean && ok && rok, $sformatf("FC_RESET_%s_CLEAN reached=%0b clean=%0b regrant=%0b response=%0b", sname(st[k]), reached, clean, ok, rok));
      end
    end
    // lost response -> timeout -> retry
    begin
      automatic int f0; automatic bit failed_blocked;
      f0 = fails; g0 = grants;
      load_chain(1); @(negedge clk); dut.TBI.drop4 = 1; pulse_start(); wait_idle(); repeat (50) @(negedge clk); dut.TBI.drop4 = 0;
      failed_blocked = fails > f0 && grants == g0 && !authorized[3];
      repeat (300) @(negedge clk);
      attest(0, ok, rok);
      check(failed_blocked && ok && rok, $sformatf("FC_TIMEOUT_THEN_RETRY failed_blocked=%0b retry=%0b", failed_blocked, ok));
    end
    flood = 0; repeat (300) @(negedge clk);
    check(q_forwarded > q0, $sformatf("FC_SPOOF_COEXIST forwarded=+%0d", q_forwarded - q0));
    check(bad_commit == 0 && n_commit >= 3, $sformatf("FC_NO_UNAUTH_COMMIT commits=%0d bad=%0d", n_commit, bad_commit));
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 21 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #90ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
