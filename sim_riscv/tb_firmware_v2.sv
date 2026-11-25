`timescale 1ns/1ps
// I-20: 12 frozen checks; two real CPU wrappers, qualified v2 image, controlled app responder.
module tb_firmware_v2;
 import noc_pkg::*;
 logic clk=0,rst=1;always #10 clk=~clk;
 `include "demo_fw_v2.svh"
 `include "closure_profile.svh"
 logic av[2],pv[2],hv[2],dv[2],last[2],uart[2];
 coord_t dest[2],src[2];msg_type_e msg[2],rmsg[2];logic[10:0]ctl[2],rc[2];
 logic[31:0]pay[2],rd[2],p0[2],p1[2];int packets[2];coord_t pd[2];msg_type_e pm[2];logic[10:0]pc[2];
 logic auth=0;logic[7:0]gpio[2];logic[511:0]meas[2];logic[6:0]mlen[2];logic mv[2];
 for(genvar g=0;g<2;g++)begin:gi
  cpu_tile_noc #(.TILE_ID(g==0?3:0)) dut(
   .clk,.rst,.app_valid_o(av[g]),.app_ready_i(1'b1),.app_destination_o(dest[g]),.app_message_o(msg[g]),.app_control_o(ctl[g]),
   .app_payload_o(pay[g]),.app_payload_valid_o(pv[g]),.app_payload_ready_i(1'b1),.app_tx_error_i(1'b0),
   .app_rx_head_valid_i(hv[g]),.app_rx_src_i(src[g]),.app_rx_msg_i(rmsg[g]),.app_rx_control_i(rc[g]),
   .app_rx_data_i(rd[g]),.app_rx_data_valid_i(dv[g]),.app_rx_last_i(last[g]),.app_rx_abort_i(1'b0),
   .authorized_i(g==0?auth:1'b0),.grant_done_i(1'b0),.attest_failed_i(1'b0),.attest_req_o(),
   .meas_imem_o(meas[g]),.meas_imem_len_o(mlen[g]),.meas_valid_o(mv[g]),.uart_tx_o(uart[g]),.gpio_o(gpio[g]));
  ctn_responder rsp(.clk,.rst,.app_valid(av[g]),.app_dest(dest[g]),.app_msg(msg[g]),.app_ctl(ctl[g]),
   .app_payload(pay[g]),.app_pvalid(pv[g]),.rx_hv(hv[g]),.rx_src(src[g]),.rx_msg(rmsg[g]),.rx_ctl(rc[g]),
   .rx_data(rd[g]),.rx_dv(dv[g]),.rx_last(last[g]),.pkts(packets[g]),.p_dest(pd[g]),.p_msg(pm[g]),.p_ctl(pc[g]),.p_w0(p0[g]),.p_w1(p1[g]));
  initial for(int k=0;k<DEMO_FW_V2_N;k++)dut.u_mem.imem_inst.mem[k]=DEMO_FW_V2[k];
 end
 string text[2];
 for(genvar g=0;g<2;g++)begin:rx
  initial begin text[g]="";wait(!rst);forever begin
   logic[7:0]ch;@(negedge uart[g]);repeat(651)@(posedge clk);
   for(int b=0;b<8;b++)begin ch[b]=uart[g];repeat(434)@(posedge clk);end
   text[g]={text[g],ch};
  end end
 end
 function automatic bit contains(input string s,input string sub);
  for(int i=0;i+sub.len()<=s.len();i++)if(s.substr(i,i+sub.len()-1)==sub)return 1;return 0;
 endfunction
 int checks=0,errors=0;
 task automatic check(input bit ok,input string name);
  checks++;if(ok)$display("[PASS] %s",name);else begin errors++;$display("[FAIL] %s",name);end
 endtask
 initial begin
  int n,before_packets;
  $display("CONFIG: TOP=tb_firmware_v2 CHECKS=12");repeat(8)@(negedge clk);rst=0;repeat(300)@(negedge clk);auth=1;
  n=0;while((gpio[0][3:0]!==4'd1 || gpio[1][3:0]!==4'd2) && n<400000)begin @(negedge clk);n++;end
  check(gpio[0][3:0]===4'd1,"V2_ADMITTED");check(gpio[1][3:0]===4'd2,"V2_REFUSED");
  check(gi[1].dut.u_tile.cpu.irq_active==0 && gi[1].dut.u_tile.cpu.cpuregs[21]==2,"V2_IRQ_RETURNS");
  check(packets[0]==2 && packets[1]==0,"V2_INITIAL_ACCOUNTING");
  check(gi[0].dut.u_mem.dmem_inst.mem[0]>0 && gi[0].dut.u_mem.dmem_inst.mem[0]<4096,"V2_CYCLE_WORKLOAD");
  check(mv[0] && mlen[0]==64 && meas[0]===CLOSURE_IMEM,"V2_MEASURED_WINDOW");
  before_packets=packets[0];auth=0;
  n=0;while(gpio[0][3:0]!==4'd5 && n<400000)begin @(negedge clk);n++;end
  check(gpio[0][3:0]===4'd5,"V2_POST_REVOKE_REFUSED");
  check(packets[0]==before_packets,"V2_NO_REVOKED_NETWORK");
  auth=1;n=0;while(gpio[0][3:0]!==4'd7 && n<400000)begin @(negedge clk);n++;end
  check(gpio[0][3:0]===4'd7 && packets[0]==4,"V2_RECOVERY");
  // GPIO acknowledges enqueue, not serial drain. Wait for the complete expected
  // line with an explicit upper bound; retain exact text checks below.
  n=0;
  while(!contains(text[0],"PASS T3 RECOVERED\n") && n<200000)begin @(negedge clk);n++;end
  check(contains(text[0],"PASS T3 cycles=") && contains(text[0],"PASS T3 REVOKED\n") && contains(text[0],"PASS T3 RECOVERED\n"),"V2_T3_UART");
  check(text[1]=="PASS T0 REFUSED OK\n","V2_T0_UART");
  check(!contains(text[0],"FAIL") && !contains(text[1],"FAIL"),"V2_NO_FAILURE_OUTPUT");
  $display("UART0=%s UART1=%s",text[0],text[1]);
  $display("CHECKS : %0d",checks);$display("ERRORS : %0d",errors);$display("RESULT : %s",errors==0 && checks==12?"PASS":"FAIL");$finish;
 end
 initial begin #60ms;$display("TB_TIMEOUT V2");$display("RESULT : FAIL");$finish;end
endmodule
