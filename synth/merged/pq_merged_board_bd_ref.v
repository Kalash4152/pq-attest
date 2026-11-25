`timescale 1ns/1ps
//=============================================================================
// pq_merged_board_bd_ref -- plain-Verilog shell around pq_merged_board_top, for Vivado IP Integrator only.
//
// IP Integrator "module reference" cells need a Verilog (not SystemVerilog) top file. This shell adds NO logic: it
// instantiates the unmodified board top once and passes every port and parameter straight through. It is used only by
// scripts/create_project_block_design.tcl (block-diagram project); the release builds do not use it.
//=============================================================================
module pq_merged_board_bd_ref #(
    parameter integer DEBOUNCE_BITS    = 20,
    parameter integer AUTO_START_DELAY = 1024,
    parameter integer HEARTBEAT_BIT    = 24
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK100MHZ CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 100000000" *)
    input  wire       CLK100MHZ,      // 100 MHz board oscillator (E3); the 50 MHz design clock is made inside (MMCM)
    input  wire [2:0] btn,            // [0] reset, [1] re-attest, [2] revoke (asynchronous, synchronised inside)
    input  wire [0:0] sw,             // [0] UART select: 0 = CPU A (tile 3), 1 = CPU B (tile 0)
    output wire [3:0] led,
    output wire       led0_r,
    output wire       led0_g,
    output wire       uart_rxd_out    // FPGA TX -> USB-UART
);
    pq_merged_board_top #(
        .DEBOUNCE_BITS   (DEBOUNCE_BITS),
        .AUTO_START_DELAY(AUTO_START_DELAY),
        .HEARTBEAT_BIT   (HEARTBEAT_BIT)
    ) u_top (
        .CLK100MHZ   (CLK100MHZ),
        .btn         (btn),
        .sw          (sw),
        .led         (led),
        .led0_r      (led0_r),
        .led0_g      (led0_g),
        .uart_rxd_out(uart_rxd_out)
    );
endmodule
