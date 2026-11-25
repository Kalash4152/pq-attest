`timescale 1ns/1ps
// Step d, M-F1 rev 7 R7.4 / C2 (required test): the non-attested tiles 0, 1, 2, 5 of rtl/dual_lane/pq_noc_subsystem_p7.sv
// refuse GRANT/REVOKE. PQ_MAC_ON. In P7 no trusted path can carry a control packet to these tiles (the L2 TX refuses a
// non-peer destination, the ingress drops forged sources), so the packets are presented at each tile's network input
// directly through the subsystem's bench-only TB_INJECT hook (fault injection at the eject port, no force), honouring
// the NI's ready. Each packet is NI-format as an L2 wrapper would replay it: HEAD (src = TILE_ROT, dest = g, length 5) + 4 MAC words.
// Checks, for g in {0, 1, 2, 5}:
//   P7R_REFUSE_<g>_GRANT / P7R_REFUSE_<g>_REVOKE: l2_rejected[g] rises by one with reason 8, authorized[g] stays 0, no
//     gate fault (fault 5 is unreachable), and the NI delivers no control HEAD to the tile.                       8
//   P7R_TX_REFUSED_<g>: the tile's application asks to send a GRANT to tile 3; the NI raises tx_error and nothing from
//     tile g enters the mesh within 200 cycles.                                                                   4
// CHECKS = 12, frozen before the first run. Mutant p7s_control_allowed (CONTROL_ALLOWED = 1, ATTESTABLE = 1) must be killed
// by P7R_ checks (the GRANT authorizes the tile).
module tb_p7_refuse_grant;
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
  logic [5:0][31:0] l2_rejected, l2_accepted, gate_faults, ingress_rejected;
  logic [5:0][3:0] l2_reason, ingress_reason;
  logic [1:0][31:0] p_slot_drops;
  pq_noc_subsystem_p7 #(.TB_INJECT(1'b1)) dut(.clk, .rst, .start_attestation(1'b0), .revoke(1'b0), .boot_epoch(80'h1), .attest_epoch(80'h1),
    .nonce('0), .root_secret('0), .approved_measurement('0), .directed_keys('0), .context_in('0), .context_len('0),
    .config_data('0), .imem('0), .config_len('0), .imem_len('0),
    .app_valid, .app_payload_valid, .app_ready, .app_payload_ready, .app_destination, .app_message, .app_control, .app_payload,
    .spoof_raw_valid(1'b0), .spoof_raw_flit, .spoof_raw_ready, .authorized, .rot_busy, .grant_done, .attestation_failed,
    .endpoint_response, .memory_commits, .memory_last_data, .l2_rejected, .l2_accepted, .gate_faults, .ingress_rejected,
    .l2_reason, .ingress_reason, .p_slot_drops, .app_tx_error, .endpoint_rejected, .verifier_rejected);
  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  task automatic timeout(input string w); $display("TB_TIMEOUT %s", w); $finish; endtask
  int ctl_deliv [6] = '{0, 0, 0, 0, 0, 0};
  always @(posedge clk) if (!rst) for (int g = 0; g < 6; g++) if (dut.rhv[g] && is_control(dut.rxmsg[g])) ctl_deliv[g]++;
  // present a flit at tile g's network input through the bench-only TB_INJECT hook (procedural assignment, no force);
  // the NI's ready is honoured exactly as at the mesh eject port
  task automatic present(input int g, input flit_t f, input bit v);
    dut.TBI.f[g] = f; dut.TBI.v[g] = v;
  endtask
  task automatic ctl_packet(input int g, input msg_type_e m);
    automatic head_flit_t h; automatic flit_t f; automatic coord_t s, d;   // set by statements: XSim 2024.1 leaves a later declarator X when a chained initializer holds an enum cast
    h = '0; s = tile_to_coord(TILE_ROT); d = tile_to_coord(tile_id_e'(g));
    h.src_x = s.x; h.src_y = s.y; h.dest_x = d.x; h.dest_y = d.y; h.msg_type = m; h.length = p7_length(m);
    h.control.raw = (m == MSG_ATTEST_GRANT) ? 11'h080 : 11'h000;
    for (int i = 0; i < 5; i++) begin
      automatic int n = 0;
      f.vc_id = message_to_vc(m);
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
    $display("CONFIG: TOP=tb_p7_refuse_grant CHECKS=12 TILES=0,1,2,5");
    for (int g = 0; g < 6; g++) app_message[g] = MSG_MEM_RD_REQ;
    repeat (6) @(negedge clk); rst = 0; repeat (5) @(negedge clk);
    foreach (TILES[t]) begin
      automatic int g = TILES[t];
      for (int k = 0; k < 2; k++) begin
        automatic msg_type_e m = k == 0 ? MSG_ATTEST_GRANT : MSG_ATTEST_REVOKE;
        automatic logic [31:0] r0 = l2_rejected[g], f0 = gate_faults[g]; automatic int d0 = ctl_deliv[g];
        ctl_packet(g, m);
        repeat (50) @(negedge clk);
        check(l2_rejected[g] == r0 + 1 && l2_reason[g] == 4'd8 && authorized[g] == 0 && gate_faults[g] == f0 && ctl_deliv[g] == d0,
              $sformatf("P7R_REFUSE_%0d_%s rej=+%0d reason=%0d authorized=%b faults=+%0d delivered=+%0d", g, k == 0 ? "GRANT" : "REVOKE",
                        l2_rejected[g] - r0, l2_reason[g], authorized[g], gate_faults[g] - f0, ctl_deliv[g] - d0));
      end
    end
    foreach (TILES[t]) begin
      automatic int g = TILES[t]; automatic bit err = 0, sent = 0;
      @(negedge clk); app_destination[g] = tile_to_coord(TILE_CRYPTO); app_message[g] = MSG_ATTEST_GRANT; app_control[g] = 11'h080; app_valid[g] = 1;
      repeat (200) begin @(posedge clk); if (app_tx_error[g]) err = 1; if (dut.tile_ov[g]) sent = 1; end
      @(negedge clk); app_valid[g] = 0; app_message[g] = MSG_MEM_RD_REQ;
      repeat (20) begin @(posedge clk); if (dut.tile_ov[g]) sent = 1; end
      check(err && !sent, $sformatf("P7R_TX_REFUSED_%0d tx_error=%b sent=%b", g, err, sent));
    end
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #2ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
