`timescale 1ns/1ps
//=============================================================================
// tb_noc_n81_p7 - N-8.1 containment re-earned on P7 (contract sec. 9; DECISION_REGISTER S2-N81-P7).
// DUT (A): noc_mesh_3x2 (LINK_PIPE=1) + 6 x noc_network_interface_p7, CONTROL_ALLOWED only at tiles 3 (CRYPTO) and 4 (RoT).
// Protected tb_noc_n81.sv is unchanged; this is a fresh P7 bench.
//
// Tiles: CPU0(0,0)=0 CPU1(1,0)=1 MEM(2,0)=2 CRYPTO(0,1)=3 RoT(1,1)=4 SPOOF(2,1)=5. Non-attested: 0,1,2,5.
//
// Checks (frozen from this source before the first run):
//   STRUCT: P7_PACKET_BOUND_OK (noc_p7_pkg elaboration-time per-packet bound compiled into the design)         1
//   EJECT  : eject-port containment at SPOOF under a data P_A (CPU0 -> SPOOF MEM_WR_REQ), two stall shapes
//            A-S0 (block from reset) and A-S1 (accept 2, then block), each: sticky=1, count=1,
//            info={src(0,0),MEM_WR_REQ}, one rx_abort, P_A not delivered complete, persistence 1000 cyc,
//            recovery (a later MEM_WR_REQ delivered), trusted clear = 7 checks each. A slow-drip shape is not
//            applicable to a 3-flit data packet (it completes inside W), so only the two block shapes are used. 2 x 7 = 14
//   NONINT : (C1/C2) SPOOF-ready read completes (1) with no sticky (1); the disjoint route CRY->ROT (R3.E->R4.local,
//            which shares no output with the SPOOF-ward path) is delivered in the SAME latency with the SPOOF
//            backlog present as with the mesh idle (T_A == T_B0, cycle-exact) (1); the shared-router route
//            ROT->MEM (R4.E->R5.N->R2.L, routers R5/R2 shared with the backlog, no shared output) within
//            T_B0 + SH_BOUND = 6 cycles (1)                                                                      4
//   N0     : watchdog off (WDE=0) + SPOOF blocked -> eject interface stalled, nothing accepted, no containment  1
//   BK     : multi-packet backlog (SPOOF stalled; CPU0 and CPU1 each send 3 MEM_WR_REQ to SPOOF, 18 flits >
//            eject depth 12): upstream output lock held (1), containment fired (1), nothing delivered to SPOOF (1);
//            after release every sender NI retired its slots and the locks cleared (1); recovery packet (1)       5
//   LONG   : counterfactual source-list build (N81P7_LONG): WR_REQ has 16 payload words / 17 wire flits, and the
//            per-packet bound is deliberately false. This is NOT production P7. A single packet exceeds the
//            12-entry eject FIFO and creates a held upstream lock before containment releases it.              1  [LONG build only]
// CHECKS: default build (WDE=1) = STRUCT 1 + EJECT 14 + NONINT 4 + BK 5 = 24 (23 until 2026-10-29); N0 build (WDE=0) = STRUCT 1 + N0 1 = 2;
// LONG build (define N81P7_LONG) = STRUCT 1 + LONG 1 = 2.
//=============================================================================
`ifndef N81_W
  `define N81_W 16
`endif
`ifndef N81_WDE
  `define N81_WDE 1
`endif
module tb_noc_n81_p7 #(parameter int W = `N81_W, parameter bit WDE = `N81_WDE);
  localparam int SH_BOUND = 6;   // shared-router case: 2 shared routers x 3-flit packet
  import noc_pkg::*;
  import noc_p7_pkg::*;
  localparam int NT = 6;
  localparam int T_CPU0=0, T_CPU1=1, T_MEM=2, T_CRY=3, T_ROT=4, T_SPF=5;
  logic clk = 0; logic rst; always #5 clk = ~clk;

  flit_t [NT-1:0] m_in_flit, m_out_flit; logic [NT-1:0] m_in_valid, m_in_ready, m_out_valid, m_out_ready;
  noc_mesh_3x2 #(.LINK_PIPE(1'b1)) mesh (.clk, .rst,
    .tile_in_flit(m_in_flit), .tile_in_valid(m_in_valid), .tile_in_ready(m_in_ready),
    .tile_out_flit(m_out_flit), .tile_out_valid(m_out_valid), .tile_out_ready(m_out_ready));

  logic tx_valid[NT], tx_ready[NT]; coord_t tx_dest[NT]; msg_type_e tx_msg[NT]; logic [10:0] tx_ctl[NT];
  logic [FLIT_WIDTH-1:0] tx_pd[NT]; logic tx_pv[NT], tx_pr[NT]; logic tx_err[NT];
  coord_t rx_src[NT], rx_dst[NT]; msg_type_e rx_msg[NT]; logic [10:0] rx_ctl[NT]; logic [4:0] rx_len[NT];
  logic rx_hv[NT]; logic [FLIT_WIDTH-1:0] rx_pd[NT]; logic rx_pv[NT], rx_pl[NT], rx_ready[NT];
  logic rx_perr[NT], rx_lerr[NT], rx_abort[NT];
  logic st_clr[NT], c_sticky[NT], f_sticky[NT]; logic [7:0] c_cnt[NT], f_cnt[NT]; logic [9:0] c_info[NT];
  logic tx_busy[NT], rx_busy[NT];

  // per-instance locals (XSim packed-port assertion workaround, S1_NOTES sec. 5a)
  for (genvar g = 0; g < NT; g++) begin : GN
    logic l_tv,l_tr,l_pv,l_pr,l_te,l_txv,l_txr,l_rxv,l_rxr,l_hv,l_rpv,l_rpl,l_rr,l_mv,l_pe,l_le,l_ab,l_clr,l_cs,l_fs,l_tb,l_rb;
    coord_t l_td,l_rs,l_rd; msg_type_e l_tm,l_rm; logic [10:0] l_tc,l_rc; logic [4:0] l_rl;
    logic [FLIT_WIDTH-1:0] l_tpd,l_rpd; flit_t l_txf,l_rxf; logic [7:0] l_cc,l_fc; logic [9:0] l_ci;
    assign l_tv=tx_valid[g]; assign tx_ready[g]=l_tr; assign l_td=tx_dest[g]; assign l_tm=tx_msg[g]; assign l_tc=tx_ctl[g];
    assign l_tpd=tx_pd[g]; assign l_pv=tx_pv[g]; assign tx_pr[g]=l_pr; assign tx_err[g]=l_te;
    assign m_in_flit[g]=l_txf; assign m_in_valid[g]=l_txv; assign l_txr=m_in_ready[g];
    assign l_rxf=m_out_flit[g]; assign l_rxv=m_out_valid[g]; assign m_out_ready[g]=l_rxr;
    assign rx_src[g]=l_rs; assign rx_dst[g]=l_rd; assign rx_msg[g]=l_rm; assign rx_ctl[g]=l_rc; assign rx_len[g]=l_rl;
    assign rx_hv[g]=l_hv; assign rx_pd[g]=l_rpd; assign rx_pv[g]=l_rpv; assign rx_pl[g]=l_rpl; assign l_rr=rx_ready[g];
    assign rx_perr[g]=l_pe; assign rx_lerr[g]=l_le; assign rx_abort[g]=l_ab; assign l_clr=st_clr[g];
    assign c_sticky[g]=l_cs; assign c_cnt[g]=l_cc; assign c_info[g]=l_ci; assign f_sticky[g]=l_fs; assign f_cnt[g]=l_fc;
    assign tx_busy[g]=l_tb; assign rx_busy[g]=l_rb;
    noc_network_interface_p7 #(.CONTROL_ALLOWED(g==T_CRY||g==T_ROT), .LOCAL_TILE_ID(g), .WD_ENABLE(WDE), .WD_LIMIT(W)) ni (
      .clk,.rst,.tx_valid(l_tv),.tx_ready(l_tr),.tx_dest_coord(l_td),.tx_msg_type(l_tm),.tx_control(l_tc),
      .tx_payload_data(l_tpd),.tx_payload_valid(l_pv),.tx_payload_ready(l_pr),.tx_mac_tag('0),.tx_error(l_te),
      .noc_tx_flit(l_txf),.noc_tx_valid(l_txv),.noc_tx_ready(l_txr),
      .noc_rx_flit(l_rxf),.noc_rx_valid(l_rxv),.noc_rx_ready(l_rxr),
      .rx_src_coord(l_rs),.rx_dest_coord(l_rd),.rx_msg_type(l_rm),.rx_control(l_rc),.rx_length(l_rl),
      .rx_head_valid(l_hv),.rx_payload_data(l_rpd),.rx_payload_valid(l_rpv),.rx_payload_last(l_rpl),
      .rx_ready(l_rr),.rx_mac_tag(),.rx_mac_valid(l_mv),.rx_protocol_error(l_pe),.rx_length_error(l_le),.rx_abort(l_ab),
      .ni_status_clr(l_clr),.ni_contain_sticky(l_cs),.ni_contain_cnt(l_cc),.ni_contain_info(l_ci),
      .ni_framing_sticky(l_fs),.ni_framing_cnt(l_fc),.tx_busy(l_tb),.rx_busy(l_rb));
  end

  int checks=0, errors=0;
  task automatic check(input bit ok, input string s);
    checks++; if (ok) $display("[PASS] %s", s); else begin errors++; $display("[FAIL] %s @ %0t", s, $time); end
  endtask
  int cyc; always @(posedge clk) cyc <= rst ? 0 : cyc+1;

  // RX models: READY / BLOCK / ACCK(n) / DRIP ; plus a responder for MEM (answers RD/WR_REQ)
  typedef enum int {M_READY,M_BLOCK,M_ACCK,M_DRIP} rmode_e;
  rmode_e rmode[NT]; int racc_n[NT], racc[NT];
  int got_n[NT], n_head[NT], n_abort[NT], t_head1[NT]; bit seen_src_spf[NT]; int t_cry_launch, t_rot_launch;
  always @(posedge clk) begin
    for (int t=0;t<NT;t++) begin
      automatic bit off = rx_hv[t]||rx_pv[t];
      automatic int a = racc[t] + ((off && rx_ready[t])?1:0);
      if (rst) begin racc[t]<=0; rx_ready[t]<=(rmode[t]==M_READY); end
      else begin
        racc[t]<=a;
        case (rmode[t]) M_READY: rx_ready[t]<=1; M_BLOCK: rx_ready[t]<=0;
          M_ACCK: rx_ready[t]<=(a<racc_n[t]); M_DRIP: rx_ready[t]<=((cyc%4)==2); default: rx_ready[t]<=1; endcase
      end
    end
  end
  always @(posedge clk) if (!rst) for (int t=0;t<NT;t++) begin
    if (rx_hv[t]&&rx_ready[t]) begin if (n_head[t]==0) t_head1[t]=cyc; n_head[t]++; if (rx_src[t]==tile_to_coord(TILE_SPOOF)) seen_src_spf[t]=1; end
    if (rx_pv[t]&&rx_ready[t]) got_n[t]++;
    if (rx_abort[t]) n_abort[t]++;
  end
  always @(posedge clk) if (!rst && m_in_valid[T_CRY] && m_in_ready[T_CRY] &&
      (m_in_flit[T_CRY].flit_type==FLIT_HEAD||m_in_flit[T_CRY].flit_type==FLIT_HEAD_TAIL) && t_cry_launch<0) t_cry_launch=cyc;
  always @(posedge clk) if (!rst && m_in_valid[T_ROT] && m_in_ready[T_ROT] &&
      (m_in_flit[T_ROT].flit_type==FLIT_HEAD||m_in_flit[T_ROT].flit_type==FLIT_HEAD_TAIL) && t_rot_launch<0) t_rot_launch=cyc;

  // eject / upstream-lock probes (read-only hierarchical)
  wire spf_eject_locked = mesh.GEN_R[T_SPF].r.u_allocator.output_locked[PORT_LOCAL];
  // upstream toward SPOOF(2,1): from MEM(2,0) south output, and from RoT(1,1) east output
  wire up_r2s = mesh.GEN_R[T_MEM].r.u_allocator.output_locked[PORT_SOUTH];
  wire up_r4e = mesh.GEN_R[T_ROT].r.u_allocator.output_locked[PORT_EAST];
  int up_hold; always @(posedge clk) if (!rst && (up_r2s||up_r4e)) up_hold++;

  bit stop_all;
  task automatic send_msg(input int t, input int dst, input msg_type_e m, input int seed, input int nover=-1);
    automatic int n = (nover>=0)?nover:int'(message_payload_flits(m));
    @(negedge clk); tx_dest[t]=tile_to_coord(tile_id_e'(dst)); tx_msg[t]=m; tx_ctl[t]='0; tx_valid[t]=1; #1;
    while (!tx_ready[t]&&!stop_all) begin @(negedge clk); #1; end
    if (stop_all) begin tx_valid[t]=0; return; end
    @(posedge clk); #1; tx_valid[t]=0;
    for (int i=0;i<n;i++) begin
      tx_pd[t]=32'hD0000000+(seed<<8)+i; tx_pv[t]=1; #1;
      while (!tx_pr[t]&&!stop_all) begin @(negedge clk); #1; end
      if (stop_all) break; @(posedge clk); #1;
    end
    tx_pv[t]=0;
  endtask

  task automatic reset_all();
    stop_all=1; rst=1; repeat(4) @(posedge clk);
    for (int t=0;t<NT;t++) begin tx_valid[t]=0; tx_dest[t]='0; tx_msg[t]=MSG_MEM_RD_REQ; tx_ctl[t]=0; tx_pd[t]=0; tx_pv[t]=0; st_clr[t]=0;
      rmode[t]=M_READY; racc_n[t]=0; got_n[t]=0; n_head[t]=0; n_abort[t]=0; seen_src_spf[t]=0; t_head1[t]=-1; end
    t_cry_launch=-1; t_rot_launch=-1;
    up_hold=0; repeat(2) @(posedge clk); stop_all=0; @(negedge clk); rst=0;
  endtask

  task automatic eject_run(input int kind);   // 0 A-S0 (block), 1 A-S1 (accept 2 then block)
    automatic string K = kind==0?"A-S0":"A-S1";
    reset_all();
    case (kind) 0: rmode[T_SPF]=M_BLOCK; default: begin rmode[T_SPF]=M_ACCK; racc_n[T_SPF]=2; end endcase
    send_msg(T_CPU0, T_SPF, MSG_MEM_WR_REQ, 1);     // P_A: 3-flit data packet
    repeat (W+40) @(posedge clk); #1;
    check(c_sticky[T_SPF] && c_cnt[T_SPF]==8'd1, $sformatf("EJECT %s : SPOOF sticky=1 count=1", K));
    check(c_info[T_SPF]=={3'd0,3'd0,4'(MSG_MEM_WR_REQ)}, $sformatf("EJECT %s : info {src(0,0),MEM_WR_REQ}", K));
    check(n_abort[T_SPF]==1, $sformatf("EJECT %s : one rx_abort", K));
    check(got_n[T_SPF] < int'(message_payload_flits(MSG_MEM_WR_REQ)), $sformatf("EJECT %s : P_A not delivered complete (%0d)", K, got_n[T_SPF]));
    repeat (1000) @(posedge clk); #1;
    check(c_sticky[T_SPF] && c_cnt[T_SPF]==8'd1, $sformatf("EJECT %s : sticky persists 1000 cyc", K));
    rmode[T_SPF]=M_READY;
    begin automatic int h0=n_head[T_SPF], p0=got_n[T_SPF], a0=n_abort[T_SPF]; send_msg(T_ROT, T_SPF, MSG_MEM_WR_REQ, 7);
      repeat (300) @(posedge clk); #1;
      check(n_head[T_SPF]==h0+1 && got_n[T_SPF]==p0+2 && n_abort[T_SPF]==a0,
            $sformatf("EJECT %s : recovery - exactly one complete later data packet delivered", K)); end
    @(negedge clk); st_clr[T_SPF]=1; @(negedge clk); st_clr[T_SPF]=0; #1;
    check(!c_sticky[T_SPF] && c_cnt[T_SPF]==0, $sformatf("EJECT %s : trusted clear resets report", K));
    stop_all=1;
  endtask

  initial begin
    $display("CONFIG: TOP=tb_noc_n81_p7 W=%0d WDE=%0d P7_PACKET_BOUND_OK=%0d FIFO_DEPTH=%0d", W, WDE, P7_PACKET_BOUND_OK, FIFO_DEPTH);
`ifdef N81P7_LONG
    check(!P7_PACKET_BOUND_OK && p7_length(MSG_MEM_WR_REQ)==17,
          "LONG_PROFILE : counterfactual WR_REQ is 17 flits and fails the production per-packet bound");
    reset_all(); rmode[T_SPF]=M_BLOCK;
    fork send_msg(T_CPU0, T_SPF, MSG_MEM_WR_REQ, 3); begin end join_none
    repeat (W+200) @(posedge clk); #1;
    $display("STATS LONG WDE=%0d upstream_cycles=%0d upstream_locked=%b aborts=%0d contained=%b payload=%0d",
             WDE, up_hold, up_r2s||up_r4e, n_abort[T_SPF], c_sticky[T_SPF], got_n[T_SPF]);
    check(up_hold>0 && c_sticky[T_SPF] && n_abort[T_SPF]==1 && !up_r2s && !up_r4e,
          "LONG : long data packet held upstream; containment aborted it and released upstream locks");
    stop_all=1;
`else
    check(P7_PACKET_BOUND_OK==1'b1, "STRUCT : P7 per-packet bound holds (p7_length<=FIFO_DEPTH for data, 4-7 control-only)");
    if (WDE) begin
      // ---- eject-port containment (data P_A)
      eject_run(0); eject_run(1);
      // ---- non-interference: a request answered by the MEM responder, SPOOF ready, no sticky anywhere
      reset_all();
      fork
        begin automatic int h0; h0=n_head[T_MEM]; send_msg(T_CPU0, T_MEM, MSG_MEM_RD_REQ, 9);
          repeat (400) @(posedge clk); end
        begin  // MEM responds to the read request it receives
          wait (n_head[T_MEM] > 0); send_msg(T_MEM, T_CPU0, MSG_MEM_RD_RESP, 90); end
      join
      #1;
      check(n_head[T_MEM]>=1 && n_head[T_CPU0]>=1, "NONINT : request delivered to MEM and response to CPU0");
      begin automatic bit any=0; for (int t=0;t<NT;t++) if (c_sticky[t]||f_sticky[t]) any=1;
        check(!any, "NONINT : no tile raised a containment/framing sticky"); end
      // ---- C1/C2 non-interference (T_A == T_B0): a trusted transaction on a route DISJOINT from the SPOOF-ward output.
      // CRY(0,1) -> ROT(1,1) is R3.E -> R4.local; the SPOOF backlog uses R0.E/R1.E/R2.S/R5.L, so the routes are disjoint.
      begin automatic int lat_b0, lat_a;
        reset_all();                                   // baseline, everything idle
        send_msg(T_CRY, T_ROT, MSG_MEM_RD_REQ, 50);
        begin automatic int w=0; while (n_head[T_ROT]==0 && w<2000) begin @(posedge clk); w++; end end
        lat_b0 = t_head1[T_ROT] - t_cry_launch;        // disjoint-route delivery latency, no contention
        reset_all(); rmode[T_SPF]=M_BLOCK;            // SPOOF stalled + backlog toward SPOOF present
        fork
          begin send_msg(T_CPU0, T_SPF, MSG_MEM_WR_REQ, 11); send_msg(T_CPU0, T_SPF, MSG_MEM_WR_REQ, 12); send_msg(T_CPU0, T_SPF, MSG_MEM_WR_REQ, 13); end
          begin send_msg(T_CPU1, T_SPF, MSG_MEM_WR_REQ, 21); send_msg(T_CPU1, T_SPF, MSG_MEM_WR_REQ, 22); send_msg(T_CPU1, T_SPF, MSG_MEM_WR_REQ, 23); end
          begin  // once the backlog holds an upstream lock, launch the disjoint CRY->ROT transaction
            automatic int w=0; while (!(up_r2s||up_r4e) && w<1500) begin @(posedge clk); w++; end
            send_msg(T_CRY, T_ROT, MSG_MEM_RD_REQ, 50);
            begin automatic int ww=0; while (n_head[T_ROT]==0 && ww<2000) begin @(posedge clk); ww++; end end
          end
        join_none
        repeat (W+400) @(posedge clk); #1;
        lat_a = t_head1[T_ROT] - t_cry_launch;
        $display("STATS NONINT lat_baseline=%0d lat_backlog=%0d", lat_b0, lat_a);
        check(n_head[T_ROT]==1 && lat_a==lat_b0,
              $sformatf("NONINT : disjoint CRY->ROT T_A==T_B0 (lat %0d vs %0d), delivered exactly once", lat_a, lat_b0));
        // ---- BK: backlog held an upstream lock; containment fired; no loss / no duplication to non-SPOOF; slots balance
        check(up_hold>0, "BK : an upstream router output-lock toward SPOOF was held under backlog");
        check(c_sticky[T_SPF], "BK : NI containment fired at SPOOF under backlog");
        check(n_head[T_SPF]==0 && got_n[T_SPF]==0, "BK : nothing delivered to the stalled SPOOF");
      end
      // recovery: release SPOOF, let the backlog drain, then every sender NI retires its slots (tx_busy low) and a new
      // packet to SPOOF is delivered
      rmode[T_SPF]=M_READY;
      begin automatic int w=0; while ((tx_busy[T_CPU0]||tx_busy[T_CPU1]) && w<6000) begin @(posedge clk); w++; end end
      repeat (200) @(posedge clk); #1;
      check(!tx_busy[T_CPU0] && !tx_busy[T_CPU1] && !up_r2s && !up_r4e,
            "BK : after release every sender NI retired its slots and upstream locks cleared (no hung slot)");
      begin automatic int h0=n_head[T_SPF]; send_msg(T_ROT, T_SPF, MSG_MEM_WR_REQ, 60);
        begin automatic int w=0; while (n_head[T_SPF]==h0 && w<2000) begin @(posedge clk); w++; end end
        check(n_head[T_SPF]==h0+1, "BK : recovery - a new data packet to SPOOF delivered after drain"); end
      // ---- shared-router case (Kalash 2026-10-29): ROT(1,1) -> MEM(2,0) is R4.E -> R5.N -> R2.L. It shares routers R5 and
      // R2 with the SPOOF backlog (R0.E/R1.E/R2.S/R5.L) but no output port. T_A <= T_B0 + SH_BOUND, SH_BOUND = 2 shared
      // routers x one 3-flit P7 data packet of switch-allocation interference = 6 cycles.
      begin automatic int lat_s0, lat_s;
        reset_all();
        send_msg(T_ROT, T_MEM, MSG_MEM_WR_REQ, 70);
        begin automatic int w=0; while (n_head[T_MEM]==0 && w<2000) begin @(posedge clk); w++; end end
        lat_s0 = t_head1[T_MEM] - t_rot_launch;
        reset_all(); rmode[T_SPF]=M_BLOCK;
        fork
          begin send_msg(T_CPU0, T_SPF, MSG_MEM_WR_REQ, 31); send_msg(T_CPU0, T_SPF, MSG_MEM_WR_REQ, 32); send_msg(T_CPU0, T_SPF, MSG_MEM_WR_REQ, 33); end
          begin send_msg(T_CPU1, T_SPF, MSG_MEM_WR_REQ, 41); send_msg(T_CPU1, T_SPF, MSG_MEM_WR_REQ, 42); send_msg(T_CPU1, T_SPF, MSG_MEM_WR_REQ, 43); end
          begin
            automatic int w=0; while (!(up_r2s||up_r4e) && w<1500) begin @(posedge clk); w++; end
            send_msg(T_ROT, T_MEM, MSG_MEM_WR_REQ, 70);
            begin automatic int ww=0; while (n_head[T_MEM]==0 && ww<2000) begin @(posedge clk); ww++; end end
          end
        join_none
        repeat (W+400) @(posedge clk); #1;
        lat_s = t_head1[T_MEM] - t_rot_launch;
        $display("STATS NONINT_SHARED lat_baseline=%0d lat_backlog=%0d bound=%0d", lat_s0, lat_s, lat_s0 + SH_BOUND);
        check(n_head[T_MEM]==1 && lat_s0 > 0 && lat_s >= lat_s0 && lat_s <= lat_s0 + SH_BOUND,
              $sformatf("NONINT : shared-router ROT->MEM T_A <= T_B0 + %0d (lat %0d vs %0d), delivered exactly once", SH_BOUND, lat_s, lat_s0));
      end
      stop_all=1;
    end
    else begin
      // ---- N0 negative control: watchdog off, SPOOF blocked -> lock held, nothing accepted, no containment
      reset_all(); rmode[T_SPF]=M_BLOCK;
      fork send_msg(T_CPU0, T_SPF, MSG_MEM_WR_REQ, 1); begin end join_none
      repeat (300) @(posedge clk); #1;
      $display("STATS N0 eject_valid=%b eject_ready=%b allocator_locked=%b payload=%0d contained=%b",
               m_out_valid[T_SPF], m_out_ready[T_SPF], spf_eject_locked, got_n[T_SPF], c_sticky[T_SPF]);
      check(m_out_valid[T_SPF] && !m_out_ready[T_SPF] && !c_sticky[T_SPF] && got_n[T_SPF]==0,
            "N0 : watchdog off - SPOOF eject interface stalled, nothing accepted, no containment");
      if(errors==0) $display("N0 EXPECTED-FAIL CONFIRMED (receive interface stalled without containment)");
      stop_all=1;
    end
`endif
    repeat (5) @(posedge clk);
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors==0?"PASS":"FAIL");
    $finish;
  end
  initial begin #20ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
