`timescale 1ns/1ps
//=============================================================================
// cpu_tile_noc_stub  --  SKELETON STAND-IN for the RISC-V lane's cpu_tile_noc (brief v2 sec. B2). NOT EVIDENCE.
//
// Purpose: let Lane 1 build, simulate and synthesize the merged top before the RISC-V package arrives. Same port
// list as brief B2 (app TX + app_rx bundle, authorized_i / grant_done_i / attest_failed_i, attest_req_o,
// meas_imem_o / meas_imem_len_o / meas_valid_o, uart_tx_o, gpio_o). Port NAMES are Lane 1's guess; when the real
// cpu_tile_noc arrives, only the one instantiation in pq_soc_merged_core.sv is re-mapped (README port table).
//
// Behaviour = a scripted "firmware" that obeys the bridge rules of M-F1 rev 8 sec. 3 / 5:
//   - never raises app_valid while authorized_i = 0 (local refusal, counted in gpio_o[3]);
//   - one request at a time; write = {address, data}, read = {address}; app_control = 11'h780 / 11'h000;
//   - waits for the app_rx response; control[10] (err) or abort = error; BRIDGE_TIMEOUT -> error, late response dropped.
//   Script: wait for authorized (or, if NEVER_AUTHORIZED_TEST, try once without it), then loop: write DATA_SEED+n to
//   ADDR, read it back, compare. gpio_o: [0] last write ok, [1] last read matched, [2] any error, [3] local refusal
//   seen, [7:4] low nibble of the round counter.
// Measurement: meas_imem_o = MEAS_IMAGE (the first 64 IMEM bytes at MEAS_BASE in the real tile), valid after reset.
// UART: idle high (the real tile prints PASS / FAIL lines).
//=============================================================================
module cpu_tile_noc_stub #(
    parameter int          TILE_ID          = 3,
    parameter bit          WHOLE_IMEM_MEASUREMENT = 1'b0, // interface compatibility only; stub is never a qualified rev-10 CPU
    parameter int          MEM_TILE         = 2,
    parameter int          BRIDGE_TIMEOUT   = 4096,     // D7
    parameter int          NI_SLOT_TIMEOUT  = 8192,     // real-tile compatibility; stub uses its own scripted timeout
    parameter logic [31:0] ADDR             = 32'h2200_0100,
    parameter logic [31:0] DATA_SEED        = 32'hC0DE_0000,
    parameter int          ROUND_GAP        = 4096,     // idle cycles between rounds
    parameter bit          NEVER_AUTHORIZED_TEST = 0,   // tile 0: try once while unauthorized (must be refused locally)
    parameter logic [511:0] MEAS_IMAGE      = '0,
    parameter               IMEM_INIT_FILE  = "",     // real-tile compatibility only; ignored by the stub
    parameter logic [31:0]  BUILD_ID        = 32'h0     // real-tile compatibility only; ignored by the stub
)(
    input  logic clk, rst,
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
    // app_rx (sec. 4)
    input  logic                 app_rx_head_valid_i,
    input  noc_pkg::coord_t      app_rx_src_i,
    input  noc_pkg::msg_type_e   app_rx_msg_i,
    input  logic [10:0]          app_rx_control_i,
    input  logic [31:0]          app_rx_data_i,
    input  logic                 app_rx_data_valid_i,
    input  logic                 app_rx_last_i,
    input  logic                 app_rx_abort_i,
    // attestation (sec. 8, OPEN)
    input  logic                 authorized_i, grant_done_i, attest_failed_i,
    output logic                 attest_req_o,
    output logic [511:0]         meas_imem_o,
    output logic [6:0]           meas_imem_len_o,
    output logic                 meas_valid_o,
    // board
    output logic                 uart_tx_o,
    output logic [7:0]           gpio_o
);
    import noc_pkg::*;

    typedef enum logic [3:0] {S_WAIT, S_GAP, S_HDR, S_P0, S_P1, S_RESP, S_DONE} st_e;
    st_e st;
    logic        is_wr, wr_ok, rd_ok, any_err, refused, tried_unauth, resp_err, got_data;
    logic [31:0] data, rdata;
    logic [3:0]  rounds;
    logic [$clog2(BRIDGE_TIMEOUT+1)-1:0] tmo;
    logic [$clog2(ROUND_GAP+1)-1:0]      gap;

    assign app_destination_o   = tile_to_coord(tile_id_e'(MEM_TILE));
    assign app_message_o       = is_wr ? MSG_MEM_WR_REQ : MSG_MEM_RD_REQ;
    assign app_control_o       = is_wr ? 11'h780 : 11'h000;
    assign app_valid_o         = st == S_HDR && authorized_i;            // sec. 3 rule 4
    assign app_payload_valid_o = st == S_P0 || st == S_P1;
    assign app_payload_o       = st == S_P0 ? ADDR : data;

    always_ff @(posedge clk) begin
        if (rst) begin
            st <= S_WAIT; is_wr <= 1'b1; wr_ok <= 0; rd_ok <= 0; any_err <= 0; refused <= 0; tried_unauth <= 0;
            resp_err <= 0; got_data <= 0; data <= DATA_SEED; rdata <= '0; rounds <= '0; tmo <= '0; gap <= '0;
        end else begin
            case (st)
                S_WAIT: if (authorized_i) begin st <= S_GAP; gap <= '0; end
                        else if (NEVER_AUTHORIZED_TEST && !tried_unauth) begin
                            tried_unauth <= 1'b1; refused <= 1'b1;   // bridge: tmem_err, no network traffic
                        end
                S_GAP:  if (!authorized_i) st <= S_WAIT;
                        else if (gap == ROUND_GAP) begin st <= S_HDR; tmo <= '0; end
                        else gap <= gap + 1'b1;
                S_HDR:  if (!authorized_i) begin refused <= 1'b1; any_err <= 1'b1; st <= S_WAIT; end
                        else if (app_ready_i) st <= S_P0;
                        else if (tmo == BRIDGE_TIMEOUT) begin any_err <= 1'b1; st <= S_WAIT; end
                        else tmo <= tmo + 1'b1;
                S_P0:   if (app_payload_ready_i) begin
                            if (is_wr) st <= S_P1; else begin st <= S_RESP; tmo <= '0; resp_err <= 0; got_data <= 0; end
                        end
                S_P1:   if (app_payload_ready_i) begin st <= S_RESP; tmo <= '0; resp_err <= 0; got_data <= 0; end
                S_RESP: begin
                            if (app_rx_head_valid_i && (app_rx_control_i[10] || app_rx_src_i != tile_to_coord(tile_id_e'(MEM_TILE))
                                || app_rx_msg_i != (is_wr ? MSG_MEM_WR_RESP : MSG_MEM_RD_RESP))) resp_err <= 1'b1;
                            if (app_rx_abort_i) resp_err <= 1'b1;
                            if (app_rx_data_valid_i) begin rdata <= app_rx_data_i; got_data <= 1'b1; end
                            if (app_rx_last_i) st <= S_DONE;
                            else if (tmo == BRIDGE_TIMEOUT) begin any_err <= 1'b1; st <= S_WAIT; end   // late response dropped
                            else tmo <= tmo + 1'b1;
                        end
                S_DONE: begin
                            if (resp_err) any_err <= 1'b1;
                            if (is_wr) begin wr_ok <= !resp_err; is_wr <= 1'b0; st <= S_HDR; tmo <= '0; end
                            else begin
                                rd_ok <= !resp_err && got_data && rdata == data;
                                if (resp_err || !got_data || rdata != data) any_err <= 1'b1;
                                is_wr <= 1'b1; data <= data + 1; rounds <= rounds + 1'b1; st <= S_GAP; gap <= '0;
                            end
                        end
                default: st <= S_WAIT;
            endcase
        end
    end

    assign attest_req_o    = 1'b0;          // sec. 8 OPEN: RoT starts attestation in the skeleton
    assign meas_imem_o     = MEAS_IMAGE;
    assign meas_imem_len_o = 7'd64;         // D2
    assign meas_valid_o    = !rst;
    assign uart_tx_o       = 1'b1;
    assign gpio_o          = {rounds, refused, any_err, rd_ok, wr_ok};
endmodule
