`timescale 1ns/1ps
// N-13 real-pin top, INSECURE profile (Kalash 2026-11-02: "Mesh + 6 plain NIs"): the same protected mesh and six plain
// P7 NIs (CONTROL_ALLOWED = 1, WD_LIMIT 64 as in the subsystem), with no L2, no attestation, no gates, no ingress checks.
// Same wrapper as the secure top (pq_p7_n13_top.sv): inputs from a run-time shift chain, outputs into the MISR.
module pq_p7_n13_insecure_top (input logic clk, rst, sdi, sen, output logic sdo);
  import noc_pkg::*;
  typedef struct packed {
    logic [5:0] tv, pv, rr;
    coord_t [5:0] dest;
    msg_type_e [5:0] msg;
    logic [5:0][10:0] ctl;
    logic [5:0][31:0] pd;
  } prov_t;
  typedef struct packed {
    logic [5:0] tr, pr, te, rhv, rpv, rpl, rab, rpe, sb, rb;
    coord_t [5:0] rs, rd;
    msg_type_e [5:0] rm;
    logic [5:0][10:0] rc;
    logic [5:0][4:0] rl;
    logic [5:0][31:0] rdat;
  } obs_t;
  logic [$bits(prov_t)-1:0] sr;
  prov_t p;
  obs_t o;
  always_ff @(posedge clk) if (sen) sr <= {sr[$bits(prov_t)-2:0], sdi};
  assign p = prov_t'(sr);
  logic rst_i;
  rst_bridge rstb(.clk, .rst_in(rst), .rst_out(rst_i));
  flit_t [5:0] tile_in, tile_out;
  logic [5:0] tiv, tir, tov, tor;
  noc_mesh_3x2 #(.LINK_PIPE(1'b1)) mesh(.clk, .rst(rst_i),
    .tile_in_flit(tile_in), .tile_in_valid(tiv), .tile_in_ready(tir),
    .tile_out_flit(tile_out), .tile_out_valid(tov), .tile_out_ready(tor));
  for (genvar g = 0; g < 6; g++) begin: N
    // scalar locals per port (the S1 NI-binding note in pq_noc_subsystem_p7.sv)
    logic s_tr, s_pr, s_te, s_txv, s_txr, s_rxv, s_rxr, s_rhv, s_rpv, s_rpl, s_rab, s_rpe, s_sb, s_rb;
    coord_t s_rs, s_rd; msg_type_e s_rm; logic [10:0] s_rc; logic [31:0] s_rdat; logic [4:0] s_rl;
    flit_t s_txf, s_rxf;
    assign tile_in[g] = s_txf; assign tiv[g] = s_txv; assign s_txr = tir[g];
    assign s_rxf = tile_out[g]; assign s_rxv = tov[g]; assign tor[g] = s_rxr;
    assign o.tr[g] = s_tr; assign o.pr[g] = s_pr; assign o.te[g] = s_te; assign o.rhv[g] = s_rhv; assign o.rpv[g] = s_rpv;
    assign o.rpl[g] = s_rpl; assign o.rab[g] = s_rab; assign o.rpe[g] = s_rpe; assign o.sb[g] = s_sb; assign o.rb[g] = s_rb;
    assign o.rs[g] = s_rs; assign o.rd[g] = s_rd; assign o.rm[g] = s_rm; assign o.rc[g] = s_rc; assign o.rl[g] = s_rl;
    assign o.rdat[g] = s_rdat;
    noc_network_interface_p7 #(.CONTROL_ALLOWED(1'b1), .LOCAL_TILE_ID(g), .WD_LIMIT(64)) ni(
      .clk, .rst(rst_i), .tx_valid(p.tv[g]), .tx_ready(s_tr), .tx_auth_preview(),
      .tx_dest_coord(p.dest[g]), .tx_msg_type(p.msg[g]), .tx_control(p.ctl[g]),
      .tx_payload_data(p.pd[g]), .tx_payload_valid(p.pv[g]), .tx_payload_ready(s_pr),
      .tx_mac_tag('0), .tx_error(s_te),
      .noc_tx_flit(s_txf), .noc_tx_valid(s_txv), .noc_tx_ready(s_txr),
      .noc_rx_flit(s_rxf), .noc_rx_valid(s_rxv), .noc_rx_ready(s_rxr),
      .rx_src_coord(s_rs), .rx_dest_coord(s_rd), .rx_msg_type(s_rm), .rx_control(s_rc), .rx_length(s_rl),
      .rx_head_valid(s_rhv), .rx_payload_data(s_rdat), .rx_payload_valid(s_rpv), .rx_payload_last(s_rpl),
      .rx_ready(p.rr[g]), .rx_abort(s_rab),
      .rx_mac_tag(), .rx_mac_valid(), .rx_protocol_error(s_rpe), .rx_length_error(),
      .ni_status_clr(1'b0), .ni_contain_sticky(), .ni_contain_cnt(), .ni_contain_info(),
      .ni_framing_sticky(), .ni_framing_cnt(), .tx_busy(s_sb), .rx_busy(s_rb));
  end
  n13_observe #(.W($bits(obs_t))) obs(.clk, .rst(rst_i), .d(o), .sdo);
endmodule
