`timescale 1ns/1ps
// I-11 spec-literal NoC bench (Kalash 2026-11-06 "Triage + implement gaps"; council decision in reports/I11_GATE_*.md).
// Closes two oracle gaps found by triaging Engineer 4's Step 18 proposals: no registered bench observed (a) the XY order of
// the routing function (YX also delivers in the same hop count) or (b) the message-type -> VC map (every bench computes the
// expected VC with the same NOC_PKG function it would be testing). Expected values here are LITERALS from the spec,
// never from NOC_PKG functions:
//   - XY rule (M-F1 sec. 2 / NOC_XY_ROUTING.sv header): x first (Dx > Cx EAST, Dx < Cx WEST), then y (Dy > Cy SOUTH,
//     Dy < Cy NORTH), equal LOCAL; port encodings N 0, S 1, E 2, W 3, L 4 (NOC_PKG port_e, frozen in M-F1).
//   - VC map (M-F1 sec. 2 table): MEM_*_REQ -> 0, MEM_*_RESP -> 1, ATTEST_* -> 2; message types MEM_RD_REQ 0, MEM_RD_RESP 1,
//     MEM_WR_REQ 2, MEM_WR_RESP 3, ATTEST_CHALLENGE 4, RESPONSE 5, GRANT 6, REVOKE 7 (M-F1 rev 8 sec. 3 / 4).
// Checks (CHECKS = 44, frozen before the first run):
//   SPEC_XY_C<cx><cy>_D<dx><dy>   route_port == literal XY port and route_valid, every current x destination   36
//   SPEC_VC_MEM_REQ_<t>          t = 0, 2 -> VC 0                                                               2
//   SPEC_VC_MEM_RESP_<t>         t = 1, 3 -> VC 1                                                               2
//   SPEC_VC_ATTEST_<t>           t = 4..7 -> VC 2                                                               4
module tb_i11_noc_spec;
  import noc_pkg::*;
  int checks = 0, errors = 0;
  task automatic check(input bit ok, input string name);
    checks++; if (ok) $display("[PASS] %s", name); else begin errors++; $display("[FAIL] %s", name); end
  endtask
  coord_t cur, dst;
  port_id_t route_port;
  logic route_valid;
  noc_xy_routing dut(.current_coord(cur), .dest_coord(dst), .route_port(route_port), .route_valid(route_valid));
  function automatic int xy_port(input int cx, cy, dx, dy);   // literal XY rule
    if (dx > cx) return 2; if (dx < cx) return 3; if (dy > cy) return 1; if (dy < cy) return 0; return 4;
  endfunction
  initial begin
    $display("CONFIG: TOP=tb_i11_noc_spec CHECKS=44 MESH=3x2 SPEC=M-F1-literal");
    for (int cy = 0; cy < 2; cy++) for (int cx = 0; cx < 3; cx++)
      for (int dy = 0; dy < 2; dy++) for (int dx = 0; dx < 3; dx++) begin
        automatic int exp_p = xy_port(cx, cy, dx, dy);
        cur = '0; dst = '0; cur.x = cx; cur.y = cy; dst.x = dx; dst.y = dy;
        #1;
        check(route_valid === 1'b1 && int'(route_port) == exp_p,
              $sformatf("SPEC_XY_C%0d%0d_D%0d%0d port=%0d expected=%0d valid=%b", cx, cy, dx, dy, int'(route_port), exp_p, route_valid));
      end
    for (int t = 0; t < 8; t++) begin
      automatic int exp_vc = (t < 4) ? (t % 2) : 2;
      automatic int got = int'(message_to_vc(msg_type_e'(t)));
      automatic string cls = (t < 4) ? ((t % 2) ? "MEM_RESP" : "MEM_REQ") : "ATTEST";
      check(got == exp_vc, $sformatf("SPEC_VC_%s_%0d vc=%0d expected=%0d", cls, t, got, exp_vc));
    end
    $display("CHECKS : %0d", checks);
    $display("ERRORS : %0d", errors);
    $display("RESULT : %s", errors == 0 && checks == 44 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
