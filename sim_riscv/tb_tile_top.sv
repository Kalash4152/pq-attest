`timescale 1ns / 1ps

module tb_tile_top;

    logic clk_i = 0;
    logic reset_i = 1;

    logic uart_tx;

    localparam integer BIT_PERIOD_NS = 8681;

    logic [3:0] switches;
    logic [3:0] leds;

    // ------------------------------------------------------------
    // Instruction memory
    // ------------------------------------------------------------

    logic        imem_valid;
    logic [31:0] imem_addr;
    logic [31:0] imem_wdata;
    logic [3:0]  imem_wstrb;
    logic        imem_ready;
    logic [31:0] imem_rdata;

    // ------------------------------------------------------------
    // Data memory
    // ------------------------------------------------------------

    logic        dmem_valid;
    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic [3:0]  dmem_wstrb;
    logic        dmem_ready;
    logic [31:0] dmem_rdata;

    // ------------------------------------------------------------
    // Tile memory interface
    // ------------------------------------------------------------

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

    // ------------------------------------------------------------
    // Attestation / status
    // ------------------------------------------------------------

    logic attested;
    logic last_fault_timeout;
    logic attest_req;

    // ------------------------------------------------------------
    // Debug
    // ------------------------------------------------------------

    logic [31:0] dbg_pc;
    logic [31:0] dbg_inst;
    logic        dbg_valid;
    logic        dbg_trap;

    integer cycle_count = 0;
    integer core_transfer_count = 0;
    integer adapter_capture_count = 0;
    integer adapter_response_count = 0;
    logic [31:0] max_pc = 32'h0, last_pc = 32'hFFFF_FFFF;   // progress tracking (Lane 1 fix 2026-11-06)
    integer pc_stable_cycles = 0;

    // ------------------------------------------------------------
    // Clock: 50 MHz
    // ------------------------------------------------------------

    always #10 clk_i = ~clk_i;

    // ------------------------------------------------------------
    // No remote traffic in this basic local-memory test
    // ------------------------------------------------------------

    assign tmem_gnt    = 1'b0;
    assign tmem_rvalid = 1'b0;
    assign tmem_rdata  = 32'b0;
    assign tmem_err    = 1'b0;

    // ------------------------------------------------------------
    // Tile
    // ------------------------------------------------------------

    tile_top #(
        .TILE_ID    (4'h0),
        .BUILD_ID   (32'h0000_0000),
        .IMEM_WORDS (2048),
        .DMEM_WORDS (2048),
        .HAS_UART   (1'b1)
    ) dut (
        .clk_i   (clk_i),
        .reset_i (reset_i),

        .imem_valid_o (imem_valid),
        .imem_addr_o  (imem_addr),
        .imem_wdata_o (imem_wdata),
        .imem_wstrb_o (imem_wstrb),
        .imem_ready_i (imem_ready),
        .imem_rdata_i (imem_rdata),

        .dmem_valid_o (dmem_valid),
        .dmem_addr_o  (dmem_addr),
        .dmem_wdata_o (dmem_wdata),
        .dmem_wstrb_o (dmem_wstrb),
        .dmem_ready_i (dmem_ready),
        .dmem_rdata_i (dmem_rdata),

        .uart_tx_o (uart_tx),

        .switches_i (switches),
        .leds_o     (leds),

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
        .tmem_err_code_i (4'd3),   // Lane 1 (A3)

        .attested_i           (attested),

        .grant_done_i         (1'b0),   // Lane 1 (B4)

        .attest_failed_i      (1'b0),
        .last_fault_timeout_i (last_fault_timeout),
        .attest_req_o         (attest_req),

        .dbg_pc_o    (dbg_pc),
        .dbg_inst_o (dbg_inst),
        .dbg_valid_o(dbg_valid),
        .dbg_trap_o (dbg_trap)
    );

    // ------------------------------------------------------------
    // External instruction/data memories
    // ------------------------------------------------------------

    tile_mem_wrapper #(
        .IMEM_WORDS (4096),
        .DMEM_WORDS (4096),
        .IMEM_INIT_FILE ("sw/hello_words.hex"),
        .DMEM_INIT_FILE ("")
    ) memory (
        .clk_i   (clk_i),
        .reset_i (reset_i),

        .imem_valid_i (imem_valid),
        .imem_addr_i  (imem_addr),
        .imem_wdata_i (imem_wdata),
        .imem_wstrb_i (imem_wstrb),
        .imem_ready_o (imem_ready),
        .imem_rdata_o (imem_rdata),

        .dmem_valid_i (dmem_valid),
        .dmem_addr_i  (dmem_addr),
        .dmem_wdata_i (dmem_wdata),
        .dmem_wstrb_i (dmem_wstrb),
        .dmem_ready_o (dmem_ready),
        .dmem_rdata_o (dmem_rdata),
        .meas_rd_en_i   (1'b0),   // Lane 1 (A7): no reader in this bench
        .meas_rd_addr_i (32'b0),
        .meas_rd_data_o ()
    );

    // ------------------------------------------------------------
    // UART monitor
    // ------------------------------------------------------------

    initial begin : uart_monitor
        logic [7:0] rx_byte;
        integer i;

        forever begin
            @(negedge uart_tx);

            #(BIT_PERIOD_NS / 2);

            if (uart_tx === 1'b0) begin
                for (i = 0; i < 8; i = i + 1) begin
                    #BIT_PERIOD_NS;
                    rx_byte[i] = uart_tx;
                end

                #BIT_PERIOD_NS;

                if (uart_tx === 1'b1)
                    $write("%c", rx_byte);
                else
                    $display("\nUART framing error");
            end
        end
    end

    // ------------------------------------------------------------
    // A1 counters and bounded heartbeat
    // ------------------------------------------------------------

    always @(posedge clk_i) begin
        if (reset_i) begin
            cycle_count             <= 0;
            core_transfer_count    <= 0;
            adapter_capture_count  <= 0;
            adapter_response_count <= 0;
        end
        else begin
            cycle_count <= cycle_count + 1;

            if (dut.mem_valid && dut.mem_ready)
                core_transfer_count <= core_transfer_count + 1;

            if (dut.adapter_inst.capture)
                adapter_capture_count <= adapter_capture_count + 1;

            if ((dut.adapter_inst.state_q == 2'd2) &&
                ((dut.adapter_inst.remote_q && tmem_rvalid) ||
                 (!dut.adapter_inst.remote_q && dut.local_rvalid)))
                adapter_response_count <= adapter_response_count + 1;

            // progress tracking (Lane 1 fix 2026-11-06): highest PC seen, and how long the PC has been unchanged
            if (dut.cpu.reg_pc > max_pc) max_pc <= dut.cpu.reg_pc;
            if (dut.cpu.reg_pc == last_pc) pc_stable_cycles <= pc_stable_cycles + 1;
            else begin pc_stable_cycles <= 0; last_pc <= dut.cpu.reg_pc; end

            if ((cycle_count != 0) && ((cycle_count % 50000) == 0)) begin
                $display("A1 HEARTBEAT cycle=%0d time=%0t pc=%08h mem_valid=%b mem_ready=%b adapter_state=%0d captures=%0d core_xfers=%0d responses=%0d",
                    cycle_count, $time, dut.cpu.reg_pc, dut.mem_valid,
                    dut.mem_ready, dut.adapter_inst.state_q,
                    adapter_capture_count, core_transfer_count,
                    adapter_response_count);
                $fflush;
            end
        end
    end

    // ------------------------------------------------------------
    // Simulation
    // ------------------------------------------------------------

    // Lane 1 fix 2026-11-06: the bench never ended in XSim. Causes: (1) the adapter assertion printed an
    // $error + $fatal on every suppressed capture attempt (~317k false messages), and (2) $fatal does not
    // terminate an xsim -R run, so neither the FAIL path nor the watchdog ended it. Now: every exit path
    // prints RESULT and calls $finish; the check waits for the program to reach its end loop (the CPU spends
    // ~22 ms printing over the 115,200-baud UART, far past the old 5,000-cycle window).
    localparam integer MAX_CYCLES      = 2_500_000;   // 50 ms at 20 ns
    localparam integer END_LOOP_CYCLES = 1_000;       // PC unchanged this long = end-of-program spin loop
    integer run_cycles;
    integer settle_cycles;
    initial begin
        switches           = 4'b0000;
        attested           = 1'b0;
        last_fault_timeout = 1'b0;

        $display("Starting A1 tile_top test...");
        $fflush;

        #200;
        reset_i = 1'b0;

        run_cycles = 0;
        while ((pc_stable_cycles < END_LOOP_CYCLES) && (run_cycles < MAX_CYCLES)) begin
            @(posedge clk_i);
            run_cycles = run_cycles + 1;
        end

        // Drain the final in-flight transaction, with a bounded wait.
        settle_cycles = 0;
        while (((dut.adapter_inst.state_q != 2'd0) ||
                dut.mem_valid || dut.adapter_inst.mem_ready_q) &&
               (settle_cycles < 100)) begin
            @(posedge clk_i);
            settle_cycles = settle_cycles + 1;
        end

        #1;
        $display("A1 FINAL: pc=%08h max_pc=%08h end_loop=%0b run_cycles=%0d core_transfers=%0d adapter_captures=%0d adapter_responses=%0d settle_cycles=%0d",
            dut.cpu.reg_pc, max_pc, pc_stable_cycles >= END_LOOP_CYCLES, run_cycles, core_transfer_count,
            adapter_capture_count, adapter_response_count, settle_cycles);

        if ((max_pc > 32'h0000_012c) && (pc_stable_cycles >= END_LOOP_CYCLES) &&
            (core_transfer_count == adapter_capture_count) &&
            (core_transfer_count == adapter_response_count) &&
            (dut.adapter_inst.state_q == 2'd0) &&
            !dut.mem_valid && !dut.adapter_inst.mem_ready_q) begin
            $display("PASS: A1 tile_top CPU advanced beyond 0x12C to its end loop; core transfers, adapter captures and responses match.");
            $display("RESULT : PASS");
            $fflush;
            $finish;
        end
        else begin
            $display("FAIL: A1 tile_top acceptance criteria not met.");
            $display("  PC beyond 0x12C (max seen): %b", max_pc > 32'h0000_012c);
            $display("  program reached its end loop: %b", pc_stable_cycles >= END_LOOP_CYCLES);
            $display("  core_transfers == adapter_captures: %b",
                core_transfer_count == adapter_capture_count);
            $display("  core_transfers == adapter_responses: %b",
                core_transfer_count == adapter_response_count);
            $display("  adapter_idle: %b", dut.adapter_inst.state_q == 2'd0);
            $display("  mem_valid_low: %b", !dut.mem_valid);
            $display("RESULT : FAIL");
            $fflush;
            $finish;   // $fatal does not end an xsim -R run
        end
    end

    // Simulation-time watchdog (60 ms, above MAX_CYCLES). Use an external wall-clock timeout too,
    // because a zero-time loop cannot advance to this watchdog.
    initial begin
        #60_000_000;
        $display("FAIL: timeout in tb_tile_top");
        $display("RESULT : FAIL");
        $fflush;
        $finish;
    end

endmodule