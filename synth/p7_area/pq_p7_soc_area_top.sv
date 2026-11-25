`timescale 1ns/1ps
//=============================================================================
// Module : pq_p7_soc_area_top   (SoC-profile accurate-area bitstream, Arty A7-100T; S4-SOC, docs/decisions/S4_AREA_CONTRACT.md)
// Purpose: a bitstream whose area is the real area of the P7 subsystem as a SoC integrates it: synth/p7_soc/pq_p7_soc_core.sv
//          (the unchanged pq_noc_subsystem_p7 with the observation-only exports unconnected). Every core input comes from a
//          run-time serial shift chain and every kept core output is folded into a 64-bit MISR (synth/n13/n13_observe.sv),
//          so nothing constant-folds and nothing kept is unobservable. Same board wrapper as pq_p7_area_top (full exports).
// Clock  : CLK100MHZ (E3) -> MMCME2_BASE (x10 / 20) -> 50 MHz (20 ns). Reset: btn[0] or MMCM not locked -> 2-FF sync.
// I/O    : sw[0] = sdi, sw[1] = shift enable (2-FF synchronised); led[0] = sdo (MISR), led[1] = MMCM locked.
// Not a demo (use pq_p7_board_top) and not evidence (the registered SoC-profile area is job s4_soc_pnr).
//=============================================================================
module pq_p7_soc_shell (input logic clk, rst, sdi, sen, output logic sdo);
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
  pq_p7_soc_core u_core(.clk, .rst, .start_attestation(p.start), .revoke(p.revoke), .trusted_clear(p.tclear),
    .boot_epoch(p.boot), .attest_epoch(p.attest), .nonce(p.nonce), .root_secret(p.root), .approved_measurement(p.appr),
    .directed_keys(p.keys), .context_in(p.ctx), .context_len(p.ctxlen), .config_data(p.cfg), .imem(p.imem),
    .config_len(p.cfglen), .imem_len(p.imemlen), .app_valid(p.av), .app_payload_valid(p.apv),
    .app_ready(o.app_ready), .app_payload_ready(o.app_payload_ready), .app_destination(p.ad), .app_message(p.am),
    .app_control(p.ac), .app_payload(p.ap), .spoof_raw_valid(p.sv), .spoof_raw_flit(p.sf), .spoof_raw_ready(o.spoof_ready),
    .authorized(o.authorized), .rot_busy(o.rot_busy), .grant_done(o.grant_done), .attestation_failed(o.failed),
    .memory_commits(o.commits), .app_tx_error(o.app_tx_error), .fault_sticky(o.fs), .fault_count(o.fc),
    .fault_source(o.fsrc), .fault_operation(o.fop), .fault_reason(o.frs), .fault_epoch(o.fep));
  n13_observe #(.W($bits(obs_t))) obs(.clk, .rst, .d(o), .sdo);
endmodule

module pq_p7_soc_area_top (
    input  logic       CLK100MHZ,
    input  logic [0:0] btn,
    input  logic [1:0] sw,
    output logic [1:0] led
);
    logic clk_fb, clk_fb_buf, clk50_mmcm, clk, locked;
    MMCME2_BASE #(.CLKIN1_PERIOD(10.0), .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(10.0), .CLKOUT0_DIVIDE_F(20.0)) u_mmcm (
        .CLKIN1(CLK100MHZ), .CLKFBIN(clk_fb_buf), .CLKFBOUT(clk_fb), .CLKFBOUTB(),
        .CLKOUT0(clk50_mmcm), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0));
    BUFG u_bufg_fb  (.I(clk_fb),     .O(clk_fb_buf));
    BUFG u_bufg_clk (.I(clk50_mmcm), .O(clk));

    logic [1:0] rst_s, sdi_s, sen_s;
    always_ff @(posedge clk or negedge locked)
        if (!locked) rst_s <= 2'b11;
        else         rst_s <= {rst_s[0], btn[0]};
    always_ff @(posedge clk) begin
        sdi_s <= {sdi_s[0], sw[0]};
        sen_s <= {sen_s[0], sw[1]};
    end
    pq_p7_soc_shell u_soc (.clk, .rst(rst_s[1]), .sdi(sdi_s[1]), .sen(sen_s[1]), .sdo(led[0]));
    assign led[1] = locked;
endmodule
