`timescale 1ns/1ps
// P7 ingress guard for one local mesh port g (M-F1 rev 7 R7.5 + C1, R7.5a / decision D1). Sits between the tile side
// (NI or raw port) and the mesh's tile_in; the router is untouched.
//  - Source check (R7.5, C1): a HEAD / HEAD_TAIL whose stamped src != g is dropped with its whole packet through the
//    terminator (reason 9). The dropped flits are consumed here, so nothing enters the mesh and no credit is used.
//    A non-HEAD flit outside a packet has no stamped source; it is discarded and counted with reason 9 as well.
//  - Completion watchdog (R7.5a, D1): while forwarding an accepted packet, cycles in which the sender presents no flit
//    are counted (mesh backpressure is not). At W_ING the packet is force-terminated: one synthetic TAIL (data 0, the
//    packet's VC) is sent, releasing every wormhole lock on the path; the receiver rejects the truncated packet by its
//    framing rules. The sender's remaining flits up to its own terminator are then discarded here (reason 10, counted
//    once at the forced termination).
// The forwarding path is combinational (in_ready = out_ready, out_valid = in_valid); C1 requires the mesh timing recheck.
module noc_ingress_guard #(
  parameter int PORT = 0,
  parameter int W_ING = 64,
  parameter bit CHECK_SRC = 1'b1,    // mutant hook: 0 disables the source check
  parameter bit WATCHDOG  = 1'b1     // mutant hook: 0 disables the completion watchdog
)(
  input  logic clk, rst,
  input  noc_pkg::flit_t in_flit,
  input  logic in_valid,
  output logic in_ready,
  output noc_pkg::flit_t out_flit,
  output logic out_valid,
  input  logic out_ready,
  output logic [31:0] rejected_count,
  output logic [3:0]  reject_reason
);
  import noc_pkg::*;
  typedef enum logic [2:0] {G_IDLE, G_FWD, G_DROP, G_TAIL, G_REST} gs_t;
  gs_t gs;
  logic [1:0] vc_q;
  logic [6:0] stall;
  head_flit_t h;
  logic is_head, is_term, src_ok;
  localparam coord_t ME = tile_to_coord(tile_id_e'(PORT));
  assign h = head_flit_t'(in_flit.flit_data);
  assign is_head = in_flit.flit_type == FLIT_HEAD || in_flit.flit_type == FLIT_HEAD_TAIL;
  assign is_term = in_flit.flit_type == FLIT_TAIL || in_flit.flit_type == FLIT_HEAD_TAIL;
  assign src_ok = !CHECK_SRC || (h.src_x == ME.x && h.src_y == ME.y);
  always_comb begin
    out_flit = in_flit; out_valid = 1'b0; in_ready = 1'b0;
    case (gs)
      G_IDLE: if (in_valid) begin
        if (is_head && src_ok) begin out_valid = 1'b1; in_ready = out_ready; end
        else in_ready = 1'b1;                                   // forged HEAD or stray flit: consumed, never forwarded
      end
      G_FWD:  begin out_valid = in_valid; in_ready = out_ready; end
      G_TAIL: begin out_valid = 1'b1; out_flit = '0; out_flit.flit_type = FLIT_TAIL; out_flit.vc_id = vc_q; end
      G_DROP, G_REST: in_ready = 1'b1;
      default: ;
    endcase
  end
  always_ff @(posedge clk) begin
    if (rst) begin gs <= G_IDLE; vc_q <= '0; stall <= '0; rejected_count <= '0; reject_reason <= '0; end
    else case (gs)
      G_IDLE: if (in_valid) begin
        if (is_head && src_ok) begin
          if (out_ready && in_flit.flit_type == FLIT_HEAD) begin gs <= G_FWD; vc_q <= in_flit.vc_id; stall <= '0; end
        end else begin
          rejected_count <= rejected_count + 1; reject_reason <= 4'd9;
          if (is_head && !is_term) gs <= G_DROP;
        end
      end
      G_FWD: begin
        if (in_valid) begin if (out_ready && is_term) gs <= G_IDLE; end
        else if (WATCHDOG) begin
          if (stall == 7'(W_ING - 1)) gs <= G_TAIL; else stall <= stall + 7'd1;
        end
      end
      G_TAIL: if (out_ready) begin gs <= G_REST; rejected_count <= rejected_count + 1; reject_reason <= 4'd10; end
      G_DROP, G_REST: if (in_valid && is_term) gs <= G_IDLE;
      default: gs <= G_IDLE;
    endcase
  end
endmodule
