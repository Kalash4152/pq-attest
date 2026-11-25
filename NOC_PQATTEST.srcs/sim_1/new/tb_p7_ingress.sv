`timescale 1ns/1ps
// Contract sec. 1d (M-F1 R7.5b) on rtl/dual_lane/pq_noc_subsystem_p7.sv (PQ_MAC_ON): raw-port quarantine, NI-port
// parsers, port-5 merge. Chain row 0 provisioning (vectors/full_chain.svh); every section starts from reset with tile 3
// attested and authorized. The raw port is the untrusted protocol-level local injector at tile 5 (src 5 is its own source).
// A. Forged source on the raw port (reason 9, zero delivery):
//    Q9_CHALLENGE_SRC4 (17-flit CHALLENGE claiming 4 -> 3), Q9_WRITE_SRC3 (MEM_WR_REQ claiming 3 -> 2),
//    Q9_HEAD_TAIL_SRC3 (single-flit MEM_WR_RESP claiming 3): q_rejected +1, q_reason 9, q_forwarded unchanged, no
//    delivery at the destination, tile-3 L2 counters and memory_commits unchanged.                               3
// B. Nested HEAD inside a legal own-source packet (reason 11, zero delivery): Q11_NESTED_SAME_VC, Q11_NESTED_CROSS_VC,
//    Q11_NESTED_SRC4_GRANT (a forged src = 4 GRANT HEAD inside a legal VC0 MEM_WR_REQ 5 -> 2).                     3
// C. Malformed continuation / stray flits (reason 11, discarded, then resync): for each of MID_HEAD_TAIL, VC_CHANGE,
//    EARLY_TAIL, OVERLONG, ENDLESS_BODY, STRAY_BODY, STRAY_TAIL: Q11_<case> (q_reason 11 and nothing of it delivered) and
//    QRESYNC_<case> (the next legal raw packet is delivered unchanged).                                       7 x 2 = 14
// D. Withheld TAIL (raw HEAD + 1 body, then nothing for 10,000 cycles) toward tile 3 while the RoT revokes:
//    QW_REASON10 (q_reason 10), QW_NO_ROUTE_HOLD (no flit of the partial packet ever entered the mesh),
//    QW_REVOKE_DELIVERED (authorized[3] falls within 1,500 cycles of the revoke pulse).                           3
// E. Missing final write-data flit (raw MEM_WR_REQ 5 -> 2, HEAD + address only): QE_DISCARDED (q_discarded +1, reason 10),
//    QE_NO_COMMIT (no HEAD from tile 5 reaches tile 2, memory_commits unchanged, no zero write).                   2
// F. Gap counter, standalone quarantine u_q (out_ready driven by the TB): QGAP_V1R1 (accepted flit resets gap),
//    QGAP_V0R1 (idle sender with space: +1 per cycle), QGAP_V1R0 and QGAP_V0R0 (FIFO full, in_ready = 0: no change).  4
// G. Legal traffic: QG_RAW_TO_<d> for d = 0, 1, 2, 3, 4 (own-source MEM_RD_REQ delivered unchanged at tile d's NI);
//    QG_NI3_WRITE (tile 3's write commits), QG_NI2_REPLY (tile 2's reply reaches tile 3), QG_NI4_ATTEST (an attestation
//    through tile 4 grants).                                                                                      8
// H. NI-port parser, standalone u_p (port 1): QP_FORGED (src != 1 HEAD: reason 9, consumed whole, nothing forwarded),
//    QP_LEGAL (src = 1 packet forwarded unchanged).                                                               2
// CHECKS = 3 + 3 + 14 + 3 + 2 + 4 + 8 + 2 = 39, frozen from this source before the first run. Setup failures: TB_TIMEOUT.
// ING_ONLY_C (define; job p7_ingress_c and mutant ig_mut_q_no_cap; Kalash 2026-10-22): section C alone. Without the length
//   cap the endless body fills the FIFO and the raw port stalls for good (liveness), so every raw-port wait is bounded
//   (N = 5,000 cycles per flit, the raw() bound; correct RTL takes or discards each flit within a cycle) and judged by
//   the targeted check QC_RAW_PORT_LIVE (no stall), never a TB_TIMEOUT. CHECKS = 14 + 1 = 15.
module tb_p7_ingress;
  import noc_pkg::*;
  import noc_p7_pkg::*;
  localparam int E2E_REVOKE = 1500;
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
  logic [31:0] memory_commits, memory_last_data, endpoint_rejected, verifier_rejected, q_rejected, q_forwarded, q_discarded, mem_faults;
  logic [3:0] q_reason;
  logic [5:0][31:0] l2_rejected, l2_accepted, gate_faults, ingress_rejected, ingress_fault;
  logic [5:0][3:0] l2_reason, ingress_reason;
  logic [1:0][31:0] p_slot_drops;
  logic [511:0] keys_p7;
  assign keys_p7 = {directed_keys[(3*6+4)*256 +: 256], directed_keys[(4*6+3)*256 +: 256]};
  pq_noc_subsystem_p7 dut(.clk, .rst, .start_attestation, .revoke, .boot_epoch, .attest_epoch, .nonce, .root_secret,
    .approved_measurement, .directed_keys(keys_p7), .context_in, .context_len, .config_data, .imem, .config_len, .imem_len,
    .app_valid, .app_payload_valid, .app_ready, .app_payload_ready, .app_destination, .app_message, .app_control, .app_payload,
    .spoof_raw_valid, .spoof_raw_flit, .spoof_raw_ready, .authorized, .rot_busy, .grant_done, .attestation_failed,
    .endpoint_response, .memory_commits, .memory_last_data, .l2_rejected, .l2_accepted, .gate_faults, .ingress_rejected,
    .ingress_fault, .q_rejected, .q_forwarded, .q_discarded, .mem_faults, .q_reason,
    .l2_reason, .ingress_reason, .p_slot_drops, .app_tx_error, .endpoint_rejected, .verifier_rejected);
  `include "full_chain.svh"
  localparam logic [31:0] ADDR = 32'h8200_0100;
  // standalone units for sections F and H
  flit_t uq_in, uq_out, up_in, up_out; logic uq_iv = 0, uq_ir, uq_ov, uq_or = 1, up_iv = 0, up_ir, up_ov, up_or = 1;
  logic [31:0] uq_rej, uq_fwd, uq_dis, up_rej, up_flt; logic [3:0] uq_rsn, up_rsn;
  noc_ingress_quarantine #(.PORT(5)) u_q (.clk, .rst, .in_flit(uq_in), .in_valid(uq_iv), .in_ready(uq_ir), .out_flit(uq_out),
    .out_valid(uq_ov), .out_ready(uq_or), .q_rejected(uq_rej), .q_forwarded(uq_fwd), .q_discarded(uq_dis), .q_reason(uq_rsn));
  noc_ingress_parser #(.PORT(1)) u_p (.clk, .rst, .in_flit(up_in), .in_valid(up_iv), .in_ready(up_ir), .out_flit(up_out),
    .out_valid(up_ov), .out_ready(up_or), .rejected_count(up_rej), .fault_count(up_flt), .reject_reason(up_rsn));
  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  task automatic timeout(input string w); $display("TB_TIMEOUT %s", w); $finish; endtask
  // monitors: deliveries per tile from tile 5, grants, port-5 mesh entries, tile-2 heads from tile 5
  int grants = 0, rd_resp3 = 0, from5 [6] = '{0,0,0,0,0,0}, mesh5_flits = 0, up_fwd = 0;
  always @(posedge clk) if (!rst) begin
    if (grant_done) grants++;
    if (dut.rhv[3] && dut.rxmsg[3] == MSG_MEM_RD_RESP) rd_resp3++;
    for (int g = 0; g < 6; g++) if (dut.rhv[g] && dut.rxsrc[g] == tile_to_coord(TILE_SPOOF)) from5[g]++;
    if (dut.mesh_iv[5] && dut.mesh_ir[5] && dut.q_ov) mesh5_flits++;
    if (up_ov && up_or) up_fwd++;
  end
  task automatic do_reset();
    @(negedge clk); rst = 1; app_valid = 0; app_payload_valid = 0; revoke = 0; start_attestation = 0; spoof_raw_valid = 0;
    uq_iv = 0; up_iv = 0; uq_or = 1; up_or = 1;
    repeat (6) @(negedge clk); rst = 0; repeat (5) @(negedge clk);
  endtask
  task automatic pulse_start(); @(negedge clk); start_attestation = 1; @(negedge clk); start_attestation = 0; endtask
  task automatic attest_ok(input int row);
    automatic int g0 = grants, n = 0;
    load_chain(row); pulse_start();
    while (!(grants == g0 + 1 && authorized[3]) && n < 60000) begin @(negedge clk); n++; end
    if (!(grants == g0 + 1 && authorized[3])) timeout($sformatf("setup attestation row %0d", row));
    repeat (20) @(negedge clk);
  endtask
  task automatic app_hdr(input int g, input coord_t d, input msg_type_e m, input logic [10:0] c, output bit ok);
    automatic int n = 0;
    @(negedge clk); app_destination[g] = d; app_message[g] = m; app_control[g] = c; app_valid[g] = 1;
    do begin @(posedge clk); n++; end while (!app_ready[g] && n < 20000);
    ok = app_ready[g]; @(negedge clk); app_valid[g] = 0;
  endtask
  task automatic app_words(input int g, input logic [31:0] w [4], input int nw, output bit ok);
    ok = 1;
    for (int i = 0; i < nw && ok; i++) begin
      automatic int n = 0;
      app_payload[g] = w[i]; app_payload_valid[g] = 1;
      do begin @(posedge clk); n++; end while (!app_payload_ready[g] && n < 20000);
      ok = app_payload_ready[g]; @(negedge clk);
    end
    app_payload_valid[g] = 0;
  endtask
  int raw_stalls = 0;
  task automatic raw(input flit_t f);
    automatic int n = 0;
    @(negedge clk); spoof_raw_flit = f; spoof_raw_valid = 1;
    do begin @(posedge clk); n++; end while (!spoof_raw_ready && n < 5000);
    if (!spoof_raw_ready) begin
`ifdef ING_ONLY_C
      raw_stalls++;          // judged by QC_RAW_PORT_LIVE
`else
      timeout("raw port never ready");
`endif
    end
  endtask
  task automatic raw_idle(input int n = 1); repeat (n) begin @(negedge clk); spoof_raw_valid = 0; end endtask
  function automatic flit_t hf(input int src, input int dst, input msg_type_e m, input int len, input flit_type_e ft, input logic [1:0] vc);
    automatic head_flit_t h; automatic flit_t f; automatic coord_t s, d;   // set by statements: XSim 2024.1 leaves a later declarator X when a chained initializer holds an enum cast
    h = '0; s = tile_to_coord(tile_id_e'(src)); d = tile_to_coord(tile_id_e'(dst));
    h.src_x = s.x; h.src_y = s.y; h.dest_x = d.x; h.dest_y = d.y; h.msg_type = m; h.length = 5'(len);
    h.control.raw = (m == MSG_MEM_WR_REQ) ? 11'h780 : (m == MSG_ATTEST_GRANT) ? 11'h080 : 11'h000;
    f.flit_data = h; f.flit_type = ft; f.vc_id = vc; return f;
  endfunction
  function automatic flit_t bf(input logic [31:0] d, input flit_type_e ft, input logic [1:0] vc);
    automatic flit_t f; f.flit_data = d; f.flit_type = ft; f.vc_id = vc; return f;
  endfunction
  function automatic int wl(input msg_type_e m); return is_control(m) ? int'(p7_length(m)) + 5 : int'(p7_length(m)); endfunction
  // a complete legal own-source raw packet 5 -> d (MEM_RD_REQ: HEAD + address)
  task automatic raw_legal(input int d, input logic [31:0] a);
    raw(hf(5, d, MSG_MEM_RD_REQ, 2, FLIT_HEAD, 2'(message_to_vc(MSG_MEM_RD_REQ)))); raw(bf(a, FLIT_TAIL, 2'(message_to_vc(MSG_MEM_RD_REQ)))); raw_idle();
  endtask
  task automatic settle(input int n = 600); repeat (n) @(negedge clk); endtask
  bit ok, ok2; logic [31:0] w [4];
  localparam logic [1:0] VC0 = 2'd0, VC1 = 2'd1, VC2 = 2'd2;

  initial begin
`ifdef ING_ONLY_C
    $display("CONFIG: TOP=tb_p7_ingress CHECKS=39 W_Q=64 E2E_REVOKE=%0d PHASES=C CHECKS=15", E2E_REVOKE);
`else
    $display("CONFIG: TOP=tb_p7_ingress CHECKS=39 W_Q=64 E2E_REVOKE=%0d PHASES=ALL CHECKS=39", E2E_REVOKE);
`endif
    app_valid = 0; app_payload_valid = 0; app_destination = '0; app_message = '0; app_control = 0; app_payload = 0;
    spoof_raw_flit = '0; uq_in = '0; up_in = '0;
    load_chain(0); boot_epoch = BOOT; directed_keys = KEYS;
    do_reset(); attest_ok(0);
`ifndef ING_ONLY_C
    // ---- A: forged sources on the raw port
    for (int k = 0; k < 3; k++) begin
      automatic logic [31:0] r0 = q_rejected, f0 = q_forwarded, l3 = l2_rejected[3] + l2_accepted[3], c0 = memory_commits;
      automatic int d0 = from5[2] + from5[3]; string nm [3] = '{"CHALLENGE_SRC4", "WRITE_SRC3", "HEAD_TAIL_SRC3"};
      if (k == 0) begin raw(hf(4, 3, MSG_ATTEST_CHALLENGE, 17, FLIT_HEAD, VC2)); for (int i = 1; i < 17; i++) raw(bf(32'h0, i == 16 ? FLIT_TAIL : FLIT_BODY, VC2)); end
      else if (k == 1) begin raw(hf(3, 2, MSG_MEM_WR_REQ, 3, FLIT_HEAD, VC0)); raw(bf(ADDR, FLIT_BODY, VC0)); raw(bf(32'hBAD0_0003, FLIT_TAIL, VC0)); end
      else raw(hf(3, 3, MSG_MEM_WR_RESP, 1, FLIT_HEAD_TAIL, VC1));
      raw_idle(); settle();
      check(q_rejected == r0 + 1 && q_reason == 4'd9 && q_forwarded == f0 && l2_rejected[3] + l2_accepted[3] == l3 && memory_commits == c0,
            $sformatf("Q9_%s rej=+%0d reason=%0d fwd=+%0d", nm[k], q_rejected - r0, q_reason, q_forwarded - f0));
    end
    // ---- B: nested HEADs
    for (int k = 0; k < 3; k++) begin
      automatic logic [31:0] r0 = q_rejected, l3 = l2_rejected[3] + l2_accepted[3]; automatic int d0 = from5[0] + from5[2] + from5[3];
      string nm [3] = '{"SAME_VC", "CROSS_VC", "SRC4_GRANT"};
      if (k < 2) begin
        raw(hf(5, 0, MSG_MEM_RD_REQ, 2, FLIT_HEAD, VC0)); raw(hf(5, 0, MSG_MEM_RD_REQ, 2, FLIT_HEAD, k == 0 ? VC0 : VC1)); raw(bf(ADDR, FLIT_TAIL, VC0));
      end else begin
        raw(hf(5, 2, MSG_MEM_WR_REQ, 3, FLIT_HEAD, VC0)); raw(hf(4, 3, MSG_ATTEST_GRANT, 10, FLIT_HEAD, VC0));
        for (int i = 0; i < 9; i++) raw(bf(32'h0, i == 8 ? FLIT_TAIL : FLIT_BODY, VC0));
      end
      raw_idle(); settle();
      check(q_rejected >= r0 + 1 && q_reason == 4'd11 && from5[0] + from5[2] + from5[3] == d0 && l2_rejected[3] + l2_accepted[3] == l3,
            $sformatf("Q11_NESTED_%s rej=+%0d reason=%0d", nm[k], q_rejected - r0, q_reason));
    end
`endif
    // ---- C: malformed continuations and strays, each followed by a legal packet (resync)
    for (int k = 0; k < 7; k++) begin
      automatic logic [31:0] r0 = q_rejected; automatic int d0 = from5[0];
      string nm [7] = '{"MID_HEAD_TAIL", "VC_CHANGE", "EARLY_TAIL", "OVERLONG", "ENDLESS_BODY", "STRAY_BODY", "STRAY_TAIL"};
      case (k)
        0: begin raw(hf(5, 0, MSG_MEM_WR_REQ, 3, FLIT_HEAD, VC0)); raw(bf(ADDR, FLIT_HEAD_TAIL, VC0)); end
        1: begin raw(hf(5, 0, MSG_MEM_WR_REQ, 3, FLIT_HEAD, VC0)); raw(bf(ADDR, FLIT_BODY, VC1)); raw(bf(32'h1, FLIT_TAIL, VC1)); end
        2: begin raw(hf(5, 0, MSG_MEM_WR_REQ, 3, FLIT_HEAD, VC0)); raw(bf(ADDR, FLIT_TAIL, VC0)); end
        3: begin raw(hf(5, 0, MSG_MEM_RD_REQ, 2, FLIT_HEAD, VC0)); raw(bf(ADDR, FLIT_BODY, VC0)); raw(bf(32'h1, FLIT_TAIL, VC0)); end
        4: begin raw(hf(5, 0, MSG_MEM_RD_REQ, 2, FLIT_HEAD, VC0)); for (int i = 0; i < 40; i++) raw(bf(32'h0, FLIT_BODY, VC0)); end
        5: raw(bf(32'h0, FLIT_BODY, VC0));
        default: raw(bf(32'h0, FLIT_TAIL, VC0));
      endcase
      raw_idle(); settle(200);
      check(q_rejected >= r0 + 1 && q_reason == 4'd11 && from5[0] == d0, $sformatf("Q11_%s rej=+%0d reason=%0d", nm[k], q_rejected - r0, q_reason));
      d0 = from5[0]; raw_legal(0, ADDR); settle(400);
      check(from5[0] == d0 + 1, $sformatf("QRESYNC_%s delivered=+%0d", nm[k], from5[0] - d0));
    end
`ifdef ING_ONLY_C
    check(raw_stalls == 0, $sformatf("QC_RAW_PORT_LIVE raw-port stalls=%0d (bound 5000 cycles per flit)", raw_stalls));
`else
    // ---- G (raw part): legal own-source traffic to every tile
    for (int d = 0; d < 5; d++) begin
      automatic int d0 = from5[d];
      raw_legal(d, ADDR); settle(800);
      check(from5[d] == d0 + 1, $sformatf("QG_RAW_TO_%0d delivered=+%0d", d, from5[d] - d0));
    end
    // ---- G (NI ports)
    begin
      automatic logic [31:0] c0 = memory_commits; automatic int r0 = rd_resp3, g0, n = 0;
      app_hdr(3, tile_to_coord(TILE_MEMORY), MSG_MEM_WR_REQ, 11'h780, ok); w[0] = ADDR; w[1] = 32'h600D_0003; app_words(3, w, 2, ok2);
      n = 0; while (memory_commits == c0 && n < 5000) begin @(negedge clk); n++; end
      check(ok && ok2 && memory_commits == c0 + 1 && memory_last_data == 32'h600D_0003, $sformatf("QG_NI3_WRITE commits=+%0d", memory_commits - c0));
      app_hdr(3, tile_to_coord(TILE_MEMORY), MSG_MEM_RD_REQ, 11'h000, ok); w[0] = ADDR; app_words(3, w, 1, ok2);
      n = 0; while (rd_resp3 == r0 && n < 5000) begin @(negedge clk); n++; end
      check(rd_resp3 == r0 + 1, $sformatf("QG_NI2_REPLY rd_resp=+%0d", rd_resp3 - r0));
      g0 = grants; load_chain(1); pulse_start();
      n = 0; while (grants == g0 && n < 60000) begin @(negedge clk); n++; end
      check(grants == g0 + 1 && !attestation_failed, $sformatf("QG_NI4_ATTEST grants=+%0d", grants - g0));
    end
    // ---- E: missing final write-data flit
    begin
      automatic logic [31:0] dsc = q_discarded, c0 = memory_commits; automatic int t2 = from5[2];
      raw(hf(5, 2, MSG_MEM_WR_REQ, 3, FLIT_HEAD, VC0)); raw(bf(ADDR, FLIT_BODY, VC0)); raw_idle(); settle(300);
      check(q_discarded == dsc + 1 && q_reason == 4'd10, $sformatf("QE_DISCARDED discarded=+%0d reason=%0d", q_discarded - dsc, q_reason));
      check(from5[2] == t2 && memory_commits == c0, $sformatf("QE_NO_COMMIT heads_at_2=+%0d commits=+%0d", from5[2] - t2, memory_commits - c0));
    end
    // ---- F: gap counter on the standalone quarantine
    begin
      automatic int g1, g2;
      @(negedge clk); uq_in = hf(5, 0, MSG_MEM_WR_REQ, 3, FLIT_HEAD, VC0); uq_iv = 1; @(negedge clk); uq_iv = 0;   // HEAD only: packet open
      repeat (5) @(negedge clk); g1 = u_q.gap;
      @(negedge clk); uq_in = bf(ADDR, FLIT_BODY, VC0); uq_iv = 1; @(posedge clk); #1; g2 = u_q.gap; @(negedge clk); uq_iv = 0;   // accepted; TAIL still due
      check(g1 == 5 && g2 == 0, $sformatf("QGAP_V1R1 gap_before=%0d after_accept=%0d", g1, g2));
      repeat (3) @(negedge clk); g1 = u_q.gap; repeat (4) @(negedge clk); g2 = u_q.gap;
      check(g2 == g1 + 4, $sformatf("QGAP_V0R1 gap %0d -> %0d over 4 idle cycles", g1, g2));
      // fill the FIFO (output blocked) so that in_ready = 0 with a partial packet open
      do_reset(); uq_or = 0;
      for (int p = 0; p < 15; p++) begin
        @(negedge clk); uq_in = hf(5, 0, MSG_MEM_RD_REQ, 2, FLIT_HEAD, VC0); uq_iv = 1; @(negedge clk); uq_in = bf(ADDR, FLIT_TAIL, VC0); @(negedge clk);
      end
      uq_in = hf(5, 0, MSG_MEM_WR_REQ, 3, FLIT_HEAD, VC0); @(negedge clk);          // 31 flits: HEAD of a partial packet (length 3)
      uq_in = bf(ADDR, FLIT_BODY, VC0); @(negedge clk);                             // 32: the FIFO is full, the packet still open
      uq_in = bf(32'h1, FLIT_TAIL, VC0);                                            // the TAIL is presented and held (in_ready = 0)
      repeat (2) @(negedge clk); g1 = u_q.gap; repeat (6) @(negedge clk); g2 = u_q.gap;
      check(!uq_ir && g2 == g1, $sformatf("QGAP_V1R0 in_ready=%b gap %0d -> %0d", uq_ir, g1, g2));
      uq_iv = 0; g1 = u_q.gap; repeat (6) @(negedge clk); g2 = u_q.gap;
      check(!uq_ir && g2 == g1, $sformatf("QGAP_V0R0 in_ready=%b gap %0d -> %0d", uq_ir, g1, g2));
      uq_or = 1;
    end
    // ---- H: standalone NI-port parser (port 1)
    begin
      automatic logic [31:0] r0 = up_rej; automatic int f0 = up_fwd;
      @(negedge clk); up_in = hf(4, 0, MSG_MEM_RD_REQ, 2, FLIT_HEAD, VC0); up_iv = 1; @(negedge clk); up_in = bf(ADDR, FLIT_TAIL, VC0); @(negedge clk); up_iv = 0;
      repeat (3) @(negedge clk);
      check(up_rej == r0 + 1 && up_rsn == 4'd9 && up_fwd == f0, $sformatf("QP_FORGED rej=+%0d reason=%0d forwarded=%0d", up_rej - r0, up_rsn, up_fwd - f0));
      f0 = up_fwd;
      @(negedge clk); up_in = hf(1, 0, MSG_MEM_RD_REQ, 2, FLIT_HEAD, VC0); up_iv = 1; @(negedge clk); up_in = bf(ADDR, FLIT_TAIL, VC0); @(negedge clk); up_iv = 0;
      repeat (3) @(negedge clk);
      check(up_fwd == f0 + 2, $sformatf("QP_LEGAL forwarded=%0d", up_fwd - f0));
    end
    // ---- D (last): withheld TAIL while the RoT revokes
    do_reset(); attest_ok(0);
    begin
      automatic int n = 0, m0 = mesh5_flits;
      raw(hf(5, 3, MSG_MEM_WR_REQ, 3, FLIT_HEAD, VC0)); raw(bf(ADDR, FLIT_BODY, VC0)); raw_idle();   // the TAIL is withheld
      @(negedge clk); revoke = 1; @(negedge clk); revoke = 0;
      while (authorized[3] && n < 10000) begin @(negedge clk); n++; end
      check(!authorized[3] && n < E2E_REVOKE, $sformatf("QW_REVOKE_DELIVERED %0d cycles (bound %0d)", n, E2E_REVOKE));
      repeat (10000 - n) @(negedge clk);
      check(q_reason == 4'd10, $sformatf("QW_REASON10 reason=%0d", q_reason));
      check(mesh5_flits == m0, $sformatf("QW_NO_ROUTE_HOLD partial-packet flits in the mesh=%0d", mesh5_flits - m0));
    end
`endif
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #40ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
