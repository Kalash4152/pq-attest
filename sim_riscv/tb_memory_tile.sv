`timescale 1ns / 1ps

module tb_memory_tile;

    logic        clk;
    logic        reset;

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

    integer errors;

    always #5 clk = ~clk;

    memory_tile #(
        .TILE_ID   (4'h2),
        .MEM_WORDS (4096)
    ) dut (
        .clk_i           (clk),
        .reset_i         (reset),

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

    // ------------------------------------------------------------
    // WRITE
    // ------------------------------------------------------------
    task automatic write_word(
        input [31:0] addr,
        input [31:0] data,
        input [3:0]  strb
    );
        begin
            @(negedge clk);

            tmem_req      = 1'b1;
            tmem_we       = 1'b1;
            tmem_addr     = addr;
            tmem_wdata    = data;
            tmem_wstrb    = strb;
            tmem_is_fetch = 1'b0;

            wait (tmem_gnt == 1'b1);

            @(negedge clk);
            tmem_req = 1'b0;

            wait (tmem_rvalid == 1'b1);

            if (tmem_err !== 1'b0) begin
                $display(
                    "ERROR: write 0x%08h returned bus error",
                    addr
                );
                errors = errors + 1;
            end

            @(negedge clk);
        end
    endtask

    // ------------------------------------------------------------
    // READ
    // ------------------------------------------------------------
    task automatic read_word(
        input [31:0] addr,
        input [31:0] expected
    );
        begin
            @(negedge clk);

            tmem_req      = 1'b1;
            tmem_we       = 1'b0;
            tmem_addr     = addr;
            tmem_wdata    = 32'b0;
            tmem_wstrb    = 4'b0000;
            tmem_is_fetch = 1'b0;

            wait (tmem_gnt == 1'b1);

            @(negedge clk);
            tmem_req = 1'b0;

            wait (tmem_rvalid == 1'b1);

            if (tmem_err !== 1'b0) begin
                $display(
                    "ERROR: read 0x%08h returned bus error",
                    addr
                );
                errors = errors + 1;
            end

            if (tmem_rdata !== expected) begin
                $display(
                    "ERROR: read 0x%08h expected %08h got %08h",
                    addr,
                    expected,
                    tmem_rdata
                );
                errors = errors + 1;
            end

            @(negedge clk);
        end
    endtask

    // ------------------------------------------------------------
    // EXPECT ERROR
    // ------------------------------------------------------------
    task automatic expect_error(
        input [31:0] addr,
        input        write_access
    );
        begin
            @(negedge clk);

            tmem_req      = 1'b1;
            tmem_we       = write_access;
            tmem_addr     = addr;
            tmem_wdata    = 32'hDEAD_BEEF;
            tmem_wstrb    = write_access ? 4'b1111 : 4'b0000;
            tmem_is_fetch = 1'b0;

            wait (tmem_gnt == 1'b1);

            @(negedge clk);
            tmem_req = 1'b0;

            wait (tmem_rvalid == 1'b1);

            if (tmem_err !== 1'b1) begin
                $display(
                    "ERROR: address 0x%08h should have returned error",
                    addr
                );
                errors = errors + 1;
            end

            if (tmem_rdata !== 32'b0) begin
                $display(
                    "ERROR: error access should return zero, got %08h",
                    tmem_rdata
                );
                errors = errors + 1;
            end

            @(negedge clk);
        end
    endtask

    // ------------------------------------------------------------
    // MAIN TEST
    // ------------------------------------------------------------
    initial begin

        clk   = 1'b0;
        reset = 1'b1;

        tmem_req      = 1'b0;
        tmem_we       = 1'b0;
        tmem_addr     = 32'b0;
        tmem_wdata    = 32'b0;
        tmem_wstrb    = 4'b0;
        tmem_is_fetch = 1'b0;

        errors = 0;

        #50;
        reset = 1'b0;

        $display("");
        $display("======================================");
        $display(" MEMORY TILE TEST");
        $display("======================================");

        // Tile ID = 2, therefore valid base = 0x22000000

        $display("TEST 1: full-word write/read");
        write_word(32'h2200_0000, 32'h1234_5678, 4'b1111);
        read_word (32'h2200_0000, 32'h1234_5678);

        $display("TEST 2: second memory location");
        write_word(32'h2200_0004, 32'hAABB_CCDD, 4'b1111);
        read_word (32'h2200_0004, 32'hAABB_CCDD);

        $display("TEST 3: byte write strobes");
        write_word(32'h2200_0008, 32'h1122_3344, 4'b1111);
        write_word(32'h2200_0008, 32'hAA00_0000, 4'b1000);
        read_word (32'h2200_0008, 32'hAA22_3344);

        $display("TEST 4: zero write strobe is no-op");
        write_word(32'h2200_0008, 32'hFFFF_FFFF, 4'b0000);
        read_word (32'h2200_0008, 32'hAA22_3344);

        $display("TEST 5: misaligned access");
        expect_error(32'h2200_0002, 1'b0);

        $display("TEST 6: out-of-range access");
        expect_error(32'h2200_4000, 1'b0);

        $display("TEST 7: wrong tile ID");
        expect_error(32'h2100_0000, 1'b0);

        $display("TEST 8: non-remote address");
        expect_error(32'h0000_4000, 1'b0);

        $display("");
        $display("======================================");
        $display("RESULT");
        $display("======================================");

        $display("Errors = %0d", errors);

        if (errors == 0)
            $display("PASS: Memory tile tests passed.");
        else
            $display("FAIL: Memory tile test failed.");

        $display("======================================");

        $finish;
    end

endmodule