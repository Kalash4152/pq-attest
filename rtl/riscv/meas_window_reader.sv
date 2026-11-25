`timescale 1ns / 1ps
//=============================================================================
// meas_window_reader  --  IMEM measurement window for the attestation endpoint (brief v2 B3)
//
// On start_i (attest_req / meas_start, one-cycle pulse) reads 16 consecutive 32-bit IMEM words, starting at byte
// address MEAS_BASE, through a DEDICATED read port (tile_mem_wrapper meas_rd_*: rd_en + byte address, data registered
// one cycle later), and assembles the endpoint's measurement input:
//   meas_imem_o[i*8 +: 8] = IMEM byte (MEAS_BASE + i), i = 0..63   (pq_measurement port convention)
//   => little-endian word k sits at meas_imem_o[32k +: 32]
//   meas_imem_len_o = 64
// meas_valid_o rises when all 16 words are loaded and stays high, with the window frozen, until the next start_i.
// A start_i while busy restarts from word 0 (the in-flight read's data is ignored). The port is separate from the
// CPU's IMEM port, so the CPU is never stalled.
//=============================================================================
module meas_window_reader #(
    parameter logic [31:0] MEAS_BASE = 32'h0000_0000      // byte address, word-aligned
)(
    input  logic         clk,
    input  logic         rst,                // synchronous, active high
    input  logic         start_i,
    // dedicated IMEM read port (tile_mem_wrapper meas_rd_en_i / meas_rd_addr_i / meas_rd_data_o)
    output logic         meas_rd_en_o,
    output logic [31:0]  meas_rd_addr_o,
    input  logic [31:0]  meas_rd_data_i,
    // to the attestation endpoint
    output logic [511:0] meas_imem_o,
    output logic [6:0]   meas_imem_len_o,
    output logic         meas_valid_o,
    output logic         busy_o
);
    logic [4:0] issue_q;      // next word to read (0..16)
    logic       pend_q;       // a read was issued last cycle: its data is on meas_rd_data_i now
    logic [3:0] pend_idx_q;

    assign meas_imem_len_o = 7'd64;
    assign meas_rd_en_o    = busy_o && !issue_q[4];
    assign meas_rd_addr_o  = MEAS_BASE + {25'd0, issue_q[3:0], 2'b00};

    always_ff @(posedge clk) begin
        if (rst) begin
            issue_q <= '0; pend_q <= 1'b0; pend_idx_q <= '0; busy_o <= 1'b0; meas_valid_o <= 1'b0; meas_imem_o <= '0;
        end else if (start_i) begin
            issue_q <= '0; pend_q <= 1'b0; busy_o <= 1'b1; meas_valid_o <= 1'b0;
        end else begin
            pend_q     <= meas_rd_en_o;
            pend_idx_q <= issue_q[3:0];
            if (meas_rd_en_o) issue_q <= issue_q + 1'b1;
            if (pend_q) begin
                meas_imem_o[pend_idx_q*32 +: 32] <= meas_rd_data_i;
                if (pend_idx_q == 4'd15) begin busy_o <= 1'b0; meas_valid_o <= 1'b1; end
            end
        end
    end
endmodule
