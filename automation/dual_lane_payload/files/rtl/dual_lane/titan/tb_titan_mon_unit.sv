`timescale 1ns/1ps
module tb_titan_mon_unit #(parameter int CASE_ID = 0);
    localparam int EXPECTED_CHECKS = CASE_ID == 0 ? 11 : 1;
    logic clk = 0, rst = 1;
    always #10 clk = !clk;
    logic [5:0] issued, issue_tag, issue_write;
    logic [5:0] epoch_bump, revoke_now, authorized;
    logic front_head, commit_v;
    logic [2:0] front_src = 3, commit_src = 3;
    logic front_tag, commit_tag;
    logic [31:0] commit_address = 32'h22000100, commit_data = 32'h4;
    logic [5:0] response, response_tag, response_write;
    logic [5:0] read_delivered, read_tag;
    logic [5:0][1:0] slot_expired, bridge_timeout;
    int checks, errors;

    titan_finality_monitor #(.ASSERT_VIOLATIONS(0)) dut (.*);

    task automatic step;
        @(negedge clk);
        issued = '0;
        epoch_bump = '0;
        revoke_now = '0;
        front_head = 0;
        commit_v = 0;
        response = '0;
        read_delivered = '0;
        slot_expired = '0;
        bridge_timeout = '0;
    endtask

    task automatic reset_case;
        rst = 1;
        authorized = '0;
        step();
        rst = 0;
        authorized[3] = 1;
    endtask

    task automatic issue(input bit tag, input bit write_req);
        issued[3] = 1;
        issue_tag[3] = tag;
        issue_write[3] = write_req;
        step();
    endtask

    task automatic definitive(input bit tag, input bit write_req);
        response[3] = 1;
        response_tag[3] = tag;
        response_write[3] = write_req;
        step();
    endtask

    task automatic commit(input bit tag);
        commit_tag = tag;
        commit_v = 1;
        step();
    endtask

    task automatic reached(input bit tag);
        front_tag = tag;
        front_head = 1;
        step();
    endtask

    task automatic verify_counts(input string label, input int p1, p2, p3, p4, sd, m3);
        checks++;
        if ({dut.p1, dut.p2, dut.p3, dut.p4, dut.sd, dut.m3} === {p1, p2, p3, p4, sd, m3})
            $display("[PASS] %s", label);
        else begin
            errors++;
            $display("[FAIL] %s P1=%0d P2=%0d P3=%0d P4=%0d SD=%0d M3=%0d",
                     label, dut.p1, dut.p2, dut.p3, dut.p4, dut.sd, dut.m3);
        end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_titan_mon_unit CHECKS=%0d CASE=%0d", EXPECTED_CHECKS, CASE_ID);
        step();
        if (CASE_ID == 0 || CASE_ID == 1) begin
            reset_case();
            issue(0, 1); reached(0); commit(0); definitive(0, 1);
            verify_counts("MON_CLEAN_WRITE", 0, 0, 0, 0, 0, 0);
        end

        if (CASE_ID == 0 || CASE_ID == 2) begin
            reset_case();
            issue(1, 0); definitive(1, 0);
            read_delivered[3] = 1; read_tag[3] = 1; step();
            verify_counts("MON_CLEAN_READ", 0, 0, 0, 0, 0, 0);
        end

        if (CASE_ID == 0 || CASE_ID == 3) begin
            reset_case();
            issue(0, 1);
            revoke_now[3] = 1; epoch_bump[3] = 1; step();
            authorized[3] = 0; step();
            epoch_bump[3] = 1; step(); authorized[3] = 1;
            commit(0);
            verify_counts("MON_P1_STALE_COMMIT", 1, 0, 0, 0, 0, 0);
        end

        if (CASE_ID == 0 || CASE_ID == 4) begin
            reset_case();
            issue(0, 0); definitive(0, 0);
            authorized[3] = 0;
            read_delivered[3] = 1; read_tag[3] = 0; step();
            verify_counts("MON_P2_REVOKED_READ", 0, 1, 0, 0, 0, 0);
        end

        if (CASE_ID == 0 || CASE_ID == 5) begin
            reset_case();
            issue(1, 1); definitive(1, 1); definitive(1, 1);
            verify_counts("MON_P4_DUPLICATE", 0, 0, 0, 1, 0, 0);
        end

        if (CASE_ID == 0 || CASE_ID == 6) begin
            reset_case();
            issue(0, 1); reached(0);
            slot_expired[3][0] = 1; step();
            verify_counts("MON_SD_SLOT_EXPIRY", 0, 0, 0, 0, 1, 0);
        end

        if (CASE_ID == 0 || CASE_ID == 7) begin
            reset_case();
            issue(1, 1); bridge_timeout[3][1] = 1; step(); commit(1);
            verify_counts("MON_M3_LATE_COMMIT", 0, 0, 0, 0, 0, 1);
        end

        if (CASE_ID == 0 || CASE_ID == 8) begin
            reset_case();
            issue(0, 1); reset_case(); definitive(0, 1);
            verify_counts("MON_RESET_DISCARDS_OPEN", 0, 0, 1, 0, 0, 0);
        end

        if (CASE_ID == 0 || CASE_ID == 9) begin
            reset_case();
            issue(0, 1); issue(1, 0); definitive(1, 0); definitive(0, 1);
            verify_counts("MON_BOTH_TAGS", 0, 0, 0, 0, 0, 0);
        end

        if (CASE_ID == 0 || CASE_ID == 10) begin
            reset_case();
            issue(1, 0); definitive(1, 0); issue(1, 1); definitive(1, 1);
            verify_counts("MON_TAG_REUSE", 0, 0, 0, 0, 0, 0);
        end

        if (CASE_ID == 0 || CASE_ID == 11) begin
            reset_case();
            definitive(0, 0);
            verify_counts("MON_P3_UNKNOWN", 0, 0, 1, 0, 0, 0);
        end
        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %s", (checks == EXPECTED_CHECKS && errors == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule

module tb_titan_mon_case_p1;
    tb_titan_mon_unit #(.CASE_ID(3)) test_case();
endmodule

module tb_titan_mon_case_tag;
    tb_titan_mon_unit #(.CASE_ID(9)) test_case();
endmodule

module tb_titan_mon_case_reset;
    tb_titan_mon_unit #(.CASE_ID(8)) test_case();
endmodule
