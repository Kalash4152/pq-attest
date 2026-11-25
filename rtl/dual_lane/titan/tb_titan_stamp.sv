`timescale 1ns/1ps
module tb_titan_stamp #(parameter int CASE_ID=0);
    import noc_pkg::*;
    localparam int EXPECTED = CASE_ID == 0 ? 5 : 1;
    logic clk=0,rst=1,valid=0,ready=0;
    always #10 clk=!clk;
    logic [5:0] epoch=0;
    logic [10:0] input_ctl=11'h6ff,output_ctl;
    msg_type_e msg=MSG_MEM_WR_REQ;
    int checks,errors;

    titan_epoch_stamp dut(.clk,.rst,.valid,.ready,.message_type(msg),
        .app_control(input_ctl),.epoch,.stamped_control(output_ctl));

    task automatic reset_case;
        rst=1; valid=0; ready=0; msg=MSG_MEM_WR_REQ; epoch=0;
        @(negedge clk); rst=0;
    endtask

    task automatic check(input bit ok,input string name);
        checks++;
        if (ok) $display("[PASS] %s",name);
        else begin errors++; $display("[FAIL] %s ctl=%03h epoch=%0d",name,output_ctl,epoch); end
    endtask

    initial begin
        bit stable;
        $display("CONFIG: TOP=tb_titan_stamp CHECKS=%0d CASE=%0d",EXPECTED,CASE_ID);
        @(negedge clk);
        if (CASE_ID == 0 || CASE_ID == 1) begin
            reset_case(); epoch=6'd2; valid=1; stable=1;
            for (int i=0;i<50;i++) begin
                if (i==25) epoch=6'd9;
                @(posedge clk);
                stable &= output_ctl[6:1]===6'd2;
                @(negedge clk);
            end
            ready=1;
            @(posedge clk); stable &= output_ctl[6:1]===6'd2;
            @(negedge clk); #1;
            check(stable && output_ctl[6:1]===6'd9,"STAMP_HOLD");
        end
        if (CASE_ID == 0 || CASE_ID == 2) begin
            reset_case(); msg=MSG_ATTEST_RESPONSE; epoch=6'd7; valid=1; ready=1; #1;
            check(output_ctl===input_ctl,"STAMP_NON_MEMORY");
        end
        if (CASE_ID == 0 || CASE_ID == 3) begin
            reset_case(); valid=1; ready=1; epoch=6'd12; #1;
            check(output_ctl==={input_ctl[10:7],6'd12,input_ctl[0]},"STAMP_OVERWRITE");
        end
        if (CASE_ID == 0) begin
            reset_case(); valid=1; epoch=6'd5;
            @(negedge clk); rst=1; epoch=6'd8;
            @(negedge clk); rst=0; #1;
            check(output_ctl[6:1]===6'd8,"STAMP_RESET_HELD_HEAD");
            reset_case(); valid=1; epoch=6'd15;
            @(negedge clk); valid=0; epoch=6'd19;
            @(negedge clk); valid=1; #1;
            check(output_ctl[6:1]===6'd19,"STAMP_WITHDRAWAL");
        end
        $display("CHECKS : %0d",checks);
        $display("ERRORS : %0d",errors);
        $display("RESULT : %s",checks==EXPECTED && errors==0 ? "PASS" : "FAIL");
        $finish;
    end
endmodule

module tb_titan_stamp_no_hold;
    tb_titan_stamp #(.CASE_ID(1)) run_case();
endmodule
module tb_titan_stamp_non_memory;
    tb_titan_stamp #(.CASE_ID(2)) run_case();
endmodule
module tb_titan_stamp_trust_app;
    tb_titan_stamp #(.CASE_ID(3)) run_case();
endmodule
