`timescale 1ns/1ps
module noc_attest_gate #(
 parameter bit BYPASS_GATE=0,BYPASS_ISSUER=0,BYPASS_REVOKE=0,
 parameter bit ATTESTABLE=1,  // M-F1 R7.4: 0 at the non-attested P7 tiles 0, 1, 2, 5 (authorized tied 0; fault 5)
 parameter int TILE=0         // I-6: this gate's tile index (fault_source of a local fault)
)(input logic clk,rst,
  input logic app_valid,
  input noc_pkg::msg_type_e app_msg,
  input logic ni_ready,
  output logic ni_valid,app_ready,
  input logic authenticated_head,
  input noc_pkg::coord_t source,
  input noc_pkg::msg_type_e message_type,
  input logic [10:0] control,
  input logic trusted_fail,trusted_timeout,trusted_clear,
  output logic authorized,
  output logic [31:0] fault_count,
  output logic [3:0] fault_reason,
  // I-6 fault-status feed: one-cycle pulse registered with fault_reason; source = tile index (packet source for
  // GRANT / REVOKE faults, else TILE); operation = message type
  output logic fault_event,
  output logic [2:0] fault_source,
  output logic [3:0] fault_operation);
  import noc_pkg::*;
  logic allowed,issuer;
  logic [2:0] src_index;
  assign src_index=3'(int'(source.y)*3+int'(source.x));
  assign issuer=BYPASS_ISSUER || source==tile_to_coord(TILE_ROT);
  assign allowed=BYPASS_GATE || authorized || app_msg>=MSG_ATTEST_CHALLENGE;
  assign ni_valid=app_valid && allowed;
  assign app_ready=ni_ready && allowed;
  always_ff @(posedge clk) begin
    if(rst) begin authorized<=0;fault_count<=0;fault_reason<=0;fault_event<=0;fault_source<=0;fault_operation<=0;end
    else begin
      fault_event<=0;
      if(trusted_clear) begin fault_count<=0;fault_reason<=0;end
      if(app_valid && !allowed) begin fault_count<=fault_count+1;fault_reason<=1;
        fault_event<=1;fault_source<=3'(TILE);fault_operation<=4'(app_msg);end
      if(trusted_fail || trusted_timeout) begin authorized<=0;fault_count<=fault_count+1;fault_reason<=4;
        fault_event<=1;fault_source<=3'(TILE);fault_operation<=4'(MSG_ATTEST_RESPONSE);end
      if(authenticated_head && (message_type==MSG_ATTEST_GRANT || message_type==MSG_ATTEST_REVOKE)) begin
        if(!ATTESTABLE) begin fault_count<=fault_count+1;fault_reason<=5;   // unreachable: the P7 NI drops it (reason 8)
          fault_event<=1;fault_source<=src_index;fault_operation<=4'(message_type);end
        else if(!issuer) begin fault_count<=fault_count+1;fault_reason<=2;
          fault_event<=1;fault_source<=src_index;fault_operation<=4'(message_type);end
        else if(message_type==MSG_ATTEST_REVOKE) begin if(!BYPASS_REVOKE) authorized<=0;end
        else if(control[10:7]==1) authorized<=1;
        else begin authorized<=0;fault_count<=fault_count+1;fault_reason<=3;
          fault_event<=1;fault_source<=src_index;fault_operation<=4'(message_type);end
      end
    end
  end
  // R7.4: a non-attested tile is never authorized
  // synthesis translate_off
  always_ff @(posedge clk) if(!rst && !ATTESTABLE && authenticated_head && (message_type==MSG_ATTEST_GRANT || message_type==MSG_ATTEST_REVOKE))
    $error("noc_attest_gate: fault 5, GRANT/REVOKE delivered at a gate built ATTESTABLE = 0");
  // synthesis translate_on
endmodule
