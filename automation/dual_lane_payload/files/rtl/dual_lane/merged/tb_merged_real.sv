`timescale 1ns/1ps
// tb_merged_real (Lane 1, 2026-11-07; brief v2 B6 co-simulation): pq_soc_merged_core with the REAL cpu_tile_noc at tiles 3 and 0
// (compile with -d CPU_TILE_MODULE=cpu_tile_noc -d PQ_MAC_ON), both running the board demo firmware sw/riscv/demo_fw.S
// (sim_riscv/include/demo_fw.svh, preloaded into each tile's IMEM at time 0).
// Provisioning: vectors/d2_k3_64.svh row 0 (same TILE / EPOCH / CONTEXT / NONCE / ROOT / CONFIG as scripts/merged_provision.py)
// with the approved measurement and expected response of the firmware's 64-byte boot stub, from
//   python scripts/merged_provision.py --words sw/riscv/demo_fw.hex
// Checks (CHECKS = 10, frozen before the first run):
//   MR_MEAS_IMAGE     CPU A's meas_imem_o = the firmware's first 16 words, meas_valid before the RoT start
//   MR_RESPONSE       endpoint_response == the provisioned expected response (real measured window)
//   MR_GRANT          tile 3 authorized after the RoT start
//   MR_T3_UART        CPU A prints exactly "T3 PASS\n"
//   MR_T3_LED         CPU A LEDs = 0001
//   MR_BRAM           tile-2 BRAM word at 0x100 = 0xC0DE5A5A (CPU A's write through the NoC)
//   MR_COMMITS        memory_commits == 1 (exactly CPU A's one write)
//   MR_T0_UART        CPU B prints exactly "T0 REFUSED\n"
//   MR_T0_ISOLATED    tile 0 never authorized, gate_faults[0] == 0 (the bridge never raised app_valid), CPU B LEDs = 0010
//   MR_REVOKE         after REVOKE tile 3 is not authorized and no further commit happens
module tb_merged_real;
  import noc_pkg::*;
  logic clk = 0, rst = 1, start_attestation = 0, revoke = 0;
  always #10 clk = ~clk;
  logic [79:0] boot_epoch, attest_epoch; logic [127:0] nonce; logic [255:0] root_secret, approved_measurement;
  logic [111:0] context_in; logic [3:0] context_len; logic [511:0] config_data, imem; logic [6:0] config_len, imem_len;
  logic [775:0] expected_response, endpoint_response;
  logic [5:0] authorized; logic rot_busy, grant_done, attestation_failed, fault_sticky; logic [3:0] fault_reason;
  logic [31:0] memory_commits; logic [5:0][31:0] gate_faults; logic [1:0] uart; logic [1:0][7:0] gpio;
  `include "full_chain.svh"
  `include "d2_k3_64.svh"
  `include "demo_fw.svh"
  // python scripts/merged_provision.py --words sw/riscv/demo_fw.hex (2026-11-07)
  localparam logic [255:0] FW_APPROVED_MEAS = 256'h9ef8549424ebdaca3d4b8c193d49c67d9f095abca8ec6abeb186095d4a399a89;
  localparam logic [775:0] FW_EXPECTED_RESPONSE = 776'hcd746c32ab3de6017a852e86e6b98bd33d19bd3bb8734e484d7d2c633b23bdca9ef8549424ebdaca3d4b8c193d49c67d9f095abca8ec6abeb186095d4a399a890f0e0d0c0b0a09080706050403020100313030305f48434f504533305f454c4954;
  localparam int BIT_CLKS = 50_000_000 / 115200;

  pq_soc_merged_core #(.VERIFIER_TIMEOUT(20000)) dut(
    .clk, .rst, .start_attestation, .revoke, .trusted_clear(1'b0), .boot_epoch, .attest_epoch, .nonce, .root_secret,
    .approved_measurement, .directed_keys({KEYS[(3*6+4)*256 +: 256], KEYS[(4*6+3)*256 +: 256]}),
    .context_in, .context_len, .config_data, .authorized, .rot_busy, .grant_done, .attestation_failed, .memory_commits,
    .gate_faults, .fault_sticky, .fault_reason, .endpoint_response, .cpu_uart_tx(uart), .cpu_gpio(gpio));

  initial for (int k = 0; k < DEMO_FW_N; k++) begin
    dut.u_cpu_a.u_mem.imem_inst.mem[k] = DEMO_FW[k]; dut.u_cpu_b.u_mem.imem_inst.mem[k] = DEMO_FW[k];
  end

  logic [7:0] rxb [2][0:31]; int rxn [2] = '{0, 0};
  for (genvar g = 0; g < 2; g++) begin : ur
    initial begin
      wait (!rst);
      forever begin
        logic [7:0] ch;
        @(negedge uart[g]);
        repeat (BIT_CLKS + BIT_CLKS / 2) @(posedge clk);
        for (int b = 0; b < 8; b++) begin ch[b] = uart[g]; repeat (BIT_CLKS) @(posedge clk); end
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
    automatic int n = 0; automatic logic [31:0] c0; bit img_ok;
    $display("CONFIG: TOP=tb_merged_real CHECKS=10 FW=demo_fw CPU_TILE=cpu_tile_noc");
    load_d2(0); boot_epoch = BOOT;
    approved_measurement = FW_APPROVED_MEAS; expected_response = FW_EXPECTED_RESPONSE;
    repeat (8) @(negedge clk); rst = 0; repeat (60) @(negedge clk);
    img_ok = dut.c_meas_valid[0]; for (int k = 0; k < 16; k++) if (dut.c_meas[0][32*k +: 32] != DEMO_FW[k]) img_ok = 0;
    check(img_ok, $sformatf("MR_MEAS_IMAGE valid=%0b w0=%h", dut.c_meas_valid[0], dut.c_meas[0][31:0]));
    @(negedge clk); start_attestation = 1; @(negedge clk); start_attestation = 0;
    while (!authorized[3] && n < 200000) begin @(negedge clk); n++; end
    check(endpoint_response == expected_response, $sformatf("MR_RESPONSE match=%0b", endpoint_response == expected_response));
    check(authorized[3], $sformatf("MR_GRANT cycles=%0d", n));
    n = 0; while (!(rx_is(0, "T3 PASS\n") && rx_is(1, "T0 REFUSED\n")) && rxn[0] <= 12 && rxn[1] <= 12 && n < 600000) begin
      @(negedge clk); n++; end
    repeat (BIT_CLKS * 12) @(negedge clk);
    check(rx_is(0, "T3 PASS\n"), $sformatf("MR_T3_UART n=%0d hex=%s", rxn[0], rx_hex(0)));
    check(gpio[0][3:0] == 4'b0001, $sformatf("MR_T3_LED %b", gpio[0][3:0]));
    check(dut.u_bram.mem[32'h100 >> 2] == 32'hC0DE_5A5A, $sformatf("MR_BRAM word=%h", dut.u_bram.mem[32'h100 >> 2]));
    check(memory_commits == 1, $sformatf("MR_COMMITS commits=%0d", memory_commits));
    check(rx_is(1, "T0 REFUSED\n"), $sformatf("MR_T0_UART n=%0d hex=%s", rxn[1], rx_hex(1)));
    check(!authorized[0] && gate_faults[0] == 0 && gpio[1][3:0] == 4'b0010,
          $sformatf("MR_T0_ISOLATED authorized0=%0b gate_faults0=%0d led=%b", authorized[0], gate_faults[0], gpio[1][3:0]));
    @(negedge clk); revoke = 1; @(negedge clk); revoke = 0;
    n = 0; while (authorized[3] && n < 5000) begin @(negedge clk); n++; end
    repeat (300) @(negedge clk); c0 = memory_commits; repeat (3000) @(negedge clk);
    check(!authorized[3] && memory_commits == c0, $sformatf("MR_REVOKE authorized3=%0b commits_after=+%0d", authorized[3], memory_commits - c0));
    $display("CHECKS : %0d", checks); $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 10 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #80ms; $display("TB_TIMEOUT global"); $display("RESULT : FAIL"); $finish; end
endmodule
