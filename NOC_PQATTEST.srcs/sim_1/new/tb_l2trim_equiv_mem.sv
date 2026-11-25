`timescale 1ns/1ps
// B-2 step a, MEMORY-REQUEST coverage (Kalash 21:19): same equivalence as tb_l2trim_equiv (trimmed rtl/dual_lane/noc_l2_auth.sv
// vs the TB-only pre-trim copy, every output every cycle), but the sender and the DUT driver generate ONLY the slot-holding
// memory requests MEM_RD_REQ (1 payload word, wire length 11) and MEM_WR_REQ (2 words, wire length 12). tb_l2trim_equiv does
// not cover those two (its types 1,3,4,5,6,7 give payload counts 0/1/7/16 and wire lengths 10/11/17/26): T1 depends on the
// wire length, T2 on the payload count, so length 12 / count 2 were uncovered.
// A request holds an NI transaction slot until its response returns and no responder exists here, so whenever the sender
// cannot issue for 300 cycles the bench resets ALL three wrappers together (both DUTs see the identical reset) and continues.
// Same mutations as tb_l2trim_equiv (bit flip, replay, truncation, junk, zero-gap busy-drop, epoch phase).
// Checks: N_CYC = 100000 per-cycle L2TRIM_EQUIV_CYCLE compares + 4 coverage checks
//   (delivered MEM_RD_REQ heads >= 20, delivered MEM_WR_REQ heads >= 20, resets >= 10, DUT TX heads >= 20).
//   CHECKS = 100004, frozen before the first run. Bounded waits; a bound hit is TB_TIMEOUT (INVALID).
module tb_l2trim_equiv_mem;
  import noc_pkg::*;
  localparam int N_CYC = 100000;
  logic clk = 0, rst = 1;
  always #10 clk = ~clk;
  logic [79:0] epoch_rx = 80'h1A2B_3C4D_5E6F_7081_92A3, epoch_tx;
  logic [1535:0] keys_tx_snd, keys_rx_snd, keys_tx_dut, keys_rx_dut;
  logic [31:0] lcg = 32'h2D1E_0001;
  function automatic logic [31:0] rnd();
    lcg = lcg * 32'd1664525 + 32'd1013904223; return lcg;
  endfunction
  function automatic coord_t tile_xy(input int t); coord_t c; c.x = t % 3; c.y = t / 3; return c; endfunction
  localparam int TYPES[2] = '{0, 2};               // ONLY the slot-holding memory requests (see header)
  int resets = 0, rd_heads = 0, wr_heads = 0;
  task automatic do_reset(); @(negedge clk); rst = 1; repeat (4) @(negedge clk); rst = 0; resets++; endtask
  localparam int OTHER4[5] = '{0, 1, 2, 3, 5};     // sender (tile 4) never targets itself
  localparam int OTHER3[5] = '{0, 1, 2, 4, 5};     // DUT (tile 3) never targets itself

  // ---------------- sender (tile 4, pre-trim) -> wire queue
  logic s_tv, s_tr, s_pv, s_pr; coord_t s_dest; msg_type_e s_msg; logic [10:0] s_ctl; logic [31:0] s_pd;
  flit_t s_nf; logic s_nv;
  noc_l2_auth_orig_l2trim #(.TILE(4)) u_snd (.clk, .rst, .boot_epoch(epoch_tx), .tx_keys(keys_tx_snd), .rx_keys(keys_rx_snd),
    .tx_valid(s_tv), .tx_ready(s_tr), .tx_dest_coord(s_dest), .tx_msg_type(s_msg), .tx_control(s_ctl),
    .tx_payload_data(s_pd), .tx_payload_valid(s_pv), .tx_payload_ready(s_pr), .tx_error(),
    .noc_tx_flit(s_nf), .noc_tx_valid(s_nv), .noc_tx_ready(1'b1),
    .noc_rx_flit('0), .noc_rx_valid(1'b0), .noc_rx_ready(),
    .rx_src_coord(), .rx_dest_coord(), .rx_msg_type(), .rx_control(), .rx_length(), .rx_head_valid(),
    .rx_payload_data(), .rx_payload_valid(), .rx_payload_last(), .rx_ready(1'b1), .rx_abort(),
    .rejected_count(), .accepted_count(), .reject_reason(), .tx_busy(), .rx_busy());
  typedef flit_t pkt_t[$];
  pkt_t q[$], hist[$], cur;
  int snd_packets = 0;
  always @(posedge clk) if (!rst && s_nv) begin
    cur.push_back(s_nf);
    if (s_nf.flit_type == FLIT_TAIL || s_nf.flit_type == FLIT_HEAD_TAIL) begin q.push_back(cur); cur = {}; snd_packets++; end
  end

  // ---------------- the two tile-3 DUTs, identical inputs
  logic d_tv, d_pv, d_rr, d_ntr; coord_t d_dest; msg_type_e d_msg; logic [10:0] d_ctl; logic [31:0] d_pd;
  flit_t inj; logic inj_v;
  `define L2_PORTS(tag) \
    .clk, .rst, .boot_epoch(epoch_rx), .tx_keys(keys_tx_dut), .rx_keys(keys_rx_dut), \
    .tx_valid(d_tv), .tx_ready(tag``_tr), .tx_dest_coord(d_dest), .tx_msg_type(d_msg), .tx_control(d_ctl), \
    .tx_payload_data(d_pd), .tx_payload_valid(d_pv), .tx_payload_ready(tag``_pr), .tx_error(tag``_te), \
    .noc_tx_flit(tag``_nf), .noc_tx_valid(tag``_nv), .noc_tx_ready(d_ntr), \
    .noc_rx_flit(inj), .noc_rx_valid(inj_v), .noc_rx_ready(tag``_nrr), \
    .rx_src_coord(tag``_rs), .rx_dest_coord(tag``_rd), .rx_msg_type(tag``_rm), .rx_control(tag``_rc), .rx_length(tag``_rl), \
    .rx_head_valid(tag``_rh), .rx_payload_data(tag``_rpd), .rx_payload_valid(tag``_rpv), .rx_payload_last(tag``_rpl), \
    .rx_ready(d_rr), .rx_abort(tag``_ra), .rejected_count(tag``_rej), .accepted_count(tag``_acc), .reject_reason(tag``_why), \
    .tx_busy(tag``_tb), .rx_busy(tag``_rb)
  logic n_tr, n_pr, n_te, n_nv, n_nrr, n_rh, n_rpv, n_rpl, n_ra, n_tb, n_rb; flit_t n_nf; coord_t n_rs, n_rd; msg_type_e n_rm;
  logic [10:0] n_rc; logic [4:0] n_rl; logic [31:0] n_rpd, n_rej, n_acc; logic [3:0] n_why;
  logic o_tr, o_pr, o_te, o_nv, o_nrr, o_rh, o_rpv, o_rpl, o_ra, o_tb, o_rb; flit_t o_nf; coord_t o_rs, o_rd; msg_type_e o_rm;
  logic [10:0] o_rc; logic [4:0] o_rl; logic [31:0] o_rpd, o_rej, o_acc; logic [3:0] o_why;
  noc_l2_auth             #(.TILE(3)) u_new (`L2_PORTS(n));
  noc_l2_auth_orig_l2trim #(.TILE(3)) u_ref (`L2_PORTS(o));
  wire [511:0] out_new = {n_tr, n_pr, n_te, n_nf, n_nv, n_nrr, n_rs, n_rd, n_rm, n_rc, n_rl, n_rh, n_rpd, n_rpv, n_rpl, n_ra,
                          n_rej, n_acc, n_why, n_tb, n_rb};
  wire [511:0] out_ref = {o_tr, o_pr, o_te, o_nf, o_nv, o_nrr, o_rs, o_rd, o_rm, o_rc, o_rl, o_rh, o_rpd, o_rpv, o_rpl, o_ra,
                          o_rej, o_acc, o_why, o_tb, o_rb};

  int checks = 0, errors = 0, shown = 0, dut_heads = 0;
  bit [15:0] seen_reason; logic [31:0] last_rej = 0;
  task automatic check(input bit ok, input string name);
    checks++; if (!ok) begin errors++; if (shown < 20) begin shown++; $display("[FAIL] %s", name); end end
  endtask
  task automatic timeout(input string w); $display("TB_TIMEOUT %s", w); $finish; endtask

  // ---------------- sender driver: genuine traffic of every type to tile 3 (a few to other tiles, never delivered here)
  task automatic snd_one();
    int n, t, k, r0; msg_type_e m;
    t = TYPES[rnd() % 2]; m = msg_type_e'(t); n = message_payload_flits(m);
    @(negedge clk); s_dest = (rnd() % 10 == 0) ? tile_xy(OTHER4[rnd() % 5]) : tile_xy(3); s_msg = m; s_ctl = 11'(rnd());
    s_tv = 1; k = 0;                                   // valid held until ready is sampled at a clock edge
    do begin @(posedge clk); k++; end while (!s_tr && k <= 300);
    if (!s_tr) begin @(negedge clk); s_tv = 0; cur = {}; do_reset(); return; end   // slots exhausted: reset all wrappers
    r0 = resets;
    @(negedge clk); s_tv = 0;
    for (int w = 0; w < n; w++) begin
      s_pd = rnd(); s_pv = 1; k = 0;
      do begin @(posedge clk); if (++k > 5000) timeout("sender payload"); end while (!s_pr && resets == r0);
      @(negedge clk);
    end
    s_pv = 0;
  endtask
  initial begin
    s_tv = 0; s_pv = 0; s_dest = '0; s_msg = MSG_MEM_RD_REQ; s_ctl = 0; s_pd = 0; epoch_tx = epoch_rx;
    wait (!rst);
    forever begin
      // an epoch phase every ~200 sender packets: 20 packets under a different boot epoch (MAC valid, epoch reject)
      epoch_tx = ((snd_packets % 200) >= 180) ? (epoch_rx ^ 80'h1) : epoch_rx;
      snd_one();
    end
  end

  // ---------------- injector: identical stream into both tile-3 DUTs
  task automatic put(input flit_t f); @(negedge clk); inj = f; inj_v = 1; endtask
  task automatic idle(input int n); repeat (n) begin @(negedge clk); inj_v = 0; inj = '0; end endtask
  initial begin
    pkt_t p; int sel, k;
    inj = '0; inj_v = 0;
    wait (!rst);
    forever begin
      k = 0; while (q.size() == 0) begin @(negedge clk); inj_v = 0; if (++k > 20000) timeout("sender queue empty"); end
      p = q.pop_front(); sel = rnd() % 100;
      if (sel < 45) begin end                                                   // genuine
      else if (sel < 63) begin int i = rnd() % p.size(); p[i].flit_data[rnd() % 32] ^= 1'b1; end   // bit flip
      else if (sel < 71 && hist.size() > 0) p = hist[rnd() % hist.size()];      // replay
      else if (sel < 77 && p.size() > 2) begin p = p[0:p.size()-2]; p[p.size()-1].flit_type = FLIT_TAIL; end  // truncation
      else if (sel < 82) begin                                                  // junk
        int n = 1 + rnd() % 30; p = {};
        for (int i = 0; i < n; i++) begin flit_t f; f.flit_data = rnd(); f.flit_type = flit_type_e'(rnd() % 4); f.vc_id = rnd(); p.push_back(f); end
      end
      if (sel < 45 && hist.size() < 64) hist.push_back(p);
      foreach (p[i]) begin put(p[i]); if (rnd() % 8 == 0) idle(1 + rnd() % 3); end
      if (sel >= 90) idle(0);                                                   // zero gap: next packet lands while busy
      else idle(rnd() % 4);
    end
  end

  // ---------------- DUT TX driver (send side and NI paths), random backpressure and rx_ready
  initial begin
    int n, k; msg_type_e m;
    d_tv = 0; d_pv = 0; d_dest = '0; d_msg = MSG_MEM_RD_REQ; d_ctl = 0; d_pd = 0;
    wait (!rst);
    forever begin
      m = msg_type_e'(TYPES[rnd() % 2]); n = message_payload_flits(m);
      @(negedge clk); d_dest = tile_xy(OTHER3[rnd() % 5]); if (rnd() % 16 == 0) d_dest.x = 3; d_msg = m; d_ctl = 11'(rnd());
      d_tv = 1; k = 0;                                 // valid held until ready is sampled at a clock edge
      do begin @(posedge clk); k++; end while (!o_tr && k < 64);
      begin automatic bit acc = o_tr; @(negedge clk); d_tv = 0;
      if (acc) begin                                   // refused for 64 cycles (e.g. bad dest): give up, not an error
        for (int w = 0; w < n; w++) begin
          d_pd = rnd(); d_pv = 1; k = 0;
          do begin @(posedge clk); if (++k > 5000) timeout("dut payload"); end while (!o_pr && !rst);
          @(negedge clk);
        end
        d_pv = 0;
      end
      end
      repeat (rnd() % 40) @(negedge clk);
    end
  end
  always @(negedge clk) begin d_ntr = (rnd() % 10) < 7; d_rr = (rnd() % 10) < 8; end
  always @(posedge clk) if (!rst && o_nv && d_ntr && o_nf.flit_type inside {FLIT_HEAD, FLIT_HEAD_TAIL}) dut_heads++;
  always @(posedge clk) if (!rst && o_rh && d_rr) begin if (o_rm == MSG_MEM_RD_REQ) rd_heads++; if (o_rm == MSG_MEM_WR_REQ) wr_heads++; end

  // ---------------- compare every cycle; record reject reasons from the reference
  initial begin
    $display("CONFIG: TOP=tb_l2trim_equiv_mem N_CYC=%0d COVERAGE=4 PROFILE=P6-S TYPES=MEM_RD_REQ,MEM_WR_REQ", N_CYC);
    for (int i = 0; i < 6; i++) begin
      for (int w = 0; w < 8; w++) begin
        keys_tx_snd[i*256 + w*32 +: 32] = rnd(); keys_rx_dut[i*256 + w*32 +: 32] = rnd();
        keys_tx_dut[i*256 + w*32 +: 32] = rnd(); keys_rx_snd[i*256 + w*32 +: 32] = rnd();
      end
    end
    keys_rx_dut[4*256 +: 256] = keys_tx_snd[3*256 +: 256];   // K[4->3]: sender's tx key to tile 3 = DUT rx key from tile 4
    repeat (5) @(negedge clk); rst = 0;
    for (int c = 0; c < N_CYC; c++) begin
      @(negedge clk);
      check(out_new === out_ref, $sformatf("L2TRIM_EQUIV_CYCLE %0d new=%h ref=%h", c, out_new, out_ref));
      if (o_rej != last_rej) begin seen_reason[o_why] = 1; last_rej = o_rej; end
    end
    check(rd_heads >= 20,  $sformatf("L2TRIM_MEM_COVER_RD_REQ_DELIVERED %0d", rd_heads));
    check(wr_heads >= 20,  $sformatf("L2TRIM_MEM_COVER_WR_REQ_DELIVERED %0d", wr_heads));
    check(resets >= 10,    $sformatf("L2TRIM_MEM_COVER_RESETS %0d", resets));
    check(dut_heads >= 20, $sformatf("L2TRIM_MEM_COVER_DUT_TX_HEADS %0d", dut_heads));
    $display("STATS accepted=%0d rejected=%0d reasons=%b rd_req=%0d wr_req=%0d resets=%0d dut_tx_heads=%0d sender_packets=%0d", o_acc, o_rej, seen_reason, rd_heads, wr_heads, resets, dut_heads, snd_packets);
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
