`timescale 1ns / 1ps

module tb_cpu_mem;

    logic clk;
    logic resetn;

    wire        mem_valid;
    wire        mem_instr;
    logic       mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    logic [31:0] mem_rdata;

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

    logic [31:0] mem [0:4095];

    integer i;
    integer errors;
    integer instructions;

    initial begin
        for (i = 0; i < 4096; i = i + 1)
            mem[i] = 32'h00000013;

        // --------------------------------
        // Initial data memory
        // --------------------------------

        // Address 0x100 = 0x12345678
        mem[32'h100 >> 2] = 32'h12345678;

        // Address 0x104 = 0x00000080
        mem[32'h104 >> 2] = 32'h00000080;

        // Address 0x108 = 0x0000007f
        mem[32'h108 >> 2] = 32'h0000007f;

        // --------------------------------
        // Program
        // --------------------------------

        // PC 0x00
        // ADDI x1, x0, 0x100
        // x1 = 0x100
        mem[0] = 32'h10000093;

        // PC 0x04
        // LW x2, 0(x1)
        // x2 = 0x12345678
        mem[1] = 32'h0000a103;

        // PC 0x08
        // ADDI x3, x2, 1
        // x3 = 0x12345679
        mem[2] = 32'h00110193;

        // PC 0x0C
        // SW x3, 0(x1)
        // Memory[0x100] = 0x12345679
        mem[3] = 32'h0030a023;

        // PC 0x10
        // LB x4, 4(x1)
        // 0x80 sign extends to 0xFFFFFF80
        mem[4] = 32'h00408203;

        // PC 0x14
        // LBU x5, 4(x1)
        // 0x80 zero extends to 0x00000080
        mem[5] = 32'h0040c283;

        // PC 0x18
        // LH x6, 4(x1)
        // 0x0080 sign extends to 0x00000080
        mem[6] = 32'h00409303;

        // PC 0x1C
        // LHU x7, 4(x1)
        // 0x0080 zero extends to 0x00000080
        mem[7] = 32'h0040d383;

        // PC 0x20
        // LW x8, 8(x1)
        // x8 = 0x0000007F
        mem[8] = 32'h0080a403;

        // PC 0x24
        // ADDI x9, x0, -1
        // x9 = 0xFFFFFFFF
        mem[9] = 32'hfff00493;

        // PC 0x28
        // SB x9, 8(x1)
        // Writes FF to address 0x108
        mem[10] = 32'h00908423;

        // PC 0x2C
        // LBU x10, 8(x1)
        // x10 = 0x000000FF
        mem[11] = 32'h0080c503;

        // PC 0x30
        // SH x9, 10(x1)
        // Writes FFFF to address 0x10A.
        // Since 0x10A is byte offset 2 within word 0x108,
        // WSTRB must be 1100.
        mem[12] = 32'h00909523;

        // PC 0x34
        // LH x11, 10(x1)
        // x11 = 0xFFFFFFFF
        mem[13] = 32'h00a09583;

        // PC 0x38
        // Infinite loop
        mem[14] = 32'h0000006f;
    end

    // --------------------------------
    // Simple one-cycle memory model
    // --------------------------------

    always_ff @(posedge clk) begin
        if (!resetn) begin
            mem_ready <= 1'b0;
            mem_rdata <= 32'b0;
        end
        else begin
            mem_ready <= 1'b0;

            if (mem_valid) begin
                mem_ready <= 1'b1;

                if (mem_addr[31:14] == 18'b0) begin

                    // Write
                    if (mem_wstrb != 4'b0000) begin

                        if (mem_wstrb[0])
                            mem[mem_addr[13:2]][7:0] <=
                                mem_wdata[7:0];

                        if (mem_wstrb[1])
                            mem[mem_addr[13:2]][15:8] <=
                                mem_wdata[15:8];

                        if (mem_wstrb[2])
                            mem[mem_addr[13:2]][23:16] <=
                                mem_wdata[23:16];

                        if (mem_wstrb[3])
                            mem[mem_addr[13:2]][31:24] <=
                                mem_wdata[31:24];

                        mem_rdata <= mem[mem_addr[13:2]];
                    end

                    // Read
                    else begin
                        mem_rdata <= mem[mem_addr[13:2]];
                    end
                end
                else begin
                    mem_rdata <= 32'b0;
                end
            end
        end
    end

    // --------------------------------
    // PicoRV32
    // --------------------------------

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

        // RVFI
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

    // --------------------------------
    // Clock
    // --------------------------------

    always #5 clk = ~clk;

    // --------------------------------
    // Reset
    // --------------------------------

    initial begin
        clk    = 1'b0;
        resetn = 1'b0;

        repeat (10)
            @(posedge clk);

        resetn = 1'b1;
    end

    // --------------------------------
    // Test completion
    // --------------------------------

    initial begin
        errors       = 0;
        instructions = 0;

        wait (resetn);

        repeat (300)
            @(posedge clk);

        $display("");
        $display("==============================================");
        $display(" CPU LOAD / STORE / IMMEDIATE ARCHITECTURAL TEST");
        $display("==============================================");
        $display("Instructions observed = %0d", instructions);
        $display("Errors                = %0d", errors);
        $display("----------------------------------------------");

        if (errors == 0)
            $display("PASS: CPU load/store/immediate test passed.");
        else
            $display(
                "FAIL: CPU load/store/immediate test found %0d errors.",
                errors
            );

        $display("==============================================");

        $finish;
    end

    // --------------------------------
    // RVFI architectural checker
    // --------------------------------

    always @(posedge clk) begin
        if (rvfi_valid) begin

            instructions = instructions + 1;

            // No unexpected traps.
            if (rvfi_trap) begin
                $display(
                    "ERROR: unexpected trap at PC %08h",
                    rvfi_pc_rdata
                );

                errors = errors + 1;
            end

            // --------------------------------
            // LW x2, 0(x1)
            // --------------------------------

            if (rvfi_pc_rdata == 32'h00000004) begin

                if (rvfi_rd_addr != 5'd2 ||
                    rvfi_rd_wdata != 32'h12345678) begin

                    $display(
                        "ERROR: LW failed: x2=%08h",
                        rvfi_rd_wdata
                    );

                    errors = errors + 1;
                end
            end

            // --------------------------------
            // ADDI x3, x2, 1
            // --------------------------------

            if (rvfi_pc_rdata == 32'h00000008) begin

                if (rvfi_rd_addr != 5'd3 ||
                    rvfi_rd_wdata != 32'h12345679) begin

                    $display(
                        "ERROR: ADDI failed: x3=%08h",
                        rvfi_rd_wdata
                    );

                    errors = errors + 1;
                end
            end

            // --------------------------------
            // SW x3, 0(x1)
            // --------------------------------

            if (rvfi_pc_rdata == 32'h0000000c) begin

                if (rvfi_mem_wmask != 4'b1111 ||
                    rvfi_mem_wdata != 32'h12345679) begin

                    $display("ERROR: SW failed");

                    errors = errors + 1;
                end
            end

            // --------------------------------
            // LB x4, 4(x1)
            // --------------------------------

            if (rvfi_pc_rdata == 32'h00000010) begin

                if (rvfi_rd_addr != 5'd4 ||
                    rvfi_rd_wdata != 32'hffffff80) begin

                    $display(
                        "ERROR: LB sign extension failed: x4=%08h",
                        rvfi_rd_wdata
                    );

                    errors = errors + 1;
                end
            end

            // --------------------------------
            // LBU x5, 4(x1)
            // --------------------------------

            if (rvfi_pc_rdata == 32'h00000014) begin

                if (rvfi_rd_addr != 5'd5 ||
                    rvfi_rd_wdata != 32'h00000080) begin

                    $display(
                        "ERROR: LBU zero extension failed: x5=%08h",
                        rvfi_rd_wdata
                    );

                    errors = errors + 1;
                end
            end

            // --------------------------------
            // LH x6, 4(x1)
            // --------------------------------

            if (rvfi_pc_rdata == 32'h00000018) begin

                if (rvfi_rd_addr != 5'd6 ||
                    rvfi_rd_wdata != 32'h00000080) begin

                    $display(
                        "ERROR: LH failed: x6=%08h",
                        rvfi_rd_wdata
                    );

                    errors = errors + 1;
                end
            end

            // --------------------------------
            // LHU x7, 4(x1)
            // --------------------------------

            if (rvfi_pc_rdata == 32'h0000001c) begin

                if (rvfi_rd_addr != 5'd7 ||
                    rvfi_rd_wdata != 32'h00000080) begin

                    $display(
                        "ERROR: LHU failed: x7=%08h",
                        rvfi_rd_wdata
                    );

                    errors = errors + 1;
                end
            end

            // --------------------------------
            // LW x8, 8(x1)
            // --------------------------------

            if (rvfi_pc_rdata == 32'h00000020) begin

                if (rvfi_rd_addr != 5'd8 ||
                    rvfi_rd_wdata != 32'h0000007f) begin

                    $display(
                        "ERROR: second LW failed: x8=%08h",
                        rvfi_rd_wdata
                    );

                    errors = errors + 1;
                end
            end

            // --------------------------------
            // SB x9, 8(x1)
            // --------------------------------

            if (rvfi_pc_rdata == 32'h00000028) begin

                if (rvfi_mem_wmask != 4'b0001) begin

                    $display(
                        "ERROR: SB WSTRB incorrect: %b",
                        rvfi_mem_wmask
                    );

                    errors = errors + 1;
                end
            end

            // --------------------------------
            // LBU after SB
            // --------------------------------

            if (rvfi_pc_rdata == 32'h0000002c) begin

                if (rvfi_rd_addr != 5'd10 ||
                    rvfi_rd_wdata != 32'h000000ff) begin

                    $display(
                        "ERROR: SB/LBU failed: x10=%08h",
                        rvfi_rd_wdata
                    );

                    errors = errors + 1;
                end
            end

            // --------------------------------
            // SH x9, 10(x1)
            //
            // Address = 0x10A.
            // This is byte lane 2 of word 0x108,
            // therefore WSTRB = 1100.
            // --------------------------------

            if (rvfi_pc_rdata == 32'h00000030) begin

                if (rvfi_mem_wmask != 4'b1100) begin

                    $display(
                        "ERROR: SH WSTRB incorrect: %b",
                        rvfi_mem_wmask
                    );

                    errors = errors + 1;
                end
            end

            // --------------------------------
            // LH after SH
            // --------------------------------

            if (rvfi_pc_rdata == 32'h00000034) begin

                if (rvfi_rd_addr != 5'd11 ||
                    rvfi_rd_wdata != 32'hffffffff) begin

                    $display(
                        "ERROR: SH/LH failed: x11=%08h",
                        rvfi_rd_wdata
                    );

                    errors = errors + 1;
                end
            end

        end
    end

endmodule