`timescale 1ns/1ps
// Smoke bench for the D5 board wrapper (not registered, not evidence). Drives only the board pins: 100 MHz clock,
// buttons, switches; reads only LEDs plus memory_commits / gate_faults through hierarchy (read-only).
// Checks: AUTO_GRANT (led[0] after the automatic start), NO_FAIL, T3_WRITES (sw[0]: commits grow), T0_REFUSED
// (sw[1]: led0_r, and tile 0 adds no commits), REVOKE (btn[2] clears led[0]), REATTEST (btn[1] sets it again).
module tb_p7_board_top;
  logic CLK100MHZ = 0;
  logic [2:0] btn = 3'b001;   // held in reset at start
  logic [1:0] sw = 2'b00;
  logic [3:0] led;
  logic led0_r;
  always #5 CLK100MHZ = ~CLK100MHZ;

  pq_p7_board_top #(.DEBOUNCE_BITS(4), .AUTO_START_DELAY(16), .HEARTBEAT_BIT(8), .COMMIT_BIT(0)) dut (.*);

  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  task automatic wait_for(input string what, input int max_us, ref logic sig, input logic val, output bit ok);
    ok = 0;
    for (int i = 0; i < max_us * 100; i++) begin @(posedge CLK100MHZ); if (sig === val) begin ok = 1; break; end end
    if (!ok) $display("waited %0d us for %s", max_us, what);
  endtask
  task automatic press(input int b);
    btn[b] = 1; repeat (200) @(posedge CLK100MHZ); btn[b] = 0; repeat (200) @(posedge CLK100MHZ);
  endtask

  logic granted, refused;
  assign granted = led[0];
  assign refused = led0_r;
  int c0, c1, c2;
  bit ok;
  initial begin
    $display("CONFIG: TOP=tb_p7_board_top CHECKS=6");
    repeat (100) @(posedge CLK100MHZ); btn[0] = 0;
    wait_for("auto grant", 400, granted, 1'b1, ok);
    check(ok, "BOARD_AUTO_GRANT");
    check(led[1] == 1'b0, "BOARD_NO_FAIL");
    c0 = dut.u_p7.memory_commits; sw[0] = 1; repeat (20000) @(posedge CLK100MHZ); sw[0] = 0; repeat (2000) @(posedge CLK100MHZ);
    c1 = dut.u_p7.memory_commits;
    check(c1 > c0, $sformatf("BOARD_T3_WRITES commits=+%0d", c1 - c0));
    sw[1] = 1; wait_for("tile 0 refused", 200, refused, 1'b1, ok); repeat (5000) @(posedge CLK100MHZ);
    c2 = dut.u_p7.memory_commits; sw[1] = 0;
    check(ok && c2 == c1, $sformatf("BOARD_T0_REFUSED commits=+%0d", c2 - c1));
    press(2); wait_for("revoke", 400, granted, 1'b0, ok);
    check(ok, "BOARD_REVOKE");
    press(1); wait_for("re-attest", 400, granted, 1'b1, ok);
    check(ok && led[1] == 1'b0, "BOARD_REATTEST");
    $display("CHECKS : %0d", checks); $display("ERRORS : %0d", errors);
    $display("RESULT : %s", (errors == 0 && checks == 6) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
