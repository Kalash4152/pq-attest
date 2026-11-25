`timescale 1ns/1ps
module tb_titan_epoch_subsystem_r1;
    import noc_pkg::*;
    logic clk=0, rst=1;
    always #10 clk=!clk;
    int checks, errors;
    logic [5:0] authorized;

    pq_noc_subsystem_p7 #(.TB_INJECT(1),.TITAN_MODE(4)) dut(
        .clk,.rst,.start_attestation(1'b0),.revoke(1'b0),.trusted_clear(1'b0),
        .boot_epoch('0),.attest_epoch('0),.nonce('0),.root_secret('0),.approved_measurement('0),
        .directed_keys('0),.context_in('0),.context_len('0),.config_data('0),.imem('0),
        .config_len(7'd16),.imem_len(7'd16),.app_valid('0),.app_payload_valid('0),
        .app_destination('0),.app_message('{default:MSG_MEM_RD_REQ}),
        .app_control('0),.app_payload('0),.spoof_raw_valid(1'b0),.spoof_raw_flit('0),
        .mem_rdata('0),.authorized);

    task automatic check(input bit ok, input string name);
        checks++;
        if (ok) $display("[PASS] %s",name);
        else begin errors++; $display("[FAIL] %s",name); end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_titan_epoch_subsystem_r1 CHECKS=4");
        repeat (5) @(negedge clk); rst=0;
        repeat (5) @(negedge clk);
        check(dut.tile_epoch==='0 && authorized==='0,"EPOCH_MODE4_RESET");
        dut.TBI.gsrc[3]=tile_to_coord(TILE_ROT);
        dut.TBI.gctl[3]=11'h080;
        dut.TBI.gmsg[3]=MSG_ATTEST_GRANT;
        dut.TBI.gv[3]=1;
        @(negedge clk);
        check(authorized[3]===1 && dut.tile_epoch[3]===6'd1,"EPOCH_MODE4_GRANT");
        dut.TBI.gmsg[3]=MSG_ATTEST_REVOKE;
        @(negedge clk);
        dut.TBI.gv[3]=0;
        check(authorized[3]===0 && dut.tile_epoch[3]===6'd1,"EPOCH_MODE4_REVOKE");
        repeat (3) @(negedge clk);
        check(dut.tile_epoch==={12'b0,6'd1,18'b0} && dut.tile_epoch_wrap==='0,"EPOCH_MODE4_LOCAL_ONLY");
        $display("CHECKS : %0d",checks);
        $display("ERRORS : %0d",errors);
        $display("RESULT : %s",checks==4 && errors==0 ? "PASS" : "FAIL");
        $finish;
    end
endmodule
