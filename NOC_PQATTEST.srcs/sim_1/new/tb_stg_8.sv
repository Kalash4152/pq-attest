`timescale 1ns/1ps

module pq_attestation_controller_tb;

    //======================================================================
    // CLOCK
    //======================================================================

    logic clk;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end


    //======================================================================
    // DUT INPUTS
    //
    // These widths are taken directly from the Stage 5/6/7 RTL.
    //======================================================================

    logic         rst_n;
    logic         start;

    logic [55:0]  tile_id;
    logic [79:0]  epoch;
    logic [127:0] nonce;

    logic [255:0] root_secret;

    logic [111:0] context_in;
    logic [3:0]   context_len;

    logic [511:0] config_data;
    logic [6:0]   config_len;

    logic [511:0] imem;
    logic [6:0]   imem_len;


    //======================================================================
    // DUT OUTPUTS
    //======================================================================

    logic [775:0] response;

    logic         busy;
    logic         done;
    logic         err;

    logic [2:0]   status;
    logic [3:0]   error_code;


    //======================================================================
    // RESPONSE SNAPSHOTS
    //
    // IMPORTANT:
    // These are declared at module scope.
    // Do NOT declare them halfway through an initial block.
    //======================================================================

    logic [775:0] response_A;
    logic [775:0] response_B;


    //======================================================================
    // DUT
    //
    // Exact interface of the Stage-8 controller previously defined.
    //======================================================================

    pq_attestation_controller dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (start),

        .tile_id      (tile_id),
        .epoch        (epoch),
        .nonce        (nonce),

        .root_secret  (root_secret),

        .context_in   (context_in),
        .context_len  (context_len),

        .config_data  (config_data),
        .config_len   (config_len),

        .imem         (imem),
        .imem_len     (imem_len),

        .response     (response),

        .busy         (busy),
        .done         (done),
        .err          (err),

        .status       (status),
        .error_code   (error_code)
    );


    //======================================================================
    // TEST SCOREBOARD
    //======================================================================

    integer tests;
    integer errors;


    task automatic check;

        input logic   condition;
        input string  message;

        begin

            tests = tests + 1;

            if (condition === 1'b1) begin

                $display("[PASS] %s", message);

            end
            else begin

                errors = errors + 1;

                $display("[FAIL] %s", message);

            end

        end

    endtask


    //======================================================================
    // TEST VECTORS
    //======================================================================

    // ---------------------------------------------------------------------
    // TILE_01
    //
    // Byte 0 = T
    // Byte 1 = I
    // Byte 2 = L
    // Byte 3 = E
    // Byte 4 = _
    // Byte 5 = 0
    // Byte 6 = 1
    //
    // Project convention:
    // byte i -> [i*8 +: 8]
    // ---------------------------------------------------------------------

    localparam logic [55:0] TILE_01 =
        56'h31305f454c4954;


    // TILE_02

    localparam logic [55:0] TILE_02 =
        56'h32305f454c4954;


    // ---------------------------------------------------------------------
    // EPOCH_0001
    // ---------------------------------------------------------------------

    localparam logic [79:0] EPOCH_0001 =
        80'h313030305f48434f5045;


    // EPOCH_0002

    localparam logic [79:0] EPOCH_0002 =
        80'h323030305f48434f5045;


    // ---------------------------------------------------------------------
    // NONCE A
    // ---------------------------------------------------------------------

    localparam logic [127:0] NONCE_A =
        128'h0f0e0d0c0b0a09080706050403020100;


    // NONCE B

    localparam logic [127:0] NONCE_B =
        128'h1f1e1d1c1b1a19181716151413121110;


    // ---------------------------------------------------------------------
    // ROOT SECRET
    //
    // One continuous 256-bit literal.
    // ---------------------------------------------------------------------

    localparam logic [255:0] ROOT_SECRET_A =
        256'h1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100;


    // ---------------------------------------------------------------------
    // CONTEXT
    //
    // "PQ-ATTEST-AUTH"
    //
    // 14 bytes.
    // ---------------------------------------------------------------------

    localparam logic [111:0] CONTEXT_AUTH =
        112'h485455412d5453455454412d5150;


    // ---------------------------------------------------------------------
    // CONFIGURATION
    //
    // 512-bit container.
    //
    // The actual Stage-6 measurement length is controlled separately
    // through config_len.
    //
    // This vector is all zero.
    // ---------------------------------------------------------------------

    localparam logic [511:0] CONFIG_A =
        512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;


    // ---------------------------------------------------------------------
    // IMEM
    //
    // 512-bit container.
    //
    // Low 16 bytes:
    //
    // byte 0  = 00
    // byte 1  = 01
    // byte 2  = 02
    // ...
    // byte 15 = 0f
    //
    // Remaining bytes = 00.
    //
    // This follows:
    //
    //     byte i -> [i*8 +: 8]
    // ---------------------------------------------------------------------

    localparam logic [511:0] IMEM_A =
        512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f0e0d0c0b0a09080706050403020100;


    //======================================================================
    // RESET
    //
    // Stage-8 controller uses synchronous active-low reset.
    // Therefore rst_n is held low across clock edges.
    //======================================================================

    task automatic reset_dut;

        begin

            rst_n = 1'b0;

            start = 1'b0;

            tile_id = '0;
            epoch = '0;
            nonce = '0;

            root_secret = '0;

            context_in = '0;
            context_len = '0;

            config_data = '0;
            config_len = '0;

            imem = '0;
            imem_len = '0;

            repeat (3) begin
                @(posedge clk);
                #1;
            end

            rst_n = 1'b1;

            @(posedge clk);
            #1;

        end

    endtask


    //======================================================================
    // DRIVE VALID REQUEST A
    //======================================================================

    task automatic drive_request_A;

        begin

            tile_id = TILE_01;
            epoch = EPOCH_0001;
            nonce = NONCE_A;

            root_secret = ROOT_SECRET_A;

            context_in = CONTEXT_AUTH;
            context_len = 4'd14;

            config_data = CONFIG_A;
            config_len = 7'd64;

            imem = IMEM_A;
            imem_len = 7'd64;

        end

    endtask


    //======================================================================
    // START PULSE
    //
    // Inputs are already stable before this pulse.
    //======================================================================

    task automatic pulse_start;

        begin

            @(negedge clk);

            start = 1'b1;

            @(negedge clk);

            start = 1'b0;

        end

    endtask


    //======================================================================
    // WAIT FOR DONE
    //======================================================================

    task automatic wait_for_done;

        integer timeout;

        begin

            timeout = 0;

            while (!done && timeout < 10000) begin

                @(posedge clk);
                #1;

                timeout = timeout + 1;

            end

            check(
                done,
                "Controller completed transaction"
            );

        end

    endtask


    //======================================================================
    // CHECK DONE IS ONE-CYCLE
    //======================================================================

    task automatic check_done_pulse;

        begin

            @(posedge clk);
            #1;

            check(
                !done,
                "DONE is a one-cycle pulse"
            );

        end

    endtask


    //======================================================================
    // MAIN TEST
    //======================================================================

    initial begin

        tests = 0;
        errors = 0;

        // Initial values.
        rst_n = 1'b0;
        start = 1'b0;

        tile_id = '0;
        epoch = '0;
        nonce = '0;

        root_secret = '0;

        context_in = '0;
        context_len = '0;

        config_data = '0;
        config_len = '0;

        imem = '0;
        imem_len = '0;

        response_A = '0;
        response_B = '0;


        //==================================================================
        // TEST 1
        // RESET
        //==================================================================

        $display("");
        $display("============================================================");
        $display("TEST 1: RESET");
        $display("============================================================");

        reset_dut;

        check(
            !busy,
            "BUSY = 0 after reset"
        );

        check(
            !done,
            "DONE = 0 after reset"
        );

        check(
            !err,
            "ERR = 0 after reset"
        );

        check(
            status == 3'b000,
            "STATUS = IDLE after reset"
        );

        check(
            error_code == 4'b0000,
            "ERROR_CODE = NONE after reset"
        );


        //==================================================================
        // TEST 2
        // VALID END-TO-END TRANSACTION
        //==================================================================

        $display("");
        $display("============================================================");
        $display("TEST 2: VALID END-TO-END");
        $display("============================================================");

        drive_request_A;

        pulse_start;

        check(
            busy,
            "BUSY asserted after valid START"
        );

        check(
            status == 3'b001,
            "STATUS = PROCESSING"
        );

        wait_for_done;

        check(
            !err,
            "ERR = 0 for valid transaction"
        );

        check(
            status == 3'b010,
            "STATUS = RESPONSE_READY"
        );


        //==================================================================
        // TEST 3
        // RESPONSE WIDTH
        //==================================================================

        $display("");
        $display("============================================================");
        $display("TEST 3: RESPONSE WIDTH");
        $display("============================================================");

        check(
            $bits(response) == 776,
            "Response width = 776 bits"
        );


        //==================================================================
        // TEST 4
        // RESPONSE TILE ID
        //==================================================================

        $display("");
        $display("============================================================");
        $display("TEST 4: RESPONSE TILE ID");
        $display("============================================================");

        check(
            response[0 +: 56] == TILE_01,
            "Response TILE_ID matches request"
        );


        //==================================================================
        // TEST 5
        // RESPONSE EPOCH
        //==================================================================

        $display("");
        $display("============================================================");
        $display("TEST 5: RESPONSE EPOCH");
        $display("============================================================");

        check(
            response[56 +: 80] == EPOCH_0001,
            "Response EPOCH matches request"
        );


        //==================================================================
        // TEST 6
        // RESPONSE NONCE
        //==================================================================

        $display("");
        $display("============================================================");
        $display("TEST 6: RESPONSE NONCE");
        $display("============================================================");

        check(
            response[136 +: 128] == NONCE_A,
            "Response NONCE matches request"
        );


        //==================================================================
        // TEST 7
        // RESPONSE MEASUREMENT
        //======================================================================

        $display("");
        $display("============================================================");
        $display("TEST 7: RESPONSE MEASUREMENT");
        $display("============================================================");

        check(
            ^response[264 +: 256] !== 1'bx,
            "Response MEASUREMENT contains no X/Z"
        );


        //==================================================================
        // TEST 8
        // RESPONSE TAG
        //======================================================================

        $display("");
        $display("============================================================");
        $display("TEST 8: RESPONSE TAG");
        $display("============================================================");

        check(
            ^response[520 +: 256] !== 1'bx,
            "Response TAG contains no X/Z"
        );


        // Save response A.
        response_A = response;


        //==================================================================
        // TEST 9
        // DONE PULSE
        //==================================================================

        $display("");
        $display("============================================================");
        $display("TEST 9: DONE PULSE");
        $display("============================================================");

        check_done_pulse;


        //==================================================================
        // TEST 10
        // START WHILE BUSY
        //
        // This is important:
        //
        // Request A begins.
        // While it is running, request B is placed on the inputs.
        // A second START is asserted.
        //
        // The controller must continue processing A.
        //==================================================================

        $display("");
        $display("============================================================");
        $display("TEST 10: START WHILE BUSY");
        $display("============================================================");

        reset_dut;

        drive_request_A;

        pulse_start;

        check(
            busy,
            "BUSY asserted for first transaction"
        );


        // Change live inputs to request B.
        tile_id = TILE_02;
        epoch = EPOCH_0002;
        nonce = NONCE_B;


        // Attempt START while busy.
        @(negedge clk);

        start = 1'b1;

        @(negedge clk);

        start = 1'b0;


        wait_for_done;


        check(
            response[0 +: 56] == TILE_01,
            "Busy-time START did not replace TILE_ID"
        );

        check(
            response[56 +: 80] == EPOCH_0001,
            "Busy-time START did not replace EPOCH"
        );

        check(
            response[136 +: 128] == NONCE_A,
            "Busy-time START did not replace NONCE"
        );


        //==================================================================
        // TEST 11
        // DIFFERENT NONCE
        //==================================================================

        $display("");
        $display("============================================================");
        $display("TEST 11: DIFFERENT NONCE");
        $display("============================================================");

        reset_dut;

        drive_request_A;

        pulse_start;

        wait_for_done;

        response_A = response;


        // Same request, different nonce.
        nonce = NONCE_B;

        pulse_start;

        wait_for_done;

        response_B = response;


        check(
            response_B[136 +: 128] == NONCE_B,
            "Modified NONCE appears in response"
        );

        check(
            response_B !== response_A,
            "Changing NONCE changes response"
        );


        //==================================================================
        // TEST 12
        // DIFFERENT TILE ID
        //==================================================================

        $display("");
        $display("============================================================");
        $display("TEST 12: DIFFERENT TILE ID");
        $display("============================================================");

        reset_dut;

        drive_request_A;

        pulse_start;

        wait_for_done;

        response_A = response;


        tile_id = TILE_02;

        pulse_start;

        wait_for_done;

        response_B = response;


        check(
            response_B[0 +: 56] == TILE_02,
            "Modified TILE_ID appears in response"
        );

        check(
            response_B !== response_A,
            "Changing TILE_ID changes response"
        );


        //==================================================================
        // TEST 13
        // INVALID CONTEXT LENGTH
        //
        // Stage 5 allows 0..14 bytes.
        //==================================================================

        $display("");
        $display("============================================================");
        $display("TEST 13: INVALID CONTEXT LENGTH");
        $display("============================================================");

        reset_dut;

        drive_request_A;

        context_len = 4'd15;

        pulse_start;

        // Invalid request is rejected by the controller.
        @(posedge clk);
        #1;

        check(
            err,
            "ERR asserted for invalid context length"
        );

        check(
            done,
            "DONE asserted for rejected request"
        );

        check(
            status == 3'b011,
            "STATUS = INVALID_REQUEST"
        );

        check(
            error_code == 4'b0001,
            "ERROR_CODE = INVALID_CONTEXT_LENGTH"
        );


        //==================================================================
        // TEST 14
        // INVALID CONFIG LENGTH
        //
        // Stage 6 CONFIG maximum = 64 bytes.
        //==================================================================

        $display("");
        $display("============================================================");
        $display("TEST 14: INVALID CONFIG LENGTH");
        $display("============================================================");

        reset_dut;

        drive_request_A;

        config_len = 7'd65;

        pulse_start;

        @(posedge clk);
        #1;

        check(
            err,
            "ERR asserted for invalid CONFIG length"
        );

        check(
            done,
            "DONE asserted for rejected CONFIG request"
        );

        check(
            status == 3'b011,
            "STATUS = INVALID_REQUEST"
        );

        check(
            error_code == 4'b0010,
            "ERROR_CODE = INVALID_MEASUREMENT_LENGTH"
        );


        //==================================================================
        // TEST 15
        // INVALID IMEM LENGTH
        //
        // Stage 6 IMEM maximum = 64 bytes.
        //==================================================================

        $display("");
        $display("============================================================");
        $display("TEST 15: INVALID IMEM LENGTH");
        $display("============================================================");

        reset_dut;

        drive_request_A;

        imem_len = 7'd65;

        pulse_start;

        @(posedge clk);
        #1;

        check(
            err,
            "ERR asserted for invalid IMEM length"
        );

        check(
            done,
            "DONE asserted for rejected IMEM request"
        );

        check(
            status == 3'b011,
            "STATUS = INVALID_REQUEST"
        );

        check(
            error_code == 4'b0010,
            "ERROR_CODE = INVALID_MEASUREMENT_LENGTH"
        );


        //==================================================================
        // TEST 16
        // MAXIMUM LEGAL MEASUREMENT
        //
        // TILE_ID = 7 bytes
        // CONFIG  = 64 bytes
        // IMEM    = 64 bytes
        //
        // Total = 7 + 64 + 64 = 135 bytes.
        //
        // This is exactly the Stage-6 maximum.
        //==================================================================

        $display("");
        $display("============================================================");
        $display("TEST 16: MAXIMUM LEGAL MEASUREMENT");
        $display("============================================================");

        reset_dut;

        drive_request_A;

        config_len = 7'd64;
        imem_len = 7'd64;

        pulse_start;

        wait_for_done;

        check(
            !err,
            "135-byte measurement accepted"
        );

        check(
            status == 3'b010,
            "Maximum legal request reaches RESPONSE_READY"
        );


        //==================================================================
        // TEST 17
        // BACK-TO-BACK TRANSACTIONS
        //
        // Transaction A followed by transaction B.
        //==================================================================

        $display("");
        $display("============================================================");
        $display("TEST 17: BACK-TO-BACK TRANSACTIONS");
        $display("============================================================");

        reset_dut;


        // -------------------------
        // Transaction A
        // -------------------------

        drive_request_A;

        pulse_start;

        wait_for_done;

        response_A = response;


        check(
            response_A[0 +: 56] == TILE_01,
            "Transaction A TILE_ID correct"
        );

        check(
            response_A[56 +: 80] == EPOCH_0001,
            "Transaction A EPOCH correct"
        );

        check(
            response_A[136 +: 128] == NONCE_A,
            "Transaction A NONCE correct"
        );


        // -------------------------
        // Transaction B
        // -------------------------

        tile_id = TILE_02;
        epoch = EPOCH_0002;
        nonce = NONCE_B;

        pulse_start;

        wait_for_done;

        response_B = response;


        check(
            response_B[0 +: 56] == TILE_02,
            "Transaction B TILE_ID correct"
        );

        check(
            response_B[56 +: 80] == EPOCH_0002,
            "Transaction B EPOCH correct"
        );

        check(
            response_B[136 +: 128] == NONCE_B,
            "Transaction B NONCE correct"
        );

        check(
            response_B !== response_A,
            "Transaction B response differs from A"
        );


        //==================================================================
        // FINAL
        //==================================================================

        $display("");
        $display("============================================================");
        $display("STAGE 8 CONTROLLER TB COMPLETE");
        $display("============================================================");

        $display("TOTAL CHECKS : %0d", tests);
        $display("TOTAL ERRORS : %0d", errors);

        if (errors == 0) begin

            $display("");
            $display("******** STAGE 8 CONTROLLER TB PASS ********");
            $display("");

        end
        else begin

            $display("");
            $display("******** STAGE 8 CONTROLLER TB FAIL ********");
            $display("");

        end

        $finish;

    end

endmodule