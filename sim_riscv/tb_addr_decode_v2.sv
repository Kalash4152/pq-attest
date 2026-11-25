`timescale 1ns / 1ps
// tb_addr_decode_v2 (Lane 1, 2026-11-06): directed bench for the CURRENT addr_decode interface (the imported tb_addr_decode
// targets an older interface and does not elaborate). IMEM / DMEM are modelled exactly like mem_bram (registered, ready one
// cycle after valid, an access on EVERY valid cycle); peripherals grant at once and answer one cycle later.
// Checks (CHECKS = 12, frozen before the first registered run):
//   DEC_IMEM_READ_ONE_ACCESS    IMEM read: one valid cycle, data returned, err 0                 (AD-1)
//   DEC_DMEM_READ_ONE_ACCESS    DMEM read: one valid cycle, data returned                        (AD-1)
//   DEC_DMEM_WRITE_ONE_ACCESS   DMEM write: exactly one write access (wstrb seen once)          (AD-1)
//   DEC_DMEM_WRITE_DATA         the written word reads back                                       (AD-1)
//   DEC_NO_STALE_READY          no memory ready ever arrives while the decoder is IDLE            (AD-1)
//   DEC_IMEM_STORE_REFUSED      IMEM store: IMEM never sees valid, response = err               (R-D8)
//   DEC_IMEM_STORE_NO_CHANGE    the IMEM word is unchanged after the refused store              (R-D8)
//   DEC_UNMAPPED_ERR_AFTER_GNT  unmapped: no rvalid in the grant cycle, rvalid + err next cycle  (AD-4)
//   DEC_UART_ROUTE / DEC_GPIO_ROUTE / DEC_STATUS_ROUTE  request reaches its target with the offset address
//   DEC_ONE_RESPONSE_EACH       every accepted request got exactly one rvalid
module tb_addr_decode_v2;
  logic clk_i = 0, reset_i = 1;
  always #10 clk_i = ~clk_i;
  logic local_req_i = 0, local_we_i = 0, local_is_fetch_i = 0;
  logic [31:0] local_addr_i = 0, local_wdata_i = 0; logic [3:0] local_wstrb_i = 0;
  logic local_gnt_o, local_rvalid_o, local_err_o; logic [31:0] local_rdata_o;
  logic imem_valid_o, dmem_valid_o; logic [31:0] imem_addr_o, imem_wdata_o, dmem_addr_o, dmem_wdata_o;
  logic [3:0] imem_wstrb_o, dmem_wstrb_o; logic imem_ready_i = 0, dmem_ready_i = 0; logic [31:0] imem_rdata_i, dmem_rdata_i;
  logic uart_req_o, uart_we_o, gpio_req_o, gpio_we_o, status_req_o, status_we_o;
  logic [31:0] uart_addr_o, uart_wdata_o, gpio_addr_o, gpio_wdata_o, status_addr_o, status_wdata_o;
  logic [3:0] uart_wstrb_o, gpio_wstrb_o, status_wstrb_o;
  logic uart_rvalid_i = 0, gpio_rvalid_i = 0, status_rvalid_i = 0;
  wire uart_gnt_i = 1'b1, gpio_gnt_i = 1'b1, status_gnt_i = 1'b1;
  wire uart_err_i = 1'b0, gpio_err_i = 1'b0, status_err_i = 1'b0;
  wire [31:0] uart_rdata_i = 32'h0000_00A5, gpio_rdata_i = 32'h0000_00B6, status_rdata_i = 32'h0000_00C7;
  // Revision 9 adds an NI target. Keep the original 12 checks unchanged;
  // NI-specific behavior is independently exercised by tb_closure_ni.
  logic ni_req_o, ni_we_o;
  logic [31:0] ni_addr_o;
  logic ni_rvalid_i = 0;
  wire [31:0] ni_rdata_i = 32'd9;
  wire ni_err_i = ni_we_o;
  always @(posedge clk_i) ni_rvalid_i <= !reset_i && ni_req_o;

  addr_decode dut (.*);

  // mem_bram-equivalent models: registered, an access on every valid cycle
  logic [31:0] imem [0:4095], dmem [0:4095];
  int imem_acc = 0, dmem_acc = 0, dmem_wr_acc = 0, stale = 0, rvalids = 0;
  always @(posedge clk_i) begin
    imem_ready_i <= 1'b0; dmem_ready_i <= 1'b0;
    if (!reset_i && imem_valid_o) begin
      imem_acc++; imem_ready_i <= 1'b1; imem_rdata_i <= imem[imem_addr_o[13:2]];
      for (int b = 0; b < 4; b++) if (imem_wstrb_o[b]) imem[imem_addr_o[13:2]][b*8 +: 8] <= imem_wdata_o[b*8 +: 8];
    end
    if (!reset_i && dmem_valid_o) begin
      dmem_acc++; if (dmem_wstrb_o != 0) dmem_wr_acc++; dmem_ready_i <= 1'b1; dmem_rdata_i <= dmem[dmem_addr_o[13:2]];
      for (int b = 0; b < 4; b++) if (dmem_wstrb_o[b]) dmem[dmem_addr_o[13:2]][b*8 +: 8] <= dmem_wdata_o[b*8 +: 8];
    end
    uart_rvalid_i <= uart_req_o && uart_gnt_i; gpio_rvalid_i <= gpio_req_o && gpio_gnt_i; status_rvalid_i <= status_req_o && status_gnt_i;
    if (!reset_i && dut.state_q == 0 && (imem_ready_i || dmem_ready_i)) stale++;
    if (!reset_i && local_rvalid_o) rvalids++;
  end

  int checks = 0, errors = 0, accepted = 0;
  task automatic check(input bit ok, input string name);
    checks++; if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  // one request; returns data / err / whether rvalid came in the grant cycle / cycles to the response
  task automatic access(input logic [31:0] a, input bit we, input logic [31:0] d, input logic [3:0] s,
                        output logic [31:0] rd, output bit err, output bit rv_in_gnt);
    automatic int n = 0;
    @(negedge clk_i); local_req_i = 1; local_addr_i = a; local_we_i = we; local_wdata_i = d; local_wstrb_i = s;
    #1; while (!local_gnt_o && n < 50) begin @(negedge clk_i); #1; n++; end
    rv_in_gnt = local_rvalid_o; accepted++;
    @(negedge clk_i); local_req_i = 0; n = 0;
    #1; while (!local_rvalid_o && n < 50) begin @(negedge clk_i); #1; n++; end
    rd = local_rdata_o; err = local_err_o;
    @(negedge clk_i);
  endtask

  initial begin
    logic [31:0] rd; bit err, rvg; int i0, d0, w0;
    $display("CONFIG: TOP=tb_addr_decode_v2 CHECKS=12");
    for (int k = 0; k < 4096; k++) begin imem[k] = 32'h1000_0000 + k; dmem[k] = 32'h2000_0000 + k; end
    repeat (4) @(negedge clk_i); reset_i = 0; repeat (2) @(negedge clk_i);

    i0 = imem_acc; access(32'h0000_0040, 0, 0, 0, rd, err, rvg);
    check(imem_acc == i0 + 1 && rd == 32'h1000_0010 && !err, $sformatf("DEC_IMEM_READ_ONE_ACCESS accesses=%0d data=%h err=%0b", imem_acc - i0, rd, err));
    d0 = dmem_acc; access(32'h0000_4080, 0, 0, 0, rd, err, rvg);
    check(dmem_acc == d0 + 1 && rd == 32'h2000_0020, $sformatf("DEC_DMEM_READ_ONE_ACCESS accesses=%0d data=%h", dmem_acc - d0, rd));
    w0 = dmem_wr_acc; access(32'h0000_4100, 1, 32'hCAFE_F00D, 4'hF, rd, err, rvg);
    check(dmem_wr_acc == w0 + 1 && !err, $sformatf("DEC_DMEM_WRITE_ONE_ACCESS write_accesses=%0d", dmem_wr_acc - w0));
    access(32'h0000_4100, 0, 0, 0, rd, err, rvg);
    check(rd == 32'hCAFE_F00D, $sformatf("DEC_DMEM_WRITE_DATA read=%h", rd));
    i0 = imem_acc; access(32'h0000_0080, 1, 32'hDEAD_BEEF, 4'hF, rd, err, rvg);
    check(imem_acc == i0 && err, $sformatf("DEC_IMEM_STORE_REFUSED imem_accesses=%0d err=%0b", imem_acc - i0, err));
    check(imem[32] == 32'h1000_0020, $sformatf("DEC_IMEM_STORE_NO_CHANGE word=%h", imem[32]));
    access(32'h3000_0000, 0, 0, 0, rd, err, rvg);
    check(!rvg && err && rd == 0, $sformatf("DEC_UNMAPPED_ERR_AFTER_GNT rvalid_in_gnt=%0b err=%0b data=%h", rvg, err, rd));
    access(32'h1000_0004, 0, 0, 0, rd, err, rvg);
    check(rd == 32'hA5 && !err, $sformatf("DEC_UART_ROUTE data=%h", rd));
    access(32'h1000_1004, 0, 0, 0, rd, err, rvg);
    check(rd == 32'hB6 && !err, $sformatf("DEC_GPIO_ROUTE data=%h", rd));
    access(32'h1000_2008, 0, 0, 0, rd, err, rvg);
    check(rd == 32'hC7 && !err, $sformatf("DEC_STATUS_ROUTE data=%h", rd));
    repeat (5) @(negedge clk_i);
    check(stale == 0, $sformatf("DEC_NO_STALE_READY stale=%0d", stale));
    check(rvalids == accepted, $sformatf("DEC_ONE_RESPONSE_EACH accepted=%0d rvalids=%0d", accepted, rvalids));
    $display("CHECKS : %0d", checks); $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 12 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #200us; $display("TB_TIMEOUT global"); $display("RESULT : FAIL"); $finish; end
endmodule
