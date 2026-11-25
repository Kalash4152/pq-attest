`timescale 1ns / 1ps
// tb_bridge_decode_table (Lane 1, 2026-11-07; brief v2 A6 "every row of sec. 1.2, T = 0..15"): tmem_app_bridge at TILE_ID 3,
// MEM_TILE 2, authorized. One authorized read per target tile T = 0..15 at 0x2T00_0100, plus a wrong prefix and a misaligned
// address. Expected (contract sec. 1.2 / B1): only T = 2 reaches the network (app_valid, destination = tile 2); every other
// row is refused locally: tmem_err, last_err_kind = 1 (decode), app_valid never raised during the transaction.
// Checks (CHECKS = 18, frozen before the first run):
//   DT_T00 .. DT_T15   one per target tile (T = 2 forwarded and answered without error; all others refused, kind 1)
//   DT_PREFIX_NOT_2    0x3200_0100 (addr[31:28] != 2): refused, kind 1, no app_valid
//   DT_MISALIGNED      0x2200_0102 (addr[1:0] != 0): refused, kind 1, no app_valid
module tb_bridge_decode_table;
  import noc_pkg::*;
  logic clk = 0, rst = 1;
  always #10 clk = ~clk;
  logic tmem_req = 0, tmem_we = 0, tmem_is_fetch = 0; logic [31:0] tmem_addr = 0, tmem_wdata = 0; logic [3:0] tmem_wstrb = 0;
  logic tmem_gnt, tmem_rvalid, tmem_err; logic [31:0] tmem_rdata;
  logic av, apv, hv, dv, last; coord_t adst, rsrc; msg_type_e amsg, rmsg; logic [10:0] actl, rctl; logic [31:0] apay, rdat;
  logic [2:0] kind; logic [15:0] tmo_cnt, ref_cnt;
  int pkts; coord_t pd; msg_type_e pm; logic [10:0] pc; logic [31:0] pw0, pw1;

  tmem_app_bridge #(.TILE_ID(3), .MEM_TILE(2), .BRIDGE_TIMEOUT(4096), .NI_SLOT_TIMEOUT(8192), .LATE_DRAIN_CYCLES(8192)) dut (
    .clk, .rst, .tmem_req_i(tmem_req), .tmem_we_i(tmem_we), .tmem_addr_i(tmem_addr), .tmem_wdata_i(tmem_wdata),
    .tmem_wstrb_i(tmem_wstrb), .tmem_is_fetch_i(tmem_is_fetch), .tmem_gnt_o(tmem_gnt), .tmem_rvalid_o(tmem_rvalid),
    .tmem_rdata_o(tmem_rdata), .tmem_err_o(tmem_err), .authorized_i(1'b1),
    .app_valid_o(av), .app_ready_i(1'b1), .app_destination_o(adst), .app_message_o(amsg), .app_control_o(actl),
    .app_payload_o(apay), .app_payload_valid_o(apv), .app_payload_ready_i(1'b1), .app_tx_error_i(1'b0),
    .app_rx_head_valid_i(hv), .app_rx_src_i(rsrc), .app_rx_msg_i(rmsg), .app_rx_control_i(rctl), .app_rx_data_i(rdat),
    .app_rx_data_valid_i(dv), .app_rx_last_i(last), .app_rx_abort_i(1'b0),
    .last_err_kind_o(kind), .timeout_count_o(tmo_cnt), .refused_count_o(ref_cnt));
  ctn_responder #(.ERR(0)) rsp (.clk, .rst, .app_valid(av), .app_dest(adst), .app_msg(amsg), .app_ctl(actl), .app_payload(apay),
    .app_pvalid(apv), .rx_hv(hv), .rx_src(rsrc), .rx_msg(rmsg), .rx_ctl(rctl), .rx_data(rdat), .rx_dv(dv), .rx_last(last),
    .pkts(pkts), .p_dest(pd), .p_msg(pm), .p_ctl(pc), .p_w0(pw0), .p_w1(pw1));

  int av_cycles = 0; coord_t last_dest;
  always @(posedge clk) if (!rst && av) begin av_cycles++; last_dest = adst; end

  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++; if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  // one read; returns err, kind and how many app_valid cycles it caused
  task automatic rd(input logic [31:0] a, output bit err, output logic [2:0] k, output int avc);
    automatic int n = 0, a0 = av_cycles;
    // grant is combinational in IDLE: sample it mid-cycle, the request is accepted at the next edge, and a local refusal
    // answers in the very next cycle (driver fixed after the first scratch run, which sampled gnt after the edge and missed
    // the one-cycle error response; checks and count unchanged)
    @(negedge clk); tmem_req = 1; tmem_addr = a; tmem_we = 0; tmem_wstrb = 0;
    #1; while (!tmem_gnt && n < 100) begin @(negedge clk); #1; n++; end
    @(posedge clk); #1; tmem_req = 0; n = 0;
    while (!tmem_rvalid && n < 10000) begin @(posedge clk); #1; n++; end
    err = tmem_err; k = kind; avc = av_cycles - a0;
    repeat (4) @(negedge clk);
  endtask

  initial begin
    bit e; logic [2:0] k; int avc;
    $display("CONFIG: TOP=tb_bridge_decode_table CHECKS=18 TILE_ID=3 MEM_TILE=2");
    repeat (5) @(negedge clk); rst = 0; repeat (3) @(negedge clk);
    for (int t = 0; t < 16; t++) begin
      rd({4'h2, 4'(t), 24'h00_0100}, e, k, avc);
      if (t == 2) check(!e && avc > 0 && last_dest == tile_to_coord(TILE_MEMORY),
                        $sformatf("DT_T%02d forwarded err=%0b app_valid_cycles=%0d", t, e, avc));
      else        check(e && k == 3'd1 && avc == 0, $sformatf("DT_T%02d refused err=%0b kind=%0d app_valid_cycles=%0d", t, e, k, avc));
    end
    rd(32'h3200_0100, e, k, avc);
    check(e && k == 3'd1 && avc == 0, $sformatf("DT_PREFIX_NOT_2 err=%0b kind=%0d app_valid_cycles=%0d", e, k, avc));
    rd(32'h2200_0102, e, k, avc);
    check(e && k == 3'd1 && avc == 0, $sformatf("DT_MISALIGNED err=%0b kind=%0d app_valid_cycles=%0d", e, k, avc));
    $display("CHECKS : %0d", checks); $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 18 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #5ms; $display("TB_TIMEOUT"); $display("RESULT : FAIL"); $finish; end
endmodule
