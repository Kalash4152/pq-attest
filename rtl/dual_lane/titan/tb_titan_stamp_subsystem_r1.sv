`timescale 1ns/1ps
module tb_titan_stamp_subsystem_r1;
    import noc_pkg::*;
    localparam int REQUESTS=1005;
    localparam coord_t MEM_COORD=tile_to_coord(TILE_MEMORY);
    logic clk=0,rst=1;
    always #10 clk=!clk;
    logic [5:0] authorized,app_valid='0,app_payload_valid='0,app_ready,app_payload_ready,app_tx_error;
    coord_t [5:0] app_destination='0;
    msg_type_e [5:0] app_msg='{default:MSG_MEM_RD_REQ};
    logic [5:0][10:0] app_ctl='0,rx_ctl;
    logic [5:0][31:0] app_payload='0;
    logic [5:0] rx_head,rx_last,rx_abort;
    logic [9:0] expected_control[REQUESTS];
    msg_type_e expected_msg[REQUESTS];
    logic actual_tag[REQUESTS];
    int checks,errors,submitted,observed,completed,bad_wire,bad_response;
    logic [5:0] expected_epoch=0;
    logic [31:0] prng=32'h61C88647;
    logic [31:0] commits;
    bit watch_dual, saw_dual;

    pq_noc_subsystem_p7 #(.TB_INJECT(1),.TITAN_MODE(4),.NI_SLOT_TIMEOUT(8192)) dut(
        .clk,.rst,.start_attestation(1'b0),.revoke(1'b0),.trusted_clear(1'b0),
        .boot_epoch('0),.attest_epoch('0),.nonce('0),.root_secret('0),.approved_measurement('0),
        .directed_keys('0),.context_in('0),.context_len('0),.config_data('0),.imem('0),
        .config_len(7'd16),.imem_len(7'd16),.app_valid,.app_payload_valid,.app_ready,.app_payload_ready,
        .app_destination,.app_message(app_msg),.app_control(app_ctl),.app_payload,
        .spoof_raw_valid(1'b0),.spoof_raw_flit('0),.mem_rdata('0),.authorized,.app_tx_error,
        .memory_commits(commits),.app_rx_head_valid(rx_head),.app_rx_last(rx_last),
        .app_rx_abort(rx_abort),.app_rx_control(rx_ctl));

    // Observe the accepted tile-3 wire HEAD before the ingress parser.
    always @(posedge clk) begin
        head_flit_t head;
        if (!rst) begin
            if (watch_dual && dut.l2.W[0].l2.ni.txn_valid_q === 2'b11)
                saw_dual=1;
            if (dut.tile_ov[3] && dut.tile_or[3] &&
                (dut.tile_out[3].flit_type==FLIT_HEAD || dut.tile_out[3].flit_type==FLIT_HEAD_TAIL)) begin
                head=head_flit_t'(dut.tile_out[3].flit_data);
                if (head.msg_type==MSG_MEM_RD_REQ || head.msg_type==MSG_MEM_WR_REQ) begin
                    if (observed>=submitted || observed>=REQUESTS) begin
                        bad_wire++;
                    end else begin
                        if (head.control.raw[10:1] !== expected_control[observed] ||
                            head.msg_type !== expected_msg[observed] || head.dest_x !== MEM_COORD.x || head.dest_y !== MEM_COORD.y) begin
                            bad_wire++;
                            if (bad_wire==1)
                                $display("STAMP_WIRE_DIAG index=%0d actual=%03h expected=%03h",observed,
                                         head.control.raw, {expected_control[observed],1'b0});
                        end
                        actual_tag[observed]=head.control.raw[0];
                    end
                    observed++;
                end
            end
            if (rx_last[3]) completed++;
            if ((rx_head[3] && rx_ctl[3][10]) || rx_abort[3] || app_tx_error[3]) bad_response++;
        end
    end

    task automatic check(input bit ok,input string name);
        checks++;
        if (ok) $display("[PASS] %s",name);
        else begin
            errors++;
            $display("[FAIL] %s sent=%0d observed=%0d completed=%0d errors=%0d/%0d",
                     name,submitted,observed,completed,bad_wire,bad_response);
        end
    endtask

    task automatic begin_grant;
        dut.TBI.gsrc[3]=tile_to_coord(TILE_ROT);
        dut.TBI.gctl[3]=11'h080;
        dut.TBI.gmsg[3]=MSG_ATTEST_GRANT;
        dut.TBI.gv[3]=1;
    endtask

    task automatic revoke;
        begin_grant();
        dut.TBI.gmsg[3]=MSG_ATTEST_REVOKE;
        @(negedge clk);
        dut.TBI.gv[3]=0;
    endtask

    task automatic grant;
        begin_grant();
        @(negedge clk);
        dut.TBI.gv[3]=0;
        expected_epoch++;
    endtask

    task automatic open_request(input bit write_req,input logic [3:0] strobes,input logic [5:0] forged,
                                input logic [5:0] stamp);
        app_msg[3]=write_req?MSG_MEM_WR_REQ:MSG_MEM_RD_REQ;
        app_ctl[3]={strobes,forged,1'b1};
        expected_msg[submitted]=app_msg[3];
        expected_control[submitted]={strobes,stamp};
        submitted++;
        app_valid[3]=1;
    endtask

    task automatic payload_word(input logic [31:0] word_value);
        app_payload[3]=word_value;
        app_payload_valid[3]=1;
        for (int n=0; ; n++) begin
            @(posedge clk);
            if (app_payload_ready[3]) break;
            if (n==8191) $fatal(1,"STAMP payload handshake expired, submitted=%0d",submitted);
        end
        @(negedge clk);
        app_payload_valid[3]=0;
    endtask

    task automatic finish_request(input bit write_req,input logic [31:0] address,input logic [31:0] data);
        for (int n=0; ; n++) begin
            @(posedge clk);
            if (app_ready[3]) break;
            if (n==8191) $fatal(1,"STAMP HEAD handshake expired, submitted=%0d",submitted);
        end
        @(negedge clk);
        app_valid[3]=0;
        payload_word(address);
        if (write_req) payload_word(data);
    endtask

    task automatic send(input bit write_req,input logic [3:0] strobes,input logic [5:0] forged,
                        input logic [31:0] address,input logic [31:0] data);
        open_request(write_req,strobes,forged,expected_epoch);
        finish_request(write_req,address,data);
    endtask

    task automatic drain;
        for (int n=0; ; n++) begin
            @(negedge clk);
            if (completed==submitted) break;
            if (n==8191) $fatal(1,"STAMP response wait expired, submitted=%0d complete=%0d",submitted,completed);
        end
    endtask

    initial begin
        bit stable,write_req;
        logic [5:0] forged,held;
        logic [3:0] strobes;
        int writes_before,random_writes;
        $display("CONFIG: TOP=tb_titan_stamp_subsystem_r1 CHECKS=7");
        repeat(5) @(negedge clk); rst=0;
        app_destination[3]=MEM_COORD;
        repeat(5) @(negedge clk);
        check(dut.tile_epoch[3]===6'd0 && authorized[3]===0,"STAMP_SYS_RESET");

        // Exercise wire epoch zero while still authorized, at the 64th rise.
        repeat(63) begin grant(); revoke(); end
        grant();
        send(1,4'hf,6'd63,32'h22000100,32'h62);
        drain();
        send(0,4'h0,6'd63,32'h22000100,32'h0);
        drain();
        check(authorized[3]===1 && expected_epoch===0 && observed==2 && bad_wire==0,"STAMP_SYS_EPOCH_ZERO");

        // Hold the first write reply at the memory egress until both
        // inner NI slots are allocated. This keeps the old request live
        // across revoke/regrant without blocking or withdrawing the next HEAD.
        force dut.own2_mem=1'b0;
        watch_dual=1;
        send(1,4'hf,6'd63,32'h22000104,32'h1234);
        for (int n=0; commits<2; n++) begin
            @(negedge clk);
            if (n==255) $fatal(1,"STAMP first write did not commit");
        end
        revoke(); grant();
        send(0,4'h0,6'd63,32'h22000104,32'h0);
        for (int n=0; !saw_dual; n++) begin
            @(negedge clk);
            if (n==255) $fatal(1,"STAMP second slot did not allocate");
        end
        force dut.own2_mem=1'b1;
        for (int n=0; ; n++) begin
            @(posedge clk);
            if (dut.tvalid[2] && dut.tready[2]) break;
            if (n==255) $fatal(1,"STAMP held write response did not transfer");
        end
        @(negedge clk);
        release dut.own2_mem;
        drain();
        watch_dual=0;
        $display("STAMP_SYS_TAG_DIAG both_live=%b first=%b second=%b",saw_dual,actual_tag[2],actual_tag[3]);
        check(saw_dual && observed==4 && actual_tag[2]===0 && actual_tag[3]===1 && bad_wire==0,
              "STAMP_SYS_TWO_TAGS");

        // Drive only the app mux's backpressure condition. Both tvalid and
        // g_ready are gated by app_ok, so the NI sees no early HEAD.
        force dut.GN[3].app_ok=1'b0;
        held=expected_epoch;
        open_request(0,4'h0,6'd63,held);
        stable=1;
        for (int i=0;i<50;i++) begin
            if (i==25) begin_grant();
            @(posedge clk);
            stable &= !app_ready[3] && dut.GN[3].app_head_control[6:1]===held;
            @(negedge clk);
            if (i==25) dut.TBI.gv[3]=0;
        end
        $display("STAMP_SYS_STALL_DIAG held=%0d epoch=%0d stalled_cycles=50",held,expected_epoch);
        force dut.GN[3].app_ok=1'b1;
        finish_request(0,32'h22000104,32'h0);
        release dut.GN[3].app_ok;
        drain();
        check(stable && observed==5 && bad_wire==0,"STAMP_SYS_HOLD_50");

        writes_before=int'(commits);
        random_writes=0;
        for (int i=0;i<1000;i++) begin
            if (i%31==0) begin revoke(); grant(); end
            prng^=prng<<13; prng^=prng>>17; prng^=prng<<5;
            write_req=prng[0];
            strobes=write_req ? (prng[4:1] | 4'h1) : 4'h0;
            forged=prng[10:5];
            if (forged==expected_epoch) forged^=6'h20;
            send(write_req,strobes,forged,32'h22000000+(32'(prng[17:11])<<2),prng);
            random_writes+=int'(write_req);
            drain();
        end
        $display("TITAN_STAMP_RANDOM requests=1000 writes=%0d reads=%0d wire=%0d",random_writes,
                 1000-random_writes,observed-5);
        check(submitted==REQUESTS && observed==REQUESTS && bad_wire==0 &&
              random_writes>0 && random_writes<1000,"STAMP_SYS_RANDOM_WIRE");
        check(completed==REQUESTS && bad_response==0,"STAMP_SYS_RESPONSES");
        check(int'(commits)==writes_before+random_writes,"STAMP_SYS_COMMITS");

        $display("CHECKS : %0d",checks);
        $display("ERRORS : %0d",errors);
        $display("RESULT : %s",checks==7 && errors==0 ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #3ms;
        $display("TB_TIMEOUT STAMP");
        $display("RESULT : FAIL");
        $finish;
    end
endmodule
