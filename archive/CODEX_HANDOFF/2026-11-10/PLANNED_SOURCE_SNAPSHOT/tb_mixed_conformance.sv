`timescale 1ns / 1ps

module tb_mixed_conformance;
    integer coverage[8];
    integer half_low=0,half_high=0;
    bit coverage_ok,half_ok;

    logic clk;
    logic reset;

    // CPU interface
    logic        mem_valid;
    logic        mem_instr;
    logic        mem_ready;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    logic [3:0]  mem_wstrb;

    // Local interface
    logic        local_rvalid;
    logic [31:0] local_rdata;
    logic        local_err;

    // TMEM interface
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

    integer i;
    integer delay;
    integer timeout;

    integer transactions;
    integer grants;
    integer responses;
    integer stability_errors;
    integer fetch_errors;
    integer response_errors;
    integer protocol_errors;

    // Captured TMEM request
    logic [31:0] hold_addr;
    logic [31:0] hold_wdata;
    logic [3:0]  hold_wstrb;
    logic        hold_we;
    logic        hold_fetch;

    // Expected CPU transaction
    logic [31:0] expected_addr;
    logic [31:0] expected_wdata;
    logic [3:0]  expected_wstrb;
    logic        expected_we;
    logic        expected_fetch;

    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------

    picorv32_adapter dut (
        .clk_i           (clk),
        .reset_i         (reset),

        .mem_valid_i     (mem_valid),
        .mem_instr_i     (mem_instr),
        .mem_ready_o     (mem_ready),
        .mem_addr_i      (mem_addr),
        .mem_wdata_i     (mem_wdata),
        .mem_rdata_o     (mem_rdata),
        .mem_wstrb_i     (mem_wstrb),

        .local_rvalid_i  (local_rvalid),
        .local_rdata_i   (local_rdata),
        .local_err_i     (local_err),

        .tmem_req_o      (tmem_req),
        .tmem_we_o       (tmem_we),
        .tmem_addr_o     (tmem_addr),
        .tmem_wdata_o    (tmem_wdata),
        .tmem_wstrb_o    (tmem_wstrb),
        .tmem_is_fetch_o (tmem_is_fetch),

        .tmem_gnt_i      (tmem_gnt),
        .tmem_rvalid_i   (tmem_rvalid),
        .tmem_rdata_i    (tmem_rdata),
        .tmem_err_i      (tmem_err),
        .tmem_err_code_i (4'd3),   // Lane 1 (A3): fixed kind in this bench
        .bus_fault_o     (),
        .fault_addr_o    (),
        .fault_code_o    ()
    );

    // ------------------------------------------------------------
    // Test
    // ------------------------------------------------------------

    initial begin

        clk = 0;
        reset = 1;

        mem_valid = 0;
        mem_instr = 0;
        mem_addr  = 0;
        mem_wdata = 0;
        mem_wstrb = 0;

        local_rvalid = 0;
        local_rdata  = 0;
        local_err    = 0;

        tmem_gnt    = 0;
        tmem_rvalid = 0;
        tmem_rdata  = 0;
        tmem_err    = 0;

        transactions     = 0;
        grants           = 0;
        responses        = 0;
        stability_errors = 0;
        fetch_errors     = 0;
        response_errors  = 0;
        protocol_errors  = 0;

        $display("");
        $display("==============================================");
        $display(" TMEM INTERFACE CONFORMANCE TEST");
        $display("==============================================");

        repeat (5) @(posedge clk);
        reset = 0;

        // ========================================================
        // 1000 transactions
        // ========================================================

        for(int c=0;c<8;c++)coverage[c]=0;
        for (i = 0; i < 1000; i = i + 1) begin

            // ----------------------------------------------------
            // Start from a clean idle boundary.
            // ----------------------------------------------------

            @(negedge clk);

            if (tmem_req)
                protocol_errors = protocol_errors + 1;

            if (mem_ready)
                protocol_errors = protocol_errors + 1;

            // ----------------------------------------------------
            // Drive CPU transaction.
            // ----------------------------------------------------

            mem_valid = 1'b1;

            mem_instr=0;mem_addr=32'h20001000+i*4;mem_wdata=32'hA0000000+i;mem_wstrb=0;
            case(i%8)
              0:begin mem_instr=1;mem_addr=32'h20000000+i*4;end
              1:begin end
              2:mem_wstrb=4'hf;
              3:mem_wstrb=4'h1;
              4:begin mem_wstrb=4'h2;mem_addr=mem_addr+1;end
              5:begin mem_wstrb=4'h4;mem_addr=mem_addr+2;end
              6:begin mem_wstrb=4'h8;mem_addr=mem_addr+3;end
              7:if((i/8)%2==0)begin mem_wstrb=4'h3;half_low++;end
                else begin mem_wstrb=4'hc;mem_addr=mem_addr+2;half_high++;end
            endcase
            coverage[i%8]++;

            expected_addr  = mem_addr;
            expected_wdata = mem_wdata;
            expected_wstrb = mem_wstrb;
            expected_we    = |mem_wstrb;
            expected_fetch = mem_instr;

            // ----------------------------------------------------
            // Wait one clock edge for adapter to capture CPU request.
            // ----------------------------------------------------

            @(negedge clk);

            // ----------------------------------------------------
            // Wait for TMEM request.
            // Sample only on negedge clock edges.
            // ----------------------------------------------------

            timeout = 0;

            while (!tmem_req && timeout < 100) begin
                @(negedge clk);
                timeout = timeout + 1;
            end

            if (!tmem_req) begin
                $display("ERROR: TMEM request timeout at transaction %0d", i);
                protocol_errors = protocol_errors + 1;
                $finish;
            end

            // ----------------------------------------------------
            // Capture TMEM request.
            // ----------------------------------------------------

            hold_addr  = tmem_addr;
            hold_wdata = tmem_wdata;
            hold_wstrb = tmem_wstrb;
            hold_we    = tmem_we;
            hold_fetch = tmem_is_fetch;

            if (i < 3) begin
                $display("");
                $display("DEBUG %0d", i);
                $display("EXPECTED: addr=%h wdata=%h wstrb=%b we=%b fetch=%b",
                    expected_addr, expected_wdata, expected_wstrb,
                    expected_we, expected_fetch);
                $display("TMEM    : addr=%h wdata=%h wstrb=%b we=%b fetch=%b",
                    hold_addr, hold_wdata, hold_wstrb,
                    hold_we, hold_fetch);
            end

            // ----------------------------------------------------
            // Check initial request.
            // ----------------------------------------------------

            if (hold_addr !== expected_addr)
                stability_errors = stability_errors + 1;

            if (hold_wdata !== expected_wdata)
                stability_errors = stability_errors + 1;

            if (hold_wstrb !== expected_wstrb)
                stability_errors = stability_errors + 1;

            if (hold_we !== expected_we)
                stability_errors = stability_errors + 1;

            if (hold_fetch !== expected_fetch)
                fetch_errors = fetch_errors + 1;

            // ----------------------------------------------------
            // Random grant latency: 1-100 cycles.
            // ----------------------------------------------------

            delay = $urandom_range(1, 100);

            repeat (delay) begin

                @(negedge clk);

                if (!tmem_req) begin

                    protocol_errors = protocol_errors + 1;

                end
                else begin

                    if (tmem_addr !== hold_addr)
                        stability_errors = stability_errors + 1;

                    if (tmem_wdata !== hold_wdata)
                        stability_errors = stability_errors + 1;

                    if (tmem_wstrb !== hold_wstrb)
                        stability_errors = stability_errors + 1;

                    if (tmem_we !== hold_we)
                        stability_errors = stability_errors + 1;

                    if (tmem_is_fetch !== hold_fetch)
                        fetch_errors = fetch_errors + 1;

                end

            end

            // ----------------------------------------------------
            // Grant.
            // ----------------------------------------------------

            @(negedge clk);
            tmem_gnt = 1'b1;

            @(posedge clk);

            grants = grants + 1;

            @(negedge clk);
            tmem_gnt = 1'b0;

            // ----------------------------------------------------
            // Request must disappear after grant.
            // ----------------------------------------------------

            @(negedge clk);

            if (tmem_req)
                protocol_errors = protocol_errors + 1;

            // ----------------------------------------------------
            // Random response latency: 1-100 cycles.
            // ----------------------------------------------------

            delay = $urandom_range(1, 100);

            repeat (delay)
                @(negedge clk);

            // ----------------------------------------------------
            // Response.
            // ----------------------------------------------------

            @(negedge clk);

            tmem_rdata  = 32'h1234_0000 + i;
            tmem_err    = 1'b0;
            tmem_rvalid = 1'b1;

            @(posedge clk);

            // Complete the CPU valid/ready handshake before the next
            // rising edge, when the adapter is back in IDLE.  Otherwise
            // IDLE would recapture this already-completed transaction.
            mem_valid = 1'b0;

            @(negedge clk);
            tmem_rvalid = 1'b0;

            responses = responses + 1;

            // ----------------------------------------------------
            // Wait for CPU completion.
            // ----------------------------------------------------

            timeout = 0;

            while (!mem_ready && timeout < 20) begin
                @(negedge clk);
                timeout = timeout + 1;
            end

            if (!mem_ready) begin
                $display("ERROR: CPU completion timeout at transaction %0d", i);
                protocol_errors = protocol_errors + 1;
                $finish;
            end

            // ----------------------------------------------------
            // Check response data.
            // ----------------------------------------------------

            if (mem_rdata !== (32'h1234_0000 + i))
                response_errors = response_errors + 1;

            // ----------------------------------------------------
            // mem_ready must be one cycle only.
            // ----------------------------------------------------

            @(negedge clk);

            if (mem_ready)
                protocol_errors = protocol_errors + 1;

            // ----------------------------------------------------
            // Release CPU transaction.
            // ----------------------------------------------------

            mem_valid = 1'b0;

            // Explicit idle boundary.
            @(negedge clk);

            if (tmem_req)
                protocol_errors = protocol_errors + 1;

            transactions = transactions + 1;

            if (((i + 1) % 100) == 0)
                $display("Completed %0d / 1000 transactions", i + 1);

        end

        // ========================================================
        // Results
        // ========================================================

        $display("");
        $display("==============================================");
        $display(" CONFORMANCE RESULTS");
        $display("==============================================");

        coverage_ok=1;for(int c=0;c<8;c++)begin
          $display("OP_COVERAGE class=%0d count=%0d",c,coverage[c]);if(coverage[c]!=125)coverage_ok=0;
        end
        half_ok=half_low==63 && half_high==62;
        $display("HALF_COVERAGE low=%0d high=%0d",half_low,half_high);
        $display("CONFIG: TOP=tb_mixed_conformance CHECKS=9");
        $display("Transactions completed = %0d", transactions);
        $display("CHECKS : 9");
        $display("ERRORS : %0d",stability_errors+fetch_errors+response_errors+protocol_errors+(!coverage_ok)+(!half_ok));
        $display("TMEM grants            = %0d", grants);
        $display("TMEM responses         = %0d", responses);
        $display("Stability errors       = %0d", stability_errors);
        $display("Fetch flag errors      = %0d", fetch_errors);
        $display("Response errors        = %0d", response_errors);
        $display("Protocol errors        = %0d", protocol_errors);

        $display("");

        if ((transactions == 1000) &&
            (grants == 1000) &&
            (responses == 1000) &&
            (stability_errors == 0) &&
            (fetch_errors == 0) &&
            (response_errors == 0) &&
            (protocol_errors == 0) && coverage_ok && half_ok) begin

            $display("PASS: 1000 TMEM conformance transactions passed.");
            $display("RESULT : PASS");

        end
        else begin

            $display("FAIL: TMEM conformance test failed.");
            $display("RESULT : FAIL");

        end

        $display("==============================================");
        $display("");

        $finish;

    end

endmodule