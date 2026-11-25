`timescale 1ns / 1ps
// tb_adapter_a3 (Lane 1, 2026-11-06, brief v2 A3): directed bench for the adapter's bus-error path.
// The imported conformance / random-latency benches never drive an error, so the poison path had no bench.
// Checks (CHECKS = 8, frozen before the first run):
//   A3_OK_NO_FAULT            remote read without error: data passes, no bus_fault pulse
//   A3_REMOTE_ERR_POISON      remote read, err, code 4 -> rdata 0xBADBE004, fault_code 4
//   A3_REMOTE_CODE0_MAPS_3    remote read, err, code 0 -> rdata 0xBADBE003, fault_code 3
//   A3_LOCAL_ERR_POISON       local read, err -> rdata 0xBADBE005, fault_code 5
//   A3_WRITE_ERR_FAULTS       remote write, err -> bus_fault pulses, fault_code 2
//   A3_FAULT_ADDR             fault_addr_o = the faulting request's address (each error case)
//   A3_PULSE_ALIGNED          bus_fault_o is high only in cycles where mem_ready_o is high
//   A3_ONE_PULSE_PER_ERROR    bus_fault pulse count = number of error transfers (4)
module tb_adapter_a3;
  logic clk_i = 0, reset_i = 1;
  always #10 clk_i = ~clk_i;
  logic mem_valid_i = 0, mem_instr_i = 0; logic [31:0] mem_addr_i = 0, mem_wdata_i = 0; logic [3:0] mem_wstrb_i = 0;
  logic mem_ready_o; logic [31:0] mem_rdata_o;
  logic local_req_o, local_we_o, local_is_fetch_o; logic [31:0] local_addr_o, local_wdata_o; logic [3:0] local_wstrb_o;
  logic tmem_req_o, tmem_we_o, tmem_is_fetch_o; logic [31:0] tmem_addr_o, tmem_wdata_o; logic [3:0] tmem_wstrb_o;
  wire  local_gnt_i = 1'b1, tmem_gnt_i = 1'b1;
  logic local_rvalid_i = 0, tmem_rvalid_i = 0, local_err_i = 0, tmem_err_i = 0;
  logic [31:0] local_rdata_i = 0, tmem_rdata_i = 0;
  logic [3:0] tmem_err_code_i = 0;
  logic bus_fault_o; logic [31:0] fault_addr_o; logic [3:0] fault_code_o;

  picorv32_adapter dut (.*);

  // slave models: grant at once, answer one cycle later with the configured error / data
  logic err_cfg = 0; logic [3:0] code_cfg = 0; logic [31:0] data_cfg = 0;
  always @(posedge clk_i) begin
    local_rvalid_i <= local_req_o; local_err_i <= local_req_o && err_cfg; local_rdata_i <= data_cfg;
    tmem_rvalid_i  <= tmem_req_o;  tmem_err_i  <= tmem_req_o && err_cfg;  tmem_rdata_i  <= data_cfg;
    tmem_err_code_i <= code_cfg;
  end
  int pulses = 0, misaligned = 0;
  always @(posedge clk_i) if (!reset_i) begin
    if (bus_fault_o) pulses++;
    if (bus_fault_o && !mem_ready_o) misaligned++;
  end

  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++; if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  // one CPU transfer; returns the data and whether bus_fault_o was high with mem_ready_o
  task automatic xfer(input logic [31:0] a, input logic [3:0] s, input bit e, input logic [3:0] c, input logic [31:0] dat,
                      output logic [31:0] rd, output bit flt);
    automatic int n = 0;
    @(negedge clk_i); err_cfg = e; code_cfg = c; data_cfg = dat;
    mem_valid_i = 1; mem_addr_i = a; mem_wstrb_i = s; mem_wdata_i = 32'h5555_AAAA;
    do begin @(posedge clk_i); #1; n++; end while (!mem_ready_o && n < 50);
    rd = mem_rdata_o; flt = bus_fault_o; mem_valid_i = 0; mem_wstrb_i = 0;
    repeat (2) @(negedge clk_i);
  endtask

  initial begin
    logic [31:0] rd; bit flt, fa_ok;
    $display("CONFIG: TOP=tb_adapter_a3 CHECKS=8");
    repeat (3) @(negedge clk_i); reset_i = 0; repeat (2) @(negedge clk_i);
    fa_ok = 1;
    xfer(32'h2000_0040, 4'h0, 0, 4'd0, 32'h1234_5678, rd, flt);
    check(rd == 32'h1234_5678 && !flt && pulses == 0, $sformatf("A3_OK_NO_FAULT data=%h fault=%0b", rd, flt));
    xfer(32'h2000_0100, 4'h0, 1, 4'd4, 32'hFFFF_FFFF, rd, flt);
    check(rd == 32'hBADB_E004 && flt && fault_code_o == 4'd4, $sformatf("A3_REMOTE_ERR_POISON data=%h code=%0d", rd, fault_code_o));
    if (fault_addr_o != 32'h2000_0100) fa_ok = 0;
    xfer(32'h2000_0200, 4'h0, 1, 4'd0, 32'hFFFF_FFFF, rd, flt);
    check(rd == 32'hBADB_E003 && flt && fault_code_o == 4'd3, $sformatf("A3_REMOTE_CODE0_MAPS_3 data=%h code=%0d", rd, fault_code_o));
    if (fault_addr_o != 32'h2000_0200) fa_ok = 0;
    xfer(32'h3000_0000, 4'h0, 1, 4'd0, 32'hFFFF_FFFF, rd, flt);
    check(rd == 32'hBADB_E005 && flt && fault_code_o == 4'd5, $sformatf("A3_LOCAL_ERR_POISON data=%h code=%0d", rd, fault_code_o));
    if (fault_addr_o != 32'h3000_0000) fa_ok = 0;
    xfer(32'h2000_0300, 4'hF, 1, 4'd2, 32'h0, rd, flt);
    check(flt && fault_code_o == 4'd2, $sformatf("A3_WRITE_ERR_FAULTS fault=%0b code=%0d", flt, fault_code_o));
    if (fault_addr_o != 32'h2000_0300) fa_ok = 0;
    check(fa_ok, "A3_FAULT_ADDR");
    repeat (4) @(negedge clk_i);
    check(misaligned == 0, $sformatf("A3_PULSE_ALIGNED misaligned=%0d", misaligned));
    check(pulses == 4, $sformatf("A3_ONE_PULSE_PER_ERROR pulses=%0d", pulses));
    $display("CHECKS : %0d", checks); $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 8 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #100us; $display("TB_TIMEOUT"); $display("RESULT : FAIL"); $finish; end
endmodule
