`timescale 1ns/1ps
//=============================================================================
// Module : pq_p7_board_top             (D5 board wrapper, Kalash go-ahead 2026-11-02)
// File   : synth/p7_board/pq_p7_board_top.sv
//
// Purpose: give pq_noc_subsystem_p7 (the I-5 P7 design) a real-pin boundary on the Arty A7-100T
// (xc7a100tcsg324-1) so a bitstream can be built. The subsystem itself is unchanged.
//
// Clock  : CLK100MHZ (E3) -> MMCME2_BASE (x10 / 20) -> 50 MHz (20 ns), the design's registered clock.
// Reset  : btn[0] or MMCM not locked -> 2-FF sync -> 16-cycle stretch -> active-HIGH synchronous rst.
// Inputs : btn[1] re-attest (start_attestation pulse), btn[2] revoke pulse (debounced, edge-detected);
//          one start_attestation pulse is also issued automatically AUTO_START_DELAY cycles after reset.
//          sw[0]: tile 3 (CRYPTO) writes to the memory tile (authorized data, accepted after GRANT).
//          sw[1]: tile 0 (CPU0, never attested) tries to write to the memory tile (refused by the P7 gate).
// Outputs: led[0] tile 3 authorized; led[1] attestation failed (sticky until the next start);
//          led[2] memory_commits[COMMIT_BIT] (blinks while tile 3 writes); led[3] heartbeat;
//          led0_r tile 0 refused (gate_faults[0] != 0).
//
// Secrets: the I-5 bench vectors (vectors/full_chain.svh load_chain(0), BOOT, directed keys 4->3 / 3->4 from KEYS),
//          so the board run reproduces the registered attestation. DEMO ONLY: fixed keys are readable from the
//          bitstream and the nonce never changes (a real system needs a TRNG nonce and protected key storage).
//
// Not evidence. Registered results come only from scripts/dual_lane.py.
//=============================================================================
module pq_p7_board_top #(
    parameter int DEBOUNCE_BITS    = 20,   // ~21 ms at 50 MHz
    parameter int AUTO_START_DELAY = 1024,
    parameter int HEARTBEAT_BIT    = 24,   // ~1.5 Hz at 50 MHz
    parameter int COMMIT_BIT       = 12
)(
    input  logic       CLK100MHZ,
    input  logic [2:0] btn,
    input  logic [1:0] sw,
    output logic [3:0] led,
    output logic       led0_r
);
    import noc_pkg::*;

    // ------------------------------------------------------------------ clock
    logic clk_fb, clk_fb_buf, clk50_mmcm, clk, locked;
    MMCME2_BASE #(
        .CLKIN1_PERIOD   (10.0),
        .DIVCLK_DIVIDE   (1),
        .CLKFBOUT_MULT_F (10.0),   // VCO 1000 MHz
        .CLKOUT0_DIVIDE_F(20.0)    // 50 MHz
    ) u_mmcm (
        .CLKIN1(CLK100MHZ), .CLKFBIN(clk_fb_buf), .CLKFBOUT(clk_fb), .CLKFBOUTB(),
        .CLKOUT0(clk50_mmcm), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0)
    );
    BUFG u_bufg_fb  (.I(clk_fb),     .O(clk_fb_buf));
    BUFG u_bufg_clk (.I(clk50_mmcm), .O(clk));

    // ------------------------------------------------------------------ reset
    logic [1:0] rst_sync;
    logic [4:0] rst_cnt;
    logic       rst;
    always_ff @(posedge clk or negedge locked) begin
        if (!locked) begin rst_sync <= 2'b11; rst_cnt <= '0; rst <= 1'b1; end
        else begin
            rst_sync <= {rst_sync[0], btn[0]};
            if (rst_sync[1])         begin rst_cnt <= '0; rst <= 1'b1; end
            else if (!rst_cnt[4])    begin rst_cnt <= rst_cnt + 5'd1; rst <= 1'b1; end
            else                           rst <= 1'b0;
        end
    end

    // ------------------------------------------------- buttons and switches
    function automatic logic edge_up(input logic now, input logic prev); return now && !prev; endfunction
    logic [1:0] b1_s, b2_s, sw0_s, sw1_s;
    logic [DEBOUNCE_BITS-1:0] b1_cnt, b2_cnt;
    logic b1_db, b2_db, b1_q, b2_q;
    always_ff @(posedge clk) begin
        b1_s <= {b1_s[0], btn[1]}; b2_s <= {b2_s[0], btn[2]};
        sw0_s <= {sw0_s[0], sw[0]}; sw1_s <= {sw1_s[0], sw[1]};
        if (rst) begin b1_cnt <= '0; b2_cnt <= '0; b1_db <= 1'b0; b2_db <= 1'b0; b1_q <= 1'b0; b2_q <= 1'b0; end
        else begin
            if (b1_s[1] == b1_db) b1_cnt <= '0; else begin b1_cnt <= b1_cnt + 1'b1; if (&b1_cnt) b1_db <= b1_s[1]; end
            if (b2_s[1] == b2_db) b2_cnt <= '0; else begin b2_cnt <= b2_cnt + 1'b1; if (&b2_cnt) b2_db <= b2_s[1]; end
            b1_q <= b1_db; b2_q <= b2_db;
        end
    end

    // ------------------------------------------- attestation start / revoke
    logic start_attestation, revoke, auto_done;
    logic [$clog2(AUTO_START_DELAY+1)-1:0] auto_cnt;
    always_ff @(posedge clk) begin
        if (rst) begin auto_cnt <= '0; auto_done <= 1'b0; start_attestation <= 1'b0; revoke <= 1'b0; end
        else begin
            start_attestation <= 1'b0; revoke <= edge_up(b2_db, b2_q);
            if (!auto_done) begin
                if (auto_cnt == AUTO_START_DELAY) begin start_attestation <= 1'b1; auto_done <= 1'b1; end
                else auto_cnt <= auto_cnt + 1'b1;
            end
            else if (edge_up(b1_db, b1_q)) start_attestation <= 1'b1;
        end
    end

    // ------------------------------------------------------- demo secrets
    localparam logic [79:0]  BOOT_EPOCH   = 80'h31303030305f544f4f42;
    localparam logic [79:0]  ATTEST_EPOCH = 80'h313030305f48434f5045;
    localparam logic [127:0] NONCE        = 128'h0f0e0d0c0b0a09080706050403020100;
    localparam logic [255:0] ROOT_SECRET  = 256'h1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100;
    localparam logic [255:0] APPROVED_MEAS= 256'h1482e1f71d02a26e7bf0f9fd0ae1c08b3a32eb98026e9f0ee347c01e46f174d4;
    localparam logic [111:0] CONTEXT_IN   = 112'h0046444b2d5453455454412d5150;
    localparam logic [511:0] CONFIG_DATA  = 512'h0f0e0d0c0b0a09080706050403020100;
    localparam logic [511:0] IMEM         = 512'h1f1e1d1c1b1a19181716151413121110;
    localparam logic [511:0] DIRECTED_KEYS= 512'h289767c5289573d18748138585c50bda20480dbc92e553e1c1a2c701c02bc98a8d46f6da2f67236ad094f9a1fd90cdc2a86d83e5cbcac7cc2ba1f8ba37c4cd18;

    // ------------------------------------------------- application traffic
    localparam logic [31:0] ADDR = 32'h2200_0100;   // C-5 window (I-6)
    localparam int T_WR [2] = '{3, 0};   // generator 0 drives tile 3, generator 1 drives tile 0
    logic [5:0] app_valid, app_payload_valid, app_ready, app_payload_ready;
    coord_t     [5:0] app_destination;
    msg_type_e  [5:0] app_message;
    logic [5:0][10:0] app_control;
    logic [5:0][31:0] app_payload;
    logic [5:0] authorized;
    logic       rot_busy, grant_done, attestation_failed;
    logic [31:0] memory_commits;
    logic [5:0][31:0] gate_faults;

    typedef enum logic [1:0] {W_IDLE, W_HEAD, W_P0, W_P1} wstate_e;
    wstate_e    wst [2];
    logic [31:0] wdata [2];
    logic [1:0]  wen;
    assign wen[0] = sw0_s[1] && authorized[3];
    assign wen[1] = sw1_s[1];

    always_comb begin
        app_valid = '0; app_payload_valid = '0; app_destination = '0; app_message = msg_type_e'('0);
        app_control = '0; app_payload = '0;
        for (int k = 0; k < 2; k++) begin
            app_destination[T_WR[k]] = tile_to_coord(TILE_MEMORY);
            app_message[T_WR[k]]     = MSG_MEM_WR_REQ;
            app_control[T_WR[k]]     = 11'h780;
            app_valid[T_WR[k]]         = wst[k] == W_HEAD;
            app_payload_valid[T_WR[k]] = wst[k] == W_P0 || wst[k] == W_P1;
            app_payload[T_WR[k]]       = wst[k] == W_P0 ? ADDR : wdata[k];
        end
    end
    always_ff @(posedge clk) begin
        for (int k = 0; k < 2; k++) begin
            if (rst) begin wst[k] <= W_IDLE; wdata[k] <= 32'hFEED_0000; end
            else case (wst[k])
                W_IDLE: if (wen[k]) wst[k] <= W_HEAD;
                W_HEAD: if (app_ready[T_WR[k]]) wst[k] <= W_P0;
                        else if (!wen[k]) wst[k] <= W_IDLE;   // a refused request is withdrawn when its switch goes off
                W_P0:   if (app_payload_ready[T_WR[k]]) wst[k] <= W_P1;
                W_P1:   if (app_payload_ready[T_WR[k]]) begin wst[k] <= W_IDLE; wdata[k] <= wdata[k] + 1; end
            endcase
        end
    end

    // ------------------------------------------------------------- the DUT
    pq_noc_subsystem_p7 u_p7 (
        .clk, .rst, .start_attestation, .revoke,
        .boot_epoch(BOOT_EPOCH), .attest_epoch(ATTEST_EPOCH), .nonce(NONCE),
        .root_secret(ROOT_SECRET), .approved_measurement(APPROVED_MEAS), .directed_keys(DIRECTED_KEYS),
        .context_in(CONTEXT_IN), .context_len(4'd13),
        .config_data(CONFIG_DATA), .imem(IMEM), .config_len(7'd16), .imem_len(7'd16),
        .trusted_clear(1'b0), .app_valid, .app_payload_valid, .app_ready, .app_payload_ready,
        .app_destination, .app_message, .app_control, .app_payload,
        .spoof_raw_valid(1'b0), .spoof_raw_flit('0), .spoof_raw_ready(),
        .authorized, .rot_busy, .grant_done, .attestation_failed,
        .endpoint_response(), .memory_commits, .memory_last_data(),
        .l2_rejected(), .l2_accepted(), .gate_faults, .ingress_rejected(), .ingress_fault(),
        .q_rejected(), .q_forwarded(), .q_discarded(), .mem_faults(), .q_reason(),
        .l2_reason(), .ingress_reason(),
        .p_slot_drops(), .peer_accepted(), .peer_replayed(), .peer_rejected(), .peer_hold_max(),
        .app_tx_error(), .endpoint_rejected(), .verifier_rejected()
    );

    // ----------------------------------------------------------------- LEDs
    logic failed_sticky;
    logic [HEARTBEAT_BIT:0] hb;
    always_ff @(posedge clk) begin
        if (rst) begin failed_sticky <= 1'b0; hb <= '0; end
        else begin
            hb <= hb + 1'b1;
            if (start_attestation)       failed_sticky <= 1'b0;
            else if (attestation_failed) failed_sticky <= 1'b1;
        end
        led    <= {hb[HEARTBEAT_BIT], memory_commits[COMMIT_BIT], failed_sticky, authorized[3]};
        led0_r <= gate_faults[0] != '0;
    end
endmodule
