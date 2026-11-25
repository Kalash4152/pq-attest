`timescale 1ns / 1ps

module memory_tile #(
    parameter logic [3:0] TILE_ID = 4'h2,
    parameter integer MEM_WORDS = 4096,
    parameter INIT_FILE = ""
) (
    input  logic        clk_i,
    input  logic        reset_i,

    // ------------------------------------------------------------
    // Tile memory interface
    // ------------------------------------------------------------

    input  logic        tmem_req_i,
    input  logic        tmem_we_i,
    input  logic [31:0] tmem_addr_i,
    input  logic [31:0] tmem_wdata_i,
    input  logic [3:0]  tmem_wstrb_i,
    input  logic        tmem_is_fetch_i,

    output logic        tmem_gnt_o,
    output logic        tmem_rvalid_o,
    output logic [31:0] tmem_rdata_o,
    output logic        tmem_err_o
);

    localparam integer MEM_BYTES = MEM_WORDS * 4;

    logic [31:0] mem [0:MEM_WORDS-1];

    logic        pending_q;
    logic        pending_we_q;
    logic [31:0] pending_addr_q;
    logic [31:0] pending_wdata_q;
    logic [3:0]  pending_wstrb_q;
    logic        pending_err_q;

    logic [31:0] word_addr;

    logic access_valid;

    /*
     * Remote memory semantics:
     *
     *   addr[31:28] = 4'h2
     *   addr[27:24] = TILE_ID
     *   addr[23:0]  = byte offset into this memory
     *
     * Only data memory is exposed.
     *
     * For a 16 KB memory:
     *   valid offsets = 0x00000000 .. 0x00003FFC
     */

    always_comb begin

        word_addr = tmem_addr_i[31:2];

        access_valid =
            (tmem_addr_i[31:28] == 4'h2) &&
            (tmem_addr_i[27:24] == TILE_ID) &&
            (tmem_addr_i[1:0] == 2'b00) &&
            (tmem_addr_i[23:0] < MEM_BYTES);
    end

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    always_ff @(posedge clk_i) begin

        if (reset_i) begin

            tmem_gnt_o    <= 1'b0;
            tmem_rvalid_o <= 1'b0;
            tmem_rdata_o  <= 32'b0;
            tmem_err_o    <= 1'b0;

            pending_q      <= 1'b0;
            pending_we_q   <= 1'b0;
            pending_addr_q <= 32'b0;
            pending_wdata_q <= 32'b0;
            pending_wstrb_q <= 4'b0;
            pending_err_q  <= 1'b0;

        end
        else begin

            /*
             * Default: handshake/response signals are pulses.
             */
            tmem_gnt_o    <= 1'b0;
            tmem_rvalid_o <= 1'b0;
            tmem_err_o    <= 1'b0;

            /*
             * Accept exactly one request.
             *
             * The memory tile has one outstanding transaction,
             * matching the Lane-2 TMEM contract.
             */
            if (tmem_req_i && !pending_q) begin

                tmem_gnt_o <= 1'b1;

                pending_q       <= 1'b1;
                pending_we_q    <= tmem_we_i;
                pending_addr_q  <= tmem_addr_i;
                pending_wdata_q <= tmem_wdata_i;
                pending_wstrb_q <= tmem_wstrb_i;
                pending_err_q   <= !access_valid;

            end

            /*
             * Complete the request one cycle after grant.
             */
            if (pending_q) begin

                tmem_rvalid_o <= 1'b1;
                tmem_err_o    <= pending_err_q;

                if (pending_err_q) begin

                    /*
                     * Error response:
                     * reads return zero;
                     * writes change nothing.
                     */
                    tmem_rdata_o <= 32'b0;

                end
                else begin

                    /*
                     * Return the current word.
                     */
                    tmem_rdata_o <= mem[pending_addr_q[23:2]];

                    /*
                     * Apply byte writes.
                     *
                     * wstrb=0000 is a legal no-op.
                     */
                    if (pending_we_q) begin

                        if (pending_wstrb_q[0])
                            mem[pending_addr_q[23:2]][7:0]
                                <= pending_wdata_q[7:0];

                        if (pending_wstrb_q[1])
                            mem[pending_addr_q[23:2]][15:8]
                                <= pending_wdata_q[15:8];

                        if (pending_wstrb_q[2])
                            mem[pending_addr_q[23:2]][23:16]
                                <= pending_wdata_q[23:16];

                        if (pending_wstrb_q[3])
                            mem[pending_addr_q[23:2]][31:24]
                                <= pending_wdata_q[31:24];

                    end

                end

                pending_q <= 1'b0;

            end

        end

    end

endmodule