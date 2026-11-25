`timescale 1ns/1ps
// SKELETON SMOKE BENCH for pq_soc_merged_core (stub CPU tiles). NOT EVIDENCE, NOT REGISTERED.
// Provisioning: vectors/d2_k3_64.svh row 0 (K-3 config 16 / IMEM 64) + full_chain.svh BOOT / KEYS.
// SK_RESPONSE   endpoint_response == teammate expected response (64-byte IMEM from CPU A's meas_imem_o)
// SK_GRANT      tile 3 authorized after the RoT start
// SK_CPU_A      CPU A completed >= 3 write/read rounds through the BRAM, no error
// SK_BRAM       the BRAM word at 0x100 holds CPU A's last written data
// SK_CPU_B      CPU B (tile 0) refused locally, never authorized, no gate fault at tile 0 (it never raised app_valid)
// SK_REVOKE     after REVOKE tile 3 is not authorized and no further commit happens
module tb_merged_skeleton;
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
  localparam logic [511:0] IMAGE = 512'h4f4e4d4c4b4a494847464544434241403f3e3d3c3b3a393837363534333231302f2e2d2c2b2a292827262524232221201f1e1d1c1b1a19181716151413121110;
  pq_soc_merged_core #(.VERIFIER_TIMEOUT(20000), .ROUND_GAP(64), .CPU_A_MEAS_IMAGE(IMAGE)) dut(
    .clk, .rst, .start_attestation, .revoke, .trusted_clear(1'b0), .boot_epoch, .attest_epoch, .nonce, .root_secret,
    .approved_measurement, .directed_keys({KEYS[(3*6+4)*256 +: 256], KEYS[(4*6+3)*256 +: 256]}),
    .context_in, .context_len, .config_data, .authorized, .rot_busy, .grant_done, .attestation_failed, .memory_commits,
    .gate_faults, .fault_sticky, .fault_reason, .endpoint_response, .cpu_uart_tx(uart), .cpu_gpio(gpio));
  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++; if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  initial begin
    automatic int n = 0; automatic logic [31:0] c0;
    load_d2(0); boot_epoch = BOOT;
    repeat (8) @(negedge clk); rst = 0; repeat (20) @(negedge clk);
    check(imem == IMAGE, "SK_IMAGE_MATCHES_VECTOR");
    @(negedge clk); start_attestation = 1; @(negedge clk); start_attestation = 0;
    while (!authorized[3] && n < 200000) begin @(negedge clk); n++; end
    check(endpoint_response == expected_response, $sformatf("SK_RESPONSE match=%0b", endpoint_response == expected_response));
    check(authorized[3], $sformatf("SK_GRANT cycles=%0d", n));
    n = 0; while (gpio[0][7:4] < 3 && n < 400000) begin @(negedge clk); n++; end
    check(gpio[0][7:4] >= 3 && gpio[0][0] && gpio[0][1] && !gpio[0][2],
          $sformatf("SK_CPU_A rounds=%0d wr_ok=%0b rd_ok=%0b err=%0b commits=%0d", gpio[0][7:4], gpio[0][0], gpio[0][1], gpio[0][2], memory_commits));
    repeat (10) @(negedge clk);
    check(dut.u_bram.mem[32'h100 >> 2][31:24] == 8'hA3, $sformatf("SK_BRAM word=%h", dut.u_bram.mem[32'h100 >> 2]));
    check(gpio[1][3] && !authorized[0] && gate_faults[0] == 0 && gpio[1][7:4] == 0,
          $sformatf("SK_CPU_B refused=%0b authorized0=%0b gate_faults0=%0d", gpio[1][3], authorized[0], gate_faults[0]));
    @(negedge clk); revoke = 1; @(negedge clk); revoke = 0;
    n = 0; while (authorized[3] && n < 5000) begin @(negedge clk); n++; end
    repeat (300) @(negedge clk); c0 = memory_commits; repeat (3000) @(negedge clk);
    check(!authorized[3] && memory_commits == c0, $sformatf("SK_REVOKE authorized3=%0b commits_after=+%0d", authorized[3], memory_commits - c0));
    $display("CHECKS : %0d", checks); $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 7 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #80ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
