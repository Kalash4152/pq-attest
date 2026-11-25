`timescale 1ns / 1ps

module tb_uart_mmio;

    logic clk_i = 0;
    logic reset_i = 1;
    logic req_i = 0;
    logic we_i = 0;
    logic [31:0] addr_i = 0;
    logic [31:0] wdata_i = 0;
    logic [3:0] wstrb_i = 0;

    logic gnt_o, rvalid_o, err_o, tx_o;
    logic [31:0] rdata_o;

    localparam integer CLK_PERIOD = 20;

    uart_mmio dut (
        .clk_i(clk_i),
        .reset_i(reset_i),
        .req_i(req_i),
        .we_i(we_i),
        .addr_i(addr_i),
        .wdata_i(wdata_i),
        .wstrb_i(wstrb_i),
        .gnt_o(gnt_o),
        .rvalid_o(rvalid_o),
        .rdata_o(rdata_o),
        .err_o(err_o),
        .tx_o(tx_o)
    );

    always #(CLK_PERIOD/2) clk_i = ~clk_i;

    task automatic bus_access(
        input logic write_enable,
        input logic [31:0] address,
        input logic [31:0] write_data,
        input logic [3:0] strobes
    );
    begin
        @(negedge clk_i);
        req_i   = 1;
        we_i    = write_enable;
        addr_i  = address;
        wdata_i = write_data;
        wstrb_i = strobes;

        wait(gnt_o == 1);
        @(posedge clk_i);
        @(negedge clk_i);
        req_i = 0;
        we_i  = 0;

        wait(rvalid_o == 1);
        #1;
    end
    endtask

    initial begin
        $display("Starting UART MMIO test...");

        repeat(5) @(negedge clk_i);
        reset_i = 0;

        // Test 1: Write character 'A'
        bus_access(1, 32'h00000000, 32'h00000041, 4'b0001);
        $display("UART data write accepted");

        // Test 2: Read UART status
        bus_access(0, 32'h00000004, 32'b0, 4'b0000);
        if (err_o !== 0)
            $fatal(1, "Status read error");

        $display("UART status read OK");

        // Test 3: Invalid address
        bus_access(0, 32'h00000008, 32'b0, 4'b0000);
        if (err_o !== 1)
            $fatal(1, "Invalid address error not detected");

        $display("Invalid address error OK");

        // Test 4: Check serial transmission begins
        wait(tx_o == 0);
        $display("UART serial transmission started");

        $display("UART MMIO TEST PASSED");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "UART MMIO test timed out");
    end

endmodule