module noc_fault_status(input logic clk,rst,event_valid,trusted_clear,
 input logic [2:0] source, input logic [3:0] operation,reason,
 input logic [79:0] epoch, input logic [63:0] timestamp,
 output logic sticky,output logic [31:0] count,
 output logic [2:0] last_source,output logic [3:0] last_operation,last_reason,
 output logic [79:0] last_epoch,output logic [63:0] last_timestamp);
 always_ff @(posedge clk) begin
  if(rst || trusted_clear) begin sticky<=0;count<=0;last_source<=0;last_operation<=0;last_reason<=0;last_epoch<=0;last_timestamp<=0;end
  else if(event_valid) begin sticky<=1;if(count!=32'hffffffff) count<=count+1;
   last_source<=source;last_operation<=operation;last_reason<=reason;last_epoch<=epoch;last_timestamp<=timestamp;end
 end
endmodule
