`timescale 1ns/1ps
// Shared L2 KMAC engine (M-F1 rev 7 R7.6/R7.6a, A0; docs/decisions/STEP_C_DESIGN_P7_L2_SHARED.md sec.1-2).
// One kmac128 #(32, 14, 88) for both P7 wrappers (tiles 3 and 4) and the R7.6a arbiter l2_arbiter, unchanged.
//   r0 tile-4 TX (P)   r1 tile-3 RX slot P (P)   r2 tile-3 TX (Q)   r3 tile-4 RX slot P (Q)
// Keys (T3, R7.3): K[4->3] for r0/r1, K[3->4] for r2/r3; no wrapper holds a key.
// Job: after the grant the engine streams the owner's 22 R6.6 transcript words (one per cycle, index widx, read
// combinationally from the owner's registers/LUTRAM) into one message register, starts the kmac and pulses done with
// the tag. Words at or beyond msg_len are masked by kmac_encode, as in the trimmed wrapper (T2). The owner must keep
// its words and msg_len stable from req to done (they are its own registers/LUTRAM, written only while idle).
// A2 (OVH <= 4 idle cycles between jobs with a request pending) and A3 (job <= J_MAX = 128 cycles counting the grant
// cycle) are asserted here; A1 (no request while the own job is in flight) is asserted in l2_arbiter.
module l2_kmac_engine #(
    parameter int OVH = 4
)(
    input  logic             clk,
    input  logic             rst,
    input  logic [255:0]     key_43,          // K[4->3]
    input  logic [255:0]     key_34,          // K[3->4]
    input  logic [3:0]       req,
    input  logic [3:0][31:0] wd,              // word widx of each requester's transcript
    input  logic [3:0][6:0]  mlen,            // transcript bytes (24 + 4 * payload words)
    output logic             grant,           // pulse
    output logic [1:0]       grant_id,
    output logic             busy,
    output logic [1:0]       owner,
    output logic [4:0]       widx,            // NWORDS <= 32
    output logic             done,            // pulse; tag valid in this cycle
    output logic [127:0]     tag
);
    localparam int        J_MAX  = 128;
    localparam int        NWORDS = 22;                                    // 88 bytes
    localparam logic [111:0] DOMAIN = 112'h31762d485455412d324c2d434f4e;  // NOC-L2-AUTH-v1
    typedef enum logic [1:0] {E_IDLE, E_LOAD, E_START, E_RUN} es_t;
    es_t es;
    logic [NWORDS*32-1:0] emsg;
    logic [5:0]   wcnt;                                                   // stream index (widx = wcnt[4:0])
    logic [6:0]   mlen_q;
    logic         kstart, kdone;
    logic [255:0] ktag;

    logic [255:0] key_q;            // contract sec. 5 (Q4): the directed key is latched with the owner at the grant
    logic [3:0]   req_m;            // grants masked during reset (the accepted l2_arbiter is unchanged)
    assign req_m = rst ? 4'b0 : req;
    l2_arbiter #(.OVH(OVH)) arb (.clk, .rst, .req(req_m), .done(kdone), .grant, .grant_id, .busy);

    assign kstart = es == E_START;
    assign widx   = wcnt[4:0];
    always_ff @(posedge clk) begin
        if (rst) begin
            es <= E_IDLE; owner <= '0; wcnt <= '0; mlen_q <= '0; emsg <= '0; key_q <= '0;
        end else begin
            case (es)
                E_IDLE:  if (grant) begin owner <= grant_id; wcnt <= '0; mlen_q <= mlen[grant_id]; key_q <= grant_id[1] ? key_34 : key_43; es <= E_LOAD; end
                E_LOAD:  begin
                    for (int k = 0; k < NWORDS; k++) if (wcnt == 6'(k)) emsg[k*32 +: 32] <= wd[owner];
                    if (wcnt == 6'(NWORDS - 1)) es <= E_START; else wcnt <= wcnt + 6'd1;
                end
                E_START: es <= E_RUN;
                E_RUN:   if (kdone) es <= E_IDLE;
                default: es <= E_IDLE;
            endcase
        end
    end

    kmac128 #(.KEY_BYTES(32), .CUSTOM_BYTES(14), .MSG_BYTES(88)) kmac (
        .clk, .rst_n(!rst), .start(kstart), .key_in(key_q), .key_len(6'd32),
        .custom_in(DOMAIN), .custom_len(4'd14), .msg_in(emsg), .msg_len(mlen_q),
        .out_len_sel(1'b0), .tag_out(ktag), .busy(), .done(kdone));
    assign done = kdone;
    assign tag  = ktag[127:0];

    // synthesis translate_off
    int jlen, gap;
    always_ff @(posedge clk) begin
        if (rst) begin jlen <= 0; gap <= 0; end
        else begin
            if (grant) jlen <= 1; else if (busy) jlen <= jlen + 1;
            if (kdone && jlen + 1 > J_MAX)
                $error("l2_kmac_engine: A3 violated, job of %0d cycles exceeds J_MAX %0d", jlen + 1, J_MAX);
            if (kdone || grant) gap <= 0; else if (!busy && req != 0) gap <= gap + 1;
            if (grant && gap > 4)
                $error("l2_kmac_engine: A2 violated, %0d idle cycles with a request pending before the grant", gap);
        end
    end
    // synthesis translate_on
endmodule
