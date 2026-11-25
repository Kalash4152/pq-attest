`timescale 1ns/1ps
//=============================================================================
// pq_merged_board_top  --  Combined SoC board wrapper (Arty A7-100T, xc7a100tcsg324-1). Evidence is in the gate reports.
//
// Same clock / reset / button front end as synth/p7_board/pq_p7_board_top.sv (D5-BOARD): CLK100MHZ -> MMCM -> 50 MHz
// (20 ns); btn[0] reset, btn[1] re-attest, btn[2] revoke; one attestation start AUTO_START_DELAY cycles after reset.
// Contract M-F1 rev 8 sec. 10 adds UART TX for the CPUs: sw[0] selects CPU A (tile 3, 0) or CPU B (tile 0, 1).
//
// LEDs: led[0] tile 3 authorized; led[1] attestation failed (sticky until the next start); led[2] CPU A last
//       write + read-back OK; led[3] heartbeat; led0_r CPU B refused (never authorized); led0_g CPU A error seen
//       (REAL_CPU_TILE: led0_g = either CPU printed FAIL).
//
// Secrets are demonstration provisioning, with fixed keys and nonce readable from the image.
// REAL_CPU_TILE uses the qualified revision-9 config and first 64 IMEM bytes from firmware v2.
// scripts/check_closure_profile.py verifies the generated reference artifacts; the board-profile
// checker verifies these local constants. The stub profile remains a historical explicit opt-in.
//=============================================================================
module pq_merged_board_top #(
    parameter int DEBOUNCE_BITS    = 20,
    parameter int AUTO_START_DELAY = 1024,
    parameter int HEARTBEAT_BIT    = 24
)(
    input  logic       CLK100MHZ,
    input  logic [2:0] btn,
    input  logic [0:0] sw,
    output logic [3:0] led,
    output logic       led0_r, led0_g,
    output logic       uart_rxd_out          // FPGA TX -> USB-UART (host receives)
);
    // ------------------------------------------------------------------ clock
    logic clk_fb, clk_fb_buf, clk50_mmcm, clk, locked;
    MMCME2_BASE #(.CLKIN1_PERIOD(10.0), .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(10.0), .CLKOUT0_DIVIDE_F(20.0)) u_mmcm (
        .CLKIN1(CLK100MHZ), .CLKFBIN(clk_fb_buf), .CLKFBOUT(clk_fb), .CLKFBOUTB(),
        .CLKOUT0(clk50_mmcm), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0));
    BUFG u_bufg_fb  (.I(clk_fb),     .O(clk_fb_buf));
    BUFG u_bufg_clk (.I(clk50_mmcm), .O(clk));

    // ------------------------------------------------------------------ reset
    logic [1:0] rst_sync; logic [4:0] rst_cnt; logic rst;
    always_ff @(posedge clk or negedge locked) begin
        if (!locked) begin rst_sync <= 2'b11; rst_cnt <= '0; rst <= 1'b1; end
        else begin
            rst_sync <= {rst_sync[0], btn[0]};
            if (rst_sync[1])      begin rst_cnt <= '0; rst <= 1'b1; end
            else if (!rst_cnt[4]) begin rst_cnt <= rst_cnt + 5'd1; rst <= 1'b1; end
            else                        rst <= 1'b0;
        end
    end

    // ------------------------------------------------- buttons and switch
    logic [1:0] b1_s, b2_s, sw0_s;
    logic [DEBOUNCE_BITS-1:0] b1_cnt, b2_cnt;
    logic b1_db, b2_db, b1_q, b2_q;
    always_ff @(posedge clk) begin
        b1_s <= {b1_s[0], btn[1]}; b2_s <= {b2_s[0], btn[2]}; sw0_s <= {sw0_s[0], sw[0]};
        if (rst) begin b1_cnt <= '0; b2_cnt <= '0; b1_db <= 1'b0; b2_db <= 1'b0; b1_q <= 1'b0; b2_q <= 1'b0; end
        else begin
            if (b1_s[1] == b1_db) b1_cnt <= '0; else begin b1_cnt <= b1_cnt + 1'b1; if (&b1_cnt) b1_db <= b1_s[1]; end
            if (b2_s[1] == b2_db) b2_cnt <= '0; else begin b2_cnt <= b2_cnt + 1'b1; if (&b2_cnt) b2_db <= b2_s[1]; end
            b1_q <= b1_db; b2_q <= b2_db;
        end
    end
    logic start_attestation, revoke, auto_done;
    logic [$clog2(AUTO_START_DELAY+1)-1:0] auto_cnt;
    always_ff @(posedge clk) begin
        if (rst) begin auto_cnt <= '0; auto_done <= 1'b0; start_attestation <= 1'b0; revoke <= 1'b0; end
        else begin
            start_attestation <= 1'b0; revoke <= b2_db && !b2_q;
            if (!auto_done) begin
                if (auto_cnt == AUTO_START_DELAY) begin start_attestation <= 1'b1; auto_done <= 1'b1; end
                else auto_cnt <= auto_cnt + 1'b1;
            end else if (b1_db && !b1_q) start_attestation <= 1'b1;
        end
    end

    // ------------------------------------------------------- demo secrets (vectors/d2_k3_64.svh row 0)
    localparam logic [79:0]  BOOT_EPOCH    = 80'h31303030305f544f4f42;
    localparam logic [79:0]  ATTEST_EPOCH  = 80'h313030305f48434f5045;
    localparam logic [127:0] NONCE         = 128'h0f0e0d0c0b0a09080706050403020100;
    localparam logic [255:0] ROOT_SECRET   = 256'h1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100;
    localparam logic [111:0] CONTEXT_IN    = 112'h0046444b2d5453455454412d5150;
`ifdef REAL_CPU_TILE
    localparam logic [511:0] CONFIG_DATA = 512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000092026110800000003;
`else
    localparam logic [511:0] CONFIG_DATA   = 512'h0f0e0d0c0b0a09080706050403020100;
`endif
`ifdef REAL_CPU_TILE
    // Real cpu_tile_noc (R-4, Lane 1 2026-11-07): both CPUs run sw/riscv/demo_fw.hex (copied next to the run / added to the
    // project). APPROVED_MEAS binds revision-9 config and the first 64 firmware bytes; scripts/check_closure_profile.py requalifies it.
    localparam logic [511:0] CPU_A_IMAGE = 512'h00000013000000130000001300000013000000130000001300000013000000130000001300000013000000132240006f0000001300000013000000130400006f;
    localparam logic [255:0] APPROVED_MEAS = 256'h1ee0fd3bc964a819161ec7bd5666a4d82a9fbf037da21cc511917cacb06eefd1;
    localparam               CPU_FW        = "demo_fw_v2.hex";
`else
    localparam logic [511:0] CPU_A_IMAGE   = 512'h4f4e4d4c4b4a494847464544434241403f3e3d3c3b3a393837363534333231302f2e2d2c2b2a292827262524232221201f1e1d1c1b1a19181716151413121110;
    localparam logic [255:0] APPROVED_MEAS = 256'h742eb93df35f0e663096c39dde290d9a2caf58b39d5e3f57f11d8a984243ab4f;
    localparam               CPU_FW        = "";
`endif
    localparam logic [511:0] DIRECTED_KEYS = 512'h289767c5289573d18748138585c50bda20480dbc92e553e1c1a2c701c02bc98a8d46f6da2f67236ad094f9a1fd90cdc2a86d83e5cbcac7cc2ba1f8ba37c4cd18;

    // ------------------------------------------------------------- the merged core
    logic [5:0] authorized; logic rot_busy, grant_done, attestation_failed, fault_sticky;
    logic [31:0] memory_commits; logic [5:0][31:0] gate_faults; logic [3:0] fault_reason;
    logic [1:0] cpu_uart; logic [1:0][7:0] cpu_gpio;
    pq_soc_merged_core #(.CPU_A_MEAS_IMAGE(CPU_A_IMAGE), .CPU_A_IMEM_INIT(CPU_FW), .CPU_B_IMEM_INIT(CPU_FW),
                         .CPU_BUILD_ID(32'h20261108)) u_core (
        .clk, .rst, .start_attestation, .revoke, .trusted_clear(1'b0),
        .boot_epoch(BOOT_EPOCH), .attest_epoch(ATTEST_EPOCH), .nonce(NONCE), .root_secret(ROOT_SECRET),
        .approved_measurement(APPROVED_MEAS), .directed_keys(DIRECTED_KEYS), .context_in(CONTEXT_IN), .context_len(4'd13),
        .config_data(CONFIG_DATA), .authorized, .rot_busy, .grant_done, .attestation_failed, .memory_commits,
        .gate_faults, .fault_sticky, .fault_reason, .endpoint_response(), .cpu_uart_tx(cpu_uart), .cpu_gpio);

    // ----------------------------------------------------------------- outputs
    logic failed_sticky; logic [HEARTBEAT_BIT:0] hb;
    always_ff @(posedge clk) begin
        if (rst) begin failed_sticky <= 1'b0; hb <= '0; end
        else begin
            hb <= hb + 1'b1;
            if (start_attestation)       failed_sticky <= 1'b0;
            else if (attestation_failed) failed_sticky <= 1'b1;
        end
`ifdef REAL_CPU_TILE
        // Firmware v2 LED flags: CPU A 0001 = "T3 PASS", 1000 = "T3 FAIL"; CPU B 0010 = "T0 REFUSED", 1000 = "T0 FAIL"
        led          <= {hb[HEARTBEAT_BIT], cpu_gpio[0][0], failed_sticky, authorized[3]};
        led0_r       <= cpu_gpio[1][1];
        led0_g       <= cpu_gpio[0][3] || cpu_gpio[1][3];
`else
        led          <= {hb[HEARTBEAT_BIT], cpu_gpio[0][0] && cpu_gpio[0][1], failed_sticky, authorized[3]};
        led0_r       <= cpu_gpio[1][3];
        led0_g       <= cpu_gpio[0][2];
`endif
        uart_rxd_out <= sw0_s[1] ? cpu_uart[1] : cpu_uart[0];
    end
endmodule
