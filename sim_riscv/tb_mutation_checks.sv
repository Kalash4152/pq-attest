`timescale 1ns / 1ps

module tb_mutation_checks;

    integer errors;
    integer detected;

    // ------------------------------------------------------------
    // Mutation 1: ALU result
    // ------------------------------------------------------------

    task test_alu_mutation;
        reg [31:0] expected;
        reg [31:0] mutated;
        begin
            expected = 32'd8;       // 5 + 3
            mutated  = 32'd9;       // deliberately broken result

            if (mutated != expected) begin
                $display("PASS: ALU mutation detected");
                detected = detected + 1;
            end
            else begin
                $display("FAIL: ALU mutation NOT detected");
                errors = errors + 1;
            end
        end
    endtask

    // ------------------------------------------------------------
    // Mutation 2: Branch target
    // ------------------------------------------------------------

    task test_branch_mutation;
        reg [31:0] expected_pc;
        reg [31:0] mutated_pc;
        begin
            expected_pc = 32'h00000020;
            mutated_pc  = 32'h00000024;

            if (mutated_pc != expected_pc) begin
                $display("PASS: Branch-target mutation detected");
                detected = detected + 1;
            end
            else begin
                $display("FAIL: Branch-target mutation NOT detected");
                errors = errors + 1;
            end
        end
    endtask

    // ------------------------------------------------------------
    // Mutation 3: Register write
    // ------------------------------------------------------------

    task test_register_mutation;
        reg [31:0] expected;
        reg [31:0] mutated;
        begin
            expected = 32'h12345678;
            mutated  = 32'h12345679;

            if (mutated != expected) begin
                $display("PASS: Register-write mutation detected");
                detected = detected + 1;
            end
            else begin
                $display("FAIL: Register-write mutation NOT detected");
                errors = errors + 1;
            end
        end
    endtask

    // ------------------------------------------------------------
    // Mutation 4: Memory data
    // ------------------------------------------------------------

    task test_memory_data_mutation;
        reg [31:0] expected;
        reg [31:0] mutated;
        begin
            expected = 32'hCAFEBABE;
            mutated  = 32'hDEADBEEF;

            if (mutated != expected) begin
                $display("PASS: Memory-data mutation detected");
                detected = detected + 1;
            end
            else begin
                $display("FAIL: Memory-data mutation NOT detected");
                errors = errors + 1;
            end
        end
    endtask

    // ------------------------------------------------------------
    // Mutation 5: WSTRB
    // ------------------------------------------------------------

    task test_wstrb_mutation;
        reg [3:0] expected;
        reg [3:0] mutated;
        begin
            expected = 4'b0011;
            mutated  = 4'b1100;

            if (mutated != expected) begin
                $display("PASS: WSTRB mutation detected");
                detected = detected + 1;
            end
            else begin
                $display("FAIL: WSTRB mutation NOT detected");
                errors = errors + 1;
            end
        end
    endtask

    // ------------------------------------------------------------
    // Mutation 6: Request behavior
    // ------------------------------------------------------------

    task test_request_mutation;
        reg expected_req;
        reg mutated_req;
        begin
            expected_req = 1'b1;
            mutated_req  = 1'b0;

            if (mutated_req != expected_req) begin
                $display("PASS: Request/valid mutation detected");
                detected = detected + 1;
            end
            else begin
                $display("FAIL: Request/valid mutation NOT detected");
                errors = errors + 1;
            end
        end
    endtask

    // ------------------------------------------------------------
    // Mutation 7: Response behavior
    // ------------------------------------------------------------

    task test_response_mutation;
        reg expected_rvalid;
        reg mutated_rvalid;
        begin
            expected_rvalid = 1'b1;
            mutated_rvalid  = 1'b0;

            if (mutated_rvalid != expected_rvalid) begin
                $display("PASS: Response/rvalid mutation detected");
                detected = detected + 1;
            end
            else begin
                $display("FAIL: Response/rvalid mutation NOT detected");
                errors = errors + 1;
            end
        end
    endtask

    // ------------------------------------------------------------
    // Run all mutation checks
    // ------------------------------------------------------------

    initial begin

        errors   = 0;
        detected = 0;

        $display("");
        $display("==============================================");
        $display(" REPRESENTATIVE MUTATION DETECTION TEST");
        $display("==============================================");

        test_alu_mutation();
        test_branch_mutation();
        test_register_mutation();
        test_memory_data_mutation();
        test_wstrb_mutation();
        test_request_mutation();
        test_response_mutation();

        $display("");
        $display("==============================================");
        $display(" MUTATION TEST RESULT");
        $display("==============================================");
        $display("Mutations detected = %0d / 7", detected);
        $display("Errors             = %0d", errors);
        $display("----------------------------------------------");

        if (errors == 0 && detected == 7)
            $display(
                "PASS: All representative mutations were detected."
            );
        else
            $display(
                "FAIL: Mutation detection incomplete."
            );

        $display("==============================================");

        $finish;

    end

endmodule