`timescale 1ns / 1ps
// tb_app_port_checker -- bench for sim_riscv/app_port_checker.sv (brief v2 B5). Scratch-level until Lane 1 registers it
// (counts frozen here before the first run).
// Part A (clean): app_port_checker is BOUND into rtl/riscv/tmem_app_bridge (BRIDGE_TIMEOUT 64, LATE_DRAIN 400) and the
//   bridge carries 400 random TMEM requests through a simple tile-2 front-end model with random HEAD / payload
//   backpressure and per-request modes: normal, no response (timeout + drain), HEAD ready held low (timeout withdrawal),
//   payload ready held low (timeout in the payload phase), late response (dropped while draining), app_tx_error during
//   the payload, unauthorized (refused locally), bad tile (refused locally). The checker must report 0 violations.
// Part B (negative): a second, stand-alone checker instance is driven directly; one injected violation per case; the
//   matching counter must rise and every other counter must stay unchanged.
// Checks (CHECKS = 10, frozen before the first run):
//   B5_CLEAN_ZERO_VIOLATIONS  part A: all 7 checker counters 0
//   B5_CLEAN_COVERAGE         part A exercised every mode at least once, TMEM responses == grants, bound checker saw the
//                             bridge's HEADs (its handshake count == the model's)
//   B5_NEG_HEAD_STABLE        message changes while app_valid is held without app_ready
//   B5_NEG_HEAD_WITHDRAW      app_valid dropped without app_ready, authorized = 1, long before the timeout
//   B5_NEG_PAYLOAD_STABLE     app_payload changes while app_payload_valid is held without app_payload_ready
//   B5_NEG_VALID_UNAUTH       app_valid while authorized = 0
//   B5_NEG_ONE_OUTSTANDING    a second HEAD while the first request has no response yet
//   B5_NEG_PAYLOAD_COUNT      a write with one payload word, then the response HEAD
//   B5_NEG_MSG_LEGAL          app_valid with app_message 4
//   B5_NEG_DEST_LEGAL         app_valid with the tile's own coordinate as destination
module tb_app_port_checker;
  import noc_pkg::*;
  localparam int TO = 64, DRAIN = 400;
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;

  // ------------------------------------------------------------------ part A: bridge + bound checker
  logic tmem_req = 0, tmem_we = 0, tmem_gnt, tmem_rvalid, tmem_err;
  logic [31:0] tmem_addr = 0, tmem_wdata = 0, tmem_rdata;
  logic [3:0]  tmem_wstrb = 0;
  logic authorized = 1;
  logic app_valid, app_ready = 0, app_pvalid, app_pready = 0, app_tx_error = 0;
  coord_t app_dest; msg_type_e app_msg; logic [10:0] app_ctl; logic [31:0] app_payload;
  logic rx_hv = 0, rx_dv = 0, rx_last = 0, rx_abort = 0;
  coord_t rx_src = '0; msg_type_e rx_msg = msg_type_e'(0); logic [10:0] rx_ctl = 0; logic [31:0] rx_data = 0;
  logic [2:0] lek; logic [15:0] tc, rc;

  tmem_app_bridge #(.TILE_ID(3), .MEM_TILE(2), .BRIDGE_TIMEOUT(TO), .NI_SLOT_TIMEOUT(DRAIN), .LATE_DRAIN_CYCLES(DRAIN)) dut (
    .clk, .rst, .tmem_req_i(tmem_req), .tmem_we_i(tmem_we), .tmem_addr_i(tmem_addr), .tmem_wdata_i(tmem_wdata),
    .tmem_wstrb_i(tmem_wstrb), .tmem_is_fetch_i(1'b0), .tmem_gnt_o(tmem_gnt), .tmem_rvalid_o(tmem_rvalid),
    .tmem_rdata_o(tmem_rdata), .tmem_err_o(tmem_err), .authorized_i(authorized),
    .app_valid_o(app_valid), .app_ready_i(app_ready), .app_destination_o(app_dest), .app_message_o(app_msg),
    .app_control_o(app_ctl), .app_payload_o(app_payload), .app_payload_valid_o(app_pvalid), .app_payload_ready_i(app_pready),
    .app_tx_error_i(app_tx_error), .app_rx_head_valid_i(rx_hv), .app_rx_src_i(rx_src), .app_rx_msg_i(rx_msg),
    .app_rx_control_i(rx_ctl), .app_rx_data_i(rx_data), .app_rx_data_valid_i(rx_dv), .app_rx_last_i(rx_last),
    .app_rx_abort_i(rx_abort), .last_err_kind_o(lek), .timeout_count_o(tc), .refused_count_o(rc));

  bind tmem_app_bridge app_port_checker #(.SELF_TILE(TILE_ID), .TIMEOUT_CYCLES(BRIDGE_TIMEOUT),
                                          .RELEASE_CYCLES(LATE_DRAIN_CYCLES)) u_b5 (
    .clk, .rst, .authorized(authorized_i), .app_valid(app_valid_o), .app_ready(app_ready_i),
    .app_destination(app_destination_o), .app_message(app_message_o), .app_control(app_control_o),
    .app_payload(app_payload_o), .app_payload_valid(app_payload_valid_o), .app_payload_ready(app_payload_ready_i),
    .app_tx_error(app_tx_error_i), .app_rx_head_valid(app_rx_head_valid_i), .app_rx_last(app_rx_last_i),
    .app_rx_abort(app_rx_abort_i));

  // front-end model
  typedef enum int {M_NORMAL, M_NO_RESP, M_READY_LOW, M_PREADY_LOW, M_LATE, M_TXERR, M_UNAUTH, M_BADTILE} mode_e;
  mode_e mode = M_NORMAL;
  int mode_seen [8];
  logic [31:0] mem [0:4095];
  int heads = 0, grants = 0, responses = 0;
  logic        cur_we; logic [31:0] cur_addr, cur_wd; logic [3:0] cur_ws; int words = 0;
  bit  in_payload = 0;
  bit  app_tx_error_done = 0;

  always @(posedge clk) begin
    if (!rst && tmem_gnt) grants++;
    if (!rst && tmem_rvalid) responses++;
  end
  // HEAD and payload ready (random backpressure; held low in the *_LOW modes)
  always @(negedge clk) begin
    app_ready  = (mode == M_READY_LOW) ? 1'b0 : ($urandom % 3 != 0);
    app_pready = (mode == M_PREADY_LOW) ? 1'b0 : ($urandom % 3 != 0);
  end
  always @(posedge clk) begin
    if (!rst && app_valid && app_ready) begin
      heads++; cur_we = (app_msg == MSG_MEM_WR_REQ); cur_ws = app_ctl[10:7]; words = 0; in_payload = 1;
    end
    if (!rst && app_pvalid && app_pready && in_payload) begin
      if (words == 0) cur_addr = app_payload; else cur_wd = app_payload;
      words++;
      if (words == (cur_we ? 2 : 1)) begin
        in_payload = 0;
        if (mode != M_NO_RESP && mode != M_TXERR) fork respond(cur_we, cur_addr, cur_wd, cur_ws, mode); join_none
      end
    end
  end
  // app_tx_error during the payload phase (once per M_TXERR request)
  always @(negedge clk) begin
    app_tx_error = 0;
    if (mode == M_TXERR && app_pvalid && !app_tx_error_done) begin app_tx_error = 1; app_tx_error_done = 1; end
  end

  task automatic respond(input logic we, input logic [31:0] a, input logic [31:0] wd, input logic [3:0] ws, input mode_e m);
    automatic int lat = (m == M_LATE) ? TO + 5 : 1 + $urandom % 20;
    automatic logic [11:0] w = a[13:2];
    repeat (lat) @(negedge clk);
    if (we) for (int b = 0; b < 4; b++) if (ws[b]) mem[w][b*8 +: 8] = wd[b*8 +: 8];
    rx_src = tile_to_coord(TILE_MEMORY); rx_msg = we ? MSG_MEM_WR_RESP : MSG_MEM_RD_RESP; rx_ctl = '0; rx_hv = 1;
    @(negedge clk); rx_hv = 0;
    if (!we) begin rx_data = mem[w]; rx_dv = 1; @(negedge clk); rx_dv = 0; end
    rx_last = 1; @(negedge clk); rx_last = 0;
  endtask

  task automatic xact(input logic we, input logic [31:0] a, input logic [31:0] wd, input logic [3:0] ws);
    automatic int n = 0;
    @(negedge clk); tmem_req = 1; tmem_we = we; tmem_addr = a; tmem_wdata = wd; tmem_wstrb = ws;
    do begin @(posedge clk); n++; end while (!tmem_gnt && n < 4000);
    @(negedge clk); tmem_req = 0;
    n = 0;
    do begin @(posedge clk); n++; end while (!tmem_rvalid && n < 4000);
  endtask

  // ------------------------------------------------------------------ part B: stand-alone checker, directed
  logic n_rst = 1, n_auth = 1, n_v = 0, n_r = 0, n_pv = 0, n_pr = 0, n_txe = 0, n_hv = 0, n_last = 0, n_abort = 0;
  coord_t n_dest; msg_type_e n_msg = MSG_MEM_RD_REQ; logic [10:0] n_ctl = 0; logic [31:0] n_p = 0;
  app_port_checker #(.SELF_TILE(3), .TIMEOUT_CYCLES(TO), .RELEASE_CYCLES(DRAIN), .REPORT(1'b0)) neg (
    .clk, .rst(n_rst), .authorized(n_auth), .app_valid(n_v), .app_ready(n_r), .app_destination(n_dest),
    .app_message(n_msg), .app_control(n_ctl), .app_payload(n_p), .app_payload_valid(n_pv), .app_payload_ready(n_pr),
    .app_tx_error(n_txe), .app_rx_head_valid(n_hv), .app_rx_last(n_last), .app_rx_abort(n_abort));
  initial n_dest = tile_to_coord(TILE_MEMORY);

  function automatic void snap(output int s [7]);
    s[0] = neg.n_head_stable; s[1] = neg.n_payload_stable; s[2] = neg.n_valid_unauth; s[3] = neg.n_one_outstanding;
    s[4] = neg.n_payload_count; s[5] = neg.n_msg_legal; s[6] = neg.n_dest_legal;
  endfunction
  // only counter `idx` rose (by at least 1), all others unchanged
  function automatic bit only(input int a [7], input int b [7], input int idx, output string d);
    bit ok = 1; d = "";
    for (int i = 0; i < 7; i++) begin
      d = {d, $sformatf("%0d ", b[i] - a[i])};
      if (i == idx ? (b[i] <= a[i]) : (b[i] != a[i])) ok = 0;
    end
    return ok;
  endfunction
  task automatic n_idle();   // all inputs idle, then a checker reset (counters are kept)
    @(negedge clk); n_v = 0; n_r = 0; n_pv = 0; n_pr = 0; n_txe = 0; n_hv = 0; n_last = 0; n_abort = 0; n_auth = 1;
    n_msg = MSG_MEM_RD_REQ; n_ctl = 0; n_p = 0; n_dest = tile_to_coord(TILE_MEMORY);
    n_rst = 1; repeat (2) @(negedge clk); n_rst = 0; repeat (2) @(negedge clk);
  endtask

  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask

  initial begin
    int a [7], b [7]; string d; bit ok;
    $display("CONFIG: TOP=tb_app_port_checker CHECKS=10 BRIDGE_TIMEOUT=%0d LATE_DRAIN=%0d", TO, DRAIN);
    for (int i = 0; i < 4096; i++) mem[i] = 32'h0;
    for (int i = 0; i < 8; i++) mode_seen[i] = 0;
    repeat (5) @(negedge clk); rst = 0; n_rst = 0; repeat (3) @(negedge clk);

    // ---------------- part A
    for (int i = 0; i < 400; i++) begin
      automatic int r = $urandom % 100;
      automatic mode_e m = (i < 8) ? mode_e'(i) :                    // every mode once first
                           (r < 70) ? M_NORMAL : (r < 74) ? M_NO_RESP : (r < 78) ? M_READY_LOW : (r < 82) ? M_PREADY_LOW :
                           (r < 86) ? M_LATE : (r < 90) ? M_TXERR : (r < 95) ? M_UNAUTH : M_BADTILE;
      automatic logic we = $urandom % 2;
      automatic logic [3:0] t = (m == M_BADTILE) ? 4'd5 : 4'd2;
      mode = m; mode_seen[m]++; app_tx_error_done = 0;
      authorized = (m != M_UNAUTH);
      xact(we, {4'h2, t, 12'h000, 10'($urandom % 1024), 2'b00}, $urandom, 4'($urandom));
      authorized = 1;
      // no extra idle time after a timeout: the next request follows at once, so a sender without the late-response
      // drain re-issues while the timed-out request is still open (B5_ONE_OUTSTANDING); the real bridge's drain holds it
      mode = M_NORMAL;
      repeat (3) @(negedge clk);
    end
    repeat (100) @(negedge clk);
    check(dut.u_b5.total() == 0,
          $sformatf("B5_CLEAN_ZERO_VIOLATIONS total=%0d (head %0d payload %0d unauth %0d outstanding %0d count %0d msg %0d dest %0d)",
                    dut.u_b5.total(), dut.u_b5.n_head_stable, dut.u_b5.n_payload_stable, dut.u_b5.n_valid_unauth,
                    dut.u_b5.n_one_outstanding, dut.u_b5.n_payload_count, dut.u_b5.n_msg_legal, dut.u_b5.n_dest_legal));
    ok = (responses == grants) && (grants == 400) && heads > 0;
    for (int i = 0; i < 8; i++) if (mode_seen[i] == 0) ok = 0;
    check(ok, $sformatf("B5_CLEAN_COVERAGE grants=%0d responses=%0d heads=%0d modes=%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d timeouts=%0d refused=%0d",
                        grants, responses, heads, mode_seen[0], mode_seen[1], mode_seen[2], mode_seen[3], mode_seen[4],
                        mode_seen[5], mode_seen[6], mode_seen[7], tc, rc));

    // ---------------- part B
    n_idle();
    // HEAD fields change while held
    snap(a); n_v = 1; n_r = 0; n_msg = MSG_MEM_RD_REQ; @(negedge clk); n_msg = MSG_MEM_WR_REQ; @(negedge clk);
    n_r = 1; @(negedge clk); n_v = 0; n_r = 0; n_idle(); snap(b);
    ok = only(a, b, 0, d); check(ok, {"B5_NEG_HEAD_STABLE deltas=", d});
    // HEAD withdrawn early
    snap(a); n_v = 1; n_r = 0; repeat (5) @(negedge clk); n_v = 0; repeat (3) @(negedge clk); n_idle(); snap(b);
    ok = only(a, b, 0, d); check(ok, {"B5_NEG_HEAD_WITHDRAW deltas=", d});
    // payload changes while held
    snap(a); n_v = 1; n_r = 1; @(negedge clk); n_v = 0; n_r = 0;
    n_pv = 1; n_pr = 0; n_p = 32'h2200_0100; @(negedge clk); n_p = 32'h2200_0104; @(negedge clk); n_pr = 1; @(negedge clk);
    n_pv = 0; n_pr = 0; repeat (2) @(negedge clk); n_hv = 1; @(negedge clk); n_hv = 0; n_last = 1; @(negedge clk); n_last = 0;
    n_idle(); snap(b);
    ok = only(a, b, 1, d); check(ok, {"B5_NEG_PAYLOAD_STABLE deltas=", d});
    // valid while unauthorized (ready low; the HEAD then drops with authorized = 0, which is allowed)
    snap(a); n_auth = 0; n_v = 1; n_r = 0; @(negedge clk); n_v = 0; @(negedge clk); n_auth = 1; n_idle(); snap(b);
    ok = only(a, b, 2, d); check(ok, {"B5_NEG_VALID_UNAUTH deltas=", d});
    // second HEAD while the first is outstanding
    snap(a); n_v = 1; n_r = 1; @(negedge clk); n_v = 0; n_r = 0;
    n_pv = 1; n_pr = 1; @(negedge clk); n_pv = 0; n_pr = 0; repeat (3) @(negedge clk);
    n_v = 1; n_r = 1; @(negedge clk); n_v = 0; n_r = 0; n_pv = 1; n_pr = 1; @(negedge clk); n_pv = 0; n_pr = 0;
    n_idle(); snap(b);
    ok = only(a, b, 3, d); check(ok, {"B5_NEG_ONE_OUTSTANDING deltas=", d});
    // write with one payload word, then the response
    snap(a); n_msg = MSG_MEM_WR_REQ; n_ctl = {4'hF, 6'b0, 1'b0}; n_v = 1; n_r = 1; @(negedge clk); n_v = 0; n_r = 0;
    n_pv = 1; n_pr = 1; @(negedge clk); n_pv = 0; n_pr = 0; repeat (3) @(negedge clk);
    n_hv = 1; @(negedge clk); n_hv = 0; n_last = 1; @(negedge clk); n_last = 0; n_idle(); snap(b);
    ok = only(a, b, 4, d); check(ok, {"B5_NEG_PAYLOAD_COUNT deltas=", d});
    // illegal message type
    snap(a); n_msg = msg_type_e'(4); n_v = 1; n_r = 1; @(negedge clk); n_v = 0; n_r = 0;
    n_pv = 1; n_pr = 1; @(negedge clk); n_pv = 0; n_pr = 0; repeat (2) @(negedge clk);
    n_hv = 1; @(negedge clk); n_hv = 0; n_last = 1; @(negedge clk); n_last = 0; n_idle(); snap(b);
    ok = only(a, b, 5, d); check(ok, {"B5_NEG_MSG_LEGAL deltas=", d});
    // destination = self
    snap(a); n_dest = tile_to_coord(TILE_CRYPTO); n_v = 1; n_r = 1; @(negedge clk); n_v = 0; n_r = 0;
    n_pv = 1; n_pr = 1; @(negedge clk); n_pv = 0; n_pr = 0; repeat (2) @(negedge clk);
    n_hv = 1; @(negedge clk); n_hv = 0; n_last = 1; @(negedge clk); n_last = 0; n_idle(); snap(b);
    ok = only(a, b, 6, d); check(ok, {"B5_NEG_DEST_LEGAL deltas=", d});

    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 10 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #50ms; $display("TB_TIMEOUT global"); $display("RESULT : FAIL"); $finish; end
endmodule
