`timescale 1ns/1ps
// I-6 C-1/C-2 busy retry (docs/decisions/I6_CONTRACT.md sec. 4) on rtl/dual_lane/pq_rot_verifier.sv, unit level, as
// tb_verifier_revoke: BYPASS_MEASUREMENT = BYPASS_TAG = 1, TIMEOUT_CYCLES = 3000. The TB is the verifier's TX sink and RX
// source; it answers each COMPLETE challenge (7 words) with the next status of the trial's list (silence when the list is
// exhausted). Expected values: vectors/i6_retry.svh, generated from scripts/policy_layer.py (busy_retry_outcome).
// A. Python rows n_busy = 0..5 (n BUSY replies then SUCCESS while challenges are still sent):
//    RETRY_PY_N<n>_CHALLENGES (challenges sent == expected, every retry carries the same 7 words as the first)
//    RETRY_PY_N<n>_OUTCOME    (GRANT: one GRANT, no REVOKE, no failure; FAIL: no GRANT, one REVOKE, one failure with
//                              fail_reason 9)                                                                6 x 2 = 12
// B. Statuses 2, 5, 10: RETRY_STATUS<s>_NO_RETRY (one challenge, one REVOKE, no GRANT) and RETRY_STATUS<s>_FAIL_REASON
//    (one failure, fail_reason 9)                                                                           3 x 2 = 6
// C. Counter reset without a hardware reset: RETRY_RESET_AFTER_FAIL (4 BUSY -> fail, then 3 BUSY + SUCCESS grants after 4
//    challenges), RETRY_RESET_AFTER_GRANT (3 BUSY + SUCCESS twice; the second grants after 4 challenges)          2
// D. Timeout inside a retry (1 BUSY, then silence): RETRY_TIMEOUT_REASON (one failure, fail_reason 8),
//    RETRY_TIMEOUT_REVOKE (2 challenges, one REVOKE, no GRANT)                                                     2
// E. RETRY_TIMER_PER_ATTEMPT: 3 BUSY + SUCCESS, each reply 2,000 cycles after its challenge (8,000 > TIMEOUT in total,
//    each attempt < TIMEOUT): grants, no failure                                                                1
// F. RETRY_REVOKE_DURING: 1 BUSY, revoke edge in the retry: one REVOKE, no GRANT, no failure                     1
// CHECKS = 12 + 6 + 2 + 2 + 1 + 1 = 24, frozen in the contract before the first run. A trial that does not return to
// V_IDLE within 60,000 cycles fails its checks (bounded, never a pass); TB_TIMEOUT only for the global limit.
module tb_i6_retry;
  import noc_pkg::*;
  `include "i6_retry.svh"
  logic clk = 0, rst = 1, start = 0, revoke = 0;
  always #10 clk = ~clk;
  logic tx_valid, tx_ready = 1, tx_payload_valid, tx_payload_ready = 1;
  coord_t tx_dest; msg_type_e tx_msg; logic [10:0] tx_ctl; logic [31:0] tx_pd;
  logic rx_head_valid = 0, rx_payload_valid = 0, rx_payload_last = 0, rx_abort = 0;
  coord_t rx_src; msg_type_e rx_msg = MSG_ATTEST_RESPONSE; logic [10:0] rx_ctl = 11'h080; logic [31:0] rx_pd = 0;
  logic rx_ready, busy, grant_done, failed; logic [31:0] rejected; logic [127:0] ononce; logic [3:0] fail_reason;
  pq_rot_verifier #(.TIMEOUT_CYCLES(3000), .BYPASS_MEASUREMENT(1'b1), .BYPASS_TAG(1'b1)) dut (
    .clk, .rst, .start, .revoke, .root_secret({8{32'h0123_4567}}), .approved_measurement('0), .epoch(80'h1),
    .nonce(128'hA5), .context_in('0), .context_len(4'd0),
    .tx_valid, .tx_ready, .tx_dest_coord(tx_dest), .tx_msg_type(tx_msg), .tx_control(tx_ctl),
    .tx_payload_data(tx_pd), .tx_payload_valid, .tx_payload_ready,
    .rx_head_valid, .rx_src_coord(rx_src), .rx_msg_type(rx_msg), .rx_control(rx_ctl),
    .rx_payload_data(rx_pd), .rx_payload_valid, .rx_payload_last, .rx_abort,
    .rx_ready, .busy, .grant_done, .failed, .rejected_count(rejected), .outstanding_nonce(ononce), .fail_reason);
  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  // monitors: requests, challenge words (the first challenge of a trial is the reference), failures
  int n_grant = 0, n_revoke = 0, n_chal = 0, n_done = 0, chal_words = 0, word_diff = 0, n_failed = 0;
  logic [3:0] last_reason = 0;
  logic [31:0] ref_words [7];
  always @(posedge clk) if (!rst) begin
    if (tx_valid && tx_ready) begin
      if (tx_msg == MSG_ATTEST_GRANT) n_grant++;
      else if (tx_msg == MSG_ATTEST_REVOKE) n_revoke++;
      else begin n_chal++; chal_words = 0; end
    end
    if (tx_payload_valid && tx_payload_ready) begin
      if (n_chal == 1 && chal_words < 7) ref_words[chal_words] = tx_pd;
      else if (chal_words < 7 && tx_pd != ref_words[chal_words]) word_diff++;
      chal_words++;
      if (chal_words == 7) n_done++;
    end
    if (failed) begin n_failed++; last_reason = fail_reason; end
  end
  task automatic do_reset(); @(negedge clk); rst = 1; revoke = 0; start = 0; tx_ready = 1; tx_payload_ready = 1;
    rx_head_valid = 0; rx_payload_valid = 0; rx_abort = 0; repeat (4) @(negedge clk); rst = 0; @(negedge clk); clear_counts(); endtask
  task automatic clear_counts(); n_grant = 0; n_revoke = 0; n_chal = 0; n_done = 0; chal_words = 0; word_diff = 0; n_failed = 0; last_reason = 0; endtask
  task automatic send_response(input int status);
    @(negedge clk); rx_src = tile_to_coord(TILE_CRYPTO); rx_msg = MSG_ATTEST_RESPONSE; rx_ctl = {4'(status), 7'b0}; rx_head_valid = 1;
    @(negedge clk); rx_head_valid = 0;
    for (int i = 0; i < 16; i++) begin rx_pd = status == 1 ? 32'hC0DE_0000 + i : 32'h0; rx_payload_valid = 1; rx_payload_last = i == 15; @(negedge clk); end
    rx_payload_valid = 0; rx_payload_last = 0;
  endtask
  // one attestation start: answer each complete challenge with the next status (none when exhausted); returns when the
  // verifier is back in V_IDLE (ok = 1) or after 60,000 cycles (ok = 0)
  task automatic trial(input int st [$], input int delay, input bit revoke_in_retry, output bit ok);
    automatic int n = 0, answered = 0;
    clear_counts();
    @(negedge clk); start = 1; @(negedge clk); start = 0;
    while (n < 60000) begin
      if (dut.vs == 0) break;
      if (n_done > answered) begin
        if (answered < st.size()) begin
          repeat (delay) @(negedge clk); n += delay;
          send_response(st[answered]); n += 17;
          if (revoke_in_retry && answered == 0) begin revoke = 1; @(negedge clk); revoke = 0; n++; end
        end
        answered++;
      end
      @(negedge clk); n++;
    end
    ok = dut.vs == 0;
    repeat (20) @(negedge clk);
  endtask
  function automatic bit outcome_grant(); return n_grant == 1 && n_revoke == 0 && n_failed == 0; endfunction
  function automatic bit outcome_fail(input int reason); return n_grant == 0 && n_revoke == 1 && n_failed == 1 && last_reason == reason; endfunction

  initial begin
    bit ok;
    int st [$];
    $display("CONFIG: TOP=tb_i6_retry CHECKS=24 TIMEOUT_CYCLES=3000 MAX_BUSY_RETRIES=%0d BYPASS=1", I6_MAX_BUSY_RETRIES);
    rx_src = tile_to_coord(TILE_CRYPTO);
    // ---- A: Python rows
    for (int r = 0; r < I6_ROWS; r++) begin
      do_reset();
      st = {}; for (int b = 0; b < I6_N_BUSY[r]; b++) st.push_back(3); st.push_back(1);
      trial(st, 5, 1'b0, ok);
      check(ok && n_chal == I6_CHALLENGES[r] && n_done == n_chal && word_diff == 0,
            $sformatf("RETRY_PY_N%0d_CHALLENGES challenges=%0d expected=%0d complete=%0d word_diff=%0d idle=%0b", I6_N_BUSY[r], n_chal, I6_CHALLENGES[r], n_done, word_diff, ok));
      check(ok && (I6_GRANT[r] ? outcome_grant() : outcome_fail(9)),
            $sformatf("RETRY_PY_N%0d_OUTCOME grants=%0d revokes=%0d failed=%0d reason=%0d expected=%s", I6_N_BUSY[r], n_grant, n_revoke, n_failed, last_reason, I6_GRANT[r] ? "GRANT" : "FAIL"));
    end
    // ---- B: other non-1 statuses fail at once

    for (int k = 0; k < 3; k++) begin
      automatic int s = k == 0 ? 2 : k == 1 ? 5 : 10;
      do_reset(); st = {s}; trial(st, 5, 1'b0, ok);
      check(ok && n_chal == 1 && n_revoke == 1 && n_grant == 0, $sformatf("RETRY_STATUS%0d_NO_RETRY challenges=%0d revokes=%0d grants=%0d", s, n_chal, n_revoke, n_grant));
      check(ok && n_failed == 1 && last_reason == 9, $sformatf("RETRY_STATUS%0d_FAIL_REASON failed=%0d reason=%0d", s, n_failed, last_reason));
    end
    // ---- C: counter reset on REVOKE (after a fail) and on GRANT, no hardware reset in between
    do_reset();
    st = {3, 3, 3, 3}; trial(st, 5, 1'b0, ok);
    st = {3, 3, 3, 1}; trial(st, 5, 1'b0, ok);
    check(ok && n_chal == 4 && outcome_grant(), $sformatf("RETRY_RESET_AFTER_FAIL challenges=%0d grants=%0d revokes=%0d failed=%0d", n_chal, n_grant, n_revoke, n_failed));
    do_reset();
    st = {3, 3, 3, 1}; trial(st, 5, 1'b0, ok);
    st = {3, 3, 3, 1}; trial(st, 5, 1'b0, ok);
    check(ok && n_chal == 4 && outcome_grant(), $sformatf("RETRY_RESET_AFTER_GRANT challenges=%0d grants=%0d revokes=%0d failed=%0d", n_chal, n_grant, n_revoke, n_failed));
    // ---- D: timeout inside a retry
    do_reset(); st = {3}; trial(st, 5, 1'b0, ok);
    check(ok && n_failed == 1 && last_reason == 8, $sformatf("RETRY_TIMEOUT_REASON failed=%0d reason=%0d", n_failed, last_reason));
    check(ok && n_chal == 2 && n_revoke == 1 && n_grant == 0, $sformatf("RETRY_TIMEOUT_REVOKE challenges=%0d revokes=%0d grants=%0d", n_chal, n_revoke, n_grant));
    // ---- E: the timer restarts per attempt
    do_reset(); st = {3, 3, 3, 1}; trial(st, 2000, 1'b0, ok);
    check(ok && n_chal == 4 && outcome_grant(), $sformatf("RETRY_TIMER_PER_ATTEMPT challenges=%0d grants=%0d failed=%0d", n_chal, n_grant, n_failed));
    // ---- F: revoke during a retry
    do_reset(); st = {3}; trial(st, 5, 1'b1, ok);
    check(ok && n_revoke == 1 && n_grant == 0 && n_failed == 0, $sformatf("RETRY_REVOKE_DURING revokes=%0d grants=%0d failed=%0d", n_revoke, n_grant, n_failed));
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 24 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #40ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
