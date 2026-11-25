// M9.2 only. Uses the frozen Stage-4 DUT and camera model without edits.
// +FALL_ONLY selects the symmetric falling case; +LEGACY_OR selects a
// deliberately incorrect CHECKER, not a production RTL mutation.
`timescale 1ns/1ps
`default_nettype none
module tb_m9_s308;
  localparam integer W = 8, H = 4, WB = 2*W, LOG_SIZE = 2048;
  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0;
  reg [3:0] sw = 4'b0001;
  wire [3:0] led;
  wire uart_out, xclk, pwdn, pclk_m, href_m, vsync_m;
  wire [9:0] dat_m;
  tri scl, sda;
  pullup(scl); pullup(sda);

  integer target_fall = 0, legacy_checker = 0;
  integer inject_mode = 0;  // 0 clean, 1 rising XOR, 2 falling XOR
  // Identical timing boundary to Stage-4 tb_stage4: delay the sensor outputs
  // by 1 ns; delay only the injection phase selector by 2 ns. At each real
  // sampling edge the selector still describes the preceding half cycle.
  // These are SIMULATION stimulus delays, not physical timing assumptions.
  wire href_d, vsync_d, pclk_phase;
  wire [9:0] dat_delayed, dat_d;
  assign #1 href_d = href_m;
  assign #1 vsync_d = vsync_m;
  assign #1 dat_delayed = dat_m;
  assign #2 pclk_phase = pclk_m;
  wire corrupt_now = ((inject_mode == 1) && !pclk_phase) ||
                     ((inject_mode == 2) &&  pclk_phase);
  assign dat_d = dat_delayed ^ (corrupt_now ? 10'h0F0 : 10'h000);

  ov5642_arty_top #(.CLK_HZ(100_000_000), .BAUD(10_000_000),
    .SCL_HZ(5_000_000), .MS_DIV(100), .EXP_W(W), .EXP_H(H),
    .FB_BYTES(W*H*2)) dut (
    .CLK100MHZ(clk), .ck_rst(rst_n), .sw(sw), .btn(4'b0), .led(led),
    .uart_rxd_out(uart_out), .uart_txd_in(1'b1), .cam_xclk(xclk),
    .cam_pwdn(pwdn), .cam_scl(scl), .cam_sda(sda), .cam_pclk(pclk_m),
    .cam_href(href_d), .cam_vsync(vsync_d), .cam_d(dat_d));
  ov5642_model #(.W_BYTES(WB), .H(H), .PCLK_NS(40.0)) cam (
    .xclk(xclk), .pwdn(pwdn), .scl(scl), .sda(sda), .pclk(pclk_m),
    .href(href_m), .vsync(vsync_m), .d(dat_m), .d10_fault(1'b0));

  function automatic [31:0] crc_byte(input [31:0] c, input [7:0] b);
    reg [31:0] x;
    integer j;
    begin
      x = c ^ {24'd0,b};
      for (j=0; j<8; j=j+1)
        x = x[0] ? ((x>>1)^32'hEDB88320) : (x>>1);
      crc_byte = x;
    end
  endfunction
  // Argument avoids the frozen bench's zero-argument XSim function issue.
  function automatic [31:0] frame_crc(input [7:0] xor_mask);
    reg [31:0] c;
    reg [7:0] b;
    integer l, k;
    begin
      c = 32'hFFFFFFFF;
      for (l=0; l<H; l=l+1) for (k=0; k<WB; k=k+1) begin
        b = ((k*37)+(l*11)+8'h5A) & 8'hFF;
        c = crc_byte(c,b^xor_mask);
      end
      frame_crc = ~c;
    end
  endfunction

  reg [31:0] golden_crc, wrong_crc;
  integer checks = 0, failures = 0, negative_hits = 0;
  task automatic check(input bit cond, input string label_text);
    begin
      checks = checks+1;
      if (!cond) begin
        failures = failures+1;
        $display("M9_CHECK_FAIL %0s t=%0t",label_text,$time);
      end
    end
  endtask

  integer frame_id = 0;
  integer frame_mode [0:LOG_SIZE-1];
  integer i, trace;
  initial begin
    for (i=0; i<LOG_SIZE; i=i+1) frame_mode[i]=0;
    trace = $fopen("m9_s308_trace.csv","w");
    if (trace == 0) $fatal(1,"M9_TRACE_OPEN_FAILED");
    $fdisplay(trace,"time_ns,frame_id,mode,wrong_ordinal,recovery_ordinal,rise_crc,fall_crc,rise_repeat,fall_repeat,legacy_detect,edge_detect,checker_detect,frames,lines,bmin,bmax,selected_fall");
  end
  always @(posedge vsync_d) begin
    frame_id = frame_id+1;
    if (frame_id >= LOG_SIZE) $fatal(1,"M9_FRAME_LOG_OVERFLOW");
  end
  // Driver updates at camera VSYNC-fall +2 ns; this logger runs at +4 ns.
  // The first line starts much later. No control changes on a data sample.
  always @(negedge vsync_d) begin
    #3;
    frame_mode[frame_id] = inject_mode;
  end

  integer armed = 0, clean_run = 0, wrong_count = 0, recovery_count = 0;
  integer pub_count = 0, saw_second = 0, saw_third = 0;
  reg have_raw = 0;
  reg [31:0] prev_rise = 0, prev_fall = 0;
  reg [15:0] ref_rise_repeat = 0, ref_fall_repeat = 0;
  reg [31:0] previous_frames = 0;
  integer have_frames = 0;

  // Snapshot event BEFORE NBA; inspect registered status and counters AFTER
  // NBA. Raw-counter history is maintained from reset, including warmup.
  always @(posedge clk) begin : publication_check
    reg ev, disc, stale_event;
    reg [31:0] in_rise, in_fall, in_frames;
    reg [31:0] exp_rise, exp_fall;
    integer fid, mode, is_wrong, legacy_detect, edge_detect, checker_detect;
    ev = dut.pub_ev;
    disc = dut.discard_ev;
    stale_event = dut.stale_now;
    if (dut.rst || dut.init_start) begin
      have_raw = 0; ref_rise_repeat = 0; ref_fall_repeat = 0;
      have_frames = 0;
    end else if (ev) begin
      in_rise = dut.p_crc_rise; in_fall = dut.p_crc_fall;
      in_frames = dut.p_frames;
      if (have_raw && !disc) begin
        ref_rise_repeat = (in_rise === prev_rise) ?
          ((&ref_rise_repeat) ? ref_rise_repeat : ref_rise_repeat+16'd1) : 16'd0;
        ref_fall_repeat = (in_fall === prev_fall) ?
          ((&ref_fall_repeat) ? ref_fall_repeat : ref_fall_repeat+16'd1) : 16'd0;
      end else begin ref_rise_repeat=0; ref_fall_repeat=0; end
      have_raw=1; prev_rise=in_rise; prev_fall=in_fall;
      fid = frame_id-1;
      if (fid < 0 || fid >= LOG_SIZE) $fatal(1,"M9_BAD_FRAME_INDEX");
      mode = frame_mode[fid];
      exp_rise = (mode == 1) ? wrong_crc : golden_crc;
      exp_fall = (mode == 2) ? wrong_crc : golden_crc;
      #1;
      if (armed) begin
        pub_count=pub_count+1;
        check(!disc,"NO_DISCARD_WITH_PUBLICATION");
        check(dut.s_crc_rise === exp_rise,"EXACT_RISING_CONTENT");
        check(dut.s_crc_fall === exp_fall,"EXACT_FALLING_CONTENT");
        check(dut.crc_rep_rise === ref_rise_repeat,"RISING_COUNTER_RECURRENCE");
        check(dut.crc_rep_fall === ref_fall_repeat,"FALLING_COUNTER_RECURRENCE");
        check(dut.s_lines === 16'(H) && dut.s_bpl === 16'(WB) &&
              dut.s_bmin === 16'(WB) && dut.s_bmax === 16'(WB),"COMPLETE_GEOMETRY");
        check(dut.s_pub_sel_neg === (target_fall != 0),"SELECTED_EDGE_PROVENANCE");
        check(dut.s_crc === ((target_fall != 0) ? exp_fall : exp_rise),"SELECTED_CONTENT");
        check(dut.s_frames === in_frames,"PUBLISHED_FRAME_COUNTER_TRANSFER");
        if (have_frames) check(dut.s_frames === previous_frames+32'd1,"PUBLICATION_CONTINUES");
        have_frames=1; previous_frames=dut.s_frames;
        is_wrong = (mode != 0);
        if (is_wrong) begin
          check(mode == (target_fall ? 2 : 1),"ONLY_TARGET_EDGE_CORRUPTED");
          wrong_count=wrong_count+1; clean_run=0;
        end else if (wrong_count > 0) recovery_count=recovery_count+1;
        else clean_run=clean_run+1;
        legacy_detect = ((dut.s_crc_rise !== golden_crc) ||
                         (dut.s_crc_fall !== golden_crc)) &&
                        ((dut.crc_rep_rise >= 2) || (dut.crc_rep_fall >= 2));
        edge_detect = target_fall ? ((dut.s_crc_fall !== golden_crc) && (dut.crc_rep_fall >= 2)) :
                                    ((dut.s_crc_rise !== golden_crc) && (dut.crc_rep_rise >= 2));
        checker_detect = legacy_checker ? legacy_detect : edge_detect;
        if (is_wrong && wrong_count == 1) begin
          check((target_fall ? dut.crc_rep_fall : dut.crc_rep_rise) == 0,"FIRST_WRONG_ACQUIRES_BASELINE");
          check(edge_detect == 0,"FIRST_WRONG_NOT_REPEATABLE_YET");
        end
        if (is_wrong && wrong_count == 2) begin
          saw_second=1;
          check((target_fall ? dut.crc_rep_fall : dut.crc_rep_rise) == 1,"SECOND_WRONG_ONE_EQUAL_COMPARISON");
          check((target_fall ? dut.crc_rep_rise : dut.crc_rep_fall) >= 2,"CLEAN_EDGE_ALREADY_REPEATABLE");
          check(legacy_detect == 1 && edge_detect == 0,"LEGACY_OR_WEAKNESS_DEMONSTRATED");
          check(checker_detect == 0,"WRONG_EDGE_STABILITY_TOO_EARLY");
          if (legacy_checker && checker_detect == 1 && edge_detect == 0) begin
            negative_hits=negative_hits+1;
            $display("M9_NEGATIVE_CAUGHT edge=%0s wrong_ordinal=2 legacy=1 edge_detect=0",
                     target_fall ? "falling" : "rising");
          end
        end
        if (is_wrong && wrong_count == 3) begin
          saw_third=1;
          check((target_fall ? dut.crc_rep_fall : dut.crc_rep_rise) == 2,"THIRD_WRONG_TWO_EQUAL_COMPARISONS");
          check(edge_detect == 1 && checker_detect == 1,"THIRD_WRONG_TARGET_DETECTS");
        end
        if (!is_wrong && wrong_count > 0) begin
          check(legacy_detect == 0 && edge_detect == 0,"RECOVERY_IS_GOLDEN");
          check((target_fall ? dut.crc_rep_fall : dut.crc_rep_rise) == recovery_count-1,
                "RECOVERY_TARGET_HISTORY_REACQUIRES");
          check((target_fall ? dut.crc_rep_rise : dut.crc_rep_fall) >= 2,
                "RECOVERY_CLEAN_HISTORY_PRESERVED");
        end
        $fdisplay(trace,"%0d,%0d,%0d,%0d,%0d,%08h,%08h,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
          $time,fid,mode,is_wrong ? wrong_count : 0,recovery_count,
          dut.s_crc_rise,dut.s_crc_fall,dut.crc_rep_rise,dut.crc_rep_fall,
          legacy_detect,edge_detect,checker_detect,dut.s_frames,dut.s_lines,
          dut.s_bmin,dut.s_bmax,dut.s_pub_sel_neg);
        $display("M9_PUBLISH frame=%0d mode=%0d wrong_n=%0d recovery_n=%0d rr=%0d rf=%0d legacy=%0d new=%0d",
          fid,mode,is_wrong ? wrong_count : 0,recovery_count,dut.crc_rep_rise,
          dut.crc_rep_fall,legacy_detect,edge_detect);
      end
    end else if (disc || stale_event) begin
      have_raw=0; ref_rise_repeat=0; ref_fall_repeat=0;
      if (armed) check(0,"UNEXPECTED_HISTORY_BREAK");
    end
  end

  initial begin : scenario
    target_fall = $test$plusargs("FALL_ONLY");
    legacy_checker = $test$plusargs("LEGACY_OR");
    sw = target_fall ? 4'b0011 : 4'b0001;
    golden_crc=frame_crc(8'h00); wrong_crc=frame_crc(8'h3C);
    check(golden_crc === 32'h9FC463F2,"INDEPENDENT_GOLDEN_ANCHOR");
    check(wrong_crc === 32'hB86B8460 && wrong_crc != golden_crc,"INDEPENDENT_WRONG_ANCHOR");
    $display("M9_CONFIG edge=%0s checker=%0s golden=%08h wrong=%08h",
      target_fall ? "falling" : "rising",legacy_checker ? "legacy_or" : "per_edge",golden_crc,wrong_crc);
    #100; rst_n=1;
    wait(dut.init_done === 1'b1);
    // Exclude configuration-time frames by waiting for complete frame
    // boundaries, then require four observed clean publications explicitly.
    repeat (3) @(posedge vsync_m);
    @(negedge clk); armed=1;
    wait(clean_run >= 4);
    @(negedge vsync_m); #2; inject_mode=target_fall ? 2 : 1;
    wait(wrong_count >= 3);
    @(negedge vsync_m); #2; inject_mode=0;
    wait(recovery_count >= 3);
    @(negedge clk);
    check(saw_second && saw_third && wrong_count == 3,"EXACT_THREE_WRONG_PUBLICATIONS");
    check(recovery_count == 3 && clean_run == 0,"THREE_RECOVERY_PUBLICATIONS");
    check(legacy_checker ? negative_hits == 1 : negative_hits == 0,"NEGATIVE_CONTROL_CARDINALITY");
    $fclose(trace);
    $display("M9_SUMMARY checks=%0d failures=%0d wrong=%0d recovery=%0d negative_hits=%0d",
      checks,failures,wrong_count,recovery_count,negative_hits);
    $display("M9_STATUS=%0s",failures == 0 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin
    #20_000_000;
    $display("M9_TIMEOUT");
    $fatal(1,"M9.2 watchdog expired");
  end
endmodule
`default_nettype wire
