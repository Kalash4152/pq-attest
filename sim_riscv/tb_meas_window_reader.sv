`timescale 1ns / 1ps
// tb_meas_window_reader -- unit bench for rtl/riscv/meas_window_reader.sv (brief v2 B3). Scratch-level until Lane 1
// registers it (counts frozen here before the first run).
// IMEM model: byte-addressed array, read port like tile_mem_wrapper meas_rd_* (rd_en + byte address, data registered
// one cycle later, little-endian words). Contents from vectors/d2_k3_64.svh (read-only, `include): IMEM byte a = row0
// imem byte a (a = 0..63) and row1 imem byte (a - 64) (a = 64..127); the svh imem uses the endpoint convention
// (byte i at [i*8 +: 8]). Row 0 IMEM bytes are 0x10..0x4F (vectors/d2_k3_64.json row 0 "imem").
// Two DUTs: MEAS_BASE 0 (row 0 window) and MEAS_BASE 0x40 (row 1 window).
// Checks (CHECKS = 10, frozen before the first run):
//   B3_IDLE_AFTER_RESET   valid 0, busy 0, no reads before the first start
//   B3_LEN_64             meas_imem_len = 64
//   B3_READ_SEQUENCE      after start: exactly 16 reads, byte addresses MEAS_BASE + 4k in order, back to back
//   B3_VALID_TIMING       valid low during the load; rises once, 17 cycles after the start edge (<= 18 allowed)
//   B3_WINDOW_ROW0        meas_imem == svh row 0 imem, compared byte for byte (first mismatch reported)
//   B3_BYTES_JSON_ROW0    byte i == 8'h10 + i for i = 0..63 (the JSON row 0 IMEM bytes, independent of the svh packing)
//   B3_FROZEN             after valid: IMEM rewritten, 50 cycles: window unchanged, valid still 1, no reads
//   B3_RESTART_DROPS_VALID  a new start: valid low on the next cycle, the new window (rewritten IMEM) is loaded
//   B3_RESTART_MIDWAY     start again 5 cycles into a load: exactly one valid rise, window == IMEM at the end
//   B3_BASE_0x40          second DUT (MEAS_BASE 0x40): reads 0x40..0x7C, window == svh row 1 imem
module tb_meas_window_reader;
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;

  // reference vectors (read-only include): variables used by load_d2
  logic [255:0] root_secret, approved_measurement;
  logic [79:0]  attest_epoch;
  logic [127:0] nonce, context_in;
  logic [511:0] config_data, imem;
  logic [775:0] expected_response;
  int context_len, config_len, imem_len;
  `include "d2_k3_64.svh"
  logic [511:0] row0, row1;

  // IMEM model
  logic [7:0] ib [0:255];
  logic        start0 = 0, start1 = 0;
  logic        en0, en1, v0, v1, b0, b1;
  logic [31:0] a0, a1, d0, d1;
  logic [511:0] w0, w1;
  logic [6:0]  l0, l1;
  always_ff @(posedge clk) begin
    if (en0) d0 <= {ib[a0[7:0] + 3], ib[a0[7:0] + 2], ib[a0[7:0] + 1], ib[a0[7:0]]};
    if (en1) d1 <= {ib[a1[7:0] + 3], ib[a1[7:0] + 2], ib[a1[7:0] + 1], ib[a1[7:0]]};
  end

  meas_window_reader #(.MEAS_BASE(32'h0000_0000)) dut0 (.clk, .rst, .start_i(start0), .meas_rd_en_o(en0), .meas_rd_addr_o(a0),
    .meas_rd_data_i(d0), .meas_imem_o(w0), .meas_imem_len_o(l0), .meas_valid_o(v0), .busy_o(b0));
  meas_window_reader #(.MEAS_BASE(32'h0000_0040)) dut1 (.clk, .rst, .start_i(start1), .meas_rd_en_o(en1), .meas_rd_addr_o(a1),
    .meas_rd_data_i(d1), .meas_imem_o(w1), .meas_imem_len_o(l1), .meas_valid_o(v1), .busy_o(b1));

  // read log for dut0
  int nreads = 0; logic [31:0] raddr [0:63]; int rcyc [0:63]; int cyc = 0; int vrise = 0; logic v0_q = 0;
  always @(posedge clk) begin
    cyc++;
    if (!rst && en0) begin if (nreads < 64) begin raddr[nreads] = a0; rcyc[nreads] = cyc; end nreads++; end
    v0_q <= v0; if (!rst && v0 && !v0_q) vrise++;
  end

  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  function automatic int first_bad(input logic [511:0] got, input logic [511:0] exp);
    for (int i = 0; i < 64; i++) if (got[i*8 +: 8] !== exp[i*8 +: 8]) return i;
    return -1;
  endfunction
  task automatic pulse0(); @(negedge clk); start0 = 1; @(negedge clk); start0 = 0; endtask

  initial begin
    int s, rise_cyc, fb, n0, r0; bit ok;
    $display("CONFIG: TOP=tb_meas_window_reader CHECKS=10 VECTORS=d2_k3_64 rows 0,1");
    load_d2(0); row0 = imem; load_d2(1); row1 = imem;
    for (int i = 0; i < 64; i++) begin ib[i] = row0[i*8 +: 8]; ib[64 + i] = row1[i*8 +: 8]; end
    for (int i = 128; i < 256; i++) ib[i] = 8'hEE;
    repeat (4) @(negedge clk); rst = 0; repeat (5) @(negedge clk);
    check(!v0 && !b0 && !v1 && !b1 && nreads == 0, $sformatf("B3_IDLE_AFTER_RESET valid=%0b busy=%0b reads=%0d", v0, b0, nreads));
    check(l0 == 7'd64 && l1 == 7'd64, $sformatf("B3_LEN_64 len=%0d", l0));

    // first load
    @(negedge clk); start0 = 1; s = cyc; @(negedge clk); start0 = 0;
    ok = 1; rise_cyc = -1;
    for (int t = 0; t < 40; t++) begin
      if (v0 && rise_cyc < 0) rise_cyc = cyc - s;
      if (rise_cyc < 0 && v0) ok = 0;
      @(negedge clk);
    end
    begin
      automatic bit seq_ok = (nreads == 16);
      for (int k = 0; k < 16 && k < nreads; k++) begin
        if (raddr[k] != 32'(4 * k)) seq_ok = 0;
        if (k > 0 && rcyc[k] != rcyc[k-1] + 1) seq_ok = 0;
      end
      check(seq_ok, $sformatf("B3_READ_SEQUENCE reads=%0d first=%h last=%h", nreads, raddr[0], raddr[(nreads > 0 && nreads <= 64) ? nreads - 1 : 0]));
    end
    check(vrise == 1 && rise_cyc >= 16 && rise_cyc <= 18, $sformatf("B3_VALID_TIMING rises=%0d cycles_after_start=%0d", vrise, rise_cyc));
    fb = first_bad(w0, row0);
    check(v0 && fb < 0, $sformatf("B3_WINDOW_ROW0 first_bad_byte=%0d got=%h exp=%h", fb, (fb >= 0) ? w0[fb*8 +: 8] : 8'h0, (fb >= 0) ? row0[fb*8 +: 8] : 8'h0));
    begin
      automatic int bad = -1;
      for (int i = 63; i >= 0; i--) if (w0[i*8 +: 8] !== 8'(8'h10 + i)) bad = i;
      check(bad < 0, $sformatf("B3_BYTES_JSON_ROW0 first_bad_byte=%0d byte0=%h byte63=%h", bad, w0[7:0], w0[511:504]));
    end

    // frozen while idle
    n0 = nreads;
    for (int i = 0; i < 64; i++) ib[i] = 8'hA0 ^ 8'(i);
    repeat (50) @(negedge clk);
    check(v0 && w0 == row0 && nreads == n0, $sformatf("B3_FROZEN valid=%0b window_same=%0b reads=+%0d", v0, w0 == row0, nreads - n0));

    // restart: valid drops, new window loaded
    r0 = vrise; n0 = nreads;
    @(negedge clk); start0 = 1; @(negedge clk); start0 = 0;
    begin
      automatic logic vd = v0;   // one cycle after the start edge
      repeat (30) @(negedge clk);
      ok = 1; for (int i = 0; i < 64; i++) if (w0[i*8 +: 8] !== (8'hA0 ^ 8'(i))) ok = 0;
      check(!vd && v0 && ok && vrise == r0 + 1 && nreads == n0 + 16,
            $sformatf("B3_RESTART_DROPS_VALID valid_after_start=%0b valid=%0b window_ok=%0b reads=+%0d", vd, v0, ok, nreads - n0));
    end

    // restart midway: IMEM changes between the two starts
    r0 = vrise;
    for (int i = 0; i < 64; i++) ib[i] = row0[i*8 +: 8];
    @(negedge clk); start0 = 1; @(negedge clk); start0 = 0;
    repeat (4) @(negedge clk);
    for (int i = 0; i < 64; i++) ib[i] = 8'h55 + 8'(i);
    @(negedge clk); start0 = 1; @(negedge clk); start0 = 0;
    repeat (40) @(negedge clk);
    ok = 1; for (int i = 0; i < 64; i++) if (w0[i*8 +: 8] !== (8'h55 + 8'(i))) ok = 0;
    check(v0 && ok && vrise == r0 + 1, $sformatf("B3_RESTART_MIDWAY valid=%0b window_ok=%0b rises=+%0d", v0, ok, vrise - r0));

    // MEAS_BASE 0x40
    @(negedge clk); start1 = 1; @(negedge clk); start1 = 0;
    repeat (30) @(negedge clk);
    fb = first_bad(w1, row1);
    check(v1 && fb < 0, $sformatf("B3_BASE_0x40 valid=%0b first_bad_byte=%0d byte0=%h", v1, fb, w1[7:0]));

    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 10 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #2ms; $display("TB_TIMEOUT global"); $display("RESULT : FAIL"); $finish; end
endmodule
