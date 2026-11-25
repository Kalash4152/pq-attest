`timescale 1ns/1ps
// Smoke bench for synth/p7_area/pq_p7_soc_area_top.sv (SoC-profile accurate-area wrapper; not evidence; no golden model, no mutants).
// 100 MHz board clock -> MMCM 50 MHz. Checks: SOC_AREA_LOCKED (MMCM locks), SOC_AREA_CHAIN_LOADED (after shifting a full chain of
// pseudo-random bits, no X/Z remains in the provisioning chain), SOC_AREA_SDO_ACTIVE (with the subsystem running, sdo is
// never X/Z and toggles at least 16 times in 4,000 cycles: the outputs reach the MISR). CHECKS = 3.
module tb_p7_soc_area_top;
  logic CLK100MHZ = 0;
  always #5 CLK100MHZ = ~CLK100MHZ;
  logic [0:0] btn = 1'b1;
  logic [1:0] sw = 2'b00;
  logic [1:0] led;
  pq_p7_soc_area_top dut(.CLK100MHZ, .btn, .sw, .led);
  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  localparam int W = $bits(dut.u_soc.sr);
  initial begin
    automatic int n = 0, toggles = 0, xs = 0;
    automatic logic [31:0] lfsr = 32'hACE1_2026;
    automatic logic prev;
    $display("CONFIG: TOP=tb_p7_soc_area_top CHECKS=3 CHAIN_BITS=%0d", W);
    while (led[1] !== 1'b1 && n < 20000) begin @(posedge CLK100MHZ); n++; end
    check(led[1] === 1'b1, $sformatf("SOC_AREA_LOCKED after %0d board cycles", n));
    repeat (20) @(negedge dut.clk); btn = 1'b0; repeat (20) @(negedge dut.clk);
    for (int i = 0; i < W + 8; i++) begin
      @(negedge dut.clk); sw = {1'b1, lfsr[0]};
      lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
    end
    @(negedge dut.clk); sw = 2'b00; repeat (4) @(negedge dut.clk);
    check(!$isunknown(dut.u_soc.sr), $sformatf("SOC_AREA_CHAIN_LOADED bits=%0d", W));
    btn = 1'b1; repeat (20) @(negedge dut.clk); btn = 1'b0; repeat (20) @(negedge dut.clk);   // reset with defined inputs
    prev = led[0];
    for (int c = 0; c < 4000; c++) begin
      @(negedge dut.clk);
      if ($isunknown(led[0])) xs++;
      else if (led[0] !== prev) toggles++;
      prev = led[0];
    end
    check(xs == 0 && toggles >= 16, $sformatf("SOC_AREA_SDO_ACTIVE toggles=%0d unknown=%0d", toggles, xs));
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 3 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #3ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
