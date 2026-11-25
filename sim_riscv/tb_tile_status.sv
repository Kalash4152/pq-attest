`timescale 1ns / 1ps
// tb_tile_status (rewritten by Lane 1, 2026-11-06, for the brief v2 B4 map; the imported bench targeted the old map).
// Checks (CHECKS = 14, frozen before the first registered run):
//   ST_RESET_ZERO          after reset CTRL reads 0 except AUTHORIZED
//   ST_AUTHORIZED          CTRL[1] follows attested_i
//   ST_ATTEST_REQ_PULSE    W1 to CTRL[0] -> exactly one attest_req_o pulse; CTRL[0] reads 0
//   ST_GRANT_SEEN_STICKY   grant_done_i pulse -> CTRL[2] = 1 and stays 1
//   ST_GRANT_SEEN_W1C      W1C CTRL[2] clears it
//   ST_FAILED_STICKY_W1C   attest_failed_i -> CTRL[3] = 1; W1C clears it
//   ST_FAULT_LATCH         bus_fault_i -> CTRL[4] = 1, FAULT_ADDR / FAULT_CODE = the fault's
//   ST_FAULT_FIRST_KEPT    a second fault before the clear does not overwrite address / code
//   ST_FAULT_W1C_RELATCH   after W1C a new fault is latched
//   ST_SET_WINS            clear and set in the same cycle -> stays set
//   ST_BUILD_ID            +0xC = build_id_i
//   ST_TILE_ID             +0x10 = tile_id_i
//   ST_RO_WRITE_ERR        write to FAULT_ADDR -> err, no change
//   ST_INVALID_ERR         offset 0x14 -> err
module tb_tile_status;
  logic clk_i = 0, reset_i = 1;
  always #10 clk_i = ~clk_i;
  logic req_i = 0, we_i = 0; logic [31:0] addr_i = 0, wdata_i = 0; logic [3:0] wstrb_i = 0;
  logic gnt_o, rvalid_o, err_o; logic [31:0] rdata_o;
  logic [31:0] build_id_i = 32'h1234_ABCD; logic [3:0] tile_id_i = 4'h3;
  logic attested_i = 0, last_fault_timeout_i = 0, grant_done_i = 0, attest_failed_i = 0, bus_fault_i = 0;
  logic [31:0] fault_addr_i = 0; logic [3:0] fault_code_i = 0;
  logic attest_req_o;
  tile_status dut (.*);

  int checks = 0, errors = 0, pulses = 0;
  always @(posedge clk_i) if (attest_req_o) pulses++;
  task automatic check(input bit ok, input string name);
    checks++; if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  task automatic acc(input logic [31:0] a, input bit we, input logic [31:0] d, output logic [31:0] rd, output bit er);
    @(negedge clk_i); req_i = 1; addr_i = a; we_i = we; wdata_i = d; wstrb_i = we ? 4'hF : 4'h0;
    @(negedge clk_i); req_i = 0; we_i = 0; rd = rdata_o; er = err_o;
  endtask
  task automatic pulse(ref logic s); @(negedge clk_i); s = 1; @(negedge clk_i); s = 0; endtask

  initial begin
    logic [31:0] rd, a0; bit er; int p0;
    $display("CONFIG: TOP=tb_tile_status CHECKS=14 MAP=B4");
    repeat (3) @(negedge clk_i); reset_i = 0;
    acc(32'h0, 0, 0, rd, er);
    check(rd == 32'h0 && !er, $sformatf("ST_RESET_ZERO ctrl=%h", rd));
    attested_i = 1; acc(32'h0, 0, 0, rd, er);
    check(rd[1] && !er, $sformatf("ST_AUTHORIZED ctrl=%h", rd));
    p0 = pulses; acc(32'h0, 1, 32'h1, rd, er); repeat (2) @(negedge clk_i); acc(32'h0, 0, 0, rd, er);
    check(pulses == p0 + 1 && !rd[0], $sformatf("ST_ATTEST_REQ_PULSE pulses=+%0d ctrl=%h", pulses - p0, rd));
    pulse(grant_done_i); repeat (3) @(negedge clk_i); acc(32'h0, 0, 0, rd, er);
    check(rd[2], $sformatf("ST_GRANT_SEEN_STICKY ctrl=%h", rd));
    acc(32'h0, 1, 32'h4, rd, er); acc(32'h0, 0, 0, rd, er);
    check(!rd[2], $sformatf("ST_GRANT_SEEN_W1C ctrl=%h", rd));
    pulse(attest_failed_i); acc(32'h0, 0, 0, rd, er); a0 = rd;
    acc(32'h0, 1, 32'h8, rd, er); acc(32'h0, 0, 0, rd, er);
    check(a0[3] && !rd[3], $sformatf("ST_FAILED_STICKY_W1C before=%h after=%h", a0, rd));
    @(negedge clk_i); fault_addr_i = 32'h2200_0100; fault_code_i = 4'd3; pulse(bus_fault_i);
    acc(32'h0, 0, 0, rd, er); a0 = rd; acc(32'h4, 0, 0, rd, er);
    begin automatic logic [31:0] fa = rd; acc(32'h8, 0, 0, rd, er);
      check(a0[4] && fa == 32'h2200_0100 && rd == 32'd3, $sformatf("ST_FAULT_LATCH ctrl=%h addr=%h code=%0d", a0, fa, rd)); end
    @(negedge clk_i); fault_addr_i = 32'h3000_0000; fault_code_i = 4'd5; pulse(bus_fault_i);
    acc(32'h4, 0, 0, rd, er); a0 = rd; acc(32'h8, 0, 0, rd, er);
    check(a0 == 32'h2200_0100 && rd == 32'd3, $sformatf("ST_FAULT_FIRST_KEPT addr=%h code=%0d", a0, rd));
    acc(32'h0, 1, 32'h10, rd, er); acc(32'h0, 0, 0, rd, er); a0 = rd;
    @(negedge clk_i); fault_addr_i = 32'h0000_0080; fault_code_i = 4'd5; pulse(bus_fault_i);
    acc(32'h4, 0, 0, rd, er);
    check(!a0[4] && rd == 32'h0000_0080, $sformatf("ST_FAULT_W1C_RELATCH cleared=%0b addr=%h", !a0[4], rd));
    // clear and set in the same cycle
    @(negedge clk_i); req_i = 1; addr_i = 32'h0; we_i = 1; wdata_i = 32'h4; wstrb_i = 4'hF; grant_done_i = 1;
    @(negedge clk_i); req_i = 0; we_i = 0; grant_done_i = 0; acc(32'h0, 0, 0, rd, er);
    check(rd[2], $sformatf("ST_SET_WINS ctrl=%h", rd));
    acc(32'hC, 0, 0, rd, er);
    check(rd == 32'h1234_ABCD && !er, $sformatf("ST_BUILD_ID data=%h", rd));
    acc(32'h10, 0, 0, rd, er);
    check(rd == 32'h3 && !er, $sformatf("ST_TILE_ID data=%h", rd));
    acc(32'h4, 1, 32'hFFFF_FFFF, rd, er); a0 = {31'b0, er}; acc(32'h4, 0, 0, rd, er);
    check(a0[0] && rd == 32'h0000_0080, $sformatf("ST_RO_WRITE_ERR err=%0b addr=%h", a0[0], rd));
    acc(32'h14, 0, 0, rd, er);
    check(er && rd == 0, $sformatf("ST_INVALID_ERR err=%0b", er));
    $display("CHECKS : %0d", checks); $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 14 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #100us; $display("TB_TIMEOUT"); $display("RESULT : FAIL"); $finish; end
endmodule
