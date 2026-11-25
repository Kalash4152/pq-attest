`timescale 1ns/1ps
// N-13 wrapper observer, shared by the secure and insecure tops (synth/n13).
// XOR-fold W bits into 64 and accumulate them in a 64-bit MISR (x^64 + x^63 + x^61 + x^60 + 1); sdo = MISR top bit.
module n13_observe #(parameter int W = 64) (input logic clk, rst, input logic [W-1:0] d, output logic sdo);
  logic [63:0] fold, misr;
  always_comb begin
    fold = '0;
    for (int i = 0; i < W; i++) fold[i % 64] ^= d[i];
  end
  always_ff @(posedge clk)
    if (rst) misr <= '0;
    else misr <= {misr[62:0], misr[63] ^ misr[62] ^ misr[60] ^ misr[59]} ^ fold;
  assign sdo = misr[63];
endmodule
