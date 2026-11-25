// SKELETON (UNCOMPILED). Stage S2. Simulation checker; bound with titan_mon_bind.sv. H7.
// Must not drive any design signal.
module titan_finality_monitor #(
  parameter int N_TILES = 6,
  parameter int EPOCH_W = 6,
  parameter bit USE_SHADOW_EPOCH = 1   // B0: derive epochs from GRANT/REVOKE heads inside the monitor
)(
  input logic clk, rst,
  // per-tile NI send / receive handshakes (flatten as the subsystem exposes them)
  input logic [N_TILES-1:0]        snd_v, snd_rdy, snd_head,
  input logic [N_TILES-1:0][3:0]   snd_msg,
  input logic [N_TILES-1:0][10:0]  snd_ctl,
  input logic [N_TILES-1:0]        rcv_v, rcv_rdy, rcv_head,
  input logic [N_TILES-1:0][3:0]   rcv_msg,
  input logic [N_TILES-1:0][10:0]  rcv_ctl,
  // tile-2 front end
  input logic                      commit_v,
  input logic [2:0]                commit_src,
  input logic                      commit_tag,
  // authority
  input logic [N_TILES-1:0]        authorized,
  input logic [N_TILES-1:0][EPOCH_W-1:0] epoch,      // ignored when USE_SHADOW_EPOCH
  // bridge (CPU tiles)
  input logic [N_TILES-1:0]        bridge_timeout_v,
  input logic [N_TILES-1:0]        outcome_v,
  input logic [N_TILES-1:0][1:0]   outcome
);
  // TODO S2: transaction table keyed (src, tag); rules P1 P2 P3 P4 P6, SD, M3; end-of-sim TITAN_SUMMARY line.
endmodule
