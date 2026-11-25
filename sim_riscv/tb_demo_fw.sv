`timescale 1ns / 1ps
// tb_demo_fw (Lane 1, 2026-11-07, takeover plan R3.2): the board demo firmware sw/riscv/demo_fw.S (assembled by
// scripts/rv32_asm.py, included as sim_riscv/include/demo_fw.svh) on two real cpu_tile_noc instances.
//   u3: TILE_ID 3, authorized_i rises at cycle AUTH_AT; the app port is answered by a tile-2 memory model.
//   u0: TILE_ID 0, never authorized.
// UART is decoded at 115,200 baud (434 clocks / bit at 50 MHz).
// Checks (CHECKS = 9, frozen before the first run):
//   FW_T3_WAITS_AUTH     no app_valid from tile 3 before authorized_i rises
//   FW_T3_PACKETS        tile 3 sends exactly WR_REQ {0x2200_0100, 0xC0DE5A5A} then RD_REQ {0x2200_0100}
//   FW_T3_UART           tile 3 prints exactly "T3 PASS\n"
//   FW_T3_LED            tile 3 LEDs = 4'b0001
//   FW_T0_NO_APP_VALID   tile 0 never raises app_valid
//   FW_T0_UART           tile 0 prints exactly "T0 REFUSED\n"
//   FW_T0_LED            tile 0 LEDs = 4'b0010
//   FW_T0_FAULT_CODE     tile 0 STATUS: BUS_FAULT set, FAULT_CODE 2 (refused), FAULT_ADDR 0x2200_0100
//   FW_MEAS_BOOT_STUB    tile 3 meas_imem_o = the first 16 firmware words (the fixed boot stub), meas_valid_o = 1
module tb_demo_fw;
  import noc_pkg::*;
  logic clk = 0, rst = 1;
  always #10 clk = ~clk;
  `include "demo_fw.svh"
  localparam int AUTH_AT = 5000;
  localparam int BIT_CLKS = 50_000_000 / 115200;

  logic        av [2], apv [2], hv [2], dv [2], last [2], areq [2], mvalid [2], utx [2], auth [2];
  coord_t      adst [2], rsrc [2];
  msg_type_e   amsg [2], rmsg [2];
  logic [10:0] actl [2], rctl [2];
  logic [31:0] apay [2], rdat [2];
  logic [511:0] meas [2]; logic [6:0] mlen [2]; logic [7:0] gpio [2];
  int pkts [2]; coord_t pd [2]; msg_type_e pm [2]; logic [10:0] pc [2]; logic [31:0] pw0 [2], pw1 [2];
  localparam int TID [2] = '{3, 0};

  for (genvar g = 0; g < 2; g++) begin : gi
    cpu_tile_noc #(.TILE_ID(TID[g]), .MEM_TILE(2), .BRIDGE_TIMEOUT(4096), .NI_SLOT_TIMEOUT(8192), .BUILD_ID(32'h2026_1107)) dut (
      .clk, .rst,
      .app_valid_o(av[g]), .app_ready_i(1'b1), .app_destination_o(adst[g]), .app_message_o(amsg[g]), .app_control_o(actl[g]),
      .app_payload_o(apay[g]), .app_payload_valid_o(apv[g]), .app_payload_ready_i(1'b1), .app_tx_error_i(1'b0),
      .app_rx_head_valid_i(hv[g]), .app_rx_src_i(rsrc[g]), .app_rx_msg_i(rmsg[g]), .app_rx_control_i(rctl[g]),
      .app_rx_data_i(rdat[g]), .app_rx_data_valid_i(dv[g]), .app_rx_last_i(last[g]), .app_rx_abort_i(1'b0),
      .authorized_i(auth[g]), .grant_done_i(1'b0), .attest_failed_i(1'b0),
      .attest_req_o(areq[g]), .meas_imem_o(meas[g]), .meas_imem_len_o(mlen[g]), .meas_valid_o(mvalid[g]),
      .uart_tx_o(utx[g]), .gpio_o(gpio[g]));
    ctn_responder #(.ERR(0)) rsp (
      .clk, .rst, .app_valid(av[g]), .app_dest(adst[g]), .app_msg(amsg[g]), .app_ctl(actl[g]), .app_payload(apay[g]),
      .app_pvalid(apv[g]), .rx_hv(hv[g]), .rx_src(rsrc[g]), .rx_msg(rmsg[g]), .rx_ctl(rctl[g]), .rx_data(rdat[g]),
      .rx_dv(dv[g]), .rx_last(last[g]), .pkts(pkts[g]), .p_dest(pd[g]), .p_msg(pm[g]), .p_ctl(pc[g]), .p_w0(pw0[g]), .p_w1(pw1[g]));
  end

  initial for (int k = 0; k < DEMO_FW_N; k++) begin
    gi[0].dut.u_mem.imem_inst.mem[k] = DEMO_FW[k]; gi[1].dut.u_mem.imem_inst.mem[k] = DEMO_FW[k];
  end

  // second packet capture for tile 3 (the responder keeps the first)
  msg_type_e pm2; logic [31:0] pw0_2;
  int cyc = 0, early_valid = 0, t0_valid = 0;
  always @(posedge clk) if (!rst) begin
    cyc++;
    if (av[0] && !auth[0]) early_valid++;
    if (av[1]) t0_valid++;
  end
  initial begin auth[0] = 0; auth[1] = 0; wait (!rst); repeat (AUTH_AT) @(posedge clk); auth[0] = 1; end
  initial begin
    wait (pkts[0] == 1); @(posedge clk iff av[0]); pm2 = amsg[0];
    @(posedge clk iff apv[0]); pw0_2 = apay[0];
  end

  // UART receivers (bytes into fixed arrays; no dynamic strings in the receive path)
  logic [7:0] rxb [2][0:31]; int rxn [2] = '{0, 0};
  for (genvar g = 0; g < 2; g++) begin : ur
    initial begin
      wait (!rst);
      forever begin
        logic [7:0] ch;
        @(negedge utx[g]);
        repeat (BIT_CLKS + BIT_CLKS / 2) @(posedge clk);
        for (int b = 0; b < 8; b++) begin ch[b] = utx[g]; repeat (BIT_CLKS) @(posedge clk); end
        if (rxn[g] < 32) rxb[g][rxn[g]] = ch;
        rxn[g]++;
      end
    end
  end
  function automatic bit rx_is(input int g, input string exp);
    if (rxn[g] != exp.len()) return 0;
    for (int i = 0; i < exp.len(); i++) if (rxb[g][i] !== exp.getc(i)) return 0;
    return 1;
  endfunction
  function automatic string rx_hex(input int g);
    string o = ""; for (int i = 0; i < rxn[g] && i < 32; i++) o = {o, $sformatf("%02h", rxb[g][i])}; return o;
  endfunction

  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++; if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask

  initial begin
    bit stub_ok;
    $display("CONFIG: TOP=tb_demo_fw CHECKS=9 FW=demo_fw AUTH_AT=%0d", AUTH_AT);
    repeat (5) @(negedge clk); rst = 0;
    // wait until both lines are complete (bounded)
    for (int w = 0; w < 400; w++) begin
      repeat (1000) @(posedge clk);
      if (rx_is(0, "T3 PASS\n") && rx_is(1, "T0 REFUSED\n")) break;
      if (rxn[0] > 12 || rxn[1] > 12) break;
    end
    repeat (BIT_CLKS * 12) @(posedge clk);
    stub_ok = mvalid[0]; for (int k = 0; k < 16; k++) if (meas[0][32*k +: 32] != DEMO_FW[k]) stub_ok = 0;
    check(early_valid == 0 && pkts[0] > 0, $sformatf("FW_T3_WAITS_AUTH early_valid=%0d", early_valid));
    check(pkts[0] == 2 && pm[0] == MSG_MEM_WR_REQ && pw0[0] == 32'h2200_0100 && pw1[0] == 32'hC0DE_5A5A &&
          pm2 == MSG_MEM_RD_REQ && pw0_2 == 32'h2200_0100,
          $sformatf("FW_T3_PACKETS pkts=%0d first=%0d %h %h second=%0d %h", pkts[0], pm[0], pw0[0], pw1[0], pm2, pw0_2));
    check(rx_is(0, "T3 PASS\n"), $sformatf("FW_T3_UART n=%0d hex=%s", rxn[0], rx_hex(0)));
    check(gpio[0][3:0] == 4'b0001, $sformatf("FW_T3_LED %b", gpio[0][3:0]));
    check(t0_valid == 0 && pkts[1] == 0, $sformatf("FW_T0_NO_APP_VALID cycles=%0d pkts=%0d", t0_valid, pkts[1]));
    check(rx_is(1, "T0 REFUSED\n"), $sformatf("FW_T0_UART n=%0d hex=%s", rxn[1], rx_hex(1)));
    check(gpio[1][3:0] == 4'b0010, $sformatf("FW_T0_LED %b", gpio[1][3:0]));
    check(gi[1].dut.u_tile.tile_status_inst.bus_fault_q && gi[1].dut.u_tile.tile_status_inst.fault_code_q == 4'd2 &&
          gi[1].dut.u_tile.tile_status_inst.fault_addr_q == 32'h2200_0100,
          $sformatf("FW_T0_FAULT_CODE code=%0d addr=%h", gi[1].dut.u_tile.tile_status_inst.fault_code_q,
                    gi[1].dut.u_tile.tile_status_inst.fault_addr_q));
    check(stub_ok, $sformatf("FW_MEAS_BOOT_STUB valid=%0b w0=%h", mvalid[0], meas[0][31:0]));
    $display("CHECKS : %0d", checks); $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 9 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #20ms; $display("TB_TIMEOUT"); $display("RESULT : FAIL"); $finish; end
endmodule
