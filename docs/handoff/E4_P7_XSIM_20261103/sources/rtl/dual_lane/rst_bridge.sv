`timescale 1ns/1ps
// Reset bridge (contract sec. 5): asynchronous assert, two-flop synchronous deassert. One instance in the P7 subsystem
// feeds every block, including the async-reset kmac children (pq_kdf_xk, rst_n = !rst).
module rst_bridge (
  input  logic clk,
  input  logic rst_in,
  output logic rst_out
);
  logic r0, r1;
  always_ff @(posedge clk or posedge rst_in) begin
    if (rst_in) begin r0 <= 1'b1; r1 <= 1'b1; end
    else begin r0 <= 1'b0; r1 <= r0; end
  end
  assign rst_out = r1;
endmodule
