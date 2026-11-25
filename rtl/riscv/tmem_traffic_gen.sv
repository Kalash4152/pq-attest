`timescale 1ns / 1ps

module tmem_traffic_gen #(
    parameter integer NUM_TRANSACTIONS = 100
) (
    input  logic        clk_i,
    input  logic        reset_i,

    output logic        tmem_req_o,
    output logic        tmem_we_o,
    output logic [31:0] tmem_addr_o,
    output logic [31:0] tmem_wdata_o,
    output logic [3:0]  tmem_wstrb_o,
    output logic        tmem_is_fetch_o,

    input  logic        tmem_gnt_i,
    input  logic        tmem_rvalid_i,
    input  logic [31:0] tmem_rdata_i,
    input  logic        tmem_err_i,

    output logic        done_o,
    output logic [31:0] error_count_o
);

    typedef enum logic [1:0] {
        IDLE,
        REQUEST,
        RESPONSE,
        DONE
    } state_t;

    state_t state_q;

    integer transaction_q;
    integer expected_q;
    integer error_count_q;

    logic [31:0] addr_q;
    logic [31:0] wdata_q;
    logic [3:0]  wstrb_q;
    logic        we_q;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            state_q        <= IDLE;
            transaction_q  <= 0;
            expected_q     <= 0;
            error_count_q  <= 0;

            addr_q         <= 32'b0;
            wdata_q        <= 32'b0;
            wstrb_q        <= 4'b0;
            we_q           <= 1'b0;
        end
        else begin
            case (state_q)

                IDLE: begin
                    transaction_q <= 0;
                    error_count_q <= 0;

                    addr_q        <= 32'h22000000;
                    wdata_q       <= 32'h10000000;
                    wstrb_q       <= 4'b1111;
                    we_q          <= 1'b1;

                    state_q       <= REQUEST;
                end

                REQUEST: begin
                    if (tmem_gnt_i)
                        state_q <= RESPONSE;
                end

                RESPONSE: begin
                    if (tmem_rvalid_i) begin

                        if (tmem_err_i)
                            error_count_q <= error_count_q + 1;

                        transaction_q <= transaction_q + 1;

                        if (transaction_q + 1 >= NUM_TRANSACTIONS) begin
                            state_q <= DONE;
                        end
                        else begin
                            /*
                             * Alternate between writes and reads.
                             *
                             * Even transaction:
                             *   write a known value
                             *
                             * Odd transaction:
                             *   read the same location
                             */
                            if (((transaction_q + 1) % 2) == 0) begin
                                addr_q <= 32'h22000000;
                                wdata_q <= 32'b0;
                                wstrb_q <= 4'b0;
                                we_q <= 1'b0;
                                expected_q <= 32'h10000000;
                            end
                            else begin
                                addr_q <= 32'h22000000;
                                wdata_q <= 32'h10000000
                                           + transaction_q + 1;
                                wstrb_q <= 4'b1111;
                                we_q <= 1'b1;
                            end

                            state_q <= REQUEST;
                        end
                    end
                end

                DONE: begin
                    state_q <= DONE;
                end

                default: begin
                    state_q <= IDLE;
                end

            endcase
        end
    end

    always_comb begin
        tmem_req_o      = 1'b0;
        tmem_we_o       = we_q;
        tmem_addr_o     = addr_q;
        tmem_wdata_o    = wdata_q;
        tmem_wstrb_o    = wstrb_q;
        tmem_is_fetch_o = 1'b0;

        if (state_q == REQUEST)
            tmem_req_o = 1'b1;
    end

    assign done_o        = (state_q == DONE);
    assign error_count_o = error_count_q;

endmodule