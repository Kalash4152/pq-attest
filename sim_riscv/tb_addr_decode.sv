`timescale 1ns / 1ps

module tb_addr_decode;

    logic clk_i = 0;
    logic reset_i = 1;

    logic        mem_valid_i = 0;
    logic        mem_instr_i = 0;
    logic [31:0] mem_addr_i = 0;
    logic [31:0] mem_wdata_i = 0;
    logic [3:0]  mem_wstrb_i = 0;
    logic        mem_ready_o;
    logic [31:0] mem_rdata_o;

    logic        bram_valid_o;
    logic [31:0] bram_addr_o, bram_wdata_o;
    logic [3:0]  bram_wstrb_o;
    logic        bram_ready_i = 0;
    logic [31:0] bram_rdata_i = 32'h12345678;

    logic        uart_req_o, uart_we_o;
    logic [31:0] uart_addr_o, uart_wdata_o;
    logic [3:0]  uart_wstrb_o;
    logic        uart_gnt_i;
    logic        uart_rvalid_i = 0;
    logic [31:0] uart_rdata_i = 32'h00000041;
    logic        uart_err_i = 0;

    logic [31:0] response_data;

    always #10 clk_i = ~clk_i;

    addr_decode dut (.*);

    // Simulated BRAM response: one cycle after request
    always_ff @(posedge clk_i) begin
        if (reset_i)
            bram_ready_i <= 0;
        else
            bram_ready_i <= bram_valid_o;
    end

    // Simulated UART: grant immediately, respond one cycle later
    assign uart_gnt_i = uart_req_o;

    always_ff @(posedge clk_i) begin
        if (reset_i)
            uart_rvalid_i <= 0;
        else
            uart_rvalid_i <= uart_req_o && uart_gnt_i;
    end

    task automatic start_request(
        input logic [31:0] address,
        input logic [3:0] strobes
    );
    begin
        @(negedge clk_i);
        mem_addr_i  = address;
        mem_wstrb_i = strobes;
        mem_valid_i = 1;
    end
    endtask

    task automatic finish_request;
    begin
        wait(mem_ready_o == 1);
        @(posedge clk_i);
        @(negedge clk_i);
        mem_valid_i = 0;
        mem_wstrb_i = 0;
    end
    endtask

    initial begin
        $display("Starting address decoder test...");

        repeat (3) @(negedge clk_i);
        reset_i = 0;

        // Test 1: BRAM read
        start_request(32'h00000000, 4'b0000);
        finish_request();

        if (mem_rdata_o !== 32'h12345678)
            $fatal(1, "BRAM read failed");

        $display("BRAM routing OK");

        // Test 2: UART write
        start_request(32'h10000000, 4'b0001);
        finish_request();

        $display("UART routing OK");

        // Test 3: Unmapped address
        start_request(32'h30000000, 4'b0000);
        finish_request();

        if (mem_rdata_o !== 32'b0)
            $fatal(1, "Unmapped address response failed");

        $display("Unmapped address response OK");
        $display("ADDRESS DECODER TEST PASSED");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Test timed out");
    end

endmodule