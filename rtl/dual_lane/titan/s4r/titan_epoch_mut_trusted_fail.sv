`timescale 1ns/1ps
module titan_epoch_tracker_r1 #(parameter int EPOCH_W=6)(
    input logic clk, rst, authorized, trusted_fail,
    output logic [EPOCH_W-1:0] epoch_o,
    output logic epoch_wrap_o
);
    logic was_authorized;
    logic [EPOCH_W-1:0] settled_epoch;
    logic advance;
    // The gate updates authorization after the clock edge. Present the new
    // epoch for that entire authorized cycle, then settle it on the next edge.
    assign advance = (authorized && !was_authorized) || trusted_fail;
    assign epoch_o = settled_epoch + EPOCH_W'(advance);
    assign epoch_wrap_o = advance && (&settled_epoch);
    always_ff @(posedge clk) begin
        if (rst) begin
            was_authorized <= 0;
            settled_epoch <= '0;
        end else begin
            was_authorized <= authorized;
            settled_epoch <= epoch_o;
        end
    end
endmodule
