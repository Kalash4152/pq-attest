module clean_trace_observer (
    input logic clk, rst, authorized, app_accept,
    input logic issue, issue_tag, commit, commit_tag,
    input logic [31:0] address, data,
    input logic delivered, response_tag,
    input logic [1:0] slots
);
    timeunit 1ns;
    timeprecision 1ps;
    integer fd;
    logic [1:0] previous;
    initial begin
        fd = $fopen("results/g0/local_independent_events.csv", "w");
        if (fd == 0) $fatal(1, "Cannot open passive trace");
        $fdisplay(fd, "cycle,event,tag,address,data,authorized");
    end
    always @(posedge clk) begin
        if (rst) previous <= '0;
        else begin
            if (authorized) $display("CLEAN_SAMPLE %0d %b %b %b", $time/20, slots, delivered, issue);
            if (app_accept) $fdisplay(fd, "%0d,APP_ACCEPT,,,,%b", $time/20, authorized);
            if (issue) $fdisplay(fd, "%0d,NI_ISSUE,%b,,,%b", $time/20, issue_tag, authorized);
            if (commit) $fdisplay(fd, "%0d,COMMIT,%b,%08h,%08h,%b", $time/20, commit_tag, address, data, authorized);
            if (delivered) $fdisplay(fd, "%0d,DELIVERY,%b,,,%b", $time/20, response_tag, authorized);
            for (int i=0; i<2; i++) begin
                if (previous[i] && !slots[i])
                    $fdisplay(fd, "%0d,RETIRED,%0d,,,%b", $time/20, i, authorized);
            end
            previous <= slots;
        end
    end
    final $fclose(fd);
endmodule

bind tb_clean_txn clean_trace_observer observation (
    .clk(clk), .rst(rst), .authorized(authorized[3]),
    .app_accept(app_valid[3] && app_ready[3]),
    .issue(dut.u_subsystem_mon.issued[3]), .issue_tag(dut.u_subsystem_mon.issue_tag[3]),
    .commit(dut.u_subsystem_mon.commit_v), .commit_tag(dut.u_subsystem_mon.commit_tag),
    .address(dut.u_subsystem_mon.commit_address), .data(dut.u_subsystem_mon.commit_data),
    .delivered(dut.u_subsystem_mon.response[3]), .response_tag(dut.u_subsystem_mon.response_tag[3]),
    .slots(dut.l2.W[0].l2.ni.txn_valid_q)
);

