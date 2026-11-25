`timescale 1ns / 1ps

module uart_mmio #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115200,
    parameter integer FIFO_DEPTH  = 16
)(
    input  logic        clk_i,
    input  logic        reset_i,

    // Memory-mapped bus interface
    input  logic        req_i,
    input  logic        we_i,
    input  logic [31:0] addr_i,
    input  logic [31:0] wdata_i,
    input  logic [3:0]  wstrb_i,
    output logic        gnt_o,
    output logic        rvalid_o,
    output logic [31:0] rdata_o,
    output logic        err_o,

    // UART serial output
    output logic        tx_o
);

    localparam logic [31:0] UART_DATA   = 32'h0000_0000;
    localparam logic [31:0] UART_STATUS = 32'h0000_0004;

    logic       uart_full;
    logic       uart_busy;
    logic       uart_wr_en;
    logic [7:0] uart_wdata;

    logic        accept;
    logic [31:0] response_data;
    logic        response_error;

    // Bus acceptance
    always_comb begin
        gnt_o = 1'b0;

        if (req_i) begin
            if (addr_i == UART_DATA && we_i)
                gnt_o = !uart_full;
            else
                gnt_o = 1'b1;
        end
    end

    assign accept = req_i && gnt_o;

    // UART data write
    always_comb begin
        uart_wr_en = 1'b0;
        uart_wdata = wdata_i[7:0];

        if (accept && we_i &&
            addr_i == UART_DATA && wstrb_i[0])
            uart_wr_en = 1'b1;
    end

    // Response data and error decoding
    always_comb begin
        response_data  = 32'b0;
        response_error = 1'b0;

        if (addr_i == UART_DATA) begin
            if (!we_i)
                response_data = 32'b0;
        end
        else if (addr_i == UART_STATUS) begin
            if (!we_i)
                response_data = {30'b0, uart_busy, uart_full};
        end
        else begin
            response_error = 1'b1;
        end
    end

    // Registered bus response
    always_ff @(posedge clk_i) begin   // Lane 1 2026-11-06 (A6): synchronous reset
        if (reset_i) begin
            rvalid_o <= 1'b0;
            rdata_o  <= 32'b0;
            err_o    <= 1'b0;
        end
        else begin
            rvalid_o <= accept;

            if (accept) begin
                rdata_o <= response_data;
                err_o   <= response_error;
            end
            else begin
                err_o <= 1'b0;
            end
        end
    end

    // UART transmitter
    uart_tx #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE),
        .FIFO_DEPTH  (FIFO_DEPTH)
    ) uart_tx_inst (
        .clk_i   (clk_i),
        .reset_i (reset_i),
        .wr_en_i (uart_wr_en),
        .wdata_i (uart_wdata),
        .full_o  (uart_full),
        .busy_o  (uart_busy),
        .tx_o    (tx_o)
    );

endmodule