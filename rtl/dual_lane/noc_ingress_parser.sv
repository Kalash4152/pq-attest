`timescale 1ns/1ps
// P7 trusted-port ingress parser (M-F1 R7.5b; docs/decisions/P7-INGRESS-REVOCATION-CONTRACT.md sec. 1b). Non-buffering,
// for every NI-driven local port. On each HEAD: source check (reason 9) and the type / dest / length / VC / HEAD_TAIL
// checks (reason 11); a failing packet is consumed whole (to its terminator) and nothing is forwarded. A trusted NI is
// qualified to frame correctly (N-8.1): a mid-packet violation (nested HEAD, VC change, early or overlong TAIL, stray
// flit) is an NI fault - counted and asserted, never repaired, and no flit is fabricated. No watchdog (the NI's W bounds
// its packets). The pass-through is combinational: in_ready = out_ready, out_valid = in_valid, out_flit = in_flit.
module noc_ingress_parser #(
  parameter int PORT = 0,
  parameter bit CHECK_SRC = 1'b1      // mutant hook: 0 disables the source check
)(
  input  logic clk, rst,
  input  noc_pkg::flit_t in_flit,
  input  logic in_valid,
  output logic in_ready,
  output noc_pkg::flit_t out_flit,
  output logic out_valid,
  input  logic out_ready,
  output logic [31:0] rejected_count, fault_count,
  output logic [3:0]  reject_reason
);
  import noc_pkg::*;
  import noc_p7_pkg::*;
  localparam coord_t ME = tile_to_coord(tile_id_e'(PORT));
  typedef enum logic [1:0] {P_IDLE, P_FWD, P_DROP} ps_t;
  ps_t ps;
  head_flit_t h;
  logic is_head, is_ht, is_term, src_ok, head_ok, pass, fwd;
  logic [4:0] wlen, rem;
  logic [1:0] vc_q;
  assign h       = head_flit_t'(in_flit.flit_data);
  assign is_head = in_flit.flit_type == FLIT_HEAD;
  assign is_ht   = in_flit.flit_type == FLIT_HEAD_TAIL;
  assign is_term = in_flit.flit_type == FLIT_TAIL || is_ht;
  assign wlen    = is_control(h.msg_type) ? p7_length(h.msg_type) + 5'd5 : p7_length(h.msg_type);
  assign src_ok  = !CHECK_SRC || (h.src_x == ME.x && h.src_y == ME.y);
  assign head_ok = !h.msg_type[3] && h.dest_x < 3 && h.dest_y < 2 && h.length == wlen &&
                   in_flit.vc_id == 2'(message_to_vc(h.msg_type)) && (is_ht == (wlen == 5'd1));
  assign pass    = ps == P_IDLE && (is_head || is_ht) && src_ok && head_ok;     // a legal HEAD is forwarded
  assign fwd     = ps == P_FWD || pass;
  assign out_flit  = in_flit;
  assign out_valid = in_valid && fwd;
  assign in_ready  = fwd ? out_ready : 1'b1;                                      // rejected / stray flits are consumed
  always_ff @(posedge clk) begin
    if (rst) begin ps <= P_IDLE; rem <= '0; vc_q <= '0; rejected_count <= '0; fault_count <= '0; reject_reason <= '0; end
    else if (in_valid && in_ready) case (ps)
      P_IDLE: if (pass) begin
          if (is_head) begin ps <= P_FWD; rem <= h.length - 5'd1; vc_q <= in_flit.vc_id; end
        end else if (is_head || is_ht) begin
          rejected_count <= rejected_count + 1; reject_reason <= !src_ok ? 4'd9 : 4'd11;
          if (is_head) ps <= P_DROP;
        end else fault_count <= fault_count + 1;                                   // stray flit from a trusted NI
      P_FWD: begin
        if (is_head || is_ht || in_flit.vc_id != vc_q || (rem == 5'd1) != is_term) fault_count <= fault_count + 1;
        if (is_term) ps <= P_IDLE; else if (rem > 5'd1) rem <= rem - 5'd1;
      end
      P_DROP: if (is_term) ps <= P_IDLE;
      default: ps <= P_IDLE;
    endcase
  end
  // synthesis translate_off
  always_ff @(posedge clk) if (!rst && in_valid && in_ready && ps == P_FWD &&
                               (is_head || is_ht || in_flit.vc_id != vc_q || (rem == 5'd1) != is_term))
    $error("noc_ingress_parser: port %0d NI framing fault (nested HEAD, VC change, early or overlong TAIL)", PORT);
  // synthesis translate_on
endmodule

// Packet-atomic two-input merge for port 5 (contract sec. 1c): the quarantine (complete packets only) and the tile-5 NI
// parser share the mesh input. The owner is locked from its HEAD handshake to its terminator handshake; round robin
// between packets. Selection depends only on registered state and the inputs' valid/flit, never on out_ready.
module noc_ingress_merge2 (
  input  logic clk, rst,
  input  noc_pkg::flit_t a_flit, b_flit,
  input  logic a_valid, b_valid,
  output logic a_ready, b_ready,
  output noc_pkg::flit_t out_flit,
  output logic out_valid,
  input  logic out_ready
);
  import noc_pkg::*;
  logic lock, own, pref, sel;            // own/sel: 0 = a, 1 = b
  logic a_head, b_head;
  assign a_head = a_flit.flit_type == FLIT_HEAD || a_flit.flit_type == FLIT_HEAD_TAIL;
  assign b_head = b_flit.flit_type == FLIT_HEAD || b_flit.flit_type == FLIT_HEAD_TAIL;
  assign sel = lock ? own : (a_valid && b_valid) ? pref : b_valid;
  assign out_flit  = sel ? b_flit : a_flit;
  assign out_valid = sel ? b_valid : a_valid;
  assign a_ready = !sel && out_ready;
  assign b_ready =  sel && out_ready;
  always_ff @(posedge clk) begin
    if (rst) begin lock <= 1'b0; own <= 1'b0; pref <= 1'b0; end
    else if (out_valid && out_ready) begin
      if (out_flit.flit_type == FLIT_TAIL || out_flit.flit_type == FLIT_HEAD_TAIL) begin lock <= 1'b0; pref <= !sel; end
      else begin lock <= 1'b1; own <= sel; end
    end
  end
endmodule
