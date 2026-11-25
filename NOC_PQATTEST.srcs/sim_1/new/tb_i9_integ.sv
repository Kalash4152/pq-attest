`timescale 1ns/1ps
// I-9 integration bench (docs/decisions/M-F1-rev8-INTEGRATION-DRAFT.md, signed 2026-11-05) on the I-9 list
// (rtl/dual_lane/pq_noc_subsystem_p7_i9.sv, module pq_noc_subsystem_p7), PQ_MAC_ON, chain row 0 of vectors/full_chain.svh.
// Parameters: TB_INJECT = 1 (bench hooks; TBI.v/f present flits at a tile's network input), VERIFIER_TIMEOUT = 3,000,
// NI_SLOT_TIMEOUT = 600, MEM_EXT = 1 (tile-2 front end drives the bench's BRAM model: 4,096 words, 1-cycle read),
// MEM_ADDR_BITS = 14 (16 KB window), K3_IMEM_LEN = 16 (default; the 64-byte profile is qualified with its own vectors).
// Tile 3 is the attested CPU tile; every request below is driven on its application port.
// Checks, in order (one run):
//  I9_RESET_STATE       after reset nothing is authorized and no app_rx HEAD was exported
//  I9_GRANT             row-0 attestation grants tile 3
//  I9_WRITE_RESP        write 0x2200_0100 (wstrb 1111): one WR_RESP on app_rx[3] from tile 2, err 0, last on the HEAD;
//                       the BRAM word holds the data; memory_commits +1
//  I9_READ_DATA         read 0x2200_0100: RD_RESP from tile 2, err 0, one data word = the written word, last with it
//  I9_BYTE_LANES        write 0xAABB_CCDD with wstrb 0101, read back 0x19BB_00DD (bytes 0 and 2 replaced)
//  I9_WINDOW_TOP_OK     write + read 0x2200_3FFC (last word of the 16 KB window): err 0, data back, BRAM word 0xFFF
//  I9_WINDOW_OUT_ERR    read 0x2200_4000: RD_RESP err 1, data 0, no BRAM access, fault record (3, MEM_RD_REQ, 13)
//  I9_UNAUTH_NO_BRAM    raw own-source write from tile 5 (wstrb 1111): no commit, no BRAM write
//  I9_SLOT_HELD         two reads to tile 1 (no responder) are accepted; a third request (a complete write, sent in
//                       parallel) gets no response and no commit for 300 cycles
//  I9_SLOT_RECOVER      that write is sent and answered (WR_RESP, one commit) once the NI slot timeout frees the slots
//                       (bounded wait)
//  I9_INJECT_PATH_LIVE  a fresh read to tile 1 answered by an injected RD_RESP from tile 1 (tag 0) IS delivered on app_rx
//                       (shows the injection path reaches the CPU port)
//  I9_STALE_DROPPED     two reads to tile 1 left 600 + 50 cycles (both slots stale), then an injected RD_RESP from tile 1
//                       with tag 0: no app_rx HEAD at tile 3
//  I9_RX_ACCOUNTED      app_rx HEADs: only at tile 3, only types 1 / 3, exactly one per expected response; control traffic
//                       did reach tile 3 (attestation) and was not exported; BRAM writes = memory commits
// CHECKS = 13, frozen in the I-9 registry before the first run. Every wait is bounded and feeds a check (never a pass);
// TB_TIMEOUT only for the global limit.
module tb_i9_integ;
  import noc_pkg::*;
  import noc_p7_pkg::*;
  localparam int T_SLOT = 600;
  logic clk = 0, rst = 1, start_attestation = 0, revoke = 0, trusted_clear = 0;
  always #10 clk = ~clk;
  logic [79:0] boot_epoch, attest_epoch;
  logic [127:0] nonce;
  logic [255:0] root_secret, approved_measurement;
  logic [9215:0] directed_keys;
  logic [111:0] context_in;
  logic [3:0] context_len;
  logic [511:0] config_data, imem;
  logic [6:0] config_len, imem_len;
  logic [5:0] app_valid, app_payload_valid, app_ready, app_payload_ready, app_tx_error;
  coord_t [5:0] app_destination;
  msg_type_e [5:0] app_message;
  logic [5:0][10:0] app_control;
  logic [5:0][31:0] app_payload;
  logic spoof_raw_valid = 0, spoof_raw_ready;
  flit_t spoof_raw_flit;
  logic [5:0] authorized;
  logic rot_busy, grant_done, attestation_failed;
  logic [775:0] endpoint_response, expected_response;
  logic [31:0] memory_commits, memory_last_data;
  logic fault_sticky; logic [31:0] fault_count; logic [2:0] fault_source; logic [3:0] fault_operation, fault_reason;
  logic [79:0] fault_epoch;
  logic [5:0] rx_hv, rx_dv, rx_last, rx_abort;
  coord_t [5:0] rx_src;
  msg_type_e [5:0] rx_msg;
  logic [5:0][10:0] rx_ctl;
  logic [5:0][31:0] rx_data;
  logic mem_en; logic [3:0] mem_we; logic [11:0] mem_addr; logic [31:0] mem_wdata, mem_rdata;
  logic [511:0] keys_p7;
  assign keys_p7 = {directed_keys[(3*6+4)*256 +: 256], directed_keys[(4*6+3)*256 +: 256]};
  pq_noc_subsystem_p7 #(.TB_INJECT(1'b1), .VERIFIER_TIMEOUT(3000), .NI_SLOT_TIMEOUT(T_SLOT), .MEM_EXT(1'b1), .MEM_ADDR_BITS(14)) dut(
    .clk, .rst, .start_attestation, .revoke, .trusted_clear, .boot_epoch, .attest_epoch, .nonce, .root_secret,
    .approved_measurement, .directed_keys(keys_p7), .context_in, .context_len, .config_data, .imem, .config_len, .imem_len,
    .app_valid, .app_payload_valid, .app_ready, .app_payload_ready, .app_destination, .app_message, .app_control, .app_payload,
    .spoof_raw_valid, .spoof_raw_flit, .spoof_raw_ready, .authorized, .rot_busy, .grant_done, .attestation_failed,
    .endpoint_response, .memory_commits, .memory_last_data, .app_tx_error,
    .fault_sticky, .fault_count, .fault_source, .fault_operation, .fault_reason, .fault_epoch,
    .app_rx_head_valid(rx_hv), .app_rx_data_valid(rx_dv), .app_rx_last(rx_last), .app_rx_abort(rx_abort),
    .app_rx_src(rx_src), .app_rx_msg(rx_msg), .app_rx_control(rx_ctl), .app_rx_data(rx_data),
    .mem_en, .mem_we, .mem_addr, .mem_wdata, .mem_rdata);
  `include "full_chain.svh"
  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask

  // ---- BRAM model (behind the tile-2 front end): 1-cycle read, byte enables
  logic [31:0] bram [4096];
  int bram_wr = 0, bram_en = 0;
  initial for (int i = 0; i < 4096; i++) bram[i] = '0;
  always @(posedge clk) if (mem_en) begin
    for (int b = 0; b < 4; b++) if (mem_we[b]) bram[mem_addr][b*8 +: 8] <= mem_wdata[b*8 +: 8];
    mem_rdata <= bram[mem_addr];
    bram_en++; if (mem_we != 0) bram_wr++;
  end

  // ---- monitors
  typedef struct { int src; int op; int reason; logic [79:0] epoch; } rec_t;
  rec_t recs [$];
  int grants = 0, ctl3 = 0, bad_tile = 0, bad_type = 0, rx3 = 0, exp_rx = 0, n_commit = 0;
  int rx_n_data = 0; bit rx_seen_last = 0;
  logic [31:0] rx_last_data = 0, commits_q = 0, fc_q = 0;
  coord_t rx_last_src; msg_type_e rx_last_msg; logic [10:0] rx_last_ctl = 0; bit rx_last_on_head = 0;
  always @(posedge clk) begin
    if (!rst) begin
      if (grant_done) grants++;
      if (dut.rhv[3] && is_control(dut.rxmsg[3])) ctl3++;
      for (int g = 0; g < 6; g++) if (rx_hv[g]) begin
        if (g != 3) bad_tile++;
        if (rx_msg[g] != MSG_MEM_RD_RESP && rx_msg[g] != MSG_MEM_WR_RESP) bad_type++;
      end
      if (rx_hv[3]) begin
        rx3++; rx_last_src = rx_src[3]; rx_last_msg = rx_msg[3]; rx_last_ctl = rx_ctl[3]; rx_last_on_head = rx_last[3];
        rx_n_data = 0; rx_seen_last = rx_last[3];
      end
      if (rx_dv[3]) begin rx_n_data++; rx_last_data = rx_data[3]; if (rx_last[3]) rx_seen_last = 1; end
      if (memory_commits != commits_q) n_commit++;
      if (fault_count != fc_q && fault_count != 0) recs.push_back('{int'(fault_source), int'(fault_operation), int'(fault_reason), fault_epoch});
      commits_q = memory_commits; fc_q = fault_count;
    end else begin commits_q = 0; fc_q = 0; end
  end
  function automatic bit seen(input int from, input int src, input int op, input int reason);
    for (int i = from; i < recs.size(); i++)
      if (recs[i].src == src && recs[i].op == op && recs[i].reason == reason && recs[i].epoch == attest_epoch) return 1;
    return 0;
  endfunction

  // ---- stimulus helpers (bounded)
  task automatic do_reset();
    @(negedge clk); rst = 1; app_valid = 0; app_payload_valid = 0; revoke = 0; start_attestation = 0; spoof_raw_valid = 0;
    trusted_clear = 0; repeat (6) @(negedge clk); rst = 0; repeat (5) @(negedge clk);
  endtask
  task automatic pulse_start(); @(negedge clk); start_attestation = 1; @(negedge clk); start_attestation = 0; endtask
  task automatic wait_idle(); automatic int n = 0; while ((rot_busy || dut.verifier.vs != 0) && n < 60000) begin @(negedge clk); n++; end endtask
  task automatic attest(input int row, output bit ok);
    automatic int g0 = grants, n = 0;
    load_chain(row); pulse_start();
    while (!(grants == g0 + 1 && authorized[3]) && n < 60000) begin @(negedge clk); n++; end
    ok = grants == g0 + 1 && authorized[3];
    wait_idle(); repeat (20) @(negedge clk);
  endtask
  task automatic app_hdr(input coord_t d, input msg_type_e m, input logic [10:0] c, input int limit, output bit ok);
    automatic int n = 0;
    @(negedge clk); app_destination[3] = d; app_message[3] = m; app_control[3] = c; app_valid[3] = 1;
    do begin @(posedge clk); n++; end while (!app_ready[3] && n < limit);
    ok = app_ready[3]; @(negedge clk); app_valid[3] = 0;
  endtask
  task automatic app_words(input logic [31:0] w0, input logic [31:0] w1, input int nw, output bit ok);
    ok = 1;
    for (int i = 0; i < nw && ok; i++) begin
      automatic int n = 0;
      app_payload[3] = i == 0 ? w0 : w1; app_payload_valid[3] = 1;
      do begin @(posedge clk); n++; end while (!app_payload_ready[3] && n < 2000);
      ok = app_payload_ready[3]; @(negedge clk);
    end
    app_payload_valid[3] = 0;
  endtask
  // wait for one new app_rx HEAD at tile 3 and, for a read, its data word; got = a complete response arrived
  task automatic wait_rx(input int r0, input bit rd, input int limit, output bit got);
    automatic int n = 0;
    while (!(rx3 > r0 && (!rd || rx_seen_last)) && n < limit) begin @(negedge clk); n++; end
    got = rx3 == r0 + 1 && (!rd || rx_seen_last);
  endtask
  task automatic mem_write(input logic [31:0] a, input logic [31:0] d, input logic [3:0] be, output bit ok);
    automatic bit ok2 = 0; automatic int r0 = rx3;
    app_hdr(tile_to_coord(TILE_MEMORY), MSG_MEM_WR_REQ, {be, 7'b0}, 2000, ok);
    if (ok) app_words(a, d, 2, ok2);
    ok = ok && ok2; if (ok) exp_rx++;
    if (ok) wait_rx(r0, 0, 2000, ok);
    repeat (20) @(negedge clk);
  endtask
  task automatic mem_read(input logic [31:0] a, output bit ok);
    automatic bit ok2 = 0; automatic int r0 = rx3;
    app_hdr(tile_to_coord(TILE_MEMORY), MSG_MEM_RD_REQ, 11'h000, 2000, ok);
    if (ok) app_words(a, 0, 1, ok2);
    ok = ok && ok2; if (ok) exp_rx++;
    if (ok) wait_rx(r0, 1, 2000, ok);
    repeat (20) @(negedge clk);
  endtask
  // a read to tile 1 (a plain tile with no responder): its NI slot stays allocated
  task automatic stuck_read(output bit ok);
    automatic bit ok2 = 0;
    app_hdr(tile_to_coord(TILE_CPU1), MSG_MEM_RD_REQ, 11'h000, 2000, ok);
    if (ok) app_words(32'h2100_0000, 0, 1, ok2);
    ok = ok && ok2;
  endtask
  task automatic raw(input flit_t f);
    automatic int n = 0;
    automatic bit accepted = 0;
    @(negedge clk); spoof_raw_flit = f; spoof_raw_valid = 1;
    do begin @(posedge clk); n++; if(spoof_raw_valid && spoof_raw_ready)accepted=1; end while (!accepted && n < 2000);
    if(!accepted)$fatal(1,"I9_RAW_NOT_ACCEPTED: injection helper did not observe a flit handshake");
    @(negedge clk); spoof_raw_valid = 0;
  endtask
  // present one flit at tile 3's network input (bench hook), held until the tile accepts it
  task automatic inject3(input flit_t f, output bit ok);
    automatic int n = 0;
    @(negedge clk); dut.TBI.f[3] = f; dut.TBI.v[3] = 1;
    do begin @(posedge clk); n++; end while (!dut.mesh_or[3] && n < 2000);
    ok = dut.mesh_or[3]; @(negedge clk); dut.TBI.v[3] = 0;
  endtask
  // RD_RESP from tile 1 to tile 3 with the given tag and data word
  task automatic inject_rd_resp(input logic tag, input logic [31:0] d, output bit ok);
    automatic head_flit_t h; automatic flit_t f; automatic coord_t s, t; automatic bit ok2 = 0;   // set by statements
    h = '0; s = tile_to_coord(TILE_CPU1); t = tile_to_coord(TILE_CRYPTO);
    h.src_x = s.x; h.src_y = s.y; h.dest_x = t.x; h.dest_y = t.y; h.msg_type = MSG_MEM_RD_RESP; h.length = 5'd2;
    h.control.raw = {10'b0, tag};
    f.flit_data = h; f.flit_type = FLIT_HEAD; f.vc_id = 2'(message_to_vc(MSG_MEM_RD_RESP)); inject3(f, ok);
    f.flit_data = d; f.flit_type = FLIT_TAIL; if (ok) inject3(f, ok2);
    ok = ok && ok2;
  endtask

  initial begin
    bit ok, ok_a, ok_b, ok_c; int mark, c0, r0, b0, e0, bw0;
    $display("CONFIG: TOP=tb_i9_integ CHECKS=13 VERIFIER_TIMEOUT=3000 NI_SLOT_TIMEOUT=%0d MEM_ADDR_BITS=14", T_SLOT);
    app_valid = 0; app_payload_valid = 0; app_destination = '0; app_message = '0; app_control = 0; app_payload = 0;
    spoof_raw_flit = '0;
    load_chain(0); boot_epoch = BOOT; directed_keys = KEYS;
    do_reset();
    repeat (50) @(negedge clk);
    check(authorized == 0 && rx3 == 0 && bad_tile == 0, $sformatf("I9_RESET_STATE authorized=%b rx3=%0d other=%0d", authorized, rx3, bad_tile));
    attest(0, ok);
    check(ok, $sformatf("I9_GRANT authorized=%b", authorized));
    // WRITE / READ through the BRAM port
    c0 = memory_commits; bw0 = bram_wr;
    mem_write(32'h2200_0100, 32'h1900_0001, 4'hF, ok);
    check(ok && rx_last_msg == MSG_MEM_WR_RESP && rx_last_src == tile_to_coord(TILE_MEMORY) && rx_last_ctl[10] == 0 &&
          rx_last_on_head && bram[12'h040] == 32'h1900_0001 && memory_commits == c0 + 1 && bram_wr == bw0 + 1,
          $sformatf("I9_WRITE_RESP ok=%0b msg=%0d err=%0b last=%0b bram=%h commits=+%0d", ok, rx_last_msg, rx_last_ctl[10],
                    rx_last_on_head, bram[12'h040], memory_commits - c0));
    mem_read(32'h2200_0100, ok);
    check(ok && rx_last_msg == MSG_MEM_RD_RESP && rx_last_src == tile_to_coord(TILE_MEMORY) && rx_last_ctl[10] == 0 &&
          rx_n_data == 1 && rx_last_data == 32'h1900_0001 && !rx_last_on_head,
          $sformatf("I9_READ_DATA ok=%0b msg=%0d err=%0b words=%0d data=%h", ok, rx_last_msg, rx_last_ctl[10], rx_n_data, rx_last_data));
    mem_write(32'h2200_0100, 32'hAABB_CCDD, 4'b0101, ok_a);
    mem_read(32'h2200_0100, ok_b);
    check(ok_a && ok_b && rx_last_data == 32'h19BB_00DD, $sformatf("I9_BYTE_LANES data=%h", rx_last_data));
    // WINDOW: last word inside the 16 KB window, first word outside
    mem_write(32'h2200_3FFC, 32'h3FFC_A5A5, 4'hF, ok_a);
    mem_read(32'h2200_3FFC, ok_b);
    check(ok_a && ok_b && rx_last_ctl[10] == 0 && rx_last_data == 32'h3FFC_A5A5 && bram[12'hFFF] == 32'h3FFC_A5A5,
          $sformatf("I9_WINDOW_TOP_OK err=%0b data=%h bram=%h", rx_last_ctl[10], rx_last_data, bram[12'hFFF]));
    mark = recs.size(); e0 = bram_en;
    mem_read(32'h2200_4000, ok);
    check(ok && rx_last_ctl[10] == 1 && rx_last_data == 0 && bram_en == e0 && seen(mark, 3, MSG_MEM_RD_REQ, 13),
          $sformatf("I9_WINDOW_OUT_ERR ok=%0b err=%0b data=%h bram_access=+%0d", ok, rx_last_ctl[10], rx_last_data, bram_en - e0));
    // SPOOF: raw own-source write from tile 5 (not authorized) never reaches the BRAM
    begin
      automatic head_flit_t h; automatic flit_t f; automatic coord_t s, d;
      c0 = memory_commits; bw0 = bram_wr;
      h = '0; s = tile_to_coord(TILE_SPOOF); d = tile_to_coord(TILE_MEMORY);
      h.src_x = s.x; h.src_y = s.y; h.dest_x = d.x; h.dest_y = d.y; h.msg_type = MSG_MEM_WR_REQ; h.length = 5'd3;
      h.control.raw = 11'h780;
      f.flit_data = h; f.flit_type = FLIT_HEAD; f.vc_id = 2'(message_to_vc(MSG_MEM_WR_REQ)); raw(f);
      f.flit_data = 32'h2200_0200; f.flit_type = FLIT_BODY; raw(f);
      f.flit_data = 32'h5B00_F000; f.flit_type = FLIT_TAIL; raw(f);
      repeat (600) @(negedge clk);
      check(memory_commits == c0 && bram_wr == bw0 && bram[12'h080] == 0,
            $sformatf("I9_UNAUTH_NO_BRAM commits=+%0d bram_writes=+%0d", memory_commits - c0, bram_wr - bw0));
    end
    // SLOT LEAK and recovery (NI_SLOT_TIMEOUT)
    stuck_read(ok_a); stuck_read(ok_b);
    // the third request (a complete write) is sent in parallel: the tile-3 L2 wrapper may buffer it, but the NI has no slot
    begin
      automatic bit sent = 0, done = 0;
      r0 = rx3; c0 = memory_commits;
      fork
        begin
          automatic bit h = 0, w = 0;
          app_hdr(tile_to_coord(TILE_MEMORY), MSG_MEM_WR_REQ, 11'h780, 2 * T_SLOT + 400, h);
          if (h) app_words(32'h2200_0104, 32'h5107_0001, 2, w);
          sent = h && w; done = 1;
        end
      join_none
      repeat (300) @(negedge clk);
      check(ok_a && ok_b && rx3 == r0 && memory_commits == c0,
            $sformatf("I9_SLOT_HELD reads=%0b%0b responses=+%0d commits=+%0d", ok_a, ok_b, rx3 - r0, memory_commits - c0));
      begin
        automatic int n = 0;
        while (!(done && (!sent || rx3 > r0)) && n < 2 * T_SLOT + 4400) begin @(negedge clk); n++; end
      end
      if (sent) exp_rx++;
      check(sent && rx3 == r0 + 1 && rx_last_msg == MSG_MEM_WR_RESP && memory_commits == c0 + 1,
            $sformatf("I9_SLOT_RECOVER sent=%0b responses=+%0d commits=+%0d", sent, rx3 - r0, memory_commits - c0));
      disable fork;
    end
    repeat (2 * T_SLOT + 100) @(negedge clk);   // any slot left by the scenario above is freed
    // INJECTION PATH (positive): a fresh read to tile 1 (slot 0, tag 0) answered by an injected RD_RESP from tile 1
    stuck_read(ok_a); repeat (50) @(negedge clk);
    r0 = rx3; inject_rd_resp(1'b0, 32'h0001_2345, ok_b);
    if (ok_a && ok_b) exp_rx++;
    wait_rx(r0, 1, 500, ok);
    check(ok_a && ok_b && ok && rx_last_data == 32'h0001_2345 && rx_last_src == tile_to_coord(TILE_CPU1),
          $sformatf("I9_INJECT_PATH_LIVE sent=%0b%0b delivered=%0b data=%h", ok_a, ok_b, ok, rx_last_data));
    repeat (50) @(negedge clk);
    // STALE: two reads to tile 1 (tags 0, 1) left T_SLOT + 50 cycles, then an injected RD_RESP with tag 0
    stuck_read(ok_a); stuck_read(ok_b);
    repeat (T_SLOT + 50) @(negedge clk);
    r0 = rx3; inject_rd_resp(1'b0, 32'h0BAD_0BAD, ok_c);
    repeat (200) @(negedge clk);
    check(ok_a && ok_b && ok_c && rx3 == r0, $sformatf("I9_STALE_DROPPED sent=%0b%0b%0b new_rx_heads=%0d", ok_a, ok_b, ok_c, rx3 - r0));
    repeat (2 * T_SLOT + 100) @(negedge clk);
    check(bad_tile == 0 && bad_type == 0 && rx3 == exp_rx && ctl3 > 0 && bram_wr == n_commit,
          $sformatf("I9_RX_ACCOUNTED other_tiles=%0d bad_types=%0d rx3=%0d expected=%0d control_at_3=%0d bram_writes=%0d commits=%0d",
                    bad_tile, bad_type, rx3, exp_rx, ctl3, bram_wr, n_commit));
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 13 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #30ms; $display("TB_TIMEOUT global"); $finish; end
endmodule
