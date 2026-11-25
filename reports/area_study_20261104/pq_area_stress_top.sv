`timescale 1ns/1ps
// N-13 real-pin top, SECURE profile (Kalash 2026-11-02: shift chain + MISR). Wraps the unchanged pq_noc_subsystem_p7.
// Every subsystem input comes from a run-time serial shift chain (sdi, sen), so nothing constant-folds; every output is
// XOR-folded into a 64-bit MISR whose top bit drives sdo, so nothing is unobservable. Five pins, one 20 ns clock.
// Not a board design (no MMCM, no secrets): an implementation-timing and area vehicle only.
module pq_area_stress_top (input logic clk, rst, sdi, sen, output logic sdo);
  import noc_pkg::*;
  typedef struct packed {
    logic start, revoke, tclear;
    logic [79:0] boot, attest;
    logic [127:0] nonce;
    logic [255:0] root, appr;
    logic [511:0] keys;
    logic [111:0] ctx;
    logic [3:0] ctxlen;
    logic [511:0] cfg, imem;
    logic [6:0] cfglen, imemlen;
    logic [5:0] av, apv;
    coord_t [5:0] ad;
    msg_type_e [5:0] am;
    logic [5:0][10:0] ac;
    logic [5:0][31:0] ap;
    logic sv;
    flit_t sf;
  } prov_t;
  typedef struct packed {
    logic [5:0] app_ready, app_payload_ready, authorized, app_tx_error;
    logic spoof_ready, rot_busy, grant_done, failed;
    logic [31:0] commits;
    logic fs; logic [31:0] fc; logic [2:0] fsrc; logic [3:0] fop, frs; logic [79:0] fep;
  } obs_t;
  logic [$bits(prov_t)-1:0] sr;
  prov_t p;
  obs_t o;
  always_ff @(posedge clk) if (sen) sr <= {sr[$bits(prov_t)-2:0], sdi};
  assign p = prov_t'(sr);
  // Phase 0: tiles 0 and 1 driven by CPU-sized placeholders instead of the shift chain
  logic [1:0] cv, cpv; coord_t [1:0] cd; msg_type_e [1:0] cm; logic [1:0][10:0] cc; logic [1:0][31:0] cpd;
  for (genvar k = 0; k < 2; k++) begin: CPU
    cpu_placeholder #(.SEED(32'h1234_5678 + k)) u (.clk, .rst, .app_ready(o.app_ready[k]), .app_payload_ready(o.app_payload_ready[k]),
      .app_tx_error(o.app_tx_error[k]), .app_valid(cv[k]), .app_payload_valid(cpv[k]), .app_destination(cd[k]),
      .app_message(cm[k]), .app_control(cc[k]), .app_payload(cpd[k]));
  end
  logic [5:0] av_x, apv_x; coord_t [5:0] ad_x; msg_type_e [5:0] am_x; logic [5:0][10:0] ac_x; logic [5:0][31:0] ap_x;
  assign av_x = {p.av[5:2], cv}; assign apv_x = {p.apv[5:2], cpv};
  assign ad_x = {p.ad[5:2], cd}; assign am_x = {p.am[5:2], cm}; assign ac_x = {p.ac[5:2], cc}; assign ap_x = {p.ap[5:2], cpd};
  pq_noc_subsystem_p7 dut(.clk, .rst, .start_attestation(p.start), .revoke(p.revoke), .trusted_clear(p.tclear),
    .boot_epoch(p.boot), .attest_epoch(p.attest), .nonce(p.nonce), .root_secret(p.root), .approved_measurement(p.appr),
    .directed_keys(p.keys), .context_in(p.ctx), .context_len(p.ctxlen), .config_data(p.cfg), .imem(p.imem),
    .config_len(p.cfglen), .imem_len(p.imemlen), .app_valid(av_x), .app_payload_valid(apv_x),
    .app_ready(o.app_ready), .app_payload_ready(o.app_payload_ready), .app_destination(ad_x), .app_message(am_x),
    .app_control(ac_x), .app_payload(ap_x), .spoof_raw_valid(p.sv), .spoof_raw_flit(p.sf), .spoof_raw_ready(o.spoof_ready),
    .authorized(o.authorized), .rot_busy(o.rot_busy), .grant_done(o.grant_done), .attestation_failed(o.failed),
    .memory_commits(o.commits), .app_tx_error(o.app_tx_error), .fault_sticky(o.fs), .fault_count(o.fc), .fault_source(o.fsrc), .fault_operation(o.fop),
    .fault_reason(o.frs), .fault_epoch(o.fep));
  n13_observe #(.W($bits(obs_t))) obs(.clk, .rst, .d(o), .sdo);
endmodule
