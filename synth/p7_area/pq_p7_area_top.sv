`timescale 1ns/1ps
//=============================================================================
// Module : pq_p7_area_top   (accurate-area bitstream for the Arty A7-100T; Kalash 2026-11-03)
// Purpose: a bitstream whose area is the real area of the release P7 subsystem. It wraps the N-13 secure top
//          synth/n13/pq_p7_n13_top.sv (every subsystem input from a run-time serial shift chain, every output folded
//          into a 64-bit MISR), so, unlike the demo wrapper synth/p7_board/pq_p7_board_top.sv, nothing constant-folds.
// Clock  : CLK100MHZ (E3) -> MMCME2_BASE (x10 / 20) -> 50 MHz (20 ns), as the demo wrapper, so the image is board-safe.
// Reset  : btn[0] or MMCM not locked -> 2-FF sync -> active-HIGH rst.
// I/O    : sw[0] = sdi, sw[1] = shift enable (both 2-FF synchronised); led[0] = sdo (MISR), led[1] = MMCM locked.
// Function on the board is not a demo (inputs are whatever is shifted in); use the demo wrapper to see attestation.
// Not evidence: the registered area / timing are N-13 (reports/I8_GATE_20261103.md).
//=============================================================================
module pq_p7_area_top (
    input  logic       CLK100MHZ,
    input  logic [0:0] btn,
    input  logic [1:0] sw,
    output logic [1:0] led
);
    logic clk_fb, clk_fb_buf, clk50_mmcm, clk, locked;
    MMCME2_BASE #(.CLKIN1_PERIOD(10.0), .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(10.0), .CLKOUT0_DIVIDE_F(20.0)) u_mmcm (
        .CLKIN1(CLK100MHZ), .CLKFBIN(clk_fb_buf), .CLKFBOUT(clk_fb), .CLKFBOUTB(),
        .CLKOUT0(clk50_mmcm), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0));
    BUFG u_bufg_fb  (.I(clk_fb),     .O(clk_fb_buf));
    BUFG u_bufg_clk (.I(clk50_mmcm), .O(clk));

    logic [1:0] rst_s, sdi_s, sen_s;
    always_ff @(posedge clk or negedge locked)
        if (!locked) rst_s <= 2'b11;
        else         rst_s <= {rst_s[0], btn[0]};
    always_ff @(posedge clk) begin
        sdi_s <= {sdi_s[0], sw[0]};
        sen_s <= {sen_s[0], sw[1]};
    end
    pq_p7_n13_top u_n13 (.clk, .rst(rst_s[1]), .sdi(sdi_s[1]), .sen(sen_s[1]), .sdo(led[0]));
    assign led[1] = locked;
endmodule
