`timescale 1ns/1ps
// Offline subsystem core. Measured bytes and demo provisioning are trusted inputs.
// No processor, firmware, physical entropy or board pin qualification is implied.
module pq_noc_subsystem #(
 parameter bit BYPASS_MAC=0,BYPASS_SEQUENCE=0,BYPASS_EPOCH=0,
 parameter bit BYPASS_GATE=0,BYPASS_ISSUER=0,BYPASS_REVOKE=0,
 parameter bit BYPASS_MEASUREMENT=0,BYPASS_TAG=0
)(input logic clk,rst,start_attestation,revoke,
 input logic [79:0] boot_epoch,attest_epoch,
 input logic [127:0] nonce,
 input logic [255:0] root_secret,approved_measurement,
 input logic [9215:0] directed_keys,
 input logic [111:0] context_in,
 input logic [3:0] context_len,
 input logic [511:0] config_data,imem,
 input logic [6:0] config_len,imem_len,
 input logic [5:0] app_valid,app_payload_valid,
 output logic [5:0] app_ready,app_payload_ready,
 input noc_pkg::coord_t [5:0] app_destination,
 input noc_pkg::msg_type_e [5:0] app_message,
 input logic [5:0][10:0] app_control,
 input logic [5:0][31:0] app_payload,
 // Explicit rogue transport port on SPOOF; actual NI5 is retained.
 input logic spoof_raw_valid,
 input noc_pkg::flit_t spoof_raw_flit,
 output logic spoof_raw_ready,
 output logic [5:0] authorized,
 output logic rot_busy,grant_done,attestation_failed,
 output logic [775:0] endpoint_response,
 output logic [31:0] memory_commits,memory_last_data,
 output logic [5:0][31:0] l2_rejected,l2_accepted,gate_faults,
 output logic [5:0][3:0] l2_reason,
 output logic [31:0] endpoint_rejected,verifier_rejected
);
 import noc_pkg::*;
 flit_t [5:0] mesh_in,mesh_out,secure_out;
 logic [5:0] mesh_iv,mesh_ir,mesh_ov,mesh_or,secure_valid;
 coord_t [5:0] rxsrc,rxdst,dest;
 msg_type_e [5:0] rxmsg,msg;
 logic [5:0][10:0] rxctl,ctl;
 logic [5:0][4:0] rxlen;
 logic [5:0][31:0] rxdata,pdata;
 logic [5:0] rhv,rpv,rpl,rready,rabort,tvalid,tready,pvalid,pready;
 logic [5:0] sbusy,rbusy;
 logic ertv,ertpv,ertready,ertpready,endpoint_busy,controller_start;
 coord_t ertdest;
 msg_type_e ertmsg;
 logic [10:0] ertctl;
 logic [31:0] ertdata;
 logic vrtv,vrtpv;
 coord_t vrtdest;
 msg_type_e vrtmsg;
 logic [10:0] vrtctl;
 logic [31:0] vrtdata;
 logic [127:0] outstanding_nonce;
 logic mtv,mtpv;
 logic own3_ep,own2_mem;   // F3 TX owners (below)
 coord_t mdest;
 msg_type_e mmsg;
 logic [10:0] mctl;
 logic [31:0] mdata;
 noc_mesh_3x2 #(.LINK_PIPE(1'b1)) mesh(.clk,.rst,
  .tile_in_flit(mesh_in),.tile_in_valid(mesh_iv),.tile_in_ready(mesh_ir),
  .tile_out_flit(mesh_out),.tile_out_valid(mesh_ov),.tile_out_ready(mesh_or));
 always_comb begin
   mesh_in=secure_out; mesh_iv=secure_valid;
   if(spoof_raw_valid) begin mesh_in[5]=spoof_raw_flit;mesh_iv[5]=1;end
 end
 assign spoof_raw_ready=mesh_ir[5];
 for(genvar g=0;g<6;g++) begin: GN
   logic [1535:0] txk,rxk;
   logic g_valid,g_ready;
   logic [3:0] freason;
   for(genvar p=0;p<6;p++) begin: GK
     assign txk[p*256+:256]=directed_keys[(g*6+p)*256+:256];
     assign rxk[p*256+:256]=directed_keys[(p*6+g)*256+:256];
   end
   noc_attest_gate #(.BYPASS_GATE(BYPASS_GATE),.BYPASS_ISSUER(BYPASS_ISSUER),.BYPASS_REVOKE(BYPASS_REVOKE)) gate(
     .clk,.rst,.app_valid(app_valid[g]),.app_msg(app_message[g]),.ni_ready(g_ready),
     .ni_valid(g_valid),.app_ready(app_ready[g]),.authenticated_head(rhv[g]),
     .source(rxsrc[g]),.message_type(rxmsg[g]),.control(rxctl[g]),
     .trusted_fail(1'b0),.trusted_timeout(1'b0),.trusted_clear(1'b0),
     .authorized(authorized[g]),.fault_count(gate_faults[g]),.fault_reason(freason));
   always_comb begin
     tvalid[g]=g_valid && !(g==3 && endpoint_busy) && !(g==2 && mtv); dest[g]=app_destination[g];msg[g]=app_message[g];ctl[g]=app_control[g];
     pvalid[g]=app_payload_valid[g];pdata[g]=app_payload[g];
     g_ready=tready[g] && !(g==3 && endpoint_busy) && !(g==2 && mtv);app_payload_ready[g]=pready[g];rready[g]=1;
     if(g==3 && own3_ep) begin
       tvalid[g]=ertv;dest[g]=ertdest;msg[g]=ertmsg;ctl[g]=ertctl;
       pvalid[g]=ertpv;pdata[g]=ertdata;g_ready=0;app_payload_ready[g]=0;
     end
     if(g==4) begin
       tvalid[g]=vrtv;dest[g]=vrtdest;msg[g]=vrtmsg;ctl[g]=vrtctl;
       pvalid[g]=vrtpv;pdata[g]=vrtdata;g_ready=0;app_payload_ready[g]=0;
     end
     if(g==2 && own2_mem) begin
       tvalid[g]=mtv;dest[g]=mdest;msg[g]=mmsg;ctl[g]=mctl;
       pvalid[g]=mtpv;pdata[g]=mdata;g_ready=0;app_payload_ready[g]=0;
     end
   end
   // NI assertions inside the trusted wrapper bind private local variables.
   noc_l2_auth #(.TILE(g),.BYPASS_MAC(BYPASS_MAC),.BYPASS_SEQUENCE(BYPASS_SEQUENCE),.BYPASS_EPOCH(BYPASS_EPOCH)) boundary(
     .clk,.rst,.boot_epoch,.tx_keys(txk),.rx_keys(rxk),
     .tx_valid(tvalid[g]),.tx_ready(tready[g]),.tx_dest_coord(dest[g]),.tx_msg_type(msg[g]),.tx_control(ctl[g]),
     .tx_payload_data(pdata[g]),.tx_payload_valid(pvalid[g]),.tx_payload_ready(pready[g]),.tx_error(),
     .noc_tx_flit(secure_out[g]),.noc_tx_valid(secure_valid[g]),
     .noc_tx_ready(mesh_ir[g] && !(g==5 && spoof_raw_valid)),
     .noc_rx_flit(mesh_out[g]),.noc_rx_valid(mesh_ov[g]),.noc_rx_ready(mesh_or[g]),
     .rx_src_coord(rxsrc[g]),.rx_dest_coord(rxdst[g]),.rx_msg_type(rxmsg[g]),.rx_control(rxctl[g]),.rx_length(rxlen[g]),
     .rx_head_valid(rhv[g]),.rx_payload_data(rxdata[g]),.rx_payload_valid(rpv[g]),.rx_payload_last(rpl[g]),
     .rx_ready(rready[g]),.rx_abort(rabort[g]),.rejected_count(l2_rejected[g]),.accepted_count(l2_accepted[g]),
     .reject_reason(l2_reason[g]),.tx_busy(sbusy[g]),.rx_busy(rbusy[g]));
 end
 // F3 (Codex audit): TX ownership is packet-atomic. The owner of tile 3's (endpoint vs application) and tile 2's (memory
 // stand-in vs application) wrapper TX changes only while that wrapper's TX is idle and no request is accepted in the
 // same cycle; a new application request is not offered while the other owner is pending.
 always_ff @(posedge clk) begin
   if(rst) begin own3_ep<=0;own2_mem<=0;end
   else begin
     if(!sbusy[3] && !(tvalid[3] && tready[3])) own3_ep<=endpoint_busy;
     if(!sbusy[2] && !(tvalid[2] && tready[2])) own2_mem<=mtv;
   end
 end
 assign ertready=tready[3] && own3_ep;assign ertpready=pready[3] && own3_ep;
 pq_attest_endpoint endpoint(.clk,.rst,.root_secret,.context_in,.context_len,.config_data,.config_len,.imem,.imem_len,
   .rx_src_coord(rxsrc[3]),.rx_msg_type(rxmsg[3]),.rx_length(rxlen[3]),.rx_head_valid(rhv[3]),
   .rx_payload_data(rxdata[3]),.rx_payload_valid(rpv[3]),.rx_payload_last(rpl[3]),.rx_abort(rabort[3]),.rx_ready(),
   .tx_valid(ertv),.tx_ready(ertready),.tx_dest_coord(ertdest),.tx_msg_type(ertmsg),.tx_control(ertctl),
   .tx_payload_data(ertdata),.tx_payload_valid(ertpv),.tx_payload_ready(ertpready),
   .busy(endpoint_busy),.rejected_count(endpoint_rejected),.internal_response(endpoint_response),.controller_start);
 pq_rot_verifier #(.BYPASS_MEASUREMENT(BYPASS_MEASUREMENT),.BYPASS_TAG(BYPASS_TAG)) verifier(
   .clk,.rst,.start(start_attestation),.revoke,.root_secret,.approved_measurement,.epoch(attest_epoch),.nonce,.context_in,.context_len,
   .tx_valid(vrtv),.tx_ready(tready[4]),.tx_dest_coord(vrtdest),.tx_msg_type(vrtmsg),.tx_control(vrtctl),
   .tx_payload_data(vrtdata),.tx_payload_valid(vrtpv),.tx_payload_ready(pready[4]),
   .rx_head_valid(rhv[4]),.rx_src_coord(rxsrc[4]),.rx_msg_type(rxmsg[4]),.rx_control(rxctl[4]),
   .rx_payload_data(rxdata[4]),.rx_payload_valid(rpv[4]),.rx_payload_last(rpl[4]),.rx_abort(rabort[4]),
   .rx_ready(),.busy(rot_busy),.grant_done,.failed(attestation_failed),.rejected_count(verifier_rejected),.outstanding_nonce);
 // Offline 1 KiB memory stand-in; actual Lane-2 memory is outside this release.
 logic [31:0] memory[256];
 logic [31:0] maddr;
 logic [1:0] mc;
 logic mcollect;
 logic [10:0] request_ctl;
 // F4 (Codex audit): the requester's authorization is checked again at the side effect (write commit / read data). A
 // REVOKE head delivered to the requester's gate in the same cycle wins (revocation boundary: no commit in or after
 // the cycle the REVOKE head reaches the gate).
 logic [5:0] rev_now;
 for(genvar g=0;g<6;g++) begin: GR
   assign rev_now[g]=rhv[g] && rxmsg[g]==MSG_ATTEST_REVOKE && rxsrc[g]==tile_to_coord(TILE_ROT);
 end
 function automatic logic src_ok_now(input coord_t c);
   automatic int i=int'(c.y)*3+int'(c.x);
   return c==tile_to_coord(TILE_ROT) || (c.x<3 && c.y<2 && authorized[i] && !rev_now[i]);
 endfunction
 typedef enum logic [1:0] {M_IDLE,M_REPLY,M_DATA} ms_t;
 ms_t ms;
 assign mtv=ms==M_REPLY || ms==M_DATA;
 assign mtpv=ms==M_DATA;
 always_ff @(posedge clk) begin
   if(rst) begin ms<=M_IDLE;mcollect<=0;mc<=0;maddr<=0;request_ctl<=0;mdest<='0;mmsg<=MSG_MEM_WR_RESP;mctl<=0;mdata<=0;memory_commits<=0;memory_last_data<=0;end
   else begin
     if(rhv[2] && ms==M_IDLE) begin
       mcollect<=(rxmsg[2]==MSG_MEM_WR_REQ || rxmsg[2]==MSG_MEM_RD_REQ) &&
          (authorized[int'(rxsrc[2].y)*3+int'(rxsrc[2].x)] || rxsrc[2]==tile_to_coord(TILE_ROT));
       mc<=0;mdest<=rxsrc[2];mmsg<=rxmsg[2]==MSG_MEM_WR_REQ?MSG_MEM_WR_RESP:MSG_MEM_RD_RESP;
       request_ctl<=rxctl[2];mctl<=rxctl[2]&11'h001;
     end
     if(rpv[2] && mcollect) begin
       if(mc==0) maddr<=rxdata[2];mc<=mc+1;
       if(rpl[2]) begin
         logic [31:0] address; logic legal; logic allowed_now;
         address=mc==0?rxdata[2]:maddr;
         legal=address[31:28]==4'h8 && address[27:24]==2 && address[23:10]==0 && address[1:0]==0;
         allowed_now=src_ok_now(mdest);   // F4: authorization at the side-effect point
         mcollect<=0;ms<=M_REPLY;
         if(!legal || !allowed_now) begin mctl<=11'h400|(request_ctl&11'h001);mdata<=0;end
         else if(mmsg==MSG_MEM_WR_RESP) begin
           for(int b=0;b<4;b++) if(request_ctl[7+b]) memory[address[9:2]][b*8+:8]<=rxdata[2][b*8+:8];
           memory_commits<=memory_commits+1;memory_last_data<=rxdata[2];
         end else mdata<=memory[address[9:2]];
       end
     end
     if(ms==M_REPLY && tready[2] && own2_mem) ms<=mmsg==MSG_MEM_RD_RESP?M_DATA:M_IDLE;
     if(ms==M_DATA && pready[2] && own2_mem) ms<=M_IDLE;
     if(rabort[2]) mcollect<=0;
   end
 end
endmodule
