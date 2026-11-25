`timescale 1ns / 1ps

module mem_bram #(
    parameter integer MEM_WORDS = 2048,
    parameter INIT_FILE = ""
) (
    input  logic        clk_i,
    input  logic        reset_i,

    input  logic        mem_valid_i,
    input  logic [31:0] mem_addr_i,
    input  logic [31:0] mem_wdata_i,
    input  logic [3:0]  mem_wstrb_i,

    output logic        mem_ready_o,
    output logic [31:0] mem_rdata_o,

    // Lane 1 2026-11-06 (A7): read-only port B (byte address, word read, registered: data one cycle after
    // rdb_en_i, like port A). Used on IMEM by the measurement window reader (B3) so it never stalls the CPU.
    // Infers a simple dual-port BRAM (A: read/write, B: read). Tie rdb_en_i to 0 where unused.
    input  logic        rdb_en_i,
    input  logic [31:0] rdb_addr_i,
    output logic [31:0] rdb_data_o
);

    logic [31:0] mem [0:MEM_WORDS-1];

    localparam integer WORD_ADDR_BITS = $clog2(MEM_WORDS);

    wire [WORD_ADDR_BITS-1:0] word_addr =
        mem_addr_i[WORD_ADDR_BITS+1:2];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    wire [WORD_ADDR_BITS-1:0] word_addr_b = rdb_addr_i[WORD_ADDR_BITS+1:2];

    always_ff @(posedge clk_i) begin
        if (rdb_en_i)
            rdb_data_o <= mem[word_addr_b];
    end

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            mem_ready_o <= 1'b0;
            mem_rdata_o <= 32'b0;
        end
        else begin
            // Default: no response.
            mem_ready_o <= 1'b0;

            if (mem_valid_i) begin

                // Valid word-aligned access within this memory.
                if ((mem_addr_i[1:0] == 2'b00) &&
                    (mem_addr_i < MEM_WORDS * 4)) begin

                    mem_ready_o <= 1'b1;

                    // Read data.
                    mem_rdata_o <= mem[word_addr];

                    // Byte-write enables.
                    if (mem_wstrb_i[0])
                        mem[word_addr][7:0] <= mem_wdata_i[7:0];

                    if (mem_wstrb_i[1])
                        mem[word_addr][15:8] <= mem_wdata_i[15:8];

                    if (mem_wstrb_i[2])
                        mem[word_addr][23:16] <= mem_wdata_i[23:16];

                    if (mem_wstrb_i[3])
                        mem[word_addr][31:24] <= mem_wdata_i[31:24];
                end
            end
        end
    end

endmodule