`timescale 1ns/1ps
module tb_pq_full_chain;
 import noc_pkg::*;
 logic clk=0,rst=1,start_attestation=0,revoke=0;
 always #10 clk=~clk;
 logic [79:0] boot_epoch,attest_epoch;
 logic [127:0] nonce;
 logic [255:0] root_secret,approved_measurement;
 logic [9215:0] directed_keys;
 logic [111:0] context_in;
 logic [3:0] context_len;
 logic [511:0] config_data,imem;
 logic [6:0] config_len,imem_len;
 logic [5:0] app_valid,app_payload_valid,app_ready,app_payload_ready;
 coord_t [5:0] app_destination;
 msg_type_e [5:0] app_message;
 logic [5:0][10:0] app_control;
 logic [5:0][31:0] app_payload;
 logic spoof_raw_valid=0,spoof_raw_ready;
 flit_t spoof_raw_flit;
 logic [5:0] authorized;
 logic rot_busy,grant_done,attestation_failed;
 logic [775:0] endpoint_response,expected_response;
 logic [31:0] memory_commits,memory_last_data,endpoint_rejected,verifier_rejected;
 logic [5:0][31:0] l2_rejected,l2_accepted,gate_faults;
 logic [5:0][3:0] l2_reason;
 pq_noc_subsystem dut(.*);
 `include "full_chain.svh"
 int checks=0,errors=0,cycles=0,grant_seen=0,fail_seen=0;
 flit_t saved_challenge[26];int saved_count=0;
 always @(posedge clk) if(!rst) begin
   cycles++;if(grant_done)grant_seen++;if(attestation_failed)fail_seen++;
   if(saved_count<17 && dut.mesh_iv[4] && dut.mesh_ir[4])begin saved_challenge[saved_count]=dut.mesh_in[4];saved_count++;end
 end
 task automatic check(input bit ok,input string name);
   checks++;$display("[%s] %s",ok?"PASS":"FAIL",name);if(!ok)errors++;
 endtask
 task automatic start;
   @(negedge clk);start_attestation=1;@(negedge clk);start_attestation=0;
 endtask
 task automatic await_authorized;
   int n;n=0;while(!authorized[3]&&n<100000)begin @(negedge clk);n++;end
   if(!authorized[3])$fatal(1,"TB_TIMEOUT authorization");
 endtask
 task automatic app_request;
   @(negedge clk);app_destination[3]=tile_to_coord(TILE_MEMORY);app_message[3]=MSG_MEM_WR_REQ;app_control[3]=11'h780;app_valid[3]=1;
   do begin @(posedge clk);end while(!app_ready[3]);
   @(negedge clk);app_valid[3]=0;app_payload_valid[3]=1;app_payload[3]=32'h82000100;
   do begin @(posedge clk);end while(!app_payload_ready[3]);
   @(negedge clk);app_payload[3]=32'hcafe1234;
   do begin @(posedge clk);end while(!app_payload_ready[3]);
   @(negedge clk);app_payload_valid[3]=0;
 endtask
 task automatic raw_packet(input bit replay_packet);
   int n;head_flit_t h;flit_t f;logic [159:0] fresh;
   fresh={16'b0,BOOT,64'd1};
   n=replay_packet?saved_count:12;
   for(int i=0;i<n;i++)begin
     @(negedge clk);
     if(replay_packet)f=saved_challenge[i];
     else begin
       f='0;f.vc_id=VC_REQUEST;f.flit_type=i==0?FLIT_HEAD:i==11?FLIT_TAIL:FLIT_BODY;
       if(i==0)begin h='0;h.src_x=1;h.src_y=1;h.dest_x=2;h.dest_y=0;h.msg_type=MSG_MEM_WR_REQ;h.length=12;h.control.raw=11'h780;f.flit_data=h;end
       if(i==1)f.flit_data=1;
       if(i>=1&&i<=5)f.flit_data=fresh[(i-1)*32+:32];
       if(i==6)f.flit_data=32'h82000100;
       if(i==7)f.flit_data=32'hdeadbeef;
     end
     spoof_raw_flit=f;spoof_raw_valid=1;
     do begin @(posedge clk);end while(!spoof_raw_ready);
   end
   @(negedge clk);spoof_raw_valid=0;
 endtask
 initial begin
   $display("CONFIG: TOP=tb_pq_full_chain DEMO=1 CLOCK_NS=20");
   app_valid=0;app_payload_valid=0;app_destination='0;app_message='0;app_control=0;app_payload=0;spoof_raw_flit='0;
   load_chain(0);boot_epoch=BOOT;directed_keys=KEYS;
   repeat(6)@(negedge clk);rst=0;
   app_message[3]=MSG_MEM_WR_REQ;app_valid[3]=1;
   repeat(5)@(negedge clk);
   check(!app_ready[3]&&memory_commits==0,"RESET_DATA_BLOCKED");app_valid[3]=0;
   fork start();raw_packet(0);join
   await_authorized();repeat(200)@(negedge clk);
   check(endpoint_response===expected_response,"INDEPENDENT_FULL_776_RESPONSE");
   check(authorized[3]&&grant_seen==1,"TRUSTED_GRANT");
   check(l2_rejected[2]>0&&memory_commits==0,"SPOOF_ZERO_MEMORY_COMMIT");
   check(saved_count==17,"EXPLICIT_CHALLENGE_WIRE_LENGTH");
   app_request();
   repeat(1000)@(negedge clk);
   check(memory_commits==1&&memory_last_data==32'hcafe1234,"AUTHORIZED_MEMORY_WRITE");
   check(dut.GN[3].boundary.ni.txn_valid_q=='0,"AUTHENTICATED_RESPONSE_RETIRES_SLOT");
   begin int before_count;before_count=l2_accepted[3];raw_packet(1);repeat(1000)@(negedge clk);
     check(l2_accepted[3]==before_count&&l2_reason[3]==4,"L2_REPLAY_REJECTED");end
   @(negedge clk);revoke=1;@(negedge clk);revoke=0;repeat(1000)@(negedge clk);
   check(!authorized[3],"TRUSTED_REVOKE");
   app_valid[3]=1;repeat(5)@(negedge clk);check(!app_ready[3]&&memory_commits==1,"REVOKED_DATA_BLOCKED");app_valid[3]=0;
   load_chain(1);config_data[7:0]=8'hff;start();repeat(4000)@(negedge clk);
   check(fail_seen>0&&!authorized[3],"RUNTIME_SUBSTITUTION_REJECTED");
   check(verifier_rejected>0,"VERIFIER_FAULT_VISIBLE");
   load_chain(2);start();await_authorized();repeat(1000)@(negedge clk);
   check(endpoint_response===expected_response&&grant_seen==2,"DISTINCT_TRUSTED_RETRY");
   rst=1;boot_epoch=BOOT+1;repeat(6)@(negedge clk);rst=0;
   check(authorized=='0,"RESET_REVOKES_ALL");
   raw_packet(1);repeat(1000)@(negedge clk);
   check(l2_accepted[3]==0&&l2_reason[3]==3,"RESET_BOOT_REPLAY_REJECTED");
   check(memory_commits==0,"RESET_NO_STALE_MEMORY_COMMIT");
   $display("CHAIN_CYCLES=%0d",cycles);
   $display("CHECKS : %0d",checks);$display("ERRORS : %0d",errors);$display("RESULT : %s",errors==0?"PASS":"FAIL");$finish;
 end
 initial begin #25ms;$fatal(1,"TB_TIMEOUT full chain");end
endmodule
