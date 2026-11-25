// SKELETON (UNCOMPILED when written, 19 Nov 2026). Stage S3 completes, lints and tests it.
// Field positions: 02_INTERFACES_v2.md section 1. TXN_TAG_WIDTH must be 1.
package titan_pkg;
  import noc_pkg::*;

  localparam int EPOCH_W_MAX = 6;               // control[6:1]

  typedef enum logic [2:0] {
    MODE_B0 = 3'd0, MODE_B1_DENY = 3'd1, MODE_B2_DRAIN = 3'd2,
    MODE_B3_RDFILT = 3'd3, MODE_B4_EPOCH = 3'd4, MODE_TITAN = 3'd5
  } titan_mode_e;

  typedef enum logic [2:0] {
    ST_ERROR = 3'b000, ST_DENIED_UNAUTH = 3'b001, ST_DENIED_STALE = 3'b010,
    ST_DENIED_HEAD = 3'b011, ST_DENIED_FILTER = 3'b100          // FILTER: local only
  } titan_status_e;

  typedef enum logic [1:0] {
    OUT_SUCCESS = 2'b00, OUT_DENIED = 2'b01, OUT_ERROR = 2'b10, OUT_UNKNOWN = 2'b11
  } outcome_e;

  function automatic logic [EPOCH_W_MAX-1:0] get_epoch(input logic [10:0] ctl);
    return ctl[6:1];
  endfunction

  function automatic logic [10:0] set_epoch(input logic [10:0] ctl, input logic [EPOCH_W_MAX-1:0] e);
    logic [10:0] r; r = ctl; r[6:1] = e; return r;
  endfunction

  function automatic logic [10:0] mk_resp_ctl(input logic err, input titan_status_e st,
                                              input logic [EPOCH_W_MAX-1:0] echo, input logic tag);
    return {err, (err ? st : ST_ERROR), echo, tag};
  endfunction

  function automatic titan_status_e resp_status(input logic [10:0] ctl);
    return titan_status_e'(ctl[9:7]);
  endfunction

  function automatic logic is_denied(input logic [10:0] ctl);
    return ctl[10] && (ctl[9:7] inside {3'b001, 3'b010, 3'b011, 3'b100});
  endfunction

  function automatic logic is_mem_req(input msg_type_e m);
    return (m == MSG_MEM_RD_REQ) || (m == MSG_MEM_WR_REQ);
  endfunction
endpackage
