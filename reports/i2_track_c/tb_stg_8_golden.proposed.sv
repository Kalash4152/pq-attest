`timescale 1ns/1ps
// PROPOSED (I-2 Track C) revision of NOC_PQATTEST.srcs/sim_1/new/tb_stg_8_golden.sv.
// NOT ADOPTED. The original TB is unchanged. Adopting this file requires, BEFORE its first run:
//   (1) the V7 adapter (scripts/s8_golden.py sv_include) to emit, per vector,
//         expected_key = 256'h<key little-endian, byte i at [i*8 +: 8]>;
//       (the key is already in vectors/s8_golden.json; it is not in the .svh today);
//   (2) refreezing s8_golden / s8_mut_* / s8_control_after checks to 174;
//   (3) s8_mut_key_length oracle -> ^\[FAIL\] G\d\d_KEY  (wrong_key stays G\d\d_TAG).
//
// Changes against the frozen 95-check TB (each closes a gap in the V9 review):
//   G1 KEY checkpoint (V9: "plus the key, measurement and tag checkpoints"): compare
//      dut.kdf_derived_key with expected_key, fail-closed if expected_key is unknown
//      (no X-vs-X vacuous pass). Separates key_length (KEY+TAG) from wrong_key (TAG only).
//   G2 start-while-busy with a VALID, DISTINCT request in the tag phase (the existing
//      disturbance is invalid-length only, so "restart on busy start" was only caught via
//      the validator); plus a counted check that no extra done/busy follows.
//   G3 reset in every non-idle state 1..9 (KDF/MEAS/TAG start, the three waits, BUILD,
//      DONE, ERROR) instead of only the three wait states 2/4/6. State numbers are the
//      controller's state_t encoding (S_KDF_START=1 ... S_ERROR=9), verified in
//      pq_attest_protocol.sv lines 184-195.
//   G4 stale completion after reset is a COUNTED check failure, not $fatal (a $fatal is
//      INVALID evidence, never a kill). Window = max(300, 2 x max observed latency).
//   G5 RESET_CLEARS also requires status==0, error_code==0, err==0.
//
// Frozen count (hand-derived):
//   good(i,1), i=0..7   : 8 x (8 compare + 1 BUSY_START_IGNORED) = 72
//   reject x4           : 4 x 3                                  = 12
//   reset_in_state 1..9 : 9 x (2 reset checks + 8 compare)       = 90
//   total                                                        = 174
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
  logic [255:0] expected_key;            // assigned by the regenerated s8_golden.svh
  logic busy, done, err;
  logic [2:0] status;
  logic [3:0] error_code;
  int checks=0, errors=0, child_starts=0, max_latency=0;
  pq_attestation_controller dut(.*);
  `include "s8_golden.svh"
  always @(posedge clk) if (rst_n && (dut.kdf_start || dut.measurement_start || dut.tag_start)) child_starts++;
  task automatic check(input bit condition, input string name);
    checks++;
    if (!condition) begin errors++; $display("[FAIL] %s",name); end
  endtask
  task automatic load(input int idx);
    expected_key='x;                      // never inherit a previous vector's key
    load_vector(idx);
  endtask
  task automatic pulse;
    @(negedge clk); start=1;
    @(negedge clk); start=0;
  endtask
  function automatic int stale_window();
    return (2*max_latency > 300) ? 2*max_latency : 300;
  endfunction
  task automatic await_done(input string name);
    int cycles;
    cycles=0;
    while(!done && cycles<80000) begin @(posedge clk); #1; cycles++; end
    if (!done) $fatal(1,"TB_TIMEOUT %s",name);
    if (cycles>max_latency) max_latency=cycles;
    $display("LATENCY %s cycles=%0d",name,cycles);
  endtask
  task automatic await_state(input int st);
    int cycles;
    cycles=0;
    while(dut.state_q!=st && cycles<80000) begin @(negedge clk); cycles++; end
    if (dut.state_q!=st) $fatal(1,"TB_TIMEOUT state %0d never reached",st);
  endtask
  task automatic compare(input string name);
    check(done && !err && status==2 && error_code==0,{name,"_STATUS"});
    check(response[0+:56]===expected[0+:56],{name,"_TILE"});
    check(response[56+:80]===expected[56+:80],{name,"_EPOCH"});
    check(response[136+:128]===expected[136+:128],{name,"_NONCE"});
    check(!$isunknown(expected_key) && dut.kdf_derived_key===expected_key,{name,"_KEY"});
    check(response[264+:256]===expected[264+:256],{name,"_MEASUREMENT"});
    check(response[520+:256]===expected[520+:256],{name,"_TAG"});
    check(response===expected,{name,"_FULL_RESPONSE"});
    @(negedge clk); @(posedge clk); #1;
  endtask
  task automatic good(input int idx, input bit disturb);
    logic [775:0] exp_save;
    logic [255:0] key_save;
    bit second_while_busy, extra;
    @(negedge clk); load(idx); pulse();
    if(disturb) begin
      exp_save=expected; key_save=expected_key;
      repeat(5) @(negedge clk);
      // (a) Invalid, inverted request while busy in the KDF phase: must be ignored.
      tile_id=~tile_id; epoch=~epoch; nonce=~nonce; root_secret=~root_secret;
      context_in=~context_in; context_len=15;
      config_data=~config_data; imem=~imem; config_len=127; imem_len=127;
      pulse();
      // (b) VALID, distinct request while busy in the tag phase: must be ignored too.
      await_state(6);
      load((idx+1)%8); expected=exp_save; expected_key=key_save;
      @(negedge clk); second_while_busy=busy; start=1;
      @(negedge clk); start=0;
    end
    await_done($sformatf("G%02d",idx)); compare($sformatf("G%02d",idx));
    if(disturb) begin
      extra=0;
      repeat(stale_window()) begin @(posedge clk); #1; if(done||busy) extra=1; end
      check(second_while_busy && !extra,$sformatf("G%02d_BUSY_START_IGNORED",idx));
    end
  endtask
  task automatic reject(input int c, input int m, input int x, input int code);
    int before_starts;
    @(negedge clk); load(0); config_len=c; imem_len=m; context_len=x;
    before_starts=child_starts; pulse(); await_done("INVALID_LENGTH");
    check(err && status==3,"INVALID_STATUS");
    check(error_code==code,"INVALID_CODE");
    check(child_starts==before_starts,"INVALID_NO_CHILD_START");
    @(negedge clk); @(posedge clk); #1;
  endtask
  // Reset while the controller is in state st (1..8 via a valid request, 9 via an invalid one).
  task automatic reset_in_state(input int st);
    bit stale;
    @(negedge clk); load(1); if(st==9) context_len=15; pulse();
    await_state(st);
    rst_n=0; repeat(3) @(negedge clk);
    check(!busy && !done && !err && status==0 && error_code==0 && response=='0,
          $sformatf("RESET_CLEARS_S%0d",st));
    rst_n=1; stale=0;
    repeat(stale_window()) begin @(posedge clk); #1; if(done||busy) stale=1; end
    check(!stale && !busy && !done,$sformatf("RESET_NO_STALE_COMPLETION_S%0d",st));
    good(7,0);
  endtask
  initial begin
    $display("CONFIG: TOP=tb_stg_8_golden VECTORS=8 RESPONSE_BITS=776 DEMO=1");
    load(0); repeat(4) @(negedge clk); rst_n=1;
    for(int i=0;i<8;i++) good(i,1);
    reject(0,0,15,1); reject(65,0,0,2); reject(0,65,0,2); reject(65,0,15,1);
    for(int st=1;st<=9;st++) reset_in_state(st);
    $display("CHECKS : %0d",checks);
    $display("ERRORS : %0d",errors);
    $display("RESULT : %s",errors==0?"PASS":"FAIL");
    $finish;
  end
  initial begin #25ms; $fatal(1,"TB_TIMEOUT global"); end
endmodule
