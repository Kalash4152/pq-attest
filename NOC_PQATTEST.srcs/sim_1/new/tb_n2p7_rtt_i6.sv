`timescale 1ns/1ps
// NOC-2 subset on P7, subsystem part (Kalash 2026-10-28, Q1 option (a); DECISION_REGISTER S2-N2P7): the real control round
// trip of rtl/dual_lane/pq_noc_subsystem_p7.sv (PQ_MAC_ON, chain rows 0 / 1, setup as tb_p7_c4) with and without load.
// Round trip of one attestation: start_attestation pulse -> CHALLENGE HEAD into the mesh at port 4 -> RESPONSE HEAD into
// the mesh at port 3 -> GRANT HEAD into the mesh at port 4 -> GRANT HEAD delivered at tile 3 (the authorization event;
// authorized[3] = 1 after it). All four segment times are printed (N2P7_RTT); no latency bound is asserted.
// Loads: NONE; LOADED = tile 3's application writes to the memory back to back (authorized data, tile 3 -> tile 2) and the
// raw injector at tile 5 floods own-source MEM_RD_REQs toward tile 3 (through the quarantine), for the whole window.
// In the P7 subsystem only attested tiles may send data, so these are the only data sources DUT (B) has.
// Per load: reset, setup attestation (row 0), 300 warm-up cycles, then K = 4 timed re-attestations (rows 1, 0, 1, 0).
// Checks: N2P7_RTT_<LOAD>_<k> (grant delivered at tile 3, authorized[3] = 1, no attestation failure)        2 x 4 = 8
//         N2P7_LOAD_NONE (no memory commit, nothing forwarded by the quarantine over the NONE window)              1
//         N2P7_LOAD_COMMITS / N2P7_LOAD_RAW (memory commits and quarantine forwards both rose over LOADED)         2
// CHECKS = 11, frozen from this source before the first run. Bounded waits; a setup failure prints TB_TIMEOUT (INVALID).
module tb_n2p7_rtt;
  import noc_pkg::*;
  import noc_p7_pkg::*;
  localparam int K = 4;
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
  logic [5:0] app_valid, app_payload_valid, app_ready, app_payload_ready, app_tx_error;
  coord_t [5:0] app_destination;
  msg_type_e [5:0] app_message;
  logic [5:0][10:0] app_control;
  logic [5:0][31:0] app_payload;
  logic spoof_raw_valid = 0, spoof_raw_ready;
  flit_t spoof_raw_flit;
  logic [5:0] authorized;
  logic rot_busy, grant_done, attestation_failed;
  logic [775:0] endpoint_response, expected_response;   // expected_response: written by full_chain.svh
  logic [31:0] memory_commits, memory_last_data, endpoint_rejected, verifier_rejected, q_forwarded;
  logic [511:0] keys_p7;
  assign keys_p7 = {directed_keys[(3*6+4)*256 +: 256], directed_keys[(4*6+3)*256 +: 256]};
  pq_noc_subsystem_p7 dut(.clk, .rst, .start_attestation, .revoke, .boot_epoch, .attest_epoch, .nonce, .root_secret,
    .approved_measurement, .directed_keys(keys_p7), .context_in, .context_len, .config_data, .imem, .config_len, .imem_len,
    .trusted_clear(1'b0), .app_valid, .app_payload_valid, .app_ready, .app_payload_ready, .app_destination, .app_message, .app_control, .app_payload,
    .spoof_raw_valid, .spoof_raw_flit, .spoof_raw_ready, .authorized, .rot_busy, .grant_done, .attestation_failed,
    .endpoint_response, .memory_commits, .memory_last_data, .app_tx_error, .endpoint_rejected, .verifier_rejected,
    .q_forwarded);
  `include "full_chain.svh"
  localparam logic [31:0] ADDR = 32'h2200_0100;
  int checks = 0, errors = 0, fails = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  task automatic timeout(input string w); $display("TB_TIMEOUT %s", w); $finish; endtask
  always @(posedge clk) if (!rst && attestation_failed) fails++;

  // segment monitor (read-only): first HEAD of each kind after the start pulse
  int cyc = 0, t_ch = -1, t_rs = -1, t_gr = -1, t_del = -1;
  bit timing = 0;
  head_flit_t h4, h3, hd3;
  assign h4  = head_flit_t'(dut.mesh_in[4].flit_data);
  assign h3  = head_flit_t'(dut.mesh_in[3].flit_data);
  always @(posedge clk) begin
    cyc++;
    if (!rst && timing) begin
      if (t_ch < 0 && dut.mesh_iv[4] && dut.mesh_ir[4] && dut.mesh_in[4].flit_type == FLIT_HEAD && h4.msg_type == MSG_ATTEST_CHALLENGE) t_ch = cyc;
      if (t_rs < 0 && t_ch >= 0 && dut.mesh_iv[3] && dut.mesh_ir[3] && dut.mesh_in[3].flit_type == FLIT_HEAD && h3.msg_type == MSG_ATTEST_RESPONSE) t_rs = cyc;
      if (t_gr < 0 && t_rs >= 0 && dut.mesh_iv[4] && dut.mesh_ir[4] && dut.mesh_in[4].flit_type == FLIT_HEAD && h4.msg_type == MSG_ATTEST_GRANT) t_gr = cyc;
      if (t_del < 0 && t_gr >= 0 && dut.rhv[3] && dut.rxmsg[3] == MSG_ATTEST_GRANT) t_del = cyc;
    end
  end

  bit flood = 0, wflood = 0;
  initial forever begin
    @(negedge clk);
    if (flood) begin
      automatic head_flit_t h; automatic flit_t f; automatic coord_t s, d;   // set by statements (XSim chained-cast X)
      h = '0; s = tile_to_coord(TILE_SPOOF); d = tile_to_coord(TILE_CRYPTO);
      h.src_x = s.x; h.src_y = s.y; h.dest_x = d.x; h.dest_y = d.y; h.msg_type = MSG_MEM_RD_REQ; h.length = 5'd2;
      f.flit_data = h; f.flit_type = FLIT_HEAD; f.vc_id = 2'(message_to_vc(MSG_MEM_RD_REQ)); spoof_raw_flit = f; spoof_raw_valid = 1;
      do @(posedge clk); while (!spoof_raw_ready); @(negedge clk);
      f.flit_data = ADDR; f.flit_type = FLIT_TAIL; spoof_raw_flit = f;
      do @(posedge clk); while (!spoof_raw_ready); @(negedge clk); spoof_raw_valid = 0;
    end
  end
  initial forever begin
    @(negedge clk);
    if (wflood && authorized[3]) begin
      automatic int n = 0;
      app_destination[3] = tile_to_coord(TILE_MEMORY); app_message[3] = MSG_MEM_WR_REQ; app_control[3] = 11'h780; app_valid[3] = 1;
      do begin @(posedge clk); n++; end while (!app_ready[3] && n < 2000); @(negedge clk); app_valid[3] = 0;
      if (n < 2000) for (int i = 0; i < 2; i++) begin
        app_payload[3] = i == 0 ? ADDR : 32'hFEED_0000 + i; app_payload_valid[3] = 1; n = 0;
        do begin @(posedge clk); n++; end while (!app_payload_ready[3] && n < 2000); @(negedge clk);
      end
      app_payload_valid[3] = 0;
    end
  end

  task automatic do_reset();
    @(negedge clk); rst = 1; app_valid = 0; app_payload_valid = 0; revoke = 0; start_attestation = 0; spoof_raw_valid = 0;
    flood = 0; wflood = 0; repeat (6) @(negedge clk); rst = 0; repeat (5) @(negedge clk);
  endtask
  task automatic pulse_start(); @(negedge clk); start_attestation = 1; @(negedge clk); start_attestation = 0; endtask
  task automatic attest_setup();
    automatic int n = 0;
    load_chain(0); pulse_start();
    while (!authorized[3] && n < 60000) begin @(negedge clk); n++; end
    if (!authorized[3]) timeout("setup attestation");
    repeat (20) @(negedge clk);
  endtask
  // one timed re-attestation; returns the round trip (start pulse -> GRANT delivered at tile 3)
  task automatic timed(input string load, input int k, input int row);
    automatic int n = 0, t0, f0;
    f0 = fails;
    load_chain(row);
    t_ch = -1; t_rs = -1; t_gr = -1; t_del = -1; timing = 1;
    t0 = cyc + 1; pulse_start();
    while (t_del < 0 && n < 60000) begin @(negedge clk); n++; end
    if (t_del < 0) timeout($sformatf("round trip %s %0d", load, k));
    repeat (10) @(negedge clk);
    timing = 0;
    check(authorized[3] && fails == f0, $sformatf("N2P7_RTT_%s_%0d", load, k));
    $display("N2P7_RTT load=%s k=%0d row=%0d rtt=%0d to_challenge=%0d challenge_to_response=%0d response_to_grant=%0d grant_to_delivered=%0d",
             load, k, row, t_del - t0, t_ch - t0, t_rs - t_ch, t_gr - t_rs, t_del - t_gr);
    repeat (200) @(negedge clk);
  endtask
  task automatic run_load(input string load, input bit loaded, output int dcommit, output int dfwd);
    automatic int c0, q0;
    do_reset(); attest_setup();
    if (loaded) begin flood = 1; wflood = 1; end
    repeat (300) @(negedge clk);
    c0 = memory_commits; q0 = q_forwarded;
    for (int k = 0; k < K; k++) timed(load, k, (k % 2 == 0) ? 1 : 0);
    dcommit = memory_commits - c0; dfwd = q_forwarded - q0;
    flood = 0; wflood = 0;
    $display("N2P7_LOAD load=%s memory_commits=+%0d quarantine_forwarded=+%0d", load, dcommit, dfwd);
  endtask

  initial begin
    int c_none, q_none, c_load, q_load;
    $display("CONFIG: TOP=tb_n2p7_rtt CHECKS=11 K=%0d", K);
    app_valid = 0; app_payload_valid = 0; app_destination = '0; app_message = '0; app_control = 0; app_payload = 0; spoof_raw_flit = '0;
    load_chain(0); boot_epoch = BOOT; directed_keys = KEYS;
    run_load("NONE", 1'b0, c_none, q_none);
    check(c_none == 0 && q_none == 0, $sformatf("N2P7_LOAD_NONE commits=%0d forwarded=%0d", c_none, q_none));
    run_load("LOADED", 1'b1, c_load, q_load);
    check(c_load > 0, $sformatf("N2P7_LOAD_COMMITS commits=+%0d", c_load));
    check(q_load > 0, $sformatf("N2P7_LOAD_RAW forwarded=+%0d", q_load));
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #60ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
