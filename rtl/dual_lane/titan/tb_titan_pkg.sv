`timescale 1ns/1ps
module tb_titan_pkg;
    import noc_pkg::*;
    import titan_pkg::*;
    localparam int EXPECTED_CHECKS = 2067;
    int checks, errors;

    task automatic check(input bit ok, input string name, input int vector_id);
        checks++;
        if (!ok) begin
            errors++;
            $display("[FAIL] %s vector=%0d", name, vector_id);
        end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_titan_pkg CHECKS=%0d", EXPECTED_CHECKS);
        check(TXN_TAG_WIDTH == 1 && EPOCH_W_MAX == 6, "PROFILE_WIDTH", 0);
        for (int raw = 0; raw < 2048; raw++) begin
            logic [10:0] ctl, expected_response;
            int status, epoch;
            bit err, denied, ok;
            ctl = 11'(raw);
            status = (raw >> 7) & 7;
            epoch = (raw >> 1) & 63;
            err = raw >= 1024;
            denied = err && status >= 1 && status <= 4;
            expected_response = 11'((err ? raw : raw & 127));
            ok = get_epoch(ctl) === 6'(epoch) &&
                 resp_status(ctl) === 3'(status) &&
                 is_denied(ctl) === denied &&
                 mk_resp_ctl(err, titan_status_e'(status), 6'(epoch), ctl[0]) === expected_response;
            for (int replacement = 0; replacement < 64; replacement++) begin
                logic [10:0] updated;
                updated = set_epoch(ctl, 6'(replacement));
                ok &= updated === 11'((raw & 1921) | (replacement << 1));
                ok &= get_epoch(updated) === 6'(replacement);
            end
            check(ok, "RAW_CONTROL", raw);
        end
        for (int tag = 0; tag < 2; tag++)
            check(mk_resp_ctl(1'b1, ST_ERROR, 6'd0, 1'(tag)) === (11'h400 | 11'(tag)),
                  "LEGACY_ERROR", tag);
        for (int msg = 0; msg < 16; msg++)
            check(is_mem_req(msg_type_e'(msg)) === (msg == 0 || msg == 2), "MESSAGE_CLASS", msg);
        $display("TITAN_PKG_CONTROL_VECTORS=2048 EPOCH_REPLACEMENTS=131072 LEGACY_TAGS=2 MESSAGE_CODES=16");
        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %s", checks == EXPECTED_CHECKS && errors == 0 ? "PASS" : "FAIL");
        #1 $finish;
    end
endmodule
