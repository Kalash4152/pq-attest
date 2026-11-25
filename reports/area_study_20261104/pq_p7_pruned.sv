`timescale 1ns/1ps
// Area measurement only (scratch): pq_noc_subsystem_p7 with the debug / statistics outputs left unconnected (the ones a SoC
// does not read: endpoint_response, L2 / ingress / quarantine / peer / memory / endpoint / verifier counters and reasons,
// gate fault counters, memory_last_data). Kept: authorization, attestation status, app handshakes, raw-port ready, fault status.
module pq_p7_pruned import noc_pkg::*; (
 input logic clk,rst,start_attestation,revoke,trusted_clear,
 input logic [79:0] boot_epoch,attest_epoch, input logic [127:0] nonce, input logic [255:0] root_secret,approved_measurement,
 input logic [511:0] directed_keys, input logic [111:0] context_in, input logic [3:0] context_len,
 input logic [511:0] config_data,imem, input logic [6:0] config_len,imem_len,
 input logic [5:0] app_valid,app_payload_valid, output logic [5:0] app_ready,app_payload_ready,
 input coord_t [5:0] app_destination, input msg_type_e [5:0] app_message, input logic [5:0][10:0] app_control,
 input logic [5:0][31:0] app_payload, input logic spoof_raw_valid, input flit_t spoof_raw_flit, output logic spoof_raw_ready,
 output logic [5:0] authorized, output logic rot_busy,grant_done,attestation_failed, output logic [31:0] memory_commits,
 output logic [5:0] app_tx_error, output logic fault_sticky, output logic [31:0] fault_count, output logic [2:0] fault_source,
 output logic [3:0] fault_operation,fault_reason, output logic [79:0] fault_epoch);
 pq_noc_subsystem_p7 dut(.clk,.rst,.start_attestation,.revoke,.trusted_clear,.boot_epoch,.attest_epoch,.nonce,.root_secret,
  .approved_measurement,.directed_keys,.context_in,.context_len,.config_data,.imem,.config_len,.imem_len,.app_valid,
  .app_payload_valid,.app_ready,.app_payload_ready,.app_destination,.app_message,.app_control,.app_payload,.spoof_raw_valid,
  .spoof_raw_flit,.spoof_raw_ready,.authorized,.rot_busy,.grant_done,.attestation_failed,.memory_commits,.app_tx_error,
  .fault_sticky,.fault_count,.fault_source,.fault_operation,.fault_reason,.fault_epoch);
endmodule
