`timescale 1ns / 1ps

module fpga_top (
    input  logic clk,
    output logic led
);

    // ============================================================
    // Reset
    // ============================================================

    logic [3:0] reset_counter = 4'h0;
    logic       reset_i;

    always_ff @(posedge clk) begin
        if (reset_counter != 4'hF)
            reset_counter <= reset_counter + 1'b1;
    end

    assign reset_i = (reset_counter != 4'hF);


    // ============================================================
    // Tile -> local instruction memory
    // ============================================================

    logic        imem_valid;
    logic [31:0] imem_addr;
    logic [31:0] imem_wdata;
    logic [3:0]  imem_wstrb;
    logic        imem_ready;
    logic [31:0] imem_rdata;


    // ============================================================
    // Tile -> local data memory
    // ============================================================

    logic        dmem_valid;
    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic [3:0]  dmem_wstrb;
    logic        dmem_ready;
    logic [31:0] dmem_rdata;


    // ============================================================
    // UART
    // ============================================================

    logic uart_tx;


    // ============================================================
    // GPIO
    // ============================================================

    logic [3:0] leds;


    // ============================================================
    // TMEM interface
    // ============================================================

    logic        tmem_req;
    logic        tmem_we;
    logic [31:0] tmem_addr;
    logic [31:0] tmem_wdata;
    logic [3:0]  tmem_wstrb;
    logic        tmem_is_fetch;

    logic        tmem_gnt;
    logic        tmem_rvalid;
    logic [31:0] tmem_rdata;
    logic        tmem_err;


    // ============================================================
    // Attestation / status
    // ============================================================

    logic attest_req;


    // ============================================================
    // Debug
    // ============================================================

    logic [31:0] dbg_pc;
    logic [31:0] dbg_inst;
    logic        dbg_valid;
    logic        dbg_trap;


    // ============================================================
    // Processor Tile
    // ============================================================

    tile_top #(
        .TILE_ID    (4'h0),
        .BUILD_ID   (32'h0000_0001),
        .IMEM_WORDS (4096),
        .DMEM_WORDS (4096),
        .HAS_UART   (1'b1)
    ) tile_inst (
        .clk_i                (clk),
        .reset_i              (reset_i),

        // Instruction memory
        .imem_valid_o         (imem_valid),
        .imem_addr_o          (imem_addr),
        .imem_wdata_o         (imem_wdata),
        .imem_wstrb_o         (imem_wstrb),
        .imem_ready_i         (imem_ready),
        .imem_rdata_i         (imem_rdata),

        // Data memory
        .dmem_valid_o         (dmem_valid),
        .dmem_addr_o          (dmem_addr),
        .dmem_wdata_o         (dmem_wdata),
        .dmem_wstrb_o         (dmem_wstrb),
        .dmem_ready_i         (dmem_ready),
        .dmem_rdata_i         (dmem_rdata),

        // UART
        .uart_tx_o            (uart_tx),

        // GPIO
        .switches_i           (4'b0000),
        .leds_o               (leds),

        // TMEM
        .tmem_req_o           (tmem_req),
        .tmem_we_o            (tmem_we),
        .tmem_addr_o          (tmem_addr),
        .tmem_wdata_o         (tmem_wdata),
        .tmem_wstrb_o         (tmem_wstrb),
        .tmem_is_fetch_o      (tmem_is_fetch),

        .tmem_gnt_i           (tmem_gnt),
        .tmem_rvalid_i        (tmem_rvalid),
        .tmem_rdata_i         (tmem_rdata),
        .tmem_err_i           (tmem_err),

        // Attestation / status
        .attested_i           (1'b0),
        .last_fault_timeout_i (1'b0),
        .attest_req_o         (attest_req),

        // Debug
        .dbg_pc_o             (dbg_pc),
        .dbg_inst_o           (dbg_inst),
        .dbg_valid_o          (dbg_valid),
        .dbg_trap_o           (dbg_trap)
    );


    // ============================================================
    // Local instruction + data memories
    // ============================================================

    tile_mem_wrapper #(
        .IMEM_WORDS     (4096),
        .DMEM_WORDS     (4096),
        .IMEM_INIT_FILE ("rtl/program.hex"),
        .DMEM_INIT_FILE ("")
    ) memory_inst (
        .clk_i          (clk),
        .reset_i        (reset_i),

        // Instruction memory
        .imem_valid_i   (imem_valid),
        .imem_addr_i    (imem_addr),
        .imem_wdata_i   (imem_wdata),
        .imem_wstrb_i   (imem_wstrb),
        .imem_ready_o   (imem_ready),
        .imem_rdata_o   (imem_rdata),

        // Data memory
        .dmem_valid_i   (dmem_valid),
        .dmem_addr_i    (dmem_addr),
        .dmem_wdata_i   (dmem_wdata),
        .dmem_wstrb_i   (dmem_wstrb),
        .dmem_ready_o   (dmem_ready),
        .dmem_rdata_o   (dmem_rdata)
    );


    // ============================================================
    // Memory Tile
    //
    // Tile 2 = remote memory target.
    // ============================================================

    memory_tile #(
        .TILE_ID   (4'h2),
        .MEM_WORDS (4096),
        .INIT_FILE ("")
    ) memory_tile_inst (
        .clk_i           (clk),
        .reset_i         (reset_i),

        .tmem_req_i      (tmem_req),
        .tmem_we_i       (tmem_we),
        .tmem_addr_i     (tmem_addr),
        .tmem_wdata_i    (tmem_wdata),
        .tmem_wstrb_i    (tmem_wstrb),
        .tmem_is_fetch_i (tmem_is_fetch),

        .tmem_gnt_o      (tmem_gnt),
        .tmem_rvalid_o   (tmem_rvalid),
        .tmem_rdata_o    (tmem_rdata),
        .tmem_err_o      (tmem_err)
    );


    // ============================================================
    // Board LED
    //
    // GPIO LED 0 is exposed on the Arty board LED.
    // ============================================================

    assign led = leds[0];

endmodule