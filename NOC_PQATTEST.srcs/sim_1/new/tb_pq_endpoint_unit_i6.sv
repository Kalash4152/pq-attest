`timescale 1ns/1ps
// tb_pq_endpoint_unit : PQ-2 unit bench for rtl/dual_lane/pq_attest_endpoint.sv, driven at the
// NI-side ports (no NoC). Expected values: vectors/endpoint_golden.svh (scripts/endpoint_golden.py,
// thin adapter over the teammate reference, TILE_KEY_BYTES=32). Track Q2 2026-10-19: prepared,
// NOT compiled or simulated by Track Q2. Frozen count: reports/i3_q2/Q2_COUNT_DERIVATION.md.
// No $fatal is used for any check; a bounded wait that expires prints TB_TIMEOUT (never a pass/kill).
module tb_pq_endpoint_unit;
  import noc_pkg::*;
  logic clk = 0, rst = 1;
  always #10 clk = ~clk;

  logic [255:0] root_secret;
  logic [111:0] context_in;
  logic [3:0]   context_len;
  logic [511:0] config_data, imem;
  logic [6:0]   config_len, imem_len;
  coord_t       rx_src_coord;
  msg_type_e    rx_msg_type;
  logic [4:0]   rx_length;
  logic         rx_head_valid = 0, rx_payload_valid = 0, rx_payload_last = 0, rx_abort = 0;
  logic [31:0]  rx_payload_data;
  logic         rx_ready;
  logic         tx_valid, tx_ready = 1, tx_payload_valid, tx_payload_ready = 1;
  coord_t       tx_dest_coord;
  msg_type_e    tx_msg_type;
  logic [10:0]  tx_control;
  logic [31:0]  tx_payload_data;
  logic         busy, controller_start, k3_fault;   // I-6: K-3 output (K3_ENFORCE = 0 here)
  logic [31:0]  rejected_count;
  logic [775:0] internal_response;

  pq_attest_endpoint dut(.*);
  `include "endpoint_golden.svh"

  // Endpoint state encodings (pq_attest_endpoint.sv es_t / pk_t).
  localparam int E_IDLE = 0, E_VALIDATE = 1, E_START = 2, E_WAIT = 3, E_REQ = 4, E_FILL = 5;

  int checks = 0, errors = 0;
  int starts = 0, exp_starts = 0, responses = 0, exp_responses = 0;
  int rx_ready_viol = 0, req_viol = 0, word_viol = 0, status_viol = 0, errword_viol = 0;
  logic [4:0] CL;                        // message_length(MSG_ATTEST_CHALLENGE)
  logic [31:0] pw[32];                   // payload words of the next packet
  logic [511:0] last_words, log_words[8];
  coord_t       last_dest;
  int bp_mode = 0;                       // 0 ready, 1 LFSR stalls, 2 manual hold
  logic hold_req = 1, hold_word = 1;
  logic [15:0] lfsr = 16'hace1;

  typedef struct packed { coord_t dest; logic [3:0] msg; logic [10:0] ctl; logic [511:0] words; } resp_t;
  resp_t q[$];
  resp_t cap;
  int cap_n = 0; bit cap_active = 0, seen_tx = 0;
  bit pr_req = 0, pr_word = 0;
  coord_t pr_dest; logic [3:0] pr_msg; logic [10:0] pr_ctl; logic [31:0] pr_data;

  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name);
    else begin errors++; $display("[FAIL] %s", name); end
  endtask

  // ---------------- TX monitor (sampled at posedge, flop semantics) ----------------
  always @(posedge clk) begin
    if (rst) begin
      cap_active = 0; cap_n = 0; q.delete(); pr_req = 0; pr_word = 0;
    end else begin
      if (controller_start) starts++;
      if (rx_ready !== 1'b1) rx_ready_viol++;
      if (tx_valid) seen_tx = 1;
      if (pr_req && !(tx_valid && tx_dest_coord == pr_dest && tx_msg_type == pr_msg && tx_control == pr_ctl)) req_viol++;
      if (pr_word && !(tx_payload_valid && tx_payload_data == pr_data)) word_viol++;
      pr_req = tx_valid && !tx_ready; pr_dest = tx_dest_coord; pr_msg = tx_msg_type; pr_ctl = tx_control;
      pr_word = tx_payload_valid && !tx_payload_ready; pr_data = tx_payload_data;
      if (tx_valid && tx_ready) begin
        cap.dest = tx_dest_coord; cap.msg = tx_msg_type; cap.ctl = tx_control; cap.words = '0;
        cap_active = 1; cap_n = 0;
        if (!(tx_control[10:7] inside {4'd1, 4'd2, 4'd3, 4'd5, 4'd10}) || tx_control[6:0] != 0 ||
            tx_msg_type != MSG_ATTEST_RESPONSE) status_viol++;
      end else if (tx_payload_valid && tx_payload_ready && cap_active) begin
        cap.words[32*cap_n +: 32] = tx_payload_data;
        if (cap.ctl[10:7] != 4'd1 && tx_payload_data != 0) errword_viol++;
        cap_n++;
        if (cap_n == 16) begin q.push_back(cap); responses++; cap_active = 0; end
      end
    end
  end

  // ---------------- TX backpressure generator ----------------
  always @(negedge clk) begin
    lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    case (bp_mode)
      1: begin tx_ready <= lfsr[0] & lfsr[3]; tx_payload_ready <= lfsr[1] | lfsr[6]; end
      2: begin tx_ready <= hold_req; tx_payload_ready <= hold_word; end
      default: begin tx_ready <= 1'b1; tx_payload_ready <= 1'b1; end
    endcase
  end

  // ---------------- helpers ----------------
  task automatic set_challenge(input int idx, input logic [15:0] pad);
    logic [223:0] c;
    c = {pad, ep_nonce(idx), ep_epoch(idx)};
    for (int k = 0; k < 7; k++) pw[k] = c[32*k +: 32];
    for (int k = 7; k < 32; k++) pw[k] = 32'h0bad0000 + k;
  endtask

  // HEAD then nwords payload words; abort_after = k >= 0 aborts after k words instead.
  task automatic send(input coord_t src, input msg_type_e msg, input logic [4:0] len, input int nwords,
                      input int abort_after = -1, input bit gaps = 0);
    @(negedge clk);
    rx_src_coord = src; rx_msg_type = msg; rx_length = len; rx_head_valid = 1;
    rx_payload_last = (nwords == 0 && abort_after < 0);
    @(negedge clk); rx_head_valid = 0; rx_payload_last = 0;
    for (int i = 0; i < nwords; i++) begin
      if (abort_after == i) begin rx_abort = 1; @(negedge clk); rx_abort = 0; return; end
      if (gaps && i[0]) @(negedge clk);
      rx_payload_data = pw[i]; rx_payload_valid = 1; rx_payload_last = (i == nwords - 1);
      @(negedge clk); rx_payload_valid = 0; rx_payload_last = 0;
    end
  endtask

  task automatic wait_es(input int st, input string name);
    int n; n = 0;
    while (dut.es != st && n < 20000) begin @(negedge clk); n++; end
    if (dut.es != st) begin errors++; $display("TB_TIMEOUT wait_es %0d %s", st, name); end
  endtask

  task automatic settle();
    int n; n = 0;
    while (busy && n < 20000) begin @(negedge clk); n++; end
    if (busy) begin errors++; $display("TB_TIMEOUT settle"); end
    repeat (2) @(negedge clk);
  endtask

  task automatic pop(output resp_t r, input string name);
    int n; n = 0;
    while (q.size() == 0 && n < 20000) begin @(negedge clk); n++; end
    if (q.size() == 0) begin errors++; $display("TB_TIMEOUT response %s", name); r = '0; end
    else r = q.pop_front();
  endtask

  task automatic expect_success(input string p, input int idx);   // 6 checks
    resp_t r; logic [511:0] e;
    e = ep_payload(idx); exp_responses++;
    pop(r, p); last_words = r.words; last_dest = r.dest;
    check(r.ctl[10:7] == EP_ST_SUCCESS && r.ctl[6:0] == 0 && r.msg == MSG_ATTEST_RESPONSE, {p, "_STATUS"});
    check(r.dest == tile_to_coord(TILE_ROT), {p, "_DEST"});
    check(r.words[255:0] === e[255:0], {p, "_MEAS_WORDS"});
    check(r.words[511:256] === e[511:256], {p, "_TAG_WORDS"});
    check(internal_response[56 +: 80] === ep_epoch(idx) && internal_response[136 +: 128] === ep_nonce(idx),
          {p, "_EPOCH_NONCE_FIELDS"});
    check(internal_response === ep_internal(idx), {p, "_INTERNAL_776"});
  endtask

  task automatic expect_error(input string p, input logic [3:0] code);   // 3 checks
    resp_t r;
    exp_responses++; pop(r, p);
    check(r.ctl[10:7] == code && r.ctl[6:0] == 0 && r.msg == MSG_ATTEST_RESPONSE, {p, "_STATUS"});
    check(r.dest == tile_to_coord(TILE_ROT), {p, "_DEST"});
    check(r.words == '0, {p, "_ZERO_PAYLOAD"});
  endtask

  task automatic expect_quiet(input string p, input int cycles);   // 1 check
    @(negedge clk); seen_tx = 0;
    repeat (cycles) @(negedge clk);
    check(q.size() == 0 && !seen_tx && !busy, {p, "_NO_REPLY"});
  endtask

  task automatic valid_case(input string p, input int idx, input bit gaps);   // 7 checks
    int rc0;
    settle(); ep_provision(idx); set_challenge(idx, 16'h0); rc0 = rejected_count;
    send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7, -1, gaps); exp_starts++;
    expect_success(p, idx);
    check(rejected_count == rc0, {p, "_NO_REJECT"});
  endtask

  task automatic malformed_case(input string p, input logic [4:0] len, input int nwords,
                                input int abort_after, input logic [15:0] pad, input logic [3:0] code);   // 5 checks
    int rc0, s0;
    settle(); ep_provision(0); set_challenge(0, pad); rc0 = rejected_count; s0 = starts;
    send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, len, nwords, abort_after);
    expect_error(p, code);
    settle();
    check(rejected_count == rc0 + 1, {p, "_COUNTED"});
    check(starts == s0, {p, "_NO_START"});
  endtask

  task automatic drop_case(input string p, input coord_t src, input msg_type_e msg, input logic [4:0] len,
                           input int nwords, input logic [15:0] pad, input bit counted);   // 3 checks
    int rc0, s0;
    settle(); ep_provision(0); set_challenge(0, pad); rc0 = rejected_count; s0 = starts;
    send(src, msg, len, nwords);
    expect_quiet(p, 400);
    check(rejected_count == rc0 + (counted ? 1 : 0), {p, counted ? "_COUNTED" : "_NOT_COUNTED"});
    check(starts == s0, {p, "_NO_START"});
  endtask

  task automatic ctrl_error_case(input string p, input int which, input logic [3:0] code);   // 5 checks
    int rc0, s0;
    settle(); ep_provision(0);
    if (which == 1) context_len = 4'd15;
    if (which == 2) config_len = 7'd65;
    if (which == 3) imem_len = 7'd65;
    set_challenge(0, 16'h0); rc0 = rejected_count; s0 = starts;
    send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7); exp_starts++;
    if (which == 4) begin
      wait_es(E_WAIT, p);
      force dut.err = 1'b1;              // controller err with error_code 0 -> internal (10)
      for (int n = 0; n < 20000 && dut.es == E_WAIT; n++) @(negedge clk);
      release dut.err;
    end
    expect_error(p, code);
    check(starts == s0 + 1, {p, "_STARTED"});
    check(rejected_count == rc0, {p, "_NOT_COUNTED"});
    settle(); ep_provision(0);
  endtask

  task automatic reset_pulse();   // called at a negedge: the next posedge is the first reset edge
    rst = 1;
    rx_head_valid = 0; rx_payload_valid = 0; rx_payload_last = 0; rx_abort = 0;
    repeat (3) @(negedge clk);
  endtask

  task automatic reset_checks(input string p);   // 2 checks
    int s0;
    check(!busy && !tx_valid && !tx_payload_valid && rejected_count == 0 && dut.busy_pending == 0 &&
          dut.status_q == 0 && dut.es == E_IDLE && dut.pk == 0 && internal_response == '0, {p, "_CLEARED"});
    bp_mode = 0; hold_req = 1; hold_word = 1;
    @(negedge clk); rst = 0; s0 = starts; seen_tx = 0;
    repeat (400) @(negedge clk);
    check(!seen_tx && q.size() == 0 && starts == s0 && !busy, {p, "_NO_STALE_TX"});
  endtask

  // ---------------- test sequence ----------------
  initial begin
    CL = message_length(MSG_ATTEST_CHALLENGE);
    $display("CONFIG: TOP=tb_pq_endpoint_unit MAC_FLITS=%0d CHALLENGE_LEN=%0d VECTORS=%0d TILE_KEY_BYTES=32",
             MAC_FLITS, CL, EP_VECTORS);
    rx_src_coord = '0; rx_msg_type = MSG_MEM_RD_REQ; rx_length = 0; rx_payload_data = 0;
    ep_provision(0);
    repeat (5) @(negedge clk); rst = 0; repeat (2) @(negedge clk);

    // T1 valid challenges, distinct and consecutive; duplicate is served statelessly.
    for (int i = 0; i < EP_VECTORS; i++) begin
      valid_case($sformatf("V%02d", i), i, i[0]);
      log_words[i] = last_words;
    end
    check(log_words[0] != log_words[1] && log_words[1] != log_words[2] && log_words[2] != log_words[3],
          "DISTINCT_CONSECUTIVE");
    valid_case("V00DUP", 0, 0);
    check(last_words == log_words[0], "DUPLICATE_SERVED_STATELESS");

    // T2 malformed RoT challenges -> 5; drop and ignore cases -> no reply.
    malformed_case("M_SHORT6",     CL,        6, -1, 16'h0000, EP_EXP_SHORT6);
    malformed_case("M_LONG8",      CL,        8, -1, 16'h0000, EP_EXP_LONG8);
    malformed_case("M_LEN_PLUS1",  CL + 5'd1, 7, -1, 16'h0000, EP_EXP_LEN_PLUS1);
    malformed_case("M_LEN_MINUS1", CL - 5'd1, 7, -1, 16'h0000, EP_EXP_LEN_MINUS1);
    malformed_case("M_ZERO_WORDS", 5'd1,      0, -1, 16'h0000, EP_EXP_ZERO_WORDS);
    malformed_case("M_PAD_BIT223", CL,        7, -1, 16'h8000, EP_EXP_PAD_BIT223);
    malformed_case("M_PAD_BIT208", CL,        7, -1, 16'h0001, EP_EXP_PAD_BIT208);
    for (int k = 0; k < 7; k++)
      malformed_case($sformatf("M_ABORT_AFTER_%0d", k), CL, 7, k, 16'h0000, EP_EXP_ABORT);
    drop_case("D_ISSUER_SPOOF",        tile_to_coord(TILE_SPOOF),  MSG_ATTEST_CHALLENGE, CL, 7, 16'h0, 1);
    drop_case("D_ISSUER_CPU0",         tile_to_coord(TILE_CPU0),   MSG_ATTEST_CHALLENGE, CL, 7, 16'h0, 1);
    drop_case("D_ISSUER_CRYPTO",       tile_to_coord(TILE_CRYPTO), MSG_ATTEST_CHALLENGE, CL, 7, 16'h0, 1);
    drop_case("D_ISSUER_SPOOF_BADPAD", tile_to_coord(TILE_SPOOF),  MSG_ATTEST_CHALLENGE, CL, 7, 16'hffff, 1);
    drop_case("D_TYPE_RESPONSE",       tile_to_coord(TILE_ROT),    MSG_ATTEST_RESPONSE,
              message_length(MSG_ATTEST_RESPONSE), 16, 16'h0, 1);
    drop_case("D_TYPE_RESERVED9",      tile_to_coord(TILE_ROT),    msg_type_e'(4'd9), CL, 7, 16'h0, 1);
    drop_case("I_GRANT",               tile_to_coord(TILE_ROT),    MSG_ATTEST_GRANT,
              message_length(MSG_ATTEST_GRANT), 0, 16'h0, 0);
    drop_case("I_REVOKE",              tile_to_coord(TILE_ROT),    MSG_ATTEST_REVOKE,
              message_length(MSG_ATTEST_REVOKE), 0, 16'h0, 0);
    drop_case("I_MEM_WR_RESP",         tile_to_coord(TILE_MEMORY), MSG_MEM_WR_RESP,
              message_length(MSG_MEM_WR_RESP), 0, 16'h0, 0);
    drop_case("I_MEM_RD_RESP",         tile_to_coord(TILE_MEMORY), MSG_MEM_RD_RESP,
              message_length(MSG_MEM_RD_RESP), 1, 16'h0, 0);

    // T3 controller verdicts: reject (2) and internal (10); stale internal bytes never sent.
    check(internal_response != '0, "R_STALE_INTERNAL_PRESENT");
    ctrl_error_case("R_CTX15",      1, EP_EXP_REJECT_CTX);
    ctrl_error_case("R_CFG65",      2, EP_EXP_REJECT_LEN);
    ctrl_error_case("R_IMEM65",     3, EP_EXP_REJECT_LEN);
    ctrl_error_case("X_FORCED_ERR", 4, EP_EXP_INTERNAL);

    // T4 busy endpoint drains and counts.
    begin : b1   // busy RoT challenge during computation -> success first, then 3
      int rc0, s0;
      settle(); ep_provision(1); set_challenge(1, 16'h0); rc0 = rejected_count; s0 = starts;
      send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7); exp_starts++;
      set_challenge(2, 16'h0);
      send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7);
      expect_success("B1_FIRST", 1);
      expect_error("B1_BUSY", EP_EXP_BUSY);
      settle();
      check(rejected_count == rc0 + 1, "B1_COUNTED");
      check(starts == s0 + 1, "B1_ONE_START");
    end
    begin : b2   // two busy challenges while TX is held: one busy reply, both counted
      int rc0, s0;
      settle(); ep_provision(3); set_challenge(3, 16'h0); rc0 = rejected_count; s0 = starts;
      @(negedge clk); hold_req = 0; bp_mode = 2;
      send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7); exp_starts++;
      wait_es(E_REQ, "B2");
      send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7);
      send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7);
      @(negedge clk); hold_req = 1;
      expect_success("B2_FIRST", 3);
      expect_error("B2_BUSY", EP_EXP_BUSY);
      bp_mode = 0;
      expect_quiet("B2_SINGLE_BUSY_REPLY", 400);
      check(rejected_count == rc0 + 2, "B2_COUNTED_TWO");
      check(starts == s0 + 1, "B2_ONE_START");
    end
    begin : b3   // SPOOF challenge during computation: count only; reply-to stays latched
      int rc0;
      settle(); ep_provision(0); set_challenge(0, 16'h0); rc0 = rejected_count;
      send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7); exp_starts++;
      send(tile_to_coord(TILE_SPOOF), MSG_ATTEST_CHALLENGE, CL, 7);
      expect_success("B3_FIRST", 0);
      check(rx_src_coord == tile_to_coord(TILE_SPOOF) && last_dest == tile_to_coord(TILE_ROT), "REPLY_TO_LATCHED");
      expect_quiet("B3_NO_BUSY_REPLY_TO_SPOOF", 400);
      check(rejected_count == rc0 + 1, "B3_COUNTED");
    end
    begin : b4   // aborted busy challenge: counted, no busy reply
      int rc0;
      settle(); ep_provision(2); set_challenge(2, 16'h0); rc0 = rejected_count;
      send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7); exp_starts++;
      send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7, 2);
      expect_success("B4_FIRST", 2);
      expect_quiet("B4_NO_BUSY_REPLY", 400);
      check(rejected_count == rc0 + 1, "B4_COUNTED");
    end
    begin : b5   // busy has priority over malformed (nonzero padding while busy -> 3)
      int rc0;
      settle(); ep_provision(0); set_challenge(0, 16'h0); rc0 = rejected_count;
      send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7); exp_starts++;
      set_challenge(0, 16'h00ff);
      send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7);
      expect_success("B5_FIRST", 0);
      expect_error("B5_BUSY", EP_EXP_BUSY);
      settle();
      check(rejected_count == rc0 + 1, "B5_COUNTED");
    end

    // T5 TX backpressure.
    settle(); bp_mode = 1;
    valid_case("P1", 4, 1);
    malformed_case("P2_SHORT6", CL, 6, -1, 16'h0000, EP_EXP_SHORT6);
    bp_mode = 0;
    begin : p3   // sustained request backpressure: held 500 cycles, then word stalls
      int held;
      settle(); ep_provision(5); set_challenge(5, 16'h0);
      @(negedge clk); hold_req = 0; hold_word = 0; bp_mode = 2;
      send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7); exp_starts++;
      wait_es(E_REQ, "P3");
      held = 0;
      repeat (500) begin @(negedge clk); if (tx_valid) held++; end
      check(held == 500, "P3_HELD_REQUEST");
      hold_req = 1; bp_mode = 1;
      expect_success("P3", 5);
      bp_mode = 0;
    end

    // T6 reset in each phase cancels everything; then recovery.
    settle(); ep_provision(1); set_challenge(1, 16'h0);
    send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7, 3);   // abort after 3 = malformed reply path
    expect_error("RST_PRE_ABORT", EP_EXP_ABORT);                       // (3 checks) then reset mid-RX:
    settle();
    @(negedge clk);
    rx_src_coord = tile_to_coord(TILE_ROT); rx_msg_type = MSG_ATTEST_CHALLENGE; rx_length = CL; rx_head_valid = 1;
    @(negedge clk); rx_head_valid = 0;
    for (int i = 0; i < 3; i++) begin rx_payload_data = pw[i]; rx_payload_valid = 1; @(negedge clk); end
    rx_payload_valid = 0;
    reset_pulse(); reset_checks("RST_RX");
    send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7);
    wait_es(E_VALIDATE, "RST_VALIDATE"); reset_pulse(); reset_checks("RST_VALIDATE");
    send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7);
    wait_es(E_START, "RST_START"); reset_pulse(); reset_checks("RST_START");
    send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7); exp_starts++;
    wait_es(E_WAIT, "RST_WAIT"); repeat (20) @(negedge clk); reset_pulse(); reset_checks("RST_WAIT");
    @(negedge clk); hold_req = 0; bp_mode = 2;
    send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7); exp_starts++;
    wait_es(E_REQ, "RST_REQ"); repeat (10) @(negedge clk); reset_pulse(); reset_checks("RST_REQ");
    @(negedge clk); hold_req = 1; hold_word = 1; bp_mode = 2;
    send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7); exp_starts++;
    wait_es(E_FILL, "RST_FILL"); repeat (5) @(negedge clk); hold_word = 0; repeat (10) @(negedge clk);
    reset_pulse(); reset_checks("RST_FILL");
    @(negedge clk); hold_req = 0; bp_mode = 2;
    send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7); exp_starts++;
    wait_es(E_REQ, "RST_BUSY_PENDING");
    send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 7);
    repeat (3) @(negedge clk); reset_pulse(); reset_checks("RST_BUSY_PENDING");
    @(negedge clk); hold_req = 1; hold_word = 1; bp_mode = 2;
    set_challenge(1, 16'h0);
    send(tile_to_coord(TILE_ROT), MSG_ATTEST_CHALLENGE, CL, 6);
    wait_es(E_FILL, "RST_ERROR_FILL"); repeat (3) @(negedge clk); hold_word = 0; repeat (10) @(negedge clk);
    reset_pulse(); reset_checks("RST_ERROR_FILL");
    valid_case("RST_RECOVERY", 1, 0);

    // Global monitors.
    settle();
    check(rx_ready_viol == 0, "RX_READY_ALWAYS");
    check(req_viol == 0, "TX_REQUEST_STABLE");
    check(word_viol == 0, "TX_WORD_STABLE");
    check(status_viol == 0, "STATUS_CODES_LEGAL");
    check(errword_viol == 0, "ERROR_WORDS_ZERO");
    check(starts == exp_starts, "START_COUNT");
    check(q.size() == 0, "NO_UNCONSUMED_RESPONSE");
    check(responses == exp_responses, "RESPONSE_COUNT");
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #24ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
