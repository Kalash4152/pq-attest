`timescale 1ns / 1ps

module gpio (
    input  logic        clk_i,
    input  logic        reset_i,

    input  logic        req_i,
    input  logic        we_i,
    input  logic [31:0] addr_i,
    input  logic [31:0] wdata_i,
    input  logic [3:0]  wstrb_i,

    output logic        gnt_o,
    output logic        rvalid_o,
    output logic [31:0] rdata_o,
    output logic        err_o,

    input  logic [3:0]  switches_i,
    output logic [3:0]  leds_o
);

    // GPIO accepts a request immediately.
    assign gnt_o = 1'b1;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            rvalid_o <= 1'b0;
            rdata_o  <= 32'b0;
            err_o    <= 1'b0;
            leds_o   <= 4'b0;
        end
        else begin
            rvalid_o <= 1'b0;
            err_o    <= 1'b0;

            if (req_i) begin
                rvalid_o <= 1'b1;

                case (addr_i)

                    // ------------------------------------------------
                    // LED register: offset 0x00
                    // ------------------------------------------------
                    32'h0000_0000: begin
                        rdata_o <= {28'b0, leds_o};

                        if (we_i && wstrb_i[0])
                            leds_o <= wdata_i[3:0];
                    end

                    // ------------------------------------------------
                    // Switch register: offset 0x04
                    // ------------------------------------------------
                    32'h0000_0004: begin
                        rdata_o <= {28'b0, switches_i};

                        // Switches are read-only.
                        if (we_i)
                            err_o <= 1'b1;
                    end

                    // ------------------------------------------------
                    // Invalid offset
                    // ------------------------------------------------
                    default: begin
                        rdata_o <= 32'b0;
                        err_o   <= 1'b1;
                    end

                endcase
            end
        end
    end

endmodule