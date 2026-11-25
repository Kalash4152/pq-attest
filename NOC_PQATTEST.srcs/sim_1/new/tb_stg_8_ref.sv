`timescale 1ns/1ps
//=============================================================================
// tb_stg_8_ref - Stage 8 controller: exact-response reference-chain testbench
//
// DUT : pq_attestation_controller (pq_attest_protocol.sv)
// REF : a SEPARATE chain of the already-verified Stage 5/6/7 modules
//       (pq_kdf -> pq_measurement -> pq_attestation_tag) driven by this TB's
//       own sequencer, and the 776-bit response assembled HERE from the
//       Python field order (byte i at [i*8 +: 8]):
//         TILE_ID @0 (7B) | EPOCH @7 (10B) | NONCE @17 (16B) |
//         MEASUREMENT @33 (32B) | TAG @65 (32B)
//
// What this proves: Stage-8 INTEGRATION - request latching, child
// sequencing, the key/measurement actually feeding the tag, field placement,
// length validation. It does NOT re-prove the crypto (Stage 5/6/7 KATs do
// that) and it is NOT the Python end-to-end golden (next step).
//
// Complements tb_stg_8.sv (sequencing/status tests); does not replace it.
//=============================================================================

module tb_stg_8_ref;

    logic clk = 1'b0;
    logic rst_n;
    always #5 clk = ~clk;

    //-------------------------------------------------------------------------
    // Request (shared by DUT and REF)
    //-------------------------------------------------------------------------
    logic         start;
    logic [55:0]  tile_id;
    logic [79:0]  epoch;
    logic [127:0] nonce;
    logic [255:0] root_secret;
    logic [111:0] context_in;
    logic [3:0]   context_len;
    logic [511:0] config_data;
    logic [6:0]   config_len;
    logic [511:0] imem;
    logic [6:0]   imem_len;

    //-------------------------------------------------------------------------
    // DUT
    //-------------------------------------------------------------------------
    logic [775:0] response;
    logic         busy, done, err;
    logic [2:0]   status;
    logic [3:0]   error_code;

    pq_attestation_controller dut (
        .clk, .rst_n, .start,
        .tile_id, .epoch, .nonce, .root_secret, .context_in, .context_len,
        .config_data, .config_len, .imem, .imem_len,
        .response, .busy, .done, .err, .status, .error_code
    );

    //-------------------------------------------------------------------------
    // REFERENCE CHAIN (independent instances, TB-sequenced)
    //-------------------------------------------------------------------------
    logic         r_kdf_start, r_meas_start, r_tag_start;
    logic [255:0] r_key;
    logic [5:0]   r_key_bytes;
    logic         r_kdf_busy, r_kdf_done;
    logic [255:0] r_meas;
    logic         r_meas_busy, r_meas_done;
    logic [255:0] r_tag;
    logic [5:0]   r_tag_bytes;
    logic         r_tag_busy, r_tag_done, r_tag_err;

    pq_kdf ref_kdf (
        .clk, .rst_n, .start(r_kdf_start),
        .root_secret, .tile_id, .epoch, .context_in, .context_len,
        .key_len_sel(2'b01),
        .derived_key(r_key), .derived_key_bytes(r_key_bytes),
        .busy(r_kdf_busy), .done(r_kdf_done)
    );

    pq_measurement ref_meas (
        .clk, .rst_n, .start(r_meas_start),
        .tile_id, .config_data, .config_len, .imem, .imem_len,
        .measurement(r_meas), .busy(r_meas_busy), .done(r_meas_done)
    );

    pq_attestation_tag ref_tag (
        .clk, .rst_n, .start(r_tag_start),
        .tile_key(r_key), .tile_id, .epoch, .nonce, .measurement(r_meas),
        .tag_len_sel(2'b01),
        .tag(r_tag), .tag_bytes(r_tag_bytes),
        .busy(r_tag_busy), .done(r_tag_done), .err(r_tag_err)
    );

    //-------------------------------------------------------------------------
    // Bookkeeping
    //-------------------------------------------------------------------------
    int checks = 0, errors = 0;
    task automatic check(input bit cond, input string what);
        checks++;
        if (cond) $display("[PASS] %s", what);
        else begin errors++; $display("[FAIL] %s @ %0t", what, $time); end
    endtask

    localparam int TMO = 20000;

    // Child activity during a rejected request (must stay zero).
    int child_busy_cycles;
    always @(posedge clk)
        if (rst_n && (dut.kdf_busy || dut.measurement_busy || dut.tag_busy))
            child_busy_cycles++;

    //-------------------------------------------------------------------------
    // Reference: run the chain on the CURRENT request inputs, return response
    //-------------------------------------------------------------------------
    task automatic ref_run(output logic [775:0] exp, output bit ok);
        int t;
        ok = 1'b1;
        exp = '0;
        @(negedge clk); r_kdf_start = 1'b1; @(negedge clk); r_kdf_start = 1'b0;
        t = 0; while (!r_kdf_done && t < TMO) begin @(posedge clk); #1; t++; end
        if (t >= TMO) ok = 1'b0;
        @(negedge clk); r_meas_start = 1'b1; @(negedge clk); r_meas_start = 1'b0;
        t = 0; while (!r_meas_done && t < TMO) begin @(posedge clk); #1; t++; end
        if (t >= TMO) ok = 1'b0;
        @(negedge clk); r_tag_start = 1'b1; @(negedge clk); r_tag_start = 1'b0;
        t = 0; while (!r_tag_done && t < TMO) begin @(posedge clk); #1; t++; end
        if (t >= TMO || r_tag_err) ok = 1'b0;
        exp[0*8  +: 56]  = tile_id;
        exp[7*8  +: 80]  = epoch;
        exp[17*8 +: 128] = nonce;
        exp[33*8 +: 256] = r_meas;
        exp[65*8 +: 256] = r_tag;
    endtask

    //-------------------------------------------------------------------------
    // DUT: pulse start, wait for done, capture response/status on done
    //-------------------------------------------------------------------------
    logic [775:0] got_resp;
    logic         got_err;
    logic [2:0]   got_status;
    logic [3:0]   got_code;

    task automatic dut_run(output bit finished);
        int t;
        @(negedge clk); start = 1'b1; @(negedge clk); start = 1'b0;
        t = 0; finished = 1'b0;
        while (t < 4 * TMO) begin
            @(posedge clk);
            if (done) begin
                got_resp = response; got_err = err; got_status = status; got_code = error_code;
                finished = 1'b1;
                break;
            end
            t++;
        end
        #1;
    endtask

    //-------------------------------------------------------------------------
    // Stimulus helpers
    //-------------------------------------------------------------------------
    function automatic logic [511:0] rand512();
        logic [511:0] v;
        for (int i = 0; i < 16; i++) v[i*32 +: 32] = $urandom();
        return v;
    endfunction

    task automatic randomize_req(input int clen, input int ilen, input int xlen);
        tile_id     = {$urandom(), $urandom()} & 56'hFF_FFFF_FFFF_FFFF;
        epoch       = {$urandom(), $urandom(), $urandom()} & {80{1'b1}};
        nonce       = {$urandom(), $urandom(), $urandom(), $urandom()};
        root_secret = {$urandom(), $urandom(), $urandom(), $urandom(), $urandom(), $urandom(), $urandom(), $urandom()};
        context_in  = {$urandom(), $urandom(), $urandom(), $urandom()} & {112{1'b1}};
        context_len = 4'(xlen);
        config_data = rand512();
        config_len  = 7'(clen);
        imem        = rand512();
        imem_len    = 7'(ilen);
    endtask

    // One full compare: DUT response must equal the reference chain bit-exactly.
    task automatic compare_one(input string name);
        logic [775:0] exp;
        bit rok, fin;
        ref_run(exp, rok);
        check(rok, {name, " : reference chain completed"});
        dut_run(fin);
        check(fin && !got_err && got_status == 3'b010 && got_code == 4'b0000,
              $sformatf("%s : DUT done, err=0, status=RESPONSE_READY (fin %0d err %0d st %0b code %0b)",
                        name, fin, got_err, got_status, got_code));
        check(got_resp[0*8  +: 56]  === exp[0*8  +: 56],  {name, " : TILE_ID     @ byte 0"});
        check(got_resp[7*8  +: 80]  === exp[7*8  +: 80],  {name, " : EPOCH       @ byte 7"});
        check(got_resp[17*8 +: 128] === exp[17*8 +: 128], {name, " : NONCE       @ byte 17"});
        check(got_resp[33*8 +: 256] === exp[33*8 +: 256], {name, " : MEASUREMENT @ byte 33 == reference"});
        check(got_resp[65*8 +: 256] === exp[65*8 +: 256], {name, " : TAG         @ byte 65 == reference"});
        check(got_resp === exp, {name, " : full 776-bit response bit-exact"});
    endtask

    task automatic reject_one(input string name, input int clen, input int ilen, input int xlen,
                              input logic [3:0] code);
        bit fin;
        randomize_req(clen, ilen, xlen);
        child_busy_cycles = 0;
        dut_run(fin);
        check(fin && got_err && got_status == 3'b011 && got_code == code,
              $sformatf("%s : rejected, status INVALID_REQUEST, code %0b (got fin %0d err %0d st %0b code %0b)",
                        name, code, fin, got_err, got_status, got_code));
        check(child_busy_cycles == 0, {name, " : no Stage 5/6/7 engine started"});
    endtask

    //-------------------------------------------------------------------------
    // Main
    //-------------------------------------------------------------------------
    initial begin
        // No $urandom(seed) call: XSim 2024.1 rejects a seeded $urandom(seed)
        // (XSIM 43-3122). Plain $urandom() / $urandom_range() only, as in TB1.sv.
        // XSim's default seed is fixed, so runs are repeatable; override with
        // xsim -sv_seed <n> to vary. Stimulus values differ from Verilator's,
        // which is fine: the expected response comes from the reference chain.
        start = 0; r_kdf_start = 0; r_meas_start = 0; r_tag_start = 0;
        randomize_req(0, 0, 0);
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        #1 rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("\n===== R1 directed boundaries =====");
        randomize_req(0, 0, 0);   compare_one("R1 empty config/imem, ctx 0");
        randomize_req(64, 64, 14); compare_one("R1 max 135-byte measurement, ctx 14");
        randomize_req(64, 0, 7);  compare_one("R1 config 64, imem 0");
        randomize_req(0, 64, 1);  compare_one("R1 config 0, imem 64");

        $display("\n===== R2 random =====");
        for (int i = 0; i < 12; i++) begin
            randomize_req($urandom_range(0, 64), $urandom_range(0, 64), $urandom_range(0, 14));
            compare_one($sformatf("R2 #%0d", i));
        end

        $display("\n===== R3 length rejection (per-field limits isolated) =====");
        reject_one("R3 config 65, imem 0",   65, 0, 0,  4'b0010);
        reject_one("R3 imem 65, config 0",   0, 65, 0,  4'b0010);
        reject_one("R3 config 127, imem 0",  127, 0, 0, 4'b0010);
        reject_one("R3 context 15",          0, 0, 15,  4'b0001);
        reject_one("R3 context 15 + config 65 (context reported first)", 65, 0, 15, 4'b0001);

        $display("\n===== R4 accepted after rejection (no stale state) =====");
        randomize_req(33, 17, 5); compare_one("R4 after rejects");

        $display("\n============================================================");
        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %s", (errors == 0) ? "PASS" : "FAIL");
        $display("============================================================");
        $finish;
    end

    initial begin
        #50ms;
        $display("RESULT : FAIL (global timeout)");
        $finish;
    end

endmodule
