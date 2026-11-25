`timescale 1ns/1ps
module tb_stg_8_golden;
  logic clk=0, rst_n=0, start=0;
  always #10 clk=~clk;
  logic [55:0] tile_id;
  logic [79:0] epoch;
  logic [127:0] nonce;
  logic [255:0] root_secret;
  logic [111:0] context_in;
  logic [3:0] context_len;
  logic [511:0] config_data, imem;
  logic [6:0] config_len, imem_len;
  logic [775:0] response, expected;
  logic busy, done, err;
  logic [2:0] status;
  logic [3:0] error_code;
  int checks=0, errors=0, child_starts=0;
  pq_attestation_controller dut(.*);
  `include "s8_golden.svh"
  always @(posedge clk) if (rst_n && (dut.kdf_start || dut.measurement_start || dut.tag_start)) child_starts++;
  task automatic check(input bit condition, input string name);
    checks++;
    if (!condition) begin errors++; $display("[FAIL] %s",name); end
  endtask
  task automatic pulse;
    @(negedge clk); start=1;
    @(negedge clk); start=0;
  endtask
  task automatic await_done(input string name);
    int cycles;
    cycles=0;
    while(!done && cycles<80000) begin @(posedge clk); #1; cycles++; end
    if (!done) $fatal(1,"TB_TIMEOUT %s",name);
    $display("LATENCY %s cycles=%0d",name,cycles);
  endtask
  task automatic compare(input string name);
    check(done && !err && status==2 && error_code==0,{name,"_STATUS"});
    check(response[0+:56]===expected[0+:56],{name,"_TILE"});
    check(response[56+:80]===expected[56+:80],{name,"_EPOCH"});
    check(response[136+:128]===expected[136+:128],{name,"_NONCE"});
    check(response[264+:256]===expected[264+:256],{name,"_MEASUREMENT"});
    check(response[520+:256]===expected[520+:256],{name,"_TAG"});
    check(response===expected,{name,"_FULL_RESPONSE"});
    @(negedge clk); @(posedge clk); #1;
  endtask
  task automatic good(input int idx, input bit disturb);
    @(negedge clk); load_vector(idx); pulse();
    if(disturb) begin
      repeat(5) @(negedge clk);
      // Accepted request must be latched; a second start while busy is ignored.
      tile_id=~tile_id; epoch=~epoch; nonce=~nonce; root_secret=~root_secret;
      context_in=~context_in; context_len=15;
      config_data=~config_data; imem=~imem; config_len=127; imem_len=127;
      pulse();
    end
    await_done($sformatf("G%02d",idx)); compare($sformatf("G%02d",idx));
  endtask
  task automatic reject(input int c, input int m, input int x, input int code);
    int before_starts;
    @(negedge clk); load_vector(0); config_len=c; imem_len=m; context_len=x;
    before_starts=child_starts; pulse(); await_done("INVALID_LENGTH");
    check(err && status==3,"INVALID_STATUS");
    check(error_code==code,"INVALID_CODE");
    check(child_starts==before_starts,"INVALID_NO_CHILD_START");
    @(negedge clk); @(posedge clk); #1;
  endtask
  initial begin
    $display("CONFIG: TOP=tb_stg_8_golden VECTORS=8 RESPONSE_BITS=776 DEMO=1");
    load_vector(0); repeat(4) @(negedge clk); rst_n=1;
    for(int i=0;i<8;i++) good(i,1);
    reject(0,0,15,1); reject(65,0,0,2); reject(0,65,0,2); reject(65,0,15,1);
    // Reset in KDF, measurement and tag wait states; no stale completion.
    for(int st=2;st<=6;st+=2) begin
      @(negedge clk); load_vector(1); pulse();
      while(dut.state_q!=st) @(negedge clk);
      rst_n=0; repeat(3) @(negedge clk);
      check(!busy && !done && response=='0,"RESET_CLEARS");
      rst_n=1;
      repeat(300) begin @(posedge clk); #1; if(done) $fatal(1,"stale done after reset"); end
      check(!busy && !done,"RESET_NO_STALE_COMPLETION");
      good(7,0);
    end
    $display("CHECKS : %0d",checks);
    $display("ERRORS : %0d",errors);
    $display("RESULT : %s",errors==0?"PASS":"FAIL");
    $finish;
  end
  initial begin #25ms; $fatal(1,"TB_TIMEOUT global"); end
endmodule
