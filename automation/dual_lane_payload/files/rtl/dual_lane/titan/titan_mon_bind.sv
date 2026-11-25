`timescale 1ns/1ps
// Test-only adapter for the real merged B0 core. The monitor remains in the
// simulator and observes the P7 subsystem plus its two CPU bridge counters.
module titan_mon_taps (
    input logic clk, rst,
    input logic [5:0] issued, issue_tag, issue_write,
    input logic [5:0][1:0] stale_slots,
    input logic [5:0] epoch_bump, revoke_now, authorized,
    input logic front_head, commit_v,
    input noc_pkg::coord_t front_coord, commit_coord,
    input logic front_tag, commit_tag,
    input logic [31:0] commit_address, commit_data,
    input logic [5:0] response_head, read_delivered,
    input noc_pkg::msg_type_e [5:0] response_msg,
    input logic [5:0][10:0] response_ctl,
    input logic [15:0] timeout_a, timeout_b
);
    import noc_pkg::*;
    logic [5:0] response, response_tag, response_write, read_tag;
    logic [5:0] last_issue_tag;
    logic [5:0][1:0] stale_previous, slot_expired, bridge_timeout;
    logic [15:0] timeout_a_previous, timeout_b_previous;

    always_ff @(posedge clk) begin
        if (rst) begin
            read_tag <= '0;
            last_issue_tag <= '0;
            stale_previous <= '0;
            timeout_a_previous <= '0;
            timeout_b_previous <= '0;
        end else begin
            stale_previous <= stale_slots;
            timeout_a_previous <= timeout_a;
            timeout_b_previous <= timeout_b;
            for (int i = 0; i < 6; i++) begin
                if (issued[i]) last_issue_tag[i] <= issue_tag[i];
                if (response[i] && response_msg[i] == MSG_MEM_RD_RESP)
                    read_tag[i] <= response_tag[i];
            end
        end
    end

    for (genvar i = 0; i < 6; i++) begin : RESP
        assign response[i] = response_head[i] &&
                             (response_msg[i] == MSG_MEM_WR_RESP || response_msg[i] == MSG_MEM_RD_RESP);
        assign response_tag[i] = response_ctl[i][0];
        assign response_write[i] = response_msg[i] == MSG_MEM_WR_RESP;
    end

    assign slot_expired = stale_slots & ~stale_previous;
    always_comb begin
        bridge_timeout = '0;
        bridge_timeout[3][last_issue_tag[3]] = timeout_a != timeout_a_previous;
        bridge_timeout[0][last_issue_tag[0]] = timeout_b != timeout_b_previous;
    end

    titan_finality_monitor monitor(
        .clk, .rst, .issued, .issue_tag, .issue_write, .epoch_bump, .revoke_now, .authorized,
        .front_head(front_head && valid_coord(front_coord)),
        .front_src(3'(coord_to_tile(front_coord))), .front_tag,
        .commit_v(commit_v && valid_coord(commit_coord)),
        .commit_src(3'(coord_to_tile(commit_coord))), .commit_tag, .commit_address, .commit_data,
        .response, .response_tag, .response_write, .read_delivered, .read_tag, .slot_expired, .bridge_timeout
    );
endmodule

// Reuse the existing matched-memory bench and make the bind a compile
// dependency of its test wrapper. The same module types name I-9 and T1.
module tb_titan_mon_b0;
    tb_matched_memory_v10 workload();

    `define TITAN_NI_REQ(N) ((N.tx_accept) && ((N.tx_msg_type) == noc_pkg::MSG_MEM_WR_REQ || (N.tx_msg_type) == noc_pkg::MSG_MEM_RD_REQ))
    `define TITAN_NI_WRITE(N) ((N.tx_msg_type) == noc_pkg::MSG_MEM_WR_REQ)
    `define TITAN_NI_TAG(N) (N.tx_alloc_tag)
    `define TITAN_NI_STALE(N) (N.txn_stale_q)
    `define TITAN_GATE_REVOKE(G) (G.authenticated_head && G.issuer && G.message_type == noc_pkg::MSG_ATTEST_REVOKE && !G.BYPASS_REVOKE)
    `define TITAN_GATE_BUMP(G) (`TITAN_GATE_REVOKE(G) || (G.authenticated_head && G.issuer && G.message_type == noc_pkg::MSG_ATTEST_GRANT && G.control[10:7] == 1))

    bind pq_soc_merged_core titan_mon_taps titan_passive_taps(
        .clk, .rst(u_p7.rst_i),
        .issued({`TITAN_NI_REQ(u_p7.GN[5].PLAIN.ni), `TITAN_NI_REQ(u_p7.l2.W[1].l2.ni), `TITAN_NI_REQ(u_p7.l2.W[0].l2.ni),
                  `TITAN_NI_REQ(u_p7.GN[2].PLAIN.ni), `TITAN_NI_REQ(u_p7.GN[1].PLAIN.ni), `TITAN_NI_REQ(u_p7.GN[0].PLAIN.ni)}),
        .issue_tag({`TITAN_NI_TAG(u_p7.GN[5].PLAIN.ni), `TITAN_NI_TAG(u_p7.l2.W[1].l2.ni), `TITAN_NI_TAG(u_p7.l2.W[0].l2.ni),
                  `TITAN_NI_TAG(u_p7.GN[2].PLAIN.ni), `TITAN_NI_TAG(u_p7.GN[1].PLAIN.ni), `TITAN_NI_TAG(u_p7.GN[0].PLAIN.ni)}),
        .issue_write({`TITAN_NI_WRITE(u_p7.GN[5].PLAIN.ni), `TITAN_NI_WRITE(u_p7.l2.W[1].l2.ni), `TITAN_NI_WRITE(u_p7.l2.W[0].l2.ni),
                  `TITAN_NI_WRITE(u_p7.GN[2].PLAIN.ni), `TITAN_NI_WRITE(u_p7.GN[1].PLAIN.ni), `TITAN_NI_WRITE(u_p7.GN[0].PLAIN.ni)}),
        .stale_slots({`TITAN_NI_STALE(u_p7.GN[5].PLAIN.ni), `TITAN_NI_STALE(u_p7.l2.W[1].l2.ni), `TITAN_NI_STALE(u_p7.l2.W[0].l2.ni),
                  `TITAN_NI_STALE(u_p7.GN[2].PLAIN.ni), `TITAN_NI_STALE(u_p7.GN[1].PLAIN.ni), `TITAN_NI_STALE(u_p7.GN[0].PLAIN.ni)}),
        .epoch_bump({1'b0, `TITAN_GATE_BUMP(u_p7.GN[4].gate), `TITAN_GATE_BUMP(u_p7.GN[3].gate), 3'b0}),
        .revoke_now({1'b0, `TITAN_GATE_REVOKE(u_p7.GN[4].gate), `TITAN_GATE_REVOKE(u_p7.GN[3].gate), 3'b0}),
        .authorized,
        .front_head(u_p7.rhv[2] && u_p7.ms == 2'd0 &&
                    (u_p7.rxmsg[2] == noc_pkg::MSG_MEM_WR_REQ || u_p7.rxmsg[2] == noc_pkg::MSG_MEM_RD_REQ)),
        .front_coord(u_p7.rxsrc[2]), .front_tag(u_p7.rxctl[2][0]),
        .commit_v(u_p7.mem_en && u_p7.mmsg == noc_pkg::MSG_MEM_WR_RESP),
        .commit_coord(u_p7.mdest), .commit_tag(u_p7.request_ctl[0]),
        .commit_address(u_p7.mc == 0 ? u_p7.rxdata[2] : u_p7.maddr), .commit_data(u_p7.mem_wdata),
        .response_head(u_p7.rhv & u_p7.rready), .response_msg(u_p7.rxmsg), .response_ctl(u_p7.rxctl),
        .read_delivered(u_p7.app_rx_data_valid),
        .timeout_a(u_cpu_a.timeout_count), .timeout_b(u_cpu_b.timeout_count)
    );

    `undef TITAN_GATE_BUMP
    `undef TITAN_GATE_REVOKE
    `undef TITAN_NI_STALE
    `undef TITAN_NI_TAG
    `undef TITAN_NI_WRITE
    `undef TITAN_NI_REQ
endmodule
