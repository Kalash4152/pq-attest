`timescale 1ns/1ps
module tb_titan_epoch #(parameter int CASE_ID=0);
    import noc_pkg::*;
    localparam int EXPECTED = CASE_ID == 0 ? 13 : 1;
    logic clk=0, rst=1, head=0, trusted_fail=0, trusted_timeout=0;
    always #10 clk=!clk;
    coord_t src=tile_to_coord(TILE_ROT);
    msg_type_e msg=MSG_ATTEST_GRANT;
    logic [10:0] ctl='0;
    logic update_v, is_grant, bypass_update, bypass_grant, plain_update, plain_grant;
    logic [5:0] epoch, bypass_epoch, plain_epoch;
    logic wrap, bypass_wrap, plain_wrap, authorized, bypass_authorized;
    int checks, errors;

    noc_attest_gate #(.TILE(3)) gate_i(.clk,.rst,.app_valid(1'b0),.app_msg(MSG_MEM_RD_REQ),
        .ni_ready(1'b0),.authenticated_head(head),.source(src),.message_type(msg),.control(ctl),
        .trusted_fail,.trusted_timeout,.trusted_clear(1'b0),.authorized);
    noc_attest_gate #(.TILE(3),.BYPASS_REVOKE(1)) bypass_i(
        .clk,.rst,.app_valid(1'b0),.app_msg(MSG_MEM_RD_REQ),.ni_ready(1'b0),
        .authenticated_head(head),.source(src),.message_type(msg),.control(ctl),
        .trusted_fail,.trusted_timeout,.trusted_clear(1'b0),.authorized(bypass_authorized));

    titan_epoch_gate_event event_i(.authenticated_head(head),.source(src),.message_type(msg),
        .control(ctl),.auth_update_v(update_v),.auth_is_grant(is_grant));
    titan_epoch_gate_event #(.BYPASS_REVOKE(1)) event_bypass_i(
        .authenticated_head(head),.source(src),.message_type(msg),.control(ctl),
        .auth_update_v(bypass_update),.auth_is_grant(bypass_grant));
    // Plain NIs never deliver authenticated control to a non-attestable gate.
    // Exercise the decoder rejection directly without violating that gate assertion.
    titan_epoch_gate_event #(.ATTESTABLE(0)) event_plain_i(
        .authenticated_head(head),.source(src),.message_type(msg),.control(ctl),
        .auth_update_v(plain_update),.auth_is_grant(plain_grant));
    titan_epoch_tracker tracker_i(.clk,.rst,.auth_update_v(update_v),.auth_is_grant(is_grant),
        .epoch_o(epoch),.epoch_wrap_o(wrap));
    titan_epoch_tracker bypass_tracker_i(.clk,.rst,.auth_update_v(bypass_update),
        .auth_is_grant(bypass_grant),.epoch_o(bypass_epoch),.epoch_wrap_o(bypass_wrap));
    titan_epoch_tracker plain_tracker_i(.clk,.rst,.auth_update_v(plain_update),
        .auth_is_grant(plain_grant),.epoch_o(plain_epoch),.epoch_wrap_o(plain_wrap));

    task automatic step;
        @(negedge clk);
        head=0;
        trusted_fail=0;
        trusted_timeout=0;
    endtask

    task automatic reset_case;
        rst=1;
        step();
        rst=0;
    endtask

    task automatic drive(input msg_type_e kind, input coord_t sender, input logic [3:0] stat);
        head=1; msg=kind; src=sender; ctl={stat,7'b0};
    endtask

    task automatic grant;
        drive(MSG_ATTEST_GRANT,tile_to_coord(TILE_ROT),4'd1);
        step();
    endtask

    task automatic check(input bit ok, input string name);
        checks++;
        if (ok) $display("[PASS] %s",name);
        else begin
            errors++;
            $display("[FAIL] %s epoch=%0d wrap=%b authorized=%b",name,epoch,wrap,authorized);
        end
    endtask

    initial begin
        bit wrap_ok;
        $display("CONFIG: TOP=tb_titan_epoch CHECKS=%0d CASE=%0d",EXPECTED,CASE_ID);
        reset_case();
        if (CASE_ID == 0) check({epoch,bypass_epoch,plain_epoch,wrap,authorized} === '0,"EPOCH_RESET");

        if (CASE_ID == 0 || CASE_ID == 1) begin
            drive(MSG_ATTEST_GRANT,tile_to_coord(TILE_ROT),4'd2);
            step();
            check(epoch===0 && authorized===0 && gate_i.fault_reason===4'd3,"EPOCH_BAD_GRANT");
        end

        if (CASE_ID == 0) begin
            reset_case();
            drive(MSG_ATTEST_GRANT,tile_to_coord(TILE_SPOOF),4'd1);
            step();
            check(epoch===0 && authorized===0 && gate_i.fault_reason===4'd2,"EPOCH_WRONG_ISSUER");
            grant();
            check(plain_epoch===0 && plain_wrap===0,"EPOCH_NON_ATTESTABLE");
            check(epoch===6'd1 && authorized===1 && wrap===0,"EPOCH_GRANT");
        end

        if (CASE_ID == 0 || CASE_ID == 2) begin
            reset_case(); grant();
            drive(MSG_ATTEST_REVOKE,tile_to_coord(TILE_ROT),4'd0); step();
            check(epoch===6'd2 && authorized===0,"EPOCH_REVOKE");
        end

        if (CASE_ID == 0) begin
            check(bypass_epoch===6'd1 && bypass_authorized===1,"EPOCH_BYPASS_REVOKE");
            reset_case(); grant(); trusted_fail=1; step();
            check(epoch===6'd1 && authorized===0,"EPOCH_TRUSTED_FAIL");
            reset_case(); grant(); grant();
            check(epoch===6'd2 && authorized===1,"EPOCH_CONSECUTIVE_GRANTS");
        end

        if (CASE_ID == 0 || CASE_ID == 3) begin
            reset_case(); wrap_ok=1;
            for (int i=1; i<=64; i++) begin
                grant();
                wrap_ok &= epoch === 6'(i) && wrap === (i==64);
            end
            check(wrap_ok,"EPOCH_MODULO_WRAP");
        end

        if (CASE_ID == 0) begin
            step(); check(epoch===0 && wrap===0,"EPOCH_WRAP_PULSE");
            reset_case();
            drive(MSG_ATTEST_GRANT,tile_to_coord(TILE_ROT),4'd1);
            trusted_fail=1; step();
            check(epoch===6'd1 && authorized===1,"EPOCH_GRANT_PRIORITY");
            trusted_timeout=1; step();
            check(epoch===6'd1 && authorized===0,"EPOCH_TRUSTED_TIMEOUT");
        end
        $display("CHECKS : %0d",checks);
        $display("ERRORS : %0d",errors);
        $display("RESULT : %s",checks==EXPECTED && errors==0 ? "PASS" : "FAIL");
        $finish;
    end
endmodule

module tb_titan_epoch_bad_grant;
    tb_titan_epoch #(.CASE_ID(1)) run_case();
endmodule
module tb_titan_epoch_drop_revoke;
    tb_titan_epoch #(.CASE_ID(2)) run_case();
endmodule
module tb_titan_epoch_early_wrap;
    tb_titan_epoch #(.CASE_ID(3)) run_case();
endmodule
