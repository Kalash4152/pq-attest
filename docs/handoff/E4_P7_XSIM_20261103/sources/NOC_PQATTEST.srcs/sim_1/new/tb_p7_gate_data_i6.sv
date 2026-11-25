`timescale 1ns/1ps
// Sec. 9 authorization mapping, row "plain-tile data refused at the gate" (Kalash 2026-10-28, Q2; DECISION_REGISTER
// S2-N2P7): on rtl/dual_lane/pq_noc_subsystem_p7.sv (PQ_MAC_ON) the non-attested tiles 0, 1, 2, 5 can send no data.
// noc_attest_gate is built ATTESTABLE = 0 there (authorized stays 0) and passes a data request only when authorized
// (noc_attest_gate.sv:21-23). Per tile the attack first tries to become authorized: a GRANT (control[10:7] = 1, src = RoT)
// is presented at the tile's network input through the bench-only TB_INJECT hook (as tb_p7_refuse_grant), then the tile's
// application offers a MEM_WR_REQ (to the memory; tile 2 writes to tile 0) with its payload for 200 cycles.
// Check GATE_DATA_REFUSED_<g>: authorized[g] = 0, app_ready[g] never 1, nothing from tile g enters the mesh, and no memory
// commit.                                                                                                     4
// CHECKS = 4, frozen before the first run. Negative controls: p7s_control_allowed (CONTROL_ALLOWED = 1, ATTESTABLE = 1: the
// GRANT authorizes the tile, its data passes) and p7s_gate_bypass (the plain-tile gates pass data without authorization).
module tb_p7_gate_data;
  import noc_pkg::*;
  import noc_p7_pkg::*;
  logic clk = 0, rst = 1;
  always #10 clk = ~clk;
  logic [5:0] app_valid = 0, app_payload_valid = 0, app_ready, app_payload_ready, app_tx_error;
  coord_t [5:0] app_destination = '0;
  msg_type_e [5:0] app_message;
  logic [5:0][10:0] app_control = '0;
  logic [5:0][31:0] app_payload = '0;
  logic spoof_raw_ready; flit_t spoof_raw_flit = '0;
  logic [5:0] authorized;
  logic rot_busy, grant_done, attestation_failed;
  logic [775:0] endpoint_response;
  logic [31:0] memory_commits, memory_last_data, endpoint_rejected, verifier_rejected;
  pq_noc_subsystem_p7 #(.TB_INJECT(1'b1)) dut(.clk, .rst, .start_attestation(1'b0), .revoke(1'b0), .boot_epoch(80'h1), .attest_epoch(80'h1),
    .nonce('0), .root_secret('0), .approved_measurement('0), .directed_keys('0), .context_in('0), .context_len('0),
    .config_data('0), .imem('0), .config_len('0), .imem_len('0),
    .trusted_clear(1'b0), .app_valid, .app_payload_valid, .app_ready, .app_payload_ready, .app_destination, .app_message, .app_control, .app_payload,
    .spoof_raw_valid(1'b0), .spoof_raw_flit, .spoof_raw_ready, .authorized, .rot_busy, .grant_done, .attestation_failed,
    .endpoint_response, .memory_commits, .memory_last_data, .app_tx_error, .endpoint_rejected, .verifier_rejected);
  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  task automatic timeout(input string w); $display("TB_TIMEOUT %s", w); $finish; endtask
  task automatic present(input int g, input flit_t f, input bit v);
    dut.TBI.f[g] = f; dut.TBI.v[g] = v;
  endtask
  task automatic grant_packet(input int g);
    automatic head_flit_t h; automatic flit_t f; automatic coord_t s, d;   // set by statements (XSim chained-cast X)
    h = '0; s = tile_to_coord(TILE_ROT); d = tile_to_coord(tile_id_e'(g));
    h.src_x = s.x; h.src_y = s.y; h.dest_x = d.x; h.dest_y = d.y; h.msg_type = MSG_ATTEST_GRANT; h.length = p7_length(MSG_ATTEST_GRANT);
    h.control.raw = 11'h080;
    for (int i = 0; i < 5; i++) begin
      automatic int n = 0;
      f.vc_id = message_to_vc(MSG_ATTEST_GRANT);
      if (i == 0) begin f.flit_data = h; f.flit_type = FLIT_HEAD; end
      else begin f.flit_data = 32'hAC00_0000 + i; f.flit_type = i == 4 ? FLIT_TAIL : FLIT_BODY; end
      @(negedge clk); present(g, f, 1'b1);
      do begin @(posedge clk); n++; end while (!dut.mesh_or[g] && n < 2000);
      if (!dut.mesh_or[g]) timeout($sformatf("tile %0d NI never ready", g));
    end
    @(negedge clk); present(g, '0, 1'b0);
  endtask
  localparam int TILES [4] = '{0, 1, 2, 5};
  initial begin
    $display("CONFIG: TOP=tb_p7_gate_data CHECKS=4 TILES=0,1,2,5");
    for (int g = 0; g < 6; g++) app_message[g] = MSG_MEM_RD_REQ;
    repeat (6) @(negedge clk); rst = 0; repeat (5) @(negedge clk);
    foreach (TILES[t]) begin
      automatic int g = TILES[t];
      automatic bit rdy = 0, sent = 0;
      automatic logic [31:0] c0;
      grant_packet(g);
      repeat (50) @(negedge clk);
      c0 = memory_commits;
      @(negedge clk);
      app_destination[g] = tile_to_coord(g == 2 ? TILE_CPU0 : TILE_MEMORY); app_message[g] = MSG_MEM_WR_REQ; app_control[g] = 11'h780;
      app_payload[g] = 32'h2200_0100; app_valid[g] = 1; app_payload_valid[g] = 1;
      repeat (200) begin @(posedge clk); if (app_ready[g]) rdy = 1; if (dut.tile_ov[g]) sent = 1; end
      @(negedge clk); app_valid[g] = 0; app_payload_valid[g] = 0; app_message[g] = MSG_MEM_RD_REQ;
      repeat (100) begin @(posedge clk); if (dut.tile_ov[g]) sent = 1; end
      check(!authorized[g] && !rdy && !sent && memory_commits == c0,
            $sformatf("GATE_DATA_REFUSED_%0d authorized=%b app_ready_seen=%b sent=%b commits=+%0d", g, authorized[g], rdy, sent, memory_commits - c0));
    end
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #2ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
