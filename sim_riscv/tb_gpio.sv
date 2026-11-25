`timescale 1ns / 1ps

module tb_gpio;
    // Lane 1 2026-11-06 (A5): self-checking (CHECKS = 4, frozen before the first registered run)
    int lc_checks = 0, lc_errors = 0;
    function automatic void lc_check(input bit ok, input string name);
        lc_checks++; if (ok) $display("[PASS] %s", name); else begin lc_errors++; $display("[FAIL] %s", name); end
    endfunction

    logic clk_i;
    logic reset_i;
    logic req_i;
    logic we_i;
    logic [31:0] addr_i;
    logic [31:0] wdata_i;
    logic [3:0] wstrb_i;

    logic gnt_o;
    logic rvalid_o;
    logic [31:0] rdata_o;
    logic err_o;

    logic [3:0] switches_i;
    logic [3:0] leds_o;

    gpio dut (
        .clk_i       (clk_i),
        .reset_i     (reset_i),
        .req_i       (req_i),
        .we_i        (we_i),
        .addr_i      (addr_i),
        .wdata_i     (wdata_i),
        .wstrb_i     (wstrb_i),
        .gnt_o       (gnt_o),
        .rvalid_o    (rvalid_o),
        .rdata_o     (rdata_o),
        .err_o       (err_o),
        .switches_i  (switches_i),
        .leds_o      (leds_o)
    );

    always #5 clk_i = ~clk_i;

    initial begin
        clk_i      = 0;
        reset_i    = 1;
        req_i      = 0;
        we_i       = 0;
        addr_i     = 0;
        wdata_i    = 0;
        wstrb_i    = 0;
        switches_i = 4'b1010;

        #20;
        reset_i = 0;

        // --------------------------------------------------------
        // Write 0xA to LED register
        // --------------------------------------------------------
        @(negedge clk_i);
        req_i   = 1;
        we_i    = 1;
        addr_i  = 32'h0000_0000;
        wdata_i = 32'h0000_000A;
        wstrb_i = 4'b0001;

        @(negedge clk_i);
        req_i = 0;
        we_i  = 0;

        @(posedge clk_i);
        #1;

        $display("LEDs = %h", leds_o);
        lc_check(leds_o == 4'hA, "GPIO_LED_WRITE");

        // --------------------------------------------------------
        // Read LED register
        // --------------------------------------------------------
        @(negedge clk_i);
        req_i  = 1;
        we_i   = 0;
        addr_i = 32'h0000_0000;

        @(negedge clk_i);
        req_i = 0;

        @(posedge clk_i);
        #1;

        $display("LED read = %h, err = %b", rdata_o, err_o);
        lc_check(rdata_o == 32'hA && !err_o, "GPIO_LED_READ");

        // --------------------------------------------------------
        // Read switches
        // --------------------------------------------------------
        @(negedge clk_i);
        req_i  = 1;
        we_i   = 0;
        addr_i = 32'h0000_0004;

        @(negedge clk_i);
        req_i = 0;

        @(posedge clk_i);
        #1;

        $display("Switch read = %h, err = %b", rdata_o, err_o);
        lc_check(rdata_o == 32'hA && !err_o, "GPIO_SWITCH_READ");

        // --------------------------------------------------------
        // Invalid address
        // --------------------------------------------------------
        @(negedge clk_i);
        req_i  = 1;
        we_i   = 0;
        addr_i = 32'h0000_0008;

        @(posedge clk_i);
        #1;

        $display("Invalid read: rdata = %h, err = %b", rdata_o, err_o);
        lc_check(rdata_o == 32'h0 && err_o, "GPIO_INVALID_ERR");

        @(negedge clk_i);
        req_i = 0;

        $display("CHECKS : %0d", lc_checks);
        $display("ERRORS : %0d", lc_errors);
        $display("RESULT : %s", lc_errors == 0 && lc_checks == 4 ? "PASS" : "FAIL");
        $finish;
    end

endmodule