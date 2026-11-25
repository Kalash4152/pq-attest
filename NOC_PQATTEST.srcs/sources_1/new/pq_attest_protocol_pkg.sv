//=============================================================================
// PQ-Attest - Stage 8 - Attestation Protocol Boundary Package
//
// Purpose:
//   Canonical hardware/software attestation protocol definitions.
//
// Security model:
//   - Verifier-issued nonce / challenge-response.
//   - Tile consumes the nonce supplied by the verifier.
//   - Stage 8 does NOT generate a nonce.
//   - Stage 4 TRNG is therefore outside the Stage-8 request/response boundary.
//
// Canonical attestation tag:
//
//   TAG = KMAC128(
//             K = TILE_KEY,
//             X = TILE_ID || EPOCH || NONCE || MEASUREMENT,
//             S = "PQ-ATTEST-AUTH",
//             L = 256
//         )
//
// Canonical protocol layout follows the existing Python attestation protocol:
//
//   REQUEST:
//       TILE_ID || EPOCH || NONCE
//
//   RESPONSE:
//       TILE_ID || EPOCH || NONCE || MEASUREMENT || TAG
//
// Byte convention used throughout the crypto lane:
//   byte i occupies vector bits [i*8 +: 8].
//   Therefore byte 0 is at the LSB end of each packed field.
//
// IMPORTANT:
//   The NoC M-F1 transport currently reserves:
//       ATTEST_CHALLENGE = 160-bit payload
//       ATTEST_RESPONSE  = 512-bit payload
//
//   Those widths are TRANSPORT widths, not the canonical protocol widths.
//   This package deliberately does NOT invent a lossy mapping between them.
//   A Stage-8 transport adapter must resolve that separately.
//
// Target:
//   AMD/Xilinx Arty A7-100T
//   xc7a100tcsg324-1
//   Vivado 2024.1
//=============================================================================

`timescale 1ns/1ps

package pq_attest_protocol_pkg;

    //=========================================================================
    // 1. CANONICAL PROTOCOL FIELD WIDTHS
    //
    // These match the already-established crypto lane:
    //
    //   TILE_ID      : 7 bytes  / 56 bits
    //   EPOCH        : 10 bytes / 80 bits
    //   NONCE        : 16 bytes / 128 bits
    //   MEASUREMENT  : 32 bytes / 256 bits
    //   TAG          : 32 bytes / 256 bits
    //
    // These values agree with Stage 5, Stage 6, Stage 7 and the Python
    // attestation protocol.
    //=========================================================================

    localparam int unsigned STG8_TILE_ID_BYTES = 7;
    localparam int unsigned STG8_TILE_ID_BITS  = 56;

    localparam int unsigned STG8_EPOCH_BYTES = 10;
    localparam int unsigned STG8_EPOCH_BITS  = 80;

    localparam int unsigned STG8_NONCE_BYTES = 16;
    localparam int unsigned STG8_NONCE_BITS  = 128;

    localparam int unsigned STG8_MEASUREMENT_BYTES = 32;
    localparam int unsigned STG8_MEASUREMENT_BITS  = 256;

    localparam int unsigned STG8_TAG_BYTES = 32;
    localparam int unsigned STG8_TAG_BITS  = 256;


    //=========================================================================
    // 2. CANONICAL REQUEST LAYOUT
    //
    // Python protocol:
    //
    //     request = {
    //         tile_id,
    //         epoch,
    //         nonce
    //     }
    //
    // Byte offsets:
    //
    //     0 ..  6 : TILE_ID
    //     7 .. 16 : EPOCH
    //    17 .. 32 : NONCE
    //
    // Total = 33 bytes = 264 bits
    //
    // Packed struct ordering is intentionally reversed so that byte 0 of the
    // logical protocol object is at the LSB end of the packed vector.
    //=========================================================================

    localparam int unsigned STG8_REQUEST_TILE_ID_OFFSET = 0;

    localparam int unsigned STG8_REQUEST_EPOCH_OFFSET =
        STG8_REQUEST_TILE_ID_OFFSET + STG8_TILE_ID_BYTES;

    localparam int unsigned STG8_REQUEST_NONCE_OFFSET =
        STG8_REQUEST_EPOCH_OFFSET + STG8_EPOCH_BYTES;

    localparam int unsigned STG8_REQUEST_BYTES =
        STG8_TILE_ID_BYTES +
        STG8_EPOCH_BYTES +
        STG8_NONCE_BYTES;

    localparam int unsigned STG8_REQUEST_BITS =
        STG8_REQUEST_BYTES * 8;


    //=========================================================================
    // 3. CANONICAL RESPONSE LAYOUT
    //
    // Python protocol:
    //
    //     response = {
    //         tile_id,
    //         epoch,
    //         nonce,
    //         measurement,
    //         tag
    //     }
    //
    // Byte offsets:
    //
    //     0 ..  6 : TILE_ID
    //     7 .. 16 : EPOCH
    //    17 .. 32 : NONCE
    //    33 .. 64 : MEASUREMENT
    //    65 .. 96 : TAG
    //
    // Total = 97 bytes = 776 bits
    //
    // The response deliberately echoes TILE_ID/EPOCH/NONCE. The verifier
    // checks these fields against the original request before cryptographic
    // acceptance.
    //=========================================================================

    localparam int unsigned STG8_RESPONSE_TILE_ID_OFFSET = 0;

    localparam int unsigned STG8_RESPONSE_EPOCH_OFFSET =
        STG8_RESPONSE_TILE_ID_OFFSET + STG8_TILE_ID_BYTES;

    localparam int unsigned STG8_RESPONSE_NONCE_OFFSET =
        STG8_RESPONSE_EPOCH_OFFSET + STG8_EPOCH_BYTES;

    localparam int unsigned STG8_RESPONSE_MEASUREMENT_OFFSET =
        STG8_RESPONSE_NONCE_OFFSET + STG8_NONCE_BYTES;

    localparam int unsigned STG8_RESPONSE_TAG_OFFSET =
        STG8_RESPONSE_MEASUREMENT_OFFSET + STG8_MEASUREMENT_BYTES;

    localparam int unsigned STG8_RESPONSE_BYTES =
        STG8_TILE_ID_BYTES +
        STG8_EPOCH_BYTES +
        STG8_NONCE_BYTES +
        STG8_MEASUREMENT_BYTES +
        STG8_TAG_BYTES;

    localparam int unsigned STG8_RESPONSE_BITS =
        STG8_RESPONSE_BYTES * 8;


    //=========================================================================
    // 4. STAGE-7 TRANSCRIPT LAYOUT
    //
    // TAG input is exactly:
    //
    //     TILE_ID || EPOCH || NONCE || MEASUREMENT
    //
    // No separators.
    // No length prefixes.
    // No encode_string().
    //
    // Total:
    //
    //     7 + 10 + 16 + 32 = 65 bytes = 520 bits
    //
    // These offsets intentionally match pq_attest_pkg / Stage 7.
    //=========================================================================

    localparam int unsigned STG8_TRANSCRIPT_TILE_ID_OFFSET = 0;

    localparam int unsigned STG8_TRANSCRIPT_EPOCH_OFFSET =
        STG8_TRANSCRIPT_TILE_ID_OFFSET + STG8_TILE_ID_BYTES;

    localparam int unsigned STG8_TRANSCRIPT_NONCE_OFFSET =
        STG8_TRANSCRIPT_EPOCH_OFFSET + STG8_EPOCH_BYTES;

    localparam int unsigned STG8_TRANSCRIPT_MEASUREMENT_OFFSET =
        STG8_TRANSCRIPT_NONCE_OFFSET + STG8_NONCE_BYTES;

    localparam int unsigned STG8_TRANSCRIPT_BYTES =
        STG8_TILE_ID_BYTES +
        STG8_EPOCH_BYTES +
        STG8_NONCE_BYTES +
        STG8_MEASUREMENT_BYTES;

    localparam int unsigned STG8_TRANSCRIPT_BITS =
        STG8_TRANSCRIPT_BYTES * 8;


    //=========================================================================
    // 5. AUTHENTICATION CUSTOMIZATION
    //
    // Stage 7 / Python reference:
    //
    //     "PQ-ATTEST-AUTH"
    //
    // 14 bytes = 112 bits.
    //=========================================================================

    localparam int unsigned STG8_AUTH_CUSTOM_BYTES = 14;
    localparam int unsigned STG8_AUTH_CUSTOM_BITS  = 112;

    localparam logic [STG8_AUTH_CUSTOM_BITS-1:0] STG8_AUTH_CUSTOM =
        112'h485455412d5453455454412d5150;


    //=========================================================================
    // 6. TAG OUTPUT LENGTH
    //
    // Stage 8 canonical protocol uses the 256-bit attestation tag.
    //
    // Stage 7 independently supports L=128 and L=256, but the canonical
    // attestation protocol uses the 32-byte / 256-bit form.
    //=========================================================================

    localparam int unsigned STG8_TAG_OUTPUT_BYTES = 32;
    localparam int unsigned STG8_TAG_OUTPUT_BITS  = 256;


    //=========================================================================
    // 7. NONCE SEMANTICS
    //
    // Canonical Stage-8 model:
    //
    //     VERIFIER -> TILE : nonce
    //
    // The tile does not generate the protocol challenge.
    //
    // This matches the existing Python attestation_protocol.py request model
    // and preserves challenge-response freshness semantics.
    //=========================================================================

    localparam bit STG8_NONCE_VERIFIER_ISSUED = 1'b1;
    localparam bit STG8_NONCE_TILE_GENERATED  = 1'b0;


    //=========================================================================
    // 8. VERIFIER FIELD-CHECK ORDER
    //
    // Before cryptographic verification, the verifier checks:
    //
    //     1. TILE_ID
    //     2. EPOCH
    //     3. NONCE
    //     4. MEASUREMENT type/length
    //     5. TAG type/length
    //     6. KMAC verification
    //
    // These are protocol semantics, not a second cryptographic primitive.
    //=========================================================================

    typedef enum logic [2:0] {
        STG8_CHECK_TILE_ID   = 3'd0,
        STG8_CHECK_EPOCH     = 3'd1,
        STG8_CHECK_NONCE     = 3'd2,
        STG8_CHECK_MEAS      = 3'd3,
        STG8_CHECK_TAG       = 3'd4,
        STG8_CHECK_KMAC      = 3'd5
    } stg8_check_e;


    //=========================================================================
    // 9. ATTESTATION STATUS CODES
    //
    // Four bits are available in noc_pkg::head_flit_t.control.attest.status.
    //
    // 0     = unspecified / idle
    // 1     = accept
    // 2     = reject
    // 3     = busy
    // 4     = stale challenge
    // 5     = malformed protocol data
    // 6     = authentication/tag failure
    // 7     = measurement failure
    // 8     = tile identity failure
    // 9     = epoch failure
    // 10    = internal error
    // 11-15 = reserved
    //
    // NOTE:
    // These are Stage-8 protocol decisions. They were NOT previously frozen
    // by M-F1; this package now makes the table explicit so later RTL does
    // not invent independent values.
    //=========================================================================

    typedef enum logic [3:0] {
        STG8_STATUS_UNSPECIFIED       = 4'd0,
        STG8_STATUS_ACCEPT            = 4'd1,
        STG8_STATUS_REJECT            = 4'd2,
        STG8_STATUS_BUSY              = 4'd3,
        STG8_STATUS_STALE             = 4'd4,
        STG8_STATUS_BAD_FORMAT        = 4'd5,
        STG8_STATUS_BAD_TAG           = 4'd6,
        STG8_STATUS_BAD_MEASUREMENT   = 4'd7,
        STG8_STATUS_BAD_TILE_ID       = 4'd8,
        STG8_STATUS_BAD_EPOCH         = 4'd9,
        STG8_STATUS_INTERNAL_ERROR    = 4'd10
    } stg8_status_e;


    //=========================================================================
    // 10. INTERNAL ERROR REASONS
    //
    // This is deliberately separate from the 4-bit transport status.
    // It gives the Stage-8 controller / verifier a stable internal reason
    // code without pretending that every reason must fit in the NoC header.
    //=========================================================================

    typedef enum logic [3:0] {
        STG8_ERROR_NONE          = 4'd0,
        STG8_ERROR_MALFORMED    = 4'd1,
        STG8_ERROR_TILE_ID      = 4'd2,
        STG8_ERROR_EPOCH        = 4'd3,
        STG8_ERROR_NONCE        = 4'd4,
        STG8_ERROR_MEASUREMENT  = 4'd5,
        STG8_ERROR_TAG           = 4'd6,
        STG8_ERROR_KEY           = 4'd7,
        STG8_ERROR_BUSY          = 4'd8,
        STG8_ERROR_STALE         = 4'd9,
        STG8_ERROR_INTERNAL      = 4'd10
    } stg8_error_e;


    //=========================================================================
    // 11. CANONICAL REQUEST TYPE
    //
    // Packed ordering:
    //
    //     [263:208] TILE_ID?  No.
    //
    // Because SystemVerilog packed structs place the first field at the MSB,
    // fields are intentionally declared in reverse protocol order:
    //
    //     nonce | epoch | tile_id
    //
    // Therefore:
    //
    //     byte 0 = tile_id byte 0
    //     byte 7 = epoch byte 0
    //     byte 17 = nonce byte 0
    //
    // This matches the project's LSB-first byte convention.
    //=========================================================================

    typedef struct packed {
        logic [STG8_NONCE_BITS-1:0]  nonce;
        logic [STG8_EPOCH_BITS-1:0]  epoch;
        logic [STG8_TILE_ID_BITS-1:0] tile_id;
    } stg8_attestation_request_t;


    //=========================================================================
    // 12. CANONICAL RESPONSE TYPE
    //
    // Reverse declaration order gives the required logical byte layout:
    //
    //     TILE_ID || EPOCH || NONCE || MEASUREMENT || TAG
    //
    // in increasing byte offsets from the LSB side.
    //=========================================================================

    typedef struct packed {
        logic [STG8_TAG_BITS-1:0]          tag;
        logic [STG8_MEASUREMENT_BITS-1:0]  measurement;
        logic [STG8_NONCE_BITS-1:0]        nonce;
        logic [STG8_EPOCH_BITS-1:0]        epoch;
        logic [STG8_TILE_ID_BITS-1:0]      tile_id;
    } stg8_attestation_response_t;


    //=========================================================================
    // 13. NO-C TRANSPORT WIDTHS
    //
    // These are copied from the already-frozen M-F1 transport contract.
    //
    // They are NOT the canonical protocol object widths above.
    //
    // ATTEST_CHALLENGE : 5 flits = 160 bits
    // ATTEST_RESPONSE  : 16 flits = 512 bits
    //
    // A future Stage-8 transport adapter MUST define how the canonical
    // 264-bit request and 776-bit response are transported without silently
    // truncating security-critical fields.
    //=========================================================================

    localparam int unsigned STG8_NOC_FLIT_BITS = 32;

    localparam int unsigned STG8_NOC_CHALLENGE_FLITS = 5;
    localparam int unsigned STG8_NOC_CHALLENGE_BITS =
        STG8_NOC_CHALLENGE_FLITS * STG8_NOC_FLIT_BITS;

    localparam int unsigned STG8_NOC_RESPONSE_FLITS = 16;
    localparam int unsigned STG8_NOC_RESPONSE_BITS =
        STG8_NOC_RESPONSE_FLITS * STG8_NOC_FLIT_BITS;


    //=========================================================================
    // 14. TRANSPORT RECONCILIATION GUARD
    //
    // These constants make the size mismatch explicit.
    //
    // Do NOT "solve" this by truncating:
    //
    //     EPOCH
    //     NONCE
    //     TILE_ID
    //     MEASUREMENT
    //     TAG
    //
    // Any transport adapter must preserve the complete canonical protocol
    // fields or use an explicitly defined multi-message/fragmentation scheme.
    //=========================================================================

    localparam int unsigned STG8_REQUEST_TRANSPORT_GAP_BITS =
        STG8_REQUEST_BITS - STG8_NOC_CHALLENGE_BITS;

    localparam int unsigned STG8_RESPONSE_TRANSPORT_GAP_BITS =
        STG8_RESPONSE_BITS - STG8_NOC_RESPONSE_BITS;


    //=========================================================================
    // 15. PROTOCOL VERSION
    //=========================================================================

    localparam logic [7:0] STG8_PROTOCOL_VERSION = 8'h01;


    //=========================================================================
    // 16. STRUCTURE WIDTH CHECKPOINTS
    //
    // These are intentionally localparams rather than SVA. They allow later
    // Stage-8 RTL/TB code to compare $bits(type) against the canonical widths.
    //=========================================================================

    localparam int unsigned STG8_REQUEST_STRUCT_BITS =
        $bits(stg8_attestation_request_t);

    localparam int unsigned STG8_RESPONSE_STRUCT_BITS =
        $bits(stg8_attestation_response_t);

endpackage