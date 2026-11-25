`timescale 1ns/1ps
//=============================================================================
// tb_noc_n81 - N-8.1 SPOOF containment system testbench (FD-1 B')
//
// Spec : docs/decisions/N-8.1-ni-endpoint-containment.md rev 1, sec.9
// DUT  : noc_mesh_3x2 (LINK_PIPE=1, EJECT_PIPE=1) + 6 x noc_network_interface
//        (WD_ENABLE = N81_WDE, WD_LIMIT = N81_W). No router file is modified.
//
// Topology (XY, y+ = SOUTH), router i = y*3 + x:
//   R0 CPU0(0,0) -E-> R1 CPU1(1,0) -E-> R2 MEMORY(2,0)
//                                          |S
//   R3 CRYPTO(0,1) -E-> R4 RoT(1,1)       R5 SPOOF(2,1)
//
//   P_A : CPU0 -> SPOOF  ATTEST_RESPONSE  holds R0.E, R1.E, R2.S, R5.L
//   C1a,b: CPU0 -> CPU1   MEM_WR_REQ       contends R0.E (after P_A)
//   C2a,b: CPU1 -> MEMORY MEM_WR_REQ       contends R1.E (injected at T_trig)
//   C3a,b: CRYPTO -> RoT  MEM_RD_REQ       disjoint control (injected at T_trig)
//   T_trig = first cycle R1's output_locked[EAST] is set (P_A HEAD at R1.E).
//
// One simulation = B0 (reference, SPOOF tile always ready) followed by the
// attack runs selected by N81_RUNS, all from identical resets and schedules:
//   bit0 A-S0  SPOOF rx_ready = 0 from reset
//   bit1 A-S1  SPOOF accepts HEAD + 3 payload, then 0
//   bit2 A-S2  SPOOF accepts 1 cycle in 4 (slow drip)
//   bit3 N0    negative control: SPOOF blocked, build with WD_ENABLE = 0
//
// Acceptance (sec.9.5 test acceptance bound, delta computed from the packet list):
//   T_A(c) - T_B0(c) <= W + delta(M)  for C1a,C1b,C2a,C2b
//   T_A(c) == T_B0(c)                 for C3a,C3b  (+ resource disjointness)
//   A-S0 release order R0.E < R1.E < R2.S < R5.L
//   drain: FIFOs/eject/link/locks/credits idle, all NIs idle
//   SPOOF sticky = 1, count = 1, info = {0,0,ATTEST_RESPONSE}; others 0;
//   sticky persists 1000 cycles, survives good traffic, cleared by ni_status_clr.
// N0: at T_bound C1/C2 incomplete, C3 complete, 4 locks held, sticky 0, no
//   P_A progress for 256 cycles -> "N0 EXPECTED-FAIL CONFIRMED".
//
// Build (Verilator):  -GW=16 / +define+N81_WDE=0 / +define+N81_RUNS=8 / +define+PQ_MAC_ON
// Build (XSim):       xvlog -d N81_W=16 -d N81_WDE=0 -d N81_RUNS=8 -d PQ_MAC_ON
//=============================================================================

`ifndef N81_W
  `define N81_W 16
`endif
`ifndef N81_WDE
  `define N81_WDE 1
`endif
`ifndef N81_RUNS
  `define N81_RUNS 7
`endif

module tb_noc_n81 #(
    parameter int W    = `N81_W,
    parameter bit WDE  = `N81_WDE,
    parameter int RUNS = `N81_RUNS
);

    import noc_pkg::*;

    localparam int NT = 6;
    localparam int T_CPU0 = 0, T_CPU1 = 1, T_MEM = 2, T_CRY = 3, T_ROT = 4, T_SPF = 5;

    logic clk = 1'b0;
    logic rst;
    always #5 clk = ~clk;

    //-------------------------------------------------------------------------
    // Mesh
    //-------------------------------------------------------------------------
    flit_t [NT-1:0] m_in_flit;
    logic  [NT-1:0] m_in_valid, m_in_ready;
    flit_t [NT-1:0] m_out_flit;
    logic  [NT-1:0] m_out_valid, m_out_ready;

    noc_mesh_3x2 #(.LINK_PIPE(1'b1)) mesh (
        .clk, .rst,
        .tile_in_flit (m_in_flit),  .tile_in_valid (m_in_valid),  .tile_in_ready (m_in_ready),
        .tile_out_flit(m_out_flit), .tile_out_valid(m_out_valid), .tile_out_ready(m_out_ready)
    );

    //-------------------------------------------------------------------------
    // Tile <-> NI signals
    //-------------------------------------------------------------------------
    logic                    tx_valid   [NT], tx_ready [NT];
    coord_t                  tx_dest    [NT];
    msg_type_e               tx_msg     [NT];
    logic [10:0]             tx_control [NT];
    logic [FLIT_WIDTH-1:0]   tx_pdata   [NT];
    logic                    tx_pvalid  [NT], tx_pready [NT];
    logic [MAC_TAG_BITS-1:0] tx_mac     [NT];
    logic                    tx_error   [NT];

    coord_t                  rx_src [NT], rx_dst [NT];
    msg_type_e               rx_msg [NT];
    logic [10:0]             rx_ctl [NT];
    logic [4:0]              rx_len [NT];
    logic                    rx_hv  [NT];
    logic [FLIT_WIDTH-1:0]   rx_pd  [NT];
    logic                    rx_pv  [NT], rx_pl [NT];
    logic                    rx_ready [NT];
    logic [MAC_TAG_BITS-1:0] rx_mt  [NT];
    logic                    rx_mv  [NT], rx_perr [NT], rx_lerr [NT], rx_abort [NT];

    logic                    st_clr [NT];
    logic                    c_sticky [NT], f_sticky [NT];
    logic [7:0]              c_cnt [NT], f_cnt [NT];
    logic [9:0]              c_info [NT];
    logic                    tx_busy [NT], rx_busy [NT];

    for (genvar g = 0; g < NT; g++) begin : GN
        noc_network_interface #(
            .LOCAL_TILE_ID (g),
            .WD_ENABLE     (WDE),
            .WD_LIMIT      (W)
        ) ni (
            .clk, .rst,
            .tx_valid(tx_valid[g]), .tx_ready(tx_ready[g]),
            .tx_dest_coord(tx_dest[g]), .tx_msg_type(tx_msg[g]), .tx_control(tx_control[g]),
            .tx_payload_data(tx_pdata[g]), .tx_payload_valid(tx_pvalid[g]),
            .tx_payload_ready(tx_pready[g]),
            .tx_mac_tag(tx_mac[g]), .tx_error(tx_error[g]),
            .noc_tx_flit(m_in_flit[g]), .noc_tx_valid(m_in_valid[g]), .noc_tx_ready(m_in_ready[g]),
            .noc_rx_flit(m_out_flit[g]), .noc_rx_valid(m_out_valid[g]), .noc_rx_ready(m_out_ready[g]),
            .rx_src_coord(rx_src[g]), .rx_dest_coord(rx_dst[g]), .rx_msg_type(rx_msg[g]),
            .rx_control(rx_ctl[g]), .rx_length(rx_len[g]), .rx_head_valid(rx_hv[g]),
            .rx_payload_data(rx_pd[g]), .rx_payload_valid(rx_pv[g]), .rx_payload_last(rx_pl[g]),
            .rx_ready(rx_ready[g]), .rx_mac_tag(rx_mt[g]), .rx_mac_valid(rx_mv[g]),
            .rx_protocol_error(rx_perr[g]), .rx_length_error(rx_lerr[g]), .rx_abort(rx_abort[g]),
            .ni_status_clr(st_clr[g]),
            .ni_contain_sticky(c_sticky[g]), .ni_contain_cnt(c_cnt[g]), .ni_contain_info(c_info[g]),
            .ni_framing_sticky(f_sticky[g]), .ni_framing_cnt(f_cnt[g]),
            .tx_busy(tx_busy[g]), .rx_busy(rx_busy[g])
        );
    end

    //-------------------------------------------------------------------------
    // Check bookkeeping
    //-------------------------------------------------------------------------
    int checks = 0, errors = 0;
    task automatic check(input bit cond, input string what);
        checks++;
        if (cond) $display("[PASS] %s", what);
        else begin errors++; $display("[FAIL] %s @ %0t", what, $time); end
    endtask

    //-------------------------------------------------------------------------
    // Cycle counter (0 at the first cycle after reset release)
    //-------------------------------------------------------------------------
    int cyc;
    always @(posedge clk) begin
        if (rst) cyc <= 0;
        else     cyc <= cyc + 1;
    end

    //-------------------------------------------------------------------------
    // Packet list (independent of the DUT)
    //-------------------------------------------------------------------------
    localparam int NC = 6;                    // C1a C1b C2a C2b C3a C3b
    localparam string CNAME [NC] = '{"C1a", "C1b", "C2a", "C2b", "C3a", "C3b"};
    localparam int CSEED [NC] = '{11, 12, 21, 22, 31, 32};
    localparam int PA_SEED = 1, RV_SEED = 41;

    function automatic logic [FLIT_WIDTH-1:0] pay_word(input int seed, input int i);
        return 32'hA000_0000 + (seed << 8) + i;
    endfunction

    function automatic logic [MAC_TAG_BITS-1:0] mac_of(input int seed);
        logic [MAC_TAG_BITS-1:0] t;
        for (int i = 0; i < MAC_TAG_BITS / FLIT_WIDTH; i++)
            t[i*FLIT_WIDTH +: FLIT_WIDTH] = 32'hC0DE_0000 + (seed << 8) + i;
        return t;
    endfunction

    // delta(M): each competing packet that crosses an input shared with P_A
    // (C1 at R1.W, C2 at R2.W) contributes its full length (sec.9.5, AF1/AF2).
    function automatic int delta_m();
        return 4 * int'(message_length(MSG_MEM_WR_REQ));
    endfunction

    //-------------------------------------------------------------------------
    // Tile RX models
    //-------------------------------------------------------------------------
    typedef enum int {M_READY, M_BLOCK, M_ACCK, M_DRIP} rmode_e;
    rmode_e rmode [NT];
    int     racc_n [NT];         // M_ACCK: offered cycles to accept
    int     racc   [NT];

    // Fixed-size logs (arrays of queues are avoided on purpose: simulator
    // support for per-element push_back on unpacked arrays of queues varies).
    localparam int GMAX = 64, TMAX = 8;
    logic [FLIT_WIDTH-1:0] got_w [NT][GMAX];
    int got_n [NT];
    int n_head [NT], n_abort [NT], n_mac [NT];
    int term_w [NT][TMAX];       // cycles a terminator was accepted by the NI
    int term_n [NT];
    int spf_acc;                 // flits accepted by the SPOOF NI
    int t0_spf;                  // first cycle a flit is valid at the SPOOF NI

    always @(posedge clk) begin
        for (int t = 0; t < NT; t++) begin
            automatic bit offered = rx_hv[t] || rx_pv[t];
            automatic int a = racc[t] + ((offered && rx_ready[t]) ? 1 : 0);
            if (rst) begin
                racc[t]     <= 0;
                rx_ready[t] <= (rmode[t] == M_READY);
            end
            else begin
                racc[t] <= a;
                case (rmode[t])
                    M_READY: rx_ready[t] <= 1'b1;
                    M_BLOCK: rx_ready[t] <= 1'b0;
                    M_ACCK : rx_ready[t] <= (a < racc_n[t]);
                    M_DRIP : rx_ready[t] <= ((cyc % 4) == 2);
                    default: rx_ready[t] <= 1'b1;
                endcase
            end
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            for (int t = 0; t < NT; t++) begin
                if (rx_hv[t] && rx_ready[t]) n_head[t]++;
                if (rx_pv[t] && rx_ready[t]) begin
                    if (got_n[t] < GMAX) got_w[t][got_n[t]] = rx_pd[t];
                    got_n[t]++;
                end
                if (rx_mv[t])                n_mac[t]++;
                if (rx_abort[t])             n_abort[t]++;
                if (m_out_valid[t] && m_out_ready[t] &&
                    ((m_out_flit[t].flit_type == FLIT_TAIL) ||
                     (m_out_flit[t].flit_type == FLIT_HEAD_TAIL)))
                begin
                    if (term_n[t] < TMAX) term_w[t][term_n[t]] = cyc;
                    term_n[t]++;
                end
            end
            if (m_out_valid[T_SPF] && m_out_ready[T_SPF]) spf_acc++;
            if (m_out_valid[T_SPF] && (t0_spf < 0))        t0_spf = cyc;
        end
    end

    //-------------------------------------------------------------------------
    // Router probes (hierarchical, read-only)
    //-------------------------------------------------------------------------
    logic r_idle [NT];
    logic l_idle [NT];

    for (genvar g = 0; g < NT; g++) begin : GP
        always_comb begin
            r_idle[g] = !mesh.GEN_R[g].r.eject_wr_q &&
                         mesh.GEN_R[g].r.eject_empty &&
                        (mesh.GEN_R[g].r.u_allocator.output_locked == '0);
            for (int i = 0; i < NUM_PORTS * NUM_VC; i++)
                if (!mesh.GEN_R[g].r.fifo_empty[i]) r_idle[g] = 1'b0;
            for (int p = 0; p < NUM_PORTS; p++)
                for (int v = 0; v < NUM_VC; v++)
                    if (int'(mesh.GEN_R[g].r.u_credit_control.credit_count[p][v]) != 4)
                        r_idle[g] = 1'b0;
            l_idle[g] = !(mesh.GEN_R[g].qv_n || mesh.GEN_R[g].qv_s ||
                          mesh.GEN_R[g].qv_e || mesh.GEN_R[g].qv_w);
        end
    end

    wire lk_r0e = mesh.GEN_R[0].r.u_allocator.output_locked[PORT_EAST];
    wire lk_r1e = mesh.GEN_R[1].r.u_allocator.output_locked[PORT_EAST];
    wire lk_r2s = mesh.GEN_R[2].r.u_allocator.output_locked[PORT_SOUTH];
    wire lk_r5l = mesh.GEN_R[5].r.u_allocator.output_locked[PORT_LOCAL];

    int  trig_cyc;
    int  rel_r0e, rel_r1e, rel_r2s, rel_r5l;
    int  set_r0e, set_r1e, set_r2s, set_r5l;
    int  mv_cnt;                // flits moved on R0.E / R1.E / R2.S outputs
    int  dj_bad, dj_r4w;        // disjointness monitor
    bit  dj_on;

    always @(posedge clk) begin
        if (!rst) begin
            if (lk_r1e && trig_cyc < 0) trig_cyc = cyc;
            if (lk_r0e && set_r0e < 0) set_r0e = cyc;
            if (lk_r1e && set_r1e < 0) set_r1e = cyc;
            if (lk_r2s && set_r2s < 0) set_r2s = cyc;
            if (lk_r5l && set_r5l < 0) set_r5l = cyc;
            if (!lk_r0e && set_r0e >= 0 && rel_r0e < 0) rel_r0e = cyc;
            if (!lk_r1e && set_r1e >= 0 && rel_r1e < 0) rel_r1e = cyc;
            if (!lk_r2s && set_r2s >= 0 && rel_r2s < 0) rel_r2s = cyc;
            if (!lk_r5l && set_r5l >= 0 && rel_r5l < 0) rel_r5l = cyc;
            if (mesh.out_v_e[0] || mesh.out_v_e[1] || mesh.out_v_s[2]) mv_cnt++;
            if (dj_on) begin
                // C3 uses only R3.L-in -> R3.E -> R4.W-in -> R4.L. Nothing may
                // enter R3/R4 from N or E, and R4.W-in carries only C3 flits.
                if (mesh.in_v_n[3] || mesh.in_v_e[3] || mesh.in_v_n[4] || mesh.in_v_e[4])
                    dj_bad++;
                if (mesh.in_v_w[4]) dj_r4w++;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Tile TX driver (store-and-forward NI: request, then fill)
    //-------------------------------------------------------------------------
    bit stop_all;

    task automatic send_msg(input int t, input int dst_tile, input msg_type_e m, input int seed);
        int n;
        n = int'(message_payload_flits(m));
        @(negedge clk);
        tx_dest[t]    = tile_to_coord(tile_id_e'(dst_tile));
        tx_msg[t]     = m;
        tx_control[t] = '0;
        tx_mac[t]     = mac_of(seed);
        tx_valid[t]   = 1'b1;
        #1;
        while (!tx_ready[t] && !stop_all) begin @(negedge clk); #1; end
        if (stop_all) begin tx_valid[t] = 1'b0; return; end
        @(posedge clk); #1;
        tx_valid[t] = 1'b0;
        for (int i = 0; i < n; i++) begin
            tx_pdata[t]  = pay_word(seed, i);
            tx_pvalid[t] = 1'b1;
            #1;
            while (!tx_pready[t] && !stop_all) begin @(negedge clk); #1; end
            if (stop_all) break;
            @(posedge clk); #1;
        end
        tx_pvalid[t] = 1'b0;
    endtask

    //-------------------------------------------------------------------------
    // Reset + clear
    //-------------------------------------------------------------------------
    task automatic reset_all();
        stop_all = 1'b1;
        rst = 1'b1;
        repeat (4) @(posedge clk);
        for (int t = 0; t < NT; t++) begin
            tx_valid[t] = 0; tx_dest[t] = '0; tx_msg[t] = MSG_MEM_RD_REQ; tx_control[t] = '0;
            tx_pdata[t] = '0; tx_pvalid[t] = 0; tx_mac[t] = '0; st_clr[t] = 0;
            rmode[t] = M_READY; racc_n[t] = 0;
            got_n[t] = 0; term_n[t] = 0;
            n_head[t] = 0; n_abort[t] = 0; n_mac[t] = 0;
        end
        spf_acc = 0; t0_spf = -1; trig_cyc = -1; mv_cnt = 0; dj_bad = 0; dj_r4w = 0; dj_on = 1'b1;
        set_r0e = -1; set_r1e = -1; set_r2s = -1; set_r5l = -1;
        rel_r0e = -1; rel_r1e = -1; rel_r2s = -1; rel_r5l = -1;
        repeat (2) @(posedge clk);
        stop_all = 1'b0;
        @(negedge clk); rst = 1'b0;
    endtask

    //-------------------------------------------------------------------------
    // One run: identical schedule, SPOOF behaviour by kind
    //   0 B0, 1 A-S0, 2 A-S1, 3 A-S2, 4 N0
    //-------------------------------------------------------------------------
    localparam string KNAME [5] = '{"B0", "A-S0", "A-S1", "A-S2", "N0"};
    int T_b0 [NC];
    int T_run [NC];
    int T_bound;

    function automatic int comp_cyc(input int c);
        // destination tile and index of c among that tile's terminators
        int d, k;
        d = (c < 2) ? T_CPU1 : (c < 4) ? T_MEM : T_ROT;
        k = c % 2;
        return (term_n[d] > k) ? term_w[d][k] : -1;
    endfunction

    function automatic bit all_competing_done();
        for (int c = 0; c < NC; c++) if (comp_cyc(c) < 0) return 1'b0;
        return 1'b1;
    endfunction

    function automatic bit drained();
        for (int g = 0; g < NT; g++) begin
            if (!r_idle[g] || !l_idle[g] || rx_busy[g] || tx_busy[g]) return 1'b0;
            if (mesh.out_v_n[g] || mesh.out_v_s[g] || mesh.out_v_e[g] ||
                mesh.out_v_w[g] || mesh.out_v_l[g]) return 1'b0;
        end
        return 1'b1;
    endfunction

    task automatic check_payloads(input string tag);
        logic [FLIT_WIDTH-1:0] e [$];
        bit ok;
        int dsts [3] = '{T_CPU1, T_MEM, T_ROT};
        for (int j = 0; j < 3; j++) begin
            e.delete();
            for (int c = 2*j; c < 2*j + 2; c++) begin
                msg_type_e m = (c < 4) ? MSG_MEM_WR_REQ : MSG_MEM_RD_REQ;
                for (int i = 0; i < int'(message_payload_flits(m)); i++) e.push_back(pay_word(CSEED[c], i));
            end
            ok = (got_n[dsts[j]] == e.size());
            for (int i = 0; ok && i < e.size(); i++) if (got_w[dsts[j]][i] !== e[i]) ok = 1'b0;
            check(ok, $sformatf("%s : tile %0d payload scoreboard (%0d words, got %0d)",
                                tag, dsts[j], e.size(), got_n[dsts[j]]));
        end
    endtask

    task automatic run_one(input int kind);
        string K;
        int lim;
        K = KNAME[kind];
        $display("\n===== RUN %s  (W=%0d WDE=%0d MAC_FLITS=%0d delta=%0d) =====",
                 K, W, WDE, MAC_FLITS, delta_m());
        reset_all();
        case (kind)
            0: rmode[T_SPF] = M_READY;
            1, 4: rmode[T_SPF] = M_BLOCK;
            2: begin rmode[T_SPF] = M_ACCK; racc_n[T_SPF] = 4; end
            3: rmode[T_SPF] = M_DRIP;
        endcase

        fork
            begin
                send_msg(T_CPU0, T_SPF,  MSG_ATTEST_RESPONSE, PA_SEED);
                send_msg(T_CPU0, T_CPU1, MSG_MEM_WR_REQ, CSEED[0]);
                send_msg(T_CPU0, T_CPU1, MSG_MEM_WR_REQ, CSEED[1]);
            end
            begin
                while (trig_cyc < 0 && !stop_all) @(posedge clk);
                if (!stop_all) begin
                    fork
                        begin
                            send_msg(T_CPU1, T_MEM, MSG_MEM_WR_REQ, CSEED[2]);
                            send_msg(T_CPU1, T_MEM, MSG_MEM_WR_REQ, CSEED[3]);
                        end
                        begin
                            send_msg(T_CRY, T_ROT, MSG_MEM_RD_REQ, CSEED[4]);
                            send_msg(T_CRY, T_ROT, MSG_MEM_RD_REQ, CSEED[5]);
                        end
                    join
                end
            end
        join_none

        //--------------------------------------------------------------- N0
        if (kind == 4) begin
            while (cyc < T_bound) @(posedge clk);
            #1;
            check(comp_cyc(0) < 0 && comp_cyc(1) < 0 && comp_cyc(2) < 0 && comp_cyc(3) < 0,
                  $sformatf("N0 : at T_bound=%0d C1a/C1b/C2a/C2b NOT complete", T_bound));
            check(comp_cyc(4) >= 0 && comp_cyc(5) >= 0, "N0 : C3a/C3b complete (disjoint control)");
            check(lk_r0e && lk_r1e && lk_r2s && lk_r5l, "N0 : R0.E R1.E R2.S R5.L still locked");
            check(!c_sticky[T_SPF] && c_cnt[T_SPF] == 0, "N0 : no containment (watchdog disabled)");
            begin
                int mv0 = mv_cnt, acc0 = spf_acc;
                repeat (256) @(posedge clk);
                #1;
                check(mv_cnt == mv0 && acc0 == 0 && spf_acc == 0,
                      "N0 : no P_A progress for 256 cycles, SPOOF accepted nothing");
            end
            if (comp_cyc(0) < 0 && comp_cyc(2) < 0 && lk_r0e && lk_r1e && lk_r2s && lk_r5l)
                $display("N0 EXPECTED-FAIL CONFIRMED (deterministic: locks held, competitors blocked)");
            stop_all = 1'b1;
            return;
        end

        //--------------------------------------------------------------- B0 / A
        lim = 6000;
        while (!(all_competing_done() && !rx_busy[T_SPF]) && cyc < lim) @(posedge clk);
        repeat (32) @(posedge clk);
        #1;
        dj_on = 1'b0;
        check(all_competing_done(), $sformatf("%s : all 6 competing packets completed", K));
        check(drained(), $sformatf("%s : network drained (FIFOs, eject, links, locks, credits, NIs)", K));
        check_payloads(K);
        check(dj_bad == 0 && dj_r4w == 2 * int'(message_length(MSG_MEM_RD_REQ)),
              $sformatf("%s : C3 resource disjointness (bad %0d, R4.W flits %0d)", K, dj_bad, dj_r4w));
        for (int g = 0; g < NT; g++)
            if (g != T_SPF)
                check(!c_sticky[g] && !f_sticky[g], $sformatf("%s : tile %0d no sticky", K, g));
        check(!f_sticky[T_SPF], $sformatf("%s : SPOOF no framing event", K));

        for (int c = 0; c < NC; c++) T_run[c] = comp_cyc(c);
        for (int c = 0; c < NC; c++)
            $display("TIME %s %s T=%0d", K, CNAME[c], T_run[c]);
        $display("TIME %s t0=%0d trig=%0d rel R0.E=%0d R1.E=%0d R2.S=%0d R5.L=%0d",
                 K, t0_spf, trig_cyc, rel_r0e, rel_r1e, rel_r2s, rel_r5l);

        if (kind == 0) begin
            int mx = 0;
            check(!c_sticky[T_SPF], "B0 : SPOOF no containment");
            check(n_head[T_SPF] == 1 && got_n[T_SPF] == int'(message_payload_flits(MSG_ATTEST_RESPONSE)),
                  "B0 : P_A delivered complete to SPOOF");
            for (int c = 0; c < NC; c++) begin
                T_b0[c] = T_run[c];
                if (T_run[c] > mx) mx = T_run[c];
            end
            T_bound = mx + W + delta_m();
            $display("TIME B0 T_bound=%0d", T_bound);
            return;
        end

        // ---- attack runs
        check(c_sticky[T_SPF] && c_cnt[T_SPF] == 8'd1,
              $sformatf("%s : SPOOF containment sticky = 1, count = 1", K));
        check(c_info[T_SPF] == {3'd0, 3'd0, 4'(MSG_ATTEST_RESPONSE)},
              $sformatf("%s : contain_info = {src (0,0), ATTEST_RESPONSE}", K));
        check(n_abort[T_SPF] == 1, $sformatf("%s : one rx_abort at SPOOF", K));
        check(got_n[T_SPF] < int'(message_payload_flits(MSG_ATTEST_RESPONSE)),
              $sformatf("%s : P_A not delivered complete (%0d words)", K, got_n[T_SPF]));
        for (int c = 0; c < 4; c++) begin
            int d = T_run[c] - T_b0[c];
            $display("DELTA %s W=%0d %s %0d", K, W, CNAME[c], d);
            check(d <= W + delta_m(),
                  $sformatf("%s : %s T_A-T_B0 = %0d <= W+delta = %0d", K, CNAME[c], d, W + delta_m()));
        end
        for (int c = 4; c < NC; c++)
            check(T_run[c] == T_b0[c],
                  $sformatf("%s : %s cycle-exact vs B0 (%0d vs %0d)", K, CNAME[c], T_run[c], T_b0[c]));
        if (kind == 1)
            check(rel_r0e < rel_r1e && rel_r1e < rel_r2s && rel_r2s < rel_r5l,
                  "A-S0 : release order R0.E < R1.E < R2.S < R5.L");

        // persistence
        repeat (1000) @(posedge clk);
        #1;
        check(c_sticky[T_SPF] && c_cnt[T_SPF] == 8'd1, $sformatf("%s : sticky persists 1000 cycles", K));

        // resume: good traffic to SPOOF is delivered, does not clear the report
        rmode[T_SPF] = M_READY;
        begin
            int h0 = n_head[T_SPF];
            send_msg(T_ROT, T_SPF, MSG_ATTEST_REVOKE, RV_SEED);
            lim = cyc + 500;
            while (n_head[T_SPF] == h0 && cyc < lim) @(posedge clk);
            repeat (16) @(posedge clk);
            #1;
            check(n_head[T_SPF] == h0 + 1 && !rx_busy[T_SPF],
                  $sformatf("%s : SPOOF resumes - REVOKE delivered after containment", K));
        end
        check(c_sticky[T_SPF] && c_cnt[T_SPF] == 8'd1, $sformatf("%s : good traffic does not clear", K));
        @(negedge clk); st_clr[T_SPF] = 1'b1;
        @(negedge clk); st_clr[T_SPF] = 1'b0;
        #1;
        check(!c_sticky[T_SPF] && c_cnt[T_SPF] == 0, $sformatf("%s : trusted clear resets the report", K));
    endtask

    //-------------------------------------------------------------------------
    // Vacuity: at the moment of containment, the contention really existed
    //-------------------------------------------------------------------------
    int cur_kind;
    always @(posedge clk) begin
        if (!rst && GN[T_SPF].ni.rx_expire) begin
            if (cur_kind == 1) begin
                check(lk_r0e && lk_r1e && comp_cyc(0) < 0 && comp_cyc(2) < 0,
                      "A-S0 vacuity : at expiry R0.E, R1.E held by P_A; C1a, C2a still waiting");
            end
            else if (cur_kind == 2 || cur_kind == 3) begin
                check(lk_r1e && comp_cyc(2) < 0,
                      $sformatf("%s vacuity : at expiry R1.E held; C2a still waiting", KNAME[cur_kind]));
            end
            $display("EXPIRE %s cyc=%0d t0=%0d", KNAME[cur_kind], cyc, t0_spf);
            if (cur_kind == 1)
                check(cyc == t0_spf + W - 1,
                      $sformatf("A-S0 : expiry exactly at t0+W-1 (%0d vs %0d)", cyc, t0_spf + W - 1));
        end
    end

    //-------------------------------------------------------------------------
    // Main
    //-------------------------------------------------------------------------
    initial begin
        $display("============================================================");
        $display(" tb_noc_n81  W=%0d WDE=%0d RUNS=%0d MAC_FLITS=%0d delta=%0d",
                 W, WDE, RUNS, MAC_FLITS, delta_m());
        $display("============================================================");
        if (!WDE && (RUNS & 7) != 0)
            $display("[WARN] attack runs requested with WD_ENABLE=0 - skipped (only N0 is valid)");
        if (WDE && RUNS[3])
            $display("[WARN] N0 requested with WD_ENABLE=1 - skipped (N0 needs WD_ENABLE=0)");
        cur_kind = 0;  run_one(0);
        for (int k = 1; k <= 3; k++)
            if (WDE && RUNS[k-1]) begin cur_kind = k; run_one(k); end
        if (!WDE && RUNS[3]) begin cur_kind = 4; run_one(4); end
        stop_all = 1'b1;
        repeat (5) @(posedge clk);
        $display("============================================================");
        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("CONFIG : W=%0d WDE=%0d RUNS=%0d MAC_FLITS=%0d", W, WDE, RUNS, MAC_FLITS);
        $display("RESULT : %s", (errors == 0) ? "PASS" : "FAIL");
        $display("============================================================");
        $finish;
    end

    initial begin
        #20ms;
        $display("RESULT : FAIL (global timeout)");
        $finish;
    end

endmodule
