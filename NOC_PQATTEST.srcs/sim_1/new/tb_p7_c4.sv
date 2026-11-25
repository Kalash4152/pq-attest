`timescale 1ns/1ps
// Contract sec. 7 (Q6): C4 REVOKE latency on rtl/dual_lane/pq_noc_subsystem_p7.sv (PQ_MAC_ON), chain row 0 provisioning.
// Latency: from the first sampled rising edge of `revoke` with authorized[3] = 1 to the first sampled authorized[3] = 0.
// Every scenario starts from reset with tile 3 attested (authorized). Scenarios S (one check C4_<S> each, latency <= 1500):
//   IDLE; a revoke edge during a second attestation in each verifier state KSTART, KWAIT, REQ, FILL, WAIT, CHECK, TSTART,
//   TWAIT, GRANT (9); SAT_DATA (tile 3's application writes back to back and the raw port floods own-source data toward
//   tile 3 for the whole window); RAW_WITHHELD_TAIL, RAW_ENDLESS_BODY, RAW_NESTED_HEAD (raw-port faults on the path to tile 3);
//   PEER_OCCUPIED (the edge while tile 3's slot P holds the second attestation's CHALLENGE); Q_CONTENTION (the edge while the
//   shared engine serves tile 3's RESPONSE, requester r2); HELD (revoke held for 10,000 cycles).
// Plus C4_MAX: the maximum over all scenarios <= 1500 (also printed with the per-scenario values).
// CHECKS = 1 + 9 + 1 + 3 + 1 + 1 + 1 + 1 = 18, frozen from this source before the first run. Setup failures: TB_TIMEOUT.
module tb_p7_c4;
  import noc_pkg::*;
  import noc_p7_pkg::*;
  localparam int BOUND = 1500;
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
  logic [775:0] endpoint_response, expected_response;
  logic [31:0] memory_commits, memory_last_data, endpoint_rejected, verifier_rejected;
  logic [511:0] keys_p7;
  assign keys_p7 = {directed_keys[(3*6+4)*256 +: 256], directed_keys[(4*6+3)*256 +: 256]};
  pq_noc_subsystem_p7 dut(.clk, .rst, .start_attestation, .revoke, .boot_epoch, .attest_epoch, .nonce, .root_secret,
    .approved_measurement, .directed_keys(keys_p7), .context_in, .context_len, .config_data, .imem, .config_len, .imem_len,
    .app_valid, .app_payload_valid, .app_ready, .app_payload_ready, .app_destination, .app_message, .app_control, .app_payload,
    .spoof_raw_valid, .spoof_raw_flit, .spoof_raw_ready, .authorized, .rot_busy, .grant_done, .attestation_failed,
    .endpoint_response, .memory_commits, .memory_last_data, .app_tx_error, .endpoint_rejected, .verifier_rejected);
  `include "full_chain.svh"
  localparam logic [31:0] ADDR = 32'h8200_0100;
  int checks = 0, errors = 0, lat_max = 0, grants = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  task automatic timeout(input string w); $display("TB_TIMEOUT %s", w); $finish; endtask
  always @(posedge clk) if (!rst && grant_done) grants++;
  // latency monitor: armed by the first sampled rising edge of revoke while authorized[3] = 1
  logic rev_q = 0; bit armed = 0; int lat = -1, cnt = 0;
  always @(posedge clk) begin
    if (rst) begin rev_q <= 0; armed = 0; end
    else begin
      if (!armed && revoke && !rev_q && authorized[3]) begin armed = 1; cnt = 0; lat = -1; end
      else if (armed) begin cnt++; if (!authorized[3]) begin lat = cnt; armed = 0; end end
      rev_q <= revoke;
    end
  end
  bit flood = 0, wflood = 0;
  // background loads (SAT_DATA)
  initial forever begin
    @(negedge clk);
    if (flood) begin
      automatic head_flit_t h; automatic flit_t f; automatic coord_t s, d;   // set by statements: XSim 2024.1 leaves a later declarator X when a chained initializer holds an enum cast
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
  task automatic attest_ok(input int row);
    automatic int g0 = grants, n = 0;
    load_chain(row); pulse_start();
    while (!(grants == g0 + 1 && authorized[3]) && n < 60000) begin @(negedge clk); n++; end
    if (!(grants == g0 + 1 && authorized[3])) timeout($sformatf("setup attestation row %0d", row));
    repeat (20) @(negedge clk);
  endtask
  task automatic raw_flit(input flit_t f);
    automatic int n = 0;
    @(negedge clk); spoof_raw_flit = f; spoof_raw_valid = 1;
    do begin @(posedge clk); n++; end while (!spoof_raw_ready && n < 2000);
    @(negedge clk); spoof_raw_valid = 0;
  endtask
  function automatic flit_t hf5(input int dst, input msg_type_e m, input int len, input logic [1:0] vc);
    automatic head_flit_t h; automatic flit_t f; automatic coord_t s, d;   // set by statements: XSim 2024.1 leaves a later declarator X when a chained initializer holds an enum cast
    h = '0; s = tile_to_coord(TILE_SPOOF); d = tile_to_coord(tile_id_e'(dst));
    h.src_x = s.x; h.src_y = s.y; h.dest_x = d.x; h.dest_y = d.y; h.msg_type = m; h.length = 5'(len);
    f.flit_data = h; f.flit_type = FLIT_HEAD; f.vc_id = vc; return f;
  endfunction
  function automatic flit_t bf(input logic [31:0] d, input flit_type_e t, input logic [1:0] vc);
    automatic flit_t f; f.flit_data = d; f.flit_type = t; f.vc_id = vc; return f;
  endfunction
  // apply one revoke edge (or a held level) now and return the measured latency
  task automatic measure(input string name, input bit held = 0);
    automatic int n = 0;
    @(negedge clk); revoke = 1;
    if (!held) begin @(negedge clk); revoke = 0; end
    while (lat < 0 && n < 3 * BOUND) begin @(negedge clk); n++; end
    if (held) begin repeat (10000 - n) @(negedge clk); revoke = 0; end
    flood = 0; wflood = 0;
    if (lat > lat_max) lat_max = lat;
    check(lat >= 0 && lat <= BOUND, $sformatf("C4_%s latency=%0d (bound %0d)", name, lat, BOUND));
    $display("C4_LAT %s %0d", name, lat);
    repeat (200) @(negedge clk);
  endtask
  task automatic wait_vs(input int s);
    automatic int n = 0;
    while (dut.verifier.vs != s && n < 60000) begin @(negedge clk); n++; end
    if (dut.verifier.vs != s) timeout($sformatf("verifier state %0d", s));
  endtask
  // state names by a case function: XSim 2024.1 printed a localparam string array element as garbage (run 182317)
  function automatic string vsn(input int s);
    case (s) 0: return "IDLE"; 1: return "KSTART"; 2: return "KWAIT"; 3: return "REQ"; 4: return "FILL"; 5: return "WAIT";
      6: return "CHECK"; 7: return "TSTART"; 8: return "TWAIT"; 9: return "GRANT"; 10: return "REVOKE"; default: return "BAD"; endcase
  endfunction
  initial begin
    $display("CONFIG: TOP=tb_p7_c4 CHECKS=18 BOUND=%0d", BOUND);
    app_valid = 0; app_payload_valid = 0; app_destination = '0; app_message = '0; app_control = 0; app_payload = 0; spoof_raw_flit = '0;
    load_chain(0); boot_epoch = BOOT; directed_keys = KEYS;
    do_reset(); attest_ok(0); measure("IDLE");
    for (int s = 1; s <= 9; s++) begin
      do_reset(); attest_ok(0); load_chain(1); pulse_start(); wait_vs(s); measure(vsn(s));
    end
    do_reset(); attest_ok(0); flood = 1; wflood = 1; repeat (300) @(negedge clk); measure("SAT_DATA");
    do_reset(); attest_ok(0);                                    // withheld TAIL on the raw port toward tile 3
    raw_flit(hf5(3, MSG_MEM_WR_REQ, 3, 2'd0)); raw_flit(bf(ADDR, FLIT_BODY, 2'd0)); measure("RAW_WITHHELD_TAIL");
    do_reset(); attest_ok(0);
    fork begin raw_flit(hf5(3, MSG_MEM_RD_REQ, 2, 2'd0)); repeat (200) raw_flit(bf(32'h0, FLIT_BODY, 2'd0)); end measure("RAW_ENDLESS_BODY"); join
    do_reset(); attest_ok(0);
    fork begin raw_flit(hf5(3, MSG_MEM_RD_REQ, 2, 2'd0)); raw_flit(hf5(3, MSG_MEM_RD_REQ, 2, 2'd0)); raw_flit(bf(ADDR, FLIT_TAIL, 2'd0)); end
         measure("RAW_NESTED_HEAD"); join
    do_reset(); attest_ok(0); load_chain(1); pulse_start();
    begin automatic int n = 0; while (dut.l2.W[0].l2.ps == 0 && n < 60000) begin @(negedge clk); n++; end end
    measure("PEER_OCCUPIED");
    do_reset(); attest_ok(0); load_chain(1); pulse_start();
    begin automatic int n = 0; while (!(dut.l2.engine.busy && dut.l2.engine.owner == 2'd2) && n < 60000) begin @(negedge clk); n++; end
      if (n >= 60000) timeout("engine serving r2"); end
    measure("Q_CONTENTION");
    do_reset(); attest_ok(0); measure("HELD", 1'b1);
    check(lat_max <= BOUND, $sformatf("C4_MAX max_latency=%0d (bound %0d)", lat_max, BOUND));
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #60ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
