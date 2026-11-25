
// PQ-Attest - Stage 8 - Attestation Protocol Controller
//
// Purpose:
//   Orchestrates the already-existing Stage 5, Stage 6 and Stage 7 engines:
//
//       Stage 5 : pq_kdf
//       Stage 6 : pq_measurement
//       Stage 7 : pq_attestation_tag
//
// Protocol:
//
//   Request:
//       TILE_ID || EPOCH || NONCE
//
//   Response:
//       TILE_ID || EPOCH || NONCE || MEASUREMENT || TAG
//
//   Response width:
//       7 + 10 + 16 + 32 + 32 = 97 bytes = 776 bits
//
// IMPORTANT:
//   This module does NOT:
//     - implement KMAC
//     - implement SHA3
//     - implement Keccak
//     - generate the nonce
//     - verify an incoming response
//     - implement replay storage
//     - packetize the response into NoC flits
//
//   The nonce is supplied externally.
//   The verifier/challenge side supplies the nonce.
//
// Existing modules used verbatim:
//   pq_kdf
//   pq_measurement
//   pq_attestation_tag
//
// Target : xc7a100tcsg324-1
// Tool   : Vivado 2024.1
//=============================================================================

`timescale 1ns/1ps


module pq_attestation_controller (

    //-------------------------------------------------------------------------
    // CLOCK / RESET
    //-------------------------------------------------------------------------
    input  logic         clk,
    input  logic         rst_n,          // ACTIVE LOW, SYNCHRONOUS

    //-------------------------------------------------------------------------
    // REQUEST CONTROL
    //-------------------------------------------------------------------------
    input  logic         start,

    //-------------------------------------------------------------------------
    // ATTESTATION REQUEST FIELDS
    //
    // Exact widths from existing Stage 5 / Stage 7 interfaces.
    //-------------------------------------------------------------------------
    input  logic [55:0]  tile_id,
    input  logic [79:0]  epoch,
    input  logic [127:0] nonce,

    //-------------------------------------------------------------------------
    // ROOT OF TRUST INPUTS
    //
    // Exact widths from pq_kdf.
    //-------------------------------------------------------------------------
    input  logic [255:0] root_secret,

    // KDF context:
    // maximum 14 bytes = 112 bits
    // context_len is 0..14 and is therefore 4 bits.
    input  logic [111:0] context_in,
    input  logic [3:0]   context_len,

    //-------------------------------------------------------------------------
    // MEASUREMENT INPUTS
    //
    // Exact widths from pq_measurement.
    //
    // config_len / imem_len are byte counts.
    //-------------------------------------------------------------------------
    input  logic [511:0] config_data,
    input  logic [6:0]   config_len,

    input  logic [511:0] imem,
    input  logic [6:0]   imem_len,

    //-------------------------------------------------------------------------
    // PROTOCOL RESPONSE
    //
    // Byte layout:
    //
    //   [  0 ..   6] TILE_ID       7 bytes
    //   [  7 ..  16] EPOCH        10 bytes
    //   [ 17 ..  32] NONCE        16 bytes
    //   [ 33 ..  64] MEASUREMENT  32 bytes
    //   [ 65 ..  96] TAG          32 bytes
    //
    // Total = 97 bytes = 776 bits
    //
    // Project byte convention:
    //   byte i occupies [i*8 +: 8]
    //-------------------------------------------------------------------------
    output logic [775:0] response,

    //-------------------------------------------------------------------------
    // CONTROLLER STATUS
    //-------------------------------------------------------------------------
    output logic         busy,
    output logic         done,
    output logic         err,

    // Status:
    //
    //   000 = IDLE
    //   001 = PROCESSING
    //   010 = RESPONSE_READY
    //   011 = INVALID_REQUEST
    //   100 = CRYPTO_ERROR
    //
    output logic [2:0]   status,

    // Error code:
    //
    //   0000 = NONE
    //   0001 = INVALID_CONTEXT_LENGTH
    //   0010 = INVALID_MEASUREMENT_LENGTH
    //   0011 = KDF_ERROR
    //   0100 = TAG_ERROR
    //   0101 = INTERNAL_ERROR
    //
    output logic [3:0]   error_code
);


    //=========================================================================
    // FIXED PROTOCOL CONSTANTS
    //=========================================================================

    localparam int RESPONSE_BITS = 776;

    localparam int TILE_ID_BITS  = 56;
    localparam int EPOCH_BITS    = 80;
    localparam int NONCE_BITS    = 128;
    localparam int MEAS_BITS     = 256;
    localparam int TAG_BITS      = 256;

    localparam int TILE_ID_BYTES = 7;
    localparam int EPOCH_BYTES   = 10;
    localparam int NONCE_BYTES   = 16;
    localparam int MEAS_BYTES    = 32;
    localparam int TAG_BYTES     = 32;

    // Measurement engine has:
    //
    //   CONFIG_MAX = 64 bytes
    //   IMEM_MAX   = 64 bytes
    //
    // Total measurement input:
    //
    //   TILE_ID 7 + CONFIG 64 + IMEM 64 = 135 bytes
    //
    // The existing Stage-6 SHA3 path is deliberately limited to this range.

    localparam int MAX_CONFIG_BYTES = 64;
    localparam int MAX_IMEM_BYTES   = 64;
    localparam int MAX_MEAS_MSG     = 135;

    // Stage 5 context maximum.
    localparam int MAX_CONTEXT_BYTES = 14;


    //=========================================================================
    // STATE MACHINE
    //=========================================================================

    typedef enum logic [3:0] {
        S_IDLE         = 4'd0,
        S_KDF_START    = 4'd1,
        S_KDF_WAIT     = 4'd2,
        S_MEAS_START   = 4'd3,
        S_MEAS_WAIT    = 4'd4,
        S_TAG_START    = 4'd5,
        S_TAG_WAIT     = 4'd6,
        S_BUILD        = 4'd7,
        S_DONE         = 4'd8,
        S_ERROR        = 4'd9
    } state_t;

    state_t state_q;


    //=========================================================================
    // LATCHED REQUEST
    //
    // All request information is captured when start is accepted.
    // This prevents upstream changes during the cryptographic operation from
    // corrupting the request.
    //=========================================================================

    logic [55:0]  tile_id_q;
    logic [79:0]  epoch_q;
    logic [127:0] nonce_q;

    logic [255:0] root_secret_q;

    logic [111:0] context_q;
    logic [3:0]   context_len_q;

    logic [511:0] config_q;
    logic [6:0]   config_len_q;

    logic [511:0] imem_q;
    logic [6:0]   imem_len_q;


    //=========================================================================
    // STAGE 5 : PQ KDF
    //=========================================================================

    logic         kdf_start;
    logic [255:0] kdf_derived_key;
    logic [5:0]   kdf_derived_key_bytes;
    logic         kdf_busy;
    logic         kdf_done;


    pq_kdf u_pq_kdf (
        .clk              (clk),
        .rst_n            (rst_n),

        .start            (kdf_start),

        .root_secret      (root_secret_q),
        .tile_id          (tile_id_q),
        .epoch            (epoch_q),
        .context_in       (context_q),
        .context_len      (context_len_q),

        // Stage 8 always requests the 256-bit tile key.
        // Existing pq_kdf encoding:
        //   KDF_LEN_128 = 2'b00
        //   KDF_LEN_256 = 2'b01
        .key_len_sel      (2'b01),

        .derived_key      (kdf_derived_key),
        .derived_key_bytes(kdf_derived_key_bytes),
        .busy             (kdf_busy),
        .done             (kdf_done)
    );


    //=========================================================================
    // STAGE 6 : MEASUREMENT ENGINE
    //=========================================================================

    logic         measurement_start;
    logic [255:0] measurement;
    logic         measurement_busy;
    logic         measurement_done;


    pq_measurement u_pq_measurement (
        .clk          (clk),
        .rst_n        (rst_n),

        .start        (measurement_start),

        .tile_id      (tile_id_q),

        .config_data  (config_q),
        .config_len   (config_len_q),

        .imem         (imem_q),
        .imem_len     (imem_len_q),

        .measurement  (measurement),
        .busy         (measurement_busy),
        .done         (measurement_done)
    );


    //=========================================================================
    // STAGE 7 : ATTESTATION TAG
    //=========================================================================

    logic         tag_start;

    logic [255:0] tag;
    logic [5:0]   tag_bytes;
    logic         tag_busy;
    logic         tag_done;
    logic         tag_err;


    pq_attestation_tag u_pq_attestation_tag (
        .clk          (clk),
        .rst_n        (rst_n),

        .start        (tag_start),

        .tile_key     (kdf_derived_key),

        .tile_id      (tile_id_q),
        .epoch        (epoch_q),
        .nonce        (nonce_q),
        .measurement  (measurement),

        // Stage 8 protocol requires a 256-bit / 32-byte tag.
        //
        // Existing Stage 7:
        //   TAG_LEN_128 = 2'b00
        //   TAG_LEN_256 = 2'b01
        .tag_len_sel  (2'b01),

        .tag           (tag),
        .tag_bytes    (tag_bytes),
        .busy         (tag_busy),
        .done         (tag_done),
        .err          (tag_err)
    );


    //=========================================================================
    // REQUEST VALIDATION
    //
    // IMPORTANT:
    //
    // pq_measurement does not generate an error for an invalid length.
    // It simply refuses to accept start.
    //
    // Therefore Stage 8 MUST reject bad lengths before launching it.
    //=========================================================================

    logic context_len_valid;
    logic measurement_len_valid;

    logic [7:0] config_len_int;
    logic [7:0] imem_len_int;

    logic [8:0] total_measurement_bytes;


    always_comb begin

        config_len_int = {1'b0, config_len};

        imem_len_int   = {1'b0, imem_len};

        total_measurement_bytes =
              9'd7
            + {2'b00, config_len}
            + {2'b00, imem_len};

        context_len_valid =
            (context_len <= 4'd14);

        measurement_len_valid =
            (config_len <= 7'd64) &&
            (imem_len   <= 7'd64) &&
            (total_measurement_bytes <= 9'd135);

    end


    //=========================================================================
    // CHILD START PULSES
    //
    // Each child receives exactly one start cycle.
    //=========================================================================

    always_comb begin

        kdf_start         = 1'b0;
        measurement_start = 1'b0;
        tag_start         = 1'b0;

        case (state_q)

            S_KDF_START:
                kdf_start = 1'b1;

            S_MEAS_START:
                measurement_start = 1'b1;

            S_TAG_START:
                tag_start = 1'b1;

            default: begin
                kdf_start         = 1'b0;
                measurement_start = 1'b0;
                tag_start         = 1'b0;
            end

        endcase

    end


    //=========================================================================
    // CONTROLLER STATUS
    //=========================================================================

    always_comb begin

        busy = 1'b0;

        case (state_q)

            S_KDF_START,
            S_KDF_WAIT,
            S_MEAS_START,
            S_MEAS_WAIT,
            S_TAG_START,
            S_TAG_WAIT,
            S_BUILD:
                busy = 1'b1;

            default:
                busy = 1'b0;

        endcase

    end


    //=========================================================================
    // SEQUENTIAL CONTROLLER
    //
    // Reset is synchronous active-low.
    //
    // This is intentional:
    //   - pq_measurement is synchronous active-low
    //   - pq_attestation_tag is synchronous active-low
    //   - pq_kdf additionally supports asynchronous assertion
    //
    // Holding rst_n low across a clock edge therefore resets all three.
    //=========================================================================

    always_ff @(posedge clk) begin

        if (!rst_n) begin

            state_q <= S_IDLE;

            tile_id_q    <= '0;
            epoch_q      <= '0;
            nonce_q      <= '0;

            root_secret_q <= '0;

            context_q     <= '0;
            context_len_q <= '0;

            config_q      <= '0;
            config_len_q  <= '0;

            imem_q        <= '0;
            imem_len_q    <= '0;

            response  <= '0;

            done       <= 1'b0;
            err        <= 1'b0;

            status     <= 3'b000;
            error_code <= 4'b0000;

        end
        else begin

            // Default: one-cycle pulses.
            done <= 1'b0;
            err  <= 1'b0;

            case (state_q)

                //=============================================================
                // IDLE
                //=============================================================

                S_IDLE: begin

                    status     <= 3'b000;
                    error_code <= 4'b0000;

                    if (start) begin

                        //-----------------------------------------------------------------
                        // Validate before accepting the request.
                        //-----------------------------------------------------------------

                        if (!context_len_valid) begin

                            state_q    <= S_ERROR;
                            status     <= 3'b011;
                            error_code <= 4'b0001;

                        end
                        else if (!measurement_len_valid) begin

                            state_q    <= S_ERROR;
                            status     <= 3'b011;
                            error_code <= 4'b0010;

                        end
                        else begin

                            //-----------------------------------------------------------------
                            // Latch complete request.
                            //-----------------------------------------------------------------

                            tile_id_q <= tile_id;
                            epoch_q   <= epoch;
                            nonce_q   <= nonce;

                            root_secret_q <= root_secret;

                            context_q     <= context_in;
                            context_len_q <= context_len;

                            config_q     <= config_data;
                            config_len_q <= config_len;

                            imem_q     <= imem;
                            imem_len_q <= imem_len;

                            //-----------------------------------------------------------------
                            // Begin Stage 5.
                            //-----------------------------------------------------------------

                            state_q <= S_KDF_START;
                            status  <= 3'b001;

                        end

                    end

                end


                //=============================================================
                // STAGE 5 START
                //=============================================================

                S_KDF_START: begin

                    status <= 3'b001;

                    // kdf_start is generated combinationally.
                    //
                    // Move immediately to wait state after presenting the
                    // one-cycle start pulse.

                    state_q <= S_KDF_WAIT;

                end


                //=============================================================
                // STAGE 5 WAIT
                //=============================================================

                S_KDF_WAIT: begin

                    status <= 3'b001;

                    if (kdf_done) begin

                        // pq_kdf has no error output.
                        //
                        // At this point the selected 256-bit key is valid.

                        state_q <= S_MEAS_START;

                    end

                end


                //=============================================================
                // STAGE 6 START
                //=============================================================

                S_MEAS_START: begin

                    status <= 3'b001;

                    // measurement_start is high for this state only.

                    state_q <= S_MEAS_WAIT;

                end


                //=============================================================
                // STAGE 6 WAIT
                //=============================================================

                S_MEAS_WAIT: begin

                    status <= 3'b001;

                    if (measurement_done) begin

                        state_q <= S_TAG_START;

                    end

                end


                //=============================================================
                // STAGE 7 START
                //=============================================================

                S_TAG_START: begin

                    status <= 3'b001;

                    // tag_start is high for this state only.

                    state_q <= S_TAG_WAIT;

                end


                //=============================================================
                // STAGE 7 WAIT
                //=============================================================

                S_TAG_WAIT: begin

                    status <= 3'b001;

                    if (tag_done) begin

                        if (tag_err) begin

                            //-----------------------------------------------------------------
                            // Stage 7 rejected the request.
                            //-----------------------------------------------------------------

                            state_q    <= S_ERROR;
                            status     <= 3'b100;
                            error_code <= 4'b0100;

                        end
                        else begin

                            //-----------------------------------------------------------------
                            // Tag successfully generated.
                            //-----------------------------------------------------------------

                            state_q <= S_BUILD;

                        end

                    end

                end


                //=============================================================
                // BUILD RESPONSE
                //
                // Byte layout:
                //
                //   response byte 0  .. 6   = tile_id
                //   response byte 7  .. 16  = epoch
                //   response byte 17 .. 32  = nonce
                //   response byte 33 .. 64  = measurement
                //   response byte 65 .. 96  = tag
                //
                // Project convention:
                //   byte i -> [i*8 +: 8]
                //=============================================================

                S_BUILD: begin

                    response <= '0;

                    response[0*8 +: 56]  <= tile_id_q;

                    response[7*8 +: 80]  <= epoch_q;

                    response[17*8 +: 128] <= nonce_q;

                    response[33*8 +: 256] <= measurement;

                    response[65*8 +: 256] <= tag;

                    state_q <= S_DONE;

                    status <= 3'b010;

                end


                //=============================================================
                // RESPONSE READY / DONE
                //=============================================================

                S_DONE: begin

                    done       <= 1'b1;
                    err        <= 1'b0;

                    status     <= 3'b010;
                    error_code <= 4'b0000;

                    state_q <= S_IDLE;

                end


                //=============================================================
                // ERROR
                //=============================================================

                S_ERROR: begin

                    done <= 1'b1;
                    err  <= 1'b1;

                    state_q <= S_IDLE;

                end


                //=============================================================
                // DEFAULT
                //=============================================================

                default: begin

                    state_q    <= S_IDLE;

                    response   <= '0;

                    done       <= 1'b0;
                    err        <= 1'b1;

                    status     <= 3'b100;
                    error_code <= 4'b0101;

                end

            endcase

        end

    end


endmodule