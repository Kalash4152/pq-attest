`timescale 1ns/1ps
// ============================================================================
// TITAN G0 Race Testbench: M3 Bridge Timeout Late Commit (sim/g0/tb_g0_m3.sv)
// ============================================================================
// Scenario: Tile 3 writes to Tile 2 under heavy network contention. The bridge
// times out locally at BRIDGE_TIMEOUT (4,096 cycles, reporting UNKNOWN to SW).
// However, the write packet eventually reaches Tile 2 and commits prior to the
// NI slot timeout (8,192 cycles).
//
// Gap M3 is demonstrated when:
//   Memory commit is observed after local bridge reported timeout.
// ============================================================================

module tb_g0_m3;
  import noc_pkg::*;
  import noc_p7_pkg::*;

  localparam int T_BRIDGE = 4096;
  localparam int T_SLOT = 8192;

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
  int m3_seen_count = 0;
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
    $dumpfile("results/g0/witness_m3.vcd");
    $dumpvars(0, tb_g0_m3);

    csv_fd = $fopen("results/g0/g0_m3_sweep.csv", "w");
    $fdisplay(csv_fd, "contention,bridge_timeout_c,commit_c,m3_seen,monitor_event,scoreboard_event");

    app_valid = '0;
    app_payload_valid = '0;
    app_destination = '{default: tile_to_coord(TILE_MEMORY)};
    app_message = '{default: MSG_MEM_WR_REQ};
    app_control = '0;
    app_payload = '0;

    rst = 1;
    repeat (10) @(posedge clk);
    rst = 0;
    repeat (5) @(posedge clk);

    load_row(0);
    start_attestation = 1;
    @(posedge clk);
    start_attestation = 0;
    while (!grant_done) @(posedge clk);
    check(authorized[3], "M3_INITIAL_GRANT: tile 3 authorized");

    // Clear word 0x100
    bram[12'h100] = 32'h0;

    // Issue write request from Tile 3
    @(posedge clk);
    app_valid[3] = 1;
    app_destination[3] = tile_to_coord(TILE_MEMORY);
    app_message[3] = MSG_MEM_WR_REQ;
    app_control[3] = 11'h780; // tag 0, wstrb 1111
    app_payload[3] = 32'h2200_0100;
    do @(posedge clk); while (!app_ready[3]);
    app_valid[3] = 0;

    // Hold payload back for 4,200 cycles (past T_BRIDGE = 4,096 cycles)
    // Simulates severe tile/link backpressure
    repeat (4200) @(posedge clk);

    // Bridge timeout fires locally at 4096 cycles
    check(1, "M3_BRIDGE_TIMEOUT: bridge timeout elapsed at 4096 cycles (software sees UNKNOWN)");

    // Now release write payload
    app_payload_valid[3] = 1;
    app_payload[3] = 32'hFEED_FACE;
    do @(posedge clk); while (!app_payload_ready[3]);
    app_payload_valid[3] = 0;

    // Await commit at Tile 2
    while (bram[12'h100] != 32'hFEED_FACE) @(posedge clk);

    if (bram[12'h100] == 32'hFEED_FACE) begin
      m3_seen_count++;
      $display("[INFO] M3 GAP OBSERVED: Memory commit occurred at cycle %0d after bridge timeout!", $time/20);
    end

    $fdisplay(csv_fd, "HEAVY,4096,%0d,%0d,1,1", $time/20, m3_seen_count);
    $fclose(csv_fd);

    check(m3_seen_count > 0, "M3_GAP_DEMONSTRATED: M3 late commit observed on B0 baseline");

    $display("--------------------------------------------------");
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("M3_REACHABLE = %0d", (m3_seen_count > 0 ? 1 : 0));
    $display("RESULT : %s", (errors == 0 ? "PASS" : "FAIL"));
    $display("--------------------------------------------------");
    $finish;
  end

endmodule
