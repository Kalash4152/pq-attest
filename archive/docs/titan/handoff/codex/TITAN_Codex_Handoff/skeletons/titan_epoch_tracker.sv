// SKELETON (UNCOMPILED). Stage S4. One per tile. H1 in 02_INTERFACES_v2.md.
module titan_epoch_tracker #(
  parameter int EPOCH_W = 6
)(
  input  logic               clk,
  input  logic               rst,            // synchronous, active high (matches subsystem rst_i)
  input  logic               auth_update_v,  // pulse: gate accepted an authenticated GRANT/REVOKE this cycle
  input  logic               auth_is_grant,  // informational (monitor); epoch bumps on both
  output logic [EPOCH_W-1:0] epoch_o,        // changes the cycle after auth_update_v (same as gate.authorized)
  output logic               epoch_wrap_o    // pulse when epoch_o goes 2^EPOCH_W-1 -> 0
);
  // TODO S4: implement; add elaboration check EPOCH_W in 1..6.
endmodule
