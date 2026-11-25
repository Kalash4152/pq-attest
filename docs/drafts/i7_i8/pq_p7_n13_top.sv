`timescale 1ns/1ps
// N-13 real-pin top, SECURE profile (Kalash 2026-11-02: shift chain + MISR). Wraps the unchanged pq_noc_subsystem_p7.
// Every subsystem input comes from a run-time serial shift chain (sdi, sen), so nothing constant-folds; every output is
// XOR-folded into a 64-bit MISR whose top bit drives sdo, so nothing is unobservable. Five pins, one 20 ns clock.
// Not a board design (no MMCM, no secrets): an implementation-timing and area vehicle only.
module pq_p7_n13_top (input logic clk, rst, sdi, sen, output logic sdo);
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
    logic [775:0] ep_resp;
    logic [31:0] commits, last_data;
    logic [5:0][31:0] l2r, l2a, gf, ir, ifc;
    logic [31:0] qr, qf, qd, mf;
    logic [3:0] qreason;
    logic [5:0][3:0] l2reason, ireason;
    logic [1:0][31:0] psd, pa, pr, prj;
    logic [1:0][15:0] phm;
    logic [31:0] epr, vr;
    logic fs; logic [31:0] fc; logic [2:0] fsrc; logic [3:0] fop, frs; logic [79:0] fep;
  } obs_t;
  logic [$bits(prov_t)-1:0] sr;
  prov_t p;
  obs_t o;
  always_ff @(posedge clk) if (sen) sr <= {sr[$bits(prov_t)-2:0], sdi};
  assign p = prov_t'(sr);
  pq_noc_subsystem_p7 dut(.clk, .rst, .start_attestation(p.start), .revoke(p.revoke), .trusted_clear(p.tclear),
    .boot_epoch(p.boot), .attest_epoch(p.attest), .nonce(p.nonce), .root_secret(p.root), .approved_measurement(p.appr),
    .directed_keys(p.keys), .context_in(p.ctx), .context_len(p.ctxlen), .config_data(p.cfg), .imem(p.imem),
    .config_len(p.cfglen), .imem_len(p.imemlen), .app_valid(p.av), .app_payload_valid(p.apv),
    .app_ready(o.app_ready), .app_payload_ready(o.app_payload_ready), .app_destination(p.ad), .app_message(p.am),
    .app_control(p.ac), .app_payload(p.ap), .spoof_raw_valid(p.sv), .spoof_raw_flit(p.sf), .spoof_raw_ready(o.spoof_ready),
    .authorized(o.authorized), .rot_busy(o.rot_busy), .grant_done(o.grant_done), .attestation_failed(o.failed),
    .endpoint_response(o.ep_resp), .memory_commits(o.commits), .memory_last_data(o.last_data),
    .l2_rejected(o.l2r), .l2_accepted(o.l2a), .gate_faults(o.gf), .ingress_rejected(o.ir), .ingress_fault(o.ifc),
    .q_rejected(o.qr), .q_forwarded(o.qf), .q_discarded(o.qd), .mem_faults(o.mf), .q_reason(o.qreason),
    .l2_reason(o.l2reason), .ingress_reason(o.ireason), .p_slot_drops(o.psd), .peer_accepted(o.pa), .peer_replayed(o.pr),
    .peer_rejected(o.prj), .peer_hold_max(o.phm), .app_tx_error(o.app_tx_error), .endpoint_rejected(o.epr),
    .verifier_rejected(o.vr), .fault_sticky(o.fs), .fault_count(o.fc), .fault_source(o.fsrc), .fault_operation(o.fop),
    .fault_reason(o.frs), .fault_epoch(o.fep));
  n13_observe #(.W($bits(obs_t))) obs(.clk, .rst, .d(o), .sdo);
endmodule

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
