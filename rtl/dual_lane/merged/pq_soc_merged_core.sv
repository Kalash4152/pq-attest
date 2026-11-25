`timescale 1ns/1ps
// Combined two-CPU NoC and PQ-Attest core. Validation is recorded in the increment gate reports.
// Topology: attested CPU A at tile 3, refused CPU B at tile 0, 16 KB shared tile-2 BRAM,
// tile-4 RoT and tied-off tile-5 raw injector. Each CPU has 16 KB IMEM and 16 KB DMEM.
// The explicit source list selects the I-9 subsystem variant, a 64-byte measurement window,
// NI_SLOT_TIMEOUT 8192 and BRIDGE_TIMEOUT 4096. Memory commits follow authorization-low F4/Q2 rules.
// Revision 9: only RoT-side start_attestation initiates verification; it waits for the
// measurement reader. Provisioned config binds tile/build/profile fields. CPU ATTEST_REQ
// remains local to the reader and cannot grant authority. Grant/failure status reaches CPU A.
// Default CPU implementation is real; the historical stub is an explicit opt-in define.
`ifndef CPU_TILE_MODULE
 `define CPU_TILE_MODULE cpu_tile_noc
`endif
`ifndef TILE2_BRAM_MODULE
 `define TILE2_BRAM_MODULE tile2_bram_infer
`endif

module tile2_bram_infer #(parameter int DEPTH_WORDS = 4096)(
    input  logic clk, en,
    input  logic [3:0] we,
    input  logic [$clog2(DEPTH_WORDS)-1:0] addr,
    input  logic [31:0] wdata,
    output logic [31:0] rdata
);
    (* ram_style = "block" *) logic [31:0] mem [0:DEPTH_WORDS-1];
    always_ff @(posedge clk) if (en) begin
        for (int b = 0; b < 4; b++) if (we[b]) mem[addr][b*8 +: 8] <= wdata[b*8 +: 8];
        rdata <= mem[addr];
    end
endmodule

module pq_soc_merged_core #(
    parameter int           BRIDGE_TIMEOUT  = 4096,   // D7
    parameter int           NI_SLOT_TIMEOUT = 8192,   // D6, > BRIDGE_TIMEOUT
    parameter int           MEM_ADDR_BITS   = 14,     // 16 KB window (sec. 9)
    parameter int           VERIFIER_TIMEOUT= 100000,
    parameter int           ROUND_GAP       = 4096,
    parameter bit           WHOLE_IMEM_MEASUREMENT = 1'b0, // explicit qualified rev-10 selection; legacy profiles retain windows
    parameter logic [511:0] CPU_A_MEAS_IMAGE = '0,    // stub only: first 64 IMEM bytes of CPU A
    parameter               CPU_A_IMEM_INIT  = "",    // real cpu_tile_noc: firmware image ($readmemh) of CPU A (tile 3)
    parameter               CPU_B_IMEM_INIT  = "",    // real cpu_tile_noc: firmware image of CPU B (tile 0)
    parameter logic [31:0]  CPU_BUILD_ID     = 32'h0   // real cpu_tile_noc: STATUS BUILD_ID
)(
    input  logic clk, rst,
    input  logic start_attestation, revoke, trusted_clear,
    input  logic [79:0]  boot_epoch, attest_epoch,
    input  logic [127:0] nonce,
    input  logic [255:0] root_secret, approved_measurement,
    input  logic [511:0] directed_keys,
    input  logic [111:0] context_in,
    input  logic [3:0]   context_len,
    input  logic [511:0] config_data,
    output logic [5:0]   authorized,
    output logic         rot_busy, grant_done, attestation_failed,
    output logic [31:0]  memory_commits,
    output logic [5:0][31:0] gate_faults,
    output logic         fault_sticky,
    output logic [3:0]   fault_reason,
    output logic [775:0] endpoint_response,
    output logic [1:0]   cpu_uart_tx,      // [0] CPU A (tile 3), [1] CPU B (tile 0)
    output logic [1:0][7:0] cpu_gpio
);
    import noc_pkg::*;
    localparam int CPU [2] = '{3, 0};

    // ------------------------------------------------------------ app ports
    logic [5:0] app_valid, app_payload_valid, app_ready, app_payload_ready, app_tx_error;
    coord_t     [5:0] app_destination;
    msg_type_e  [5:0] app_message;
    logic [5:0][10:0] app_control;
    logic [5:0][31:0] app_payload;
    logic [5:0] rx_hv, rx_dv, rx_last, rx_abort;
    coord_t     [5:0] rx_src;
    msg_type_e  [5:0] rx_msg;
    logic [5:0][10:0] rx_ctl;
    logic [5:0][31:0] rx_data;

    // per-CPU scalars (wired to the packed arrays below; avoids binding module ports straight to array elements)
    logic [1:0] c_valid, c_pvalid, c_attest_req, c_meas_valid;
    coord_t     [1:0] c_dest;
    msg_type_e  [1:0] c_msg;
    logic [1:0][10:0] c_ctl;
    logic [1:0][31:0] c_payload;
    logic [1:0][511:0] c_meas;
    logic [1:0][6:0]   c_meas_len;

    `CPU_TILE_MODULE #(.TILE_ID(3), .BRIDGE_TIMEOUT(BRIDGE_TIMEOUT), .NI_SLOT_TIMEOUT(NI_SLOT_TIMEOUT), .ROUND_GAP(ROUND_GAP),
                       .DATA_SEED(32'hA300_0000), .MEAS_IMAGE(CPU_A_MEAS_IMAGE),
                       .IMEM_INIT_FILE(CPU_A_IMEM_INIT), .BUILD_ID(CPU_BUILD_ID),
                       .WHOLE_IMEM_MEASUREMENT(WHOLE_IMEM_MEASUREMENT)) u_cpu_a (
        .clk, .rst,
        .app_valid_o(c_valid[0]), .app_ready_i(app_ready[3]), .app_destination_o(c_dest[0]), .app_message_o(c_msg[0]),
        .app_control_o(c_ctl[0]), .app_payload_o(c_payload[0]), .app_payload_valid_o(c_pvalid[0]),
        .app_payload_ready_i(app_payload_ready[3]), .app_tx_error_i(app_tx_error[3]),
        .app_rx_head_valid_i(rx_hv[3]), .app_rx_src_i(rx_src[3]), .app_rx_msg_i(rx_msg[3]), .app_rx_control_i(rx_ctl[3]),
        .app_rx_data_i(rx_data[3]), .app_rx_data_valid_i(rx_dv[3]), .app_rx_last_i(rx_last[3]), .app_rx_abort_i(rx_abort[3]),
        .authorized_i(authorized[3]), .grant_done_i(grant_done), .attest_failed_i(attestation_failed),
        .attest_req_o(c_attest_req[0]), .meas_imem_o(c_meas[0]), .meas_imem_len_o(c_meas_len[0]), .meas_valid_o(c_meas_valid[0]),
        .uart_tx_o(cpu_uart_tx[0]), .gpio_o(cpu_gpio[0]));

    `CPU_TILE_MODULE #(.TILE_ID(0), .BRIDGE_TIMEOUT(BRIDGE_TIMEOUT), .NI_SLOT_TIMEOUT(NI_SLOT_TIMEOUT), .ROUND_GAP(ROUND_GAP),
                       .DATA_SEED(32'hB000_0000), .NEVER_AUTHORIZED_TEST(1'b1),
                       .IMEM_INIT_FILE(CPU_B_IMEM_INIT), .BUILD_ID(CPU_BUILD_ID),
                       .WHOLE_IMEM_MEASUREMENT(1'b0)) u_cpu_b (
        .clk, .rst,
        .app_valid_o(c_valid[1]), .app_ready_i(app_ready[0]), .app_destination_o(c_dest[1]), .app_message_o(c_msg[1]),
        .app_control_o(c_ctl[1]), .app_payload_o(c_payload[1]), .app_payload_valid_o(c_pvalid[1]),
        .app_payload_ready_i(app_payload_ready[0]), .app_tx_error_i(app_tx_error[0]),
        .app_rx_head_valid_i(rx_hv[0]), .app_rx_src_i(rx_src[0]), .app_rx_msg_i(rx_msg[0]), .app_rx_control_i(rx_ctl[0]),
        .app_rx_data_i(rx_data[0]), .app_rx_data_valid_i(rx_dv[0]), .app_rx_last_i(rx_last[0]), .app_rx_abort_i(rx_abort[0]),
        .authorized_i(authorized[0]), .grant_done_i(1'b0), .attest_failed_i(1'b0),
        .attest_req_o(c_attest_req[1]), .meas_imem_o(c_meas[1]), .meas_imem_len_o(c_meas_len[1]), .meas_valid_o(c_meas_valid[1]),
        .uart_tx_o(cpu_uart_tx[1]), .gpio_o(cpu_gpio[1]));

    always_comb begin
        app_valid = '0; app_payload_valid = '0; app_destination = '0; app_message = msg_type_e'('0);
        app_control = '0; app_payload = '0;
        for (int k = 0; k < 2; k++) begin
            app_valid[CPU[k]] = c_valid[k]; app_payload_valid[CPU[k]] = c_pvalid[k];
            app_destination[CPU[k]] = c_dest[k]; app_message[CPU[k]] = c_msg[k];
            app_control[CPU[k]] = c_ctl[k]; app_payload[CPU[k]] = c_payload[k];
        end
    end

    // ------------------------------------- attestation start held until tile 3's measurement is loaded
    logic start_pending, start_core;
    always_ff @(posedge clk) begin
        if (rst) begin start_pending <= 1'b0; start_core <= 1'b0; end
        else begin
            start_core <= 1'b0;
            if (start_attestation) start_pending <= 1'b1;
            if ((start_pending || start_attestation) && c_meas_valid[0]) begin start_core <= 1'b1; start_pending <= 1'b0; end
        end
    end

    // ---------------------------------------------------------------- tile-2 BRAM
    logic mem_en; logic [3:0] mem_we; logic [MEM_ADDR_BITS-3:0] mem_addr; logic [31:0] mem_wdata, mem_rdata;
    `TILE2_BRAM_MODULE #(.DEPTH_WORDS(2**(MEM_ADDR_BITS-2))) u_bram (
        .clk, .en(mem_en), .we(mem_we), .addr(mem_addr), .wdata(mem_wdata), .rdata(mem_rdata));

    // ---------------------------------------------------------------- subsystem (I-9 variant)
    pq_noc_subsystem_p7 #(.VERIFIER_TIMEOUT(VERIFIER_TIMEOUT), .NI_SLOT_TIMEOUT(NI_SLOT_TIMEOUT), .MEM_EXT(1'b1),
                          .MEM_ADDR_BITS(MEM_ADDR_BITS), .K3_IMEM_LEN(7'd64), .CPU_TILES(6'b001001)) u_p7 (
        .clk, .rst, .start_attestation(start_core), .revoke, .trusted_clear,
        .boot_epoch, .attest_epoch, .nonce, .root_secret, .approved_measurement, .directed_keys,
        .context_in, .context_len, .config_data, .imem(c_meas[0]), .config_len(7'd16), .imem_len(c_meas_len[0]),
        .app_valid, .app_payload_valid, .app_ready, .app_payload_ready, .app_destination, .app_message, .app_control,
        .app_payload, .spoof_raw_valid(1'b0), .spoof_raw_flit('0), .spoof_raw_ready(),
        .authorized, .rot_busy, .grant_done, .attestation_failed, .endpoint_response, .memory_commits,
        .memory_last_data(), .l2_rejected(), .l2_accepted(), .gate_faults, .ingress_rejected(), .ingress_fault(),
        .q_rejected(), .q_forwarded(), .q_discarded(), .mem_faults(), .q_reason(), .l2_reason(), .ingress_reason(),
        .p_slot_drops(), .peer_accepted(), .peer_replayed(), .peer_rejected(), .peer_hold_max(),
        .app_tx_error, .endpoint_rejected(), .verifier_rejected(),
        .fault_sticky, .fault_count(), .fault_source(), .fault_operation(), .fault_reason, .fault_epoch(),
        .app_rx_head_valid(rx_hv), .app_rx_data_valid(rx_dv), .app_rx_last(rx_last), .app_rx_abort(rx_abort),
        .app_rx_src(rx_src), .app_rx_msg(rx_msg), .app_rx_control(rx_ctl), .app_rx_data(rx_data),
        .mem_en, .mem_we, .mem_addr, .mem_wdata, .mem_rdata);
endmodule
