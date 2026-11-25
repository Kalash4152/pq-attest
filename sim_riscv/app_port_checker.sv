`timescale 1ns / 1ps
//=============================================================================
// app_port_checker  --  simulation-only protocol checker for ONE tile's Lane 1 application port (brief v2 B5)
//
// Bind it to any module that has the app port, e.g.
//   bind tmem_app_bridge app_port_checker #(.SELF_TILE(TILE_ID), .TIMEOUT_CYCLES(BRIDGE_TIMEOUT),
//                                           .RELEASE_CYCLES(LATE_DRAIN_CYCLES)) u_b5 (
//     .clk, .rst, .authorized(authorized_i), .app_valid(app_valid_o), .app_ready(app_ready_i), ...);
// Specs: brief v2 sec. B5; M-F1 rev 8 sec. 3-6; the main session's B5 task message (2026-11-06).
//
// Properties (a violation prints "[FAIL] B5_<PROPERTY> t=... <detail>", never an Error: line, and increments the
// matching counter, so a run stays adjudicable):
//   B5_HEAD_STABLE      app_valid without app_ready: next cycle app_valid still high and destination / message / control
//                       unchanged. app_valid may drop without app_ready only (1) when authorized = 0 (revocation
//                       withdraws the HEAD, M-F1 rev 8 sec. 3 rule 4), or (2) after it was held for TIMEOUT_CYCLES
//                       (the sender's BRIDGE_TIMEOUT: sec. 3 rule 6 makes a held-off HEAD a wait covered by the timeout),
//                       or (3) the cycle after app_tx_error (the NI rejected the request).
//                       Field changes while held always fire.
//   B5_PAYLOAD_STABLE   app_payload_valid without app_payload_ready: next cycle still valid, app_payload unchanged
//                       (valid may drop only the cycle after app_tx_error, or once TIMEOUT_CYCLES have passed since the
//                       request's HEAD was first raised: the sender's timeout also covers a held-off payload word).
//   B5_VALID_UNAUTH     app_valid high while authorized = 0.
//   B5_ONE_OUTSTANDING  a new HEAD (app_valid rising) while a request is outstanding. A request is outstanding from its
//                       HEAD handshake until the first of: app_rx_last, app_rx_abort, app_tx_error, or RELEASE_CYCLES
//                       cycles. RELEASE_CYCLES = the sender's late-response drain (>= NI slot timeout): a sender that times
//                       out must still drop app_rx for that long, so its next HEAD cannot come earlier (tmem_app_bridge:
//                       LATE_DRAIN_CYCLES). A sender without the drain re-issues about BRIDGE_TIMEOUT cycles after the HEAD.
//   B5_PAYLOAD_COUNT    payload handshakes per request: 2 for MSG_MEM_WR_REQ, 1 for MSG_MEM_RD_REQ. Too many (a handshake
//                       beyond the count, or with no request open) fires at once (a cycle with
//                       app_tx_error is a rejection, not a transfer); too few fires when the response HEAD,
//                       the terminator or the next HEAD arrives first. app_tx_error ends the count without a check.
//   B5_MSG_LEGAL        app_valid with app_message not in {MSG_MEM_RD_REQ (0), MSG_MEM_WR_REQ (2)}.
//   B5_DEST_LEGAL       app_valid with a destination outside the 3 x 2 mesh, or equal to the tile's own coordinate.
// Not covered here: "every request ends in exactly one of response / error / timeout" needs the sender's TMEM side;
// tmem_app_bridge's bench checks it (B1_COUNTS: responses == grants).
//=============================================================================
module app_port_checker #(
    parameter int SELF_TILE      = 3,
    parameter int TIMEOUT_CYCLES = 4096,       // sender's BRIDGE_TIMEOUT
    parameter int RELEASE_CYCLES = 8192,       // sender's LATE_DRAIN_CYCLES
    parameter bit REPORT         = 1           // 0: count only, no [FAIL] lines (directed negative-injection instances; Lane 1 2026-11-07)
)(
    input logic                 clk,
    input logic                 rst,
    input logic                 authorized,
    input logic                 app_valid,
    input logic                 app_ready,
    input noc_pkg::coord_t      app_destination,
    input noc_pkg::msg_type_e   app_message,
    input logic [10:0]          app_control,
    input logic [31:0]          app_payload,
    input logic                 app_payload_valid,
    input logic                 app_payload_ready,
    input logic                 app_tx_error,
    input logic                 app_rx_head_valid,
    input logic                 app_rx_last,
    input logic                 app_rx_abort
);
    import noc_pkg::*;

    int n_head_stable = 0, n_payload_stable = 0, n_valid_unauth = 0, n_one_outstanding = 0, n_payload_count = 0,
        n_msg_legal = 0, n_dest_legal = 0;
    function automatic int total();
        return n_head_stable + n_payload_stable + n_valid_unauth + n_one_outstanding + n_payload_count + n_msg_legal +
               n_dest_legal;
    endfunction

    coord_t self_c;
    assign self_c = tile_to_coord(tile_id_e'(SELF_TILE));

    // previous-cycle samples
    logic      v_q = 0, r_q = 0, pv_q = 0, pr_q = 0, txe_q = 0;
    coord_t    d_q;
    msg_type_e m_q;
    logic [10:0] c_q;
    logic [31:0] p_q;
    // request tracking
    bit outstanding = 0;   int age = 0;   int held = 0;   int since_head = 0;
    bit counting = 0;      int pcount = 0, pexp = 0;

    always @(posedge clk) begin
        if (rst) begin
            v_q <= 0; r_q <= 0; pv_q <= 0; pr_q <= 0; txe_q <= 0; held = 0; outstanding = 0; age = 0; counting = 0; pcount = 0;
        end else begin
            // (a) HEAD stable until ready (withdrawal allowed only on revocation)
            if (v_q && !r_q) begin
                if (!app_valid && authorized && held < TIMEOUT_CYCLES && !txe_q) begin
                    n_head_stable++; if (REPORT) $display("[FAIL] B5_HEAD_STABLE t=%0t app_valid dropped before app_ready after %0d cycles", $time, held);
                end else if (app_valid && (app_destination != d_q || app_message != m_q || app_control != c_q)) begin
                    n_head_stable++; if (REPORT) $display("[FAIL] B5_HEAD_STABLE t=%0t fields changed before app_ready", $time);
                end
            end
            // (b) payload stable until ready
            if (pv_q && !pr_q) begin
                if ((!app_payload_valid && !txe_q && since_head < TIMEOUT_CYCLES) || (app_payload_valid && app_payload != p_q)) begin
                    n_payload_stable++;
                    if (REPORT) $display("[FAIL] B5_PAYLOAD_STABLE t=%0t valid=%0b payload %h -> %h", $time, app_payload_valid, p_q, app_payload);
                end
            end
            // (c) never valid while unauthorized
            if (app_valid && !authorized) begin
                n_valid_unauth++; if (REPORT) $display("[FAIL] B5_VALID_UNAUTH t=%0t", $time);
            end
            // message / destination legality
            if (app_valid && app_message != MSG_MEM_RD_REQ && app_message != MSG_MEM_WR_REQ) begin
                n_msg_legal++; if (REPORT) $display("[FAIL] B5_MSG_LEGAL t=%0t message=%0d", $time, app_message);
            end
            if (app_valid && (app_destination.x >= 3 || app_destination.y >= 2 || app_destination == self_c)) begin
                n_dest_legal++; if (REPORT) $display("[FAIL] B5_DEST_LEGAL t=%0t dest=(%0d,%0d)", $time, app_destination.x, app_destination.y);
            end

            // (e) payload count: too few, checked when the request's next event arrives
            if (counting && pcount < pexp && (app_rx_head_valid || app_rx_last || (app_valid && !v_q))) begin
                n_payload_count++;
                if (REPORT) $display("[FAIL] B5_PAYLOAD_COUNT t=%0t %0d of %0d payload words before the next event", $time, pcount, pexp);
                counting = 0;
            end
            // (d) one outstanding: a new HEAD while the previous request is still open
            if (app_valid && !v_q && outstanding) begin
                n_one_outstanding++; if (REPORT) $display("[FAIL] B5_ONE_OUTSTANDING t=%0t new HEAD %0d cycles after the previous one", $time, age);
            end
            // request close
            if (outstanding) begin
                age++;
                if (app_rx_last || app_rx_abort || app_tx_error || age >= RELEASE_CYCLES) begin outstanding = 0; counting = 0; end
            end
            if (app_tx_error) counting = 0;
            // (e) payload count: too many
            if (app_payload_valid && app_payload_ready && !app_tx_error) begin
                if (!counting || pcount >= pexp) begin
                    n_payload_count++; if (REPORT) $display("[FAIL] B5_PAYLOAD_COUNT t=%0t extra payload word (%0d expected)", $time, pexp);
                end else begin
                    pcount++;
                    if (pcount == pexp) counting = 0;
                end
            end
            // request open
            if (app_valid && app_ready) begin
                outstanding = 1; age = 0;
                counting = 1; pcount = 0; pexp = (app_message == MSG_MEM_WR_REQ) ? 2 : 1;
            end
            held = (app_valid && !app_ready) ? held + 1 : 0;
            since_head = (app_valid && !v_q) ? 0 : since_head + 1;
            v_q <= app_valid; r_q <= app_ready; txe_q <= app_tx_error; d_q <= app_destination; m_q <= app_message; c_q <= app_control;
            pv_q <= app_payload_valid; pr_q <= app_payload_ready; p_q <= app_payload;
        end
    end
endmodule
