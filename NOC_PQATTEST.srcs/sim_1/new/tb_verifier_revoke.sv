`timescale 1ns/1ps
// Contract sec. 2 (Q3, Q5), docs/decisions/P7-INGRESS-REVOCATION-CONTRACT.md: revocation rules of rtl/dual_lane/
// pq_rot_verifier.sv, unit level. BYPASS_MEASUREMENT = BYPASS_TAG = 1 so that a well-formed RESPONSE header reaches
// every state cheaply (the crypto checks are covered by s8_golden / the endpoint benches); TIMEOUT_CYCLES = 3000.
// The TB is the verifier's L2 TX sink (tx_ready / tx_payload_ready, with backpressure on request) and its RX source.
// Monitors: every accepted request (GRANT / REVOKE / CHALLENGE) and its payload words; a withdrawal monitor (tx_valid
// falling, or msg_type changing, before the handshake) for the interface rule.
// A. A revoke edge in each of the 11 states (V_REQ and V_GRANT reached under TX backpressure). Per state S:
//    VREV_<S>_ONE_REVOKE  exactly one REVOKE request after the edge;
//    VREV_<S>_NO_GRANT    no GRANT after the edge, except at most the one already offered in V_GRANT;
//    VREV_<S>_CHALLENGE   every accepted CHALLENGE got all 7 words.                                   11 x 3 = 33
// B. Same-edge combinations: revoke with tx_ready in V_REQ, with tx_ready in V_GRANT, with kd (KDF done), with td (tag
//    done): VREV_SAME_<X>_ONE_REVOKE and VREV_SAME_<X>_NO_GRANT (same allowance rule).                    4 x 2 = 8
// C. VREV_HELD_ONE: revoke held high for 10,000 cycles from idle gives exactly one REVOKE.                     1
// D. Timeout during V_FILL (payload stalled past TIMEOUT_CYCLES): VREV_TIMEOUT_FILL_COMPLETE (the challenge still gets its
//    7 words), VREV_TIMEOUT_FILL_REVOKE (one REVOKE), VREV_TIMEOUT_FILL_FAILED (failed pulsed).               3
// E. rx_abort during V_WAIT: VREV_ABORT_WAIT_REVOKE (one REVOKE), VREV_ABORT_WAIT_FAILED (failed pulsed).        2
// F. VREV_NO_WITHDRAWAL: the withdrawal monitor never fired over the whole run.                                1
// CHECKS = 33 + 8 + 1 + 3 + 2 + 1 = 48, frozen before the first run. Bounded waits: TB_TIMEOUT (INVALID).
module tb_verifier_revoke;
  import noc_pkg::*;
  logic clk = 0, rst = 1, start = 0, revoke = 0;
  always #10 clk = ~clk;
  logic tx_valid, tx_ready = 1, tx_payload_valid, tx_payload_ready = 1;
  coord_t tx_dest; msg_type_e tx_msg; logic [10:0] tx_ctl; logic [31:0] tx_pd;
  logic rx_head_valid = 0, rx_payload_valid = 0, rx_payload_last = 0, rx_abort = 0;
  coord_t rx_src; msg_type_e rx_msg = MSG_ATTEST_RESPONSE; logic [10:0] rx_ctl = 11'h080; logic [31:0] rx_pd = 0;
  logic rx_ready, busy, grant_done, failed; logic [31:0] rejected; logic [127:0] ononce;
  pq_rot_verifier #(.TIMEOUT_CYCLES(3000), .BYPASS_MEASUREMENT(1'b1), .BYPASS_TAG(1'b1)) dut (
    .clk, .rst, .start, .revoke, .root_secret({8{32'h0123_4567}}), .approved_measurement('0), .epoch(80'h1),
    .nonce(128'hA5), .context_in('0), .context_len(4'd0),
    .tx_valid, .tx_ready, .tx_dest_coord(tx_dest), .tx_msg_type(tx_msg), .tx_control(tx_ctl),
    .tx_payload_data(tx_pd), .tx_payload_valid, .tx_payload_ready,
    .rx_head_valid, .rx_src_coord(rx_src), .rx_msg_type(rx_msg), .rx_control(rx_ctl),
    .rx_payload_data(rx_pd), .rx_payload_valid, .rx_payload_last, .rx_abort,
    .rx_ready, .busy, .grant_done, .failed, .rejected_count(rejected), .outstanding_nonce(ononce));
  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  task automatic timeout(input string w); $display("TB_TIMEOUT %s", w); $finish; endtask
  // request / payload monitors
  int n_grant = 0, n_revoke = 0, n_chal = 0, chal_words = 0, chal_bad = 0, withdraw = 0, n_failed = 0;
  logic v_q = 0; msg_type_e m_q;
  always @(posedge clk) if (!rst) begin
    if (tx_valid && tx_ready) begin
      if (tx_msg == MSG_ATTEST_GRANT) n_grant++;
      else if (tx_msg == MSG_ATTEST_REVOKE) n_revoke++;
      else begin if (n_chal > 0 && chal_words != 7) chal_bad++; n_chal++; chal_words = 0; end
    end
    if (tx_payload_valid && tx_payload_ready) chal_words++;
    if (v_q && (!tx_valid || tx_msg != m_q)) withdraw++;                    // valid or type changed before the handshake
    v_q = tx_valid && !tx_ready; m_q = tx_msg;
    if (failed) n_failed++;
  end
  task automatic do_reset(); @(negedge clk); rst = 1; revoke = 0; start = 0; tx_ready = 1; tx_payload_ready = 1;
    rx_head_valid = 0; rx_payload_valid = 0; rx_abort = 0; repeat (4) @(negedge clk); rst = 0; @(negedge clk);
    n_grant = 0; n_revoke = 0; n_chal = 0; chal_words = 0; chal_bad = 0; n_failed = 0; endtask
  task automatic pulse_start(); @(negedge clk); start = 1; @(negedge clk); start = 0; endtask
  task automatic wait_state(input int s, input string w);
    automatic int n = 0;
    while (dut.vs != s && n < 20000) begin @(negedge clk); n++; end
    if (dut.vs != s) timeout({"state ", w});
  endtask
  task automatic send_response();
    @(negedge clk); rx_src = tile_to_coord(TILE_CRYPTO); rx_msg = MSG_ATTEST_RESPONSE; rx_ctl = 11'h080; rx_head_valid = 1;
    @(negedge clk); rx_head_valid = 0;
    for (int i = 0; i < 16; i++) begin rx_pd = 32'hC0DE_0000 + i; rx_payload_valid = 1; rx_payload_last = i == 15; @(negedge clk); end
    rx_payload_valid = 0; rx_payload_last = 0;
  endtask
  task automatic finish_ok(input int s);       // let the run complete: release backpressure, answer if waiting
    automatic int n = 0;
    tx_ready = 1; tx_payload_ready = 1;
    while (dut.vs != 0 && n < 30000) begin
      @(negedge clk); n++;
      if (dut.vs == 5 && !dut.collecting) send_response();
    end
    if (dut.vs != 0) timeout("verifier never returned to V_IDLE");
    repeat (20) @(negedge clk);
  endtask
  task automatic edge_now(); revoke = 1; @(negedge clk); revoke = 0; endtask
  // section A: one state at a time; the edge is applied in the cycle the state is observed
  // state names by a case function: XSim 2024.1 printed a localparam string array element as garbage (run 182317)
  function automatic string sn(input int s);
    case (s) 0: return "IDLE"; 1: return "KSTART"; 2: return "KWAIT"; 3: return "REQ"; 4: return "FILL"; 5: return "WAIT";
      6: return "CHECK"; 7: return "TSTART"; 8: return "TWAIT"; 9: return "GRANT"; 10: return "REVOKE"; default: return "BAD"; endcase
  endfunction
  task automatic state_trial(input int s);
    automatic int g0, r0;
    do_reset();
    if (s == 3) tx_ready = 0;                                  // V_REQ held by backpressure
    if (s == 9 || s == 10) tx_ready = 1;
    if (s != 0) pulse_start();
    if (s == 0) begin end
    else if (s == 9) begin                                     // V_GRANT under backpressure
      wait_state(5, "WAIT"); send_response(); wait_state(8, "TWAIT"); tx_ready = 0; wait_state(9, "GRANT");
    end else if (s == 10) begin                                // V_REVOKE: get there with a first revoke, then edge again
      wait_state(2, "KWAIT"); edge_now(); tx_ready = 0; wait_state(10, "REVOKE");
    end else if (s >= 6) begin wait_state(5, "WAIT"); send_response(); wait_state(s, sn(s)); end
    else wait_state(s, sn(s));
    g0 = n_grant; r0 = n_revoke;
    edge_now();
    finish_ok(s);
    check(n_revoke - r0 == 1 || (s == 10 && n_revoke - r0 == 1), $sformatf("VREV_%s_ONE_REVOKE revokes=%0d", sn(s), n_revoke - r0));
    check(n_grant - g0 <= (s == 9 ? 1 : 0), $sformatf("VREV_%s_NO_GRANT grants=%0d", sn(s), n_grant - g0));
    check(chal_bad == 0 && (n_chal == 0 || chal_words == 7), $sformatf("VREV_%s_CHALLENGE challenges=%0d last_words=%0d bad=%0d", sn(s), n_chal, chal_words, chal_bad));
  endtask

  initial begin
    $display("CONFIG: TOP=tb_verifier_revoke CHECKS=48 TIMEOUT_CYCLES=3000 BYPASS=1");
    rx_src = tile_to_coord(TILE_CRYPTO);
    for (int s = 0; s < 11; s++) state_trial(s);
    // ---- B: same-edge combinations
    begin
      automatic int g0, r0;
      // revoke together with the V_REQ handshake
      do_reset(); tx_ready = 0; pulse_start(); wait_state(3, "REQ"); g0 = n_grant; r0 = n_revoke;
      revoke = 1; tx_ready = 1; @(negedge clk); revoke = 0; finish_ok(3);
      check(n_revoke - r0 == 1, $sformatf("VREV_SAME_REQ_ONE_REVOKE revokes=%0d", n_revoke - r0));
      check(n_grant - g0 == 0 && chal_words == 7, $sformatf("VREV_SAME_REQ_NO_GRANT grants=%0d words=%0d", n_grant - g0, chal_words));
      // revoke together with the V_GRANT handshake
      do_reset(); pulse_start(); wait_state(5, "WAIT"); send_response(); wait_state(8, "TWAIT"); tx_ready = 0; wait_state(9, "GRANT");
      g0 = n_grant; r0 = n_revoke; revoke = 1; tx_ready = 1; @(negedge clk); revoke = 0; finish_ok(9);
      check(n_revoke - r0 == 1, $sformatf("VREV_SAME_GRANT_ONE_REVOKE revokes=%0d", n_revoke - r0));
      check(n_grant - g0 <= 1, $sformatf("VREV_SAME_GRANT_NO_GRANT grants=%0d", n_grant - g0));
      // revoke in the cycle the KDF completes
      do_reset(); pulse_start(); begin automatic int n = 0; while (!(dut.vs == 2 && dut.kd) && n < 20000) begin @(negedge clk); n++; end
        if (n >= 20000) timeout("kd"); end
      g0 = n_grant; r0 = n_revoke; edge_now(); finish_ok(2);
      check(n_revoke - r0 == 1, $sformatf("VREV_SAME_KD_ONE_REVOKE revokes=%0d", n_revoke - r0));
      check(n_grant - g0 == 0, $sformatf("VREV_SAME_KD_NO_GRANT grants=%0d", n_grant - g0));
      // revoke in the cycle the tag check completes
      do_reset(); pulse_start(); wait_state(5, "WAIT"); send_response();
      begin automatic int n = 0; while (!(dut.vs == 8 && dut.td) && n < 20000) begin @(negedge clk); n++; end
        if (n >= 20000) timeout("td"); end
      g0 = n_grant; r0 = n_revoke; edge_now(); finish_ok(8);
      check(n_revoke - r0 == 1, $sformatf("VREV_SAME_TD_ONE_REVOKE revokes=%0d", n_revoke - r0));
      check(n_grant - g0 == 0, $sformatf("VREV_SAME_TD_NO_GRANT grants=%0d", n_grant - g0));
    end
    // ---- C: held revoke
    do_reset(); revoke = 1; repeat (10000) @(negedge clk); revoke = 0; repeat (50) @(negedge clk);
    check(n_revoke == 1, $sformatf("VREV_HELD_ONE revokes=%0d", n_revoke));
    // ---- D: timeout during V_FILL
    do_reset(); pulse_start(); wait_state(4, "FILL"); tx_payload_ready = 0;
    repeat (3200) @(negedge clk);
    begin automatic int f0 = n_failed; tx_payload_ready = 1; finish_ok(4);
      check(chal_words == 7 && chal_bad == 0, $sformatf("VREV_TIMEOUT_FILL_COMPLETE words=%0d", chal_words));
      check(n_revoke == 1, $sformatf("VREV_TIMEOUT_FILL_REVOKE revokes=%0d", n_revoke));
      check(n_failed >= 1, $sformatf("VREV_TIMEOUT_FILL_FAILED failed_pulses=%0d", n_failed)); end
    // ---- E: rx_abort during V_WAIT
    do_reset(); pulse_start(); wait_state(5, "WAIT"); @(negedge clk); rx_abort = 1; @(negedge clk); rx_abort = 0;
    begin automatic int n = 0; while (dut.vs != 0 && n < 30000) begin @(negedge clk); n++; end end
    repeat (20) @(negedge clk);
    check(n_revoke == 1, $sformatf("VREV_ABORT_WAIT_REVOKE revokes=%0d", n_revoke));
    check(n_failed >= 1, $sformatf("VREV_ABORT_WAIT_FAILED failed_pulses=%0d", n_failed));
    // ---- F
    check(withdraw == 0, $sformatf("VREV_NO_WITHDRAWAL withdrawals=%0d", withdraw));
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #20ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
