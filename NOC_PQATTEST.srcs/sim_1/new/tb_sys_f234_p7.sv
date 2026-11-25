`timescale 1ns/1ps
// tb_sys_f234 in P7 mode (pq_noc_subsystem_p7): the define is set here, in the source, so that the Vivado export sees the
// P7 hierarchy (job defines are applied only at compile time). Body: sim/dual_lane/f234/tb_sys_f234_body.svh. Counts: 26.
`define F234_P7
module tb_sys_f234;
`include "tb_sys_f234_body.svh"
endmodule
