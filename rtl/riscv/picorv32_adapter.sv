`timescale 1ns / 1ps

module picorv32_adapter (
    input  logic        clk_i,
    input  logic        reset_i,

    // PicoRV32 memory interface
    input  logic        mem_valid_i,
    input  logic        mem_instr_i,
    input  logic [31:0] mem_addr_i,
    input  logic [31:0] mem_wdata_i,
    input  logic [3:0]  mem_wstrb_i,

    output logic        mem_ready_o,
    output logic [31:0] mem_rdata_o,

    // Local memory/peripheral interface
    output logic        local_req_o,
    output logic        local_we_o,
    output logic [31:0] local_addr_o,
    output logic [31:0] local_wdata_o,
    output logic [3:0]  local_wstrb_o,
    output logic        local_is_fetch_o,

    input  logic        local_gnt_i,
    input  logic        local_rvalid_i,
    input  logic [31:0] local_rdata_i,
    input  logic        local_err_i,

    // Remote tile memory interface
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

    // Lane 1 2026-11-06 (A3, brief v2 sec. A3): bus errors are no longer silent. On an error the transfer
    // completes with the poison value 0xBADB_E000 | code, bus_fault_o pulses (-> IRQ line + STATUS) and the
    // fault address / code are presented for STATUS to latch. tmem_err_code_i carries the bridge's error
    // kind (1 decode, 2 refused, 3 remote err, 4 timeout) as a sideband; the 10 TMEM signals are unchanged.
    input  logic [3:0]  tmem_err_code_i,
    output logic        bus_fault_o,
    output logic [31:0] fault_addr_o,
    output logic [3:0]  fault_code_o
);

    localparam logic [3:0]  FAULT_LOCAL = 4'd5;   // local unmapped / refused (incl. the R-D8 IMEM store)
    localparam logic [31:0] POISON      = 32'hBADB_E000;

    typedef enum logic [1:0] {
        IDLE,
        REQUEST,
        RESPONSE
    } state_t;

    state_t state_q;

    logic [31:0] addr_q;
    logic [31:0] wdata_q;
    logic [3:0]  wstrb_q;
    logic        we_q;
    logic        is_fetch_q;
    logic        remote_q;

    logic        mem_ready_q;
    logic        bus_fault_q;     // A3: one-cycle pulse, aligned with the error's mem_ready pulse
    logic [31:0] fault_addr_q;
    logic [3:0]  fault_code_q;
    logic [31:0] mem_rdata_q;

    // A capture attempt is an IDLE cycle with a live CPU request.
    // The actual capture is suppressed while the previous ready pulse
    // is being presented to PicoRV32.
    wire capture_attempt = (state_q == IDLE) && mem_valid_i;
    wire capture         = capture_attempt && !mem_ready_q;

    // a_no_capture_during_ready (brief A1), checked on the REGISTERED state, not on the capture wire:
    // in a cycle where the previous ready pulse is presented (IDLE && mem_ready_q), the adapter must
    // still be IDLE on the next edge. A live mem_valid in that cycle is legal (PicoRV32 keeps it high
    // for a compressed second-word fetch, picorv32.v:600-603) and must simply not be captured.
    // (The earlier check fired on suppressed *attempts*, ~317k false messages in XSim, and its edited
    // form `mem_ready_q && capture` was true by definition.)
    logic idle_ready_q;
    always @(posedge clk_i) begin
        if (reset_i) idle_ready_q <= 1'b0;
        else begin
            if (idle_ready_q && state_q != IDLE) begin
                $display("[FAIL] A1_NO_CAPTURE_DURING_READY: captured while mem_ready_q was high (t=%0t)", $time);
            end
            idle_ready_q <= (state_q == IDLE) && mem_ready_q;
        end
    end

    // A5 (brief v2 sec. 7.3; Lane 1 2026-11-07), checked on registered history like A1 (simulation messages only):
    //   A5_REQ_STABLE            while a request stays asserted (no grant yet), its address / we / wdata / wstrb / is_fetch
    //                            must not change from one cycle to the next;
    //   A5_RESPONSE_WITHOUT_REQ  an rvalid may only arrive in RESPONSE, i.e. at least one cycle after the grant and for the
    //                            one outstanding request (a response in IDLE or in the grant cycle is a protocol violation).
    logic        a5_req_q;
    logic [31:0] a5_addr_q, a5_wdata_q;
    logic [3:0]  a5_wstrb_q;
    logic        a5_we_q, a5_fetch_q;
    // Bench hook (default 0): a testbench that drives the TMEM port directly, bypassing this adapter (tb_two_tiles'
    // direct memory-tile test), sets it for exactly that window so the responses it causes are not attributed to the adapter.
    bit          a5_external_traffic = 1'b0;
    always @(posedge clk_i) begin
        if (reset_i) a5_req_q <= 1'b0;
        else begin
            if (a5_req_q && (local_req_o || tmem_req_o) &&
                ({addr_q, wdata_q, wstrb_q, we_q, is_fetch_q} != {a5_addr_q, a5_wdata_q, a5_wstrb_q, a5_we_q, a5_fetch_q}))
                $display("[FAIL] A5_REQ_STABLE: request fields changed while waiting for the grant (t=%0t)", $time);
            if ((local_rvalid_i || (tmem_rvalid_i && !a5_external_traffic)) && state_q != RESPONSE)
                $display("[FAIL] A5_RESPONSE_WITHOUT_REQ: rvalid in state %0d (t=%0t)", state_q, $time);
            a5_req_q   <= (local_req_o || tmem_req_o) && !(remote_q ? tmem_gnt_i : local_gnt_i);
            a5_addr_q  <= addr_q;  a5_wdata_q <= wdata_q; a5_wstrb_q <= wstrb_q; a5_we_q <= we_q; a5_fetch_q <= is_fetch_q;
        end
    end

    // ------------------------------------------------------------
    // Sequential logic
    // ------------------------------------------------------------

    always_ff @(posedge clk_i) begin

        if (reset_i) begin

            state_q <= IDLE;

            addr_q     <= 32'b0;
            wdata_q    <= 32'b0;
            wstrb_q    <= 4'b0;
            we_q       <= 1'b0;
            is_fetch_q <= 1'b0;
            remote_q   <= 1'b0;

            mem_ready_q <= 1'b0;
            mem_rdata_q <= 32'b0;
            bus_fault_q  <= 1'b0;
            fault_addr_q <= 32'b0;
            fault_code_q <= 4'b0;

        end
        else begin

            // Default: CPU ready is a one-cycle pulse.
            mem_ready_q <= 1'b0;
            bus_fault_q <= 1'b0;   // A3: pulse

            case (state_q)

                // ------------------------------------------------
                // Capture CPU transaction.
                // ------------------------------------------------

                IDLE: begin

                    // Do not recapture the completed transaction while
                    // PicoRV32 is sampling the previous mem_ready pulse.
                    if (capture) begin

                        addr_q     <= mem_addr_i;
                        wdata_q    <= mem_wdata_i;
                        wstrb_q    <= mem_wstrb_i;
                        we_q       <= |mem_wstrb_i;
                        is_fetch_q <= mem_instr_i;

                        remote_q <= (mem_addr_i[31:28] == 4'h2);

                        state_q <= REQUEST;
                    end

                end

                // ------------------------------------------------
                // Hold transaction until grant.
                // ------------------------------------------------

                REQUEST: begin

                    if (remote_q) begin

                        if (tmem_gnt_i)
                            state_q <= RESPONSE;

                    end
                    else begin

                        if (local_gnt_i)
                            state_q <= RESPONSE;

                    end

                end

                // ------------------------------------------------
                // Wait for response.
                // ------------------------------------------------

                RESPONSE: begin

                    if (remote_q) begin

                        if (tmem_rvalid_i) begin

                            if (tmem_err_i) begin
                                mem_rdata_q  <= POISON | {28'b0, (tmem_err_code_i == 4'd0 ? 4'd3 : tmem_err_code_i)};
                                bus_fault_q  <= 1'b1;
                                fault_addr_q <= addr_q;
                                fault_code_q <= (tmem_err_code_i == 4'd0 ? 4'd3 : tmem_err_code_i);
                            end
                            else
                                mem_rdata_q <= tmem_rdata_i;

                            mem_ready_q <= 1'b1;
                            state_q     <= IDLE;
                        end

                    end
                    else begin

                        if (local_rvalid_i) begin

                            if (local_err_i) begin
                                mem_rdata_q  <= POISON | {28'b0, FAULT_LOCAL};
                                bus_fault_q  <= 1'b1;
                                fault_addr_q <= addr_q;
                                fault_code_q <= FAULT_LOCAL;
                            end
                            else
                                mem_rdata_q <= local_rdata_i;

                            mem_ready_q <= 1'b1;
                            state_q     <= IDLE;
                        end

                    end

                end

                default: begin
                    state_q <= IDLE;
                end

            endcase

        end

    end

    // ------------------------------------------------------------
    // Output logic
    // ------------------------------------------------------------

    always_comb begin

        // Local interface.
        local_req_o      = 1'b0;
        local_we_o       = we_q;
        local_addr_o     = addr_q;
        local_wdata_o    = wdata_q;
        local_wstrb_o    = wstrb_q;
        local_is_fetch_o = is_fetch_q;

        // Remote interface.
        tmem_req_o       = 1'b0;
        tmem_we_o        = we_q;
        tmem_addr_o      = addr_q;
        tmem_wdata_o     = wdata_q;
        tmem_wstrb_o     = wstrb_q;
        tmem_is_fetch_o  = is_fetch_q;

        // Request is asserted only while waiting for grant.
        if (state_q == REQUEST) begin

            if (remote_q)
                tmem_req_o = 1'b1;
            else
                local_req_o = 1'b1;

        end

    end

    assign mem_ready_o = mem_ready_q;
    assign bus_fault_o  = bus_fault_q;
    assign fault_addr_o = fault_addr_q;
    assign fault_code_o = fault_code_q;
    assign mem_rdata_o = mem_rdata_q;

endmodule