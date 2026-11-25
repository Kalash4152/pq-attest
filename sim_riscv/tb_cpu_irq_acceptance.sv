`timescale 1ns/1ps
// I-18 counts frozen before first execution: 10 checks, real CPU, RISCV_FORMAL.
// Three independent cases: remote read, remote write, local unmapped read.
module tb_cpu_irq_acceptance;
  logic clk=0, rst=1;
  always #10 clk=~clk;
  `include "irq_acceptance.svh"
  logic [2:0] entered, bad_retire, marker, fault_seen, status_ok;
  int cycles=0;
  always @(posedge clk) cycles <= cycles+1;
  for(genvar g=0;g<3;g++) begin: cases
    logic iv,ir,dv,dr,tx,req,we,fetch,gnt,rv,err,areq;
    logic [31:0] ia,iw,idata,da,dw,ddata,ta,tw,rd;
    logic [3:0] is,ds,ts,led;
    tile_top #(.TILE_ID(3)) dut(
      .clk_i(clk),.reset_i(rst),
      .imem_valid_o(iv),.imem_addr_o(ia),.imem_wdata_o(iw),.imem_wstrb_o(is),.imem_ready_i(ir),.imem_rdata_i(idata),
      .dmem_valid_o(dv),.dmem_addr_o(da),.dmem_wdata_o(dw),.dmem_wstrb_o(ds),.dmem_ready_i(dr),.dmem_rdata_i(ddata),
      .uart_tx_o(tx),.switches_i(4'b0),.leds_o(led),
      .tmem_req_o(req),.tmem_we_o(we),.tmem_addr_o(ta),.tmem_wdata_o(tw),.tmem_wstrb_o(ts),.tmem_is_fetch_o(fetch),
      .tmem_gnt_i(gnt),.tmem_rvalid_i(rv),.tmem_rdata_i(rd),.tmem_err_i(err),.tmem_err_code_i(4'd3),
      .attested_i(1'b1),.last_fault_timeout_i(1'b0),.attest_req_o(areq),.grant_done_i(1'b0),.attest_failed_i(1'b0),
      .dbg_pc_o(),.dbg_inst_o(),.dbg_valid_o(),.dbg_trap_o());
    tile_mem_wrapper mem(
      .clk_i(clk),.reset_i(rst),
      .imem_valid_i(iv),.imem_addr_i(ia),.imem_wdata_i(iw),.imem_wstrb_i(is),.imem_ready_o(ir),.imem_rdata_o(idata),
      .dmem_valid_i(dv),.dmem_addr_i(da),.dmem_wdata_i(dw),.dmem_wstrb_i(ds),.dmem_ready_o(dr),.dmem_rdata_o(ddata),
      .meas_rd_en_i(1'b0),.meas_rd_addr_i(32'b0),.meas_rd_data_o());
    assign gnt=req;
    always @(posedge clk) begin
      if(rst) begin rv<=0;err<=0;rd<=0;end
      else begin rv<=req;err<=req;rd<=32'hffffffff;end
    end
    initial begin
      entered[g]=0;bad_retire[g]=0;fault_seen[g]=0;
      for(int k=0;k<IRQ_ACCEPTANCE_N;k++) mem.imem_inst.mem[k]=IRQ_ACCEPTANCE[k];
      if(g==1) mem.imem_inst.mem[IRQ_FAULT_PC/4]=32'h01242023; // sw s2,0(s0)
      if(g==2) begin
        mem.imem_inst.mem[IRQ_ADDR_PC/4]=32'h30000437; // lui s0,0x30000
        mem.imem_inst.mem[IRQ_ADDR_PC/4+1]=32'h00040413;
      end
    end
    always @(posedge clk) begin
      #1;
      if(!rst) begin
        if(dut.bus_fault) fault_seen[g]=1;
        if(dut.cpu.irq_active) entered[g]=1;
        if(fault_seen[g] && !entered[g] && dut.cpu.rvfi_valid && dut.cpu.rvfi_pc_rdata==IRQ_NEXT_PC)
          bad_retire[g]=1;
      end
    end
    assign marker[g]=(mem.dmem_inst.mem[1]===32'h600d0001);
    assign status_ok[g]=dut.tile_status_inst.bus_fault_q &&
      dut.tile_status_inst.fault_code_q==(g==2 ? 4'd5 : 4'd3) &&
      dut.tile_status_inst.fault_addr_q==(g==2 ? 32'h30000000 : 32'h22000100);
  end
  int checks=0,errors=0;
  task automatic check(input bit ok,input string name);
    checks++;if(ok)$display("[PASS] %s",name);else begin errors++;$display("[FAIL] %s",name);end
  endtask
  initial begin
    int n;
    $display("CONFIG: TOP=tb_cpu_irq_acceptance CHECKS=10");
    repeat(8)@(negedge clk);rst=0;
    n=0;while(marker!==3'b111 && n<10000)begin @(negedge clk);n++;end
    for(int g=0;g<3;g++)begin
      check(fault_seen[g] && entered[g] && marker[g],$sformatf("IRQ_HANDLER_%0d entered=%b marker=%b",g,entered[g],marker[g]));
      check(!bad_retire[g] && entered[g],$sformatf("IRQ_ORDER_%0d next_before_handler=%b",g,bad_retire[g]));
      check(status_ok[g],$sformatf("IRQ_STATUS_%0d",g));
    end
    check(marker===3'b111 && n<10000,"IRQ_BOUNDED_COMPLETION");
    $display("CHECKS : %0d",checks);$display("ERRORS : %0d",errors);
    $display("RESULT : %s",errors==0 && checks==10 ? "PASS":"FAIL");$finish;
  end
  initial begin #1ms;$display("TB_TIMEOUT IRQ");$display("RESULT : FAIL");$finish;end
endmodule
