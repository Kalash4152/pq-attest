`timescale 1ns / 1ps

module tb_memory_full;

    localparam integer MEM_WORDS = 4096;

    logic clk;
    logic reset;

    logic        req;
    logic        we;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        is_fetch;

    logic        gnt;
    logic        rvalid;
    logic [31:0] rdata;
    logic        err;

    integer errors;
    integer i;

    // ============================================================
    // DUT
    // ============================================================

    memory_tile #(
        .TILE_ID   (4'h2),
        .MEM_WORDS (MEM_WORDS),
        .INIT_FILE ("")
    ) dut (
        .clk_i           (clk),
        .reset_i         (reset),

        .tmem_req_i      (req),
        .tmem_we_i       (we),
        .tmem_addr_i     (addr),
        .tmem_wdata_i    (wdata),
        .tmem_wstrb_i    (wstrb),
        .tmem_is_fetch_i (is_fetch),

        .tmem_gnt_o      (gnt),
        .tmem_rvalid_o   (rvalid),
        .tmem_rdata_o    (rdata),
        .tmem_err_o      (err)
    );

    always #5 clk = ~clk;


    // ============================================================
    // TRANSACTION TASK
    // ============================================================

    task automatic do_transaction;

        input        transaction_we;
        input [31:0] transaction_addr;
        input [31:0] transaction_wdata;
        input [3:0]  transaction_wstrb;
        input        expected_err;
        input [31:0] expected_rdata;
        input        check_rdata;

        integer timeout;
        reg got_gnt;
        reg got_response;

        begin

            got_gnt      = 1'b0;
            got_response = 1'b0;

            @(negedge clk);

            req      = 1'b1;
            we       = transaction_we;
            addr     = transaction_addr;
            wdata    = transaction_wdata;
            wstrb    = transaction_wstrb;
            is_fetch = 1'b0;

            timeout = 0;

            while (!got_gnt && timeout < 20) begin

                @(posedge clk);

                if (gnt)
                    got_gnt = 1'b1;

                timeout = timeout + 1;

            end

            if (!got_gnt) begin

                $display(
                    "ERROR: no grant for addr=%08h",
                    transaction_addr
                );

                errors = errors + 1;

            end

            @(negedge clk);

            req = 1'b0;

            timeout = 0;

            while (!got_response && timeout < 20) begin

                @(posedge clk);

                if (rvalid)
                    got_response = 1'b1;

                timeout = timeout + 1;

            end

            if (!got_response) begin

                $display(
                    "ERROR: no response for addr=%08h",
                    transaction_addr
                );

                errors = errors + 1;

            end
            else begin

                // Error flag is always meaningful.
                if (err !== expected_err) begin

                    $display(
                        "ERROR: wrong error flag at %08h: expected=%b got=%b",
                        transaction_addr,
                        expected_err,
                        err
                    );

                    errors = errors + 1;

                end

                // Only check rdata when explicitly requested.
                if (check_rdata) begin

                    if (expected_err) begin

                        if (rdata !== 32'b0) begin

                            $display(
                                "ERROR: error response data not zero at %08h: got=%08h",
                                transaction_addr,
                                rdata
                            );

                            errors = errors + 1;

                        end

                    end
                    else begin

                        if (rdata !== expected_rdata) begin

                            $display(
                                "ERROR: wrong data at %08h: expected=%08h got=%08h",
                                transaction_addr,
                                expected_rdata,
                                rdata
                            );

                            errors = errors + 1;

                        end

                    end

                end

            end

            @(negedge clk);

            req      = 1'b0;
            we       = 1'b0;
            addr     = 32'b0;
            wdata    = 32'b0;
            wstrb    = 4'b0;
            is_fetch = 1'b0;

        end

    endtask


    // ============================================================
    // TEST
    // ============================================================

    initial begin

        clk   = 1'b0;
        reset = 1'b1;

        req      = 1'b0;
        we       = 1'b0;
        addr     = 32'b0;
        wdata    = 32'b0;
        wstrb    = 4'b0;
        is_fetch = 1'b0;

        errors = 0;


        // ========================================================
        // RESET
        // ========================================================

        repeat (4)
            @(posedge clk);

        reset = 1'b0;

        repeat (2)
            @(posedge clk);


        $display("");
        $display("==============================================");
        $display(" FULL MEMORY VERIFICATION TEST");
        $display("==============================================");


        // ========================================================
        // TEST 1
        // Full-word write/read
        // ========================================================

        $display("TEST 1: full-word write/read");

        do_transaction(
            1'b1,
            32'h22000000,
            32'h12345678,
            4'b1111,
            1'b0,
            32'h00000000,
            1'b0
        );

        do_transaction(
            1'b0,
            32'h22000000,
            32'h00000000,
            4'b0000,
            1'b0,
            32'h12345678,
            1'b1
        );


        // ========================================================
        // TEST 2
        // Read-after-write / address isolation
        // ========================================================

        $display("TEST 2: read-after-write / address isolation");

        do_transaction(
            1'b1,
            32'h22000004,
            32'hA5A5A5A5,
            4'b1111,
            1'b0,
            32'h00000000,
            1'b0
        );

        do_transaction(
            1'b1,
            32'h22000008,
            32'h5A5A5A5A,
            4'b1111,
            1'b0,
            32'h00000000,
            1'b0
        );

        do_transaction(
            1'b0,
            32'h22000004,
            32'h00000000,
            4'b0000,
            1'b0,
            32'hA5A5A5A5,
            1'b1
        );

        do_transaction(
            1'b0,
            32'h22000008,
            32'h00000000,
            4'b0000,
            1'b0,
            32'h5A5A5A5A,
            1'b1
        );


        // ========================================================
        // TEST 3
        // All 16 WSTRB combinations
        // ========================================================

        $display("TEST 3: all 16 WSTRB combinations");

        for (i = 0; i < 16; i = i + 1) begin

            // Reset the location before each WSTRB test.
            do_transaction(
                1'b1,
                32'h22000100,
                32'h00000000,
                4'b1111,
                1'b0,
                32'h00000000,
                1'b0
            );

            // Apply the WSTRB being tested.
            do_transaction(
                1'b1,
                32'h22000100,
                32'hA1B2C3D4,
                i[3:0],
                1'b0,
                32'h00000000,
                1'b0
            );

            // Read back and calculate expected byte-lane result.
            case (i[3:0])

                4'b0000:
                    do_transaction(
                        1'b0,
                        32'h22000100,
                        32'h00000000,
                        4'b0000,
                        1'b0,
                        32'h00000000,
                        1'b1
                    );

                4'b0001:
                    do_transaction(
                        1'b0,
                        32'h22000100,
                        32'h00000000,
                        4'b0000,
                        1'b0,
                        32'h000000D4,
                        1'b1
                    );

                4'b0010:
                    do_transaction(
                        1'b0,
                        32'h22000100,
                        32'h00000000,
                        4'b0000,
                        1'b0,
                        32'h0000C300,
                        1'b1
                    );

                4'b0011:
                    do_transaction(
                        1'b0,
                        32'h22000100,
                        32'h00000000,
                        4'b0000,
                        1'b0,
                        32'h0000C3D4,
                        1'b1
                    );

                4'b0100:
                    do_transaction(
                        1'b0,
                        32'h22000100,
                        32'h00000000,
                        4'b0000,
                        1'b0,
                        32'h00B20000,
                        1'b1
                    );

                4'b0101:
                    do_transaction(
                        1'b0,
                        32'h22000100,
                        32'h00000000,
                        4'b0000,
                        1'b0,
                        32'h00B200D4,
                        1'b1
                    );

                4'b0110:
                    do_transaction(
                        1'b0,
                        32'h22000100,
                        32'h00000000,
                        4'b0000,
                        1'b0,
                        32'h00B2C300,
                        1'b1
                    );

                4'b0111:
                    do_transaction(
                        1'b0,
                        32'h22000100,
                        32'h00000000,
                        4'b0000,
                        1'b0,
                        32'h00B2C3D4,
                        1'b1
                    );

                4'b1000:
                    do_transaction(
                        1'b0,
                        32'h22000100,
                        32'h00000000,
                        4'b0000,
                        1'b0,
                        32'hA1000000,
                        1'b1
                    );

                4'b1001:
                    do_transaction(
                        1'b0,
                        32'h22000100,
                        32'h00000000,
                        4'b0000,
                        1'b0,
                        32'hA10000D4,
                        1'b1
                    );

                4'b1010:
                    do_transaction(
                        1'b0,
                        32'h22000100,
                        32'h00000000,
                        4'b0000,
                        1'b0,
                        32'hA100C300,
                        1'b1
                    );

                4'b1011:
                    do_transaction(
                        1'b0,
                        32'h22000100,
                        32'h00000000,
                        4'b0000,
                        1'b0,
                        32'hA100C3D4,
                        1'b1
                    );

                4'b1100:
                    do_transaction(
                        1'b0,
                        32'h22000100,
                        32'h00000000,
                        4'b0000,
                        1'b0,
                        32'hA1B20000,
                        1'b1
                    );

                4'b1101:
                    do_transaction(
                        1'b0,
                        32'h22000100,
                        32'h00000000,
                        4'b0000,
                        1'b0,
                        32'hA1B200D4,
                        1'b1
                    );

                4'b1110:
                    do_transaction(
                        1'b0,
                        32'h22000100,
                        32'h00000000,
                        4'b0000,
                        1'b0,
                        32'hA1B2C300,
                        1'b1
                    );

                4'b1111:
                    do_transaction(
                        1'b0,
                        32'h22000100,
                        32'h00000000,
                        4'b0000,
                        1'b0,
                        32'hA1B2C3D4,
                        1'b1
                    );

            endcase

        end


        // ========================================================
        // TEST 4
        // Zero WSTRB must be a no-op
        // ========================================================

        $display("TEST 4: zero WSTRB no-op");

        do_transaction(
            1'b1,
            32'h22000200,
            32'hDEADBEEF,
            4'b1111,
            1'b0,
            32'h00000000,
            1'b0
        );

        do_transaction(
            1'b1,
            32'h22000200,
            32'h11111111,
            4'b0000,
            1'b0,
            32'h00000000,
            1'b0
        );

        do_transaction(
            1'b0,
            32'h22000200,
            32'h00000000,
            4'b0000,
            1'b0,
            32'hDEADBEEF,
            1'b1
        );


        // ========================================================
        // TEST 5
        // Lower boundary
        // ========================================================

        $display("TEST 5: lower boundary");

        do_transaction(
            1'b1,
            32'h22000000,
            32'hCAFEBABE,
            4'b1111,
            1'b0,
            32'h00000000,
            1'b0
        );

        do_transaction(
            1'b0,
            32'h22000000,
            32'h00000000,
            4'b0000,
            1'b0,
            32'hCAFEBABE,
            1'b1
        );


        // ========================================================
        // TEST 6
        // Upper boundary
        // ========================================================

        $display("TEST 6: upper boundary");

        do_transaction(
            1'b1,
            32'h22003FFC,
            32'hFACE1234,
            4'b1111,
            1'b0,
            32'h00000000,
            1'b0
        );

        do_transaction(
            1'b0,
            32'h22003FFC,
            32'h00000000,
            4'b0000,
            1'b0,
            32'hFACE1234,
            1'b1
        );


        // ========================================================
        // TEST 7
        // Out-of-range
        // ========================================================

        $display("TEST 7: out-of-range access");

        do_transaction(
            1'b0,
            32'h22004000,
            32'h00000000,
            4'b0000,
            1'b1,
            32'h00000000,
            1'b1
        );

        do_transaction(
            1'b1,
            32'h22004000,
            32'hAAAAAAAA,
            4'b1111,
            1'b1,
            32'h00000000,
            1'b1
        );


        // ========================================================
        // TEST 8
        // Misaligned
        // ========================================================

        $display("TEST 8: misaligned access");

        do_transaction(
            1'b0,
            32'h22000002,
            32'h00000000,
            4'b0000,
            1'b1,
            32'h00000000,
            1'b1
        );

        do_transaction(
            1'b1,
            32'h22000001,
            32'hAAAAAAAA,
            4'b1111,
            1'b1,
            32'h00000000,
            1'b1
        );


        // ========================================================
        // TEST 9
        // Wrong tile ID
        // ========================================================

        $display("TEST 9: wrong tile ID");

        do_transaction(
            1'b0,
            32'h21000000,
            32'h00000000,
            4'b0000,
            1'b1,
            32'h00000000,
            1'b1
        );

        do_transaction(
            1'b1,
            32'h21000000,
            32'hAAAAAAAA,
            4'b1111,
            1'b1,
            32'h00000000,
            1'b1
        );


        // ========================================================
        // TEST 10
        // Non-remote address
        // ========================================================

        $display("TEST 10: non-remote address");

        do_transaction(
            1'b0,
            32'h10000000,
            32'h00000000,
            4'b0000,
            1'b1,
            32'h00000000,
            1'b1
        );

        do_transaction(
            1'b1,
            32'h00000000,
            32'hAAAAAAAA,
            4'b1111,
            1'b1,
            32'h00000000,
            1'b1
        );


        // ========================================================
        // RESULT
        // ========================================================

        $display("");
        $display("==============================================");
        $display(" MEMORY VERIFICATION RESULT");
        $display("==============================================");
        $display("Errors = %0d", errors);
        $display("----------------------------------------------");

        if (errors == 0)
            $display("PASS: Full memory verification passed.");
        else
            $display(
                "FAIL: Full memory verification found %0d errors.",
                errors
            );

        $display("==============================================");

        $finish;

    end

endmodule