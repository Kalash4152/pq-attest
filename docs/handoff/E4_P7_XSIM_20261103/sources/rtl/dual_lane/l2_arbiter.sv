`timescale 1ns/1ps
// Shared L2 KMAC arbiter (M-F1 rev 7 R7.6 + R7.6a, A0 accepted 2026-10-21; docs/decisions/STEP_C_DESIGN_P7_L2_SHARED.md
// sec.2). Exactly the rule proven by scripts/arbiter_model.py:
//   requesters r0, r1 = class P (RoT-sourced), r2, r3 = class Q;
//   a grant is issued only while the engine is free and OVH idle cycles have passed since the last done;
//   P is granted unless 2 consecutive P grants were made while a Q request was pending, then Q is granted;
//   the consecutive-P counter resets on a Q grant and on a P grant made while no Q is pending;
//   A0: inside each class the pointer moves to the other requester after EVERY grant in that class; no pre-emption.
// Frozen bounds (R7.6a, J_MAX 128, OVH <= 4): wait from request to grant P <= 269, Q <= 792 cycles.
// A1 (no request while the requester's own job is in flight) and A3 (job <= J_MAX) are the callers' obligations and
// are asserted here; A2 (OVH <= 4) is a parameter check.
module l2_arbiter #(
    parameter int OVH = 1
)(
    input  logic       clk,
    input  logic       rst,
    input  logic [3:0] req,          // held high until granted (one outstanding job per requester)
    input  logic       done,         // one-cycle pulse: the granted job finished
    output logic       grant,        // one-cycle pulse
    output logic [1:0] grant_id,
    output logic       busy          // a granted job is in flight
);
    logic [1:0] owner;
    logic [2:0] idle;
    logic [1:0] consec;
    logic       rrp, rrq;            // A0 pointers: index of the next preferred requester inside P / Q
    logic       p0, p1, q0, q1, any_p, any_q, pick_p;
    logic [1:0] gp, gq;

    always_comb begin
        p0 = req[0]; p1 = req[1]; q0 = req[2]; q1 = req[3];
        any_p = p0 | p1; any_q = q0 | q1;
        gp = (rrp ? (p1 ? 2'd1 : 2'd0) : (p0 ? 2'd0 : 2'd1));
        gq = (rrq ? (q1 ? 2'd3 : 2'd2) : (q0 ? 2'd2 : 2'd3));
        pick_p   = any_p && !(consec >= 2 && any_q);
        grant    = !busy && idle == 0 && (any_p || any_q);
        grant_id = pick_p ? gp : gq;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0; owner <= '0; idle <= '0; consec <= '0; rrp <= 1'b0; rrq <= 1'b0;
        end else begin
            if (grant) begin
                busy <= 1'b1; owner <= grant_id;
                if (pick_p) begin
                    consec <= any_q ? ((consec == 2'd3) ? 2'd3 : consec + 2'd1) : 2'd0;
                    rrp    <= (grant_id == 2'd0);                 // A0: prefer the other P requester next
                end else begin
                    consec <= 2'd0;
                    rrq    <= (grant_id == 2'd2);                 // A0: prefer the other Q requester next
                end
            end else if (busy && done) begin
                busy <= 1'b0; idle <= 3'(OVH);
            end else if (!busy && idle != 0) begin
                idle <= idle - 3'd1;
            end
        end
    end

    // synthesis translate_off
    initial if (OVH > 4) $fatal(1, "l2_arbiter: OVH=%0d violates A2 (OVH <= 4)", OVH);
    always_ff @(posedge clk) if (!rst) begin
        if (busy && req[owner]) $error("l2_arbiter: A1 violated, requester %0d requests while its own job is in flight", owner);
        if (done && !busy)      $error("l2_arbiter: done without a granted job");
    end
    // synthesis translate_on
endmodule
