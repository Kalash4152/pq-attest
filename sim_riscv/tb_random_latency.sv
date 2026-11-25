`timescale 1ns / 1ps

module tb_random_latency;
    int unsigned seed_sink;   // Lane 1: sink for the per-seed $urandom(seed) call

    logic clk;
    logic reset;

    // ============================================================
    // CPU-side adapter interface
    // ============================================================

    logic        mem_valid;
    logic        mem_instr;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [3:0]  mem_wstrb;

    logic        mem_ready;
    logic [31:0] mem_rdata;

    // ============================================================
    // Local interface
    // ============================================================

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
    // DUT
    // ============================================================

    picorv32_adapter dut (
        .clk_i   (clk),
        .reset_i (reset),

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

        .local_gnt_i    (local_gnt),
        .local_rvalid_i (local_rvalid),
        .local_rdata_i  (local_rdata),
        .local_err_i    (local_err),

        .tmem_req_o      (tmem_req),
        .tmem_we_o       (tmem_we),
        .tmem_addr_o     (tmem_addr),
        .tmem_wdata_o    (tmem_wdata),
        .tmem_wstrb_o    (tmem_wstrb),
        .tmem_is_fetch_o (tmem_is_fetch),

        .tmem_gnt_i    (tmem_gnt),
        .tmem_rvalid_i (tmem_rvalid),
        .tmem_rdata_i  (tmem_rdata),
        .tmem_err_i    (tmem_err),
        .tmem_err_code_i (4'd3),   // Lane 1 (A3): fixed kind in this bench
        .bus_fault_o     (),
        .fault_addr_o    (),
        .fault_code_o    ()
    );

    // ============================================================
    // CLOCK
    // ============================================================

    always #5 clk = ~clk;

    // ============================================================
    // Random latency state
    // ============================================================

    integer grant_delay;
    integer response_delay;

    integer seed;
    integer first_seed, end_seed, requested_seed, completed_seeds=0, prior_errors, rng_seed;
    bit single_seed;
    integer transaction;
    integer errors;

    logic grant_pending;
    logic response_pending;

    integer grant_count;
    integer response_count;

    logic [31:0] expected_rdata;

    // ============================================================
    // Random TMEM responder
    //
    // Grant and response latency are independently randomized
    // from 1 to 100 cycles.
    // ============================================================

    always @(posedge clk) begin

        if (reset) begin

            tmem_gnt    <= 1'b0;
            tmem_rvalid <= 1'b0;
            tmem_rdata  <= 32'b0;
            tmem_err    <= 1'b0;

            grant_pending    <= 1'b0;
            response_pending <= 1'b0;

            grant_count    <= 0;
            response_count <= 0;

        end
        else begin

            tmem_gnt    <= 1'b0;
            tmem_rvalid <= 1'b0;
            tmem_err    <= 1'b0;

            // ----------------------------------------------------
            // Start a new grant delay when a request appears.
            // ----------------------------------------------------

            if (tmem_req && !grant_pending && !response_pending) begin

                grant_pending <= 1'b1;

                grant_delay = ($urandom % 100) + 1;
                grant_count <= grant_delay;

            end

            // ----------------------------------------------------
            // Count grant delay.
            // ----------------------------------------------------

            if (grant_pending) begin

                if (grant_count <= 1) begin

                    tmem_gnt <= 1'b1;

                    grant_pending <= 1'b0;

                    response_pending <= 1'b1;

                    response_delay = ($urandom % 100) + 1;
                    response_count <= response_delay;

                end
                else begin
                    grant_count <= grant_count - 1;
                end

            end

            // ----------------------------------------------------
            // Count response delay.
            // ----------------------------------------------------

            if (response_pending) begin

                if (response_count <= 1) begin

                    tmem_rvalid <= 1'b1;
                    tmem_rdata  <= expected_rdata;
                    tmem_err    <= 1'b0;

                    response_pending <= 1'b0;

                end
                else begin
                    response_count <= response_count - 1;
                end

            end

        end

    end

    // ============================================================
    // One transaction
    // ============================================================

    task automatic run_transaction(
        input integer tx_number
    );

        logic [31:0] test_addr;
        logic [31:0] test_data;
        logic [3:0]  test_wstrb;
        logic        test_instr;

        integer timeout_count;

        begin

            // ----------------------------------------------------
            // Generate a remote transaction.
            // ----------------------------------------------------

            test_addr  = 32'h2000_0000 + ((tx_number % 256) * 4);
            test_data  = 32'hA500_0000 ^ tx_number;
            test_wstrb = 4'b0000;
            test_instr = 1'b1;

            expected_rdata = test_data;

            @(negedge clk);

            mem_valid = 1'b1;
            mem_instr = test_instr;
            mem_addr  = test_addr;
            mem_wdata = test_data;
            mem_wstrb = test_wstrb;

            // ----------------------------------------------------
            // Wait for CPU-side completion.
            // ----------------------------------------------------

            timeout_count = 0;

            while (!mem_ready) begin

                @(posedge clk);

                timeout_count = timeout_count + 1;

                if (timeout_count > 1000) begin
                    $display(
                        "ERROR: transaction %0d timed out",
                        tx_number
                    );
                    errors = errors + 1;
                    disable run_transaction;
                end

            end

            // ----------------------------------------------------
            // Check returned data.
            // ----------------------------------------------------

            if (mem_rdata !== expected_rdata) begin

                $display(
                    "ERROR: transaction %0d expected %08h got %08h",
                    tx_number,
                    expected_rdata,
                    mem_rdata
                );

                errors = errors + 1;

            end

            // ----------------------------------------------------
            // CPU must release valid after completion.
            // ----------------------------------------------------

            @(negedge clk);

            mem_valid = 1'b0;
            mem_instr = 1'b0;
            mem_addr  = 32'b0;
            mem_wdata = 32'b0;
            mem_wstrb = 4'b0;

            // Give adapter one clean idle cycle.
            @(negedge clk);

        end

    endtask

    // ============================================================
    // MAIN TEST
    // ============================================================

    initial begin

        clk   = 1'b0;
        reset = 1'b1;

        mem_valid = 1'b0;
        mem_instr = 1'b0;
        mem_addr  = 32'b0;
        mem_wdata = 32'b0;
        mem_wstrb = 4'b0;

        local_gnt    = 1'b0;
        local_rvalid = 1'b0;
        local_rdata  = 32'b0;
        local_err    = 1'b0;

        errors = 0;

        $display("");
        $display("==============================================");
        $display(" RANDOM LATENCY ACCEPTANCE TEST");
        $display("==============================================");
        $display("Grant latency    : 1-100 cycles");
        $display("Response latency : 1-100 cycles");
        $display("Seeds            : 1000");
        $display("==============================================");

        // --------------------------------------------------------
        // Reset
        // --------------------------------------------------------

        repeat (5)
            @(posedge clk);

        reset = 1'b0;

        // --------------------------------------------------------
        // 1000 independent seeds
        // --------------------------------------------------------

        single_seed=$value$plusargs("seed=%d",requested_seed);
        first_seed=single_seed?requested_seed:0;end_seed=single_seed?requested_seed+1:1000;
        $display("CONFIG: TOP=tb_random_latency CHECKS=2");
        for (seed = first_seed; seed < end_seed; seed = seed + 1) begin
            prior_errors=errors;

            // Deterministic seed for reproducibility.
            rng_seed=seed; seed_sink = $urandom(rng_seed);   // Lane 1 2026-11-06: XSim does not accept $urandom(seed) as a statement; same per-seed seeding

            // Each seed gets one randomized transaction.
            run_transaction(seed);
            completed_seeds++;
            $display("SEED_RESULT seed=%0d completed=1 errors=%0d",seed,errors-prior_errors);
            $display("SEED_LATENCY seed=%0d grant=%0d response=%0d",seed,grant_delay,response_delay);

            if (((seed + 1) % 100) == 0) begin
                $display(
                    "Completed %0d / 1000 seeds",
                    seed + 1
                );
            end

        end

        // --------------------------------------------------------
        // Result
        // --------------------------------------------------------

        $display("");
        $display("==============================================");
        $display("RESULT");
        $display("==============================================");

        $display(
            "Seeds completed = %0d", completed_seeds
        );

        $display(
            "Errors           = %0d",
            errors
        );

        if (errors == 0 && completed_seeds==end_seed-first_seed) begin

            $display("");
            $display(
                "PASS: selected randomized seeds passed."
            );
            $display(
                "PASS: Adapter survived independent 1-100 cycle latency."
            );

        end
        else begin

            $display("");
            $display(
                "FAIL: Random latency acceptance test failed."
            );

        end

        $display("==============================================");

        $display("CHECKS : 2");
        $display("RESULT : %s",errors==0 && completed_seeds==end_seed-first_seed ? "PASS":"FAIL");
        #20;
        $finish;

    end

endmodule
