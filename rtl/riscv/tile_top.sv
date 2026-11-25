`timescale 1ns / 1ps

module tile_top #(
    parameter logic [3:0]  TILE_ID  = 4'h0,
    parameter logic [31:0] BUILD_ID = 32'h0000_0000,
    parameter integer IMEM_WORDS = 4096,
    parameter integer DMEM_WORDS = 4096,
    parameter logic HAS_UART       = 1'b1
) (
    // ------------------------------------------------------------
    // Clock / reset
    // ------------------------------------------------------------
    input  logic        clk_i,
    input  logic        reset_i,

    // ------------------------------------------------------------
    // Instruction memory
    // ------------------------------------------------------------
    output logic        imem_valid_o,
    output logic [31:0] imem_addr_o,
    output logic [31:0] imem_wdata_o,
    output logic [3:0]  imem_wstrb_o,
    input  logic        imem_ready_i,
    input  logic [31:0] imem_rdata_i,

    // ------------------------------------------------------------
    // Data memory
    // ------------------------------------------------------------
    output logic        dmem_valid_o,
    output logic [31:0] dmem_addr_o,
    output logic [31:0] dmem_wdata_o,
    output logic [3:0]  dmem_wstrb_o,
    input  logic        dmem_ready_i,
    input  logic [31:0] dmem_rdata_i,

    // ------------------------------------------------------------
    // UART
    // ------------------------------------------------------------
    output logic        uart_tx_o,

    // ------------------------------------------------------------
    // GPIO
    // ------------------------------------------------------------
    input  logic [3:0]  switches_i,
    output logic [3:0]  leds_o,

    // ------------------------------------------------------------
    // Tile memory interface
    // ------------------------------------------------------------
    output logic        tmem_req_o,
    output logic        tmem_we_o,
    output logic [31:0] tmem_addr_o,
    output logic [31:0] tmem_wdata_o,
    output logic [3:0]  tmem_wstrb_o,
    output logic        tmem_is_fetch_o,

    input  logic        tmem_gnt_i,
    input  logic        tmem_rvalid_i,
    input  logic [31:0] tmem_rdata_i,
    input  logic        tmem_err_i,
    input  logic [3:0]  tmem_err_code_i,   // Lane 1 (A3): bridge error kind (sideband; the 10 TMEM signals are unchanged)
    input  logic [15:0] ni_timeout_count_i,
    input  logic [15:0] ni_refused_count_i,

    // ------------------------------------------------------------
    // Attestation / status
    // ------------------------------------------------------------
    input  logic        attested_i,
    input  logic        last_fault_timeout_i,
    output logic        attest_req_o,
    input  logic        grant_done_i,      // Lane 1 (B4): tile 3 GRANT accepted (pulse)
    input  logic        attest_failed_i,   // Lane 1 (B4): attestation failed (pulse)

    // ------------------------------------------------------------
    // Debug
    // ------------------------------------------------------------
    output logic [31:0] dbg_pc_o,
    output logic [31:0] dbg_inst_o,
    output logic        dbg_valid_o,
    output logic        dbg_trap_o
);

    // ------------------------------------------------------------
    // PicoRV32 native memory interface
    // ------------------------------------------------------------

    // Lane 1 (A3)
    localparam int BUS_ERR_IRQ = 3;   // lines 0-2: timer, EBREAK/ECALL/illegal insn, misaligned
    logic        bus_fault;
    logic [31:0] fault_addr;
    logic [3:0]  fault_code;

    logic        mem_valid;
    logic        mem_instr;
    logic        mem_ready;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [3:0]  mem_wstrb;
    logic [31:0] mem_rdata;

    // ------------------------------------------------------------
    // Adapter local interface
    // ------------------------------------------------------------

    logic        local_req;
    logic        local_we;
    logic [31:0] local_addr;
    logic [31:0] local_wdata;
    logic [3:0]  local_wstrb;
    logic        local_is_fetch;

    logic        local_gnt;
    logic        local_rvalid;
    logic [31:0] local_rdata;
    logic        local_err;

    // ------------------------------------------------------------
    // UART interface
    // ------------------------------------------------------------

    logic        uart_req;
    logic        uart_we;
    logic [31:0] uart_addr;
    logic [31:0] uart_wdata;
    logic [3:0]  uart_wstrb;
    logic        uart_gnt;
    logic        uart_rvalid;
    logic [31:0] uart_rdata;
    logic        uart_err;

    // ------------------------------------------------------------
    // GPIO interface
    // ------------------------------------------------------------

    logic        gpio_req;
    logic        gpio_we;
    logic [31:0] gpio_addr;
    logic [31:0] gpio_wdata;
    logic [3:0]  gpio_wstrb;
    logic        gpio_gnt;
    logic        gpio_rvalid;
    logic [31:0] gpio_rdata;
    logic        gpio_err;

    // ------------------------------------------------------------
    // Tile status interface
    // ------------------------------------------------------------

    logic        status_req;
    logic        status_we;
    logic [31:0] status_addr;
    logic [31:0] status_wdata;
    logic [3:0]  status_wstrb;
    logic        status_gnt;
    logic        status_rvalid;
    logic [31:0] status_rdata;
    logic        status_err;
    logic ni_req, ni_we, ni_rvalid, ni_err;
    logic [31:0] ni_addr, ni_rdata;

    // M-F1 rev 9: read-only bridge status; one-cycle response, undefined offsets/writes error.
    always_ff @(posedge clk_i) begin
        if (reset_i) begin ni_rvalid<=0; ni_err<=0; ni_rdata<=0; end
        else begin
            ni_rvalid <= ni_req;
            ni_err <= ni_req && (ni_we || !(ni_addr==0 || ni_addr==4 || ni_addr==8 || ni_addr==12));
            ni_rdata <= 0;
            if (ni_req && !ni_we) case(ni_addr)
                0: ni_rdata <= {28'b0,tmem_err_code_i};
                4: ni_rdata <= {16'b0,ni_timeout_count_i};
                8: ni_rdata <= {16'b0,ni_refused_count_i};
                12: ni_rdata <= 32'd9;
                default: ni_rdata <= 0;
            endcase
        end
    end

    // ------------------------------------------------------------
    // PicoRV32
    // ------------------------------------------------------------

    picorv32 #(
        .COMPRESSED_ISA(1),
        .ENABLE_MUL(1),
        .ENABLE_DIV(1),
        .ENABLE_IRQ(1)   // Lane 1 2026-11-06 (A3): bus errors raise irq[BUS_ERR_IRQ]; all IRQs are masked at reset   // Lane 1 2026-11-06 (R-D9): the declared ISA is RV32IMC (docs/riscv_lane/CPU_MEMORY_CONTRACT.md) and the firmware uses div/rem
    ) cpu (
        .clk       (clk_i),
        .resetn    (~reset_i),

        .mem_valid (mem_valid),
        .mem_instr (mem_instr),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata),

        .irq       (32'(bus_fault) << BUS_ERR_IRQ)   // Lane 1 (A3)
    );

    // ------------------------------------------------------------
    // PicoRV32 -> local / remote adapter
    // ------------------------------------------------------------

    picorv32_adapter adapter_inst (
        .clk_i       (clk_i),
        .reset_i     (reset_i),

        .mem_valid_i (mem_valid),
        .mem_instr_i (mem_instr),
        .mem_addr_i  (mem_addr),
        .mem_wdata_i (mem_wdata),
        .mem_wstrb_i (mem_wstrb),

        .mem_ready_o (mem_ready),
        .mem_rdata_o (mem_rdata),

        .local_req_o      (local_req),
        .local_we_o       (local_we),
        .local_addr_o     (local_addr),
        .local_wdata_o    (local_wdata),
        .local_wstrb_o    (local_wstrb),
        .local_is_fetch_o (local_is_fetch),

        .local_gnt_i      (local_gnt),
        .local_rvalid_i   (local_rvalid),
        .local_rdata_i    (local_rdata),
        .local_err_i      (local_err),

        .tmem_req_o       (tmem_req_o),
        .tmem_we_o        (tmem_we_o),
        .tmem_addr_o      (tmem_addr_o),
        .tmem_wdata_o     (tmem_wdata_o),
        .tmem_wstrb_o     (tmem_wstrb_o),
        .tmem_is_fetch_o  (tmem_is_fetch_o),

        .tmem_gnt_i       (tmem_gnt_i),
        .tmem_rvalid_i    (tmem_rvalid_i),
        .tmem_rdata_i     (tmem_rdata_i),
        .tmem_err_i       (tmem_err_i),
        .tmem_err_code_i  (tmem_err_code_i),
        .bus_fault_o      (bus_fault),
        .fault_addr_o     (fault_addr),
        .fault_code_o     (fault_code)
    );

    // ------------------------------------------------------------
    // Local address decoder
    // ------------------------------------------------------------

    addr_decode addr_decode_inst (
        .clk_i            (clk_i),
        .reset_i          (reset_i),

        .local_req_i      (local_req),
        .local_we_i       (local_we),
        .local_addr_i     (local_addr),
        .local_wdata_i    (local_wdata),
        .local_wstrb_i    (local_wstrb),
        .local_is_fetch_i (local_is_fetch),

        .local_gnt_o      (local_gnt),
        .local_rvalid_o   (local_rvalid),
        .local_rdata_o    (local_rdata),
        .local_err_o      (local_err),

        .imem_valid_o     (imem_valid_o),
        .imem_addr_o      (imem_addr_o),
        .imem_wdata_o     (imem_wdata_o),
        .imem_wstrb_o     (imem_wstrb_o),
        .imem_ready_i     (imem_ready_i),
        .imem_rdata_i     (imem_rdata_i),

        .dmem_valid_o     (dmem_valid_o),
        .dmem_addr_o      (dmem_addr_o),
        .dmem_wdata_o     (dmem_wdata_o),
        .dmem_wstrb_o     (dmem_wstrb_o),
        .dmem_ready_i     (dmem_ready_i),
        .dmem_rdata_i     (dmem_rdata_i),

        .uart_req_o       (uart_req),
        .uart_we_o        (uart_we),
        .uart_addr_o      (uart_addr),
        .uart_wdata_o     (uart_wdata),
        .uart_wstrb_o     (uart_wstrb),
        .uart_gnt_i       (uart_gnt),
        .uart_rvalid_i    (uart_rvalid),
        .uart_rdata_i     (uart_rdata),
        .uart_err_i       (uart_err),

        .gpio_req_o       (gpio_req),
        .gpio_we_o        (gpio_we),
        .gpio_addr_o      (gpio_addr),
        .gpio_wdata_o     (gpio_wdata),
        .gpio_wstrb_o     (gpio_wstrb),
        .gpio_gnt_i       (gpio_gnt),
        .gpio_rvalid_i    (gpio_rvalid),
        .gpio_rdata_i     (gpio_rdata),
        .gpio_err_i       (gpio_err),

        .status_req_o     (status_req),
        .status_we_o      (status_we),
        .status_addr_o    (status_addr),
        .status_wdata_o   (status_wdata),
        .status_wstrb_o   (status_wstrb),
        .status_gnt_i     (status_gnt),
        .status_rvalid_i  (status_rvalid),
        .status_rdata_i   (status_rdata),
        .status_err_i     (status_err),
        .ni_req_o(ni_req), .ni_we_o(ni_we), .ni_addr_o(ni_addr),
        .ni_rvalid_i(ni_rvalid), .ni_rdata_i(ni_rdata), .ni_err_i(ni_err)
    );

    // ------------------------------------------------------------
    // UART
    // ------------------------------------------------------------

    generate
        if (HAS_UART) begin : gen_uart

            uart_mmio uart_mmio_inst (
                .clk_i    (clk_i),
                .reset_i  (reset_i),

                .req_i    (uart_req),
                .we_i     (uart_we),
                .addr_i   (uart_addr),
                .wdata_i  (uart_wdata),
                .wstrb_i  (uart_wstrb),

                .gnt_o    (uart_gnt),
                .rvalid_o (uart_rvalid),
                .rdata_o  (uart_rdata),
                .err_o    (uart_err),

                .tx_o     (uart_tx_o)
            );

        end
        else begin : gen_no_uart

            assign uart_gnt    = 1'b0;
            assign uart_rvalid = 1'b0;
            assign uart_rdata  = 32'b0;
            assign uart_err    = 1'b0;
            assign uart_tx_o   = 1'b1;

        end
    endgenerate

    // ------------------------------------------------------------
    // GPIO
    // ------------------------------------------------------------

    gpio gpio_inst (
        .clk_i      (clk_i),
        .reset_i    (reset_i),

        .req_i      (gpio_req),
        .we_i       (gpio_we),
        .addr_i     (gpio_addr),
        .wdata_i    (gpio_wdata),
        .wstrb_i    (gpio_wstrb),

        .gnt_o      (gpio_gnt),
        .rvalid_o   (gpio_rvalid),
        .rdata_o    (gpio_rdata),
        .err_o      (gpio_err),

        .switches_i (switches_i),
        .leds_o     (leds_o)
    );

    // ------------------------------------------------------------
    // Tile status
    // ------------------------------------------------------------

    tile_status tile_status_inst (
        .clk_i                (clk_i),
        .reset_i              (reset_i),

        .req_i                (status_req),
        .we_i                 (status_we),
        .addr_i               (status_addr),
        .wdata_i              (status_wdata),
        .wstrb_i              (status_wstrb),

        .gnt_o                (status_gnt),
        .rvalid_o             (status_rvalid),
        .rdata_o              (status_rdata),
        .err_o                (status_err),

        .build_id_i           (BUILD_ID),
        .tile_id_i            (TILE_ID),
        .attested_i           (attested_i),
        .last_fault_timeout_i (last_fault_timeout_i),
        .grant_done_i         (grant_done_i),
        .attest_failed_i      (attest_failed_i),
        .bus_fault_i          (bus_fault),
        .fault_addr_i         (fault_addr),
        .fault_code_i         (fault_code),
        .attest_req_o         (attest_req_o)
    );

    // ------------------------------------------------------------
    // Debug taps
    // ------------------------------------------------------------

    always_ff @(posedge clk_i) begin
        if (reset_i) dbg_pc_o <= 0;
        else if (mem_valid && mem_ready && mem_instr) dbg_pc_o <= mem_addr;
    end
    assign dbg_inst_o  = mem_rdata;
    assign dbg_valid_o = mem_valid && mem_instr;
    assign dbg_trap_o  = bus_fault;   // Lane 1 (A3): pulse on every bus error

endmodule
