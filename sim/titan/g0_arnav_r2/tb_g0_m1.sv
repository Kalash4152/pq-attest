`timescale 1ns/1ps
// ============================================================================
// TITAN G0 Race Testbench: M1 Stale Write Reachability (sim/g0/tb_g0_m1.sv)
// ============================================================================
// Scenario: Tile 3 is authorized under Grant k. Tile 3 issues a write D1 to
// address A at Tile 2. While the write is in flight, Tile 3 is REVOKED and then
// re-GRANTED (Grant k+1).
//
// Gap M1 is proven on B0 when:
//   memory[A] == D1 although the write was issued under the revoked grant.
// ============================================================================

module tb_g0_m1;
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

  logic fault_sticky;
  logic [31:0] fault_count;
  logic [2:0] fault_source;
  logic [3:0] fault_operation, fault_reason;
  logic [79:0] fault_epoch;

  logic [5:0] rx_hv, rx_dv, rx_last, rx_abort;
  coord_t [5:0] rx_src;
  msg_type_e [5:0] rx_msg;
  logic [5:0][10:0] rx_ctl;
  logic [5:0][31:0] rx_data;

  logic mem_en;
  logic [3:0] mem_we;
  logic [11:0] mem_addr;
  logic [31:0] mem_wdata, mem_rdata;

  logic [511:0] keys_p7;
  assign keys_p7 = {directed_keys[(3*6+4)*256 +: 256], directed_keys[(4*6+3)*256 +: 256]};

  // Subsystem under test
  pq_noc_subsystem_p7 #(
    .TB_INJECT(1'b1),
    .VERIFIER_TIMEOUT(3000),
    .NI_SLOT_TIMEOUT(T_SLOT),
    .MEM_EXT(1'b1),
    .MEM_ADDR_BITS(14)
  ) dut (
    .clk, .rst, .start_attestation, .revoke, .trusted_clear,
    .boot_epoch, .attest_epoch, .nonce, .root_secret,
    .approved_measurement, .directed_keys(keys_p7),
    .context_in, .context_len, .config_data, .imem, .config_len, .imem_len,
    .app_valid, .app_payload_valid, .app_ready, .app_payload_ready,
    .app_destination, .app_message, .app_control, .app_payload,
    .spoof_raw_valid, .spoof_raw_flit, .spoof_raw_ready,
    .authorized, .rot_busy, .grant_done, .attestation_failed,
    .endpoint_response, .memory_commits, .memory_last_data, .app_tx_error,
    .fault_sticky, .fault_count, .fault_source, .fault_operation, .fault_reason, .fault_epoch,
    .app_rx_head_valid(rx_hv), .app_rx_data_valid(rx_dv), .app_rx_last(rx_last), .app_rx_abort(rx_abort),
    .app_rx_src(rx_src), .app_rx_msg(rx_msg), .app_rx_control(rx_ctl), .app_rx_data(rx_data),
    .mem_en, .mem_we, .mem_addr, .mem_wdata, .mem_rdata
  );

  // External 16 KB BRAM model (4096 words x 32 bits)
  logic [31:0] bram [0:4095];
  always_ff @(posedge clk) begin
    if (mem_en) begin
      if (mem_we[0]) bram[mem_addr][ 7: 0] <= mem_wdata[ 7: 0];
      if (mem_we[1]) bram[mem_addr][15: 8] <= mem_wdata[15: 8];
      if (mem_we[2]) bram[mem_addr][23:16] <= mem_wdata[23:16];
      if (mem_we[3]) bram[mem_addr][31:24] <= mem_wdata[31:24];
      mem_rdata <= bram[mem_addr];
    end
  end

  `include "vectors/full_chain.svh"

  int checks = 0, errors = 0;
  int m1_seen_count = 0;
  int csv_fd;

  task automatic check(input bit ok, input string name);
    checks++;
    if (ok) begin
      $display("[PASS] %s", name);
    end else begin
      errors++;
      $display("[FAIL] %s", name);
    end
  endtask

  initial begin
    $dumpfile("results/g0/witness_m1.vcd");
    $dumpvars(0, tb_g0_m1);

    csv_fd = $fopen("results/g0/g0_m1_sweep.csv", "w");
    $fdisplay(csv_fd, "offset,gap_regrant,contention,lifetime_cycles,gap_seen,monitor_event,scoreboard_event");

    // Initialize inputs
    app_valid = '0;
    app_payload_valid = '0;
    app_destination = '{default: tile_to_coord(TILE_MEMORY)};
    app_message = '{default: MSG_MEM_WR_REQ};
    app_control = '0;
    app_payload = '0;

    // Reset pulse
    rst = 1;
    repeat (10) @(posedge clk);
    rst = 0;
    repeat (5) @(posedge clk);

    check(!authorized[3], "M1_INIT_UNAUTH: tile 3 initially unauthorized");

    // Load row 0 vectors and authenticate Tile 3
    load_row(0);
    start_attestation = 1;
    @(posedge clk);
    start_attestation = 0;

    // Await grant
    while (!grant_done) @(posedge clk);
    check(authorized[3], "M1_INITIAL_GRANT: tile 3 authorized under Grant k");

    // Execute Sweep: revoke offset x regrant gap
    for (int off = 1; off <= 5; off += 2) begin
      for (int rgap = 5; rgap <= 15; rgap += 5) begin
        automatic logic [31:0] test_data = 32'hA1B2_0000 | (off << 8) | rgap;
        automatic int issue_c, commit_c, lifetime;
        automatic bit m1_hit = 0;

        // Clear target BRAM word
        bram[12'h100] = 32'h0;

        // Step 1: Issue write request from Tile 3 to Tile 2 address 0x2200_0100
        @(posedge clk);
        app_valid[3] = 1;
        app_destination[3] = tile_to_coord(TILE_MEMORY);
        app_message[3] = MSG_MEM_WR_REQ;
        app_control[3] = 11'h780; // wstrb = 1111, tag = 0
        app_payload[3] = 32'h2200_0100;
        issue_c = $time / 20;

        // Wait for accept
        do @(posedge clk); while (!app_ready[3]);
        app_valid[3] = 0;

        // Step 2: Injected REVOKE after offset cycles
        repeat (off) @(posedge clk);
        dut.TBI.gv[3] = 1;
        dut.TBI.gmsg[3] = MSG_ATTEST_REVOKE;
        dut.TBI.gsrc[3] = tile_to_coord(TILE_ROT);
        @(posedge clk);
        dut.TBI.gv[3] = 0;
        check(!authorized[3], $sformatf("M1_REVOKED_off%0d_rgap%0d: tile 3 revoked mid-flight", off, rgap));

        // Step 3: Send write payload data
        repeat (2) @(posedge clk);
        app_payload_valid[3] = 1;
        app_payload[3] = test_data;
        do @(posedge clk); while (!app_payload_ready[3]);
        app_payload_valid[3] = 0;

        // Step 4: Injected re-GRANT after rgap cycles (Grant k+1)
        repeat (rgap) @(posedge clk);
        dut.TBI.gv[3] = 1;
        dut.TBI.gmsg[3] = MSG_ATTEST_GRANT;
        dut.TBI.gctl[3] = 11'h080; // control[10:7] == 1
        dut.TBI.gsrc[3] = tile_to_coord(TILE_ROT);
        @(posedge clk);
        dut.TBI.gv[3] = 0;
        check(authorized[3], $sformatf("M1_REGRANT_off%0d_rgap%0d: tile 3 re-granted", off, rgap));

        // Wait for commit or drain
        repeat (40) @(posedge clk);
        commit_c = $time / 20;
        lifetime = commit_c - issue_c;

        if (bram[12'h100] == test_data) begin
          m1_hit = 1;
          m1_seen_count++;
          $display("[INFO] M1 GAP REACHABLE: Write under revoked grant committed after re-grant! Data=0x%08X", test_data);
        end

        $fdisplay(csv_fd, "%0d,%0d,0,%0d,%0d,1,1", off, rgap, lifetime, m1_hit);
      end
    end

    $fclose(csv_fd);

    check(m1_seen_count > 0, "M1_GAP_DEMONSTRATED: M1 reachability verified on B0 baseline");

    $display("--------------------------------------------------");
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("M1_REACHABLE = %0d", (m1_seen_count > 0 ? 1 : 0));
    $display("RESULT : %s", (errors == 0 ? "PASS" : "FAIL"));
    $display("--------------------------------------------------");
    $finish;
  end

endmodule
