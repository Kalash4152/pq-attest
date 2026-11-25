`timescale 1ns/1ps
//==============================================================================
// pq_attest_endpoint : P6 (M-F1 rev 6) CRYPTO-tile attestation endpoint, TILE_03
// rtl/dual_lane variant only (no production original). Track Q2, I-3 / PQ-2 prep,
// 2026-10-19. State: IMPLEMENTED. NOT compiled, NOT XSim-simulated, NOT
// reference-checked, NOT mutation-tested by Track Q2 (the integrator runs I-3).
// Formal: NO. Hardware: NO.
//
// Contract (R4 PQ-2; S8-2; M-F1 rev 6 R6.1-R6.3, R6.10):
//  * rx_ready = 1 in every cycle (SVA a_rx_ready_always). The parser never stalls
//    the NI; it classifies each packet at its HEAD and drains it.
//  * Reply-to is latched at the HEAD of the served challenge (reply_to) and of the
//    queued busy challenge (drain_to -> busy_to); the live rx_src_coord is never
//    used as a destination.
//  * Crypto (controller_start) starts only after a complete 7-word challenge with
//    HEAD length == message_length(MSG_ATTEST_CHALLENGE), a real terminator
//    (rx_payload_last, not rx_abort) and padding C[223:208] == 0.
//  * One transaction at a time. TX request fields and each TX word are held
//    stable while tx_ready / tx_payload_ready is low (SVAs a_tx_*_stable).
//  * Synchronous reset (rst, active high) clears parser, pending busy reply,
//    TX state, counters and the controller (rst_n = !rst): no reply survives.
//
// OD-2 / K-2 status in tx_control[10:7] of MSG_ATTEST_RESPONSE (16 payload words
// always; all 16 words are zero for every status != 1; tx_control[6:0] = 0).
// The endpoint emits only 1, 2, 3, 5, 10 (Kalash's K-2 restatement):
//   packet at HEAD                         count  reply
//   MEM_* / ATTEST_GRANT / ATTEST_REVOKE   no     none  (application / gate traffic)
//   other non-challenge type (RESPONSE,    +1     none
//     reserved 8..15)
//   challenge, source != RoT (1,1)         +1     none  (no reflection toward SPOOF)
//   RoT challenge while busy               +1     3 at its terminator (one queued;
//                                                  an aborted busy packet, or one
//                                                  arriving while a busy reply is
//                                                  already queued, is count-only)
//   RoT challenge, idle, then:
//     HEAD length != message_length        +1     5
//     payload words != 7 (incl. HEAD_TAIL) +1     5
//     rx_abort before the terminator       +1     5
//     padding C[223:208] != 0              +1     5
//     valid -> controller err, error_code
//       1 (context_len>14) or 2 (config/
//       imem length invalid)               no     2  (request refused by input
//                                                     validation, pq_attest_protocol.sv:500-512)
//     valid -> controller err, other code  no     10
//     valid -> controller done, no err     no     1  (R-B words, R6.2)
// Busy takes priority over malformed (a busy endpoint does not parse the drained
// challenge). Codes 4 and 6..9 are verifier verdicts and are never sent here.
//
// Busy reply (3) and pq_rot_verifier (rev-6 C-1 note; C-2 stays OPEN, verifier
// unchanged): the verifier has one outstanding challenge and no per-cause
// reason. A busy reply that reaches it while it is in V_WAIT is taken as THE
// response (pq_rot_verifier.sv:69-70, :77: status != 1 -> REVOKE). A busy reply
// that arrives while it is in V_CHECK/V_TSTART/V_TWAIT clears `incoming`
// (pq_rot_verifier.sv:69) and so makes the measurement/tag compare (:92, :96)
// fail -> REVOKE. Either way a busy reply can revoke a HEALTHY outstanding
// attestation. This endpoint queues the busy reply behind the in-flight response
// (never before it), which avoids the V_WAIT case for the challenge being
// served, but not the V_CHECK..V_TWAIT case. In the P6-S secure profile only
// the RoT can deliver a challenge (N-9 MAC + sequence), and the RoT issues a
// second challenge only after its own timeout/revoke, so the hazard needs a
// RoT retry racing a slow endpoint. Recorded as open in reports/i3_q2/Q2_NOTES.md.
//
// C-10 OPEN (not changed): config_len / imem_len remain runtime input ports
// forwarded to the controller; fixing them as provisioned TILE_03 constants
// needs pq_noc_subsystem / verifier whitelist changes outside this file.
// K-3 (I-6, Kalash 2026-11-02 "Enforce in HW"): with K3_ENFORCE = 1 a valid
// challenge whose runtime config_len / imem_len differ from the provisioned
// K3_CONFIG_LEN / K3_IMEM_LEN is answered with 5 (malformed) before the
// controller starts, counted, and pulses k3_fault. Default 0 (unit benches).
//==============================================================================
module pq_attest_endpoint #(
  parameter bit       K3_ENFORCE    = 1'b0,
  parameter bit [6:0] K3_CONFIG_LEN = 7'd16,
  parameter bit [6:0] K3_IMEM_LEN   = 7'd16
) (
  input  logic               clk, rst,
  input  logic [255:0]       root_secret,
  input  logic [111:0]       context_in,
  input  logic [3:0]         context_len,
  input  logic [511:0]       config_data, imem,
  input  logic [6:0]         config_len, imem_len,
  input  noc_pkg::coord_t    rx_src_coord,
  input  noc_pkg::msg_type_e rx_msg_type,
  input  logic [4:0]         rx_length,
  input  logic               rx_head_valid,
  input  logic [31:0]        rx_payload_data,
  input  logic               rx_payload_valid, rx_payload_last, rx_abort,
  output logic               rx_ready,
  output logic               tx_valid,
  input  logic               tx_ready,
  output noc_pkg::coord_t    tx_dest_coord,
  output noc_pkg::msg_type_e tx_msg_type,
  output logic [10:0]        tx_control,
  output logic [31:0]        tx_payload_data,
  output logic               tx_payload_valid,
  input  logic               tx_payload_ready,
  output logic               busy,
  output logic [31:0]        rejected_count,
  output logic [775:0]       internal_response,
  output logic               controller_start,
  output logic               k3_fault          // one-cycle pulse: K-3 length mismatch refused
);
  import noc_pkg::*;

  localparam logic [55:0] TILE03       = 56'h33305f454c4954;  // ASCII TILE_03, byte i at [8i +: 8]
  localparam logic [3:0]  ST_SUCCESS   = 4'd1;
  localparam logic [3:0]  ST_REJECT    = 4'd2;
  localparam logic [3:0]  ST_BUSY      = 4'd3;
  localparam logic [3:0]  ST_MALFORMED = 4'd5;
  localparam logic [3:0]  ST_INTERNAL  = 4'd10;
  localparam logic [4:0]  CH_WORDS     = 5'd7;

  // Encodings are referenced numerically by the testbenches (E_WAIT = 3 etc.).
  typedef enum logic [2:0] {E_IDLE, E_VALIDATE, E_START, E_WAIT, E_REQ, E_FILL} es_t;
  typedef enum logic [1:0] {P_NONE, P_SERVE, P_BUSY, P_DROP} pk_t;

  es_t          es;
  pk_t          pk;            // class of the open RX packet
  logic [4:0]   wcount;        // payload words of the open packet (saturates at 31)
  logic         len_bad;       // served challenge HEAD length wrong
  logic [223:0] challenge;
  noc_pkg::coord_t reply_to;   // destination of the current reply
  noc_pkg::coord_t drain_to;   // HEAD source of the open busy packet
  noc_pkg::coord_t busy_to;    // destination of the queued busy reply
  logic         busy_pending;
  logic [79:0]  epoch;
  logic [127:0] nonce;
  logic [3:0]   status_q;
  logic [3:0]   word_index;
  logic         done, err, ctrl_busy;
  logic [2:0]   ctrl_status;
  logic [3:0]   error_code;

  // HEAD classification (combinational on the presented HEAD).
  logic head_ignored, head_challenge, head_from_rot;
  always_comb begin
    head_challenge = (rx_msg_type == MSG_ATTEST_CHALLENGE);
    head_from_rot  = (rx_src_coord == tile_to_coord(TILE_ROT));
    case (rx_msg_type)
      MSG_MEM_RD_REQ, MSG_MEM_RD_RESP, MSG_MEM_WR_REQ, MSG_MEM_WR_RESP,
      MSG_ATTEST_GRANT, MSG_ATTEST_REVOKE: head_ignored = 1'b1;
      default:                             head_ignored = 1'b0;
    endcase
  end

  assign rx_ready = 1'b1;
  assign busy = (es != E_IDLE) || busy_pending;
  assign controller_start = (es == E_START);
  assign tx_valid = (es == E_REQ);
  assign tx_dest_coord = reply_to;
  assign tx_msg_type = MSG_ATTEST_RESPONSE;
  assign tx_control = {status_q, 7'b0};
  assign tx_payload_valid = (es == E_FILL);

  // R-B word map (R6.2): W0..W7 = internal bytes 33..64 (measurement),
  // W8..W15 = internal bytes 65..96 (tag). Zero words for every error status.
  always_comb begin
    tx_payload_data = '0;
    if (status_q == ST_SUCCESS) begin
      if (word_index < 4'd8) tx_payload_data = internal_response[264 + 32*int'(word_index) +: 32];
      else                   tx_payload_data = internal_response[520 + 32*(int'(word_index) - 8) +: 32];
    end
  end

  pq_attestation_controller controller (
    .clk, .rst_n(!rst), .start(controller_start), .tile_id(TILE03), .epoch, .nonce,
    .root_secret, .context_in, .context_len, .config_data, .config_len, .imem, .imem_len,
    .response(internal_response), .busy(ctrl_busy), .done, .err, .status(ctrl_status), .error_code);

  always_ff @(posedge clk) begin
    if (rst) begin
      es <= E_IDLE; pk <= P_NONE; wcount <= '0; len_bad <= 1'b0; challenge <= '0;
      reply_to <= '0; drain_to <= '0; busy_to <= '0; busy_pending <= 1'b0;
      epoch <= '0; nonce <= '0; status_q <= '0; word_index <= '0; rejected_count <= '0; k3_fault <= 1'b0;
    end else begin : run
      logic [2:0] rej_inc;   // rejected packets accounted this cycle
      logic       claimed;   // this cycle already committed a malformed reply
      logic       term;      // the packet of class cur terminates this cycle
      logic       bad_len;
      logic [4:0] words;
      pk_t        cur;
      rej_inc = '0; claimed = 1'b0; term = 1'b0; bad_len = len_bad; words = wcount; cur = pk;
      k3_fault <= 1'b0;

      // (1) Abort closes the open packet; never a crypto terminator.
      if (rx_abort) begin
        if (pk == P_SERVE) begin
          rej_inc = rej_inc + 3'd1; status_q <= ST_MALFORMED; es <= E_REQ; claimed = 1'b1;
        end
        cur = P_NONE;
        pk  <= P_NONE;
      end

      // (2) HEAD: classify. A HEAD over an open served packet supersedes it
      //     (count only; the NI never presents a HEAD inside a packet).
      if (rx_head_valid) begin
        if (cur == P_SERVE) rej_inc = rej_inc + 3'd1;
        words = '0; wcount <= '0;
        if (head_ignored) cur = P_NONE;
        else if (!head_challenge || !head_from_rot) begin
          cur = P_DROP; rej_inc = rej_inc + 3'd1;
        end else if (busy || claimed) begin
          cur = P_BUSY; rej_inc = rej_inc + 3'd1; drain_to <= rx_src_coord;
        end else begin
          cur = P_SERVE; reply_to <= rx_src_coord; challenge <= '0;
          bad_len = (rx_length != message_length(MSG_ATTEST_CHALLENGE));
          len_bad <= bad_len;
        end
        pk   <= cur;
        term = rx_payload_last;               // HEAD_TAIL: zero-payload packet
      end else if (rx_payload_valid && !rx_abort && pk != P_NONE) begin
        if (pk == P_SERVE && wcount < CH_WORDS) challenge[32*wcount +: 32] <= rx_payload_data;
        words = (wcount == 5'd31) ? wcount : wcount + 5'd1;
        wcount <= words;
        term = rx_payload_last;
      end

      // (3) Terminator of the open packet.
      if (term) begin
        case (cur)
          P_SERVE: begin
            if (bad_len || words != CH_WORDS) begin
              rej_inc = rej_inc + 3'd1; status_q <= ST_MALFORMED; es <= E_REQ;
            end else es <= E_VALIDATE;
          end
          P_BUSY: if (!busy_pending) begin
            busy_pending <= 1'b1;
            busy_to <= rx_head_valid ? rx_src_coord : drain_to;
          end
          default: ;
        endcase
        pk <= P_NONE;
      end

      // (4) Transaction FSM.
      case (es)
        E_IDLE: if (busy_pending) begin
          status_q <= ST_BUSY; reply_to <= busy_to; busy_pending <= 1'b0; es <= E_REQ;
        end
        E_VALIDATE: if (challenge[223:208] != 16'h0) begin
          rej_inc = rej_inc + 3'd1; status_q <= ST_MALFORMED; es <= E_REQ;
        end else if (K3_ENFORCE && (config_len != K3_CONFIG_LEN || imem_len != K3_IMEM_LEN)) begin
          rej_inc = rej_inc + 3'd1; status_q <= ST_MALFORMED; es <= E_REQ; k3_fault <= 1'b1;   // K-3
        end else begin
          epoch <= challenge[79:0];
          nonce <= challenge[207:80];
          es <= E_START;
        end
        E_START: es <= E_WAIT;
        E_WAIT: if (done) begin
          if (!err)                                    status_q <= ST_SUCCESS;
          else if (error_code == 4'd1 || error_code == 4'd2) status_q <= ST_REJECT;
          else                                         status_q <= ST_INTERNAL;
          es <= E_REQ;
        end
        E_REQ: if (tx_ready) begin word_index <= '0; es <= E_FILL; end
        E_FILL: if (tx_payload_ready) begin
          if (word_index == 4'd15) es <= E_IDLE;
          else word_index <= word_index + 4'd1;
        end
        default: es <= E_IDLE;
      endcase

      rejected_count <= rejected_count + 32'(rej_inc);
    end
  end

`ifndef SYNTHESIS
  // Fail actions print [FAIL] lines (never an "Error:" diagnostic) so that a
  // mutant run stays adjudicable; any such line makes a control run INVALID.
  a_rx_ready_always: assert property (@(posedge clk) disable iff (rst) rx_ready === 1'b1)
    else $display("[FAIL] SVA_RX_READY_ALWAYS time=%0t", $time);
  a_tx_request_stable: assert property (@(posedge clk) disable iff (rst)
      (tx_valid && !tx_ready) |=> (tx_valid && $stable(tx_dest_coord) && $stable(tx_msg_type) && $stable(tx_control)))
    else $display("[FAIL] SVA_TX_REQUEST_STABLE time=%0t", $time);
  a_tx_word_stable: assert property (@(posedge clk) disable iff (rst)
      (tx_payload_valid && !tx_payload_ready) |=> (tx_payload_valid && $stable(tx_payload_data)))
    else $display("[FAIL] SVA_TX_WORD_STABLE time=%0t", $time);
  a_status_legal: assert property (@(posedge clk) disable iff (rst)
      tx_valid |-> ((tx_control[10:7] inside {ST_SUCCESS, ST_REJECT, ST_BUSY, ST_MALFORMED, ST_INTERNAL}) && tx_control[6:0] == 7'd0))
    else $display("[FAIL] SVA_STATUS_LEGAL time=%0t", $time);
  a_error_words_zero: assert property (@(posedge clk) disable iff (rst)
      (tx_payload_valid && status_q != ST_SUCCESS) |-> (tx_payload_data == 32'd0))
    else $display("[FAIL] SVA_ERROR_WORDS_ZERO time=%0t", $time);
`endif
endmodule
