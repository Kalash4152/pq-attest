`timescale 1ns/1ps
// Trusted issuer/verifier. Expected measurement is a provisioned offline whitelist.
module pq_rot_verifier #(
  parameter int TIMEOUT_CYCLES=100000,
  parameter int MAX_BUSY_RETRIES=3,          // C-1/C-2 (I-6): BUSY re-issues the same challenge at most this often
  parameter bit BYPASS_MEASUREMENT=0,BYPASS_TAG=0
)(input logic clk,rst,start,revoke,
  input logic [255:0] root_secret,approved_measurement,
  input logic [79:0] epoch,
  input logic [127:0] nonce,
  input logic [111:0] context_in,
  input logic [3:0] context_len,
  output logic tx_valid,
  input logic tx_ready,
  output noc_pkg::coord_t tx_dest_coord,
  output noc_pkg::msg_type_e tx_msg_type,
  output logic [10:0] tx_control,
  output logic [31:0] tx_payload_data,
  output logic tx_payload_valid,
  input logic tx_payload_ready,
  input logic rx_head_valid,
  input noc_pkg::coord_t rx_src_coord,
  input noc_pkg::msg_type_e rx_msg_type,
  input logic [10:0] rx_control,
  input logic [31:0] rx_payload_data,
  input logic rx_payload_valid,rx_payload_last,rx_abort,
  output logic rx_ready,busy,grant_done,failed,
  output logic [31:0] rejected_count,
  output logic [127:0] outstanding_nonce,
  output logic [3:0] fail_reason             // I-6 fault map (I6_CONTRACT sec. 3), valid with failed: 8 timeout,
);                                           // 9 status != 1, 10 malformed, 11 measurement, 12 tag
  import noc_pkg::*;
  typedef enum logic [3:0] {V_IDLE,V_KSTART,V_KWAIT,V_REQ,V_FILL,V_WAIT,V_CHECK,V_TSTART,V_TWAIT,V_GRANT,V_REVOKE} vs_t;
  vs_t vs;
  logic [79:0] epoch_q;
  logic [255:0] root_q,measurement_q,key,expected_tag;
  logic [111:0] context_q;
  logic [3:0] context_len_q;
  logic [223:0] challenge;
  logic [511:0] incoming;
  logic collecting,bad_header;
  logic [3:0] hdr_status;                    // K-2 status of the RESPONSE being collected
  logic [1:0] busy_retries;
  logic [4:0] count,index;
  int timer;
  logic kd,td,te;
  localparam logic [55:0] TILE03=56'h33305f454c4954;
  assign busy=vs!=V_IDLE;
  // Revocation rules (docs/decisions/P7-INGRESS-REVOCATION-CONTRACT.md sec. 2, Q3/Q5; F2):
  //  - rv_pend latches one request per RISING edge of revoke (a held level is one request); cleared at the REVOKE
  //    request handshake (vs == V_REVOKE && tx_ready); an edge while in V_REVOKE merges into it. Timeout and rx_abort
  //    set it too. cancel = pending, including an edge in this very cycle.
  //  - A request is never withdrawn: once tx_valid is up (V_REQ, V_GRANT, V_REVOKE) it is held to its handshake, and an
  //    accepted challenge always gets its 7 words. Crypto jobs (KDF, tag) are drained, never cut.
  //  - pending wins over completion in V_IDLE (over start), V_KWAIT, V_CHECK, V_TWAIT; it is checked again after the
  //    challenge's last word and after the GRANT handshake (GRANT then REVOKE, same VC and path, stay ordered).
  logic rv_pend, cancel, revoke_q, rev_edge, fault_now;
  assign rev_edge=revoke && !revoke_q;
  assign cancel=rv_pend || rev_edge || fault_now;   // F2: a revoke wins in every active state
  logic timeout_now;
  assign timeout_now=busy && vs!=V_REVOKE && timer>=TIMEOUT_CYCLES;
  assign fault_now=timeout_now || rx_abort;
  assign rx_ready=1;
  assign challenge={16'b0,outstanding_nonce,epoch_q};
  assign tx_valid=vs==V_REQ || vs==V_GRANT || vs==V_REVOKE;
  assign tx_dest_coord=tile_to_coord(TILE_CRYPTO);
  assign tx_msg_type=vs==V_GRANT?MSG_ATTEST_GRANT:vs==V_REVOKE?MSG_ATTEST_REVOKE:MSG_ATTEST_CHALLENGE;
  assign tx_control=vs==V_GRANT?11'h080:0;
  assign tx_payload_valid=vs==V_FILL;
  assign tx_payload_data=challenge[index*32+:32];
  // D (M-F1 rev 7 R7.8.2): KDF (V_KSTART) and tag (V_TSTART) run strictly in sequence and share ONE kmac128.
  logic ka_start,kb_start,ka_len_sel,kb_len_sel,ks_busy,ks_done;
  logic [255:0] ka_key,kb_key,ks_tag;
  logic [5:0] ka_key_len,kb_key_len,ka_msg_len;
  logic [319:0] ka_msg;
  logic [127:0] kb_custom;
  logic [4:0] kb_custom_len;
  logic [519:0] kb_msg;
  logic [6:0] kb_msg_len;
  pq_kmac_share kshare(.clk,.rst_n(!rst),
    .a_start(ka_start),.a_key(ka_key),.a_key_len(ka_key_len),.a_msg(ka_msg),.a_msg_len(ka_msg_len),.a_out_len_sel(ka_len_sel),
    .b_start(kb_start),.b_key(kb_key),.b_key_len(kb_key_len),.b_custom(kb_custom),.b_custom_len(kb_custom_len),
    .b_msg(kb_msg),.b_msg_len(kb_msg_len),.b_out_len_sel(kb_len_sel),.tag_out(ks_tag),.busy(ks_busy),.done(ks_done));
  pq_kdf_xk kdf(.clk,.rst_n(!rst),.start(vs==V_KSTART),.root_secret(root_q),.tile_id(TILE03),
    .epoch(epoch_q),.context_in(context_q),.context_len(context_len_q),.key_len_sel(2'b01),
    .derived_key(key),.derived_key_bytes(),.busy(),.done(kd),
    .xk_start(ka_start),.xk_key(ka_key),.xk_key_len(ka_key_len),.xk_msg(ka_msg),.xk_msg_len(ka_msg_len),
    .xk_out_len_sel(ka_len_sel),.xk_tag(ks_tag),.xk_busy(ks_busy),.xk_done(ks_done));
  pq_attestation_tag_xk tagger(.clk,.rst_n(!rst),.start(vs==V_TSTART),.tile_key(key),.tile_id(TILE03),
    .epoch(epoch_q),.nonce(outstanding_nonce),.measurement(incoming[0+:256]),.tag_len_sel(2'b01),
    .tag(expected_tag),.tag_bytes(),.busy(),.done(td),.err(te),
    .xk_start(kb_start),.xk_key(kb_key),.xk_key_len(kb_key_len),.xk_custom(kb_custom),.xk_custom_len(kb_custom_len),
    .xk_msg(kb_msg),.xk_msg_len(kb_msg_len),.xk_out_len_sel(kb_len_sel),.xk_tag(ks_tag),.xk_busy(ks_busy),.xk_done(ks_done));
  always_ff @(posedge clk) begin
    if(rst) begin
      vs<=V_IDLE;epoch_q<=0;root_q<=0;measurement_q<=0;context_q<=0;context_len_q<=0;
      outstanding_nonce<=0;incoming<=0;collecting<=0;bad_header<=0;count<=0;index<=0;
      timer<=0;grant_done<=0;failed<=0;rejected_count<=0;rv_pend<=0;revoke_q<=0;hdr_status<=0;busy_retries<=0;fail_reason<=0;
    end else begin
      revoke_q<=revoke;
      if(vs==V_REVOKE && tx_ready) rv_pend<=0; else if(cancel) rv_pend<=1;
      grant_done<=0; failed<=0;
      if(busy) timer<=timer+1;
      if(rx_abort) begin collecting<=0;failed<=1;fail_reason<=10;rejected_count<=rejected_count+1;end   // pending via fault_now
      else if(rx_head_valid) begin
        collecting<=vs==V_WAIT;count<=0;incoming<=0;
        bad_header<=rx_src_coord!=tile_to_coord(TILE_CRYPTO) || rx_msg_type!=MSG_ATTEST_RESPONSE;
        hdr_status<=rx_control[10:7];
        if(vs!=V_WAIT) rejected_count<=rejected_count+1;
      end else if(rx_payload_valid && collecting) begin
        if(count<16) incoming[count*32+:32]<=rx_payload_data;
        count<=count+1;
        if(rx_payload_last) begin
          collecting<=0;
          if(count!=15 || bad_header) begin failed<=1;fail_reason<=10;rejected_count<=rejected_count+1;vs<=V_REVOKE;timer<=0;end
          else if(hdr_status==3 && busy_retries!=MAX_BUSY_RETRIES) begin busy_retries<=busy_retries+1;timer<=0;vs<=V_REQ;end   // C-1/C-2 retry
          else if(hdr_status!=1) begin failed<=1;fail_reason<=9;rejected_count<=rejected_count+1;vs<=V_REVOKE;timer<=0;end
          else vs<=V_CHECK;
        end
      end
      case(vs)
        V_IDLE: if(cancel) begin vs<=V_REVOKE;timer<=0;end
          else if(start && context_len<=14) begin
            epoch_q<=epoch;outstanding_nonce<=nonce;root_q<=root_secret;
            context_q<=context_in;context_len_q<=context_len;measurement_q<=approved_measurement;
            timer<=0;busy_retries<=0;vs<=V_KSTART;
          end
        V_KSTART: vs<=V_KWAIT;
        V_KWAIT: if(kd) vs<=cancel?V_REVOKE:V_REQ;
        V_REQ: if(tx_ready) begin index<=0;vs<=V_FILL;end   // never left without the handshake
        V_FILL: if(tx_payload_ready) begin if(index==6) vs<=cancel?V_REVOKE:V_WAIT;else index<=index+1;end
        V_WAIT: if(cancel) begin vs<=V_REVOKE;timer<=0;collecting<=0;end
        V_CHECK: if(cancel) begin vs<=V_REVOKE;timer<=0;end
          else if(!BYPASS_MEASUREMENT && incoming[0+:256]!=measurement_q) begin failed<=1;fail_reason<=11;rejected_count<=rejected_count+1;vs<=V_REVOKE;timer<=0;end
          else vs<=V_TSTART;
        V_TSTART: vs<=V_TWAIT;
        V_TWAIT: if(td) begin
          if(cancel) begin vs<=V_REVOKE;timer<=0;end
          else if(te || (!BYPASS_TAG && expected_tag!=incoming[256+:256])) begin failed<=1;fail_reason<=12;rejected_count<=rejected_count+1;vs<=V_REVOKE;timer<=0;end
          else vs<=V_GRANT;
        end
        V_GRANT: if(tx_ready) begin grant_done<=1;busy_retries<=0;vs<=cancel?V_REVOKE:V_IDLE;timer<=0;end   // held to its handshake
        V_REVOKE: if(tx_ready) begin busy_retries<=0;vs<=V_IDLE;end
        default: ;
      endcase
      if(timeout_now) begin failed<=1;fail_reason<=8;timer<=0;collecting<=0;rejected_count<=rejected_count+1;end   // pending via fault_now; drained
    end
  end
endmodule
