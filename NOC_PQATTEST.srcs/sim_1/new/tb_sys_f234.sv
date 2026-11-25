`timescale 1ns/1ps
// tb_sys_f234 (rev-6 subsystem): F2/F3/F4 reproducers. The bench body is sim/dual_lane/f234/tb_sys_f234_body.svh
// (shared with tb_sys_f234_p7.sv); jobs list sim/dual_lane/f234 as an include dir. Counts: 26 (see the body header).
module tb_sys_f234;
`include "tb_sys_f234_body.svh"
endmodule
