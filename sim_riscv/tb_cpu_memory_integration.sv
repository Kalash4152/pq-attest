`timescale 1ns / 1ps

module tb_cpu_memory_integration;

    logic clk;
    logic resetn;

    // ============================================================
    // PicoRV32 memory interface
    // ============================================================

    wire        mem_valid;
    wire        mem_instr;
    logic       mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    logic [31:0] mem_rdata;

    // ============================================================
    // RVFI
    // ============================================================

    wire        rvfi_valid;
    wire [63:0] rvfi_order;
    wire [31:0] rvfi_insn;
    wire        rvfi_trap;
    wire        rvfi_halt;
    wire        rvfi_intr;
    wire [1:0]  rvfi_mode;
    wire [1:0]  rvfi_ixl;
    wire [4:0]  rvfi_rs1_addr;
    wire [4:0]  rvfi_rs2_addr;
    wire [31:0] rvfi_rs1_rdata;
    wire [31:0] rvfi_rs2_rdata;
    wire [4:0]  rvfi_rd_addr;
    wire [31:0] rvfi_rd_wdata;
    wire [31:0] rvfi_pc_rdata;
    wire [31:0] rvfi_pc_wdata;
    wire [31:0] rvfi_mem_addr;
    wire [3:0]  rvfi_mem_rmask;
    wire [3:0]  rvfi_mem_wmask;
    wire [31:0] rvfi_mem_rdata;
    wire [31:0] rvfi_mem_wdata;

    wire [63:0] rvfi_csr_mcycle_rmask;
    wire [63:0] rvfi_csr_mcycle_wmask;
    wire [63:0] rvfi_csr_mcycle_rdata;
    wire [63:0] rvfi_csr_mcycle_wdata;
    wire [63:0] rvfi_csr_minstret_rmask;
    wire [63:0] rvfi_csr_minstret_wmask;
    wire [63:0] rvfi_csr_minstret_rdata;
    wire [63:0] rvfi_csr_minstret_wdata;

    // ============================================================
    // Memory
    // ============================================================

    logic [31:0] mem [0:4095];

    integer i;
    integer errors;
    integer instructions;
    integer transaction_count;

    // ============================================================
    // Outstanding request
    // ============================================================

    logic        active_request;

    logic [31:0] held_addr;
    logic [31:0] held_wdata;
    logic [3:0]  held_wstrb;
    logic        held_instr;

    integer stall_counter;

    // ============================================================
    // Stability checker
    // ============================================================

    logic        stability_active;
    logic [31:0] stability_addr;
    logic [31:0] stability_wdata;
    logic [3:0]  stability_wstrb;
    logic        stability_instr;


    // ============================================================
    // PROGRAM
    // ============================================================

    initial begin

        for (i = 0; i < 4096; i = i + 1)
            mem[i] = 32'h00000013;

        // PC 0x00
        // ADDI x1, x0, 0x100
        mem[0] = 32'h10000093;

        // PC 0x04
        // LUI x2, 0x12345
        mem[1] = 32'h12345137;

        // PC 0x08
        // ADDI x2, x2, 0x678
        mem[2] = 32'h67810113;

        // PC 0x0C
        // SW x2, 0(x1)
        mem[3] = 32'h0020a023;

        // PC 0x10
        // LW x3, 0(x1)
        mem[4] = 32'h0000a183;

        // PC 0x14
        // ADDI x4, x3, 1
        mem[5] = 32'h00118213;

        // PC 0x18
        // SW x4, 4(x1)
        mem[6] = 32'h0040a223;

        // PC 0x1C
        // LW x5, 4(x1)
        mem[7] = 32'h0040a283;

        // PC 0x20
        // Infinite loop
        mem[8] = 32'h0000006f;

    end


    // ============================================================
    // CLOCK
    // ============================================================

    always #5 clk = ~clk;


    // ============================================================
    // RESET
    // ============================================================

    initial begin

        clk    = 1'b0;
        resetn = 1'b0;

        repeat (10)
            @(posedge clk);

        resetn = 1'b1;

    end


    // ============================================================
    // RESPONSE
    //
    // mem_ready is combinational.
    //
    // When stall_counter reaches zero:
    //
    //     mem_rdata = valid data
    //     mem_ready = 1
    //
    // BOTH are already stable before the active clock edge.
    // ============================================================

    always_comb begin

        mem_ready = 1'b0;
        mem_rdata = 32'b0;

        if (active_request) begin

            // Read data is always available from the held address.
            if (held_addr[31:14] == 18'b0)
                mem_rdata = mem[held_addr[13:2]];
            else
                mem_rdata = 32'b0;

            // Complete after deliberate stall.
            if (stall_counter == 0)
                mem_ready = 1'b1;

        end

    end


    // ============================================================
    // REQUEST CAPTURE / RESPONSE RETIREMENT
    // ============================================================

    always_ff @(posedge clk) begin

        if (!resetn) begin

            active_request <= 1'b0;

            held_addr  <= 32'b0;
            held_wdata <= 32'b0;
            held_wstrb <= 4'b0;
            held_instr <= 1'b0;

            stall_counter <= 0;

            transaction_count <= 0;

        end
        else begin

            // ----------------------------------------------------
            // Capture a new request.
            // ----------------------------------------------------

            if (!active_request && mem_valid) begin

                active_request <= 1'b1;

                held_addr  <= mem_addr;
                held_wdata <= mem_wdata;
                held_wstrb <= mem_wstrb;
                held_instr <= mem_instr;

                // Exactly three stall cycles.
                stall_counter <= 3;

            end

            // ----------------------------------------------------
            // Existing request.
            // ----------------------------------------------------

            else if (active_request) begin

                if (stall_counter > 0) begin

                    stall_counter <= stall_counter - 1;

                end

                else if (mem_ready) begin

                    // ------------------------------------------------
                    // Exactly one response.
                    // ------------------------------------------------

                    transaction_count <=
                        transaction_count + 1;

                    // ------------------------------------------------
                    // Perform byte-lane writes.
                    // ------------------------------------------------

                    if (held_wstrb[0])
                        mem[held_addr[13:2]][7:0] <=
                            held_wdata[7:0];

                    if (held_wstrb[1])
                        mem[held_addr[13:2]][15:8] <=
                            held_wdata[15:8];

                    if (held_wstrb[2])
                        mem[held_addr[13:2]][23:16] <=
                            held_wdata[23:16];

                    if (held_wstrb[3])
                        mem[held_addr[13:2]][31:24] <=
                            held_wdata[31:24];

                    active_request <= 1'b0;

                end

            end

        end

    end


// ============================================================
// REQUEST STABILITY CHECKER
// ============================================================

always @(posedge clk) begin

    if (!resetn) begin
        stability_active = 1'b0;
    end
    else begin

        if (mem_valid && !mem_ready) begin

            if (!stability_active) begin
                stability_active = 1'b1;

                stability_addr  = mem_addr;
                stability_wdata = mem_wdata;
                stability_wstrb = mem_wstrb;
                stability_instr = mem_instr;
            end
            else begin

                // mem_valid must remain asserted during a stall.
                if (!mem_valid) begin
                    $display("ERROR: mem_valid dropped during stall");
                    errors = errors + 1;
                end

                if (mem_addr !== stability_addr) begin
                    $display(
                        "ERROR: mem_addr changed during stall"
                    );
                    errors = errors + 1;
                end

                if (mem_wdata !== stability_wdata) begin
                    $display(
                        "ERROR: mem_wdata changed during stall"
                    );
                    errors = errors + 1;
                end

                if (mem_wstrb !== stability_wstrb) begin
                    $display(
                        "ERROR: mem_wstrb changed during stall"
                    );
                    errors = errors + 1;
                end

                if (mem_instr !== stability_instr) begin
                    $display(
                        "ERROR: mem_instr changed during stall"
                    );
                    errors = errors + 1;
                end

            end
        end
        else begin
            stability_active = 1'b0;
        end

    end
end
    // ============================================================
    // PicoRV32
    // ============================================================

    picorv32 #(
        .COMPRESSED_ISA(1),
        .ENABLE_MUL(1)
    ) dut (

        .clk       (clk),
        .resetn    (resetn),

        .mem_valid (mem_valid),
        .mem_instr (mem_instr),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata),

        .irq       (32'b0),

        .rvfi_valid              (rvfi_valid),
        .rvfi_order              (rvfi_order),
        .rvfi_insn               (rvfi_insn),
        .rvfi_trap               (rvfi_trap),
        .rvfi_halt               (rvfi_halt),
        .rvfi_intr               (rvfi_intr),
        .rvfi_mode               (rvfi_mode),
        .rvfi_ixl                (rvfi_ixl),
        .rvfi_rs1_addr           (rvfi_rs1_addr),
        .rvfi_rs2_addr           (rvfi_rs2_addr),
        .rvfi_rs1_rdata          (rvfi_rs1_rdata),
        .rvfi_rs2_rdata          (rvfi_rs2_rdata),
        .rvfi_rd_addr            (rvfi_rd_addr),
        .rvfi_rd_wdata           (rvfi_rd_wdata),
        .rvfi_pc_rdata           (rvfi_pc_rdata),
        .rvfi_pc_wdata           (rvfi_pc_wdata),
        .rvfi_mem_addr           (rvfi_mem_addr),
        .rvfi_mem_rmask          (rvfi_mem_rmask),
        .rvfi_mem_wmask          (rvfi_mem_wmask),
        .rvfi_mem_rdata          (rvfi_mem_rdata),
        .rvfi_mem_wdata          (rvfi_mem_wdata),

        .rvfi_csr_mcycle_rmask   (rvfi_csr_mcycle_rmask),
        .rvfi_csr_mcycle_wmask   (rvfi_csr_mcycle_wmask),
        .rvfi_csr_mcycle_rdata   (rvfi_csr_mcycle_rdata),
        .rvfi_csr_mcycle_wdata   (rvfi_csr_mcycle_wdata),
        .rvfi_csr_minstret_rmask (rvfi_csr_minstret_rmask),
        .rvfi_csr_minstret_wmask (rvfi_csr_minstret_wmask),
        .rvfi_csr_minstret_rdata (rvfi_csr_minstret_rdata),
        .rvfi_csr_minstret_wdata (rvfi_csr_minstret_wdata)

    );


    // ============================================================
    // ARCHITECTURAL CHECKER
    // ============================================================

    always @(posedge clk) begin

        if (rvfi_valid) begin

            instructions = instructions + 1;

            if (rvfi_trap) begin

                $display(
                    "ERROR: unexpected CPU trap at PC %08h",
                    rvfi_pc_rdata
                );

                errors = errors + 1;

            end

            // ----------------------------------------------------
            // LW x3, 0(x1)
            // ----------------------------------------------------

            if (rvfi_pc_rdata == 32'h00000010) begin

                if (rvfi_rd_addr != 5'd3 ||
                    rvfi_rd_wdata != 32'h12345678) begin

                    $display(
                        "ERROR: first LW incorrect: x3=%08h",
                        rvfi_rd_wdata
                    );

                    errors = errors + 1;

                end

            end

            // ----------------------------------------------------
            // ADDI x4, x3, 1
            // ----------------------------------------------------

            if (rvfi_pc_rdata == 32'h00000014) begin

                if (rvfi_rd_addr != 5'd4 ||
                    rvfi_rd_wdata != 32'h12345679) begin

                    $display(
                        "ERROR: ADDI incorrect: x4=%08h",
                        rvfi_rd_wdata
                    );

                    errors = errors + 1;

                end

            end

            // ----------------------------------------------------
            // LW x5, 4(x1)
            // ----------------------------------------------------

            if (rvfi_pc_rdata == 32'h0000001c) begin

                if (rvfi_rd_addr != 5'd5 ||
                    rvfi_rd_wdata != 32'h12345679) begin

                    $display(
                        "ERROR: second LW incorrect: x5=%08h",
                        rvfi_rd_wdata
                    );

                    errors = errors + 1;

                end

            end

        end

    end


    // ============================================================
    // FINAL RESULT
    // ============================================================

    initial begin

        errors       = 0;
        instructions = 0;

        wait (resetn);

        repeat (800)
            @(posedge clk);

        $display("");
        $display("==============================================");
        $display(" CPU <-> MEMORY INTEGRATION TEST");
        $display("==============================================");
        $display("Instructions observed = %0d", instructions);
        $display("Memory transactions    = %0d", transaction_count);
        $display("Errors                 = %0d", errors);
        $display("----------------------------------------------");

        if (errors == 0 && instructions > 0 && transaction_count > 0)
            $display("PASS: CPU/memory integration with stalls passed.");
        else begin
            if (instructions == 0)
                $display("ERROR: No CPU instructions were observed.");
            if (transaction_count == 0)
                $display("ERROR: No memory transactions were completed.");

            $display("FAIL: CPU/memory integration found %0d errors.",errors);
        end

        $display("==============================================");

        $finish;

    end

endmodule