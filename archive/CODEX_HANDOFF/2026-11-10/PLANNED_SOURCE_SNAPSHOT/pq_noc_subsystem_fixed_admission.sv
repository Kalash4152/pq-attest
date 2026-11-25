// EXPERIMENT ONLY: fixed tile-3 admission; no attestation, L2 MAC or dynamic revocation.
`timescale 1ns/1ps
// Research ablation only. Explicit source substitution; never combine with the secure subsystem.
// The I-9 memory front end is retained verbatim; crypto/control protection is removed as documented.
module pq_noc_subsystem_p7 #(
 parameter bit BYPASS_MAC=0,BYPASS_SEQUENCE=0,BYPASS_EPOCH=0,
 parameter bit BYPASS_GATE=0,BYPASS_ISSUER=0,BYPASS_REVOKE=0,
 parameter bit BYPASS_MEASUREMENT=0,BYPASS_TAG=0,
 parameter bit TB_INJECT=0,  // bench-only injector hooks (tb_p7_refuse_grant, tb_i6_gate); 0 everywhere else
 parameter int VERIFIER_TIMEOUT=100000,  // I-6: benches may shorten it; synthesis keeps the default
 // I-9 (M-F1 rev 8). Defaults reproduce the behaviour before I-9.
 parameter int NI_SLOT_TIMEOUT=0,        // sec. 6 (D6): NI slot timeout, every NI; 0 = none
 parameter bit MEM_EXT=0,                // sec. 9: 1 = tile-2 memory front end drives the external BRAM port
 parameter int MEM_ADDR_BITS=10,         // sec. 9: memory window = 2**MEM_ADDR_BITS bytes (10: the 1 KiB stand-in)
 parameter logic [6:0] K3_IMEM_LEN=7'd16, // D2: provisioned IMEM length (64 in the merged build)
 parameter logic [5:0] CPU_TILES=6'b001001 // sec. 4 / D1: tiles whose memory responses are exported on app_rx
)(input logic clk,rst,start_attestation,revoke,
 input logic trusted_clear,                             // I-6 / M-F1 R7.11: trusted (RoT-side) clear of gate faults and fault status
 input logic [79:0] boot_epoch,attest_epoch,
 input logic [127:0] nonce,
 input logic [255:0] root_secret,approved_measurement,
 input logic [511:0] directed_keys,                     // [255:0] K[4->3], [511:256] K[3->4] (R7.3)
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
 output logic [5:0][31:0] l2_rejected,l2_accepted,gate_faults,ingress_rejected,ingress_fault,
 output logic [31:0] q_rejected,q_forwarded,q_discarded,mem_faults,
 output logic [3:0] q_reason,
 output logic [5:0][3:0] l2_reason,ingress_reason,
 output logic [1:0][31:0] p_slot_drops,peer_accepted,peer_replayed,peer_rejected,
 output logic [1:0][15:0] peer_hold_max,
 output logic [5:0] app_tx_error,
 output logic [31:0] endpoint_rejected,verifier_rejected,
 // I-6 fault status (M-F1 R7.11; map: docs/decisions/I6_CONTRACT.md sec. 3)
 output logic fault_sticky,
 output logic [31:0] fault_count,
 output logic [2:0] fault_source,
 output logic [3:0] fault_operation,fault_reason,
 output logic [79:0] fault_epoch,
 // I-9 app_rx (M-F1 rev 8 sec. 4): memory responses (types 1 / 3) to the CPU tiles; always accepted (rready = 1)
 output logic [5:0] app_rx_head_valid,app_rx_data_valid,app_rx_last,app_rx_abort,
 output noc_pkg::coord_t [5:0] app_rx_src,
 output noc_pkg::msg_type_e [5:0] app_rx_msg,
 output logic [5:0][10:0] app_rx_control,
 output logic [5:0][31:0] app_rx_data,
 // I-9 tile-2 BRAM port (sec. 9; used when MEM_EXT = 1): word address, byte enables, read data one cycle after mem_en
 output logic mem_en,
 output logic [3:0] mem_we,
 output logic [MEM_ADDR_BITS-3:0] mem_addr,
 output logic [31:0] mem_wdata,
 input logic [31:0] mem_rdata
);

 import noc_pkg::*;
 logic rst_i;rst_bridge rb(.clk,.rst_in(rst),.rst_out(rst_i));
 flit_t [5:0] mesh_in,mesh_out;
 logic [5:0] mesh_iv,mesh_ir,mesh_ov,mesh_or;
 coord_t [5:0] rxsrc;msg_type_e [5:0] rxmsg;
 logic [5:0][10:0] rxctl;logic[5:0][31:0] rxdata;
 logic [5:0] rhv,rpv,rpl,rabort,rready,tready,pready;
 logic mtv,mtpv;coord_t mdest;msg_type_e mmsg;logic[10:0]mctl;logic[31:0]mdata;
 wire own2_mem=1'b1;
 assign authorized=6'b001000;
 assign rot_busy=0;assign grant_done=0;assign attestation_failed=0;assign endpoint_response=0;
 assign rready='1;
 noc_mesh_3x2 #(.LINK_PIPE(1'b1)) mesh(.clk,.rst(rst_i),.tile_in_flit(mesh_in),.tile_in_valid(mesh_iv),.tile_in_ready(mesh_ir),
    .tile_out_flit(mesh_out),.tile_out_valid(mesh_ov),.tile_out_ready(mesh_or));
 for(genvar g=0;g<6;g++)begin:N
   logic tr,pr,te,tv,rr,hv,pv,pl,ab,rpe,rle;flit_t tf;coord_t src,dst;msg_type_e rm;logic[10:0]rc;logic[31:0]rd;
   assign mesh_in[g]=tf;assign mesh_iv[g]=tv;assign mesh_or[g]=rr;
   assign tready[g]=tr;assign pready[g]=pr;assign app_ready[g]=tr;assign app_payload_ready[g]=pr;assign app_tx_error[g]=te;
   assign rxsrc[g]=src;assign rxmsg[g]=rm;assign rxctl[g]=rc;assign rxdata[g]=rd;
   assign rhv[g]=hv;assign rpv[g]=pv;assign rpl[g]=pl;assign rabort[g]=ab;
   assign app_rx_head_valid[g]=hv && g!=2;
   assign app_rx_data_valid[g]=pv && g!=2;assign app_rx_last[g]=pl && g!=2;assign app_rx_abort[g]=ab && g!=2;
   assign app_rx_src[g]=src;assign app_rx_msg[g]=rm;assign app_rx_control[g]=rc;assign app_rx_data[g]=rd;
   noc_network_interface_p7 #(.CONTROL_ALLOWED(1'b1),.LOCAL_TILE_ID(g),.WD_LIMIT(64),.NI_SLOT_TIMEOUT(NI_SLOT_TIMEOUT)) ni(
      .clk,.rst(rst_i),.tx_valid(g==2?mtv:app_valid[g]),.tx_ready(tr),.tx_auth_preview(),
      .tx_dest_coord(g==2?mdest:app_destination[g]),.tx_msg_type(g==2?mmsg:app_message[g]),
      .tx_control(g==2?mctl:app_control[g]),.tx_payload_data(g==2?mdata:app_payload[g]),
      .tx_payload_valid(g==2?mtpv:app_payload_valid[g]),.tx_payload_ready(pr),.tx_mac_tag('0),.tx_error(te),
      .noc_tx_flit(tf),.noc_tx_valid(tv),.noc_tx_ready(mesh_ir[g]),.noc_rx_flit(mesh_out[g]),.noc_rx_valid(mesh_ov[g]),.noc_rx_ready(rr),
      .rx_src_coord(src),.rx_dest_coord(dst),.rx_msg_type(rm),.rx_control(rc),.rx_length(),.rx_head_valid(hv),
      .rx_payload_data(rd),.rx_payload_valid(pv),.rx_payload_last(pl),.rx_ready(rready[g]),.rx_abort(ab),
      .rx_mac_tag(),.rx_mac_valid(),.rx_protocol_error(rpe),.rx_length_error(rle),.tx_busy(),.rx_busy());
 end
 assign l2_rejected='0;
 assign l2_accepted='0;
 assign gate_faults='0;
 assign ingress_rejected='0;
 assign ingress_fault='0;
 assign q_rejected='0;
 assign q_forwarded='0;
 assign q_discarded='0;
 assign q_reason='0;
 assign l2_reason='0;
 assign ingress_reason='0;
 assign p_slot_drops='0;
 assign peer_accepted='0;
 assign peer_replayed='0;
 assign peer_rejected='0;
 assign peer_hold_max='0;
 assign endpoint_rejected='0;
 assign verifier_rejected='0;
 assign fault_sticky='0;
 assign fault_count='0;
 assign fault_source='0;
 assign fault_operation='0;
 assign fault_reason='0;
 assign fault_epoch='0;
 logic [31:0] memory[256];
 logic [31:0] maddr;
 logic [1:0] mc;
 logic mcollect;
 logic [10:0] request_ctl;
 // Contract sec. 3 (F4, Q2): authorization is evaluated at the side effect with authorized[src] OF THAT CYCLE; the
 // revocation boundary is the first cycle with authorized[src] = 0.
 //  - write: decided in the cycle of the final write-data acceptance; unauthorized -> no commit, mem_faults++, and the
 //    write response is suppressed (the requester's slot retires through its N-8.1 timeout);
 //  - read: rechecked in the cycle the MEM_RD_RESP HEAD is first offered; unauthorized -> the response is suppressed
 //    (never zero-filled), mem_faults++; once the HEAD is accepted the response completes.
 function automatic logic src_ok_now(input coord_t c);
   automatic int i=int'(c.y)*3+int'(c.x);
   return c==tile_to_coord(TILE_ROT) || (c.x<3 && c.y<2 && authorized[i]);
 endfunction
 logic offered;   // the reply HEAD has been offered at least once
 logic m_ev;              // I-6 memory fault event (reason 6 unauthorized, 13 outside the window), registered
 logic [2:0] m_src;
 logic [3:0] m_op,m_reason;
 function automatic logic [2:0] tix(input coord_t c); return 3'(int'(c.y)*3+int'(c.x)); endfunction
 typedef enum logic [1:0] {M_IDLE,M_REPLY,M_DATA,M_RDWAIT} ms_t;   // M_RDWAIT: I-9 BRAM read latency (MEM_EXT only)
 ms_t ms;
 logic rd_gate;   // Q2: a read reply is offered only while the requester is authorized, until its first offer
 assign rd_gate=mmsg!=MSG_MEM_RD_RESP || offered || src_ok_now(mdest);
 assign mtv=(ms==M_REPLY && rd_gate) || ms==M_DATA;
 assign mtpv=ms==M_DATA;
 always_ff @(posedge clk) begin
   if(rst_i) begin ms<=M_IDLE;mcollect<=0;mc<=0;maddr<=0;request_ctl<=0;mdest<='0;mmsg<=MSG_MEM_WR_RESP;mctl<=0;mdata<=0;memory_commits<=0;memory_last_data<=0;mem_faults<=0;offered<=0;m_ev<=0;m_src<=0;m_op<=0;m_reason<=0;end
   else begin
     m_ev<=0;
     if(rhv[2] && ms==M_IDLE) begin
       mcollect<=(rxmsg[2]==MSG_MEM_WR_REQ || rxmsg[2]==MSG_MEM_RD_REQ) &&
          (authorized[int'(rxsrc[2].y)*3+int'(rxsrc[2].x)] || rxsrc[2]==tile_to_coord(TILE_ROT));
       mc<=0;mdest<=rxsrc[2];mmsg<=rxmsg[2]==MSG_MEM_WR_REQ?MSG_MEM_WR_RESP:MSG_MEM_RD_RESP;
       request_ctl<=rxctl[2];mctl<=rxctl[2]&11'h001;
       if((rxmsg[2]==MSG_MEM_WR_REQ || rxmsg[2]==MSG_MEM_RD_REQ) &&
          !(authorized[int'(rxsrc[2].y)*3+int'(rxsrc[2].x)] || rxsrc[2]==tile_to_coord(TILE_ROT))) begin
         m_ev<=1;m_src<=tix(rxsrc[2]);m_op<=4'(rxmsg[2]);m_reason<=6;   // dropped at the HEAD
       end
     end
     if(rpv[2] && mcollect) begin
       if(mc==0) maddr<=rxdata[2];mc<=mc+1;
       if(rpl[2]) begin
         logic [31:0] address; logic legal; logic allowed_now;
         address=mc==0?rxdata[2]:maddr;
         legal=address[31:28]==4'h2 && address[27:24]==2 && (address[23:0]>>MEM_ADDR_BITS)==0 && address[1:0]==0;   // C-5 (I-6): 0x2T00_0000; I-9 window size
         allowed_now=src_ok_now(mdest);   // F4: authorization at the side-effect point
         mcollect<=0;ms<=M_REPLY;offered<=0;
         m_src<=tix(mdest);m_op<=mmsg==MSG_MEM_WR_RESP?4'(MSG_MEM_WR_REQ):4'(MSG_MEM_RD_REQ);
         if(mmsg==MSG_MEM_WR_RESP && !allowed_now) begin ms<=M_IDLE;mem_faults<=mem_faults+1;m_ev<=1;m_reason<=6;end   // no commit, response suppressed
         else if(!legal) begin mctl<=11'h400|(request_ctl&11'h001);mdata<=0;m_ev<=1;m_reason<=13;end
         else if(mmsg==MSG_MEM_WR_RESP) begin
           if(!MEM_EXT) for(int b=0;b<4;b++) if(request_ctl[7+b]) memory[address[9:2]][b*8+:8]<=rxdata[2][b*8+:8];
           memory_commits<=memory_commits+1;memory_last_data<=rxdata[2];
         end else if(MEM_EXT) ms<=M_RDWAIT;   // I-9: the BRAM read was issued this cycle (mem_en below)
         else mdata<=memory[address[9:2]];
       end
     end
     if(ms==M_REPLY && !rd_gate) begin ms<=M_IDLE;mem_faults<=mem_faults+1;   // Q2: revoked before the first offer -> suppressed
       m_ev<=1;m_src<=tix(mdest);m_op<=4'(MSG_MEM_RD_REQ);m_reason<=6;end
     else if(ms==M_REPLY && own2_mem) begin
       offered<=1;                                                            // valid now held to its handshake
       if(tready[2]) ms<=mmsg==MSG_MEM_RD_RESP?M_DATA:M_IDLE;
     end
     if(ms==M_DATA && pready[2] && own2_mem) ms<=M_IDLE;
     if(ms==M_RDWAIT) begin mdata<=mem_rdata;ms<=M_REPLY;end   // I-9: BRAM data, then the reply as before (Q2 at its offer)
     if(rabort[2]) mcollect<=0;
   end
 end
 // I-9 BRAM port (M-F1 rev 8 sec. 9): issued in the cycle of the final request word, with the same legality and F4
 // decision as the internal array (a write only when legal and authorized now; a read only when legal). Nothing else
 // reaches the BRAM.
 always_comb begin
   logic [31:0] a_now;
   a_now=mc==0?rxdata[2]:maddr;
   mem_en=1'b0; mem_we='0; mem_addr=a_now[MEM_ADDR_BITS-1:2]; mem_wdata=rxdata[2];
   if(MEM_EXT && rpv[2] && mcollect && rpl[2] && a_now[31:28]==4'h2 && a_now[27:24]==2 && (a_now[23:0]>>MEM_ADDR_BITS)==0 &&
      a_now[1:0]==0 && (mmsg==MSG_MEM_RD_RESP || src_ok_now(mdest))) begin
     mem_en=1'b1; if(mmsg==MSG_MEM_WR_RESP) mem_we=request_ctl[10:7];
   end
 end

endmodule
