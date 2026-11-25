`timescale 1ns / 1ps

module tile_mem_wrapper #(
    parameter integer IMEM_WORDS = 4096,
    parameter integer DMEM_WORDS = 4096,
    parameter IMEM_INIT_FILE = "",
    parameter DMEM_INIT_FILE = ""
) (
    input  logic        clk_i,
    input  logic        reset_i,

    // Instruction memory
    input  logic        imem_valid_i,
    input  logic [31:0] imem_addr_i,
    input  logic [31:0] imem_wdata_i,
    input  logic [3:0]  imem_wstrb_i,
    output logic        imem_ready_o,
    output logic [31:0] imem_rdata_o,

    // Data memory
    input  logic        dmem_valid_i,
    input  logic [31:0] dmem_addr_i,
    input  logic [31:0] dmem_wdata_i,
    input  logic [3:0]  dmem_wstrb_i,
    output logic        dmem_ready_o,
    output logic [31:0] dmem_rdata_o,

    // Lane 1 2026-11-06 (A7): IMEM read port B for the measurement window reader (B3); 1-cycle latency
    input  logic        meas_rd_en_i,
    input  logic [31:0] meas_rd_addr_i,
    output logic [31:0] meas_rd_data_o
);

    // ------------------------------------------------------------
    // Instruction memory
    // ------------------------------------------------------------

    mem_bram #(
        .MEM_WORDS (IMEM_WORDS),
        .INIT_FILE (IMEM_INIT_FILE)
    ) imem_inst (
        .clk_i        (clk_i),
        .reset_i      (reset_i),

        .mem_valid_i  (imem_valid_i),
        .mem_addr_i   (imem_addr_i),
        .mem_wdata_i  (imem_wdata_i),
        .mem_wstrb_i  (imem_wstrb_i),

        .mem_ready_o  (imem_ready_o),
        .mem_rdata_o  (imem_rdata_o),

        .rdb_en_i     (meas_rd_en_i),
        .rdb_addr_i   (meas_rd_addr_i),
        .rdb_data_o   (meas_rd_data_o)
    );

    // ------------------------------------------------------------
    // Data memory
    // ------------------------------------------------------------

    mem_bram #(
        .MEM_WORDS (DMEM_WORDS),
        .INIT_FILE (DMEM_INIT_FILE)
    ) dmem_inst (
        .clk_i        (clk_i),
        .reset_i      (reset_i),

        .mem_valid_i  (dmem_valid_i),
        .mem_addr_i   (dmem_addr_i),
        .mem_wdata_i  (dmem_wdata_i),
        .mem_wstrb_i  (dmem_wstrb_i),

        .mem_ready_o  (dmem_ready_o),
        .mem_rdata_o  (dmem_rdata_o),

        .rdb_en_i     (1'b0),
        .rdb_addr_i   (32'b0),
        .rdb_data_o   ()
    );

endmodule