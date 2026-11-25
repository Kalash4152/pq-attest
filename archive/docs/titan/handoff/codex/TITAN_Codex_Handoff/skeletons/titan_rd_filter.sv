// SKELETON (UNCOMPILED). Stage S8. Zero-latency rewrite on the I-9 app_rx export (CPU tiles 0,3). H5.
module titan_rd_filter #(
  parameter int EPOCH_W = 6
)(
  input  logic               clk, rst,
  input  logic [2:0]         mode,
  input  logic               rx_head_v, rx_data_v, rx_last, rx_abort, // app_rx_* export; always accepted (rready=1)
  input  logic [3:0]         rx_msg,
  input  logic [10:0]        rx_ctl,
  input  logic [31:0]        rx_data,
  input  logic               own_auth,
  input  logic [EPOCH_W-1:0] own_epoch,
  output logic [10:0]        rx_ctl_o,
  output logic [31:0]        rx_data_o,
  output logic               filter_hit      // pulse at the HEAD when the rule fires (monitor)
);
  // TODO S8: latch decision at HEAD accept (D6), apply to all words of that response.
endmodule
