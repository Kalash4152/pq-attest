`timescale 1ns/1ps
// D (M-F1 rev 7 R7.8.2, DECISION_REGISTER D-AREA-1): ONE kmac128 shared by pq_kdf_xk (requester a) and
// pq_attestation_tag_xk (requester b) inside the endpoint controller and inside the RoT verifier.
//
// - Both callers run the KDF strictly before the tag, so the two requesters never compete. That is asserted below.
// - kmac128 samples key/custom/msg/len/out_len_sel only in the start cycle (kmac_128.sv:388-400), so the request mux is
//   combinational on the start pulses and needs no owner register.
// - Parameters: KEY 32, CUSTOM 16, MSG 65 bytes. The KDF request (40 bytes) is zero-extended. kmac_encode.sv:408 absorbs
//   only bytes < msg_len, so the digest is the one the KDF's own MSG 40 instance produced.
// - tag_out / busy / done are broadcast. Each caller consumes done only in its own wait state (pq_kdf.sv:183,222;
//   pqattest_stg7.sv:242).
module pq_kmac_share
    import kmac_pkg::*;
(
    input  logic         clk,
    input  logic         rst_n,
    // requester a: KDF (no customization)
    input  logic         a_start,
    input  logic [255:0] a_key,
    input  logic [5:0]   a_key_len,
    input  logic [319:0] a_msg,
    input  logic [5:0]   a_msg_len,
    input  logic         a_out_len_sel,
    // requester b: attestation tag
    input  logic         b_start,
    input  logic [255:0] b_key,
    input  logic [5:0]   b_key_len,
    input  logic [127:0] b_custom,
    input  logic [4:0]   b_custom_len,
    input  logic [519:0] b_msg,
    input  logic [6:0]   b_msg_len,
    input  logic         b_out_len_sel,
    // shared result
    output logic [255:0] tag_out,
    output logic         busy,
    output logic         done
);
    logic         k_start, k_len_sel;
    logic [255:0] k_key;
    logic [5:0]   k_key_len;
    logic [127:0] k_custom;
    logic [4:0]   k_custom_len;
    logic [519:0] k_msg;
    logic [6:0]   k_msg_len;
    always_comb begin
        k_start      = a_start | b_start;
        k_key        = a_start ? a_key         : b_key;
        k_key_len    = a_start ? a_key_len     : b_key_len;
        k_custom     = a_start ? 128'd0        : b_custom;
        k_custom_len = a_start ? 5'd0          : b_custom_len;
        k_msg        = a_start ? {200'd0, a_msg} : b_msg;
        k_msg_len    = a_start ? 7'(a_msg_len) : b_msg_len;
        k_len_sel    = a_start ? a_out_len_sel : b_out_len_sel;
    end

    kmac128 #(
        .KEY_BYTES    (32),
        .CUSTOM_BYTES (16),
        .MSG_BYTES    (65)
    ) u_kmac (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (k_start),
        .key_in      (k_key),
        .key_len     (k_key_len),
        .custom_in   (k_custom),
        .custom_len  (k_custom_len),
        .msg_in      (k_msg),
        .msg_len     (k_msg_len),
        .out_len_sel (k_len_sel),
        .tag_out     (tag_out),
        .busy        (busy),
        .done        (done)
    );

    // Procedural checks (same style as pqattest_stg7.sv:331-337): the requesters never overlap and never start into
    // a busy engine.
    // synthesis translate_off
    always_ff @(posedge clk) begin
        if (rst_n && a_start && b_start) $error("pq_kmac_share: KDF and tag started in the same cycle");
        if (rst_n && k_start && busy)    $error("pq_kmac_share: start while the shared kmac128 is busy");
    end
    // synthesis translate_on
endmodule
