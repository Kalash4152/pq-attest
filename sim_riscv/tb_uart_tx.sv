`timescale 1ns / 1ps

module tb_uart_tx;

    logic clk_i = 0;
    logic reset_i = 1;
    logic wr_en_i = 0;
    logic [7:0] wdata_i = 0;

    logic full_o;
    logic busy_o;
    logic tx_o;

    localparam integer CLK_PERIOD = 20;
    localparam integer BIT_PERIOD = 434;

    uart_tx #(
        .CLK_FREQ_HZ(50_000_000),
        .BAUD_RATE(115200),
        .FIFO_DEPTH(16)
    ) dut (
        .clk_i(clk_i),
        .reset_i(reset_i),
        .wr_en_i(wr_en_i),
        .wdata_i(wdata_i),
        .full_o(full_o),
        .busy_o(busy_o),
        .tx_o(tx_o)
    );

    always #(CLK_PERIOD/2) clk_i = ~clk_i;

    task automatic check_bit(
        input logic expected,
        input integer bit_number
    );
        begin
            #(BIT_PERIOD * CLK_PERIOD);

            if (tx_o !== expected) begin
                $error(
                    "Bit %0d mismatch: expected %b, got %b",
                    bit_number, expected, tx_o
                );
                $fatal(1);
            end
        end
    endtask

    initial begin
        $display("Starting UART test...");

        // Reset
        repeat (5) @(negedge clk_i);
        reset_i = 0;

        repeat (2) @(negedge clk_i);

        // Write 0xA5 into FIFO
        wdata_i = 8'hA5;
        wr_en_i = 1;

        @(negedge clk_i);
        wr_en_i = 0;

        // Wait for start bit
        wait (tx_o == 1'b0);

        // Sample center of start bit
        #(BIT_PERIOD * CLK_PERIOD / 2);

        if (tx_o !== 1'b0)
            $fatal(1, "Start bit incorrect");

        $display("Start bit OK");

        // Data bits of 0xA5, LSB first: 1,0,1,0,0,1,0,1
        check_bit(1'b1, 0);
        check_bit(1'b0, 1);
        check_bit(1'b1, 2);
        check_bit(1'b0, 3);
        check_bit(1'b0, 4);
        check_bit(1'b1, 5);
        check_bit(1'b0, 6);
        check_bit(1'b1, 7);

        $display("All 8 data bits OK");

        // Stop bit
        check_bit(1'b1, 8);

        $display("Stop bit OK");
        $display("UART TEST PASSED");

        $finish;
    end

    initial begin
        #(CLK_PERIOD * BIT_PERIOD * 15);
        $fatal(1, "UART test timed out");
    end

endmodule