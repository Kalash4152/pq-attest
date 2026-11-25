`timescale 1ns / 1ps
// tb_tmem_app_bridge -- unit bench for rtl/riscv/tmem_app_bridge.sv (brief v2 B1, task R2.1). Scratch-level until Lane 1
// registers it (counts frozen here before the first run).
// DUT parameters: TILE_ID 3, MEM_TILE 2, BRIDGE_TIMEOUT 64, LATE_DRAIN_CYCLES 400 (short for simulation; same logic as 4096 / 8192).
// The TMEM driver mimics picorv32_adapter (req held until gnt, then waits for rvalid); the app-port model mimics the
// subsystem's tile-2 front end (random HEAD / payload backpressure, byte-lane memory, 16 KB window, HEAD -> data -> terminator).
// Checks (CHECKS = 19, frozen before the first run; was 18 until B1_FETCH_REFUSED was added on the main session's
// decision of 2026-11-06, frozen before the first run with it):
//   B1_WRITE_OK          write completes without error and the model memory holds the word
//   B1_READ_OK           read returns the written word
//   B1_BYTE_LANES        wstrb 4'b0101 changes only bytes 0 and 2 (read back)
//   B1_HEAD_FORMAT       write: destination tile 2, MSG_MEM_WR_REQ, control = {wstrb,6'b0,1'b0}, word0 = {4'h2, addr[27:2], 2'b00}, word1 = data
//   B1_READ_FORMAT       read: MSG_MEM_RD_REQ, control 0, exactly one payload word with the prefixed address
//   B1_REFUSED_UNAUTH    authorized = 0: tmem_err within 2 cycles of the grant, no network HEAD
//   B1_DECODE_T0 / T6 / T15 / SELF   bad tile selector: tmem_err within 2 cycles, no network HEAD          (4)
//   B1_FETCH_REFUSED     tmem_is_fetch = 1 to a valid tile-2 address: tmem_err within 2 cycles, data 0, no network HEAD
//   B1_ERR_RESPONSE      out-of-window read: response control[10] = 1 -> tmem_err, read data 0
//   B1_ABORT             app_rx_abort -> tmem_err
//   B1_TIMEOUT_NO_RESPONSE  no response: tmem_err no earlier than BRIDGE_TIMEOUT cycles
//   B1_READY_HELD_LOW    app_ready never comes: tmem_err after the timeout, no HEAD accepted
//   B1_LATE_RESPONSE_IGNORED  a response arriving after the timeout is never delivered; the next read returns its own data
//   B1_RANDOM_1000       1,000 random requests (reads / writes / bad tiles / unauthorized / out-of-window, random delays):
//                        every response matches the shadow model
//   B1_COUNTS            whole run: network HEADs == requests that should reach the network; TMEM responses == grants
//   B1_NO_VALID_WHILE_UNAUTH  whole run: app_valid never high while authorized = 0
module tb_tmem_app_bridge;
  import noc_pkg::*;
  localparam int TO = 64, DRAIN = 400, WIN_BYTES = 16'h4000;
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;

  // TMEM
  logic tmem_req = 0, tmem_we = 0, tmem_is_fetch = 0, tmem_gnt, tmem_rvalid, tmem_err;
  logic [31:0] tmem_addr = 0, tmem_wdata = 0, tmem_rdata;
  logic [3:0]  tmem_wstrb = 0;
  logic authorized = 1;
  // app port
  logic app_valid, app_ready = 0, app_pvalid, app_pready = 0, app_tx_error = 0;
  coord_t app_dest; msg_type_e app_msg; logic [10:0] app_ctl; logic [31:0] app_payload;
  logic rx_hv = 0, rx_dv = 0, rx_last = 0, rx_abort = 0;
  coord_t rx_src = '0; msg_type_e rx_msg = msg_type_e'(0); logic [10:0] rx_ctl = 0; logic [31:0] rx_data = 0;
  logic [2:0] last_err_kind; logic [15:0] tmo_cnt, ref_cnt;

  tmem_app_bridge #(.TILE_ID(3), .MEM_TILE(2), .BRIDGE_TIMEOUT(TO), .NI_SLOT_TIMEOUT(DRAIN), .LATE_DRAIN_CYCLES(DRAIN)) dut (
    .clk, .rst, .tmem_req_i(tmem_req), .tmem_we_i(tmem_we), .tmem_addr_i(tmem_addr), .tmem_wdata_i(tmem_wdata),
    .tmem_wstrb_i(tmem_wstrb), .tmem_is_fetch_i(tmem_is_fetch), .tmem_gnt_o(tmem_gnt), .tmem_rvalid_o(tmem_rvalid),
    .tmem_rdata_o(tmem_rdata), .tmem_err_o(tmem_err), .authorized_i(authorized),
    .app_valid_o(app_valid), .app_ready_i(app_ready), .app_destination_o(app_dest), .app_message_o(app_msg),
    .app_control_o(app_ctl), .app_payload_o(app_payload), .app_payload_valid_o(app_pvalid), .app_payload_ready_i(app_pready),
    .app_tx_error_i(app_tx_error), .app_rx_head_valid_i(rx_hv), .app_rx_src_i(rx_src), .app_rx_msg_i(rx_msg),
    .app_rx_control_i(rx_ctl), .app_rx_data_i(rx_data), .app_rx_data_valid_i(rx_dv), .app_rx_last_i(rx_last),
    .app_rx_abort_i(rx_abort), .last_err_kind_o(last_err_kind), .timeout_count_o(tmo_cnt), .refused_count_o(ref_cnt));

  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++; if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask

  // ------------------------------------------------------------------ model of the subsystem side
  typedef enum int {M_NORMAL, M_NO_RESP, M_READY_LOW, M_ERR, M_ABORT, M_LATE} mode_e;
  mode_e mode = M_NORMAL;
  int    resp_lat = -1;                         // -1 = random 1..20
  int    late_delay = TO + 20;
  logic [31:0] mem [0:4095];
  int net_heads = 0, grants = 0, responses = 0, valid_unauth = 0;
  // last captured packet (for format checks)
  coord_t pk_dest; msg_type_e pk_msg; logic [10:0] pk_ctl; logic [31:0] pk_w0, pk_w1; int pk_words;

  always @(posedge clk) if (!rst) begin
    if (tmem_gnt) grants++;
    if (tmem_rvalid) responses++;
    if (app_valid && !authorized) valid_unauth++;
  end
  // random HEAD / payload backpressure
  always @(negedge clk) begin
    app_ready  <= (mode != M_READY_LOW) && app_valid && ($urandom % 3 != 0);
    app_pready <= ($urandom % 2 == 0);
  end

  task automatic send_resp(input msg_type_e m, input logic err, input logic is_rd, input logic [31:0] d, input logic abort);
    @(negedge clk); rx_hv = 1; rx_src = tile_to_coord(TILE_MEMORY); rx_msg = m; rx_ctl = err ? 11'h400 : 11'h000;
    @(negedge clk); rx_hv = 0;
    if (abort) begin rx_abort = 1; @(negedge clk); rx_abort = 0; return; end
    if (is_rd && !err) begin rx_dv = 1; rx_data = d; @(negedge clk); rx_dv = 0; end
    rx_last = 1; @(negedge clk); rx_last = 0;
  endtask

  initial forever begin : receiver
    @(posedge clk);
    if (!rst && app_valid && app_ready) begin
      automatic coord_t d = app_dest; automatic msg_type_e m = app_msg; automatic logic [10:0] c = app_ctl;
      automatic int need = (m == MSG_MEM_WR_REQ) ? 2 : 1, got = 0;
      automatic logic [31:0] w [2];
      automatic mode_e md = mode; automatic int lat = resp_lat, ld = late_delay;
      net_heads++;
      while (got < need) begin
        @(posedge clk);
        if (app_pvalid && app_pready) begin w[got] = app_payload; got++; end
      end
      pk_dest = d; pk_msg = m; pk_ctl = c; pk_w0 = w[0]; pk_w1 = (need == 2) ? w[1] : 32'hx; pk_words = need;
      fork begin
        automatic logic [23:0] off = w[0][23:0];
        automatic logic oob = (off >= WIN_BYTES) || (w[0][1:0] != 0);
        automatic logic is_rd = (m == MSG_MEM_RD_REQ);
        automatic msg_type_e rm = is_rd ? MSG_MEM_RD_RESP : MSG_MEM_WR_RESP;
        automatic logic err = oob || (md == M_ERR);
        if (!is_rd && !err) for (int b = 0; b < 4; b++) if (c[7 + b]) mem[off[13:2]][b*8 +: 8] = w[1][b*8 +: 8];
        case (md)
          M_NO_RESP: ;
          M_LATE:    begin repeat (ld) @(negedge clk); send_resp(rm, err, is_rd, err ? 32'h0 : mem[off[13:2]], 1'b0); end
          default:   begin repeat ((lat < 0) ? (1 + $urandom % 20) : lat) @(negedge clk);
                           send_resp(rm, err, is_rd, err ? 32'h0 : mem[off[13:2]], md == M_ABORT); end
        endcase
      end join_none
    end
  end

  // ------------------------------------------------------------------ TMEM driver (adapter-like)
  int expected_net = 0;
  task automatic xact(input logic we, input logic [31:0] a, input logic [31:0] wd, input logic [3:0] ws,
                      output logic err, output logic [31:0] rd, output int cyc, output logic ok);
    automatic int n = 0;
    @(negedge clk); tmem_req = 1; tmem_we = we; tmem_addr = a; tmem_wdata = wd; tmem_wstrb = ws;
    do begin @(posedge clk); n++; end while (!tmem_gnt && n < 4 * (TO + DRAIN));
    ok = tmem_gnt; @(negedge clk); tmem_req = 0;
    cyc = 0; err = 1'b1; rd = 32'hx;
    if (!ok) return;
    do begin @(posedge clk); cyc++; end while (!tmem_rvalid && cyc < 4 * (TO + DRAIN));
    if (!tmem_rvalid) begin ok = 0; return; end
    err = tmem_err; rd = tmem_rdata;
  endtask
  function automatic logic [31:0] A(input logic [3:0] t, input logic [23:0] off); return {4'h2, t, off}; endfunction

  // shadow model for the random test
  logic [31:0] shadow [0:4095];

  initial begin
    logic e, ok; logic [31:0] d; int c, h0, r0; static int bad = 0;
    $display("CONFIG: TOP=tb_tmem_app_bridge CHECKS=19 BRIDGE_TIMEOUT=%0d LATE_DRAIN=%0d", TO, DRAIN);
    for (int i = 0; i < 4096; i++) begin mem[i] = 32'h0; shadow[i] = 32'h0; end
    repeat (5) @(negedge clk); rst = 0; repeat (3) @(negedge clk);

    // write / read / format
    mode = M_NORMAL; resp_lat = -1;
    xact(1, A(2, 24'h100), 32'hCAFE_0001, 4'hF, e, d, c, ok); expected_net++;
    check(ok && !e && mem[24'h100 >> 2] == 32'hCAFE_0001, $sformatf("B1_WRITE_OK err=%0b mem=%h", e, mem[24'h100 >> 2]));
    check(pk_dest == tile_to_coord(TILE_MEMORY) && pk_msg == MSG_MEM_WR_REQ && pk_ctl == {4'hF, 6'b0, 1'b0} &&
          pk_w0 == 32'h2200_0100 && pk_w1 == 32'hCAFE_0001 && pk_words == 2,
          $sformatf("B1_HEAD_FORMAT msg=%0d ctl=%h w0=%h w1=%h", pk_msg, pk_ctl, pk_w0, pk_w1));
    xact(0, A(2, 24'h100), 0, 0, e, d, c, ok); expected_net++;
    check(ok && !e && d == 32'hCAFE_0001, $sformatf("B1_READ_OK err=%0b data=%h", e, d));
    check(pk_msg == MSG_MEM_RD_REQ && pk_ctl == 11'h000 && pk_w0 == 32'h2200_0100 && pk_words == 1,
          $sformatf("B1_READ_FORMAT msg=%0d ctl=%h w0=%h words=%0d", pk_msg, pk_ctl, pk_w0, pk_words));
    xact(1, A(2, 24'h100), 32'h1122_3344, 4'b0101, e, d, c, ok); expected_net++;
    xact(0, A(2, 24'h100), 0, 0, e, d, c, ok); expected_net++;
    check(ok && !e && d == 32'hCA22_0044, $sformatf("B1_BYTE_LANES data=%h (expected ca220044)", d));

    // local refusals: no network traffic, error within 2 cycles
    h0 = net_heads; authorized = 0;
    xact(1, A(2, 24'h200), 32'hDEAD_BEEF, 4'hF, e, d, c, ok);
    check(ok && e && c <= 2 && net_heads == h0 && mem[24'h200 >> 2] == 0, $sformatf("B1_REFUSED_UNAUTH err=%0b cycles=%0d heads=+%0d", e, c, net_heads - h0));
    authorized = 1;
    for (int k = 0; k < 4; k++) begin
      automatic logic [3:0] t = (k == 0) ? 4'd0 : (k == 1) ? 4'd6 : (k == 2) ? 4'd15 : 4'd3;
      automatic string nm = (k == 0) ? "T0" : (k == 1) ? "T6" : (k == 2) ? "T15" : "SELF";
      h0 = net_heads;
      xact(0, A(t, 24'h100), 0, 0, e, d, c, ok);
      check(ok && e && c <= 2 && net_heads == h0 && d == 0, $sformatf("B1_DECODE_%s err=%0b cycles=%0d heads=+%0d", nm, e, c, net_heads - h0));
    end
    // remote instruction fetch to an otherwise valid tile-2 address: refused locally
    h0 = net_heads; tmem_is_fetch = 1;
    xact(0, A(2, 24'h100), 0, 0, e, d, c, ok);
    tmem_is_fetch = 0;
    check(ok && e && c <= 2 && net_heads == h0 && d == 0, $sformatf("B1_FETCH_REFUSED err=%0b cycles=%0d heads=+%0d data=%h", e, c, net_heads - h0, d));

    // remote error, abort
    xact(0, A(2, 24'h4000), 0, 0, e, d, c, ok); expected_net++;
    check(ok && e && d == 0, $sformatf("B1_ERR_RESPONSE err=%0b data=%h", e, d));
    mode = M_ABORT;
    xact(0, A(2, 24'h100), 0, 0, e, d, c, ok); expected_net++;
    check(ok && e && d == 0, $sformatf("B1_ABORT err=%0b data=%h", e, d));

    // timeout with no response, then the drain window passes
    mode = M_NO_RESP;
    xact(0, A(2, 24'h100), 0, 0, e, d, c, ok); expected_net++;
    check(ok && e && c >= TO && c <= TO + 30, $sformatf("B1_TIMEOUT_NO_RESPONSE err=%0b cycles=%0d", e, c));
    // ready held low: no HEAD accepted
    mode = M_READY_LOW; h0 = net_heads;
    xact(1, A(2, 24'h300), 32'h5555_5555, 4'hF, e, d, c, ok);
    check(ok && e && net_heads == h0 && mem[24'h300 >> 2] == 0 && c >= TO, $sformatf("B1_READY_HELD_LOW err=%0b cycles=%0d heads=+%0d", e, c, net_heads - h0));

    // late response after a timeout: must be dropped; the next read gets its own data
    mode = M_NORMAL; resp_lat = -1;
    xact(1, A(2, 24'h500), 32'hAAAA_0005, 4'hF, e, d, c, ok); expected_net++;
    xact(1, A(2, 24'h600), 32'hBBBB_0006, 4'hF, e, d, c, ok); expected_net++;
    // late response lands TO+5 cycles after the first packet: after the bridge timed out (HEAD + TO), but before the
    // second read's own response (latency 20), so a bridge without the drain would hand it to the second read.
    mode = M_LATE; late_delay = TO + 5;
    @(negedge clk); r0 = responses;   // after the previous response's counter update (same-edge race otherwise)
    xact(0, A(2, 24'h500), 0, 0, e, d, c, ok); expected_net++;        // times out; its late response carries AAAA_0005
    begin
      automatic logic e1 = e;
      mode = M_NORMAL; resp_lat = 20;
      xact(0, A(2, 24'h600), 0, 0, e, d, c, ok); expected_net++;
      repeat (200) @(negedge clk);
      check(e1 && ok && !e && d == 32'hBBBB_0006 && responses == r0 + 2,
            $sformatf("B1_LATE_RESPONSE_IGNORED first_err=%0b second_err=%0b data=%h responses=+%0d", e1, e, d, responses - r0));
    end
    resp_lat = -1;

    // random: 1,000 requests
    for (int i = 0; i < 4096; i++) shadow[i] = mem[i];
    for (int i = 0; i < 1000; i++) begin
      automatic int kind = $urandom % 20;
      automatic logic we = $urandom % 2;
      automatic logic [3:0] t = (kind == 0) ? 4'd0 : (kind == 1) ? 4'd5 : 4'd2;
      automatic logic [23:0] off = (kind == 2) ? (24'h4000 + (($urandom % 64) << 2)) : (($urandom % 4096) << 2);
      automatic logic [31:0] wd = $urandom;
      automatic logic [3:0] ws = $urandom;
      automatic logic unauth = (kind == 3);
      automatic logic exp_err = (t != 4'd2) || unauth || (off >= WIN_BYTES);
      authorized = !unauth; mode = M_NORMAL;
      if (t == 4'd2 && !unauth) expected_net++;
      xact(we, A(t, off), wd, ws, e, d, c, ok);
      if (!ok || e != exp_err) bad++;
      else if (!exp_err) begin
        if (we) begin for (int b = 0; b < 4; b++) if (ws[b]) shadow[off[13:2]][b*8 +: 8] = wd[b*8 +: 8]; end
        else if (d != shadow[off[13:2]]) bad++;
      end
      authorized = 1;
    end
    repeat (100) @(negedge clk);
    check(bad == 0, $sformatf("B1_RANDOM_1000 mismatches=%0d", bad));
    check(net_heads == expected_net && responses == grants, $sformatf("B1_COUNTS heads=%0d expected=%0d responses=%0d grants=%0d", net_heads, expected_net, responses, grants));
    check(valid_unauth == 0, $sformatf("B1_NO_VALID_WHILE_UNAUTH cycles=%0d", valid_unauth));

    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 19 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #50ms; $display("TB_TIMEOUT global"); $display("RESULT : FAIL"); $finish; end
endmodule
