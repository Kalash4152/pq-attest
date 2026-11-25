`timescale 1ns / 1ps

module tb_cpu_branch;

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

        // x1 = 5
        mem[0] = 32'h00500093;

        // x2 = 5
        mem[1] = 32'h00500113;

        // BEQ x1,x2,+8
        // Taken: skip instruction at PC 0x0c.
        mem[2] = 32'h00208463;

        // This must be skipped.
        // x3 = 99
        mem[3] = 32'h06300193;

        // Target: x3 = 7
        mem[4] = 32'h00700193;

        // x4 = 6
        mem[5] = 32'h00600213;

        // BNE x3,x4,+8
        // Taken: skip instruction at PC 0x1c.
        mem[6] = 32'h00419463;

        // Must be skipped.
        // x5 = 99
        mem[7] = 32'h06300293;

        // Target: x5 = 11
        mem[8] = 32'h00b00293;

        // BLT x4,x5,+8
        // 6 < 11, so taken.
        mem[9] = 32'h00524463;

        // Must be skipped.
        mem[10] = 32'h06300313;

        // Target: x6 = 13
        mem[11] = 32'h00d00313;

        // BGE x5,x4,+8
        // 11 >= 6, so taken.
        mem[12] = 32'h0042d463;

        // Must be skipped.
        mem[13] = 32'h06300393;

        // Target: x7 = 17
        mem[14] = 32'h01100393;

        // JAL x8,+8
        // x8 receives PC+4.
        mem[15] = 32'h0080046f;

        // Must be skipped.
        mem[16] = 32'h06300493;

        // JAL target: x9 = 19
        mem[17] = 32'h01300493;

        // Infinite loop.
        mem[18] = 32'h0000006f;
    end

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

        .rvfi_valid             (rvfi_valid),
        .rvfi_order             (rvfi_order),
        .rvfi_insn              (rvfi_insn),
        .rvfi_trap              (rvfi_trap),
        .rvfi_halt              (rvfi_halt),
        .rvfi_intr              (rvfi_intr),
        .rvfi_mode              (rvfi_mode),
        .rvfi_ixl               (rvfi_ixl),
        .rvfi_rs1_addr          (rvfi_rs1_addr),
        .rvfi_rs2_addr          (rvfi_rs2_addr),
        .rvfi_rs1_rdata         (rvfi_rs1_rdata),
        .rvfi_rs2_rdata         (rvfi_rs2_rdata),
        .rvfi_rd_addr           (rvfi_rd_addr),
        .rvfi_rd_wdata          (rvfi_rd_wdata),
        .rvfi_pc_rdata          (rvfi_pc_rdata),
        .rvfi_pc_wdata          (rvfi_pc_wdata),
        .rvfi_mem_addr          (rvfi_mem_addr),
        .rvfi_mem_rmask         (rvfi_mem_rmask),
        .rvfi_mem_wmask         (rvfi_mem_wmask),
        .rvfi_mem_rdata         (rvfi_mem_rdata),
        .rvfi_mem_wdata         (rvfi_mem_wdata),

        .rvfi_csr_mcycle_rmask  (rvfi_csr_mcycle_rmask),
        .rvfi_csr_mcycle_wmask  (rvfi_csr_mcycle_wmask),
        .rvfi_csr_mcycle_rdata  (rvfi_csr_mcycle_rdata),
        .rvfi_csr_mcycle_wdata  (rvfi_csr_mcycle_wdata),
        .rvfi_csr_minstret_rmask(rvfi_csr_minstret_rmask),
        .rvfi_csr_minstret_wmask(rvfi_csr_minstret_wmask),
        .rvfi_csr_minstret_rdata(rvfi_csr_minstret_rdata),
        .rvfi_csr_minstret_wdata(rvfi_csr_minstret_wdata)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        resetn = 1'b0;

        repeat (10)
            @(posedge clk);

        resetn = 1'b1;
    end

    initial begin
        errors = 0;
        instructions = 0;

        wait (resetn);

        repeat (300)
            @(posedge clk);

        $display("");
        $display("==============================================");
        $display(" CPU BRANCH / JUMP / PC ARCHITECTURAL TEST");
        $display("==============================================");
        $display("Instructions observed = %0d", instructions);
        $display("Errors                = %0d", errors);
        $display("----------------------------------------------");

        if (errors == 0)
            $display("PASS: CPU branch/jump/PC test passed.");
        else
            $display("FAIL: CPU branch/jump/PC test found %0d errors.", errors);

        $display("==============================================");

        $finish;
    end

    always @(posedge clk) begin
        if (rvfi_valid) begin
            instructions = instructions + 1;

            if (rvfi_trap) begin
                $display("ERROR: unexpected trap at PC %08h",
                         rvfi_pc_rdata);
                errors = errors + 1;
            end

            case (rvfi_pc_rdata)

                // BEQ target: PC 0x10
                32'h00000010: begin
                    if (rvfi_rd_addr != 5'd3 ||
                        rvfi_rd_wdata != 32'd7) begin
                        $display("ERROR: BEQ target incorrect");
                        errors = errors + 1;
                    end
                end

                // BNE target: PC 0x20
                32'h00000020: begin
                    if (rvfi_rd_addr != 5'd5 ||
                        rvfi_rd_wdata != 32'd11) begin
                        $display("ERROR: BNE target incorrect");
                        errors = errors + 1;
                    end
                end

                // BLT target: PC 0x2c
                32'h0000002c: begin
                    if (rvfi_rd_addr != 5'd6 ||
                        rvfi_rd_wdata != 32'd13) begin
                        $display("ERROR: BLT target incorrect");
                        errors = errors + 1;
                    end
                end

                // BGE target: PC 0x38
                32'h00000038: begin
                    if (rvfi_rd_addr != 5'd7 ||
                        rvfi_rd_wdata != 32'd17) begin
                        $display("ERROR: BGE target incorrect");
                        errors = errors + 1;
                    end
                end

                // JAL target: PC 0x44.
                // JAL at PC 0x3c should write PC+4 = 0x40 to x8.
                32'h00000044: begin
                    if (rvfi_rd_addr != 5'd9 ||
                        rvfi_rd_wdata != 32'd19) begin
                        $display("ERROR: JAL target incorrect");
                        errors = errors + 1;
                    end
                end

                default: begin
                end

            endcase

            // Explicitly check that the JAL writes the correct link.
            if (rvfi_pc_rdata == 32'h0000003c) begin
                if (rvfi_rd_addr != 5'd8 ||
                    rvfi_rd_wdata != 32'h00000040) begin
                    $display("ERROR: JAL link incorrect: x8=%h",
                             rvfi_rd_wdata);
                    errors = errors + 1;
                end
            end
        end
    end

endmodule