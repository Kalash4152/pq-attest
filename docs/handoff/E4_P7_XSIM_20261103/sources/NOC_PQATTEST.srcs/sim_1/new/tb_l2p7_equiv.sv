`timescale 1ns/1ps
// Step c (M-F1 rev 7 R7.1-R7.3, R7.6; docs/decisions/STEP_C_DESIGN_P7_L2_SHARED.md sec.4, job l2p7_equiv_ctrl):
// the P7 block rtl/dual_lane/noc_l2_p7_pair.sv (shared l2_kmac_engine + noc_l2_auth_p7 for tiles 3 and 4) against the
// B-2 trimmed wrapper rtl/dual_lane/noc_l2_auth.sv (the accepted rev 6 L2), packet by packet. Compile with PQ_MAC_ON.
//
// Phase 1, TX (control-message vectors): the same message list drives a B-2 tile-4 wrapper and P7 tile 4 (N_TX4
// CHALLENGE / GRANT / REVOKE to tile 3, random control bits and payload) and a B-2 tile-3 wrapper and P7 tile 3
// (N_TX3 RESPONSE to tile 4); random noc_tx_ready on every output. Check per packet: L2P7_TX_WIRE, the P7 wire
// packet equals the B-2 wire packet bit-exactly (HEAD, F0-F4, payload, MAC words, flit types, VC), in order.
// Phase 2, RX: the genuine phase-1 packets plus mutations and foreign packets, fed one at a time (both receivers idle
// and 70 cycles apart) to the B-2 receiver and the P7 receiver of the same tile:
//   tile 3 (N_RX3 = 480): the 300 genuine tile-4 packets; after genuine 3j+1 (j < 100) one of {bit flip of the next
//   genuine, replay of the previous genuine, truncation of the next genuine, the next genuine with its source claim
//   changed to tile 0 or 2} (cycled); after genuine 7k+3 (k < 40) one packet signed by tile 5 with K[5->3] (genuine
//   for the B-2 wrapper) and one tile-4 packet under another boot epoch;
//   tile 4 (N_RX4 = 330): the 200 genuine RESPONSE packets; after genuine 2j+1 (j < 70) a mutation as above; after
//   genuine 6k+2 (k < 30) one RESPONSE signed by tile 5 with K[5->4] and one tile-3 RESPONSE under another epoch.
//   Per packet, L2P7_RX_VERDICT: P7 verdict = mapped B-2 verdict, where the mapping is the P7 rule (R7.1/R7.2):
//     claimed type not control (a flipped type)        -> P7 has no L2 verdict (data plane; the NI decides);
//     claimed source = the peer                        -> identical (accepted, or the same reason 1/2/3/4);
//     claimed source != the peer                       -> reason 1 if B-2 gave reason 1, else reason 5 (non-peer).
//   Per packet, L2P7_RX_DELIVERY: if P7 accepted, its NI delivery (head fields and payload words) equals B-2's; else
//   P7 delivered nothing.
//   Data plane: after each of the first 100 packets of each stream, a plain memory request (RD_REQ or WR_REQ, P7
//   framing) is injected into the P7 receiver while that control packet's slot-P replay runs (or 300 cycles after it
//   when it was not accepted), so the data HEAD meets the replay and must be held, not dropped. L2P7_DATA_RX per data packet (N_DRX = 200): delivered unchanged, in order.
// Phase 3, data TX: each P7 tile sends 50 plain responses (RD_RESP / WR_RESP alternating, random destination in
//   {0, 1, 2, 5}, random control bits). L2P7_DATA_TX per packet (N_DTX = 100): the wire packet equals the plain P7
//   framing computed here (HEAD length 2 / 1, no freshness, no MAC).
// L2P7_A1: no cycle with the engine owner requesting while its job is in flight.
// Coverage (FAIL if weak): L2P7_COVER_ACCEPTED (P7 accepted >= 400), L2P7_COVER_REASONS (P7 reasons 1, 2, 3, 4, 5 each
//   >= 5), L2P7_COVER_SPOOF_SIGNED (>= 40 packets B-2 accepted and P7 refused with reason 5), L2P7_COVER_DATA_HELD
//   (>= 10 data HEADs held at the P7 mesh port during a replay).
// CHECKS = 500 + 2 * 810 + 200 + 100 + 1 + 4 = 2425, frozen before the first run.
// Every wait is bounded. A bound hit prints TB_TIMEOUT and finishes (INVALID, never a pass).
module tb_l2p7_equiv;
  import noc_pkg::*;
  import noc_p7_pkg::*;
  localparam int N_TX4 = 300, N_TX3 = 200, N_RX3 = 480, N_RX4 = 330, N_DRX = 200, N_DTX = 100;
  logic clk = 0, rst = 1;
  always #10 clk = ~clk;
  logic [79:0] epoch = 80'h1A2B_3C4D_5E6F_7081_92A3, epoch_alt = 80'h1A2B_3C4D_5E6F_7081_92A2;
  logic [31:0] lcg = 32'h7E57_0C01;
  function automatic logic [31:0] rnd(); lcg = lcg * 32'd1664525 + 32'd1013904223; return lcg; endfunction
  function automatic coord_t xy(input int t); coord_t c; c = '0; c.x = 3'(t % 3); c.y = 3'(t / 3); return c; endfunction
  int checks = 0, errors = 0, shown = 0;
  task automatic check(input bit ok, input string name);
    checks++; if (!ok) begin errors++; if (shown < 25) begin shown++; $display("[FAIL] %s", name); end end
  endtask
  task automatic timeout(input string w); $display("TB_TIMEOUT %s", w); $finish; endtask
  logic [255:0] K43, K34, K53, K54, KR [12];

  // ---------------- B-2 wrappers: b4, b3 (TX in phase 1, RX in phase 2), s5 (tile 5), a4 / a3 (other boot epoch)
  // index: 0 b4, 1 b3, 2 s5, 3 a4, 4 a3
  logic [1535:0] btk [5], brk [5];
  logic btv [5], btr [5], bpv [5], bpr [5], bnv [5], bntr [5], brv [5], brh [5], brpv [5], brb [5];
  coord_t bdest [5], brs [5]; msg_type_e bmsg [5], brm [5]; logic [10:0] bctl [5], brc [5]; logic [31:0] bpd [5], brpd [5];
  flit_t bnf [5], brf [5]; logic [31:0] brej [5], bacc [5]; logic [3:0] bwhy [5]; logic [4:0] brl [5];
  localparam int BT [5] = '{4, 3, 5, 4, 3};
  for (genvar i = 0; i < 5; i++) begin: B
    noc_l2_auth #(.TILE(BT[i])) u (.clk, .rst, .boot_epoch(i >= 3 ? epoch_alt : epoch), .tx_keys(btk[i]), .rx_keys(brk[i]),
      .tx_valid(btv[i]), .tx_ready(btr[i]), .tx_dest_coord(bdest[i]), .tx_msg_type(bmsg[i]), .tx_control(bctl[i]),
      .tx_payload_data(bpd[i]), .tx_payload_valid(bpv[i]), .tx_payload_ready(bpr[i]), .tx_error(),
      .noc_tx_flit(bnf[i]), .noc_tx_valid(bnv[i]), .noc_tx_ready(bntr[i]),
      .noc_rx_flit(brf[i]), .noc_rx_valid(brv[i]), .noc_rx_ready(),
      .rx_src_coord(brs[i]), .rx_dest_coord(), .rx_msg_type(brm[i]), .rx_control(brc[i]), .rx_length(brl[i]), .rx_head_valid(brh[i]),
      .rx_payload_data(brpd[i]), .rx_payload_valid(brpv[i]), .rx_payload_last(), .rx_ready(1'b1), .rx_abort(),
      .rejected_count(brej[i]), .accepted_count(bacc[i]), .reject_reason(bwhy[i]), .tx_busy(), .rx_busy(brb[i]));
  end

  // ---------------- P7 pair: index 0 tile 3, 1 tile 4
  logic [1:0] ptv, ptr, ppv, ppr, pnv, pntr, prv, prr, prh, prpv, prb;
  coord_t [1:0] pdest, prs; msg_type_e [1:0] pmsg, prm; logic [1:0][10:0] pctl, prc; logic [1:0][31:0] ppd, prpd;
  flit_t [1:0] pnf, prf; logic [1:0][31:0] prej, pacc, pdrop; logic [1:0][3:0] pwhy; logic [1:0][4:0] prl;
  noc_l2_p7_pair dut (.clk, .rst, .boot_epoch(epoch), .key_43(K43), .key_34(K34),
    .tx_valid(ptv), .tx_ready(ptr), .tx_dest_coord(pdest), .tx_msg_type(pmsg), .tx_control(pctl),
    .tx_payload_data(ppd), .tx_payload_valid(ppv), .tx_payload_ready(ppr), .tx_error(),
    .noc_tx_flit(pnf), .noc_tx_valid(pnv), .noc_tx_ready(pntr),
    .noc_rx_flit(prf), .noc_rx_valid(prv), .noc_rx_ready(prr),
    .rx_src_coord(prs), .rx_dest_coord(), .rx_msg_type(prm), .rx_control(prc), .rx_length(prl), .rx_head_valid(prh),
    .rx_payload_data(prpd), .rx_payload_valid(prpv), .rx_payload_last(), .rx_ready(2'b11), .rx_abort(),
    .rejected_count(prej), .accepted_count(pacc), .p_slot_drops(pdrop), .reject_reason(pwhy), .tx_busy(), .rx_busy(prb));

  // ---------------- wire capture: one packet queue per output (k 0..4 = B-2 index, 5 = P7 tile 3, 6 = P7 tile 4)
  typedef flit_t pkt_t[$];
  pkt_t wq [7][$], wcur [7];
  function automatic bit pkt_eq(input pkt_t a, input pkt_t b);
    if (a.size() != b.size()) return 0; foreach (a[i]) if (a[i] !== b[i]) return 0; return 1;
  endfunction
  always @(posedge clk) if (!rst) begin
    for (int k = 0; k < 7; k++) begin
      automatic logic v = k < 5 ? bnv[k] && bntr[k] : pnv[k-5] && pntr[k-5];
      automatic flit_t f = k < 5 ? bnf[k] : pnf[k-5];
      if (v) begin
        wcur[k].push_back(f);
        if (f.flit_type == FLIT_TAIL || f.flit_type == FLIT_HEAD_TAIL) begin wq[k].push_back(wcur[k]); wcur[k] = {}; end
      end
    end
  end
  bit bp_on = 1;
  always @(negedge clk) begin
    for (int k = 0; k < 5; k++) bntr[k] = !bp_on || (rnd() % 10) < 7;
    for (int k = 0; k < 2; k++) pntr[k] = !bp_on || (rnd() % 10) < 7;
  end

  // ---------------- generic app-side TX driver (k < 5: B-2 index; k = 5, 6: P7 tile 3, 4)
  task automatic send(input int k, input coord_t d, input msg_type_e m, input logic [10:0] c, input logic [31:0] pl [16]);
    automatic int n = message_payload_flits(m), w = 0;
    @(negedge clk);
    if (k < 5) begin bdest[k] = d; bmsg[k] = m; bctl[k] = c; btv[k] = 1; end
    else begin pdest[k-5] = d; pmsg[k-5] = m; pctl[k-5] = c; ptv[k-5] = 1; end
    do begin @(posedge clk); if (++w > 20000) timeout($sformatf("tx_ready %0d", k)); end while (!(k < 5 ? btr[k] : ptr[k-5]));
    @(negedge clk); if (k < 5) btv[k] = 0; else ptv[k-5] = 0;
    for (int i = 0; i < n; i++) begin
      if (k < 5) begin bpd[k] = pl[i]; bpv[k] = 1; end else begin ppd[k-5] = pl[i]; ppv[k-5] = 1; end
      w = 0;
      do begin @(posedge clk); if (++w > 20000) timeout($sformatf("payload %0d", k)); end while (!(k < 5 ? bpr[k] : ppr[k-5]));
      @(negedge clk);
    end
    if (k < 5) bpv[k] = 0; else ppv[k-5] = 0;
  endtask
  // message lists
  msg_type_e m4 [N_TX4], m3 [N_TX3]; logic [10:0] c4 [N_TX4], c3 [N_TX3]; logic [31:0] p4 [N_TX4][16], p3 [N_TX3][16];
  task automatic run_list(input int k, input int which);   // which 4: tile-4 list, 3: tile-3 list
    for (int i = 0; i < (which == 4 ? N_TX4 : N_TX3); i++)
      if (which == 4) send(k, xy(3), m4[i], c4[i], p4[i]); else send(k, xy(4), m3[i], c3[i], p3[i]);
  endtask
  task automatic run_foreign(input int k, input int to, input int n);
    logic [31:0] pl [16];
    for (int i = 0; i < n; i++) begin
      automatic msg_type_e m = to == 4 ? MSG_ATTEST_RESPONSE : msg_type_e'((rnd() % 2) ? 4 : 6);
      for (int w = 0; w < 16; w++) pl[w] = rnd();
      send(k, xy(to), m, 11'(rnd()), pl);
    end
  endtask

  // ---------------- receivers: delivery tokens (control) and data deliveries (P7 only)
  // token = {kind 1 head / 2 word, msg, src x/y, control, length, data}
  typedef logic [63:0] tok_t;
  tok_t btok [2][$], ptok [2][$], pdat [2][$], exp_dat [2][$];
  function automatic bit tok_eq(input tok_t a [$], input tok_t b [$]);
    if (a.size() != b.size()) return 0; foreach (a[i]) if (a[i] !== b[i]) return 0; return 1;
  endfunction
  bit pcur_data [2];
  always @(posedge clk) if (!rst) begin
    for (int t = 0; t < 2; t++) begin
      automatic int bi = t == 0 ? 1 : 0;     // B-2 receiver of tile 3 is b3 (index 1), of tile 4 is b4 (index 0)
      if (brh[bi]) btok[t].push_back({4'd1, 2'b00, 4'(brm[bi]), 3'(brs[bi].x), 3'(brs[bi].y), brc[bi], brl[bi], 32'h0});
      if (brpv[bi]) btok[t].push_back({4'd2, 28'h0, brpd[bi]});
      if (prh[t]) begin
        automatic tok_t x = {4'd1, 2'b00, 4'(prm[t]), 3'(prs[t].x), 3'(prs[t].y), prc[t], prl[t], 32'h0};
        pcur_data[t] = !is_control(prm[t]);
        if (pcur_data[t]) pdat[t].push_back(x); else ptok[t].push_back(x);
      end
      if (prpv[t]) begin if (pcur_data[t]) pdat[t].push_back({4'd2, 28'h0, prpd[t]}); else ptok[t].push_back({4'd2, 28'h0, prpd[t]}); end
    end
  end
  int held = 0;
  wire [2:0] isq [2] = '{dut.W[0].l2.is_q, dut.W[1].l2.is_q}, psq [2] = '{dut.W[0].l2.ps, dut.W[1].l2.ps};
  always @(posedge clk) if (!rst) for (int t = 0; t < 2; t++)
    if (prv[t] && !prr[t] && isq[t] == 0 && prf[t].flit_type inside {FLIT_HEAD, FLIT_HEAD_TAIL}) held++;
  int a1 = 0;
  always @(posedge clk) if (!rst && dut.engine.busy && dut.req[dut.engine.owner]) a1++;

  // injector per tile: drives the B-2 receiver (index bi) and the P7 receiver t with the same control packet;
  // data packets go to the P7 receiver only
  task automatic put(input int t, input flit_t f, input bit to_b2);
    automatic int bi = t == 0 ? 1 : 0, w = 0;
    @(negedge clk);
    prf[t] = f; prv[t] = 1; if (to_b2) begin brf[bi] = f; brv[bi] = 1; end
    @(posedge clk);
    while (!prr[t]) begin if (to_b2) begin @(negedge clk); brv[bi] = 0; end @(posedge clk); if (++w > 2000) timeout("P7 rx held"); end
    @(negedge clk); prv[t] = 0; brv[bi] = 0;
  endtask
  task automatic quiet(input int t);
    automatic int bi = t == 0 ? 1 : 0, w = 0;
    repeat (3) @(negedge clk);
    while (brb[bi] || prb[t]) begin @(negedge clk); if (++w > 5000) timeout("receivers idle"); end
    repeat (70) @(negedge clk);
  endtask
  // verdict of the last packet: 0 none, 8 accepted, else reason
  int stat_acc = 0, spoof_signed = 0; bit [15:0] seen;
  int p7_reason_n [8];
  task automatic feed(input int t, input pkt_t p, input bit with_data, input int idx);
    automatic int bi, peer, bv, pv, ev; automatic logic [31:0] ba, br, pa, pr; automatic head_flit_t h; automatic bit ctl, from_peer;
    // set by statements, not chained declaration initializers (XSim mis-evaluated those: from_peer came out 0 for the peer)
    bi = t == 0 ? 1 : 0; peer = t == 0 ? 4 : 3;
    ba = bacc[bi]; br = brej[bi]; pa = pacc[t]; pr = prej[t];
    h = head_flit_t'(p[0].flit_data);
    ctl = is_control(msg_type_e'(h.msg_type));
    from_peer = h.src_x < 3 && h.src_y < 2 && int'(h.src_y) * 3 + int'(h.src_x) == peer;
    btok[t] = {}; ptok[t] = {};
    foreach (p[i]) put(t, p[i], 1);
    if (with_data) begin
      automatic int w = 0;
      automatic msg_type_e dm = (rnd() % 2) ? MSG_MEM_RD_REQ : MSG_MEM_WR_REQ;
      automatic head_flit_t dh = '0; automatic flit_t f; automatic int n = message_payload_flits(dm);
      while (psq[t] != 6 && w < 300) begin @(negedge clk); w++; end   // P_PLAY: the data HEAD meets the replay
      dh.dest_x = (t == 0 ? 3'd0 : 3'd1); dh.dest_y = 3'd1; dh.src_x = 3'd0; dh.src_y = 3'd0; dh.msg_type = dm;
      dh.length = p7_length(dm); dh.control.raw = 11'(rnd());
      f.flit_data = dh; f.flit_type = FLIT_HEAD; f.vc_id = message_to_vc(dm); exp_dat[t].push_back({4'd1, 2'b00, 4'(dm), 3'd0, 3'd0, dh.control.raw, dh.length, 32'h0});
      put(t, f, 0);
      for (int i = 0; i < n; i++) begin
        f.flit_data = rnd(); f.flit_type = i == n - 1 ? FLIT_TAIL : FLIT_BODY; exp_dat[t].push_back({4'd2, 28'h0, f.flit_data}); put(t, f, 0);
      end
    end
    quiet(t);
    bv = bacc[bi] != ba ? 8 : brej[bi] != br ? int'(bwhy[bi]) : 0;
    pv = pacc[t] != pa ? 8 : prej[t] != pr ? int'(pwhy[t]) : 0;
    if (!ctl) ev = 0; else if (from_peer) ev = bv; else ev = bv == 1 ? 1 : 5;
    if (!from_peer && ctl && bv == 8 && pv == 5) spoof_signed++;
    if (pv == 8) stat_acc++; else if (pv > 0 && pv < 8) p7_reason_n[pv]++;
    check(pv == ev, $sformatf("L2P7_RX_VERDICT tile=%0d pkt=%0d b2=%0d p7=%0d expected=%0d src=%0d,%0d type=%0d", t + 3, idx, bv, pv, ev, h.src_x, h.src_y, h.msg_type));
    if (pv == 8) check(tok_eq(ptok[t], btok[t]), $sformatf("L2P7_RX_DELIVERY tile=%0d pkt=%0d p7=%0d b2=%0d tokens", t + 3, idx, ptok[t].size(), btok[t].size()));
    else check(ptok[t].size() == 0, $sformatf("L2P7_RX_DELIVERY tile=%0d pkt=%0d p7 delivered %0d tokens without accepting", t + 3, idx, ptok[t].size()));
  endtask
  // build the phase-2 stream of tile t (0: tile 3 from wq[0] b4 genuine, 1: tile 4 from wq[1] b3 genuine)
  task automatic rx_phase(input int t);
    automatic int gsrc = t == 0 ? 0 : 1, ng = t == 0 ? N_TX4 : N_TX3, nm = t == 0 ? 100 : 70, nf = t == 0 ? 40 : 30;
    automatic int stride = t == 0 ? 3 : 2, fst = t == 0 ? 7 : 6, foff = t == 0 ? 3 : 2, idx = 0, j = 0, kf = 0;
    pkt_t g [$], fs [$], fa [$];
    g = wq[gsrc]; fs = wq[2]; fa = wq[t == 0 ? 3 : 4];
    // tile-5 packets for this tile are the ones addressed to it (s5 sent tile-3 traffic first, then tile-4 traffic)
    if (t == 0) fs = fs[0:39]; else fs = fs[40:69];
    if (g.size() != ng || fa.size() != nf) timeout("phase-2 inputs incomplete");
    for (int i = 0; i < ng; i++) begin
      feed(t, g[i], idx < 100, idx); idx++;
      if (j < nm && i == stride * j + 1) begin
        automatic pkt_t x; automatic int kind = j % 4;
        if (kind == 0) begin x = g[i+1]; begin automatic int fi = rnd() % x.size(); x[fi].flit_data[rnd() % 32] ^= 1'b1; end end
        else if (kind == 1) x = g[i-1];
        else if (kind == 2) begin x = g[i+1]; x = x[0:x.size()-2]; x[x.size()-1].flit_type = FLIT_TAIL; end
        else begin automatic head_flit_t h; x = g[i+1]; h = head_flit_t'(x[0].flit_data); h.src_x = (rnd() % 2) ? 3'd2 : 3'd0; h.src_y = 3'd0; x[0].flit_data = h; end
        feed(t, x, idx < 100, idx); idx++; j++;
      end
      if (kf < nf && i == fst * kf + foff) begin
        feed(t, fs[kf], idx < 100, idx); idx++;
        feed(t, fa[kf], idx < 100, idx); idx++; kf++;
      end
    end
    if (idx != (t == 0 ? N_RX3 : N_RX4)) timeout($sformatf("phase-2 stream length %0d", idx));
  endtask

  initial begin
    $display("CONFIG: TOP=tb_l2p7_equiv N_TX4=%0d N_TX3=%0d N_RX3=%0d N_RX4=%0d N_DRX=%0d N_DTX=%0d PROFILE=P7", N_TX4, N_TX3, N_RX3, N_RX4, N_DRX, N_DTX);
    for (int i = 0; i < 12; i++) for (int w = 0; w < 8; w++) KR[i][w*32 +: 32] = rnd();
    K43 = KR[0]; K34 = KR[1]; K53 = KR[2]; K54 = KR[3];
    for (int i = 0; i < 5; i++) begin
      btk[i] = {6{KR[4 + i]}}; brk[i] = {6{KR[9]}};
      btv[i] = 0; bpv[i] = 0; brv[i] = 0; brf[i] = '0; bdest[i] = '0; bmsg[i] = MSG_ATTEST_GRANT; bctl[i] = 0; bpd[i] = 0;
    end
    btk[0][3*256 +: 256] = K43; brk[0][3*256 +: 256] = K34; brk[0][5*256 +: 256] = K54;    // b4
    btk[1][4*256 +: 256] = K34; brk[1][4*256 +: 256] = K43; brk[1][5*256 +: 256] = K53;    // b3
    btk[2][3*256 +: 256] = K53; btk[2][4*256 +: 256] = K54;                                  // s5
    btk[3][3*256 +: 256] = K43; btk[4][4*256 +: 256] = K34;                                  // a4, a3
    ptv = 0; ppv = 0; prv = 0; prf = '0; pdest = '0; pmsg[0] = MSG_ATTEST_GRANT; pmsg[1] = MSG_ATTEST_GRANT; pctl = '0; ppd = '0;
    for (int i = 0; i < N_TX4; i++) begin
      automatic int r = rnd() % 3; m4[i] = msg_type_e'(r == 0 ? 4 : r == 1 ? 6 : 7); c4[i] = 11'(rnd());
      for (int w = 0; w < 16; w++) p4[i][w] = rnd();
    end
    for (int i = 0; i < N_TX3; i++) begin m3[i] = MSG_ATTEST_RESPONSE; c3[i] = 11'(rnd()); for (int w = 0; w < 16; w++) p3[i][w] = rnd(); end
    repeat (5) @(negedge clk); rst = 0;
    // ---- phase 1
    fork
      run_list(0, 4); run_list(6, 4); run_list(1, 3); run_list(5, 3);
      begin run_foreign(2, 3, 40); run_foreign(2, 4, 30); end
      run_foreign(3, 3, 40); run_foreign(4, 4, 30);
    join
    repeat (400) @(negedge clk);
    if (wq[0].size() != N_TX4 || wq[6].size() != N_TX4 || wq[1].size() != N_TX3 || wq[5].size() != N_TX3 || wq[2].size() != 70)
      timeout($sformatf("phase-1 packets %0d %0d %0d %0d %0d", wq[0].size(), wq[6].size(), wq[1].size(), wq[5].size(), wq[2].size()));
    for (int i = 0; i < N_TX4; i++) check(pkt_eq(wq[6][i], wq[0][i]), $sformatf("L2P7_TX_WIRE tile=4 pkt=%0d p7_len=%0d b2_len=%0d", i, wq[6][i].size(), wq[0][i].size()));
    for (int i = 0; i < N_TX3; i++) check(pkt_eq(wq[5][i], wq[1][i]), $sformatf("L2P7_TX_WIRE tile=3 pkt=%0d p7_len=%0d b2_len=%0d", i, wq[5][i].size(), wq[1][i].size()));
    // ---- phase 2 (both tiles in parallel; each receiver pair is independent)
    bp_on = 0;
    fork rx_phase(0); rx_phase(1); join
    for (int t = 0; t < 2; t++) begin
      automatic int nd = 0;
      for (int i = 0; i < exp_dat[t].size(); i++) if (exp_dat[t][i][63:60] == 4'd1) begin
        automatic tok_t e [$], d [$]; automatic int k = i;
        e.push_back(exp_dat[t][k]); k++; while (k < exp_dat[t].size() && exp_dat[t][k][63:60] == 4'd2) begin e.push_back(exp_dat[t][k]); k++; end
        for (int q = 0; q < e.size(); q++) if (pdat[t].size() > 0) d.push_back(pdat[t].pop_front());
        check(tok_eq(d, e), $sformatf("L2P7_DATA_RX tile=%0d data=%0d delivered=%0d expected=%0d tokens", t + 3, nd, d.size(), e.size()));
        nd++;
      end
      if (nd != N_DRX / 2) timeout($sformatf("data packets injected %0d", nd));
    end
    // ---- phase 3: plain data TX from each P7 tile
    bp_on = 1;
    begin
      wq[5] = {}; wq[6] = {};
      for (int i = 0; i < N_DTX; i++) begin
        automatic int t = i % 2; automatic msg_type_e m = (i / 2) % 2 ? MSG_MEM_WR_RESP : MSG_MEM_RD_RESP;
        automatic int dt = (rnd() % 4); automatic coord_t d = xy(dt == 3 ? 5 : dt); automatic logic [10:0] c = 11'(rnd());
        automatic logic [31:0] pl [16]; automatic head_flit_t h = '0; automatic pkt_t e; automatic flit_t f; automatic int w = 0;
        for (int k = 0; k < 16; k++) pl[k] = rnd();
        h.dest_x = d.x; h.dest_y = d.y; h.src_x = t == 0 ? 3'd0 : 3'd1; h.src_y = 3'd1; h.msg_type = m; h.length = p7_length(m); h.control.raw = c;
        f.flit_data = h; f.vc_id = message_to_vc(m); f.flit_type = m == MSG_MEM_WR_RESP ? FLIT_HEAD_TAIL : FLIT_HEAD; e.push_back(f);
        if (m == MSG_MEM_RD_RESP) begin f.flit_data = pl[0]; f.flit_type = FLIT_TAIL; e.push_back(f); end
        send(5 + t, d, m, c, pl);
        while (wq[5 + t].size() == 0) begin @(negedge clk); if (++w > 5000) timeout("data TX wire"); end
        begin automatic pkt_t got = wq[5 + t].pop_front();
          check(pkt_eq(got, e), $sformatf("L2P7_DATA_TX tile=%0d pkt=%0d len=%0d expected=%0d", t + 3, i, got.size(), e.size())); end
      end
    end
    // ---- A1 + coverage
    check(a1 == 0, $sformatf("L2P7_A1 owner-request cycles=%0d", a1));
    check(stat_acc >= 400, $sformatf("L2P7_COVER_ACCEPTED %0d", stat_acc));
    check(p7_reason_n[1] >= 5 && p7_reason_n[2] >= 5 && p7_reason_n[3] >= 5 && p7_reason_n[4] >= 5 && p7_reason_n[5] >= 5,
          $sformatf("L2P7_COVER_REASONS r1=%0d r2=%0d r3=%0d r4=%0d r5=%0d", p7_reason_n[1], p7_reason_n[2], p7_reason_n[3], p7_reason_n[4], p7_reason_n[5]));
    check(spoof_signed >= 40, $sformatf("L2P7_COVER_SPOOF_SIGNED %0d", spoof_signed));
    check(held >= 10, $sformatf("L2P7_COVER_DATA_HELD %0d", held));
    $display("STATS accepted=%0d r1=%0d r2=%0d r3=%0d r4=%0d r5=%0d spoof_signed=%0d held=%0d p_slot_drops=%0d/%0d",
             stat_acc, p7_reason_n[1], p7_reason_n[2], p7_reason_n[3], p7_reason_n[4], p7_reason_n[5], spoof_signed, held, pdrop[0], pdrop[1]);
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
