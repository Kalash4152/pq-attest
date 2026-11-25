`timescale 1ns/1ps
// M-F1 rev 11 H2. The app owns the strobes; the NI owns the tag.
module titan_epoch_stamp #(
    parameter int EPOCH_W = 6
)(
    input logic clk, rst,
    input logic valid, ready,
    input noc_pkg::msg_type_e message_type,
    input logic [10:0] app_control,
    input logic [EPOCH_W-1:0] epoch,
    output logic [10:0] stamped_control
);
    import titan_pkg::*;
    logic hold_valid;
    logic [EPOCH_W-1:0] held_epoch, stamp_epoch;
    logic memory_head;

    assign memory_head = is_mem_req(message_type);
    assign stamp_epoch = hold_valid ? held_epoch : epoch;
    assign stamped_control = memory_head ? set_epoch(app_control, EPOCH_W_MAX'(stamp_epoch)) : app_control;

    always_ff @(posedge clk) begin
        if (rst) begin
            hold_valid <= 0;
            held_epoch <= '0;
        end else if (!valid || ready || !memory_head) begin
            hold_valid <= 0;
        end else if (!hold_valid) begin
            held_epoch <= epoch;
            hold_valid <= 1;
        end
    end
endmodule
