`timescale 1ns / 1ps

// tile_status: STATUS block at 0x1000_2000 (base stripped by addr_decode).
// Lane 1 2026-11-06 (R2.3, brief v2 sec. B4, decision R-D4): register map changed to the brief's B4 map, plus TILE_ID at
// +0x10 (read-only; the brief's map dropped it and the firmware prints it). Synchronous reset (A6).
//   +0x00 [0] ATTEST_REQ     W1: one-cycle pulse on attest_req_o; reads 0
//         [1] AUTHORIZED     RO: authorized_i (tile authorized by the RoT)
//         [2] GRANT_SEEN     RO sticky, W1C: set by grant_done_i
//         [3] ATTEST_FAILED  RO sticky, W1C: set by attest_failed_i
//         [4] BUS_FAULT      RO sticky, W1C: set by bus_fault_i (A3)
//   +0x04 FAULT_ADDR [31:0]  RO: address of the first fault since BUS_FAULT was last cleared
//   +0x08 FAULT_CODE [3:0]   RO: 1 decode, 2 refused, 3 remote err, 4 timeout, 5 local unmapped (with FAULT_ADDR)
//   +0x0C BUILD_ID   [31:0]  RO
//   +0x10 TILE_ID    [3:0]   RO
// Any other offset, or a write to a read-only register, answers err (no state change).
// FAULT_ADDR / FAULT_CODE keep the FIRST fault until BUS_FAULT is cleared, so firmware always reads a consistent pair.
// A W1C clear and a new set in the same cycle: the set wins (no event is lost).
module tile_status (
    input  logic        clk_i,
    input  logic        reset_i,

    // Bus interface (one-cycle grant / response)
    input  logic        req_i,
    input  logic        we_i,
    input  logic [31:0] addr_i,
    input  logic [31:0] wdata_i,
    input  logic [3:0]  wstrb_i,

    output logic        gnt_o,
    output logic        rvalid_o,
    output logic [31:0] rdata_o,
    output logic        err_o,

    // Status inputs
    input  logic [31:0] build_id_i,
    input  logic [3:0]  tile_id_i,
    input  logic        attested_i,            // AUTHORIZED
    input  logic        last_fault_timeout_i,  // legacy input of the imported tile; superseded by fault_code_i = 4
    input  logic        grant_done_i,          // pulse: tile 3's GRANT accepted
    input  logic        attest_failed_i,       // pulse: attestation failed
    input  logic        bus_fault_i,           // pulse: a bus error completed to the CPU (A3)
    input  logic [31:0] fault_addr_i,
    input  logic [3:0]  fault_code_i,

    // Control output
    output logic        attest_req_o
);

    localparam logic [31:0] OFF_CTRL       = 32'h0000_0000;
    localparam logic [31:0] OFF_FAULT_ADDR = 32'h0000_0004;
    localparam logic [31:0] OFF_FAULT_CODE = 32'h0000_0008;
    localparam logic [31:0] OFF_BUILD_ID   = 32'h0000_000C;
    localparam logic [31:0] OFF_TILE_ID    = 32'h0000_0010;

    logic grant_seen_q, attest_failed_q, bus_fault_q;
    logic [31:0] fault_addr_q;
    logic [3:0]  fault_code_q;

    logic accept;
    logic [31:0] read_data;
    logic        access_error;
    logic        w1_attest, w1c_grant, w1c_failed, w1c_fault;

    assign gnt_o  = 1'b1;
    assign accept = req_i && gnt_o;

    always_comb begin
        read_data    = 32'b0;
        access_error = 1'b0;
        w1_attest = 1'b0; w1c_grant = 1'b0; w1c_failed = 1'b0; w1c_fault = 1'b0;
        case (addr_i)
            OFF_CTRL: begin
                read_data = {27'b0, bus_fault_q, attest_failed_q, grant_seen_q, attested_i, 1'b0};
                if (we_i && wstrb_i[0]) begin
                    w1_attest  = wdata_i[0];
                    w1c_grant  = wdata_i[2];
                    w1c_failed = wdata_i[3];
                    w1c_fault  = wdata_i[4];
                end
            end
            OFF_FAULT_ADDR: begin read_data = fault_addr_q;         if (we_i) access_error = 1'b1; end
            OFF_FAULT_CODE: begin read_data = {28'b0, fault_code_q}; if (we_i) access_error = 1'b1; end
            OFF_BUILD_ID:   begin read_data = build_id_i;           if (we_i) access_error = 1'b1; end
            OFF_TILE_ID:    begin read_data = {28'b0, tile_id_i};   if (we_i) access_error = 1'b1; end
            default:        access_error = 1'b1;
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            rvalid_o <= 1'b0; rdata_o <= 32'b0; err_o <= 1'b0; attest_req_o <= 1'b0;
            grant_seen_q <= 1'b0; attest_failed_q <= 1'b0; bus_fault_q <= 1'b0;
            fault_addr_q <= 32'b0; fault_code_q <= 4'b0;
        end
        else begin
            rvalid_o     <= 1'b0;
            err_o        <= 1'b0;
            attest_req_o <= 1'b0;
            if (accept) begin
                rvalid_o <= 1'b1;
                rdata_o  <= read_data;
                err_o    <= access_error;
                if (!access_error && w1_attest) attest_req_o <= 1'b1;
            end
            // sticky flags: W1C clear, set wins in the same cycle
            if (accept && !access_error && w1c_grant)  grant_seen_q    <= 1'b0;
            if (accept && !access_error && w1c_failed) attest_failed_q <= 1'b0;
            if (accept && !access_error && w1c_fault)  bus_fault_q     <= 1'b0;
            if (grant_done_i)    grant_seen_q    <= 1'b1;
            if (attest_failed_i) attest_failed_q <= 1'b1;
            if (bus_fault_i) begin
                bus_fault_q <= 1'b1;
                // first fault since the last clear keeps its address / code
                if (!bus_fault_q || (accept && !access_error && w1c_fault)) begin
                    fault_addr_q <= fault_addr_i;
                    fault_code_q <= fault_code_i;
                end
            end
        end
    end

endmodule
