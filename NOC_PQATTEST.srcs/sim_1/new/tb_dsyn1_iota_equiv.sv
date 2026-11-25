`timescale 1ns/1ps
// D-SYN-1 equivalence: rtl/dual_lane/pq_keccak_iota.sv (keccak_iota, assertion block under `ifndef SYNTHESIS)
// vs the protected original (TB-only renamed copy keccak_iota_orig_dsyn1). Both elaborate here (sim: SYNTHESIS
// undefined, so the variant keeps its assertion). Legal rounds 0..NUM_ROUNDS-1 x 64 random states; rounds >=
// NUM_ROUNDS are illegal by design and trip the original's own assertion, so they are not driven.
// CHECKS = 24 * 64 = 1536 (frozen before the first run).
module tb_dsyn1_iota_equiv;
  import keccak_pkg::*;
  localparam int NSTATE = 64;
  state_t s_in, s_var, s_orig;
  round_t rnd;
  int checks = 0, errors = 0, shown = 0;
  // Deterministic 32-bit LCG (portable; XSim rejects seeding the built-in generator this way).
  logic [31:0] lcg_state = 32'h107A_0001;
  function automatic logic [31:0] rnd32();
    lcg_state = lcg_state * 32'd1664525 + 32'd1013904223;
    return lcg_state;
  endfunction
  keccak_iota            u_var (.state_in(s_in), .round(rnd), .state_out(s_var));
  keccak_iota_orig_dsyn1 u_ref (.state_in(s_in), .round(rnd), .state_out(s_orig));
  initial begin
    rnd = '0; s_in = '{default: '0}; #1;
    $display("CONFIG: TOP=tb_dsyn1_iota_equiv NUM_ROUNDS=%0d STATES=%0d", NUM_ROUNDS, NSTATE);
    for (int k = 0; k < NSTATE; k++) begin
      for (int x = 0; x < STATE_DIM; x++) for (int y = 0; y < STATE_DIM; y++) s_in[x][y] = {rnd32(), rnd32()};
      for (int r = 0; r < NUM_ROUNDS; r++) begin
        rnd = round_t'(r); #1;
        checks++;
        if (s_var !== s_orig) begin
          errors++;
          if (shown < 10) begin shown++; $display("[FAIL] IOTA_EQUIV state=%0d round=%0d", k, r); end
        end
      end
    end
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
