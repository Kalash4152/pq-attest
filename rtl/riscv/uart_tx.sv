module uart_tx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115200,
    parameter integer FIFO_DEPTH  = 16
)(
    input  logic        clk_i,
    input  logic        reset_i,

    // Write interface
    input  logic        wr_en_i,
    input  logic [7:0]  wdata_i,
    output logic        full_o,
    output logic        busy_o,

    // UART serial output
    output logic        tx_o
);

    localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    localparam integer PTR_WIDTH = $clog2(FIFO_DEPTH);

    logic [7:0] fifo [0:FIFO_DEPTH-1];

    logic [PTR_WIDTH-1:0] wr_ptr_q;
    logic [PTR_WIDTH-1:0] rd_ptr_q;
    logic [PTR_WIDTH:0]   count_q;

    logic [7:0] tx_data_q;
    logic [3:0] bit_idx_q;
    logic [15:0] baud_cnt_q;

    typedef enum logic [1:0] {
        IDLE,
        START,
        DATA,
        STOP
    } tx_state_t;

    tx_state_t state_q;

    logic fifo_pop;

    assign full_o = (count_q == FIFO_DEPTH);
    assign busy_o = (count_q != 0) || (state_q != IDLE);

    // FIFO
    always_ff @(posedge clk_i) begin   // Lane 1 2026-11-06 (A6): synchronous reset
        if (reset_i) begin
            wr_ptr_q <= '0;
            rd_ptr_q <= '0;
            count_q  <= '0;
        end else begin
            if (wr_en_i && !full_o) begin
                fifo[wr_ptr_q] <= wdata_i;
                wr_ptr_q <= wr_ptr_q + 1'b1;
            end

            if (fifo_pop) begin
                rd_ptr_q <= rd_ptr_q + 1'b1;
            end

            case ({wr_en_i && !full_o, fifo_pop})
                2'b10: count_q <= count_q + 1'b1;
                2'b01: count_q <= count_q - 1'b1;
                default: count_q <= count_q;
            endcase
        end
    end

    // UART transmitter
    always_ff @(posedge clk_i) begin   // Lane 1 2026-11-06 (A6): synchronous reset
        if (reset_i) begin
            state_q    <= IDLE;
            tx_o       <= 1'b1;
            tx_data_q  <= 8'h00;
            bit_idx_q  <= 0;
            baud_cnt_q <= 0;
        end else begin
            case (state_q)

                IDLE: begin
                    tx_o       <= 1'b1;
                    baud_cnt_q <= 0;
                    bit_idx_q  <= 0;

                    if (count_q != 0) begin
                        tx_data_q <= fifo[rd_ptr_q];
                        state_q   <= START;
                    end
                end

                START: begin
                    tx_o <= 1'b0;

                    if (baud_cnt_q == CLKS_PER_BIT - 1) begin
                        baud_cnt_q <= 0;
                        bit_idx_q  <= 0;
                        state_q    <= DATA;
                    end else begin
                        baud_cnt_q <= baud_cnt_q + 1'b1;
                    end
                end

                DATA: begin
                    tx_o <= tx_data_q[bit_idx_q];

                    if (baud_cnt_q == CLKS_PER_BIT - 1) begin
                        baud_cnt_q <= 0;

                        if (bit_idx_q == 7) begin
                            bit_idx_q <= 0;
                            state_q   <= STOP;
                        end else begin
                            bit_idx_q <= bit_idx_q + 1'b1;
                        end
                    end else begin
                        baud_cnt_q <= baud_cnt_q + 1'b1;
                    end
                end

                STOP: begin
                    tx_o <= 1'b1;

                    if (baud_cnt_q == CLKS_PER_BIT - 1) begin
                        baud_cnt_q <= 0;
                        state_q    <= IDLE;
                    end else begin
                        baud_cnt_q <= baud_cnt_q + 1'b1;
                    end
                end

                default: state_q <= IDLE;

            endcase
        end
    end

    // Remove a FIFO entry when the transmitter accepts it.
    assign fifo_pop = (state_q == IDLE) && (count_q != 0);

endmodule