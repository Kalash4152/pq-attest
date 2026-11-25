`timescale 1ns / 1ps

module tb_traffic_gen;

    logic clk_i;
    logic reset_i;

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

    logic        done;
    logic [31:0] error_count;

    tmem_traffic_gen #(
        .NUM_TRANSACTIONS(100)
    ) dut (
        .clk_i          (clk_i),
        .reset_i        (reset_i),

        .tmem_req_o     (tmem_req),
        .tmem_we_o      (tmem_we),
        .tmem_addr_o    (tmem_addr),
        .tmem_wdata_o   (tmem_wdata),
        .tmem_wstrb_o   (tmem_wstrb),
        .tmem_is_fetch_o(tmem_is_fetch),

        .tmem_gnt_i     (tmem_gnt),
        .tmem_rvalid_i  (tmem_rvalid),
        .tmem_rdata_i   (tmem_rdata),
        .tmem_err_i     (tmem_err),

        .done_o         (done),
        .error_count_o  (error_count)
    );

    memory_tile #(
        .TILE_ID   (4'h2),
        .MEM_WORDS (4096)
    ) mem (
        .clk_i          (clk_i),
        .reset_i        (reset_i),

        .tmem_req_i     (tmem_req),
        .tmem_we_i      (tmem_we),
        .tmem_addr_i    (tmem_addr),
        .tmem_wdata_i   (tmem_wdata),
        .tmem_wstrb_i   (tmem_wstrb),
        .tmem_is_fetch_i(tmem_is_fetch),

        .tmem_gnt_o     (tmem_gnt),
        .tmem_rvalid_o  (tmem_rvalid),
        .tmem_rdata_o   (tmem_rdata),
        .tmem_err_o     (tmem_err)
    );

    always #10 clk_i = ~clk_i;

    initial begin
        clk_i   = 1'b0;
        reset_i = 1'b1;

        repeat (5)
            @(posedge clk_i);

        reset_i = 1'b0;

        wait (done);

        $display("");
        $display("==============================================");
        $display(" TMEM TRAFFIC GENERATOR TEST");
        $display("==============================================");
        $display("Transactions = 100");
        $display("Errors       = %0d", error_count);
        $display("----------------------------------------------");

        if (error_count == 0) begin
            $display("PASS: Traffic generator completed successfully.");
        end
        else begin
            $display("FAIL: Traffic generator reported %0d errors.",
                     error_count);
        end

        $display("==============================================");

        #100;
        $finish;
    end

endmodule