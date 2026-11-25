`timescale 1ns / 1ps

module tb_cpu_alu;

    logic clk;
    logic resetn;

    // PicoRV32 native memory interface
    wire        mem_valid;
    wire        mem_instr;
    logic       mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    logic [31:0] mem_rdata;

    // RVFI
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

    // Unused RVFI CSR outputs
    wire [63:0] rvfi_csr_mcycle_rmask;
    wire [63:0] rvfi_csr_mcycle_wmask;
    wire [63:0] rvfi_csr_mcycle_rdata;
    wire [63:0] rvfi_csr_mcycle_wdata;

    wire [63:0] rvfi_csr_minstret_rmask;
    wire [63:0] rvfi_csr_minstret_wmask;
    wire [63:0] rvfi_csr_minstret_rdata;
    wire [63:0] rvfi_csr_minstret_wdata;


    // ============================================================
    // Simple 16 KB instruction/data memory
    // ============================================================

    logic [31:0] mem [0:4095];

    integer i;

    initial begin
        for (i = 0; i < 4096; i = i + 1)
            mem[i] = 32'h00000013;   // nop = addi x0,x0,0

        // Test program
        mem[0]  = 32'h00500093; // addi x1,  x0, 5
        mem[1]  = 32'h00300113; // addi x2,  x0, 3
        mem[2]  = 32'h002081b3; // add  x3,  x1, x2
        mem[3]  = 32'h40208233; // sub  x4,  x1, x2
        mem[4]  = 32'h0020f2b3; // and  x5,  x1, x2
        mem[5]  = 32'h0020e333; // or   x6,  x1, x2
        mem[6]  = 32'h0020c3b3; // xor  x7,  x1, x2
        mem[7]  = 32'h00209433; // sll  x8,  x1, x2
        mem[8]  = 32'h0020d4b3; // srl  x9,  x1, x2
        mem[9]  = 32'h4020d533; // sra  x10, x1, x2
        mem[10] = 32'h00900013; // addi x0,  x0, 9 -- must NOT change x0
        mem[11] = 32'h00700593; // addi x11, x0, 7

        // Infinite loop
        mem[12] = 32'h0000006f; // jal x0, 0
    end


    // One-cycle memory response.
    always_ff @(posedge clk) begin
        if (!resetn) begin
            mem_ready <= 1'b0;
            mem_rdata <= 32'b0;
        end
        else begin
            mem_ready <= 1'b0;

            if (mem_valid) begin
                mem_ready <= 1'b1;

                if (mem_addr[31:14] == 18'b0)
                    mem_rdata <= mem[mem_addr[13:2]];
                else
                    mem_rdata <= 32'b0;
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

        .rvfi_valid            (rvfi_valid),
        .rvfi_order            (rvfi_order),
        .rvfi_insn             (rvfi_insn),
        .rvfi_trap             (rvfi_trap),
        .rvfi_halt             (rvfi_halt),
        .rvfi_intr             (rvfi_intr),
        .rvfi_mode             (rvfi_mode),
        .rvfi_ixl              (rvfi_ixl),
        .rvfi_rs1_addr         (rvfi_rs1_addr),
        .rvfi_rs2_addr         (rvfi_rs2_addr),
        .rvfi_rs1_rdata        (rvfi_rs1_rdata),
        .rvfi_rs2_rdata        (rvfi_rs2_rdata),
        .rvfi_rd_addr          (rvfi_rd_addr),
        .rvfi_rd_wdata         (rvfi_rd_wdata),
        .rvfi_pc_rdata         (rvfi_pc_rdata),
        .rvfi_pc_wdata         (rvfi_pc_wdata),
        .rvfi_mem_addr         (rvfi_mem_addr),
        .rvfi_mem_rmask        (rvfi_mem_rmask),
        .rvfi_mem_wmask        (rvfi_mem_wmask),
        .rvfi_mem_rdata        (rvfi_mem_rdata),
        .rvfi_mem_wdata        (rvfi_mem_wdata),
        .rvfi_csr_mcycle_rmask (rvfi_csr_mcycle_rmask),
        .rvfi_csr_mcycle_wmask (rvfi_csr_mcycle_wmask),
        .rvfi_csr_mcycle_rdata (rvfi_csr_mcycle_rdata),
        .rvfi_csr_mcycle_wdata (rvfi_csr_mcycle_wdata),
        .rvfi_csr_minstret_rmask(rvfi_csr_minstret_rmask),
        .rvfi_csr_minstret_wmask(rvfi_csr_minstret_wmask),
        .rvfi_csr_minstret_rdata(rvfi_csr_minstret_rdata),
        .rvfi_csr_minstret_wdata(rvfi_csr_minstret_wdata)
    );


    // ============================================================
    // Clock / reset
    // ============================================================

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        resetn = 1'b0;

        repeat (10)
            @(posedge clk);

        resetn = 1'b1;
    end


    // ============================================================
    // Architectural checker
    // ============================================================

    integer errors;
    integer instructions;

    initial begin
        errors = 0;
        instructions = 0;

        wait (resetn == 1'b1);

        repeat (300)
            @(posedge clk);

        $display("");
        $display("==============================================");
        $display(" CPU ALU / REGISTER ARCHITECTURAL TEST");
        $display("==============================================");
        $display("Instructions observed = %0d", instructions);
        $display("Errors                = %0d", errors);
        $display("----------------------------------------------");

        if (errors == 0)
            $display("PASS: CPU ALU/register architectural test passed.");
        else
            $display("FAIL: CPU architectural test found %0d errors.", errors);

        $display("==============================================");

        $finish;
    end


    always @(posedge clk) begin
        if (rvfi_valid) begin

            instructions = instructions + 1;

            // x0 must always read as zero.
            if (rvfi_rs1_addr == 5'd0 &&
                rvfi_rs1_rdata !== 32'h00000000) begin
                $display("ERROR: x0 read was %h", rvfi_rs1_rdata);
                errors = errors + 1;
            end

            if (rvfi_rs2_addr == 5'd0 &&
                rvfi_rs2_rdata !== 32'h00000000) begin
                $display("ERROR: x0 second read was %h", rvfi_rs2_rdata);
                errors = errors + 1;
            end

            // x0 must never receive a non-zero architectural write.
            if (rvfi_rd_addr == 5'd0 &&
                rvfi_rd_wdata !== 32'h00000000) begin
                $display("ERROR: x0 was written with %h", rvfi_rd_wdata);
                errors = errors + 1;
            end

            // No trap is expected in this program.
            if (rvfi_trap) begin
                $display("ERROR: unexpected trap at PC %08h",
                         rvfi_pc_rdata);
                errors = errors + 1;
            end

            // Check the expected ALU results.
            case (rvfi_pc_rdata)

                32'h00000000: begin
                    if (rvfi_rd_addr != 5'd1 ||
                        rvfi_rd_wdata != 32'd5) begin
                        $display("ERROR: ADDI x1 expected 5, got x%0d=%h",
                                 rvfi_rd_addr, rvfi_rd_wdata);
                        errors = errors + 1;
                    end
                end

                32'h00000004: begin
                    if (rvfi_rd_addr != 5'd2 ||
                        rvfi_rd_wdata != 32'd3) begin
                        $display("ERROR: ADDI x2 expected 3, got x%0d=%h",
                                 rvfi_rd_addr, rvfi_rd_wdata);
                        errors = errors + 1;
                    end
                end

                32'h00000008: begin
                    if (rvfi_rd_addr != 5'd3 ||
                        rvfi_rd_wdata != 32'd8) begin
                        $display("ERROR: ADD x3 expected 8, got %h",
                                 rvfi_rd_wdata);
                        errors = errors + 1;
                    end
                end

                32'h0000000c: begin
                    if (rvfi_rd_addr != 5'd4 ||
                        rvfi_rd_wdata != 32'd2) begin
                        $display("ERROR: SUB x4 expected 2, got %h",
                                 rvfi_rd_wdata);
                        errors = errors + 1;
                    end
                end

                32'h00000010: begin
                    if (rvfi_rd_addr != 5'd5 ||
                        rvfi_rd_wdata != 32'd1) begin
                        $display("ERROR: AND x5 expected 1, got %h",
                                 rvfi_rd_wdata);
                        errors = errors + 1;
                    end
                end

                32'h00000014: begin
                    if (rvfi_rd_addr != 5'd6 ||
                        rvfi_rd_wdata != 32'd7) begin
                        $display("ERROR: OR x6 expected 7, got %h",
                                 rvfi_rd_wdata);
                        errors = errors + 1;
                    end
                end

                32'h00000018: begin
                    if (rvfi_rd_addr != 5'd7 ||
                        rvfi_rd_wdata != 32'd6) begin
                        $display("ERROR: XOR x7 expected 6, got %h",
                                 rvfi_rd_wdata);
                        errors = errors + 1;
                    end
                end

                32'h0000001c: begin
                    if (rvfi_rd_addr != 5'd8 ||
                        rvfi_rd_wdata != 32'd40) begin
                        $display("ERROR: SLL x8 expected 40, got %h",
                                 rvfi_rd_wdata);
                        errors = errors + 1;
                    end
                end

                32'h00000020: begin
                    if (rvfi_rd_addr != 5'd9 ||
                        rvfi_rd_wdata != 32'd0) begin
                        $display("ERROR: SRL x9 expected 0, got %h",
                                 rvfi_rd_wdata);
                        errors = errors + 1;
                    end
                end

                32'h00000024: begin
                    if (rvfi_rd_addr != 5'd10 ||
                        rvfi_rd_wdata != 32'd0) begin
                        $display("ERROR: SRA x10 expected 0, got %h",
                                 rvfi_rd_wdata);
                        errors = errors + 1;
                    end
                end

                32'h00000028: begin
                    if (rvfi_rd_addr != 5'd0 ||
                        rvfi_rd_wdata != 32'd0) begin
                        $display("ERROR: x0 write behavior incorrect");
                        errors = errors + 1;
                    end
                end

                32'h0000002c: begin
                    if (rvfi_rd_addr != 5'd11 ||
                        rvfi_rd_wdata != 32'd7) begin
                        $display("ERROR: x11 expected 7, got %h",
                                 rvfi_rd_wdata);
                        errors = errors + 1;
                    end
                end

                default: begin
                    // Loop/nop activity after the test program is ignored.
                end

            endcase
        end
    end

endmodule