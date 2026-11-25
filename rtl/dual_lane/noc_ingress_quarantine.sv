`timescale 1ns/1ps
// P7 raw-port quarantine (M-F1 R7.5b; docs/decisions/P7-INGRESS-REVOCATION-CONTRACT.md sec. 1a). Store-and-forward for
// the untrusted protocol-level local injector at tile 5: only a complete, validated packet is ever offered to the mesh.
//  - 32-deep flit FIFO (LUTRAM; the array is never reset, only pointers): wr = write, cm = commit, rd = read. A partial
//    packet lives in [cm, wr); discarding it rolls wr back to cm.
//  - HEAD checks: src == PORT (reason 9); msg_type legal (0-7), dest inside the mesh, length == P7 wire length
//    (control: p7_length + 5 freshness flits; data: p7_length), vc == message_to_vc, HEAD_TAIL iff length 1 (reason 11).
//  - Continuation checks: BODY/TAIL only (a nested HEAD/HEAD_TAIL discards the packet), the HEAD's VC, TAIL exactly at
//    flit `length` (early TAIL or overlong discards). Reason 11; the input then resyncs (consumes until the next HEAD).
//  - Gap discard: gap counts only cycles with a partial packet buffered AND in_valid == 0 AND in_ready == 1; it resets on
//    every accepted flit; at W_Q the partial packet is discarded (reason 10) and the input resyncs.
//  - Output: committed flits only, in order; a packet is committed whole, so it is offered back to back.
module noc_ingress_quarantine #(
  parameter int PORT = 5,
  parameter int W_Q  = 64,
  parameter bit SRC_CHECK     = 1'b1,   // mutant hooks (contract sec. 1d, sec. 8): 0 = source check off
  parameter bit NESTED_CHECK  = 1'b1,   //   0 = nested HEAD accepted as a body flit
  parameter bit GAP_NEEDS_READY = 1'b1, //   0 = gap also counts cycles with in_ready == 0
  parameter bit LENGTH_CAP    = 1'b1,   //   0 = no overlong discard (BODY at the last position is buffered)
  parameter bit COMMIT_WHOLE  = 1'b1    //   0 = flits are offered as soon as written (partial forwarding)
)(
  input  logic clk, rst,
  input  noc_pkg::flit_t in_flit,
  input  logic in_valid,
  output logic in_ready,
  output noc_pkg::flit_t out_flit,
  output logic out_valid,
  input  logic out_ready,
  output logic [31:0] q_rejected, q_forwarded, q_discarded,
  output logic [3:0]  q_reason
);
  import noc_pkg::*;
  import noc_p7_pkg::*;
  localparam int DEPTH = 32;
  localparam coord_t ME = tile_to_coord(tile_id_e'(PORT));
  typedef enum logic [1:0] {S_HEAD, S_BODY, S_SYNC} qs_t;
  qs_t qs;
  flit_t mem [DEPTH];
  logic [5:0] wr, cm, rd;
  logic [4:0] rem;                      // flits still expected in the current packet
  logic [1:0] vc_q;
  logic [$clog2(W_Q+1)-1:0] gap;
  head_flit_t h;
  logic is_head, is_ht, is_tail, full, acc, head_ok, src_ok;
  logic [4:0] wlen;
  assign h       = head_flit_t'(in_flit.flit_data);
  assign is_head = in_flit.flit_type == FLIT_HEAD;
  assign is_ht   = in_flit.flit_type == FLIT_HEAD_TAIL;
  assign is_tail = in_flit.flit_type == FLIT_TAIL;
  assign full    = (wr - rd) == 6'(DEPTH);
  assign in_ready = !full || (qs == S_SYNC && !is_head && !is_ht);   // a HEAD is taken only when it can be stored
  assign acc     = in_valid && in_ready;
  assign wlen    = is_control(h.msg_type) ? p7_length(h.msg_type) + 5'd5 : p7_length(h.msg_type);
  assign src_ok  = !SRC_CHECK || (h.src_x == ME.x && h.src_y == ME.y);
  assign head_ok = !h.msg_type[3] && h.dest_x < 3 && h.dest_y < 2 && h.length == wlen &&
                   in_flit.vc_id == 2'(message_to_vc(h.msg_type)) && (is_ht == (wlen == 5'd1));
  // output: committed flits (or, under the partial-forwarding mutant, every written flit)
  assign out_valid = COMMIT_WHOLE ? (rd != cm) : (rd != wr);
  assign out_flit  = mem[rd[4:0]];
  always_ff @(posedge clk) if (acc && (qs != S_SYNC || is_head || is_ht) && !full) mem[wr[4:0]] <= in_flit;
  always_ff @(posedge clk) begin
    if (rst) begin
      qs <= S_HEAD; wr <= '0; cm <= '0; rd <= '0; rem <= '0; vc_q <= '0; gap <= '0;
      q_rejected <= '0; q_forwarded <= '0; q_discarded <= '0; q_reason <= '0;
    end else begin
      if (out_valid && out_ready) begin
        rd <= rd + 6'd1;
        if (out_flit.flit_type == FLIT_TAIL || out_flit.flit_type == FLIT_HEAD_TAIL) q_forwarded <= q_forwarded + 1;
      end
      case (qs)
        S_HEAD, S_SYNC: if (acc) begin
          if (is_head || is_ht) begin
            if (!src_ok || !head_ok) begin
              q_rejected <= q_rejected + 1; q_reason <= !src_ok ? 4'd9 : 4'd11; q_discarded <= q_discarded + 1;
              qs <= is_ht ? S_HEAD : S_SYNC;
            end else if (is_ht) begin
              wr <= wr + 6'd1; cm <= wr + 6'd1; qs <= S_HEAD;
            end else begin
              wr <= wr + 6'd1; rem <= h.length - 5'd1; vc_q <= in_flit.vc_id; gap <= '0; qs <= S_BODY;
            end
          end else if (qs == S_HEAD) begin                    // stray BODY/TAIL outside a packet
            q_rejected <= q_rejected + 1; q_reason <= 4'd11; q_discarded <= q_discarded + 1;
            qs <= is_tail ? S_HEAD : S_SYNC;
          end
        end
        S_BODY: begin
          if (acc) begin
            gap <= '0;
            if (((is_head || is_ht) && NESTED_CHECK) || in_flit.vc_id != vc_q ||
                (rem == 5'd1 && !is_tail && LENGTH_CAP) || (rem > 5'd1 && is_tail)) begin
              wr <= cm; q_rejected <= q_rejected + 1; q_reason <= 4'd11; q_discarded <= q_discarded + 1;
              qs <= is_tail ? S_HEAD : S_SYNC;                // early TAIL ends the packet; else resync
            end else begin
              wr <= wr + 6'd1;
              if (is_tail) begin cm <= wr + 6'd1; qs <= S_HEAD; end
              else if (rem > 5'd1) rem <= rem - 5'd1;
            end
          end else if (!in_valid && (in_ready || !GAP_NEEDS_READY)) begin
            if (gap == ($clog2(W_Q+1))'(W_Q - 1)) begin
              wr <= cm; q_rejected <= q_rejected + 1; q_reason <= 4'd10; q_discarded <= q_discarded + 1; qs <= S_SYNC;
            end else gap <= gap + 1'b1;
          end
        end
        default: qs <= S_HEAD;
      endcase
    end
  end
  // synthesis translate_off
  always_ff @(posedge clk) if (!rst && COMMIT_WHOLE && out_valid && rd == cm) $error("noc_ingress_quarantine: uncommitted flit offered");
  // synthesis translate_on
endmodule
