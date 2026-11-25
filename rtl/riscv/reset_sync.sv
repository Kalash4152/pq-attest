
module reset_sync (
    input  logic clk_i,
    input  logic arst_i,
    input  logic locked_i,
    output logic reset_o
);

    logic [1:0] reset_pipe_q;

    always_ff @(posedge clk_i or posedge arst_i) begin
        if (arst_i) begin
            reset_pipe_q <= 2'b11;
        end
        else if (!locked_i) begin
            reset_pipe_q <= 2'b11;
        end
        else begin
            reset_pipe_q <= {reset_pipe_q[0], 1'b0};
        end
    end

    assign reset_o = reset_pipe_q[1];

endmodule