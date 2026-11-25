`timescale 1ns/1ps
module tb_titan_epoch_r1 #(parameter int CASE_ID=0);
    import noc_pkg::*;
    localparam int EXPECTED = CASE_ID == 0 ? 11 : 1;
    logic clk=0,rst=1,head=0,authorized,trusted_fail=0,trusted_timeout=0;
    always #10 clk=!clk;
    coord_t src=tile_to_coord(TILE_ROT);
    msg_type_e msg=MSG_ATTEST_GRANT;
    logic [10:0] ctl=11'h080;
    logic [5:0] epoch;
    logic wrap;
    int checks, errors;

    noc_attest_gate #(.TILE(3)) gate_i(.clk,.rst,.app_valid(1'b0),.app_msg(MSG_MEM_RD_REQ),
        .ni_ready(1'b0),.authenticated_head(head),.source(src),.message_type(msg),.control(ctl),
        .trusted_fail,.trusted_timeout,.trusted_clear(1'b0),.authorized);
    titan_epoch_tracker_r1 dut(.clk,.rst,.authorized,.trusted_fail,.epoch_o(epoch),.epoch_wrap_o(wrap));

    task automatic step;
        @(negedge clk);
        head=0; trusted_fail=0; trusted_timeout=0;
    endtask
    task automatic drive(input msg_type_e kind);
        head=1; msg=kind;
        step();
    endtask
    task automatic check(input bit ok,input string name);
        checks++;
        if(ok) $display("[PASS] %s",name);
        else begin errors++; $display("[FAIL] %s epoch=%0d auth=%b wrap=%b",name,epoch,authorized,wrap); end
    endtask
    initial begin
        bit correct;
        $display("CONFIG: TOP=tb_titan_epoch_r1 CHECKS=%0d CASE=%0d",EXPECTED,CASE_ID);
        step(); rst=0;
        if(CASE_ID==0) begin
            check(epoch===0 && authorized===0 && wrap===0,"EDGE_RESET");
            ctl=11'h100; drive(MSG_ATTEST_GRANT);
            check(authorized===0 && epoch===0,"EDGE_BAD_GRANT");
            ctl=11'h080; src=tile_to_coord(TILE_SPOOF); drive(MSG_ATTEST_GRANT);
            check(authorized===0 && epoch===0,"EDGE_ISSUER");
            src=tile_to_coord(TILE_ROT);
        end
        if(CASE_ID==0 || CASE_ID==1) begin
            drive(MSG_ATTEST_GRANT);
            if(CASE_ID==0) check(authorized===1 && epoch===1,"EDGE_GRANT_IMMEDIATE");
            drive(MSG_ATTEST_REVOKE);
            check(authorized===0 && epoch===1,"EDGE_REVOKE");
        end
        if(CASE_ID==0 || CASE_ID==2) begin
            rst=1; step(); rst=0;
            drive(MSG_ATTEST_GRANT); drive(MSG_ATTEST_GRANT); step(); step();
            check(authorized===1 && epoch===1,"EDGE_HELD");
        end
        if(CASE_ID==0 || CASE_ID==3) begin
            rst=1; step(); rst=0;
            drive(MSG_ATTEST_GRANT);
            trusted_fail=1; #1;
            correct=(epoch===1);
            step();
            check(correct && authorized===0 && epoch===1,"EDGE_TRUSTED");
        end
        if(CASE_ID==0) begin
            drive(MSG_ATTEST_REVOKE);
            check(authorized===0 && epoch===1,"EDGE_REDUNDANT_REVOKE");
            trusted_fail=1; drive(MSG_ATTEST_GRANT);
            check(authorized===1 && epoch===2,"EDGE_GRANT_PRIORITY");
            trusted_timeout=1; step();
            check(authorized===0 && epoch===2,"EDGE_TIMEOUT");
            rst=1; step(); rst=0; correct=1;
            for(int i=1;i<=64;i++) begin
                drive(MSG_ATTEST_GRANT);
                correct &= (epoch===6'(i) && wrap===(i==64));
                drive(MSG_ATTEST_REVOKE);
                correct &= (epoch===6'(i) && wrap===0);
            end
            check(correct,"EDGE_WRAP_64_RISES");
        end
        $display("CHECKS : %0d",checks);
        $display("ERRORS : %0d",errors);
        $display("RESULT : %s",checks==EXPECTED && errors==0 ? "PASS" : "FAIL");
        $finish;
    end
endmodule
module tb_titan_epoch_r1_revoke;
    tb_titan_epoch_r1 #(.CASE_ID(1)) test_case();
endmodule
module tb_titan_epoch_r1_held_high;
    tb_titan_epoch_r1 #(.CASE_ID(2)) test_case();
endmodule
module tb_titan_epoch_r1_trusted_fail;
    tb_titan_epoch_r1 #(.CASE_ID(3)) test_case();
endmodule
