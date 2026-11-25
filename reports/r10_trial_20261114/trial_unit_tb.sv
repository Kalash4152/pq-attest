`timescale 1ns/1ps
module tb_meas_imem_trial;
  logic clk=0,rst=1,start_i=0;
  always #10 clk=~clk;
  logic en,valid,busy;logic [31:0] addr,data;
  logic [511:0] field;logic [6:0] len;
  logic [31:0] mem [0:4095];
  `include "digests.svh"
  meas_imem_hasher dut(.clk,.rst,.start_i,.meas_rd_en_o(en),.meas_rd_addr_o(addr),
    .meas_rd_data_i(data),.meas_imem_o(field),.meas_imem_len_o(len),.meas_valid_o(valid),.busy_o(busy));
  int requests=0,bad_addresses=0,checks=0,errors=0;
  always @(posedge clk)begin
    if(en)data<=mem[addr[13:2]];
    if(rst || start_i)begin requests=0;bad_addresses=0;end
    else if(en)begin
      if(addr!==32'(requests*4) || requests>=4096)bad_addresses++;
      requests++;
    end
  end
  task automatic check(input bit ok,input string name);
    checks++;
    if(ok)$display("[PASS] %s",name);else begin errors++;$display("[FAIL] %s",name);end
  endtask
  task automatic start;
    @(negedge clk);start_i=1;@(negedge clk);start_i=0;
  endtask
  task automatic finish_hash;
    int n;n=0;while(!valid && n<25000)begin @(negedge clk);n++;end
    if(!valid)begin $display("TB_TIMEOUT HASH");$fatal(1,"hasher never finished");end
  endtask
  initial begin
    logic [511:0] held;
    $display("CONFIG: TOP=tb_meas_imem_trial CHECKS=9");
    repeat(5)@(negedge clk);rst=0;
    for(int image=0;image<3;image++)begin
      case(image)
        0:$readmemh("image0.hex",mem);
        1:$readmemh("image1.hex",mem);
        2:$readmemh("image2.hex",mem);
      endcase
      start();finish_hash();
      check(field[255:0]===EXPECTED[image],$sformatf("HASH_DIGEST_%0d got=%h",image,field[255:0]));
      check(requests==4096 && bad_addresses==0 && len==64 &&
        field[511:256]=={192'd0,32'd0,32'd16384} && !busy,$sformatf("HASH_METADATA_READS_%0d",image));
    end
    held=field;repeat(10)@(negedge clk);
    check(valid && !busy && field===held,"HASH_HELD_RESULT");
    start();repeat(100)@(negedge clk);start();finish_hash();
    check(field[255:0]===EXPECTED[2] && requests==4096 && bad_addresses==0,"HASH_RESTART_WHILE_BUSY");
    start();repeat(100)@(negedge clk);rst=1;@(negedge clk);rst=0;
    if(valid || busy || field!==0)$fatal(1,"reset state incorrect");
    start();finish_hash();
    check(field[255:0]===EXPECTED[2] && requests==4096 && bad_addresses==0,"HASH_RESET_AND_RESTART");
    $display("CHECKS : %0d",checks);$display("ERRORS : %0d",errors);
    $display("RESULT : %s",errors==0 && checks==9?"PASS":"FAIL");$finish;
  end
  initial begin #10ms;$display("TB_TIMEOUT HASH_UNIT");$fatal(1,"global watchdog");end
endmodule
