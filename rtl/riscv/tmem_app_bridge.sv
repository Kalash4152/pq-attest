`timescale 1ns / 1ps
//=============================================================================
// tmem_app_bridge  --  TMEM (CPU tile remote-memory port) -> Lane 1 application port (brief v2 B1, task R2.1)
//
// Specs: docs/handoff/BRIEF_RISCV_LANE_v2_20261101.md sec. B1; docs/decisions/M-F1-rev8-INTEGRATION-DRAFT.md sec. 3-6;
// TMEM side: docs/riscv_lane/CPU_MEMORY_CONTRACT.md sec. 4-8 (grant any time, response >= 1 cycle after grant,
// exactly one response per granted request, one outstanding, read error returns 0, write error has no side effect).
//
// Behaviour
//  - One request at a time. IDLE grants a TMEM request in the same cycle and latches it.
//  - Local refusal (no network traffic, tmem_err on the next cycle = within 2 cycles of the request):
//      * decode: T = addr[27:24]; T != MEM_TILE, T >= 6 or T == TILE_ID; also addr[31:28] != 4'h2 or addr[1:0] != 0;
//      * tmem_is_fetch_i = 1: a remote instruction fetch is refused (executing NoC-fetched code would bypass the
//        measured / attested IMEM); same path and status code (1) as a decode refusal;
//      * authorized_i = 0 (contract sec. 3 rule 4): app_valid is NEVER raised while authorized_i = 0.
//  - Otherwise: HEAD (app_valid, held until app_ready), then payload word 0 = {REMOTE_PREFIX_OUT, addr[27:2], 2'b00},
//    then (writes) word 1 = wdata. app_control = {wstrb, 6'b0, 1'b0} for writes, '0 for reads (tag bit owned by the NI).
//  - Response on app_rx: HEAD (src must be MEM_TILE, msg must be the matching RESP type), optional data words, terminator.
//    control[10] = err, app_rx_abort, a wrong src / msg, or app_tx_error -> tmem_err. Read errors return 0.
//  - BRIDGE_TIMEOUT cycles after the HEAD is offered -> tmem_err. If the HEAD had been accepted, the bridge then DRAINS:
//    it grants nothing new and discards app_rx traffic until the late response's terminator / abort, or LATE_DRAIN_CYCLES
//    (>= the NI slot timeout, after which the NI drops a stale response itself, contract sec. 6). A late response is
//    therefore never delivered to the CPU and never matched to a later request.
//=============================================================================
module tmem_app_bridge #(
    parameter int          TILE_ID           = 3,
    parameter int          MEM_TILE          = 2,
    parameter logic [3:0]  REMOTE_PREFIX_OUT = 4'h2,
    parameter int          BRIDGE_TIMEOUT    = 4096,   // D7
    parameter int          NI_SLOT_TIMEOUT   = 8192,   // NI slot timeout of the merged build
    parameter int          LATE_DRAIN_CYCLES = 8192    // must be >= NI_SLOT_TIMEOUT (checked at elaboration)
)(
    input  logic                 clk,
    input  logic                 rst,                 // synchronous, active high
    // TMEM (from tile_top)
    input  logic                 tmem_req_i,
    input  logic                 tmem_we_i,
    input  logic [31:0]          tmem_addr_i,
    input  logic [31:0]          tmem_wdata_i,
    input  logic [3:0]           tmem_wstrb_i,
    input  logic                 tmem_is_fetch_i,
    output logic                 tmem_gnt_o,
    output logic                 tmem_rvalid_o,
    output logic [31:0]          tmem_rdata_o,
    output logic                 tmem_err_o,
    // authorization (subsystem authorized[g])
    input  logic                 authorized_i,
    // app TX (M-F1 rev 8 sec. 3)
    output logic                 app_valid_o,
    input  logic                 app_ready_i,
    output noc_pkg::coord_t      app_destination_o,
    output noc_pkg::msg_type_e   app_message_o,
    output logic [10:0]          app_control_o,
    output logic [31:0]          app_payload_o,
    output logic                 app_payload_valid_o,
    input  logic                 app_payload_ready_i,
    input  logic                 app_tx_error_i,
    // app_rx (sec. 4; always accepted)
    input  logic                 app_rx_head_valid_i,
    input  noc_pkg::coord_t      app_rx_src_i,
    input  noc_pkg::msg_type_e   app_rx_msg_i,
    input  logic [10:0]          app_rx_control_i,
    input  logic [31:0]          app_rx_data_i,
    input  logic                 app_rx_data_valid_i,
    input  logic                 app_rx_last_i,
    input  logic                 app_rx_abort_i,
    // status (for the STATUS block / debug)
    output logic [2:0]           last_err_kind_o,     // 0 none, 1 decode, 2 refused, 3 remote err, 4 timeout
    output logic [15:0]          timeout_count_o,
    output logic [15:0]          refused_count_o
);
    import noc_pkg::*;

    // After the bridge times out, the NI can still deliver the late response until its slot timeout frees the slot,
    // so the bridge must keep dropping app_rx traffic for at least that long (main-session decision, B1 question 1).
    generate
        if (BRIDGE_TIMEOUT < 1 || NI_SLOT_TIMEOUT < 1 || NI_SLOT_TIMEOUT > 65536 || LATE_DRAIN_CYCLES < 1) begin : g_bad_timeout_range
            $fatal(1, "tmem_app_bridge: positive timeout required; NI_SLOT_TIMEOUT must fit the 16-bit age counter");
        end
        if (NI_SLOT_TIMEOUT <= BRIDGE_TIMEOUT) begin : g_bad_timeout_order
            $fatal(1,"tmem_app_bridge: NI_SLOT_TIMEOUT must exceed BRIDGE_TIMEOUT");
        end
        if (LATE_DRAIN_CYCLES < NI_SLOT_TIMEOUT) begin : g_bad_drain
            $fatal(1, "tmem_app_bridge: LATE_DRAIN_CYCLES (%0d) < NI_SLOT_TIMEOUT (%0d)", LATE_DRAIN_CYCLES, NI_SLOT_TIMEOUT);
        end
    endgenerate

    typedef enum logic [2:0] {S_IDLE, S_LOCAL_ERR, S_HEAD, S_P0, S_P1, S_WAIT, S_RESP, S_DRAIN} st_e;
    st_e st;

    logic        we_q;
    logic [31:0] addr_q, wdata_q, rdata_q;
    logic [3:0]  wstrb_q;
    logic        err_q, head_seen_q, head_acc_q;
    logic [$clog2(BRIDGE_TIMEOUT+1)-1:0]    tmo_q;
    logic [$clog2(LATE_DRAIN_CYCLES+1)-1:0] drain_q;

    // ---------------------------------------------------------------- decode (combinational, on the live request)
    logic [3:0] t_req;
    logic       decode_bad;
    assign t_req      = tmem_addr_i[27:24];
    assign decode_bad = (tmem_addr_i[31:28] != 4'h2) || (tmem_addr_i[1:0] != 2'b00) ||
                        (t_req != 4'(MEM_TILE)) || (t_req >= 4'd6) || (t_req == 4'(TILE_ID)) ||
                        tmem_is_fetch_i;   // remote instruction fetch refused: code must come from the measured IMEM

    msg_type_e exp_resp;
    assign exp_resp = we_q ? MSG_MEM_WR_RESP : MSG_MEM_RD_RESP;

    // ---------------------------------------------------------------- TMEM outputs
    assign tmem_gnt_o    = (st == S_IDLE) && tmem_req_i;
    assign tmem_rvalid_o = (st == S_RESP) || (st == S_LOCAL_ERR);
    assign tmem_err_o    = (st == S_LOCAL_ERR) || ((st == S_RESP) && err_q);
    assign tmem_rdata_o  = ((st == S_RESP) && !err_q && !we_q) ? rdata_q : 32'h0;

    // ---------------------------------------------------------------- app TX outputs
    assign app_valid_o         = (st == S_HEAD) && authorized_i;           // never while not authorized
    assign app_destination_o   = tile_to_coord(tile_id_e'(MEM_TILE));
    assign app_message_o       = we_q ? MSG_MEM_WR_REQ : MSG_MEM_RD_REQ;
    assign app_control_o       = we_q ? {wstrb_q, 6'b0, 1'b0} : 11'h000;
    assign app_payload_valid_o = (st == S_P0) || (st == S_P1);
    assign app_payload_o       = (st == S_P0) ? {REMOTE_PREFIX_OUT, addr_q[27:2], 2'b00} : wdata_q;

    // ---------------------------------------------------------------- state machine
    always_ff @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; we_q <= 1'b0; addr_q <= '0; wdata_q <= '0; wstrb_q <= '0; rdata_q <= '0;
            err_q <= 1'b0; head_seen_q <= 1'b0; head_acc_q <= 1'b0; tmo_q <= '0; drain_q <= '0;
            last_err_kind_o <= 3'd0; timeout_count_o <= '0; refused_count_o <= '0;
        end else begin
            case (st)
                S_IDLE: if (tmem_req_i) begin                                       // granted this cycle
                    we_q <= tmem_we_i; addr_q <= tmem_addr_i; wdata_q <= tmem_wdata_i; wstrb_q <= tmem_wstrb_i;
                    err_q <= 1'b0; head_seen_q <= 1'b0; head_acc_q <= 1'b0; rdata_q <= '0; tmo_q <= '0;
                    if (decode_bad) begin
                        st <= S_LOCAL_ERR; last_err_kind_o <= 3'd1;
                    end else if (!authorized_i) begin
                        st <= S_LOCAL_ERR; last_err_kind_o <= 3'd2; refused_count_o <= refused_count_o + 1'b1;
                    end else
                        st <= S_HEAD;
                end
                S_LOCAL_ERR: st <= S_IDLE;                                           // one error response
                S_HEAD: begin
                    if (!authorized_i) begin                                         // revoked before the HEAD went out
                        st <= S_LOCAL_ERR; last_err_kind_o <= 3'd2; refused_count_o <= refused_count_o + 1'b1;
                    end else if (app_tx_error_i) begin
                        st <= S_LOCAL_ERR; last_err_kind_o <= 3'd3;
                    end else if (app_ready_i) begin
                        st <= S_P0; head_acc_q <= 1'b1;
                    end else if (tmo_q == BRIDGE_TIMEOUT[$bits(tmo_q)-1:0] - 1'b1) begin
                        st <= S_LOCAL_ERR; last_err_kind_o <= 3'd4; timeout_count_o <= timeout_count_o + 1'b1;
                    end else tmo_q <= tmo_q + 1'b1;
                end
                S_P0, S_P1: begin
                    if (app_tx_error_i) begin
                        err_q <= 1'b1; st <= S_RESP; last_err_kind_o <= 3'd3;
                    end else if (app_payload_ready_i) begin
                        st <= (st == S_P0 && we_q) ? S_P1 : S_WAIT;
                    end
                    if (tmo_q == BRIDGE_TIMEOUT[$bits(tmo_q)-1:0] - 1'b1) begin
                        err_q <= 1'b1; st <= S_RESP; last_err_kind_o <= 3'd4; timeout_count_o <= timeout_count_o + 1'b1;
                        drain_q <= '0;
                    end else tmo_q <= tmo_q + 1'b1;
                end
                S_WAIT: begin
                    if (app_rx_head_valid_i) begin
                        head_seen_q <= 1'b1;
                        if (app_rx_control_i[10] || app_rx_src_i != tile_to_coord(tile_id_e'(MEM_TILE)) ||
                            app_rx_msg_i != exp_resp) err_q <= 1'b1;
                    end
                    if (app_rx_data_valid_i) rdata_q <= app_rx_data_i;
                    if (app_rx_abort_i) begin
                        err_q <= 1'b1; st <= S_RESP; last_err_kind_o <= 3'd3;
                    end else if (app_rx_last_i) begin
                        st <= S_RESP;
                        if (app_rx_control_i[10] && app_rx_head_valid_i) last_err_kind_o <= 3'd3;
                        else if (err_q) last_err_kind_o <= 3'd3;
                    end else if (tmo_q == BRIDGE_TIMEOUT[$bits(tmo_q)-1:0] - 1'b1) begin
                        err_q <= 1'b1; st <= S_RESP; last_err_kind_o <= 3'd4; timeout_count_o <= timeout_count_o + 1'b1;
                        drain_q <= '0;
                    end else tmo_q <= tmo_q + 1'b1;
                end
                S_RESP: begin                                                         // one response pulse
                    // a timed-out request whose HEAD was accepted may still get a late response: drain it
                    if (err_q && last_err_kind_o == 3'd4 && head_acc_q) begin st <= S_DRAIN; drain_q <= '0; end
                    else st <= S_IDLE;
                end
                S_DRAIN: begin                                                        // discard the late response
                    if (app_rx_last_i || app_rx_abort_i || drain_q == LATE_DRAIN_CYCLES[$bits(drain_q)-1:0] - 1'b1)
                        st <= S_IDLE;
                    else drain_q <= drain_q + 1'b1;
                end
                default: st <= S_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    // contract sec. 3 rule 4 and one-outstanding: checked continuously in simulation (prints [FAIL], never Error:)
    always @(posedge clk) if (!rst) begin
        if (app_valid_o && !authorized_i) $display("[FAIL] B1_SVA_VALID_WHILE_UNAUTH t=%0t", $time);
        if (tmem_gnt_o && st != S_IDLE)   $display("[FAIL] B1_SVA_GRANT_NOT_IDLE t=%0t", $time);
    end
`endif
endmodule
