`timescale 1ns / 1ps
// tb_cpu_tile_noc (Lane 1, 2026-11-06, brief v2 B2): three cpu_tile_noc instances run the same hand-encoded program
//   0x00 lui  x1,0x22000 / addi x1,x1,0x100      x1 = 0x2200_0100 (tile 2 window)
//   0x08 addi x5,x0,0x5A / sw x5,0(x1)           remote write
//   0x10 lw   x2,0(x1)                           remote read
//   0x14 lui  x3,0x4 / sw x2,0(x3)               DMEM[0] = x2
//   0x1C j .                                     (then 8 NOPs; the image is 16 words = the measurement window)
// The program is preloaded into IMEM by the bench (no init file). Real firmware is R-3.
//   u_a: authorized_i = 0          -> bridge refuses locally (kind 2): no app_valid, x2 = 0xBADB_E002, STATUS code 2
//   u_b: authorized_i = 1, OK      -> WR_REQ packet {0x2200_0100, 0x5A}, read returns 0x5A, no fault
//   u_c: authorized_i = 1, err resp-> remote error (kind 3): x2 = 0xBADB_E003, STATUS code 3
// Checks (CHECKS = 12, frozen before the first run):
//   CTN_MEAS_AFTER_RESET    meas_valid_o rises within 100 cycles of reset release with no ATTEST_REQ
//   CTN_MEAS_IMAGE          meas_imem_o word k = IMEM word k (k = 0..15), word k at [32k +: 32]
//   CTN_MEAS_LEN            meas_imem_len_o = 64
//   CTN_GPIO_UPPER_ZERO     gpio_o[7:4] = 0 in every cycle (all instances)
//   CTN_UNAUTH_NO_APP_VALID u_a never raises app_valid_o
//   CTN_UNAUTH_POISON       u_a DMEM[0] = 0xBADB_E002
//   CTN_UNAUTH_STATUS       u_a STATUS: BUS_FAULT, FAULT_CODE 2, FAULT_ADDR 0x2200_0100 (first fault kept)
//   CTN_AUTH_WRITE_PACKET   u_b first packet: dest tile 2, MSG_MEM_WR_REQ, control {F,6'b0,0}, words 0x2200_0100, 0x5A
//   CTN_AUTH_READ_BACK      u_b DMEM[0] = 0x5A and no BUS_FAULT
//   CTN_REMOTE_ERR_POISON   u_c DMEM[0] = 0xBADB_E003
//   CTN_REMOTE_ERR_STATUS   u_c STATUS: BUS_FAULT, FAULT_CODE 3
//   CTN_ERRKIND_ALIGNED     in every cycle with bridge tmem_err_o = 1, last_err_kind != 0 (and >= 2 such cycles seen)

// app-port responder: ready always, collects the payload, answers after 3 cycles; ERR = 1 answers control[10] = 1
module ctn_responder #(parameter bit ERR = 0)(
  input logic clk, rst,
  input logic app_valid, input noc_pkg::coord_t app_dest, input noc_pkg::msg_type_e app_msg, input logic [10:0] app_ctl,
  input logic [31:0] app_payload, input logic app_pvalid,
  output logic rx_hv, output noc_pkg::coord_t rx_src, output noc_pkg::msg_type_e rx_msg, output logic [10:0] rx_ctl,
  output logic [31:0] rx_data, output logic rx_dv, output logic rx_last,
  output int pkts, output noc_pkg::coord_t p_dest, output noc_pkg::msg_type_e p_msg, output logic [10:0] p_ctl,
  output logic [31:0] p_w0, p_w1);
  import noc_pkg::*;
  logic [31:0] mem [0:4095];
  initial begin rx_hv = 0; rx_dv = 0; rx_last = 0; rx_data = 0; rx_ctl = 0; rx_src = '0; rx_msg = MSG_MEM_RD_RESP; pkts = 0; end
  initial forever begin
    @(posedge clk);
    if (!rst && app_valid) begin
      automatic msg_type_e m = app_msg; automatic logic [10:0] c = app_ctl; automatic coord_t d = app_dest;
      automatic int need = (m == MSG_MEM_WR_REQ) ? 2 : 1, got = 0; automatic logic [31:0] w [2];
      while (got < need) begin @(posedge clk); if (app_pvalid) begin w[got] = app_payload; got++; end end
      if (pkts == 0) begin p_dest = d; p_msg = m; p_ctl = c; p_w0 = w[0]; p_w1 = (need == 2) ? w[1] : 32'h0; end
      pkts++;
      if (m == MSG_MEM_WR_REQ && !ERR) mem[w[0][13:2]] = w[1];
      repeat (3) @(negedge clk);
      rx_hv = 1; rx_src = tile_to_coord(TILE_MEMORY); rx_msg = (m == MSG_MEM_RD_REQ) ? MSG_MEM_RD_RESP : MSG_MEM_WR_RESP;
      rx_ctl = ERR ? 11'h400 : 11'h000;
      @(negedge clk); rx_hv = 0;
      if (m == MSG_MEM_RD_REQ && !ERR) begin rx_dv = 1; rx_data = mem[w[0][13:2]]; @(negedge clk); rx_dv = 0; end
      rx_last = 1; @(negedge clk); rx_last = 0;
    end
  end
endmodule

module tb_cpu_tile_noc;
  import noc_pkg::*;
  logic clk = 0, rst = 1;
  always #10 clk = ~clk;
  localparam logic [31:0] PROG [0:15] = '{32'h220000B7, 32'h10008093, 32'h05A00293, 32'h0050A023, 32'h0000A103,
      32'h000041B7, 32'h0021A023, 32'h0000006F, 32'h00000013, 32'h00000013, 32'h00000013, 32'h00000013,
      32'h00000013, 32'h00000013, 32'h00000013, 32'h00000013};

  // per-instance wires: index 0 = u_a, 1 = u_b, 2 = u_c
  logic        av [3], apv [3], hv [3], dv [3], last [3], areq [3], mvalid [3], utx [3];
  coord_t      adst [3], rsrc [3];
  msg_type_e   amsg [3], rmsg [3];
  logic [10:0] actl [3], rctl [3];
  logic [31:0] apay [3], rdat [3];
  logic [511:0] meas [3]; logic [6:0] mlen [3]; logic [7:0] gpio [3];
  int pkts [3]; coord_t pd [3]; msg_type_e pm [3]; logic [10:0] pc [3]; logic [31:0] pw0 [3], pw1 [3];
  localparam bit AUTH [3] = '{1'b0, 1'b1, 1'b1};

  for (genvar g = 0; g < 3; g++) begin : gi
    cpu_tile_noc #(.TILE_ID(3), .MEM_TILE(2), .BRIDGE_TIMEOUT(4096), .NI_SLOT_TIMEOUT(8192)) dut (
      .clk, .rst,
      .app_valid_o(av[g]), .app_ready_i(1'b1), .app_destination_o(adst[g]), .app_message_o(amsg[g]), .app_control_o(actl[g]),
      .app_payload_o(apay[g]), .app_payload_valid_o(apv[g]), .app_payload_ready_i(1'b1), .app_tx_error_i(1'b0),
      .app_rx_head_valid_i(hv[g]), .app_rx_src_i(rsrc[g]), .app_rx_msg_i(rmsg[g]), .app_rx_control_i(rctl[g]),
      .app_rx_data_i(rdat[g]), .app_rx_data_valid_i(dv[g]), .app_rx_last_i(last[g]), .app_rx_abort_i(1'b0),
      .authorized_i(AUTH[g]), .grant_done_i(1'b0), .attest_failed_i(1'b0),
      .attest_req_o(areq[g]), .meas_imem_o(meas[g]), .meas_imem_len_o(mlen[g]), .meas_valid_o(mvalid[g]),
      .uart_tx_o(utx[g]), .gpio_o(gpio[g]));
    ctn_responder #(.ERR(g == 2)) rsp (
      .clk, .rst, .app_valid(av[g]), .app_dest(adst[g]), .app_msg(amsg[g]), .app_ctl(actl[g]), .app_payload(apay[g]),
      .app_pvalid(apv[g]), .rx_hv(hv[g]), .rx_src(rsrc[g]), .rx_msg(rmsg[g]), .rx_ctl(rctl[g]), .rx_data(rdat[g]),
      .rx_dv(dv[g]), .rx_last(last[g]), .pkts(pkts[g]), .p_dest(pd[g]), .p_msg(pm[g]), .p_ctl(pc[g]), .p_w0(pw0[g]), .p_w1(pw1[g]));
  end

  // preload IMEM (time 0; the CPU runs only after reset)
  initial for (int k = 0; k < 16; k++) begin
    gi[0].dut.u_mem.imem_inst.mem[k] = PROG[k]; gi[1].dut.u_mem.imem_inst.mem[k] = PROG[k];
    gi[2].dut.u_mem.imem_inst.mem[k] = PROG[k];
  end

  // monitors
  int gpio_bad = 0, av_unauth = 0, err_cycles = 0, err_kind0 = 0, cyc = 0, meas_cyc = -1;
  logic e0, e1, e2; logic [2:0] k0, k1, k2;
  assign e0 = gi[0].dut.u_bridge.tmem_err_o; assign k0 = gi[0].dut.last_err_kind;
  assign e1 = gi[1].dut.u_bridge.tmem_err_o; assign k1 = gi[1].dut.last_err_kind;
  assign e2 = gi[2].dut.u_bridge.tmem_err_o; assign k2 = gi[2].dut.last_err_kind;
  always @(posedge clk) if (!rst) begin
    cyc++;
    if (gpio[0][7:4] != 0 || gpio[1][7:4] != 0 || gpio[2][7:4] != 0) gpio_bad++;
    if (av[0]) av_unauth++;
    if (e0) begin err_cycles++; if (k0 == 0) err_kind0++; end
    if (e1) begin err_cycles++; if (k1 == 0) err_kind0++; end
    if (e2) begin err_cycles++; if (k2 == 0) err_kind0++; end
    if (mvalid[0] && meas_cyc < 0) meas_cyc = cyc;
  end

  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++; if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask

  initial begin
    bit img_ok; logic [31:0] d0 [3];
    $display("CONFIG: TOP=tb_cpu_tile_noc CHECKS=12");
    repeat (5) @(negedge clk); rst = 0;
    repeat (3000) @(negedge clk);
    img_ok = 1; for (int k = 0; k < 16; k++) if (meas[0][32*k +: 32] != PROG[k]) img_ok = 0;
    for (int g = 0; g < 3; g++) d0[g] = '0;
    d0[0] = gi[0].dut.u_mem.dmem_inst.mem[0]; d0[1] = gi[1].dut.u_mem.dmem_inst.mem[0]; d0[2] = gi[2].dut.u_mem.dmem_inst.mem[0];
    check(meas_cyc > 0 && meas_cyc <= 100 && !areq[0], $sformatf("CTN_MEAS_AFTER_RESET cycle=%0d", meas_cyc));
    check(img_ok, $sformatf("CTN_MEAS_IMAGE w0=%h w15=%h", meas[0][31:0], meas[0][511:480]));
    check(mlen[0] == 7'd64, $sformatf("CTN_MEAS_LEN len=%0d", mlen[0]));
    check(gpio_bad == 0, $sformatf("CTN_GPIO_UPPER_ZERO bad=%0d", gpio_bad));
    check(av_unauth == 0 && pkts[0] == 0, $sformatf("CTN_UNAUTH_NO_APP_VALID valid_cycles=%0d pkts=%0d", av_unauth, pkts[0]));
    check(d0[0] == 32'hBADB_E002, $sformatf("CTN_UNAUTH_POISON dmem0=%h", d0[0]));
    check(gi[0].dut.u_tile.tile_status_inst.bus_fault_q && gi[0].dut.u_tile.tile_status_inst.fault_code_q == 4'd2 &&
          gi[0].dut.u_tile.tile_status_inst.fault_addr_q == 32'h2200_0100,
          $sformatf("CTN_UNAUTH_STATUS fault=%0b code=%0d addr=%h", gi[0].dut.u_tile.tile_status_inst.bus_fault_q,
                    gi[0].dut.u_tile.tile_status_inst.fault_code_q, gi[0].dut.u_tile.tile_status_inst.fault_addr_q));
    check(pkts[1] == 2 && pd[1] == tile_to_coord(TILE_MEMORY) && pm[1] == MSG_MEM_WR_REQ && pc[1] == {4'hF, 6'b0, 1'b0} &&
          pw0[1] == 32'h2200_0100 && pw1[1] == 32'h0000_005A,
          $sformatf("CTN_AUTH_WRITE_PACKET pkts=%0d msg=%0d ctl=%h w0=%h w1=%h", pkts[1], pm[1], pc[1], pw0[1], pw1[1]));
    check(d0[1] == 32'h0000_005A && !gi[1].dut.u_tile.tile_status_inst.bus_fault_q,
          $sformatf("CTN_AUTH_READ_BACK dmem0=%h fault=%0b", d0[1], gi[1].dut.u_tile.tile_status_inst.bus_fault_q));
    check(d0[2] == 32'hBADB_E003, $sformatf("CTN_REMOTE_ERR_POISON dmem0=%h", d0[2]));
    check(gi[2].dut.u_tile.tile_status_inst.bus_fault_q && gi[2].dut.u_tile.tile_status_inst.fault_code_q == 4'd3,
          $sformatf("CTN_REMOTE_ERR_STATUS fault=%0b code=%0d", gi[2].dut.u_tile.tile_status_inst.bus_fault_q,
                    gi[2].dut.u_tile.tile_status_inst.fault_code_q));
    check(err_kind0 == 0 && err_cycles >= 2, $sformatf("CTN_ERRKIND_ALIGNED err_cycles=%0d kind0=%0d", err_cycles, err_kind0));
    $display("CHECKS : %0d", checks); $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 12 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #2ms; $display("TB_TIMEOUT"); $display("RESULT : FAIL"); $finish; end
endmodule
